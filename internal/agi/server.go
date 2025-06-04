package agi

import (
    "bufio"
    "context"
    "fmt"
    "io"
    "net"
    "strings"
    "sync"
    "sync/atomic"
    "time"
    
    "github.com/hamzaKhattat/ara-production-system/internal/router"
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
    "github.com/hamzaKhattat/ara-production-system/pkg/errors"
)

const (
    AGISuccess = "200 result=1"
    AGIFailure = "200 result=0"
    AGIError   = "510 Invalid or unknown command"
)

type Server struct {
    router  *router.Router
    config  Config
    
    listener     net.Listener
    connections  sync.WaitGroup
    shutdown     chan struct{}
    shuttingDown atomic.Bool
    
    // Connection tracking
    mu          sync.RWMutex
    activeConns map[string]*Session
    connCount   atomic.Int64
    
    // Metrics
    metrics MetricsInterface
}

type Config struct {
    ListenAddress    string
    Port             int
    MaxConnections   int
    ReadTimeout      time.Duration
    WriteTimeout     time.Duration
    IdleTimeout      time.Duration
    ShutdownTimeout  time.Duration
}

type MetricsInterface interface {
    IncrementCounter(name string, labels map[string]string)
    ObserveHistogram(name string, value float64, labels map[string]string)
    SetGauge(name string, value float64, labels map[string]string)
}

type Session struct {
    id         string
    conn       net.Conn
    reader     *bufio.Reader
    writer     *bufio.Writer
    headers    map[string]string
    server     *Server
    startTime  time.Time
    lastActive time.Time
    ctx        context.Context
    cancel     context.CancelFunc
}

func NewServer(router *router.Router, config Config, metrics MetricsInterface) *Server {
    return &Server{
        router:      router,
        config:      config,
        shutdown:    make(chan struct{}),
        activeConns: make(map[string]*Session),
        metrics:     metrics,
    }
}

func (s *Server) Start() error {
    addr := fmt.Sprintf("%s:%d", s.config.ListenAddress, s.config.Port)
    
    listener, err := net.Listen("tcp", addr)
    if err != nil {
        return errors.Wrap(err, errors.ErrInternal, "failed to start AGI server")
    }
    
    s.listener = listener
    logger.Info("AGI server started", "address", addr)
    
    // Start connection monitor
    go s.connectionMonitor()
    
    // Accept connections
    for {
        select {
        case <-s.shutdown:
            return nil
        default:
            // Set accept timeout to check shutdown periodically
            if tcpListener, ok := listener.(*net.TCPListener); ok {
                tcpListener.SetDeadline(time.Now().Add(1 * time.Second))
            }
            
            conn, err := listener.Accept()
            if err != nil {
                if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
                    continue
                }
                if s.shuttingDown.Load() {
                    return nil
                }
                logger.Warn("Failed to accept connection", "error", err.Error())
                continue
            }
            
            // Check connection limit
            if s.config.MaxConnections > 0 && int(s.connCount.Load()) >= s.config.MaxConnections {
                logger.Warn("Connection limit reached, rejecting connection")
                conn.Close()
                s.metrics.IncrementCounter("agi_connections_rejected", map[string]string{
                    "reason": "limit_exceeded",
                })
                continue
            }
            
            s.connections.Add(1)
            s.connCount.Add(1)
            go s.handleConnection(conn)
        }
    }
}

func (s *Server) Stop() error {
    s.shuttingDown.Store(true)
    close(s.shutdown)
    
    if s.listener != nil {
        s.listener.Close()
    }
    
    // Wait for connections to finish with timeout
    done := make(chan struct{})
    go func() {
        s.connections.Wait()
        close(done)
    }()
    
    select {
    case <-done:
        logger.Info("AGI server stopped gracefully")
    case <-time.After(s.config.ShutdownTimeout):
        logger.Warn("AGI server shutdown timeout, forcing close")
        s.forceCloseConnections()
    }
    
    return nil
}

