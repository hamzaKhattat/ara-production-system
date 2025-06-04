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
    
    // Login
    if err := m.login(); err != nil {
        m.Close()
        return err
    }
    
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
    if !m.connected || !m.loggedIn {
        m.mu.RUnlock()
        return nil, errors.New(errors.ErrInternal, "not connected to AMI")
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
        return nil, errors.Wrap(err, errors.ErrInternal, "failed to write AMI action")
    }
    
    if err := m.writer.Flush(); err != nil {
        return nil, errors.Wrap(err, errors.ErrInternal, "failed to flush AMI action")
    }
    
    atomic.AddUint64(&m.totalActions, 1)
    
    // Wait for response
    select {
    case response := <-responseChan:
        return response, nil
    case <-time.After(m.config.ActionTimeout):
        atomic.AddUint64(&m.failedActions, 1)
        return nil, errors.New(errors.ErrAGITimeout, "AMI action timeout")
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
                    logger.WithField("error", err.Error()).Error("Failed to read AMI event")
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
            }
        }
    }
}

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
                logger.WithField("error", err.Error()).Warn("AMI ping failed")
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
            
            // Try to reconnect
            ctx := context.Background()
            if err := m.Connect(ctx); err != nil {
                logger.WithField("error", err.Error()).Error("AMI reconnection failed")
                
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
    
    // Read channel events
    timeout := time.After(1 * time.Second)
    for {
        select {
        case event := <-m.eventChan:
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
