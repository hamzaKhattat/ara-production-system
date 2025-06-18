package config

import (
    "fmt"
    "strings"
    "time"
    
    "github.com/spf13/viper"
)

// Config represents the complete application configuration
type Config struct {
    App         AppConfig         `mapstructure:"app"`
    Database    DatabaseConfig    `mapstructure:"database"`
    Redis       RedisConfig       `mapstructure:"redis"`
    AGI         AGIConfig         `mapstructure:"agi"`
    Asterisk    AsteriskConfig    `mapstructure:"asterisk"`
    Router      RouterConfig      `mapstructure:"router"`
    Monitoring  MonitoringConfig  `mapstructure:"monitoring"`
    Security    SecurityConfig    `mapstructure:"security"`
    Performance PerformanceConfig `mapstructure:"performance"`
}

// AppConfig holds application-level configuration
type AppConfig struct {
    Name        string `mapstructure:"name"`
    Version     string `mapstructure:"version"`
    Environment string `mapstructure:"environment"`
    Debug       bool   `mapstructure:"debug"`
}

// DatabaseConfig holds database configuration
type DatabaseConfig struct {
    Driver          string        `mapstructure:"driver"`
    Host            string        `mapstructure:"host"`
    Port            int           `mapstructure:"port"`
    Username        string        `mapstructure:"username"`
    Password        string        `mapstructure:"password"`
    Database        string        `mapstructure:"database"`
    MaxOpenConns    int           `mapstructure:"max_open_conns"`
    MaxIdleConns    int           `mapstructure:"max_idle_conns"`
    ConnMaxLifetime time.Duration `mapstructure:"conn_max_lifetime"`
    RetryAttempts   int           `mapstructure:"retry_attempts"`
    RetryDelay      time.Duration `mapstructure:"retry_delay"`
    SSLMode         string        `mapstructure:"ssl_mode"`
    Charset         string        `mapstructure:"charset"`
}

// RedisConfig holds Redis cache configuration
type RedisConfig struct {
    Host         string        `mapstructure:"host"`
    Port         int           `mapstructure:"port"`
    Password     string        `mapstructure:"password"`
    DB           int           `mapstructure:"db"`
    PoolSize     int           `mapstructure:"pool_size"`
    MinIdleConns int           `mapstructure:"min_idle_conns"`
    MaxRetries   int           `mapstructure:"max_retries"`
    DialTimeout  time.Duration `mapstructure:"dial_timeout"`
    ReadTimeout  time.Duration `mapstructure:"read_timeout"`
    WriteTimeout time.Duration `mapstructure:"write_timeout"`
    PoolTimeout  time.Duration `mapstructure:"pool_timeout"`
    IdleTimeout  time.Duration `mapstructure:"idle_timeout"`
}

// AGIConfig holds AGI server configuration
type AGIConfig struct {
    ListenAddress    string        `mapstructure:"listen_address"`
    Port             int           `mapstructure:"port"`
    MaxConnections   int           `mapstructure:"max_connections"`
    ReadTimeout      time.Duration `mapstructure:"read_timeout"`
    WriteTimeout     time.Duration `mapstructure:"write_timeout"`
    IdleTimeout      time.Duration `mapstructure:"idle_timeout"`
    ShutdownTimeout  time.Duration `mapstructure:"shutdown_timeout"`
    BufferSize       int           `mapstructure:"buffer_size"`
    EnableTLS        bool          `mapstructure:"enable_tls"`
    TLSCertFile      string        `mapstructure:"tls_cert_file"`
    TLSKeyFile       string        `mapstructure:"tls_key_file"`
}

// AsteriskConfig holds Asterisk-related configuration
type AsteriskConfig struct {
    AMI AMIConfig `mapstructure:"ami"`
    ARA ARAConfig `mapstructure:"ara"`
}

// AMIConfig holds Asterisk Manager Interface configuration
type AMIConfig struct {
    Enabled             bool          `mapstructure:"enabled"`
    Host                string        `mapstructure:"host"`
    Port                int           `mapstructure:"port"`
    Username            string        `mapstructure:"username"`
    Password            string        `mapstructure:"password"`
    ReconnectInterval   time.Duration `mapstructure:"reconnect_interval"`
    PingInterval        time.Duration `mapstructure:"ping_interval"`
    ActionTimeout       time.Duration `mapstructure:"action_timeout"`
    ConnectTimeout      time.Duration `mapstructure:"connect_timeout"`
    EventBufferSize     int           `mapstructure:"event_buffer_size"`
}

