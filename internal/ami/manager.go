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
    eventChan    chan Event
    eventHandlers map[string][]EventHandler
    
    // Action handling
    actionID     uint64
    pendingActions map[string]chan Event
    actionMutex   sync.Mutex
    
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

// Response represents an AMI response
type Response struct {
    Success  bool
    ActionID string
    Message  string
    Events   []Event
    Error    error
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
        config.ActionTimeout = 10 * time.Second
    }
    if config.BufferSize == 0 {
        config.BufferSize = 1000
    }
    
    return &Manager{
        config:         config,
        eventChan:      make(chan Event, config.BufferSize),
        eventHandlers:  make(map[string][]EventHandler),
        pendingActions: make(map[string]chan Event),
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
    
    dialer := net.Dialer{
        Timeout: 10 * time.Second,
    }
    
    conn, err := dialer.DialContext(ctx, "tcp", addr)
    if err != nil {
        return errors.Wrap(err, errors.ErrInternal, "failed to connect to AMI")
    }
    
    m.conn = conn
    m.reader = bufio.NewReader(conn)
    m.writer = bufio.NewWriter(conn)
    
    // Read banner
    banner, err := m.reader.ReadString('\n')
    if err != nil {
        conn.Close()
        return errors.Wrap(err, errors.ErrInternal, "failed to read AMI banner")
    }
    
    if !strings.Contains(banner, "Asterisk Call Manager") {
        conn.Close()
        return errors.New(errors.ErrInternal, fmt.Sprintf("invalid AMI banner: %s", banner))
    }
    
    m.connected = true
    
    // Unlock before login to avoid deadlock
    m.mu.Unlock()
    
    // Login
    if err := m.login(); err != nil {
        m.Close()
        m.mu.Lock() // Re-acquire lock before returning
        return err
    }
    
    m.mu.Lock() // Re-acquire lock
    
    // Start event reader
    m.wg.Add(1)
    go m.eventReader()
    
    // Start ping loop
    m.wg.Add(1)
    go m.pingLoop()
    
    // Start reconnect handler
    m.wg.Add(1)
    go m.reconnectHandler()
    
    logger.Info("Connected to Asterisk AMI")
    
    return nil
}

// Close closes the AMI connection
func (m *Manager) Close() {
    m.mu.Lock()
    
    if !m.connected {
        m.mu.Unlock()
        return
    }
    
    // Mark as not connected first
    m.connected = false
    m.loggedIn = false
    
    // Close shutdown channel
    select {
    case <-m.shutdown:
        // Already closed
    default:
        close(m.shutdown)
    }
    
    // Close connection
    if m.conn != nil {
        m.conn.Close()
    }
    
    m.mu.Unlock()
    
    // Wait for goroutines with timeout
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

func (m *Manager) login() error {
    action := Action{
        Action: "Login",
        Fields: map[string]string{
            "Username": m.config.Username,
            "Secret":   m.config.Password,
        },
    }
    
    response, err := m.SendAction(action)
    if err != nil {
        return errors.Wrap(err, errors.ErrAuthFailed, "AMI login failed")
    }
    
    if response["Response"] != "Success" {
        return errors.New(errors.ErrAuthFailed, "AMI login rejected")
    }
    
    m.mu.Lock()
    m.loggedIn = true
    m.mu.Unlock()
    
    return nil
}

// SendAction sends an AMI action
func (m *Manager) SendAction(action Action) (Event, error) {
    m.mu.RLock()
    connected := m.connected
    loggedIn := m.loggedIn
    m.mu.RUnlock()
    
    if !connected {
        return nil, errors.New(errors.ErrInternal, "not connected to AMI")
    }
    
    // For non-login actions, check if logged in
    if action.Action != "Login" && !loggedIn {
        return nil, errors.New(errors.ErrInternal, "not logged in to AMI")
    }
    
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
    
    // Build action string
    var lines []string
    lines = append(lines, fmt.Sprintf("Action: %s", action.Action))
    lines = append(lines, fmt.Sprintf("ActionID: %s", actionID))
    
    for key, value := range action.Fields {
        lines = append(lines, fmt.Sprintf("%s: %s", key, value))
    }
    
    lines = append(lines, "")
    
    // Send action
    actionStr := strings.Join(lines, "\r\n")
    
    m.mu.Lock()
    if m.writer == nil {
        m.mu.Unlock()
        return nil, errors.New(errors.ErrInternal, "writer is nil")
    }
    
    _, err := m.writer.WriteString(actionStr)
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
    
    // Wait for response with timeout
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
                
                // Check if this is a response to a pending action
                if actionID, ok := event["ActionID"]; ok {
                    m.actionMutex.Lock()
                    if ch, exists := m.pendingActions[actionID]; exists {
                        select {
                        case ch <- event:
                        default:
                        }
                    }
                    m.actionMutex.Unlock()
                }
                
                // Send to event channel for handlers
                select {
                case m.eventChan <- event:
                case <-time.After(1 * time.Second):
                    logger.Warn("AMI event channel full, dropping event")
                }
                
                // Call registered handlers
                if eventType, ok := event["Event"]; ok {
                    m.handleEvent(eventType, event)
                }
            }
        }
    }
}

