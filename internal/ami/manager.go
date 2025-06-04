package ami

import (
    "bufio"
    "context"
    "fmt"
    "net"
    "strconv"
    "strings"
    "sync"
    "sync/atomic"
    "time"
    
    "github.com/hamzaKhattat/asterisk-ara-router/production/pkg/logger"
    "github.com/hamzaKhattat/asterisk-ara-router/production/pkg/errors"
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
    logger.WithField("addr", addr).Info("Connecting to Asterisk AMI")
    
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
    
    // Start event reader
    m.wg.Add(1)
    go m.eventReader()
    
    // Login
    if err := m.login(ctx); err != nil {
        m.disconnect()
        return err
    }
    
    // Start ping loop
    m.wg.Add(1)
    go m.pingLoop()
    
    // Start reconnect handler
    m.wg.Add(1)
    go m.reconnectHandler()
    
    logger.Info("Connected to Asterisk AMI successfully")
    
    return nil
}

// Close gracefully shuts down the AMI connection
func (m *Manager) Close() {
    m.mu.Lock()
    defer m.mu.Unlock()
    
    if !m.connected {
        return
    }
    
    close(m.shutdown)
    
    if m.conn != nil {
        m.conn.Close()
    }
    
    m.connected = false
    m.loggedIn = false
    
    // Wait for goroutines to finish
    m.wg.Wait()
    
    logger.Info("AMI connection closed")
}

// login authenticates with AMI
func (m *Manager) login(ctx context.Context) error {
    action := Action{
        Action: "Login",
        Fields: map[string]string{
            "Username": m.config.Username,
            "Secret":   m.config.Password,
            "Events":   "on",
        },
    }
    
    response, err := m.sendActionSync(ctx, action)
    if err != nil {
        return errors.Wrap(err, errors.ErrAuthFailed, "AMI login failed")
    }
    
    if response["Response"] != "Success" {
        return errors.New(errors.ErrAuthFailed, fmt.Sprintf("AMI login rejected: %s", response["Message"]))
    }
    
    m.mu.Lock()
    m.loggedIn = true
    m.mu.Unlock()
    
    logger.Info("Successfully logged in to AMI")
    
    return nil
}

// SendAction sends an AMI action and returns response
func (m *Manager) SendAction(action Action) (Event, error) {
    ctx, cancel := context.WithTimeout(context.Background(), m.config.ActionTimeout)
    defer cancel()
    
    return m.sendActionSync(ctx, action)
}

// SendActionContext sends an AMI action with context
func (m *Manager) SendActionContext(ctx context.Context, action Action) (Event, error) {
    return m.sendActionSync(ctx, action)
}

// sendActionSync sends action and waits for response
func (m *Manager) sendActionSync(ctx context.Context, action Action) (Event, error) {
    m.mu.RLock()
    if !m.connected || !m.loggedIn {
        m.mu.RUnlock()
        return nil, errors.New(errors.ErrInternal, "not connected to AMI")
    }
    m.mu.RUnlock()
    
    // Generate action ID
    actionID := strconv.FormatUint(atomic.AddUint64(&m.actionID, 1), 10)
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
    
    if _, err := m.writer.WriteString(actionStr); err != nil {
        atomic.AddUint64(&m.failedActions, 1)
        return nil, errors.Wrap(err, errors.ErrInternal, "failed to write AMI action")
    }
    
    if err := m.writer.Flush(); err != nil {
        atomic.AddUint64(&m.failedActions, 1)
        return nil, errors.Wrap(err, errors.ErrInternal, "failed to flush AMI action")
    }
    
    atomic.AddUint64(&m.totalActions, 1)
    
    // Wait for response
    select {
    case response := <-responseChan:
        return response, nil
    case <-ctx.Done():
        atomic.AddUint64(&m.failedActions, 1)
        return nil, errors.New(errors.ErrAGITimeout, "AMI action timeout")
    }
}

// RegisterHandler registers an event handler
func (m *Manager) RegisterHandler(eventType string, handler EventHandler) {
    m.mu.Lock()
    defer m.mu.Unlock()
    
    m.eventHandlers[eventType] = append(m.eventHandlers[eventType], handler)
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
                    logger.WithError(err).Error("Failed to read AMI event")
                }
                
                m.mu.Lock()
                m.connected = false
                m.loggedIn = false
                m.mu.Unlock()
                
                // Trigger reconnect
                select {
                case m.reconnectChan <- struct{}{}:
                default:
                }
                
                return
            }
            
            if event != nil {
                atomic.AddUint64(&m.totalEvents, 1)
                m.processEvent(event)
            }
        }
    }
}

