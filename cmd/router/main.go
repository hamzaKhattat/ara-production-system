package main

import (
   "context"
   "flag"
   "fmt"
   "os"
   "os/signal"
   "syscall"
   "time"
   
   "github.com/spf13/cobra"
   "github.com/spf13/viper"
   "github.com/hamzaKhattat/ara-production-system/internal/agi"
   "github.com/hamzaKhattat/ara-production-system/internal/ami"
   "github.com/hamzaKhattat/ara-production-system/internal/ara"
   "github.com/hamzaKhattat/ara-production-system/internal/config"
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
   agiMode    bool
   verbose    bool
   
   // Global services
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
   flag.BoolVar(&initDB, "init-db", false, "Initialize database")
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
   
   // Initialize database
   if err := initializeDatabase(ctx); err != nil {
       logger.Fatal("Failed to initialize database", "error", err)
   }
   
   // Initialize database if requested
   if initDB {
       logger.Info("Initializing database schema")
       if err := db.RunMigrations(database.DB); err != nil {
           logger.Fatal("Failed to run migrations", "error", err)
       }
       
       // Create initial dialplan
       if err := araManager.CreateDialplan(ctx); err != nil {
           logger.Fatal("Failed to create dialplan", "error", err)
       }
       
       logger.Info("Database initialization completed")
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
       }
       
       amiManager = ami.NewManager(amiConfig)
       if err := amiManager.Connect(ctx); err != nil {
           logger.WithError(err).Warn("Failed to connect to AMI")
       }
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
