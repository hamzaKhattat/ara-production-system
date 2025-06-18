package router

import (
    "context"
    "database/sql"
    "encoding/json"
    "fmt"
    "strings"
    "sync"
    "time"
    
    "github.com/hamzaKhattat/ara-production-system/internal/models"
    "github.com/hamzaKhattat/ara-production-system/internal/provider"
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
    "github.com/hamzaKhattat/ara-production-system/pkg/errors"
)

// Router handles call routing logic
type Router struct {
    db           *sql.DB
    cache        CacheInterface
    loadBalancer *LoadBalancer
    metrics      MetricsInterface
    didManager   *DIDManager
    
    mu          sync.RWMutex
    activeCalls map[string]*models.CallRecord
    
    config Config
}

// Config holds router configuration
type Config struct {
    DIDAllocationTimeout time.Duration
    CallCleanupInterval  time.Duration
    StaleCallTimeout     time.Duration
    MaxRetries           int
    VerificationEnabled  bool
    StrictMode           bool
}

// CacheInterface defines cache operations
type CacheInterface interface {
    Get(ctx context.Context, key string, dest interface{}) error
    Set(ctx context.Context, key string, value interface{}, expiration time.Duration) error
    Delete(ctx context.Context, keys ...string) error
    Lock(ctx context.Context, key string, ttl time.Duration) (func(), error)
}

// MetricsInterface defines metrics operations
type MetricsInterface interface {
    IncrementCounter(name string, labels map[string]string)
    ObserveHistogram(name string, value float64, labels map[string]string)
    SetGauge(name string, value float64, labels map[string]string)
}

// NewRouter creates a new router instance
func NewRouter(db *sql.DB, cache CacheInterface, metrics MetricsInterface, config Config) *Router {
    r := &Router{
        db:           db,
        cache:        cache,
        loadBalancer: NewLoadBalancer(db, cache, metrics),
        metrics:      metrics,
        didManager:   NewDIDManager(db, cache),
        activeCalls:  make(map[string]*models.CallRecord),
        config:       config,
    }
    
    // Start cleanup routine
    go r.cleanupRoutine()
    
    return r
}