func (s *Server) handleConnection(conn net.Conn) {
    defer func() {
        s.connections.Done()
        s.connCount.Add(-1)
        conn.Close()
    }()
    
    // Create session
    ctx, cancel := context.WithCancel(context.Background())
    session := &Session{
        id:         fmt.Sprintf("%s-%d", conn.RemoteAddr().String(), time.Now().UnixNano()),
        conn:       conn,
        reader:     bufio.NewReader(conn),
        writer:     bufio.NewWriter(conn),
        headers:    make(map[string]string),
        server:     s,
        startTime:  time.Now(),
        lastActive: time.Now(),
        ctx:        ctx,
        cancel:     cancel,
    }
    
    // Track session
    s.mu.Lock()
    s.activeConns[session.id] = session
    s.mu.Unlock()
    
    defer func() {
        s.mu.Lock()
        delete(s.activeConns, session.id)
        s.mu.Unlock()
        cancel()
    }()
    
    // Set initial timeout
    conn.SetDeadline(time.Now().Add(s.config.ReadTimeout))
    
    // Log connection
    logger.Debug("New AGI connection", 
        "session_id", session.id,
        "remote_addr", conn.RemoteAddr().String())
    
    // Update metrics
    s.metrics.IncrementCounter("agi_connections_total", nil)
    s.metrics.SetGauge("agi_connections_active", float64(s.connCount.Load()), nil)
    
    // Handle session
    if err := session.handle(); err != nil {
        if err != io.EOF && !strings.Contains(err.Error(), "use of closed network connection") {
            logger.Warn("Session error", "session_id", session.id, "error", err.Error())
        }
    }
    
    // Log session duration
    duration := time.Since(session.startTime)
    logger.Debug("AGI session completed",
        "session_id", session.id,
        "duration", duration.Seconds())
    
    s.metrics.ObserveHistogram("agi_session_duration", duration.Seconds(), nil)
}

func (session *Session) handle() error {
    // Read AGI headers
    if err := session.readHeaders(); err != nil {
        return errors.Wrap(err, errors.ErrAGIConnection, "failed to read headers")
    }
    
    // Extract request info
    request := session.headers["agi_request"]
    if request == "" {
        return errors.New(errors.ErrAGIInvalidCmd, "no AGI request found")
    }
    
    // Add context values
    session.ctx = context.WithValue(session.ctx, "session_id", session.id)
    session.ctx = context.WithValue(session.ctx, "request_id", session.headers["agi_uniqueid"])
    session.ctx = context.WithValue(session.ctx, "call_id", session.headers["agi_uniqueid"])
    
    // Log request
    log := logger.WithContext(session.ctx)
    log.Info("Processing AGI request",
        "request", request,
        "channel", session.headers["agi_channel"],
        "callerid", session.headers["agi_callerid"],
        "extension", session.headers["agi_extension"])
    
    // Route request
    switch {
    case strings.Contains(request, "processIncoming"):
        return session.handleProcessIncoming()
    case strings.Contains(request, "processReturn"):
        return session.handleProcessReturn()
    case strings.Contains(request, "processFinal"):
        return session.handleProcessFinal()
    case strings.Contains(request, "hangup"):
        return session.handleHangup()
    default:
        log.Warn("Unknown AGI request", "request", request)
        return session.sendResponse(AGIFailure)
    }
}

func (session *Session) readHeaders() error {
    session.updateActivity()
    
    for {
        line, err := session.reader.ReadString('\n')
        if err != nil {
            return err
        }
        
        line = strings.TrimSpace(line)
        
        // Empty line indicates end of headers
        if line == "" {
            break
        }
        
        // Parse header
        parts := strings.SplitN(line, ":", 2)
        if len(parts) == 2 {
            key := strings.TrimSpace(parts[0])
            value := strings.TrimSpace(parts[1])
            session.headers[key] = value
        }
    }
    
    return nil
}

func (session *Session) handleProcessIncoming() error {
    // Extract call information
    callID := session.headers["agi_uniqueid"]
    ani := session.headers["agi_callerid"]
    dnis := session.headers["agi_extension"]
    channel := session.headers["agi_channel"]
    
    // Extract provider from channel
    inboundProvider := session.extractProviderFromChannel(channel)
    
    // Process through router
    startTime := time.Now()
    response, err := session.server.router.ProcessIncomingCall(session.ctx, callID, ani, dnis, inboundProvider)
    processingTime := time.Since(startTime)
    
    // Update metrics
    session.server.metrics.ObserveHistogram("agi_processing_time", processingTime.Seconds(), map[string]string{
        "action": "process_incoming",
    })
    
    if err != nil {
        log := logger.WithContext(session.ctx)
        log.Error("Failed to process incoming call", "error", err.Error())
        session.setVariable("ROUTER_STATUS", "failed")
        session.setVariable("ROUTER_ERROR", err.Error())
        
        errorCode := "UNKNOWN_ERROR"
        if appErr, ok := err.(*errors.AppError); ok {
            errorCode = string(appErr.Code)
        }
        
        session.server.metrics.IncrementCounter("agi_requests_failed", map[string]string{
            "action": "process_incoming",
            "error": errorCode,
        })
        
        return session.sendResponse(AGISuccess)
    }
    
    // Set channel variables for dialplan
    session.setVariable("ROUTER_STATUS", "success")
    session.setVariable("DID_ASSIGNED", response.DIDAssigned)
    session.setVariable("NEXT_HOP", response.NextHop)
    session.setVariable("ANI_TO_SEND", response.ANIToSend)
    session.setVariable("DNIS_TO_SEND", response.DNISToSend)
    session.setVariable("INTERMEDIATE_PROVIDER", strings.TrimPrefix(response.NextHop, "endpoint-"))
    
    session.server.metrics.IncrementCounter("agi_requests_success", map[string]string{
        "action": "process_incoming",
    })
    
    return session.sendResponse(AGISuccess)
}