// ARAConfig holds Asterisk Realtime Architecture configuration
type ARAConfig struct {
    TransportReloadInterval time.Duration `mapstructure:"transport_reload_interval"`
    EndpointCacheTTL        time.Duration `mapstructure:"endpoint_cache_ttl"`
    DialplanCacheTTL        time.Duration `mapstructure:"dialplan_cache_ttl"`
    AORCacheTTL             time.Duration `mapstructure:"aor_cache_ttl"`
    AuthCacheTTL            time.Duration `mapstructure:"auth_cache_ttl"`
    EnableCache             bool          `mapstructure:"enable_cache"`
    SyncInterval            time.Duration `mapstructure:"sync_interval"`
}

// RouterConfig holds call routing configuration
type RouterConfig struct {
    DIDAllocationTimeout time.Duration        `mapstructure:"did_allocation_timeout"`
    CallCleanupInterval  time.Duration        `mapstructure:"call_cleanup_interval"`
    StaleCallTimeout     time.Duration        `mapstructure:"stale_call_timeout"`
    MaxRetries           int                  `mapstructure:"max_retries"`
    RetryBackoff         string               `mapstructure:"retry_backoff"`
    Verification         VerificationConfig   `mapstructure:"verification"`
    Recording            RecordingConfig      `mapstructure:"recording"`
    LoadBalancer         LoadBalancerConfig   `mapstructure:"load_balancer"`
}

// VerificationConfig holds call verification settings
type VerificationConfig struct {
    Enabled     bool `mapstructure:"enabled"`
    StrictMode  bool `mapstructure:"strict_mode"`
    LogFailures bool `mapstructure:"log_failures"`
    Timeout     time.Duration `mapstructure:"timeout"`
}

// RecordingConfig holds call recording settings
type RecordingConfig struct {
    Enabled    bool   `mapstructure:"enabled"`
    Path       string `mapstructure:"path"`
    Format     string `mapstructure:"format"`
    MixType    string `mapstructure:"mix_type"`
    MaxSize    int64  `mapstructure:"max_size"`
    MaxAge     int    `mapstructure:"max_age"`
}

// LoadBalancerConfig holds load balancing configuration
type LoadBalancerConfig struct {
    DefaultMode           string        `mapstructure:"default_mode"`
    HealthCheckInterval   time.Duration `mapstructure:"health_check_interval"`
    FailoverTimeout       time.Duration `mapstructure:"failover_timeout"`
    MaxFailures           int           `mapstructure:"max_failures"`
    RecoveryTime          time.Duration `mapstructure:"recovery_time"`
}

// MonitoringConfig holds monitoring and observability configuration
type MonitoringConfig struct {
    Metrics MetricsConfig `mapstructure:"metrics"`
    Health  HealthConfig  `mapstructure:"health"`
    Logging LoggingConfig `mapstructure:"logging"`
    Tracing TracingConfig `mapstructure:"tracing"`
}

// MetricsConfig holds metrics configuration
type MetricsConfig struct {
    Enabled          bool          `mapstructure:"enabled"`
    Port             int           `mapstructure:"port"`
    Path             string        `mapstructure:"path"`
    Namespace        string        `mapstructure:"namespace"`
    Subsystem        string        `mapstructure:"subsystem"`
    CollectInterval  time.Duration `mapstructure:"collect_interval"`
}

// HealthConfig holds health check configuration
type HealthConfig struct {
    Enabled             bool          `mapstructure:"enabled"`
    Port                int           `mapstructure:"port"`
    LivenessPath        string        `mapstructure:"liveness_path"`
    ReadinessPath       string        `mapstructure:"readiness_path"`
    CheckInterval       time.Duration `mapstructure:"check_interval"`
    CheckTimeout        time.Duration `mapstructure:"check_timeout"`
}

// LoggingConfig holds logging configuration
type LoggingConfig struct {
    Level      string          `mapstructure:"level"`
    Format     string          `mapstructure:"format"`
    Output     string          `mapstructure:"output"`
    File       FileLogConfig   `mapstructure:"file"`
    Fields     map[string]interface{} `mapstructure:"fields"`
}

