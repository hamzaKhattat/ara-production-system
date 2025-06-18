package main

import (
    "context"
    "fmt"
    "time"
    
    "github.com/spf13/viper"
    "github.com/hamzaKhattat/ara-production-system/internal/ami"
    "github.com/hamzaKhattat/ara-production-system/internal/ara"
    "github.com/hamzaKhattat/ara-production-system/internal/db"
    "github.com/hamzaKhattat/ara-production-system/internal/health"
    "github.com/hamzaKhattat/ara-production-system/internal/metrics"
    "github.com/hamzaKhattat/ara-production-system/internal/provider"
    "github.com/hamzaKhattat/ara-production-system/internal/router"
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
)

func loadConfig() error {
    if configFile != "" {
        viper.SetConfigFile(configFile)
    } else {
        viper.SetConfigName("production")
        viper.SetConfigType("yaml")
        viper.AddConfigPath("./configs")
        viper.AddConfigPath("/etc/asterisk-router")
    }
    
    // Environment variables
    viper.SetEnvPrefix("ARA_ROUTER")
    viper.AutomaticEnv()
    
    // Defaults
    setDefaults()
    
    if err := viper.ReadInConfig(); err != nil {
        if _, ok := err.(viper.ConfigFileNotFoundError); !ok {
            return err
        }
        logger.Warn("No config file found, using defaults and environment")
    }
    
    return nil
}

func setDefaults() {
    // Database defaults
    viper.SetDefault("database.driver", "mysql")
    viper.SetDefault("database.host", "localhost")
    viper.SetDefault("database.port", 3306)
    viper.SetDefault("database.username", "asterisk")
    viper.SetDefault("database.password", "asterisk")
    viper.SetDefault("database.database", "asterisk_ara")
    viper.SetDefault("database.max_open_conns", 25)
    viper.SetDefault("database.max_idle_conns", 5)
    viper.SetDefault("database.conn_max_lifetime", "5m")
    
    // AGI defaults
    viper.SetDefault("agi.listen_address", "0.0.0.0")
    viper.SetDefault("agi.port", 4573)
    viper.SetDefault("agi.max_connections", 1000)
    viper.SetDefault("agi.read_timeout", "30s")
    viper.SetDefault("agi.write_timeout", "30s")
    viper.SetDefault("agi.idle_timeout", "120s")
    viper.SetDefault("agi.shutdown_timeout", "30s")
    
    // Router defaults
    viper.SetDefault("router.did_allocation_timeout", "5s")
    viper.SetDefault("router.call_cleanup_interval", "5m")
    viper.SetDefault("router.stale_call_timeout", "30m")
    viper.SetDefault("router.verification.enabled", true)
    
    // Monitoring defaults
    viper.SetDefault("monitoring.metrics.enabled", true)
    viper.SetDefault("monitoring.metrics.port", 9090)
    viper.SetDefault("monitoring.health.enabled", true)
    viper.SetDefault("monitoring.health.port", 8080)
    viper.SetDefault("monitoring.logging.level", "info")
    viper.SetDefault("monitoring.logging.format", "json")
}

