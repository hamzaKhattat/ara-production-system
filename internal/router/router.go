package router

import (
    "context"
    "database/sql"
    "fmt"
    "sync"
    "time"
    
    "github.com/hamzaKhattat/ara-production-system/internal/models"
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
    "github.com/hamzaKhattat/ara-production-system/pkg/errors"
)

type Router struct {
    db           *sql.DB
    cache        CacheInterface
    loadBalancer *LoadBalancer
    metrics      MetricsInterface
    
    mu          sync.RWMutex
    activeCalls map[string]*models.CallRecord
    didToCall   map[string]string // DID -> CallID mapping
    
    config Config
}

type Config struct {
    DIDAllocationTimeout time.Duration
    CallCleanupInterval  time.Duration
    StaleCallTimeout     time.Duration
    MaxRetries           int
    VerificationEnabled  bool
    StrictMode           bool
}

type CacheInterface interface {
    Get(ctx context.Context, key string, dest interface{}) error
    Set(ctx context.Context, key string, value interface{}, expiration time.Duration) error
    Delete(ctx context.Context, keys ...string) error
    Lock(ctx context.Context, key string, ttl time.Duration) (func(), error)
}

type MetricsInterface interface {
    IncrementCounter(name string, labels map[string]string)
    ObserveHistogram(name string, value float64, labels map[string]string)
    SetGauge(name string, value float64, labels map[string]string)
}

func NewRouter(db *sql.DB, cache CacheInterface, metrics MetricsInterface, config Config) *Router {
    r := &Router{
        db:           db,
        cache:        cache,
        loadBalancer: NewLoadBalancer(db, cache, metrics),
        metrics:      metrics,
        activeCalls:  make(map[string]*models.CallRecord),
        didToCall:    make(map[string]string),
        config:       config,
    }
    
    // Start cleanup routine
    go r.cleanupRoutine()
    
    return r
}

// ProcessIncomingCall handles call from S1 to S2 (Step 1 in UML)
func (r *Router) ProcessIncomingCall(ctx context.Context, callID, ani, dnis, inboundProvider string) (*models.CallResponse, error) {
    log := logger.WithContext(ctx).WithFields(logger.Fields{
        "call_id": callID,
        "ani": ani,
        "dnis": dnis,
        "inbound_provider": inboundProvider,
    })
    
    log.Info("Processing incoming call from S1")
    
    // Start transaction
    tx, err := r.db.BeginTx(ctx, nil)
    if err != nil {
        return nil, errors.Wrap(err, errors.ErrDatabase, "failed to start transaction")
    }
    defer tx.Rollback()
    
    // Get route for this inbound provider
    route, err := r.getRouteForInbound(ctx, tx, inboundProvider)
    if err != nil {
        r.metrics.IncrementCounter("router_calls_failed", map[string]string{
            "reason": "no_route",
            "provider": inboundProvider,
        })
        return nil, err
    }
    
    log.WithField("route", route.Name).Debug("Found route for inbound provider")
    
    // Select intermediate provider using load balancing
    intermediateProvider, err := r.loadBalancer.SelectProvider(ctx, route.IntermediateProvider, route.LoadBalanceMode)
    if err != nil {
        r.metrics.IncrementCounter("router_calls_failed", map[string]string{
            "reason": "no_intermediate_provider",
            "route": route.Name,
        })
        return nil, err
    }
    
    // Select final provider
    finalProvider, err := r.loadBalancer.SelectProvider(ctx, route.FinalProvider, route.LoadBalanceMode)
    if err != nil {
        r.metrics.IncrementCounter("router_calls_failed", map[string]string{
            "reason": "no_final_provider",
            "route": route.Name,
        })
        return nil, err
    }
    
    // Allocate DID with retry and timeout
    did, err := r.allocateDID(ctx, tx, intermediateProvider.Name, dnis)
    if err != nil {
        r.metrics.IncrementCounter("router_calls_failed", map[string]string{
            "reason": "no_did_available",
            "provider": intermediateProvider.Name,
        })
        return nil, err
    }
    
    // Create call record
    record := &models.CallRecord{
        CallID:               callID,
        OriginalANI:          ani,
        OriginalDNIS:         dnis,
        TransformedANI:       dnis, // ANI-2 = DNIS-1
        AssignedDID:          did,
        InboundProvider:      inboundProvider,
        IntermediateProvider: intermediateProvider.Name,
        FinalProvider:        finalProvider.Name,
        RouteName:            route.Name,
        Status:               models.CallStatusActive,
        CurrentStep:          "S1_TO_S2",
        StartTime:            time.Now(),
        RecordingPath:        fmt.Sprintf("/var/spool/asterisk/monitor/%s.wav", callID),
    }
    
    // Store call record in database
    if err := r.storeCallRecord(ctx, tx, record); err != nil {
        r.releaseDID(ctx, tx, did)
        return nil, err
    }
    
    // Update route current calls
    if _, err := tx.ExecContext(ctx, 
        "UPDATE provider_routes SET current_calls = current_calls + 1 WHERE id = ?", 
        route.ID); err != nil {
        log.WithError(err).Warn("Failed to update route call count")
    }
    
    // Commit transaction
    if err := tx.Commit(); err != nil {
        return nil, errors.Wrap(err, errors.ErrDatabase, "failed to commit transaction")
    }
    
    // Store in memory after successful commit
    r.mu.Lock()
    r.activeCalls[callID] = record
    r.didToCall[did] = callID
    r.mu.Unlock()
    
    // Update metrics
    r.metrics.IncrementCounter("router_calls_processed", map[string]string{
        "stage": "incoming",
        "route": route.Name,
    })
    r.metrics.SetGauge("router_active_calls", float64(len(r.activeCalls)), nil)
    
    // Update load balancer stats
    r.loadBalancer.IncrementActiveCalls(intermediateProvider.Name)
    r.loadBalancer.IncrementActiveCalls(finalProvider.Name)
    
    // Prepare response
    response := &models.CallResponse{
        Status:      "success",
        DIDAssigned: did,
        NextHop:     fmt.Sprintf("endpoint-%s", intermediateProvider.Name),
        ANIToSend:   dnis,  // ANI-2 = DNIS-1
        DNISToSend:  did,   // DID
    }
    
    log.WithFields(logger.Fields{
        "did_assigned": did,
        "next_hop": response.NextHop,
        "intermediate": intermediateProvider.Name,
        "final": finalProvider.Name,
    }).Info("Incoming call processed successfully")
    
    return response, nil
}

