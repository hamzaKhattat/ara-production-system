package ami

import (
    "bufio"
    "context"
    "fmt"
    "net"
    "strings"
    "sync"
    "sync/atomic"
    "time"
    
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
    "github.com/hamzaKhattat/ara-production-system/pkg/errors"
)

// Manager handles Asterisk Manager Interface connections
type Manager struct {
    config     Config
    conn       net.Conn
    reader     *bufio.Reader
    writer     *bufio.Writer
    
    mu         sync.RWMutex
    connected  bool
    loggedIn   bool
    
    // Event handling
    eventChan     chan Event
    eventHandlers map[string][]EventHandler
    loginChan     chan Event  // Special channel for login responses
    
    // Action handling
    actionID       uint64
    pendingActions map[string]chan Event
    actionMutex    sync.Mutex
    
    // Connection management
    shutdown      chan struct{}
    reconnectChan chan struct{}
    wg            sync.WaitGroup
    
    // Metrics
    totalEvents   uint64
    totalActions  uint64
    failedActions uint64
}

// Config holds AMI connection configuration
type Config struct {
    Host              string
    Port              int
    Username          string
    Password          string
    ReconnectInterval time.Duration
    PingInterval      time.Duration
    ActionTimeout     time.Duration
    ConnectTimeout    time.Duration
    ReadTimeout       time.Duration
    BufferSize        int
}

// Event represents an AMI event
type Event map[string]string

// EventHandler is a function that handles AMI events
type EventHandler func(event Event)

// Action represents an AMI action
type Action struct {
    Action   string
    ActionID string
    Fields   map[string]string
}

// NewManager creates a new AMI manager
func NewManager(config Config) *Manager {
    // Set defaults
    if config.Port == 0 {
        config.Port = 5038
    }
    if config.ReconnectInterval == 0 {
        config.ReconnectInterval = 5 * time.Second
    }
    if config.PingInterval == 0 {
        config.PingInterval = 30 * time.Second
    }
    if config.ActionTimeout == 0 {
        config.ActionTimeout = 30 * time.Second
    }
    if config.ConnectTimeout == 0 {
        config.ConnectTimeout = 10 * time.Second
    }
    if config.ReadTimeout == 0 {
        config.ReadTimeout = 30 * time.Second
    }
    if config.BufferSize == 0 {
        config.BufferSize = 1000
    }
    
    return &Manager{
        config:         config,
        eventChan:      make(chan Event, config.BufferSize),
        eventHandlers:  make(map[string][]EventHandler),
        pendingActions: make(map[string]chan Event),
        loginChan:      make(chan Event, 10),
        shutdown:       make(chan struct{}),
        reconnectChan:  make(chan struct{}, 1),
    }
}

// Connect establishes connection to AMI
func (m *Manager) Connect(ctx context.Context) error {
    m.mu.Lock()
    defer m.mu.Unlock()
    
    if m.connected {
        return nil
    }
    
    addr := fmt.Sprintf("%s:%d", m.config.Host, m.config.Port)
    logger.Info("Connecting to Asterisk AMI", "addr", addr)
    
    // Connect with timeout
    dialer := net.Dialer{
        Timeout: m.config.ConnectTimeout,
    }
    
    conn, err := dialer.DialContext(ctx, "tcp", addr)
    if err != nil {
        return errors.Wrap(err, errors.ErrInternal, "failed to connect to AMI")
    }
    
    m.conn = conn
    m.reader = bufio.NewReader(conn)
    m.writer = bufio.NewWriter(conn)
    
    // Set read deadline for banner
    conn.SetReadDeadline(time.Now().Add(5 * time.Second))
    
    // Read banner
    banner, err := m.reader.ReadString('\n')
    if err != nil {
        conn.Close()
        return errors.Wrap(err, errors.ErrInternal, "failed to read AMI banner")
    }
    
    // Reset deadline
    conn.SetReadDeadline(time.Time{})
    
    banner = strings.TrimSpace(banner)
    logger.Debug("AMI Banner received", "banner", banner)
    
    if !strings.Contains(banner, "Asterisk Call Manager") {
        conn.Close()
        return errors.New(errors.ErrInternal, fmt.Sprintf("invalid AMI banner: %s", banner))
    }
    
    m.connected = true
    
    // Start event reader
    m.wg.Add(1)
    go m.eventReader()
    
    // Login
    if err := m.performLogin(); err != nil {
        m.connected = false
        m.conn.Close()
        return err
    }
    
    m.loggedIn = true
    
    // Start background goroutines
    m.wg.Add(2)
    go m.pingLoop()
    go m.reconnectHandler()
    
    logger.Info("Connected to Asterisk AMI successfully")
    
    return nil
}

