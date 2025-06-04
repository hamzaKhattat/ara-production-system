package provider

import (
    "context"
    "database/sql"
    "encoding/json"
    "fmt"
    "strings"
    "time"
    "net"
    
    "github.com/hamzaKhattat/ara-production-system/internal/ara"
    "github.com/hamzaKhattat/ara-production-system/internal/ami"
    "github.com/hamzaKhattat/ara-production-system/internal/models"
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
    "github.com/hamzaKhattat/ara-production-system/pkg/errors"
)

type Service struct {
    db          *sql.DB
    araManager  *ara.Manager
    amiManager  *ami.Manager
    cache       CacheInterface
}

type CacheInterface interface {
    Get(ctx context.Context, key string, dest interface{}) error
    Set(ctx context.Context, key string, value interface{}, expiration time.Duration) error
    Delete(ctx context.Context, keys ...string) error
}

func NewService(db *sql.DB, araManager *ara.Manager, amiManager *ami.Manager, cache CacheInterface) *Service {
    return &Service{
        db:         db,
        araManager: araManager,
        amiManager: amiManager,
        cache:      cache,
    }
}

func (s *Service) CreateProvider(ctx context.Context, provider *models.Provider) error {
    log := logger.WithContext(ctx)
    
    // Validate provider
    if err := s.validateProvider(provider); err != nil {
        return err
    }
    
    // Set defaults
    if provider.Transport == "" {
        provider.Transport = "udp"
    }
    if provider.AuthType == "" {
        provider.AuthType = "ip"
    }
    if provider.Port == 0 {
        provider.Port = 5060
    }
    if provider.Priority == 0 {
        provider.Priority = 10
    }
    if provider.Weight == 0 {
        provider.Weight = 1
    }
    
    // Start transaction
    tx, err := s.db.BeginTx(ctx, nil)
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to start transaction")
    }
    defer tx.Rollback()
    
    // Insert provider
    codecsJSON, _ := json.Marshal(provider.Codecs)
    metadataJSON, _ := json.Marshal(provider.Metadata)
    
    query := `
        INSERT INTO providers (
            name, type, host, port, username, password, auth_type,
            transport, codecs, max_channels, priority, weight,
            cost_per_minute, active, health_check_enabled, metadata
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    
    result, err := tx.ExecContext(ctx, query,
        provider.Name, provider.Type, provider.Host, provider.Port,
        provider.Username, provider.Password, provider.AuthType,
        provider.Transport, codecsJSON, provider.MaxChannels,
        provider.Priority, provider.Weight, provider.CostPerMinute,
        provider.Active, provider.HealthCheckEnabled, metadataJSON,
    )
    
    if err != nil {
        if strings.Contains(err.Error(), "Duplicate entry") {
            return errors.New(errors.ErrInternal, "provider already exists")
        }
        return errors.Wrap(err, errors.ErrDatabase, "failed to insert provider")
    }
    
    providerID, _ := result.LastInsertId()
    provider.ID = int(providerID)
    
    // Create ARA endpoint
    if err := s.araManager.CreateEndpoint(ctx, provider); err != nil {
        return errors.Wrap(err, errors.ErrInternal, "failed to create ARA endpoint")
    }
    
    // Commit transaction
    if err := tx.Commit(); err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to commit transaction")
    }
    
    // Reload PJSIP
    if s.amiManager != nil {
        if err := s.amiManager.ReloadPJSIP(); err != nil {
            log.WithError(err).Warn("Failed to reload PJSIP via AMI")
        }
    }
    
    // Clear cache
    s.cache.Delete(ctx, fmt.Sprintf("provider:%s", provider.Name))
    s.cache.Delete(ctx, fmt.Sprintf("providers:%s", provider.Type))
    
    log.WithFields(logger.WithFields{
        "provider_id": provider.ID,
        "name": provider.Name,
        "type": provider.Type,
    }).Info("Provider created successfully")
    
    return nil
}

func (s *Service) UpdateProvider(ctx context.Context, name string, updates map[string]interface{}) error {
    // Get existing provider
    provider, err := s.GetProvider(ctx, name)
    if err != nil {
        return err
    }
    
    // Build update query
    var setClause []string
    var args []interface{}
    
    for key, value := range updates {
        switch key {
        case "host", "port", "username", "password", "auth_type",
             "transport", "max_channels", "priority", "weight",
             "cost_per_minute", "active", "health_check_enabled":
            setClause = append(setClause, fmt.Sprintf("%s = ?", key))
            args = append(args, value)
        case "codecs":
            codecsJSON, _ := json.Marshal(value)
            setClause = append(setClause, "codecs = ?")
            args = append(args, codecsJSON)
        case "metadata":
            metadataJSON, _ := json.Marshal(value)
            setClause = append(setClause, "metadata = ?")
            args = append(args, metadataJSON)
        }
    }
    
    if len(setClause) == 0 {
        return nil // Nothing to update
    }
    
    // Add updated_at
    setClause = append(setClause, "updated_at = NOW()")
    
    // Add WHERE clause
    args = append(args, name)
    
    query := fmt.Sprintf("UPDATE providers SET %s WHERE name = ?", strings.Join(setClause, ", "))
    
    if _, err := s.db.ExecContext(ctx, query, args...); err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to update provider")
    }
    
    // Update ARA endpoint if needed
    needsARAUpdate := false
    for key := range updates {
        if key == "host" || key == "port" || key == "username" || 
           key == "password" || key == "auth_type" || key == "codecs" {
           needsARAUpdate = true
           break
       }
   }
   
   if needsARAUpdate {
       // Get updated provider
       updatedProvider, err := s.GetProvider(ctx, name)
       if err != nil {
           return err
       }
       
       if err := s.araManager.CreateEndpoint(ctx, updatedProvider); err != nil {
           return errors.Wrap(err, errors.ErrInternal, "failed to update ARA endpoint")
       }
       
       // Reload PJSIP
       if s.amiManager != nil {
           if err := s.amiManager.ReloadPJSIP(); err != nil {
               logger.WithContext(ctx).WithError(err).Warn("Failed to reload PJSIP")
           }
       }
   }
   
   // Clear cache
   s.cache.Delete(ctx, fmt.Sprintf("provider:%s", name))
   s.cache.Delete(ctx, fmt.Sprintf("providers:%s", provider.Type))
   
   return nil
}

func (s *Service) DeleteProvider(ctx context.Context, name string) error {
   // Check if provider is in use
   var inUse bool
   err := s.db.QueryRowContext(ctx, `
       SELECT EXISTS(
           SELECT 1 FROM provider_routes 
           WHERE inbound_provider = ? OR intermediate_provider = ? OR final_provider = ?
       )`, name, name, name).Scan(&inUse)
   
   if err != nil {
       return errors.Wrap(err, errors.ErrDatabase, "failed to check provider usage")
   }
   
   if inUse {
       return errors.New(errors.ErrInternal, "provider is in use by routes")
   }
   
   // Delete from database
   tx, err := s.db.BeginTx(ctx, nil)
   if err != nil {
       return errors.Wrap(err, errors.ErrDatabase, "failed to start transaction")
   }
   defer tx.Rollback()
   
   // Delete provider
   if _, err := tx.ExecContext(ctx, "DELETE FROM providers WHERE name = ?", name); err != nil {
       return errors.Wrap(err, errors.ErrDatabase, "failed to delete provider")
   }
   
   // Delete from ARA
   if err := s.araManager.DeleteEndpoint(ctx, name); err != nil {
       logger.WithContext(ctx).WithError(err).Warn("Failed to delete ARA endpoint")
   }
   
   if err := tx.Commit(); err != nil {
       return errors.Wrap(err, errors.ErrDatabase, "failed to commit transaction")
   }
   
   // Reload PJSIP
   if s.amiManager != nil {
       if err := s.amiManager.ReloadPJSIP(); err != nil {
           logger.WithContext(ctx).WithError(err).Warn("Failed to reload PJSIP")
       }
   }
   
   // Clear cache
   s.cache.Delete(ctx, fmt.Sprintf("provider:%s", name))
   
   return nil
}

func (s *Service) GetProvider(ctx context.Context, name string) (*models.Provider, error) {
   // Try cache first
   cacheKey := fmt.Sprintf("provider:%s", name)
   var provider models.Provider
   
   if err := s.cache.Get(ctx, cacheKey, &provider); err == nil {
       return &provider, nil
   }
   
   // Query database
   query := `
       SELECT id, name, type, host, port, username, password, auth_type,
              transport, codecs, max_channels, current_channels, priority,
              weight, cost_per_minute, active, health_check_enabled,
              last_health_check, health_status, metadata, created_at, updated_at
       FROM providers
       WHERE name = ?`
   
   var codecsJSON string
   var metadataJSON sql.NullString
   
   err := s.db.QueryRowContext(ctx, query, name).Scan(
       &provider.ID, &provider.Name, &provider.Type, &provider.Host, &provider.Port,
       &provider.Username, &provider.Password, &provider.AuthType, &provider.Transport,
       &codecsJSON, &provider.MaxChannels, &provider.CurrentChannels,
       &provider.Priority, &provider.Weight, &provider.CostPerMinute,
       &provider.Active, &provider.HealthCheckEnabled, &provider.LastHealthCheck,
       &provider.HealthStatus, &metadataJSON, &provider.CreatedAt, &provider.UpdatedAt,
   )
   
   if err == sql.ErrNoRows {
       return nil, errors.New(errors.ErrProviderNotFound, "provider not found")
   }
   if err != nil {
       return nil, errors.Wrap(err, errors.ErrDatabase, "failed to query provider")
   }
   
   // Parse JSON fields
   if codecsJSON != "" {
       json.Unmarshal([]byte(codecsJSON), &provider.Codecs)
   }
   if metadataJSON.Valid {
       json.Unmarshal([]byte(metadataJSON.String), &provider.Metadata)
   }
   
   // Cache for 5 minutes
   s.cache.Set(ctx, cacheKey, provider, 5*time.Minute)
   
   return &provider, nil
}

func (s *Service) ListProviders(ctx context.Context, filter map[string]interface{}) ([]*models.Provider, error) {
   query := `
       SELECT id, name, type, host, port, username, password, auth_type,
              transport, codecs, max_channels, current_channels, priority,
              weight, cost_per_minute, active, health_check_enabled,
              last_health_check, health_status, metadata, created_at, updated_at
       FROM providers
       WHERE 1=1`
   
   var args []interface{}
   
   if providerType, ok := filter["type"].(string); ok && providerType != "" {
       query += " AND type = ?"
       args = append(args, providerType)
   }
   
   if active, ok := filter["active"].(bool); ok {
       query += " AND active = ?"
       args = append(args, active)
   }
   
   query += " ORDER BY type, priority DESC, name"
   
   rows, err := s.db.QueryContext(ctx, query, args...)
   if err != nil {
       return nil, errors.Wrap(err, errors.ErrDatabase, "failed to query providers")
   }
   defer rows.Close()
   
   var providers []*models.Provider
   
   for rows.Next() {
       var provider models.Provider
       var codecsJSON string
       var metadataJSON sql.NullString
       
       err := rows.Scan(
           &provider.ID, &provider.Name, &provider.Type, &provider.Host, &provider.Port,
           &provider.Username, &provider.Password, &provider.AuthType, &provider.Transport,
           &codecsJSON, &provider.MaxChannels, &provider.CurrentChannels,
           &provider.Priority, &provider.Weight, &provider.CostPerMinute,
           &provider.Active, &provider.HealthCheckEnabled, &provider.LastHealthCheck,
           &provider.HealthStatus, &metadataJSON, &provider.CreatedAt, &provider.UpdatedAt,
       )
       
       if err != nil {
           logger.WithContext(ctx).WithError(err).Warn("Failed to scan provider")
           continue
       }
       
       // Parse JSON fields
       if codecsJSON != "" {
           json.Unmarshal([]byte(codecsJSON), &provider.Codecs)
       }
       if metadataJSON.Valid {
           json.Unmarshal([]byte(metadataJSON.String), &provider.Metadata)
       }
       
       providers = append(providers, &provider)
   }
   
   return providers, nil
}

func (s *Service) validateProvider(provider *models.Provider) error {
   if provider.Name == "" {
       return errors.New(errors.ErrInternal, "provider name is required")
   }
   
   if provider.Type == "" {
       return errors.New(errors.ErrInternal, "provider type is required")
   }
   
   validTypes := map[models.ProviderType]bool{
       models.ProviderTypeInbound:      true,
       models.ProviderTypeIntermediate: true,
       models.ProviderTypeFinal:        true,
   }
   
   if !validTypes[provider.Type] {
       return errors.New(errors.ErrInternal, "invalid provider type")
   }
   
   if provider.Host == "" {
       return errors.New(errors.ErrInternal, "provider host is required")
   }
   
   if provider.AuthType != "" {
       validAuthTypes := map[string]bool{
           "ip":          true,
           "credentials": true,
           "both":        true,
       }
       
       if !validAuthTypes[provider.AuthType] {
           return errors.New(errors.ErrInternal, "invalid auth type")
       }
       
       if provider.AuthType == "credentials" || provider.AuthType == "both" {
           if provider.Username == "" || provider.Password == "" {
               return errors.New(errors.ErrInternal, "username and password required for credential auth")
           }
       }
   }
   
   return nil
}

func (s *Service) TestProvider(ctx context.Context, name string) (*ProviderTestResult, error) {
   provider, err := s.GetProvider(ctx, name)
   if err != nil {
       return nil, err
   }
   
   result := &ProviderTestResult{
       ProviderName: name,
       Timestamp:    time.Now(),
       Tests:        make(map[string]TestResult),
   }
   
   // Test connectivity
   connTest := s.testConnectivity(provider)
   result.Tests["connectivity"] = connTest
   
   // Test OPTIONS if SIP
   if provider.Transport == "udp" || provider.Transport == "tcp" {
       optionsTest := s.testSIPOptions(provider)
       result.Tests["sip_options"] = optionsTest
   }
   
   // Calculate overall result
   result.Success = true
   for _, test := range result.Tests {
       if !test.Success {
           result.Success = false
           break
       }
   }
   
   return result, nil
}

type ProviderTestResult struct {
   ProviderName string                 `json:"provider_name"`
   Timestamp    time.Time              `json:"timestamp"`
   Success      bool                   `json:"success"`
   Tests        map[string]TestResult  `json:"tests"`
}

type TestResult struct {
   Success  bool          `json:"success"`
   Message  string        `json:"message"`
   Duration time.Duration `json:"duration"`
   Details  interface{}   `json:"details,omitempty"`
}

func (s *Service) testConnectivity(provider *models.Provider) TestResult {
   start := time.Now()
   
   conn, err := net.DialTimeout("tcp", fmt.Sprintf("%s:%d", provider.Host, provider.Port), 5*time.Second)
   duration := time.Since(start)
   
   if err != nil {
       return TestResult{
           Success:  false,
           Message:  fmt.Sprintf("Connection failed: %v", err),
           Duration: duration,
       }
   }
   
   conn.Close()
   
   return TestResult{
       Success:  true,
       Message:  "TCP connection successful",
       Duration: duration,
   }
}

func (s *Service) testSIPOptions(provider *models.Provider) TestResult {
   // This would implement SIP OPTIONS testing
   // For now, return a placeholder
   return TestResult{
       Success: true,
       Message: "SIP OPTIONS test not implemented",
   }
}