func initializeDatabase(ctx context.Context) error {
    // Database configuration
    dbConfig := db.Config{
        Driver:          viper.GetString("database.driver"),
        Host:            viper.GetString("database.host"),
        Port:            viper.GetInt("database.port"),
        Username:        viper.GetString("database.username"),
        Password:        viper.GetString("database.password"),
        Database:        viper.GetString("database.database"),
        MaxOpenConns:    viper.GetInt("database.max_open_conns"),
        MaxIdleConns:    viper.GetInt("database.max_idle_conns"),
        ConnMaxLifetime: viper.GetDuration("database.conn_max_lifetime"),
        RetryAttempts:   3,
        RetryDelay:      time.Second,
    }
    
    // Initialize database
    if err := db.Initialize(dbConfig); err != nil {
        return err
    }
    
    database = db.GetDB()
    
    // Initialize cache
    cacheConfig := db.CacheConfig{
        Host:         viper.GetString("redis.host"),
        Port:         viper.GetInt("redis.port"),
        Password:     viper.GetString("redis.password"),
        DB:           viper.GetInt("redis.db"),
        PoolSize:     viper.GetInt("redis.pool_size"),
        MinIdleConns: viper.GetInt("redis.min_idle_conns"),
        MaxRetries:   viper.GetInt("redis.max_retries"),
    }
    
    if err := db.InitializeCache(cacheConfig, "ara-router"); err != nil {
        logger.WithError(err).Warn("Failed to initialize Redis cache, using memory cache")
    }
    
    cache = db.GetCache()
    
    // Initialize ARA manager
    araManager = ara.NewManager(database.DB, cache)
    
    // Initialize AMI manager if configured
    if viper.GetString("asterisk.ami.host") != "" {
        amiConfig := ami.Config{
            Host:              viper.GetString("asterisk.ami.host"),
            Port:              viper.GetInt("asterisk.ami.port"),
            Username:          viper.GetString("asterisk.ami.username"),
            Password:          viper.GetString("asterisk.ami.password"),
            ReconnectInterval: viper.GetDuration("asterisk.ami.reconnect_interval"),
            PingInterval:      viper.GetDuration("asterisk.ami.ping_interval"),
            ActionTimeout:     30 * time.Second, // Ensure we have a good timeout
            BufferSize:        1000,
        }
        
        amiManager = ami.NewManager(amiConfig)
        
        // Try to connect with retries
        ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
        err := amiManager.ConnectWithRetry(ctx, 3)
        cancel()
        
        if err != nil {
            logger.WithError(err).Warn("Failed to connect to AMI initially, will retry in background")
            // Start background connection attempts
            amiManager.ConnectOptional(context.Background())
        } else {
            logger.Info("AMI connected successfully")
        }
    } else {
        logger.Warn("AMI not configured, some features will be unavailable")
    }
    
    // Initialize metrics
    metricsSvc = metrics.NewPrometheusMetrics()
    
    // Initialize router
    routerConfig := router.Config{
        DIDAllocationTimeout: viper.GetDuration("router.did_allocation_timeout"),
        CallCleanupInterval:  viper.GetDuration("router.call_cleanup_interval"),
        StaleCallTimeout:     viper.GetDuration("router.stale_call_timeout"),
        MaxRetries:           viper.GetInt("router.max_retries"),
        VerificationEnabled:  viper.GetBool("router.verification.enabled"),
        StrictMode:           viper.GetBool("router.verification.strict_mode"),
    }
    
    routerSvc = router.NewRouter(database.DB, cache, metricsSvc, routerConfig)
    
    // Initialize provider service
    providerSvc = provider.NewService(database.DB, araManager, amiManager, cache)
    
    // Initialize health service
    if viper.GetBool("monitoring.health.enabled") {
        healthPort := viper.GetInt("monitoring.health.port")
        healthSvc = health.NewHealthService(healthPort)
        
        // Register health checks
        healthSvc.RegisterLivenessCheck("database", health.CheckFunc(func(ctx context.Context) error {
            if !database.IsHealthy() {
                return fmt.Errorf("database not healthy")
            }
            return database.PingContext(ctx)
        }))
        
        healthSvc.RegisterReadinessCheck("database", health.CheckFunc(func(ctx context.Context) error {
            return database.PingContext(ctx)
        }))
        
        if amiManager != nil {
            healthSvc.RegisterReadinessCheck("ami", health.CheckFunc(func(ctx context.Context) error {
                if !amiManager.IsConnected() {
                    return fmt.Errorf("AMI not connected")
                }
                _, err := amiManager.SendAction(ami.Action{Action: "Ping"})
                return err
            }))
        }
        
        go healthSvc.Start()
    }
    
    // Start metrics server
    if viper.GetBool("monitoring.metrics.enabled") {
        metricsPort := viper.GetInt("monitoring.metrics.port")
        go metricsSvc.ServeHTTP(metricsPort)
    }
    
    return nil
}

/*func initializeForCLI(ctx context.Context) error {
    if err := loadConfig(); err != nil {
        return fmt.Errorf("failed to load config: %v", err)
    }
    
    // Initialize logger
    logConfig := logger.Config{
        Level:  viper.GetString("monitoring.logging.level"),
        Format: viper.GetString("monitoring.logging.format"),
        Output: viper.GetString("monitoring.logging.output"),
        File: logger.FileConfig{
            Enabled:    viper.GetBool("monitoring.logging.file.enabled"),
            Path:       viper.GetString("monitoring.logging.file.path"),
            MaxSize:    viper.GetInt("monitoring.logging.file.max_size"),
            MaxBackups: viper.GetInt("monitoring.logging.file.max_backups"),
            MaxAge:     viper.GetInt("monitoring.logging.file.max_age"),
            Compress:   viper.GetBool("monitoring.logging.file.compress"),
        },
    }
    
    // Set defaults if not configured
    if logConfig.Level == "" {
        logConfig.Level = "info"
    }
    if logConfig.Format == "" {
        logConfig.Format = "text"  // Use text format for CLI
    }
    
    if err := logger.Init(logConfig); err != nil {
        return fmt.Errorf("failed to initialize logger: %v", err)
    }
    
    if err := initializeDatabase(ctx); err != nil {
        return fmt.Errorf("failed to initialize database: %v", err)
    }
    
    return nil
}*/