// performLogin handles the login process
func (m *Manager) performLogin() error {
    logger.Debug("Performing AMI login", "username", m.config.Username)
    
    // Build login action
    loginAction := fmt.Sprintf("Action: Login\r\nUsername: %s\r\nSecret: %s\r\n\r\n",
        m.config.Username, m.config.Password)
    
    // Send login
    if _, err := m.writer.WriteString(loginAction); err != nil {
        return errors.Wrap(err, errors.ErrInternal, "failed to send login")
    }
    
    if err := m.writer.Flush(); err != nil {
        return errors.Wrap(err, errors.ErrInternal, "failed to flush login")
    }
    
    // Wait for response
    timeout := time.NewTimer(m.config.ActionTimeout)
    defer timeout.Stop()
    
    for {
        select {
        case event := <-m.loginChan:
            if response, ok := event["Response"]; ok {
                if response == "Success" {
                    logger.Debug("AMI login successful")
                    return nil
                } else if response == "Error" {
                    msg := event["Message"]
                    if msg == "" {
                        msg = "Authentication failed"
                    }
                    return errors.New(errors.ErrAuthFailed, msg)
                }
            }
        case <-timeout.C:
            return errors.New(errors.ErrAGITimeout, "login timeout")
        }
    }
}

// Close closes the AMI connection
func (m *Manager) Close() {
    m.mu.Lock()
    if !m.connected {
        m.mu.Unlock()
        return
    }
    
    m.connected = false
    m.loggedIn = false
    
    // Close shutdown channel
    close(m.shutdown)
    
    // Close connection
    if m.conn != nil {
        m.conn.Close()
    }
    m.mu.Unlock()
    
    // Wait for goroutines
    done := make(chan struct{})
    go func() {
        m.wg.Wait()
        close(done)
    }()
    
    select {
    case <-done:
        logger.Info("AMI manager closed gracefully")
    case <-time.After(5 * time.Second):
        logger.Warn("AMI manager close timeout")
    }
}

// SendAction sends an AMI action
func (m *Manager) SendAction(action Action) (Event, error) {
    m.mu.RLock()
    if !m.connected {
        m.mu.RUnlock()
        return nil, errors.New(errors.ErrInternal, "not connected to AMI")
    }
    if action.Action != "Login" && !m.loggedIn {
        m.mu.RUnlock()
        return nil, errors.New(errors.ErrInternal, "not logged in to AMI")
    }
    m.mu.RUnlock()
    
    // Generate action ID
    actionID := fmt.Sprintf("%d", atomic.AddUint64(&m.actionID, 1))
    action.ActionID = actionID
    
    // Create response channel
    responseChan := make(chan Event, 1)
    
    m.actionMutex.Lock()
    m.pendingActions[actionID] = responseChan
    m.actionMutex.Unlock()
    
    defer func() {
        m.actionMutex.Lock()
        delete(m.pendingActions, actionID)
        m.actionMutex.Unlock()
        close(responseChan)
    }()
    
    // Build action
    var sb strings.Builder
    sb.WriteString(fmt.Sprintf("Action: %s\r\n", action.Action))
    sb.WriteString(fmt.Sprintf("ActionID: %s\r\n", actionID))
    
    for key, value := range action.Fields {
        sb.WriteString(fmt.Sprintf("%s: %s\r\n", key, value))
    }
    sb.WriteString("\r\n")
    
    // Send action
    m.mu.Lock()
    _, err := m.writer.WriteString(sb.String())
    if err != nil {
        m.mu.Unlock()
        return nil, errors.Wrap(err, errors.ErrInternal, "failed to write AMI action")
    }
    
    err = m.writer.Flush()
    m.mu.Unlock()
    
    if err != nil {
        return nil, errors.Wrap(err, errors.ErrInternal, "failed to flush AMI action")
    }
    
    atomic.AddUint64(&m.totalActions, 1)
    
    // Wait for response
    timer := time.NewTimer(m.config.ActionTimeout)
    defer timer.Stop()
    
    select {
    case response := <-responseChan:
        return response, nil
    case <-timer.C:
        atomic.AddUint64(&m.failedActions, 1)
        return nil, errors.New(errors.ErrAGITimeout, "AMI action timeout")
    case <-m.shutdown:
        return nil, errors.New(errors.ErrInternal, "AMI manager shutting down")
    }
}

