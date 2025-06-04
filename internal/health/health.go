package health

import (
    "context"
    "encoding/json"
    "net/http"
    "sync"
    "time"
    
    "github.com/gorilla/mux"
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
)

type HealthService struct {
    mu          sync.RWMutex
    checks      map[string]Checker
    readyChecks map[string]Checker
    server      *http.Server
}

type Checker interface {
    Check(ctx context.Context) error
}

type CheckFunc func(ctx context.Context) error

func (f CheckFunc) Check(ctx context.Context) error {
    return f(ctx)
}

type HealthResponse struct {
    Status     string                 `json:"status"`
    Timestamp  time.Time              `json:"timestamp"`
    Checks     map[string]CheckResult `json:"checks,omitempty"`
    TotalTime  string                 `json:"total_time,omitempty"`
}

type CheckResult struct {
    Status   string `json:"status"`
    Error    string `json:"error,omitempty"`
    Duration string `json:"duration"`
}

func NewHealthService(port int) *HealthService {
    hs := &HealthService{
        checks:      make(map[string]Checker),
        readyChecks: make(map[string]Checker),
    }
    
    router := mux.NewRouter()
    router.HandleFunc("/health/live", hs.handleLiveness).Methods("GET")
    router.HandleFunc("/health/ready", hs.handleReadiness).Methods("GET")
    
    hs.server = &http.Server{
        Addr:         fmt.Sprintf(":%d", port),
        Handler:      router,
        ReadTimeout:  10 * time.Second,
        WriteTimeout: 10 * time.Second,
    }
    
    return hs
}

func (hs *HealthService) Start() error {
    logger.WithField("addr", hs.server.Addr).Info("Health service started")
    return hs.server.ListenAndServe()
}

func (hs *HealthService) Stop() error {
    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()
    return hs.server.Shutdown(ctx)
}

func (hs *HealthService) RegisterLivenessCheck(name string, check Checker) {
    hs.mu.Lock()
    defer hs.mu.Unlock()
    hs.checks[name] = check
}

func (hs *HealthService) RegisterReadinessCheck(name string, check Checker) {
    hs.mu.Lock()
    defer hs.mu.Unlock()
    hs.readyChecks[name] = check
}

func (hs *HealthService) handleLiveness(w http.ResponseWriter, r *http.Request) {
    hs.handleCheck(w, r, hs.checks)
}

func (hs *HealthService) handleReadiness(w http.ResponseWriter, r *http.Request) {
    hs.handleCheck(w, r, hs.readyChecks)
}

func (hs *HealthService) handleCheck(w http.ResponseWriter, r *http.Request, checks map[string]Checker) {
    ctx := r.Context()
    start := time.Now()
    
    hs.mu.RLock()
    defer hs.mu.RUnlock()
    
    response := HealthResponse{
        Status:    "ok",
        Timestamp: start,
        Checks:    make(map[string]CheckResult),
    }
    
    var wg sync.WaitGroup
    resultChan := make(chan struct {
        name   string
        result CheckResult
    }, len(checks))
    
    for name, check := range checks {
        wg.Add(1)
        go func(n string, c Checker) {
            defer wg.Done()
            
            checkStart := time.Now()
            err := c.Check(ctx)
            duration := time.Since(checkStart)
            
            result := CheckResult{
                Status:   "ok",
                Duration: duration.String(),
            }
            
            if err != nil {
                result.Status = "failed"
                result.Error = err.Error()
                response.Status = "failed"
            }
            
            resultChan <- struct {
                name   string
                result CheckResult
            }{n, result}
        }(name, check)
    }
    
    go func() {
        wg.Wait()
        close(resultChan)
    }()
    
    for res := range resultChan {
        response.Checks[res.name] = res.result
    }
    
    response.TotalTime = time.Since(start).String()
    
    w.Header().Set("Content-Type", "application/json")
    if response.Status != "ok" {
        w.WriteHeader(http.StatusServiceUnavailable)
    }
    
    json.NewEncoder(w).Encode(response)
}
