package router

import (
    "context"
    "crypto/md5"
    "database/sql"
    "encoding/binary"
    "encoding/json"  // Added missing import
    "fmt"
    "math/rand"
    "sort"
    "sync"
    "sync/atomic"
    "time"
    
    "github.com/hamzaKhattat/ara-production-system/internal/models"
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
    "github.com/hamzaKhattat/ara-production-system/pkg/errors"  // Added missing import
)

type LoadBalancer struct {
    db      *sql.DB
    cache   CacheInterface
    metrics MetricsInterface
    
    mu sync.RWMutex
    
    // Round-robin counters
    rrCounters map[string]*uint64
    
    // Provider health tracking
    providerHealth map[string]*ProviderHealthInfo
    
    // Response time tracking
    responseTimes map[string]*ResponseTimeTracker
}

type ProviderHealthInfo struct {
    mu                  sync.RWMutex
    ActiveCalls         int64
    TotalCalls          int64
    FailedCalls         int64
    ConsecutiveFailures int
    LastSuccess         time.Time
    LastFailure         time.Time
    HealthScore         int
    IsHealthy           bool
}

type ResponseTimeTracker struct {
    mu           sync.RWMutex
    samples      []float64
    currentIndex int
    sum          float64
    count        int
}

func NewLoadBalancer(db *sql.DB, cache CacheInterface, metrics MetricsInterface) *LoadBalancer {
    lb := &LoadBalancer{
        db:             db,
        cache:          cache,
        metrics:        metrics,
        rrCounters:     make(map[string]*uint64),
        providerHealth: make(map[string]*ProviderHealthInfo),
        responseTimes:  make(map[string]*ResponseTimeTracker),
    }
    
    // Start health monitoring
    go lb.healthMonitor()
    
    return lb
}

func (lb *LoadBalancer) SelectProvider(ctx context.Context, providerSpec string, mode models.LoadBalanceMode) (*models.Provider, error) {
    // Get available providers
    providers, err := lb.getAvailableProviders(ctx, providerSpec)
    if err != nil {
        return nil, err
    }
    
    if len(providers) == 0 {
        return nil, errors.New(errors.ErrProviderNotFound, "no available providers")
    }
    
    // Filter healthy providers
    healthyProviders := lb.filterHealthyProviders(providers)
    if len(healthyProviders) == 0 {
        // If no healthy providers, try all providers
        logger.WithContext(ctx).Warn("No healthy providers, using all available")
        healthyProviders = providers
    }
    
    // Select based on mode
    switch mode {
    case models.LoadBalanceModeRoundRobin:
        return lb.selectRoundRobin(providerSpec, healthyProviders)
    case models.LoadBalanceModeWeighted:
        return lb.selectWeighted(healthyProviders)
    case models.LoadBalanceModePriority:
        return lb.selectPriority(healthyProviders)
    case models.LoadBalanceModeFailover:
        return lb.selectFailover(healthyProviders)
    case models.LoadBalanceModeLeastConnections:
        return lb.selectLeastConnections(healthyProviders)
    case models.LoadBalanceModeResponseTime:
        return lb.selectResponseTime(healthyProviders)
    case models.LoadBalanceModeHash:
        // For hash mode, we need additional context (like call ID)
        return lb.selectHash(ctx, healthyProviders)
    default:
        return lb.selectRoundRobin(providerSpec, healthyProviders)
    }
}