// eventReader reads events from AMI
func (m *Manager) eventReader() {
    defer m.wg.Done()
    
    for {
        select {
        case <-m.shutdown:
            return
        default:
            event, err := m.readEvent()
            if err != nil {
                if !strings.Contains(err.Error(), "use of closed network connection") {
                    logger.Error("Failed to read AMI event", "error", err.Error())
                }
                
                // Trigger reconnect
                select {
                case m.reconnectChan <- struct{}{}:
                default:
                }
                return
            }
            
            if event != nil {
                atomic.AddUint64(&m.totalEvents, 1)
                
                // Check if this is a login response (no ActionID)
                if response, hasResponse := event["Response"]; hasResponse {
                fmt.Println(response)
                    if _, hasActionID := event["ActionID"]; !hasActionID {
                        // This is a login response
                        select {
                        case m.loginChan <- event:
                        default:
                        }
                        continue
                    }
                }
                
                // Handle action responses
                if actionID, ok := event["ActionID"]; ok && actionID != "" {
                    m.actionMutex.Lock()
                    if ch, exists := m.pendingActions[actionID]; exists {
                        select {
                        case ch <- event:
                        default:
                        }
                    }
                    m.actionMutex.Unlock()
                }
                
                // Send to general event channel
                select {
                case m.eventChan <- event:
                case <-time.After(100 * time.Millisecond):
                    logger.Warn("AMI event channel full, dropping event")
                }
                
                // Handle registered handlers
                if eventType, ok := event["Event"]; ok {
                    m.handleEvent(eventType, event)
                }
            }
        }
    }
}

// readEvent reads a single event from AMI
func (m *Manager) readEvent() (Event, error) {
    event := make(Event)
    
    for {
        // Set read deadline
        if m.config.ReadTimeout > 0 {
            m.conn.SetReadDeadline(time.Now().Add(m.config.ReadTimeout))
        }
        
        line, err := m.reader.ReadString('\n')
        if err != nil {
            return nil, err
        }
        
        line = strings.TrimSpace(line)
        
        // Empty line = end of event
        if line == "" {
            if len(event) > 0 {
                return event, nil
            }
            continue
        }
        
        // Parse key: value
        if idx := strings.Index(line, ":"); idx > 0 {
            key := strings.TrimSpace(line[:idx])
            value := strings.TrimSpace(line[idx+1:])
            event[key] = value
        }
    }
}

// handleEvent calls registered event handlers
func (m *Manager) handleEvent(eventType string, event Event) {
    m.mu.RLock()
    handlers := m.eventHandlers[eventType]
    m.mu.RUnlock()
    
    for _, handler := range handlers {
        go func(h EventHandler) {
            defer func() {
                if r := recover(); r != nil {
                    logger.Error("Event handler panic", "event", eventType, "panic", r)
                }
            }()
            h(event)
        }(handler)
    }
}

// pingLoop sends periodic pings
func (m *Manager) pingLoop() {
    defer m.wg.Done()
    
    ticker := time.NewTicker(m.config.PingInterval)
    defer ticker.Stop()
    
    for {
        select {
        case <-m.shutdown:
            return
        case <-ticker.C:
            if _, err := m.SendAction(Action{Action: "Ping"}); err != nil {
                logger.Warn("AMI ping failed", "error", err.Error())
            }
        }
    }
}