// FileLogConfig holds file-based logging configuration
type FileLogConfig struct {
    Enabled    bool   `mapstructure:"enabled"`
    Path       string `mapstructure:"path"`
    MaxSize    int    `mapstructure:"max_size"`
    MaxBackups int    `mapstructure:"max_backups"`
    MaxAge     int    `mapstructure:"max_age"`
    Compress   bool   `mapstructure:"compress"`
}

// TracingConfig holds distributed tracing configuration
type TracingConfig struct {
    Enabled      bool    `mapstructure:"enabled"`
    Provider     string  `mapstructure:"provider"`
    Endpoint     string  `mapstructure:"endpoint"`
    ServiceName  string  `mapstructure:"service_name"`
    SampleRate   float64 `mapstructure:"sample_rate"`
}

// SecurityConfig holds security-related configuration
type SecurityConfig struct {
    TLS       TLSConfig       `mapstructure:"tls"`
    API       APIConfig       `mapstructure:"api"`
    RateLimit RateLimitConfig `mapstructure:"rate_limit"`
}

// TLSConfig holds TLS configuration
type TLSConfig struct {
    Enabled            bool     `mapstructure:"enabled"`
    CertFile           string   `mapstructure:"cert_file"`
    KeyFile            string   `mapstructure:"key_file"`
    CAFile             string   `mapstructure:"ca_file"`
    InsecureSkipVerify bool     `mapstructure:"insecure_skip_verify"`
    MinVersion         string   `mapstructure:"min_version"`
    CipherSuites       []string `mapstructure:"cipher_suites"`
}

// APIConfig holds API configuration
type APIConfig struct {
    Enabled       bool     `mapstructure:"enabled"`
    Port          int      `mapstructure:"port"`
    AuthToken     string   `mapstructure:"auth_token"`
    RateLimit     int      `mapstructure:"rate_limit"`
    CORSEnabled   bool     `mapstructure:"cors_enabled"`
    CORSOrigins   []string `mapstructure:"cors_origins"`
    ReadTimeout   time.Duration `mapstructure:"read_timeout"`
    WriteTimeout  time.Duration `mapstructure:"write_timeout"`
}

// RateLimitConfig holds rate limiting configuration
type RateLimitConfig struct {
    Enabled         bool          `mapstructure:"enabled"`
    RequestsPerMin  int           `mapstructure:"requests_per_min"`
    BurstSize       int           `mapstructure:"burst_size"`
    CleanupInterval time.Duration `mapstructure:"cleanup_interval"`
}

// PerformanceConfig holds performance tuning configuration
type PerformanceConfig struct {
    WorkerPoolSize   int           `mapstructure:"worker_pool_size"`
    QueueSize        int           `mapstructure:"queue_size"`
    BatchSize        int           `mapstructure:"batch_size"`
    GCInterval       time.Duration `mapstructure:"gc_interval"`
    MaxProcs         int           `mapstructure:"max_procs"`
    EnableProfiling  bool          `mapstructure:"enable_profiling"`
    ProfilingPort    int           `mapstructure:"profiling_port"`
}

// Load loads configuration from file and environment
func Load(configFile string) (*Config, error) {
    if configFile != "" {
        viper.SetConfigFile(configFile)
    } else {
        viper.SetConfigName("config")
        viper.SetConfigType("yaml")
        viper.AddConfigPath("./configs")
        viper.AddConfigPath("/etc/asterisk-ara-router")
        viper.AddConfigPath(".")
    }
    
    // Set environment variable support
    viper.SetEnvPrefix("ARA_ROUTER")
    viper.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))
    viper.AutomaticEnv()
    
    // Set defaults
    setDefaults()
    
    // Read configuration
    if err := viper.ReadInConfig(); err != nil {
        if _, ok := err.(viper.ConfigFileNotFoundError); !ok {
            return nil, fmt.Errorf("failed to read config file: %w", err)
        }
        // Config file not found; use defaults and environment
    }
    
    // Unmarshal into config struct
    var config Config
    if err := viper.Unmarshal(&config); err != nil {
        return nil, fmt.Errorf("failed to unmarshal config: %w", err)
    }
    
    // Validate configuration
    if err := config.Validate(); err != nil {
        return nil, fmt.Errorf("invalid configuration: %w", err)
    }
    
    return &config, nil
}