// ProcessReturnCall handles call returning from S3 (Step 3 in UML)
func (r *Router) ProcessReturnCall(ctx context.Context, ani2, did, provider, sourceIP string) (*models.CallResponse, error) {
    log := logger.WithContext(ctx).WithFields(logger.Fields{
        "ani2": ani2,
        "did": did,
        "provider": provider,
        "source_ip": sourceIP,
    })
    
    log.Info("Processing return call from S3")
    
    // Find call by DID
    r.mu.RLock()
    callID, exists := r.didToCall[did]
    if !exists {
        r.mu.RUnlock()
        return nil, errors.New(errors.ErrCallNotFound, "no active call for DID").
            WithContext("did", did)
    }
    
    record := r.activeCalls[callID]
    r.mu.RUnlock()
    
    if record == nil {
        return nil, errors.New(errors.ErrCallNotFound, "call record not found")
    }
    
    // Verify if enabled
    if r.config.VerificationEnabled {
        if err := r.verifyReturnCall(ctx, record, ani2, did, provider, sourceIP); err != nil {
            r.metrics.IncrementCounter("router_verification_failed", map[string]string{
                "stage": "return",
                "reason": "verification_failed",
            })
            
            if r.config.StrictMode {
                return nil, err
            }
            log.WithError(err).Warn("Verification failed but continuing (strict mode disabled)")
        }
    }
    
    // Update call state
    r.mu.Lock()
    record.CurrentStep = "S3_TO_S2"
    record.Status = models.CallStatusReturnedFromS3
    r.mu.Unlock()
    
    // Update metrics
    r.metrics.IncrementCounter("router_calls_processed", map[string]string{
        "stage": "return",
        "route": record.RouteName,
    })
    
    // Build response for routing to S4
    response := &models.CallResponse{
        Status:     "success",
        NextHop:    fmt.Sprintf("endpoint-%s", record.FinalProvider),
        ANIToSend:  record.OriginalANI,   // Restore ANI-1
        DNISToSend: record.OriginalDNIS,  // Restore DNIS-1
    }
    
    log.WithFields(logger.Fields{
        "call_id": callID,
        "next_hop": response.NextHop,
        "final_provider": record.FinalProvider,
    }).Info("Return call processed successfully")
    
    return response, nil
}