func (session *Session) handleProcessReturn() error {
    // Extract call information
    ani2 := session.headers["agi_callerid"]
    did := session.headers["agi_extension"]
    channel := session.headers["agi_channel"]
    
    // Get source IP from channel variable
    sourceIP := session.getVariable("SOURCE_IP")
    
    // Extract provider from channel
    intermediateProvider := session.extractProviderFromChannel(channel)
    
    // Process through router
    startTime := time.Now()
    response, err := session.server.router.ProcessReturnCall(session.ctx, ani2, did, intermediateProvider, sourceIP)
    processingTime := time.Since(startTime)
    
    // Update metrics
    session.server.metrics.ObserveHistogram("agi_processing_time", processingTime.Seconds(), map[string]string{
        "action": "process_return",
    })
    
    if err != nil {
        log := logger.WithContext(session.ctx)
        log.Error("Failed to process return call", "error", err.Error())
        session.setVariable("ROUTER_STATUS", "failed")
        session.setVariable("ROUTER_ERROR", err.Error())
        
        errorCode := "UNKNOWN_ERROR"
        if appErr, ok := err.(*errors.AppError); ok {
            errorCode = string(appErr.Code)
        }
        
        session.server.metrics.IncrementCounter("agi_requests_failed", map[string]string{
            "action": "process_return",
            "error": errorCode,
        })
        
        return session.sendResponse(AGISuccess)
    }
    
    // Set channel variables for routing to S4
    session.setVariable("ROUTER_STATUS", "success")
    session.setVariable("NEXT_HOP", response.NextHop)
    session.setVariable("ANI_TO_SEND", response.ANIToSend)
    session.setVariable("DNIS_TO_SEND", response.DNISToSend)
    session.setVariable("FINAL_PROVIDER", strings.TrimPrefix(response.NextHop, "endpoint-"))
    
    session.server.metrics.IncrementCounter("agi_requests_success", map[string]string{
        "action": "process_return",
    })
    
    return session.sendResponse(AGISuccess)
}

func (session *Session) handleProcessFinal() error {
    // Extract call information
    callID := session.headers["agi_uniqueid"]
    ani := session.headers["agi_callerid"]
    dnis := session.headers["agi_extension"]
    channel := session.headers["agi_channel"]
    
    // Get source IP from channel variable
    sourceIP := session.getVariable("SOURCE_IP")
    
    // Extract provider from channel
    finalProvider := session.extractProviderFromChannel(channel)
    
    // Process through router
    startTime := time.Now()
    err := session.server.router.ProcessFinalCall(session.ctx, callID, ani, dnis, finalProvider, sourceIP)
    processingTime := time.Since(startTime)
    
    // Update metrics
    session.server.metrics.ObserveHistogram("agi_processing_time", processingTime.Seconds(), map[string]string{
        "action": "process_final",
    })
    
    if err != nil {
        log := logger.WithContext(session.ctx)
        log.Error("Failed to process final call", "error", err.Error())
        
        errorCode := "UNKNOWN_ERROR"
        if appErr, ok := err.(*errors.AppError); ok {
            errorCode = string(appErr.Code)
        }
        
        session.server.metrics.IncrementCounter("agi_requests_failed", map[string]string{
            "action": "process_final",
            "error": errorCode,
        })
    } else {
        session.server.metrics.IncrementCounter("agi_requests_success", map[string]string{
            "action": "process_final",
        })
    }
    
    return session.sendResponse(AGISuccess)
}

