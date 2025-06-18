package main

import (
    "context"
    "flag"
    "fmt"
    "os"
    "os/signal"
    "syscall"
    
    "github.com/spf13/cobra"
    "github.com/spf13/viper"
    "github.com/hamzaKhattat/ara-production-system/internal/agi"
    "github.com/hamzaKhattat/ara-production-system/internal/ami"
    "github.com/hamzaKhattat/ara-production-system/internal/ara"
    "github.com/hamzaKhattat/ara-production-system/internal/db"
    "github.com/hamzaKhattat/ara-production-system/internal/health"
    "github.com/hamzaKhattat/ara-production-system/internal/metrics"
    "github.com/hamzaKhattat/ara-production-system/internal/provider"
    "github.com/hamzaKhattat/ara-production-system/internal/router"
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
)

var (
    configFile string
    initDB     bool
    flushDB    bool
    agiMode    bool
    verbose    bool
    
    // Global services - these are shared with commands.go
    database     *db.DB
    cache        *db.Cache
    araManager   *ara.Manager
    amiManager   *ami.Manager
    routerSvc    *router.Router
    providerSvc  *provider.Service
    agiServer    *agi.Server
    healthSvc    *health.HealthService
    metricsSvc   *metrics.PrometheusMetrics
)

func main() {
    // Parse flags for server mode
    flag.StringVar(&configFile, "config", "", "Configuration file path")
    flag.BoolVar(&initDB, "init-db", false, "Initialize database (WARNING: Drops existing data if --flush is used)")
    flag.BoolVar(&flushDB, "flush", false, "Flush existing database before initialization")
    flag.BoolVar(&agiMode, "agi", false, "Run AGI server")
    flag.BoolVar(&verbose, "verbose", false, "Enable verbose logging")
    flag.Parse()
    
    // If flags are set, run in server mode
    if flag.NFlag() > 0 {
        runServerMode()
        return
    }
    
    // Otherwise, run CLI mode
    runCLI()
}