func (lb *LoadBalancer) getAvailableProviders(ctx context.Context, providerSpec string) ([]*models.Provider, error) {
    // Try cache first
    cacheKey := fmt.Sprintf("providers:%s", providerSpec)
    var providers []*models.Provider
    
    if err := lb.cache.Get(ctx, cacheKey, &providers); err == nil {
        return providers, nil
    }
    
    // Query database
    query := `
        SELECT id, name, type, host, port, username, password, auth_type,
               transport, codecs, max_channels, current_channels, priority,
               weight, cost_per_minute, active, health_check_enabled,
               last_health_check, health_status, metadata
        FROM providers
        WHERE active = 1 AND (name = ? OR type = ?)
        ORDER BY priority DESC, weight DESC`
    
    rows, err := lb.db.QueryContext(ctx, query, providerSpec, providerSpec)
    if err != nil {
        return nil, errors.Wrap(err, errors.ErrDatabase, "failed to query providers")
    }
    defer rows.Close()
    
    providers = make([]*models.Provider, 0)
    for rows.Next() {
        var p models.Provider
        var codecsJSON string
        
        err := rows.Scan(
            &p.ID, &p.Name, &p.Type, &p.Host, &p.Port,
            &p.Username, &p.Password, &p.AuthType, &p.Transport,
            &codecsJSON, &p.MaxChannels, &p.CurrentChannels,
            &p.Priority, &p.Weight, &p.CostPerMinute, &p.Active,
            &p.HealthCheckEnabled, &p.LastHealthCheck, &p.HealthStatus,
            &p.Metadata,
        )
        
        if err != nil {
            logger.WithContext(ctx).WithError(err).Warn("Failed to scan provider")
            continue
        }
        
        // Parse codecs
        if codecsJSON != "" {
            json.Unmarshal([]byte(codecsJSON), &p.Codecs)
        }
        
        providers = append(providers, &p)
    }
    
    if len(providers) == 0 {
        return nil, errors.New(errors.ErrProviderNotFound, "no providers found")
    }
    
    // Cache for 30 seconds
    lb.cache.Set(ctx, cacheKey, providers, 30*time.Second)
    
    return providers, nil
}

func (lb *LoadBalancer) filterHealthyProviders(providers []*models.Provider) []*models.Provider {
    healthy := make([]*models.Provider, 0, len(providers))
    
    for _, p := range providers {
        health := lb.getProviderHealth(p.Name)
        
        // Check if healthy
        if health.IsHealthy {
            // Check channel limits
            if p.MaxChannels == 0 || health.ActiveCalls < int64(p.MaxChannels) {
                healthy = append(healthy, p)
            }
        }
    }
    
    return healthy
}

func (lb *LoadBalancer) selectRoundRobin(key string, providers []*models.Provider) (*models.Provider, error) {
    if len(providers) == 0 {
        return nil, errors.New(errors.ErrProviderNotFound, "no providers available")
    }
    
    // Get or create counter
    counter, exists := lb.rrCounters[key]
    if !exists {
        var c uint64
        counter = &c
        lb.rrCounters[key] = counter
    }
    
    // Increment and select
    index := atomic.AddUint64(counter, 1) % uint64(len(providers))
    return providers[index], nil
}

func (lb *LoadBalancer) selectWeighted(providers []*models.Provider) (*models.Provider, error) {
    if len(providers) == 0 {
        return nil, errors.New(errors.ErrProviderNotFound, "no providers available")
    }
    
    // Calculate total weight
    totalWeight := 0
    for _, p := range providers {
        totalWeight += p.Weight
    }
    
    if totalWeight == 0 {
        // If no weights, fallback to random
        return providers[rand.Intn(len(providers))], nil
    }
    
    // Random weighted selection
    r := rand.Intn(totalWeight)
    for _, p := range providers {
        r -= p.Weight
        if r < 0 {
            return p, nil
        }
    }
    
    return providers[len(providers)-1], nil
}

func (lb *LoadBalancer) selectPriority(providers []*models.Provider) (*models.Provider, error) {
    if len(providers) == 0 {
        return nil, errors.New(errors.ErrProviderNotFound, "no providers available")
    }
    
    // Sort by priority (already sorted in query, but double-check)
    sort.Slice(providers, func(i, j int) bool {
        return providers[i].Priority > providers[j].Priority
    })
    
    // Select highest priority
    return providers[0], nil
}