// setDefaults sets default configuration values
func setDefaults() {
    // App defaults
    viper.SetDefault("app.name", "asterisk-ara-router")
    viper.SetDefault("app.version", "2.0.0")
    viper.SetDefault("app.environment", "development")
    viper.SetDefault("app.debug", false)
    
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
    viper.SetDefault("database.retry_attempts", 3)
    viper.SetDefault("database.retry_delay", "1s")
    viper.SetDefault("database.charset", "utf8mb4")
    
    // Redis defaults
    viper.SetDefault("redis.host", "localhost")
    viper.SetDefault("redis.port", 6379)
    viper.SetDefault("redis.db", 0)
    viper.SetDefault("redis.pool_size", 10)
    viper.SetDefault("redis.min_idle_conns", 5)
    viper.SetDefault("redis.max_retries", 3)
    viper.SetDefault("redis.dial_timeout", "5s")
    viper.SetDefault("redis.read_timeout", "3s")
    viper.SetDefault("redis.write_timeout", "3s")
    
    // AGI defaults
    viper.SetDefault("agi.listen_address", "0.0.0.0")
    viper.SetDefault("agi.port", 4573)
    viper.SetDefault("agi.max_connections", 1000)
    viper.SetDefault("agi.read_timeout", "30s")
    viper.SetDefault("agi.write_timeout", "30s")
    viper.SetDefault("agi.idle_timeout", "120s")
    viper.SetDefault("agi.shutdown_timeout", "30s")
    viper.SetDefault("agi.buffer_size", 4096)
    
    // AMI defaults
    viper.SetDefault("asterisk.ami.enabled", true)
    viper.SetDefault("asterisk.ami.host", "localhost")
    viper.SetDefault("asterisk.ami.port", 5038)
    viper.SetDefault("asterisk.ami.reconnect_interval", "5s")
    viper.SetDefault("asterisk.ami.ping_interval", "30s")
    viper.SetDefault("asterisk.ami.action_timeout", "10s")
    viper.SetDefault("asterisk.ami.connect_timeout", "10s")
    viper.SetDefault("asterisk.ami.event_buffer_size", 1000)
    
    // ARA defaults
    viper.SetDefault("asterisk.ara.transport_reload_interval", "60s")
    viper.SetDefault("asterisk.ara.endpoint_cache_ttl", "300s")
    viper.SetDefault("asterisk.ara.dialplan_cache_ttl", "600s")
    viper.SetDefault("asterisk.ara.enable_cache", true)
    
    // Router defaults
    viper.SetDefault("router.did_allocation_timeout", "5s")
    viper.SetDefault("router.call_cleanup_interval", "5m")
    viper.SetDefault("router.stale_call_timeout", "30m")
    viper.SetDefault("router.max_retries", 3)
    viper.SetDefault("router.retry_backoff", "exponential")
    viper.SetDefault("router.verification.enabled", true)
    viper.SetDefault("router.verification.strict_mode", false)
    viper.SetDefault("router.verification.log_failures", true)
    viper.SetDefault("router.recording.enabled", false)
    viper.SetDefault("router.recording.format", "wav")
    viper.SetDefault("router.recording.mix_type", "both")
    viper.SetDefault("router.load_balancer.default_mode", "round_robin")
    viper.SetDefault("router.load_balancer.health_check_interval", "30s")
    
    // Monitoring defaults
    viper.SetDefault("monitoring.metrics.enabled", true)
    viper.SetDefault("monitoring.metrics.port", 9090)
    viper.SetDefault("monitoring.metrics.path", "/metrics")
    viper.SetDefault("monitoring.health.enabled", true)
    viper.SetDefault("monitoring.health.port", 8080)
    viper.SetDefault("monitoring.health.liveness_path", "/healthz")
    viper.SetDefault("monitoring.health.readiness_path", "/ready")
    viper.SetDefault("monitoring.logging.level", "info")
    viper.SetDefault("monitoring.logging.format", "json")
    viper.SetDefault("monitoring.logging.output", "stdout")
    
    // Security defaults
    viper.SetDefault("security.tls.enabled", false)
    viper.SetDefault("security.api.enabled", true)
    viper.SetDefault("security.api.port", 8081)
    viper.SetDefault("security.api.rate_limit", 100)
    viper.SetDefault("security.api.cors_enabled", true)
    
    // Performance defaults
    viper.SetDefault("performance.worker_pool_size", 100)
    viper.SetDefault("performance.queue_size", 1000)
    viper.SetDefault("performance.batch_size", 50)
    viper.SetDefault("performance.gc_interval", "1m")
}