// ProcessFinalCall handles the final call from S4 (Step 5 in UML)
func (r *Router) ProcessFinalCall(ctx context.Context, callID, ani, dnis, provider, sourceIP string) error {
    log := logger.WithContext(ctx).WithFields(logger.Fields{
        "call_id": callID,
        "ani": ani,
        "dnis": dnis,
        "provider": provider,
        "source_ip": sourceIP,
    })
    
    log.Info("Processing final call from S4")
    
    // Find call record
    r.mu.RLock()
    record, exists := r.activeCalls[callID]
    r.mu.RUnlock()
    
    if !exists {
        // Try to find by ANI/DNIS combination
        r.mu.RLock()
        for cid, rec := range r.activeCalls {
            if rec.OriginalANI == ani && rec.OriginalDNIS == dnis {
                record = rec
                callID = cid
                break
            }
        }
        r.mu.RUnlock()
        
        if record == nil {
            return errors.New(errors.ErrCallNotFound, "call not found").
                WithContext("call_id", callID).
                WithContext("ani", ani).
                WithContext("dnis", dnis)
        }
    }
    
    // Verify if enabled
    if r.config.VerificationEnabled {
        if err := r.verifyFinalCall(ctx, record, ani, dnis, provider, sourceIP); err != nil {
            r.metrics.IncrementCounter("router_verification_failed", map[string]string{
                "stage": "final",
                "reason": "verification_failed",
            })
            
            if r.config.StrictMode {
                return err
            }
            log.WithError(err).Warn("Verification failed but continuing")
        }
    }
    
    // Calculate duration
    duration := time.Since(record.StartTime)
    
    // Start transaction for cleanup
    tx, err := r.db.BeginTx(ctx, nil)
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to start transaction")
    }
    defer tx.Rollback()
    
    // Update call record
    now := time.Now()
    record.Status = models.CallStatusCompleted
    record.CurrentStep = "COMPLETED"
    record.EndTime = &now
    record.Duration = int(duration.Seconds())
    record.BillableDuration = record.Duration // Can be adjusted based on billing rules
    
    if err := r.updateCallRecord(ctx, tx, record); err != nil {
        log.WithError(err).Error("Failed to update call record")
    }
    
    // Release DID
    if err := r.releaseDID(ctx, tx, record.AssignedDID); err != nil {
        log.WithError(err).Error("Failed to release DID")
    }
    
    // Update route current calls
    if _, err := tx.ExecContext(ctx,
        "UPDATE provider_routes SET current_calls = GREATEST(current_calls - 1, 0) WHERE name = ?",
        record.RouteName); err != nil {
        log.WithError(err).Warn("Failed to update route call count")
    }
    
    // Commit transaction
    if err := tx.Commit(); err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to commit transaction")
    }
    
    // Update load balancer stats
    r.loadBalancer.UpdateCallComplete(record.IntermediateProvider, true, duration)
    r.loadBalancer.UpdateCallComplete(record.FinalProvider, true, duration)
    r.loadBalancer.DecrementActiveCalls(record.IntermediateProvider)
    r.loadBalancer.DecrementActiveCalls(record.FinalProvider)
    
    // Clean up memory
    r.mu.Lock()
    delete(r.activeCalls, callID)
    delete(r.didToCall, record.AssignedDID)
    r.mu.Unlock()
    
    // Update metrics
    r.metrics.Increment()
Counter("router_calls_completed", map[string]string{
       "route": record.RouteName,
       "intermediate": record.IntermediateProvider,
       "final": record.FinalProvider,
   })
   r.metrics.ObserveHistogram("router_call_duration", duration.Seconds(), map[string]string{
       "route": record.RouteName,
   })
   r.metrics.SetGauge("router_active_calls", float64(len(r.activeCalls)), nil)
   
   log.WithFields(logger.Fields{
       "duration": duration.Seconds(),
       "billable": record.BillableDuration,
   }).Info("Call completed successfully")
   
   return nil
}