// reconnectHandler handles reconnection
func (m *Manager) reconnectHandler() {
    defer m.wg.Done()
    
    for {
        select {
        case <-m.shutdown:
            return
        case <-m.reconnectChan:
            logger.Info("AMI reconnection triggered")
            
            m.mu.Lock()
            m.connected = false
            m.loggedIn = false
            if m.conn != nil {
                m.conn.Close()
            }
            m.mu.Unlock()
            
            time.Sleep(m.config.ReconnectInterval)
            
            select {
            case <-m.shutdown:
                return
            default:
                ctx := context.Background()
                if err := m.Connect(ctx); err != nil {
                    logger.Error("AMI reconnection failed", "error", err.Error())
                    select {
                    case m.reconnectChan <- struct{}{}:
                    default:
                    }
                }
            }
        }
    }
}

// Helper methods

// IsConnected returns connection status
func (m *Manager) IsConnected() bool {
    m.mu.RLock()
    defer m.mu.RUnlock()
    return m.connected
}

// IsLoggedIn returns login status
func (m *Manager) IsLoggedIn() bool {
    m.mu.RLock()
    defer m.mu.RUnlock()
    return m.loggedIn
}

// RegisterEventHandler registers an event handler
func (m *Manager) RegisterEventHandler(eventType string, handler EventHandler) {
    m.mu.Lock()
    defer m.mu.Unlock()
    m.eventHandlers[eventType] = append(m.eventHandlers[eventType], handler)
}

// UnregisterEventHandler removes event handlers
func (m *Manager) UnregisterEventHandler(eventType string, handlerID string) {
    m.mu.Lock()
    defer m.mu.Unlock()
    delete(m.eventHandlers, eventType)
}

// GetStats returns AMI statistics
func (m *Manager) GetStats() map[string]interface{} {
    return map[string]interface{}{
        "total_events":   atomic.LoadUint64(&m.totalEvents),
        "total_actions":  atomic.LoadUint64(&m.totalActions),
        "failed_actions": atomic.LoadUint64(&m.failedActions),
        "connected":      m.IsConnected(),
        "logged_in":      m.IsLoggedIn(),
    }
}

// EventChannel returns the event channel
func (m *Manager) EventChannel() <-chan Event {
    return m.eventChan
}

// ConnectWithRetry attempts connection with retries
func (m *Manager) ConnectWithRetry(ctx context.Context, maxRetries int) error {
    var lastErr error
    
    for i := 0; i < maxRetries; i++ {
        if i > 0 {
            logger.Info("Retrying AMI connection", "attempt", i+1, "max", maxRetries)
            time.Sleep(m.config.ReconnectInterval)
        }
        
        err := m.Connect(ctx)
        if err == nil {
            return nil
        }
        
        lastErr = err
        logger.Warn("AMI connection attempt failed", "attempt", i+1, "error", err)
    }
    
    return lastErr
}

// ConnectOptional attempts connection without failing
func (m *Manager) ConnectOptional(ctx context.Context) {
    go func() {
        for {
            select {
            case <-ctx.Done():
                return
            default:
                if !m.IsConnected() {
                    if err := m.Connect(ctx); err != nil {
                        logger.Debug("AMI connection failed, will retry", "error", err)
                        time.Sleep(m.config.ReconnectInterval)
                        continue
                    }
                    logger.Info("AMI connected successfully")
                }
                time.Sleep(30 * time.Second)
            }
        }
    }()
}

// ARA-specific commands

// ReloadPJSIP reloads PJSIP configuration
func (m *Manager) ReloadPJSIP() error {
    action := Action{
        Action: "Command",
        Fields: map[string]string{
            "Command": "pjsip reload",
        },
    }
    
    response, err := m.SendAction(action)
    if err != nil {
        return err
    }
    
    if response["Response"] != "Success" {
        return errors.New(errors.ErrInternal, "PJSIP reload failed")
    }
    
    logger.Info("PJSIP configuration reloaded")
    return nil
}