func runServerMode() {
    ctx := context.Background()
    
    // Load configuration
    if err := loadConfig(); err != nil {
        fmt.Fprintf(os.Stderr, "Failed to load config: %v\n", err)
        os.Exit(1)
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
    
    if verbose {
        logConfig.Level = "debug"
    }
    
    if err := logger.Init(logConfig); err != nil {
        fmt.Fprintf(os.Stderr, "Failed to initialize logger: %v\n", err)
        os.Exit(1)
    }
    
    // Initialize database connection
    if err := initializeDatabase(ctx); err != nil {
        logger.Fatal("Failed to initialize database", "error", err)
    }
    
    // Initialize database schema if requested
    if initDB {
        logger.Info("Initializing database schema")
        
        if flushDB {
            logger.Warn("FLUSH mode enabled - All existing data will be deleted!")
            fmt.Print("\nWARNING: This will DELETE ALL existing data. Continue? [y/N]: ")
            var response string
            fmt.Scanln(&response)
            if response != "y" && response != "Y" {
                logger.Info("Database initialization cancelled")
                return
            }
        }
        
        // Initialize the database schema
        if err := db.InitializeDatabase(ctx, database.DB, flushDB); err != nil {
            logger.Fatal("Failed to initialize database schema", "error", err)
        }
        
        // Create initial dialplan through ARA manager
        if err := araManager.CreateDialplan(ctx); err != nil {
            logger.WithError(err).Warn("Failed to create dialplan through ARA manager")
        }
        
        // Add sample data
        if err := addSampleData(ctx); err != nil {
            logger.WithError(err).Warn("Failed to add sample data")
        }
        
        logger.Info("Database initialization completed successfully")
        logger.Info("Next steps:")
        logger.Info("1. Restart Asterisk: systemctl restart asterisk")
        logger.Info("2. Start AGI server: ./bin/router -agi")
        logger.Info("3. Add providers: ./bin/router provider add <name> -t <type> --host <ip>")
        return
    }
    
    // Run AGI server if requested
    if agiMode {
        runAGIServer(ctx)
        return
    }
    
    // Otherwise show usage
    fmt.Println("Usage:")
    fmt.Println("  router [command] [flags]")
    fmt.Println("  router -agi              # Run AGI server")
    fmt.Println("  router -init-db          # Initialize database")
    fmt.Println("  router -init-db -flush   # Flush and reinitialize database")
    fmt.Println("")
    fmt.Println("Run 'router --help' for more information")
}

func runCLI() {
    rootCmd := &cobra.Command{
        Use:   "router",
        Short: "Asterisk ARA Dynamic Call Router",
        Long:  "Production-level dynamic call routing system with full ARA integration",
    }
    
    // Add commands
    rootCmd.AddCommand(
        createProviderCommands(),
        createGroupCommands(), 
        createDIDCommands(),
        createRouteCommands(),
        createStatsCommand(),
        createLoadBalancerCommand(),
        createCallsCommand(),
        createMonitorCommand(),
    )
    
    if err := rootCmd.Execute(); err != nil {
        fmt.Fprintf(os.Stderr, "Error: %v\n", err)
        os.Exit(1)
    }
}

func runAGIServer(ctx context.Context) {
    logger.Info("Starting AGI server")
    
    // Initialize AGI server
    agiConfig := agi.Config{
        ListenAddress:   viper.GetString("agi.listen_address"),
        Port:            viper.GetInt("agi.port"),
        MaxConnections:  viper.GetInt("agi.max_connections"),
        ReadTimeout:     viper.GetDuration("agi.read_timeout"),
        WriteTimeout:    viper.GetDuration("agi.write_timeout"),
        IdleTimeout:     viper.GetDuration("agi.idle_timeout"),
        ShutdownTimeout: viper.GetDuration("agi.shutdown_timeout"),
    }
    
    agiServer = agi.NewServer(routerSvc, agiConfig, metricsSvc)
    
    // Handle shutdown
    sigChan := make(chan os.Signal, 1)
    signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
    
    go func() {
        if err := agiServer.Start(); err != nil {
            logger.Fatal("AGI server failed", "error", err)
        }
    }()
    
    <-sigChan
    logger.Info("Shutting down AGI server")
    
    if err := agiServer.Stop(); err != nil {
        logger.WithError(err).Error("Error stopping AGI server")
    }
    
    // Cleanup
    if amiManager != nil {
        amiManager.Close()
    }
    
    if healthSvc != nil {
        healthSvc.Stop()
    }
    
    logger.Info("Shutdown complete")
}

func addSampleData(ctx context.Context) error {
    log := logger.WithContext(ctx)
    log.Info("Adding sample data...")
    
    // Check if we already have data
    var count int
    if err := database.DB.QueryRowContext(ctx, "SELECT COUNT(*) FROM providers").Scan(&count); err == nil && count > 0 {
        log.Info("Sample data already exists, skipping...")
        return nil
    }
    
    // Add sample providers
    sampleProviders := []string{
        `INSERT INTO providers (name, type, host, port, auth_type, active, transport, codecs) VALUES 
         ('s1', 'inbound', '10.0.0.1', 5060, 'ip', 1, 'udp', '["ulaw","alaw"]'),
         ('s3-intermediate', 'intermediate', '10.0.0.3', 5060, 'ip', 1, 'udp', '["ulaw","alaw"]'),
         ('s4-final', 'final', '10.0.0.4', 5060, 'ip', 1, 'udp', '["ulaw","alaw"]')`,
    }
    
    for _, query := range sampleProviders {
        if _, err := database.DB.ExecContext(ctx, query); err != nil {
            log.WithError(err).Warn("Failed to insert sample providers")
        }
    }
    
    // Add sample DIDs
    sampleDIDs := `
        INSERT INTO dids (number, provider_name, provider_id, in_use, country, city, monthly_cost, per_minute_cost) VALUES
        ('584148757547', 's1', 1, 0, 'VE', 'Caracas', 10.00, 0.01),
        ('584249726299', 's1', 1, 0, 'VE', 'Caracas', 10.00, 0.01),
        ('584167000000', 's1', 1, 0, 'VE', 'Caracas', 10.00, 0.01),
        ('584267000011', 's1', 1, 0, 'VE', 'Caracas', 10.00, 0.01),
        ('15551234001', 's3-intermediate', 2, 0, 'US', 'New York', 12.00, 0.012),
        ('15551234002', 's3-intermediate', 2, 0, 'US', 'New York', 12.00, 0.012),
        ('15551234003', 's3-intermediate', 2, 0, 'US', 'Chicago', 12.00, 0.012),
        ('15551234004', 's4-final', 3, 0, 'US', 'Miami', 15.00, 0.015),
        ('15551234005', 's4-final', 3, 0, 'US', 'Miami', 15.00, 0.015)`
    
    if _, err := database.DB.ExecContext(ctx, sampleDIDs); err != nil {
        log.WithError(err).Warn("Failed to insert sample DIDs")
    }
    
    // Add sample route
    sampleRoute := `
        INSERT INTO provider_routes (name, inbound_provider, intermediate_provider, final_provider, enabled) 
        VALUES ('main-route', 's1', 's3-intermediate', 's4-final', 1)`
    
    if _, err := database.DB.ExecContext(ctx, sampleRoute); err != nil {
        log.WithError(err).Warn("Failed to insert sample route")
    }
    
    // Create ARA endpoints for providers
    providers, err := providerSvc.ListProviders(ctx, nil)
    if err == nil {
        for _, p := range providers {
            if err := araManager.CreateEndpoint(ctx, p); err != nil {
                log.WithError(err).WithField("provider", p.Name).Warn("Failed to create ARA endpoint")
            }
        }
    }
    
    log.Info("Sample data added successfully")
    return nil
}