// ProcessHangup handles call hangup from AGI
func (r *Router) ProcessHangup(ctx context.Context, callID string) error {
   log := logger.WithContext(ctx).WithField("call_id", callID)
   
   r.mu.RLock()
   record, exists := r.activeCalls[callID]
   r.mu.RUnlock()
   
   if !exists {
       // Already cleaned up
       return nil
   }
   
   log.WithField("status", record.Status).Info("Processing hangup")
   
   // Only process if not already completed
   if record.Status != models.CallStatusCompleted {
       // Mark as failed/abandoned
       status := models.CallStatusAbandoned
       if record.Status == models.CallStatusActive {
           status = models.CallStatusFailed
       }
       
       r.mu.Lock()
       record.Status = status
       record.CurrentStep = "HANGUP"
       now := time.Now()
       record.EndTime = &now
       record.Duration = int(now.Sub(record.StartTime).Seconds())
       r.mu.Unlock()
       
       // Update in database
       tx, err := r.db.BeginTx(ctx, nil)
       if err == nil {
           r.updateCallRecord(ctx, tx, record)
           r.releaseDID(ctx, tx, record.AssignedDID)
           tx.Commit()
       }
       
       // Update stats
       r.loadBalancer.UpdateCallComplete(record.IntermediateProvider, false, 0)
       r.loadBalancer.UpdateCallComplete(record.FinalProvider, false, 0)
       r.loadBalancer.DecrementActiveCalls(record.IntermediateProvider)
       r.loadBalancer.DecrementActiveCalls(record.FinalProvider)
       
       // Clean up
       r.mu.Lock()
       delete(r.activeCalls, callID)
       delete(r.didToCall, record.AssignedDID)
       r.mu.Unlock()
       
       r.metrics.IncrementCounter("router_calls_failed", map[string]string{
           "route": record.RouteName,
           "reason": string(status),
       })
   }
   
   return nil
}

// Helper methods

func (r *Router) getRouteForInbound(ctx context.Context, tx *sql.Tx, inboundProvider string) (*models.ProviderRoute, error) {
   // Try cache first
   cacheKey := fmt.Sprintf("route:inbound:%s", inboundProvider)
   var route models.ProviderRoute
   
   if err := r.cache.Get(ctx, cacheKey, &route); err == nil {
       return &route, nil
   }
   
   // Query database
   query := `
       SELECT id, name, description, inbound_provider, intermediate_provider, 
              final_provider, load_balance_mode, priority, weight,
              max_concurrent_calls, current_calls, enabled,
              failover_routes, routing_rules, metadata
       FROM provider_routes
       WHERE inbound_provider = ? AND enabled = 1
       ORDER BY priority DESC, weight DESC
       LIMIT 1`
   
   err := tx.QueryRowContext(ctx, query, inboundProvider).Scan(
       &route.ID, &route.Name, &route.Description,
       &route.InboundProvider, &route.IntermediateProvider, &route.FinalProvider,
       &route.LoadBalanceMode, &route.Priority, &route.Weight,
       &route.MaxConcurrentCalls, &route.CurrentCalls, &route.Enabled,
       &route.FailoverRoutes, &route.RoutingRules, &route.Metadata,
   )
   
   if err == sql.ErrNoRows {
       return nil, errors.New(errors.ErrRouteNotFound, "no route for inbound provider").
           WithContext("provider", inboundProvider)
   }
   if err != nil {
       return nil, errors.Wrap(err, errors.ErrDatabase, "failed to query route")
   }
   
   // Check concurrent call limit
   if route.MaxConcurrentCalls > 0 && route.CurrentCalls >= route.MaxConcurrentCalls {
       return nil, errors.New(errors.ErrQuotaExceeded, "route at maximum capacity")
   }
   
   // Cache for 1 minute
   r.cache.Set(ctx, cacheKey, route, time.Minute)
   
   return &route, nil
}