func (lb *LoadBalancer) selectFailover(providers []*models.Provider) (*models.Provider, error) {
    if len(providers) == 0 {
        return nil, errors.New(errors.ErrProviderNotFound, "no providers available")
    }
    
    // Sort by priority
    sort.Slice(providers, func(i, j int) bool {
        return providers[i].Priority > providers[j].Priority
    })
    
    // Return first healthy provider
    for _, p := range providers {
        health := lb.getProviderHealth(p.Name)
        if health.IsHealthy && health.ConsecutiveFailures == 0 {
            return p, nil
        }
    }
    
    // If no perfect provider, return least failed
    var bestProvider *models.Provider
    minFailures := int(^uint(0) >> 1) // Max int
    
    for _, p := range providers {
        health := lb.getProviderHealth(p.Name)
        if health.ConsecutiveFailures < minFailures {
            minFailures = health.ConsecutiveFailures
            bestProvider = p
        }
    }
    
    return bestProvider, nil
}

func (lb *LoadBalancer) selectLeastConnections(providers []*models.Provider) (*models.Provider, error) {
    if len(providers) == 0 {
        return nil, errors.New(errors.ErrProviderNotFound, "no providers available")
    }
    
    var selectedProvider *models.Provider
    minConnections := int64(^uint64(0) >> 1) // Max int64
    
    for _, p := range providers {
        health := lb.getProviderHealth(p.Name)
        if health.ActiveCalls < minConnections {
            minConnections = health.ActiveCalls
            selectedProvider = p
        }
    }
    
    if selectedProvider == nil {
        return providers[0], nil
    }
    
    return selectedProvider, nil
}

func (lb *LoadBalancer) selectResponseTime(providers []*models.Provider) (*models.Provider, error) {
    if len(providers) == 0 {
        return nil, errors.New(errors.ErrProviderNotFound, "no providers available")
    }
    
    var selectedProvider *models.Provider
    minResponseTime := float64(^uint64(0) >> 1)
    
    for _, p := range providers {
        rt := lb.getAverageResponseTime(p.Name)
        if rt < minResponseTime && rt > 0 {
            minResponseTime = rt
            selectedProvider = p
        }
    }
    
    if selectedProvider == nil {
        // No response time data, fallback to random
        return providers[rand.Intn(len(providers))], nil
    }
    
    return selectedProvider, nil
}

func (lb *LoadBalancer) selectHash(ctx context.Context, providers []*models.Provider) (*models.Provider, error) {
    if len(providers) == 0 {
        return nil, errors.New(errors.ErrProviderNotFound, "no providers available")
    }
    
    // Get hash key from context (e.g., call ID or ANI)
    hashKey := ""
    if callID := ctx.Value("call_id"); callID != nil {
        hashKey = callID.(string)
    }
    
    if hashKey == "" {
        // No hash key, fallback to random
        return providers[rand.Intn(len(providers))], nil
    }
    
    // Calculate hash
    h := md5.Sum([]byte(hashKey))
    hashValue := binary.BigEndian.Uint32(h[:4])
    
    // Select provider based on hash
    index := hashValue % uint32(len(providers))
    return providers[index], nil
}

func (lb *LoadBalancer) getProviderHealth(providerName string) *ProviderHealthInfo {
    lb.mu.Lock()
    defer lb.mu.Unlock()
    
    health, exists := lb.providerHealth[providerName]
    if !exists {
        health = &ProviderHealthInfo{
            IsHealthy:   true,
            HealthScore: 100,
            LastSuccess: time.Now(),
        }
        lb.providerHealth[providerName] = health
    }
    
    return health
}

func (lb *LoadBalancer) getAverageResponseTime(providerName string) float64 {
    lb.mu.RLock()
    defer lb.mu.RUnlock()
    
    tracker, exists := lb.responseTimes[providerName]
    if !exists || tracker.count == 0 {
        return 0
    }
    
    tracker.mu.RLock()
    defer tracker.mu.RUnlock()
    
    return tracker.sum / float64(tracker.count)
}

// Public methods for updating stats

func (lb *LoadBalancer) IncrementActiveCalls(providerName string) {
    health := lb.getProviderHealth(providerName)
    health.mu.Lock()
    health.ActiveCalls++
    health.mu.Unlock()
    
    lb.metrics.SetGauge("provider_active_calls", float64(health.ActiveCalls), map[string]string{
        "provider": providerName,
    })
}