// Validate validates the configuration
func (c *Config) Validate() error {
    // Validate database configuration
    if c.Database.Host == "" {
        return fmt.Errorf("database host is required")
    }
    if c.Database.Port <= 0 || c.Database.Port > 65535 {
        return fmt.Errorf("invalid database port: %d", c.Database.Port)
    }
    if c.Database.Username == "" {
        return fmt.Errorf("database username is required")
    }
    if c.Database.Database == "" {
        return fmt.Errorf("database name is required")
    }
    
    // Validate AGI configuration
    if c.AGI.Port <= 0 || c.AGI.Port > 65535 {
        return fmt.Errorf("invalid AGI port: %d", c.AGI.Port)
    }
    if c.AGI.MaxConnections <= 0 {
        return fmt.Errorf("AGI max connections must be positive")
    }
    
    // Validate Redis configuration if host is provided
    if c.Redis.Host != "" {
        if c.Redis.Port <= 0 || c.Redis.Port > 65535 {
            return fmt.Errorf("invalid Redis port: %d", c.Redis.Port)
        }
    }
    
    // Validate AMI configuration if enabled
    if c.Asterisk.AMI.Enabled && c.Asterisk.AMI.Host != "" {
        if c.Asterisk.AMI.Port <= 0 || c.Asterisk.AMI.Port > 65535 {
            return fmt.Errorf("invalid AMI port: %d", c.Asterisk.AMI.Port)
        }
        if c.Asterisk.AMI.Username == "" {
            return fmt.Errorf("AMI username is required when AMI is enabled")
        }
    }
    
    // Validate monitoring ports
    if c.Monitoring.Metrics.Enabled {
        if c.Monitoring.Metrics.Port <= 0 || c.Monitoring.Metrics.Port > 65535 {
            return fmt.Errorf("invalid metrics port: %d", c.Monitoring.Metrics.Port)
        }
    }
    if c.Monitoring.Health.Enabled {
        if c.Monitoring.Health.Port <= 0 || c.Monitoring.Health.Port > 65535 {
            return fmt.Errorf("invalid health port: %d", c.Monitoring.Health.Port)
        }
    }
    
    // Validate API configuration
    if c.Security.API.Enabled {
        if c.Security.API.Port <= 0 || c.Security.API.Port > 65535 {
            return fmt.Errorf("invalid API port: %d", c.Security.API.Port)
        }
    }
    
    // Validate performance settings
    if c.Performance.WorkerPoolSize <= 0 {
        return fmt.Errorf("worker pool size must be positive")
    }
    if c.Performance.QueueSize <= 0 {
        return fmt.Errorf("queue size must be positive")
    }
    
    return nil
}

// GetDSN returns the database connection string
func (c *DatabaseConfig) GetDSN() string {
    charset := c.Charset
    if charset == "" {
        charset = "utf8mb4"
    }
    
    return fmt.Sprintf("%s:%s@tcp(%s:%d)/%s?charset=%s&parseTime=true&loc=Local",
        c.Username,
        c.Password,
        c.Host,
        c.Port,
        c.Database,
        charset,
    )
}

// GetRedisAddr returns the Redis address
func (c *RedisConfig) GetRedisAddr() string {
    return fmt.Sprintf("%s:%d", c.Host, c.Port)
}

// GetAGIAddr returns the AGI server address
func (c *AGIConfig) GetAGIAddr() string {
    return fmt.Sprintf("%s:%d", c.ListenAddress, c.Port)
}

// GetAMIAddr returns the AMI server address
func (c *AMIConfig) GetAMIAddr() string {
    return fmt.Sprintf("%s:%d", c.Host, c.Port)
}

// IsProduction returns true if running in production environment
func (c *AppConfig) IsProduction() bool {
    return strings.ToLower(c.Environment) == "production"
}

// IsDevelopment returns true if running in development environment
func (c *AppConfig) IsDevelopment() bool {
    return strings.ToLower(c.Environment) == "development"
}

// IsDebug returns true if debug mode is enabled
func (c *AppConfig) IsDebug() bool {
    return c.Debug
}