func (r *Router) allocateDID(ctx context.Context, tx *sql.Tx, providerName, destination string) (string, error) {
   // Use distributed lock to prevent race conditions
   lockKey := fmt.Sprintf("did:allocation:%s", providerName)
   unlock, err := r.cache.Lock(ctx, lockKey, r.config.DIDAllocationTimeout)
   if err != nil {
       return "", errors.Wrap(err, errors.ErrInternal, "failed to acquire DID lock")
   }
   defer unlock()
   
   // Try to get DID for specific provider first
   query := `
       SELECT number 
       FROM dids 
       WHERE in_use = 0 AND provider_name = ?
       ORDER BY last_used_at ASC, RAND()
       LIMIT 1
       FOR UPDATE`
   
   var did string
   err = tx.QueryRowContext(ctx, query, providerName).Scan(&did)
   
   if err == sql.ErrNoRows {
       // Try any available DID
       err = tx.QueryRowContext(ctx, `
           SELECT number 
           FROM dids 
           WHERE in_use = 0
           ORDER BY last_used_at ASC, RAND()
           LIMIT 1
           FOR UPDATE`).Scan(&did)
   }
   
   if err != nil {
       return "", errors.New(errors.ErrDIDNotAvailable, "no available DIDs")
   }
   
   // Mark DID as in use
   updateQuery := `
       UPDATE dids 
       SET in_use = 1, 
           destination = ?, 
           allocated_at = NOW(),
           usage_count = usage_count + 1,
           updated_at = NOW()
       WHERE number = ?`
   
   if _, err := tx.ExecContext(ctx, updateQuery, destination, did); err != nil {
       return "", errors.Wrap(err, errors.ErrDatabase, "failed to allocate DID")
   }
   
   // Clear DID cache
   r.cache.Delete(ctx, fmt.Sprintf("did:%s", did))
   
   return did, nil
}

func (r *Router) releaseDID(ctx context.Context, tx *sql.Tx, did string) error {
   if did == "" {
       return nil
   }
   
   query := `
       UPDATE dids 
       SET in_use = 0, 
           destination = NULL,
           released_at = NOW(),
           last_used_at = NOW(),
           updated_at = NOW()
       WHERE number = ?`
   
   if _, err := tx.ExecContext(ctx, query, did); err != nil {
       return errors.Wrap(err, errors.ErrDatabase, "failed to release DID")
   }
   
   // Clear DID cache
   r.cache.Delete(ctx, fmt.Sprintf("did:%s", did))
   
   return nil
}