func (lb *LoadBalancer) DecrementActiveCalls(providerName string) {
    health := lb.getProviderHealth(providerName)
    health.mu.Lock()
    if health.ActiveCalls > 0 {
        health.ActiveCalls--
    }
    health.mu.Unlock()
    
    lb.metrics.SetGauge("provider_active_calls", float64(health.ActiveCalls), map[string]string{
        "provider": providerName,
    })
}

func (lb *LoadBalancer) UpdateCallComplete(providerName string, success bool, duration time.Duration) {
    health := lb.getProviderHealth(providerName)
    
    health.mu.Lock()
    health.TotalCalls++
    
    if success {
        health.ConsecutiveFailures = 0
        health.LastSuccess = time.Now()
        
        // Update response time
        lb.updateResponseTime(providerName, duration.Seconds())
    } else {
        health.FailedCalls++
        health.ConsecutiveFailures++
        health.LastFailure = time.Now()
        
        // Update health score
        health.HealthScore = lb.calculateHealthScore(health)
        
        // Mark unhealthy if too many failures
        if health.ConsecutiveFailures >= 5 {
            health.IsHealthy = false
        }
    }
    health.mu.Unlock()
    
    // Update metrics
    lb.metrics.IncrementCounter("provider_calls_total", map[string]string{
        "provider": providerName,
        "status":   map[bool]string{true: "success", false: "failed"}[success],
    })
    
    if success && duration > 0 {
        lb.metrics.ObserveHistogram("provider_call_duration", duration.Seconds(), map[string]string{
            "provider": providerName,
        })
    }
    
    // Update database
    go lb.updateProviderHealthDB(providerName, health)
}

func (lb *LoadBalancer) updateResponseTime(providerName string, responseTime float64) {
    lb.mu.Lock()
    tracker, exists := lb.responseTimes[providerName]
    if !exists {
        tracker = &ResponseTimeTracker{
            samples: make([]float64, 100), // Keep last 100 samples
        }
        lb.responseTimes[providerName] = tracker
    }
    lb.mu.Unlock()
    
    tracker.mu.Lock()
    defer tracker.mu.Unlock()
    
    // Remove old value from sum
    oldValue := tracker.samples[tracker.currentIndex]
    tracker.sum -= oldValue
    
    // Add new value
    tracker.samples[tracker.currentIndex] = responseTime
    tracker.sum += responseTime
    
    // Update count
    if tracker.count < len(tracker.samples) {
        tracker.count++
    }
    
    // Move to next position
    tracker.currentIndex = (tracker.currentIndex + 1) % len(tracker.samples)
}

func (lb *LoadBalancer) calculateHealthScore(health *ProviderHealthInfo) int {
    score := 100
    
    // Deduct for consecutive failures
    score -= health.ConsecutiveFailures * 10
    
    // Deduct for failure rate
    if health.TotalCalls > 0 {
        failureRate := float64(health.FailedCalls) / float64(health.TotalCalls)
        score -= int(failureRate * 50)
    }
    
    // Ensure score is between 0 and 100
    if score < 0 {
        score = 0
    } else if score > 100 {
        score = 100
    }
    
    return score
}

func (lb *LoadBalancer) updateProviderHealthDB(providerName string, health *ProviderHealthInfo) {
    health.mu.RLock()
    defer health.mu.RUnlock()
    
    query := `
        INSERT INTO provider_health (
            provider_name, health_score, active_calls, 
            last_success_at, last_failure_at, consecutive_failures, 
            is_healthy
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            health_score = VALUES(health_score),
            active_calls = VALUES(active_calls),
            last_success_at = VALUES(last_success_at),
            last_failure_at = VALUES(last_failure_at),
            consecutive_failures = VALUES(consecutive_failures),
            is_healthy = VALUES(is_healthy),
            updated_at = NOW()`
    
    lb.db.Exec(query, 
        providerName, health.HealthScore, health.ActiveCalls,
        health.LastSuccess, health.LastFailure, health.ConsecutiveFailures,
        health.IsHealthy,
    )
}