func (session *Session) handleHangup() error {
    callID := session.headers["agi_uniqueid"]
    
    // Process hangup
    startTime := time.Now()
    err := session.server.router.ProcessHangup(session.ctx, callID)
    processingTime := time.Since(startTime)
    
    // Update metrics
    session.server.metrics.ObserveHistogram("agi_processing_time", processingTime.Seconds(), map[string]string{
        "action": "hangup",
    })
    
    if err != nil {
        log := logger.WithContext(session.ctx)
        log.Warn("Failed to process hangup", "error", err.Error())
    }
    
    session.server.metrics.IncrementCounter("agi_requests_success", map[string]string{
        "action": "hangup",
    })
    
    return session.sendResponse(AGISuccess)
}

func (session *Session) setVariable(name, value string) error {
    session.updateActivity()
    
    cmd := fmt.Sprintf("SET VARIABLE %s \"%s\"", name, value)
    if err := session.sendCommand(cmd); err != nil {
        return err
    }
    
    response, err := session.readResponse()
    if err != nil {
        return err
    }
    
    log := logger.WithContext(session.ctx)
    log.Debug("Set AGI variable",
        "variable", name,
        "value", value,
        "response", response)
    
    return nil
}

func (session *Session) getVariable(name string) string {
    session.updateActivity()
    
    cmd := fmt.Sprintf("GET VARIABLE %s", name)
    if err := session.sendCommand(cmd); err != nil {
        return ""
    }
    
    response, err := session.readResponse()
    if err != nil {
        return ""
    }
    
    // Parse response: "200 result=1 (value)"
    if strings.Contains(response, "result=1") {
        start := strings.Index(response, "(")
        end := strings.LastIndex(response, ")")
        if start > 0 && end > start {
            value := response[start+1 : end]
            log := logger.WithContext(session.ctx)
            log.Debug("Got AGI variable",
                "variable", name,
                "value", value)
            return value
        }
    }
    
    return ""
}

func (session *Session) sendCommand(cmd string) error {
    session.conn.SetWriteDeadline(time.Now().Add(session.server.config.WriteTimeout))
    
    _, err := session.writer.WriteString(cmd + "\n")
    if err != nil {
        return err
    }
    
    return session.writer.Flush()
}

func (session *Session) readResponse() (string, error) {
    session.conn.SetReadDeadline(time.Now().Add(session.server.config.ReadTimeout))
    
    response, err := session.reader.ReadString('\n')
    if err != nil {
        return "", err
    }
    
    return strings.TrimSpace(response), nil
}

func (session *Session) sendResponse(response string) error {
    return session.sendCommand(response)
}

func (session *Session) extractProviderFromChannel(channel string) string {
    // Channel format examples:
    // PJSIP/endpoint-provider1-00000001
    // SIP/provider1-00000001
    
    if channel == "" {
        return ""
    }
    
    // Remove technology prefix
    parts := strings.Split(channel, "/")
    if len(parts) < 2 {
        return ""
    }
    
    // Get endpoint part
    endpointPart := parts[1]
    
    // Extract provider name
    // Format: "endpoint-providername-uniqueid" or "providername-uniqueid"
    endpointParts := strings.Split(endpointPart, "-")
    
    if len(endpointParts) >= 3 && endpointParts[0] == "endpoint" {
        // Join all parts except first and last
        providerParts := endpointParts[1 : len(endpointParts)-1]
        return strings.Join(providerParts, "-")
    } else if len(endpointParts) >= 2 {
        // Join all parts except last
        providerParts := endpointParts[:len(endpointParts)-1]
        return strings.Join(providerParts, "-")
    }
    
    return ""
}

func (session *Session) updateActivity() {
    session.lastActive = time.Now()
}

func (s *Server) connectionMonitor() {
    ticker := time.NewTicker(30 * time.Second)
    defer ticker.Stop()
    
    for {
        select {
        case <-s.shutdown:
            return
        case <-ticker.C:
            s.checkIdleConnections()
        }
    }
}

func (s *Server) checkIdleConnections() {
    s.mu.Lock()
    defer s.mu.Unlock()
    
    now := time.Now()
    var toClose []string
    
    for id, session := range s.activeConns {
        if now.Sub(session.lastActive) > s.config.IdleTimeout {
            toClose = append(toClose, id)
        }
    }
    
    for _, id := range toClose {
        if session, exists := s.activeConns[id]; exists {
            logger.Info("Closing idle connection", "session_id", id)
            session.conn.Close()
            session.cancel()
        }
    }
}

func (s *Server) forceCloseConnections() {
    s.mu.Lock()
    defer s.mu.Unlock()
    
    for id, session := range s.activeConns {
        logger.Info("Force closing connection", "session_id", id)
        session.conn.Close()
        session.cancel()
    }
}

// GetRouter returns the router instance (for testing)
func (s *Server) GetRouter() *router.Router {
    return s.router
}