// readEvent reads a single event from AMI
func (m *Manager) readEvent() (Event, error) {
    event := make(Event)
    
    for {
        line, err := m.reader.ReadString('\n')
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

// processEvent processes an incoming event
func (m *Manager) processEvent(event Event) {
    // Check if this is a response to an action
    if actionID, ok := event["ActionID"]; ok {
        m.actionMutex.Lock()
        if responseChan, exists := m.pendingActions[actionID]; exists {
            select {
            case responseChan <- event:
            default:
            }
        }
        m.actionMutex.Unlock()
    }
    
    // Dispatch to event handlers
    eventType := event["Event"]
    if eventType != "" {
        m.mu.RLock()
        handlers := m.eventHandlers[eventType]
        m.mu.RUnlock()
        
        for _, handler := range handlers {
            go handler(event)
        }
    }
    
    // Send to event channel
    select {
    case m.eventChan <- event:
    default:
        logger.Warn("AMI event channel full, dropping event")
    }
}

// pingLoop sends periodic pings to keep connection alive
func (m *Manager) pingLoop() {
    defer m.wg.Done()
    
    ticker := time.NewTicker(m.config.PingInterval)
    defer ticker.Stop()
    
    for {
        select {
        case <-m.shutdown:
            return
        case <-ticker.C:
            m.mu.RLock()
            connected := m.connected && m.loggedIn
            m.mu.RUnlock()
            
            if connected {
                action := Action{Action: "Ping"}
                if _, err := m.SendAction(action); err != nil {
                    logger.WithError(err).Warn("AMI ping failed")
                }
            }
        }
    }
}

// reconnectHandler handles automatic reconnection
func (m *Manager) reconnectHandler() {
    defer m.wg.Done()
    
    for {
        select {
        case <-m.shutdown:
            return
        case <-m.reconnectChan:
            m.handleReconnect()
        }
    }
}

// handleReconnect attempts to reconnect to AMI
func (m *Manager) handleReconnect() {
    for {
        select {
        case <-m.shutdown:
            return
        default:
            logger.Info("Attempting to reconnect to AMI")
            
            ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
            err := m.Connect(ctx)
            cancel()
            
            if err == nil {
                logger.Info("Successfully reconnected to AMI")
                return
            }
            
            logger.WithError(err).Warn("Failed to reconnect to AMI, retrying...")
            
            select {
            case <-m.shutdown:
                return
            case <-time.After(m.config.ReconnectInterval):
                continue
            }
        }
    }
}

// disconnect closes the connection
func (m *Manager) disconnect() {
    if m.conn != nil {
        m.conn.Close()
    }
    m.connected = false
    m.loggedIn = false
}

// GetEventChannel returns the event channel
func (m *Manager) GetEventChannel() <-chan Event {
    return m.eventChan
}

// IsConnected returns true if connected and logged in
func (m *Manager) IsConnected() bool {
    m.mu.RLock()
    defer m.mu.RUnlock()
    return m.connected && m.loggedIn
}

// GetStats returns manager statistics
func (m *Manager) GetStats() map[string]uint64 {
    return map[string]uint64{
        "total_events":   atomic.LoadUint64(&m.totalEvents),
        "total_actions":  atomic.LoadUint64(&m.totalActions),
        "failed_actions": atomic.LoadUint64(&m.failedActions),
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
        return errors.New(errors.ErrInternal, fmt.Sprintf("PJSIP reload failed: %s", response["Message"]))
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
        return errors.New(errors.ErrInternal, fmt.Sprintf("Dialplan reload failed: %s", response["Message"]))
    }
    
    logger.Info("Dialplan reloaded")
    return nil
}

// ShowChannels returns active channels
func (m *Manager) ShowChannels() ([]Event, error) {
    action := Action{
        Action: "CoreShowChannels",
    }
    
    response, err := m.SendAction(action)
    if err != nil {
        return nil, err
    }
    
    if response["Response"] != "Success" {
        return nil, errors.New(errors.ErrInternal, fmt.Sprintf("Failed to get channels: %s", response["Message"]))
    }
    
    var channels []Event
    actionID := response["ActionID"]
    
    // Register temporary handler for channel events
    eventChan := make(chan Event, 100)
    handler := func(event Event) {
        if event["ActionID"] == actionID {
            eventChan <- event
        }
    }
    
    m.RegisterHandler("CoreShowChannel", handler)
    m.RegisterHandler("CoreShowChannelsComplete", handler)
    
    // Collect channel events
    timeout := time.After(5 * time.Second)
    
    for {
        select {
        case event := <-eventChan:
            if event["Event"] == "CoreShowChannel" {
                channels = append(channels, event)
            } else if event["Event"] == "CoreShowChannelsComplete" {
                return channels, nil
            }
        case <-timeout:
            return channels, nil
        }
    }
}

// HangupChannel hangs up a specific channel
func (m *Manager) HangupChannel(channel string, cause int) error {
    action := Action{
        Action: "Hangup",
        Fields: map[string]string{
            "Channel": channel,
            "Cause":   strconv.Itoa(cause),
        },
    }
    
    response, err := m.SendAction(action)
    if err != nil {
        return err
    }
    
    if response["Response"] != "Success" {
        return errors.New(errors.ErrInternal, fmt.Sprintf("Failed to hangup channel: %s", response["Message"]))
    }
    
    return nil
}

// OriginateCall originates a new call
func (m *Manager) OriginateCall(channel, exten, context, callerID string, timeout int, variables map[string]string) (string, error) {
    fields := map[string]string{
        "Channel":  channel,
        "Exten":    exten,
        "Context":  context,
        "Priority": "1",
        "Timeout":  strconv.Itoa(timeout * 1000), // Convert to milliseconds
        "Async":    "true",
    }
    
    if callerID != "" {
        fields["CallerID"] = callerID
    }
    
    // Add variables
    for key, value := range variables {
        fields[fmt.Sprintf("Variable_%s", key)] = value
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
        return "", errors.New(errors.ErrInternal, fmt.Sprintf("Failed to originate call: %s", response["Message"]))
    }
    
    return response["ActionID"], nil
}

// GetChannelVar gets a channel variable
func (m *Manager) GetChannelVar(channel, variable string) (string, error) {
    action := Action{
        Action: "GetVar",
        Fields: map[string]string{
            "Channel":  channel,
            "Variable": variable,
        },
    }
    
    response, err := m.SendAction(action)
    if err != nil {
        return "", err
    }
    
    if response["Response"] != "Success" {
        return "", errors.New(errors.ErrInternal, fmt.Sprintf("Failed to get variable: %s", response["Message"]))
    }
    
    return response["Value"], nil
}

// SetChannelVar sets a channel variable
func (m *Manager) SetChannelVar(channel, variable, value string) error {
    action := Action{
        Action: "SetVar",
        Fields: map[string]string{
            "Channel":  channel,
            "Variable": variable,
            "Value":    value,
        },
    }
    
    response, err := m.SendAction(action)
    if err != nil {
        return err
    }
    
    if response["Response"] != "Success" {
        return errors.New(errors.ErrInternal, fmt.Sprintf("Failed to set variable: %s", response["Message"]))
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
        return nil, errors.New(errors.ErrInternal, fmt.Sprintf("Failed to get queue status: %s", response["Message"]))
    }
    
    var events []Event
    actionID := response["ActionID"]
    
    // Collect queue events
    timeout := time.After(5 * time.Second)
    
    for {
        select {
        case event := <-m.eventChan:
            if event["ActionID"] == actionID {
                if event["Event"] == "QueueStatusComplete" {
                    return events, nil
                }
                events = append(events, event)
            }
        case <-timeout:
            return events, nil
        }
    }
}

// DBGet gets a value from Asterisk database
func (m *Manager) DBGet(family, key string) (string, error) {
    action := Action{
        Action: "DBGet",
        Fields: map[string]string{
            "Family": family,
            "Key":    key,
        },
    }
    
    response, err := m.SendAction(action)
    if err != nil {
        return "", err
    }
    
    if response["Response"] != "Success" {
        return "", errors.New(errors.ErrInternal, fmt.Sprintf("Failed to get DB value: %s", response["Message"]))
    }
    
    return response["Val"], nil
}

// DBPut sets a value in Asterisk database
func (m *Manager) DBPut(family, key, value string) error {
    action := Action{
        Action: "DBPut",
        Fields: map[string]string{
            "Family": family,
            "Key":    key,
            "Val":    value,
        },
    }
    
    response, err := m.SendAction(action)
    if err != nil {
        return err
    }
    
    if response["Response"] != "Success" {
        return errors.New(errors.ErrInternal, fmt.Sprintf("Failed to put DB value: %s", response["Message"]))
    }
    
    return nil
}

// DBDel deletes a value from Asterisk database
func (m *Manager) DBDel(family, key string) error {
    action := Action{
        Action: "DBDel",
        Fields: map[string]string{
            "Family": family,
            "Key":    key,
        },
    }
    
    response, err := m.SendAction(action)
    if err != nil {
        return err
    }
    
    if response["Response"] != "Success" {
        return errors.New(errors.ErrInternal, fmt.Sprintf("Failed to delete DB value: %s", response["Message"]))
    }
    
    return nil
}
