package router

import (
    "context"
    "database/sql"
    "fmt"
    "sync"
    "time"
    
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
    "github.com/hamzaKhattat/ara-production-system/pkg/errors"
)

// DIDManager handles DID allocation and management
type DIDManager struct {
    db    *sql.DB
    cache CacheInterface
    
    mu         sync.RWMutex
    didToCall  map[string]string // DID -> CallID mapping
}

// NewDIDManager creates a new DID manager
func NewDIDManager(db *sql.DB, cache CacheInterface) *DIDManager {
    return &DIDManager{
        db:        db,
        cache:     cache,
        didToCall: make(map[string]string),
    }
}

// AllocateDID allocates a DID for a call
func (dm *DIDManager) AllocateDID(ctx context.Context, tx *sql.Tx, providerName, destination string) (string, error) {
    // Use distributed lock to prevent race conditions
    lockKey := fmt.Sprintf("did:allocation:%s", providerName)
    unlock, err := dm.cache.Lock(ctx, lockKey, 5*time.Second)
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
            allocation_time = NOW(),
            usage_count = COALESCE(usage_count, 0) + 1,
            updated_at = NOW()
        WHERE number = ?`
    
    if _, err := tx.ExecContext(ctx, updateQuery, destination, did); err != nil {
        return "", errors.Wrap(err, errors.ErrDatabase, "failed to allocate DID")
    }
    
    // Clear DID cache
    dm.cache.Delete(ctx, fmt.Sprintf("did:%s", did))
    dm.cache.Delete(ctx, "did:stats")
    
    logger.WithContext(ctx).WithFields(map[string]interface{}{
        "did": did,
        "provider": providerName,
        "destination": destination,
    }).Debug("DID allocated")
    
    return did, nil
}

// ReleaseDID releases a DID back to the pool
func (dm *DIDManager) ReleaseDID(ctx context.Context, tx *sql.Tx, did string) error {
    if did == "" {
        return nil
    }
    
    query := `
        UPDATE dids 
        SET in_use = 0, 
            destination = NULL,
            allocation_time = NULL,
            released_at = NOW(),
            last_used_at = NOW(),
            updated_at = NOW()
        WHERE number = ?`
    
    if _, err := tx.ExecContext(ctx, query, did); err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to release DID")
    }
    
    // Clear DID cache
    dm.cache.Delete(ctx, fmt.Sprintf("did:%s", did))
    dm.cache.Delete(ctx, "did:stats")
    
    logger.WithContext(ctx).WithField("did", did).Debug("DID released")
    
    return nil
}

// RegisterCallDID registers a DID-to-Call mapping
func (dm *DIDManager) RegisterCallDID(did, callID string) {
    dm.mu.Lock()
    defer dm.mu.Unlock()
    dm.didToCall[did] = callID
}

// UnregisterCallDID removes a DID-to-Call mapping
func (dm *DIDManager) UnregisterCallDID(did string) {
    dm.mu.Lock()
    defer dm.mu.Unlock()
    delete(dm.didToCall, did)
}

// GetCallIDByDID returns the call ID associated with a DID
func (dm *DIDManager) GetCallIDByDID(did string) string {
    dm.mu.RLock()
    defer dm.mu.RUnlock()
    return dm.didToCall[did]
}

// GetStatistics returns DID pool statistics
func (dm *DIDManager) GetStatistics(ctx context.Context) (map[string]interface{}, error) {
    // Try cache first
    cacheKey := "did:stats"
    var stats map[string]interface{}
    if err := dm.cache.Get(ctx, cacheKey, &stats); err == nil {
        return stats, nil
    }
    
    // Query database - Fixed to handle NULL values properly
    var totalDIDs, usedDIDs, availableDIDs sql.NullInt64
    err := dm.db.QueryRowContext(ctx, `
        SELECT 
            COUNT(*) as total,
            COALESCE(SUM(CASE WHEN in_use = 1 THEN 1 ELSE 0 END), 0) as used,
            COALESCE(SUM(CASE WHEN in_use = 0 THEN 1 ELSE 0 END), 0) as available
        FROM dids
    `).Scan(&totalDIDs, &usedDIDs, &availableDIDs)
    
    if err != nil {
        return nil, errors.Wrap(err, errors.ErrDatabase, "failed to get DID statistics")
    }
    
    total := int(totalDIDs.Int64)
    used := int(usedDIDs.Int64)
    available := int(availableDIDs.Int64)
    
    stats = map[string]interface{}{
        "total_dids":      total,
        "used_dids":       used,
        "available_dids":  available,
        "did_utilization": 0.0,
    }
    
    if total > 0 {
        stats["did_utilization"] = float64(used) / float64(total) * 100
    }
    
    // Cache for 30 seconds
    dm.cache.Set(ctx, cacheKey, stats, 30*time.Second)
    
    return stats, nil
}

// GetDIDDetails returns detailed information about a DID
func (dm *DIDManager) GetDIDDetails(ctx context.Context, did string) (map[string]interface{}, error) {
    query := `
        SELECT number, provider_name, in_use, destination,
               allocation_time, last_used_at, usage_count, country, city,
               monthly_cost, per_minute_cost, created_at, updated_at
        FROM dids
        WHERE number = ?`
    
    var details struct {
        Number         string
        ProviderName   string
        InUse          bool
        Destination    sql.NullString
        AllocationTime sql.NullTime
        LastUsedAt     sql.NullTime
        UsageCount     sql.NullInt64
        Country        sql.NullString
        City           sql.NullString
        MonthlyCost    float64
        PerMinuteCost  float64
        CreatedAt      time.Time
        UpdatedAt      time.Time
    }
    
    err := dm.db.QueryRowContext(ctx, query, did).Scan(
        &details.Number, &details.ProviderName, &details.InUse,
        &details.Destination, &details.AllocationTime,
        &details.LastUsedAt, &details.UsageCount, &details.Country,
        &details.City, &details.MonthlyCost, &details.PerMinuteCost,
        &details.CreatedAt, &details.UpdatedAt,
    )
    
    if err == sql.ErrNoRows {
        return nil, errors.New(errors.ErrDIDNotAvailable, "DID not found")
    }
    if err != nil {
        return nil, errors.Wrap(err, errors.ErrDatabase, "failed to get DID details")
    }
    
    result := map[string]interface{}{
        "number":         details.Number,
        "provider_name":  details.ProviderName,
        "in_use":         details.InUse,
        "monthly_cost":   details.MonthlyCost,
        "per_minute_cost": details.PerMinuteCost,
        "created_at":     details.CreatedAt,
        "updated_at":     details.UpdatedAt,
    }
    
    if details.Destination.Valid {
        result["destination"] = details.Destination.String
    }
    if details.AllocationTime.Valid {
        result["allocation_time"] = details.AllocationTime.Time
    }
    if details.LastUsedAt.Valid {
        result["last_used_at"] = details.LastUsedAt.Time
    }
    if details.UsageCount.Valid {
        result["usage_count"] = details.UsageCount.Int64
    }
    if details.Country.Valid {
        result["country"] = details.Country.String
    }
    if details.City.Valid {
        result["city"] = details.City.String
    }
    
    // Get current call if in use
    if details.InUse {
        if callID := dm.GetCallIDByDID(did); callID != "" {
            result["current_call_id"] = callID
        }
    }
    
    return result, nil
}

// GetAvailableDIDCount returns the count of available DIDs
func (dm *DIDManager) GetAvailableDIDCount(ctx context.Context, providerName string) (int, error) {
    var count int
    query := "SELECT COUNT(*) FROM dids WHERE in_use = 0"
    args := []interface{}{}
    
    if providerName != "" {
        query += " AND provider_name = ?"
        args = append(args, providerName)
    }
    
    err := dm.db.QueryRowContext(ctx, query, args...).Scan(&count)
    if err != nil {
        return 0, errors.Wrap(err, errors.ErrDatabase, "failed to count available DIDs")
    }
    
    return count, nil
}

// CleanupStaleDIDs releases DIDs that have been allocated for too long
func (dm *DIDManager) CleanupStaleDIDs(ctx context.Context, timeout time.Duration) error {
    query := `
        UPDATE dids 
        SET in_use = 0, 
            destination = NULL,
            allocation_time = NULL,
            released_at = NOW(),
            last_used_at = NOW(),
            updated_at = NOW()
        WHERE in_use = 1 
        AND allocation_time IS NOT NULL 
        AND allocation_time < DATE_SUB(NOW(), INTERVAL ? SECOND)`
    
    result, err := dm.db.ExecContext(ctx, query, int(timeout.Seconds()))
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to cleanup stale DIDs")
    }
    
    rows, _ := result.RowsAffected()
    if rows > 0 {
        logger.WithContext(ctx).WithField("count", rows).Info("Released stale DIDs")
        dm.cache.Delete(ctx, "did:stats")
    }
    
    return nil
}

// GetProviderDIDUtilization returns DID utilization by provider
func (dm *DIDManager) GetProviderDIDUtilization(ctx context.Context) ([]map[string]interface{}, error) {
    query := `
        SELECT 
            provider_name,
            COUNT(*) as total_dids,
            SUM(CASE WHEN in_use = 1 THEN 1 ELSE 0 END) as used_dids,
            SUM(CASE WHEN in_use = 0 THEN 1 ELSE 0 END) as available_dids,
            ROUND((SUM(CASE WHEN in_use = 1 THEN 1 ELSE 0 END) / COUNT(*)) * 100, 2) as utilization_percent
        FROM dids
        GROUP BY provider_name
        ORDER BY utilization_percent DESC`
    
    rows, err := dm.db.QueryContext(ctx, query)
    if err != nil {
        return nil, errors.Wrap(err, errors.ErrDatabase, "failed to get provider DID utilization")
    }
    defer rows.Close()
    
    var results []map[string]interface{}
    for rows.Next() {
        var provider string
        var total, used, available int
        var utilization float64
        
        if err := rows.Scan(&provider, &total, &used, &available, &utilization); err != nil {
            continue
        }
        
        results = append(results, map[string]interface{}{
            "provider_name":       provider,
            "total_dids":          total,
            "used_dids":           used,
            "available_dids":      available,
            "utilization_percent": utilization,
        })
    }
    
    return results, nil
}