func (r *Router) storeCallRecord(ctx context.Context, tx *sql.Tx, record *models.CallRecord) error {
   query := `
       INSERT INTO call_records (
           call_id, original_ani, original_dnis, transformed_ani, assigned_did,
           inbound_provider, intermediate_provider, final_provider, route_name,
           status, current_step, start_time, recording_path, metadata
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
   
   metadata, _ := json.Marshal(record.Metadata)
   
   _, err := tx.ExecContext(ctx, query,
       record.CallID, record.OriginalANI, record.OriginalDNIS,
       record.TransformedANI, record.AssignedDID,
       record.InboundProvider, record.IntermediateProvider, record.FinalProvider,
       record.RouteName, record.Status, record.CurrentStep,
       record.StartTime, record.RecordingPath, metadata,
   )
   
   if err != nil {
       return errors.Wrap(err, errors.ErrDatabase, "failed to store call record")
   }
   
   return nil
}

func (r *Router) updateCallRecord(ctx context.Context, tx *sql.Tx, record *models.CallRecord) error {
   query := `
       UPDATE call_records 
       SET status = ?, current_step = ?, failure_reason = ?,
           answer_time = ?, end_time = ?, duration = ?,
           billable_duration = ?, sip_response_code = ?,
           quality_score = ?, metadata = ?
       WHERE call_id = ?`
   
   metadata, _ := json.Marshal(record.Metadata)
   
   _, err := tx.ExecContext(ctx, query,
       record.Status, record.CurrentStep, record.FailureReason,
       record.AnswerTime, record.EndTime, record.Duration,
       record.BillableDuration, record.SIPResponseCode,
       record.QualityScore, metadata, record.CallID,
   )
   
   if err != nil {
       return errors.Wrap(err, errors.ErrDatabase, "failed to update call record")
   }
   
   return nil
}

func (r *Router) verifyReturnCall(ctx context.Context, record *models.CallRecord, ani2, did, provider, sourceIP string) error {
   verification := &models.CallVerification{
       CallID:           record.CallID,
       VerificationStep: "S3_TO_S2",
       ExpectedANI:      record.OriginalDNIS, // ANI-2 should be DNIS-1
       ExpectedDNIS:     did,
       ReceivedANI:      ani2,
       ReceivedDNIS:     did,
       SourceIP:         sourceIP,
   }
   
   // Verify ANI transformation
   if ani2 != record.OriginalDNIS {
       verification.Verified = false
       verification.FailureReason = fmt.Sprintf("ANI mismatch: expected %s, got %s", record.OriginalDNIS, ani2)
       r.storeVerification(ctx, verification)
       return errors.New(errors.ErrAuthFailed, "ANI verification failed").
           WithContext("expected", record.OriginalDNIS).
           WithContext("received", ani2)
   }
   
   // Verify provider
   if provider != record.IntermediateProvider {
       verification.Verified = false
       verification.FailureReason = fmt.Sprintf("Provider mismatch: expected %s, got %s", record.IntermediateProvider, provider)
       r.storeVerification(ctx, verification)
       return errors.New(errors.ErrAuthFailed, "Provider verification failed")
   }
   
   // Verify source IP if available
   if sourceIP != "" {
       expectedIP, err := r.getProviderIP(ctx, record.IntermediateProvider)
       if err == nil && expectedIP != "" {
           verification.ExpectedIP = expectedIP
           if !r.verifyIP(sourceIP, expectedIP) {
               verification.Verified = false
               verification.FailureReason = fmt.Sprintf("IP mismatch: expected %s, got %s", expectedIP, sourceIP)
               r.storeVerification(ctx, verification)
               return errors.New(errors.ErrInvalidIP, "IP verification failed")
           }
       }
   }
   
   verification.Verified = true
   r.storeVerification(ctx, verification)
   return nil
}

func (r *Router) verifyFinalCall(ctx context.Context, record *models.CallRecord, ani, dnis, provider, sourceIP string) error {
   verification := &models.CallVerification{
       CallID:           record.CallID,
       VerificationStep: "S4_TO_S2",
       ExpectedANI:      record.OriginalANI,
       ExpectedDNIS:     record.OriginalDNIS,
       ReceivedANI:      ani,
       ReceivedDNIS:     dnis,
       SourceIP:         sourceIP,
   }
   
   // Verify ANI/DNIS restoration
   if ani != record.OriginalANI || dnis != record.OriginalDNIS {
       verification.Verified = false
       verification.FailureReason = fmt.Sprintf("ANI/DNIS mismatch: expected %s/%s, got %s/%s",
           record.OriginalANI, record.OriginalDNIS, ani, dnis)
       r.storeVerification(ctx, verification)
       return errors.New(errors.ErrAuthFailed, "ANI/DNIS verification failed")
   }
   
   // Verify provider
   if provider != record.FinalProvider {
       verification.Verified = false
       verification.FailureReason = fmt.Sprintf("Provider mismatch: expected %s, got %s", record.FinalProvider, provider)
       r.storeVerification(ctx, verification)
       return errors.New(errors.ErrAuthFailed, "Provider verification failed")
   }
   
   // Verify source IP
   if sourceIP != "" {
       expectedIP, err := r.getProviderIP(ctx, record.FinalProvider)
       if err == nil && expectedIP != "" {
           verification.ExpectedIP = expectedIP
           if !r.verifyIP(sourceIP, expectedIP) {
               verification.Verified = false
               verification.FailureReason = fmt.Sprintf("IP mismatch: expected %s, got %s", expectedIP, sourceIP)
               r.storeVerification(ctx, verification)
               return errors.New(errors.ErrInvalidIP, "IP verification failed")
           }
       }
   }
   
   verification.Verified = true
   r.storeVerification(ctx, verification)
   return nil
}

func (r *Router) storeVerification(ctx context.Context, verification *models.CallVerification) {
   query := `
       INSERT INTO call_verifications (
           call_id, verification_step, expected_ani, expected_dnis,
           received_ani, received_dnis, source_ip, expected_ip,
           verified, failure_reason
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
   
   if _, err := r.db.ExecContext(ctx, query,
       verification.CallID, verification.VerificationStep,
       verification.ExpectedANI, verification.ExpectedDNIS,
       verification.ReceivedANI, verification.ReceivedDNIS,
       verification.SourceIP, verification.ExpectedIP,
       verification.Verified, verification.FailureReason,
   ); err != nil {
       logger.WithContext(ctx).WithError(err).Warn("Failed to store verification record")
   }
}

func (r *Router) getProviderIP(ctx context.Context, providerName string) (string, error) {
   var host string
   err := r.db.QueryRowContext(ctx,
       "SELECT host FROM providers WHERE name = ?",
       providerName).Scan(&host)
   
   if err != nil {
       return "", err
   }
   
   return host, nil
}

func (r *Router) verifyIP(sourceIP, expectedIP string) bool {
   // Extract IP without port
   if idx := strings.LastIndex(sourceIP, ":"); idx != -1 {
       sourceIP = sourceIP[:idx]
   }
   
   return sourceIP == expectedIP
}

func (r *Router) cleanupRoutine() {
   ticker := time.NewTicker(r.config.CallCleanupInterval)
   defer ticker.Stop()
   
   for range ticker.C {
       ctx := context.Background()
       r.cleanupStaleCalls(ctx)
   }
}

func (r *Router) cleanupStaleCalls(ctx context.Context) {
   log := logger.WithContext(ctx)
   
   r.mu.Lock()
   defer r.mu.Unlock()
   
   now := time.Now()
   cleaned := 0
   
   for callID, record := range r.activeCalls {
       if now.Sub(record.StartTime) > r.config.StaleCallTimeout {
           log.WithField("call_id", callID).Warn("Cleaning up stale call")
           
           // Mark as timeout
           record.Status = models.CallStatusTimeout
           record.CurrentStep = "CLEANUP"
           record.EndTime = &now
           record.Duration = int(now.Sub(record.StartTime).Seconds())
           
           // Update in database
           tx, err := r.db.BeginTx(ctx, nil)
           if err == nil {
               r.updateCallRecord(ctx, tx, record)
               r.releaseDID(ctx, tx, record.AssignedDID)
               
               // Update route current calls
               tx.ExecContext(ctx,
                   "UPDATE provider_routes SET current_calls = GREATEST(current_calls - 1, 0) WHERE name = ?",
                   record.RouteName)
               
               tx.Commit()
           }
           
           // Update stats
           r.loadBalancer.UpdateCallComplete(record.IntermediateProvider, false, 0)
           r.loadBalancer.UpdateCallComplete(record.FinalProvider, false, 0)
           r.loadBalancer.DecrementActiveCalls(record.IntermediateProvider)
           r.loadBalancer.DecrementActiveCalls(record.FinalProvider)
           
           // Remove from memory
           delete(r.activeCalls, callID)
           delete(r.didToCall, record.AssignedDID)
           
           cleaned++
       }
   }
   
   if cleaned > 0 {
       log.WithField("count", cleaned).Info("Cleaned up stale calls")
       r.metrics.IncrementCounter("router_calls_timeout", map[string]string{
           "count": fmt.Sprintf("%d", cleaned),
       })
   }
}

// GetStatistics returns current router statistics
func (r *Router) GetStatistics(ctx context.Context) (map[string]interface{}, error) {
   r.mu.RLock()
   activeCalls := len(r.activeCalls)
   r.mu.RUnlock()
   
   stats := map[string]interface{}{
       "active_calls": activeCalls,
   }
   
   // Get DID statistics
   var totalDIDs, usedDIDs, availableDIDs int
   err := r.db.QueryRowContext(ctx, `
       SELECT 
           COUNT(*) as total,
           SUM(CASE WHEN in_use = 1 THEN 1 ELSE 0 END) as used,
           SUM(CASE WHEN in_use = 0 THEN 1 ELSE 0 END) as available
       FROM dids
   `).Scan(&totalDIDs, &usedDIDs, &availableDIDs)
   
   if err != nil {
       logger.WithContext(ctx).WithError(err).Warn("Failed to get DID stats")
   } else {
       stats["total_dids"] = totalDIDs
       stats["used_dids"] = usedDIDs
       stats["available_dids"] = availableDIDs
       stats["did_utilization"] = float64(usedDIDs) / float64(totalDIDs) * 100
   }
   
   // Get route statistics
   rows, err := r.db.QueryContext(ctx, `
       SELECT name, current_calls, max_concurrent_calls
       FROM provider_routes
       WHERE enabled = 1
   `)
   
   if err == nil {
       defer rows.Close()
       
       routes := make([]map[string]interface{}, 0)
       for rows.Next() {
           var name string
           var current, max int
           if err := rows.Scan(&name, &current, &max); err == nil {
               routes = append(routes, map[string]interface{}{
                   "name":        name,
                   "current":     current,
                   "max":         max,
                   "utilization": float64(current) / float64(max) * 100,
               })
           }
       }
       stats["routes"] = routes
   }
   
   return stats, nil
}

// GetActiveCall returns details of an active call
func (r *Router) GetActiveCall(ctx context.Context, callID string) (*models.CallRecord, error) {
   r.mu.RLock()
   defer r.mu.RUnlock()
   
   record, exists := r.activeCalls[callID]
   if !exists {
       return nil, errors.New(errors.ErrCallNotFound, "call not found")
   }
   
   return record, nil
}