func (lb *LoadBalancer) healthMonitor() {
    ticker := time.NewTicker(30 * time.Second)
    defer ticker.Stop()
    
    for range ticker.C {
        lb.checkProviderHealth()
    }
}

func (lb *LoadBalancer) checkProviderHealth() {
    lb.mu.Lock()
    defer lb.mu.Unlock()
    
    now := time.Now()
    
    for name, health := range lb.providerHealth {
        health.mu.Lock()
        
        // Auto-recover if no failures in last 5 minutes
        if !health.IsHealthy && now.Sub(health.LastFailure) > 5*time.Minute {
            health.IsHealthy = true
            health.ConsecutiveFailures = 0
            health.HealthScore = 100
            logger.WithField("provider", name).Info("Provider auto-recovered")
        }
        
        // Check for stale providers
        if health.ActiveCalls == 0 && now.Sub(health.LastSuccess) > 24*time.Hour {
            // Remove from memory to save space
            delete(lb.providerHealth, name)
        }
        
        health.mu.Unlock()
    }
}

// GetProviderStats returns current stats for monitoring
func (lb *LoadBalancer) GetProviderStats() map[string]*models.ProviderStats {
    lb.mu.RLock()
    defer lb.mu.RUnlock()
    
    stats := make(map[string]*models.ProviderStats)
    
    for name, health := range lb.providerHealth {
        health.mu.RLock()
        
        successRate := float64(0)
        if health.TotalCalls > 0 {
            successRate = float64(health.TotalCalls-health.FailedCalls) / float64(health.TotalCalls) * 100
        }
        
        stats[name] = &models.ProviderStats{
            ProviderName:    name,
            TotalCalls:      health.TotalCalls,
            ActiveCalls:     health.ActiveCalls,
            FailedCalls:     health.FailedCalls,
            SuccessRate:     successRate,
            AvgResponseTime: int(lb.getAverageResponseTime(name) * 1000), // Convert to ms
            LastCallTime:    health.LastSuccess,
            IsHealthy:       health.IsHealthy,
        }
        
        health.mu.RUnlock()
    }
    
    return stats
}
// Add this method to the LoadBalancer struct

// SelectFromProviders selects a provider from a given list using the specified load balance mode
func (lb *LoadBalancer) SelectFromProviders(ctx context.Context, providers []*models.Provider, mode models.LoadBalanceMode) (*models.Provider, error) {
    if len(providers) == 0 {
        return nil, errors.New(errors.ErrProviderNotFound, "no providers available")
    }
    
    // Filter healthy providers
    healthyProviders := lb.filterHealthyProviders(providers)
    if len(healthyProviders) == 0 {
        // If no healthy providers, try all providers
        logger.WithContext(ctx).Warn("No healthy providers in list, using all available")
        healthyProviders = providers
    }
    
    // Select based on mode
    switch mode {
    case models.LoadBalanceModeRoundRobin:
        // For groups, use the group name as the round-robin key
        key := fmt.Sprintf("group:%v", time.Now().UnixNano()) // Unique key for this selection
        return lb.selectRoundRobin(key, healthyProviders)
    case models.LoadBalanceModeWeighted:
        return lb.selectWeighted(healthyProviders)
    case models.LoadBalanceModePriority:
        return lb.selectPriority(healthyProviders)
    case models.LoadBalanceModeFailover:
        return lb.selectFailover(healthyProviders)
    case models.LoadBalanceModeLeastConnections:
        return lb.selectLeastConnections(healthyProviders)
    case models.LoadBalanceModeResponseTime:
        return lb.selectResponseTime(healthyProviders)
    case models.LoadBalanceModeHash:
        return lb.selectHash(ctx, healthyProviders)
    default:
        return lb.selectRoundRobin(fmt.Sprintf("default:%v", time.Now().UnixNano()), healthyProviders)
    }
}