func (m *Manager) readEvent() (Event, error) {
    event := make(Event)
    
    m.mu.RLock()
    reader := m.reader
    m.mu.RUnlock()
    
    if reader == nil {
        return nil, errors.New(errors.ErrInternal, "reader is nil")
    }
    
    for {
        line, err := reader.ReadString('\n')
        if err != nil {
            return nil, err
        }
        
        line = strings.TrimSpace(line)
        
        // Empty line indicates end of event
        if line == "" {
            if len(event) > 0 {
                return event, nil
            }
            continue
        }
        
        // Parse key: value
        parts := strings.SplitN(line, ":", 2)
        if len(parts) == 2 {
            key := strings.TrimSpace(parts[0])
            value := strings.TrimSpace(parts[1])
            event[key] = value
        }
    }
}

func (m *Manager) handleEvent(eventType string, event Event) {
    m.mu.RLock()
    handlers := m.eventHandlers[eventType]
    m.mu.RUnlock()
    
    for _, handler := range handlers {
        // Call handler in goroutine to avoid blocking
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

func (m *Manager) pingLoop() {
    defer m.wg.Done()
    
    ticker := time.NewTicker(m.config.PingInterval)
    defer ticker.Stop()
    
    for {
        select {
        case <-m.shutdown:
            return
        case <-ticker.C:
            action := Action{Action: "Ping"}
            if _, err := m.SendAction(action); err != nil {
                logger.Warn("AMI ping failed", "error", err.Error())
            }
        }
    }
}

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
            
            // Wait before reconnecting
            time.Sleep(m.config.ReconnectInterval)
            
            // Check if we should still reconnect
            select {
            case <-m.shutdown:
                return
            default:
            }
            
            // Try to reconnect
            ctx := context.Background()
            if err := m.Connect(ctx); err != nil {
                logger.Error("AMI reconnection failed", "error", err.Error())
                
                // Trigger another reconnect attempt
                select {
                case m.reconnectChan <- struct{}{}:
                default:
                }
            }
        }
    }
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
    
    // Temporarily register handler for channel events
    handlerID := fmt.Sprintf("show_channels_%d", time.Now().UnixNano())
    
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
        // Unregister handlers
        m.UnregisterEventHandler("CoreShowChannel", handlerID)
        m.UnregisterEventHandler("CoreShowChannelsComplete", handlerID)
    }()
    
    // Wait for completion or timeout
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

// RegisterEventHandler registers a handler for specific events
func (m *Manager) RegisterEventHandler(eventType string, handler EventHandler) {
    m.mu.Lock()
    defer m.mu.Unlock()
    
    m.eventHandlers[eventType] = append(m.eventHandlers[eventType], handler)
}

// UnregisterEventHandler removes a specific event handler
func (m *Manager) UnregisterEventHandler(eventType string, handlerID string) {
    m.mu.Lock()
    defer m.mu.Unlock()
    
    // For simplicity, we're clearing all handlers for the event type
    // In a production system, you'd want to track handlers by ID
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

// OriginateCall originates a new call
func (m *Manager) OriginateCall(channel, context, exten, priority string, timeout int, callerID string, variables map[string]string) (string, error) {
    fields := map[string]string{
        "Channel":  channel,
        "Context":  context,
        "Exten":    exten,
        "Priority": priority,
        "Timeout":  fmt.Sprintf("%d", timeout),
    }
    
    if callerID != "" {
        fields["CallerID"] = callerID
    }
    
    // Add variables
    for k, v := range variables {
        fields[fmt.Sprintf("Variable_%s", k)] = v
    }
    
    action := Action{
        Action: "Originate",
        Fields: fields,
    }
    
    response, err := m.SendAction(action)
    if err != nil {
        return "", err
    }
    
    if response["Response"] != "Success" {
        return "", errors.New(errors.ErrInternal, "Originate failed: " + response["Message"])
    }
    
    return response["ActionID"], nil
}

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

// EventChannel returns the event channel for external processing
func (m *Manager) EventChannel() <-chan Event {
    return m.eventChan
}