// ProcessIncomingCall handles incoming calls from S1 (Step 1 in UML)
func (r *Router) ProcessIncomingCall(ctx context.Context, callID, ani, dnis, inboundProvider string) (*models.CallResponse, error) {
    log := logger.WithContext(ctx).WithFields(map[string]interface{}{
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
    
    // Get route for this inbound provider (supports groups)
    route, err := r.getRouteForProvider(ctx, tx, inboundProvider)
    if err != nil {
        r.metrics.IncrementCounter("router_calls_failed", map[string]string{
            "reason": "no_route",
            "provider": inboundProvider,
        })
        return nil, err
    }
    
    log.WithField("route", route.Name).Debug("Found route for inbound provider")
    
    // Select intermediate provider (handle group or individual)
    intermediateProvider, err := r.selectProvider(ctx, route.IntermediateProvider, route.IntermediateIsGroup, route.LoadBalanceMode)
    if err != nil {
        r.metrics.IncrementCounter("router_calls_failed", map[string]string{
            "reason": "no_intermediate_provider",
            "route": route.Name,
        })
        return nil, err
    }
    
    // Select final provider (handle group or individual)
    finalProvider, err := r.selectProvider(ctx, route.FinalProvider, route.FinalIsGroup, route.LoadBalanceMode)
    if err != nil {
        r.metrics.IncrementCounter("router_calls_failed", map[string]string{
            "reason": "no_final_provider",
            "route": route.Name,
        })
        return nil, err
    }
    
    // Allocate DID
    did, err := r.didManager.AllocateDID(ctx, tx, intermediateProvider.Name, dnis)
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
        r.didManager.ReleaseDID(ctx, tx, did)
        return nil, err
    }
    
    // Update route current calls
    if err := r.incrementRouteCalls(ctx, tx, route.ID); err != nil {
        log.WithError(err).Warn("Failed to update route call count")
    }
    
    // Commit transaction
    if err := tx.Commit(); err != nil {
        return nil, errors.Wrap(err, errors.ErrDatabase, "failed to commit transaction")
    }
    
    // Store in memory after successful commit
    r.mu.Lock()
    r.activeCalls[callID] = record
    r.didManager.RegisterCallDID(did, callID)
    r.mu.Unlock()
    
    // Update metrics
    r.updateMetricsForNewCall(route.Name)
    
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
    
    log.WithFields(map[string]interface{}{
        "did_assigned": did,
        "next_hop": response.NextHop,
        "intermediate": intermediateProvider.Name,
        "final": finalProvider.Name,
    }).Info("Incoming call processed successfully")
    
    return response, nil
}

// ProcessReturnCall handles call returning from S3 (Step 3 in UML)
func (r *Router) ProcessReturnCall(ctx context.Context, ani2, did, provider, sourceIP string) (*models.CallResponse, error) {
    log := logger.WithContext(ctx).WithFields(map[string]interface{}{
        "ani2": ani2,
        "did": did,
        "provider": provider,
        "source_ip": sourceIP,
    })
    
    log.Info("Processing return call from S3")
    
    // Find call by DID
    callID := r.didManager.GetCallIDByDID(did)
    if callID == "" {
        return nil, errors.New(errors.ErrCallNotFound, "no active call for DID").
            WithContext("did", did)
    }
    
    r.mu.RLock()
    record, exists := r.activeCalls[callID]
    r.mu.RUnlock()
    
    if !exists || record == nil {
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
    r.updateCallState(callID, models.CallStatusReturnedFromS3, "S3_TO_S2")
    
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
    
    log.WithFields(map[string]interface{}{
        "call_id": callID,
        "next_hop": response.NextHop,
        "final_provider": record.FinalProvider,
    }).Info("Return call processed successfully")
    
    return response, nil
}

// ProcessFinalCall handles the final call from S4 (Step 5 in UML)
func (r *Router) ProcessFinalCall(ctx context.Context, callID, ani, dnis, provider, sourceIP string) error {
    log := logger.WithContext(ctx).WithFields(map[string]interface{}{
        "call_id": callID,
        "ani": ani,
        "dnis": dnis,
        "provider": provider,
        "source_ip": sourceIP,
    })
    
    log.Info("Processing final call from S4")
    
    // Find call record
    record := r.findCallRecord(callID, ani, dnis)
    if record == nil {
        return errors.New(errors.ErrCallNotFound, "call not found").
            WithContext("call_id", callID).
            WithContext("ani", ani).
            WithContext("dnis", dnis)
    }
    
    // Get actual call ID (in case we found by ANI/DNIS)
    actualCallID := r.getActualCallID(callID, record)
    
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
    
    // Complete the call
    return r.completeCall(ctx, actualCallID, record)
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
        r.handleIncompleteCall(ctx, callID, record)
    }
    
    return nil
}

// Helper methods

func (r *Router) getRouteForProvider(ctx context.Context, tx *sql.Tx, inboundProvider string) (*models.ProviderRoute, error) {
    // Try cache first
    cacheKey := fmt.Sprintf("route:inbound:%s", inboundProvider)
    var route models.ProviderRoute
    
    if err := r.cache.Get(ctx, cacheKey, &route); err == nil {
        return &route, nil
    }
    
    // Query database for both direct and group matches
    query := `
        SELECT pr.id, pr.name, pr.description, pr.inbound_provider, pr.intermediate_provider, 
               pr.final_provider, pr.load_balance_mode, pr.priority, pr.weight,
               pr.max_concurrent_calls, pr.current_calls, pr.enabled,
               pr.failover_routes, pr.routing_rules, pr.metadata,
               pr.inbound_is_group, pr.intermediate_is_group, pr.final_is_group
        FROM provider_routes pr
        WHERE pr.enabled = 1 AND (
            (pr.inbound_provider = ? AND pr.inbound_is_group = 0) OR
            (pr.inbound_is_group = 1 AND EXISTS (
                SELECT 1 FROM provider_group_members pgm
                JOIN provider_groups pg ON pgm.group_id = pg.id
                WHERE pg.name = pr.inbound_provider AND pgm.provider_name = ?
            ))
        )
        ORDER BY pr.priority DESC, pr.weight DESC
        LIMIT 1`
    
    var inboundIsGroup, intermediateIsGroup, finalIsGroup sql.NullBool
    
    err := tx.QueryRowContext(ctx, query, inboundProvider, inboundProvider).Scan(
        &route.ID, &route.Name, &route.Description,
        &route.InboundProvider, &route.IntermediateProvider, &route.FinalProvider,
        &route.LoadBalanceMode, &route.Priority, &route.Weight,
        &route.MaxConcurrentCalls, &route.CurrentCalls, &route.Enabled,
        &route.FailoverRoutes, &route.RoutingRules, &route.Metadata,
        &inboundIsGroup, &intermediateIsGroup, &finalIsGroup,
    )
    
    if err == sql.ErrNoRows {
        return nil, errors.New(errors.ErrRouteNotFound, "no route for provider").
            WithContext("provider", inboundProvider)
    }
    if err != nil {
        return nil, errors.Wrap(err, errors.ErrDatabase, "failed to query route")
    }
    
    // Set boolean flags
    route.InboundIsGroup = inboundIsGroup.Valid && inboundIsGroup.Bool
    route.IntermediateIsGroup = intermediateIsGroup.Valid && intermediateIsGroup.Bool
    route.FinalIsGroup = finalIsGroup.Valid && finalIsGroup.Bool
    
    // Check concurrent call limit
    if route.MaxConcurrentCalls > 0 && route.CurrentCalls >= route.MaxConcurrentCalls {
        return nil, errors.New(errors.ErrQuotaExceeded, "route at maximum capacity")
    }
    
    // Cache for 1 minute
    r.cache.Set(ctx, cacheKey, route, time.Minute)
    
    return &route, nil
}

func (r *Router) selectProvider(ctx context.Context, providerSpec string, isGroup bool, mode models.LoadBalanceMode) (*models.Provider, error) {
    if isGroup {
        return r.selectProviderFromGroup(ctx, providerSpec, mode)
    }
    return r.loadBalancer.SelectProvider(ctx, providerSpec, mode)
}

func (r *Router) selectProviderFromGroup(ctx context.Context, groupName string, mode models.LoadBalanceMode) (*models.Provider, error) {
    groupService := provider.NewGroupService(r.db, r.cache)
    members, err := groupService.GetGroupMembers(ctx, groupName)
    if err != nil {
        return nil, err
    }
    
    if len(members) == 0 {
        return nil, errors.New(errors.ErrProviderNotFound, "no providers in group")
    }
    
    return r.loadBalancer.SelectFromProviders(ctx, members, mode)
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

func (r *Router) incrementRouteCalls(ctx context.Context, tx *sql.Tx, routeID int) error {
    _, err := tx.ExecContext(ctx, 
        "UPDATE provider_routes SET current_calls = current_calls + 1 WHERE id = ?", 
        routeID)
    return err
}

func (r *Router) decrementRouteCalls(ctx context.Context, tx *sql.Tx, routeName string) error {
    _, err := tx.ExecContext(ctx,
        "UPDATE provider_routes SET current_calls = GREATEST(current_calls - 1, 0) WHERE name = ?",
        routeName)
    return err
}

func (r *Router) updateCallState(callID string, status models.CallStatus, step string) {
    r.mu.Lock()
    defer r.mu.Unlock()
    
    if record, exists := r.activeCalls[callID]; exists {
        record.Status = status
        record.CurrentStep = step
    }
}

func (r *Router) findCallRecord(callID, ani, dnis string) *models.CallRecord {
    r.mu.RLock()
    defer r.mu.RUnlock()
    
    // Try direct lookup first
    if record, exists := r.activeCalls[callID]; exists {
        return record
    }
    
    // Try to find by ANI/DNIS combination
    for _, rec := range r.activeCalls {
        if rec.OriginalANI == ani && rec.OriginalDNIS == dnis {
            return rec
        }
    }
    
    return nil
}

func (r *Router) getActualCallID(providedID string, record *models.CallRecord) string {
    r.mu.RLock()
    defer r.mu.RUnlock()
    
    // If we have the record with provided ID, use it
    if _, exists := r.activeCalls[providedID]; exists {
        return providedID
    }
    
    // Otherwise find the actual ID
    for id, rec := range r.activeCalls {
        if rec == record {
            return id
        }
    }
    
    return providedID
}

func (r *Router) completeCall(ctx context.Context, callID string, record *models.CallRecord) error {
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
    record.BillableDuration = record.Duration
    
    if err := r.updateCallRecord(ctx, tx, record); err != nil {
        logger.WithContext(ctx).WithError(err).Error("Failed to update call record")
    }
    
    // Release DID
    if err := r.didManager.ReleaseDID(ctx, tx, record.AssignedDID); err != nil {
        logger.WithContext(ctx).WithError(err).Error("Failed to release DID")
    }
    
    // Update route current calls
    if err := r.decrementRouteCalls(ctx, tx, record.RouteName); err != nil {
        logger.WithContext(ctx).WithError(err).Warn("Failed to update route call count")
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
    r.didManager.UnregisterCallDID(record.AssignedDID)
    r.mu.Unlock()
    
    // Update metrics
    r.updateMetricsForCompletedCall(record, duration)
    
    logger.WithContext(ctx).WithFields(map[string]interface{}{
        "call_id": callID,
        "duration": duration.Seconds(),
        "billable": record.BillableDuration,
    }).Info("Call completed successfully")
    
    return nil
}

func (r *Router) handleIncompleteCall(ctx context.Context, callID string, record *models.CallRecord) {
    // Determine final status
    status := models.CallStatusAbandoned
    if record.Status == models.CallStatusActive {
        status = models.CallStatusFailed
    }
    
    // Update call state
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
        r.didManager.ReleaseDID(ctx, tx, record.AssignedDID)
        r.decrementRouteCalls(ctx, tx, record.RouteName)
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
    r.didManager.UnregisterCallDID(record.AssignedDID)
    r.mu.Unlock()
    
    r.metrics.IncrementCounter("router_calls_failed", map[string]string{
        "route": record.RouteName,
        "reason": string(status),
    })
}

func (r *Router) updateMetricsForNewCall(routeName string) {
    r.metrics.IncrementCounter("router_calls_processed", map[string]string{
        "stage": "incoming",
        "route": routeName,
    })
    
    r.mu.RLock()
    activeCount := len(r.activeCalls)
    r.mu.RUnlock()
    
    r.metrics.SetGauge("router_active_calls", float64(activeCount), nil)
}

func (r *Router) updateMetricsForCompletedCall(record *models.CallRecord, duration time.Duration) {
    r.metrics.IncrementCounter("router_calls_completed", map[string]string{
        "route": record.RouteName,
        "intermediate": record.IntermediateProvider,
        "final": record.FinalProvider,
    })
    
    r.metrics.ObserveHistogram("router_call_duration", duration.Seconds(), map[string]string{
        "route": record.RouteName,
    })
    
    r.mu.RLock()
    activeCount := len(r.activeCalls)
    r.mu.RUnlock()
    
    r.metrics.SetGauge("router_active_calls", float64(activeCount), nil)
}

// Verification methods

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
        if err := r.verifySourceIP(ctx, sourceIP, record.IntermediateProvider, verification); err != nil {
            return err
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
        if err := r.verifySourceIP(ctx, sourceIP, record.FinalProvider, verification); err != nil {
            return err
        }
    }
    
    verification.Verified = true
    r.storeVerification(ctx, verification)
    return nil
}

func (r *Router) verifySourceIP(ctx context.Context, sourceIP, providerName string, verification *models.CallVerification) error {
    expectedIP, err := r.getProviderIP(ctx, providerName)
    if err == nil && expectedIP != "" {
        verification.ExpectedIP = expectedIP
        if !r.verifyIP(sourceIP, expectedIP) {
            verification.Verified = false
            verification.FailureReason = fmt.Sprintf("IP mismatch: expected %s, got %s", expectedIP, sourceIP)
            r.storeVerification(ctx, verification)
            return errors.New(errors.ErrInvalidIP, "IP verification failed")
        }
    }
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

// Cleanup methods

func (r *Router) cleanupRoutine() {
    ticker := time.NewTicker(r.config.CallCleanupInterval)
    defer ticker.Stop()
    
    for range ticker.C {
        ctx := context.Background()
        r.cleanupStaleCalls(ctx)
        r.didManager.CleanupStaleDIDs(ctx, r.config.StaleCallTimeout)
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
                r.didManager.ReleaseDID(ctx, tx, record.AssignedDID)
                r.decrementRouteCalls(ctx, tx, record.RouteName)
                tx.Commit()
            }
            
            // Update stats
            r.loadBalancer.UpdateCallComplete(record.IntermediateProvider, false, 0)
            r.loadBalancer.UpdateCallComplete(record.FinalProvider, false, 0)
            r.loadBalancer.DecrementActiveCalls(record.IntermediateProvider)
            r.loadBalancer.DecrementActiveCalls(record.FinalProvider)
            
            // Remove from memory
            delete(r.activeCalls, callID)
            r.didManager.UnregisterCallDID(record.AssignedDID)
            
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

// Public API methods

// GetStatistics returns current router statistics
func (r *Router) GetStatistics(ctx context.Context) (map[string]interface{}, error) {
    r.mu.RLock()
    activeCalls := len(r.activeCalls)
    r.mu.RUnlock()
    
    stats := map[string]interface{}{
        "active_calls": activeCalls,
    }
    
    // Get DID statistics
    didStats, err := r.didManager.GetStatistics(ctx)
    if err != nil {
        logger.WithContext(ctx).WithError(err).Warn("Failed to get DID stats")
    } else {
        for k, v := range didStats {
            stats[k] = v
        }
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
                utilization := 0.0
                if max > 0 {
                    utilization = float64(current) / float64(max) * 100
                }
                routes = append(routes, map[string]interface{}{
                    "name":        name,
                    "current":     current,
                    "max":         max,
                    "utilization": utilization,
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

// GetActiveCalls returns all active calls
func (r *Router) GetActiveCalls(ctx context.Context) ([]*models.CallRecord, error) {
    r.mu.RLock()
    defer r.mu.RUnlock()
    
    calls := make([]*models.CallRecord, 0, len(r.activeCalls))
    for _, record := range r.activeCalls {
        calls = append(calls, record)
    }
    
    return calls, nil
}

// GetLoadBalancer returns the load balancer instance
func (r *Router) GetLoadBalancer() *LoadBalancer {
    return r.loadBalancer
}

// GetDIDManager returns the DID manager instance
func (r *Router) GetDIDManager() *DIDManager {
    return r.didManager
}