// ReloadDialplan reloads dialplan
func (m *Manager) ReloadDialplan() error {
    action := Action{
        Action: "Command",
        Fields: map[string]string{
            "Command": "dialplan reload",
        },
    }
    
    response, err := m.SendAction(action)
    if err != nil {
        return err
    }
    
    if response["Response"] != "Success" {
        return errors.New(errors.ErrInternal, "Dialplan reload failed")
    }
    
    logger.Info("Dialplan reloaded")
    return nil
}

// ShowChannels returns active channels
func (m *Manager) ShowChannels() ([]map[string]string, error) {
    action := Action{
        Action: "CoreShowChannels",
    }
    
    response, err := m.SendAction(action)
    if err != nil {
        return nil, err
    }
    
    if response["Response"] != "Success" {
        return nil, errors.New(errors.ErrInternal, "Failed to get channels")
    }
    
    var channels []map[string]string
    completeChan := make(chan bool, 1)
    
    handler := func(event Event) {
        if event["Event"] == "CoreShowChannel" {
            channels = append(channels, event)
        } else if event["Event"] == "CoreShowChannelsComplete" {
            select {
            case completeChan <- true:
            default:
            }
        }
    }
    
    m.RegisterEventHandler("CoreShowChannel", handler)
    m.RegisterEventHandler("CoreShowChannelsComplete", handler)
    
    defer func() {
        m.UnregisterEventHandler("CoreShowChannel", "")
        m.UnregisterEventHandler("CoreShowChannelsComplete", "")
    }()
    
    select {
    case <-completeChan:
        return channels, nil
    case <-time.After(5 * time.Second):
        return channels, nil
    }
}

// HangupChannel hangs up a channel
func (m *Manager) HangupChannel(channel string, cause int) error {
    action := Action{
        Action: "Hangup",
        Fields: map[string]string{
            "Channel": channel,
            "Cause":   fmt.Sprintf("%d", cause),
        },
    }
    
    response, err := m.SendAction(action)
    if err != nil {
        return err
    }
    
    if response["Response"] != "Success" {
        return errors.New(errors.ErrInternal, "Failed to hangup channel")
    }
    
    return nil
}

// Additional helper methods for other AMI actions...
// (GetVar, SetVar, OriginateCall, QueueStatus, etc. remain the same)

// GetVar gets a global variable
func (m *Manager) GetVar(variable string) (string, error) {
    action := Action{
        Action: "GetVar",
        Fields: map[string]string{
            "Variable": variable,
        },
    }
    
    response, err := m.SendAction(action)
    if err != nil {
        return "", err
    }
    
    if response["Response"] != "Success" {
        return "", errors.New(errors.ErrInternal, "GetVar failed")
    }
    
    return response["Value"], nil
}

// SetVar sets a global variable
func (m *Manager) SetVar(variable, value string) error {
    action := Action{
        Action: "SetVar",
        Fields: map[string]string{
            "Variable": variable,
            "Value":    value,
        },
    }
    
    response, err := m.SendAction(action)
    if err != nil {
        return err
    }
    
    if response["Response"] != "Success" {
        return errors.New(errors.ErrInternal, "SetVar failed")
    }
    
    return nil
}

// QueueStatus gets queue status
func (m *Manager) QueueStatus(queue string) ([]Event, error) {
    fields := make(map[string]string)
    if queue != "" {
        fields["Queue"] = queue
    }
    
    action := Action{
        Action: "QueueStatus",
        Fields: fields,
    }
    
    response, err := m.SendAction(action)
    if err != nil {
        return nil, err
    }
    
    if response["Response"] != "Success" {
        return nil, errors.New(errors.ErrInternal, "QueueStatus failed")
    }
    
    // Collect queue events
    var events []Event
    timeout := time.After(5 * time.Second)
    
    for {
        select {
        case event := <-m.eventChan:
            eventType := event["Event"]
            if eventType == "QueueParams" || eventType == "QueueMember" || eventType == "QueueEntry" {
                events = append(events, event)
            } else if eventType == "QueueStatusComplete" {
                return events, nil
            }
        case <-timeout:
            return events, nil
        }
    }
}


