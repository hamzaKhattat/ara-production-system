package config

import (
    "time"
)

// Config holds all configuration for the application
type Config struct {
    App        AppConfig
    Database   DatabaseConfig
    Redis      RedisConfig
    AGI        AGIConfig
    Asterisk   AsteriskConfig
    Router     RouterConfig
    Monitoring MonitoringConfig
    Security   SecurityConfig
    Performance PerformanceConfig
}

type AppConfig struct {
    Name        string
    Version     string
    Environment string
    Debug       bool
}

type DatabaseConfig struct {
    Driver          string
    Host            string
    Port            int
    Username        string
    Password        string
    Database        string
    MaxOpenConns    int
    MaxIdleConns    int
    ConnMaxLifetime time.Duration
    RetryAttempts   int
    RetryDelay      time.Duration
}

type RedisConfig struct {
    Host         string
    Port         int
    Password     string
    DB           int
    PoolSize     int
    MinIdleConns int
    MaxRetries   int
}

type AGIConfig struct {
    ListenAddress   string
    Port            int
    MaxConnections  int
    ReadTimeout     time.Duration
    WriteTimeout    time.Duration
    IdleTimeout     time.Duration
    ShutdownTimeout time.Duration
}

type AsteriskConfig struct {
    AMI struct {
        Host              string
        Port              int
        Username          string
        Password          string
        ReconnectInterval time.Duration
        PingInterval      time.Duration
    }
    ARA struct {
        TransportReloadInterval time.Duration
        EndpointCacheTTL        time.Duration
        DialplanCacheTTL        time.Duration
    }
}

type RouterConfig struct {
    DIDAllocationTimeout time.Duration
    CallCleanupInterval  time.Duration
    StaleCallTimeout     time.Duration
    MaxRetries           int
    RetryBackoff         string
    Verification         struct {
        Enabled    bool
        StrictMode bool
        LogFailures bool
    }
    Recording struct {
        Enabled bool
        Path    string
        Format  string
        MixType string
    }
}

type MonitoringConfig struct {
    Metrics struct {
        Enabled bool
        Port    int
        Path    string
    }
    Health struct {
        Enabled      bool
        Port         int
        LivenessPath string
        ReadinessPath string
    }
    Logging struct {
        Level  string
        Format string
        Output string
        File   struct {
            Enabled    bool
            Path       string
            MaxSize    int
            MaxBackups int
            MaxAge     int
            Compress   bool
        }
    }
}

type SecurityConfig struct {
    TLS struct {
        Enabled  bool
        CertFile string
        KeyFile  string
        CAFile   string
    }
    API struct {
        Enabled    bool
        Port       int
        AuthToken  string
        RateLimit  int
        CORSEnabled bool
    }
}

type PerformanceConfig struct {
    WorkerPoolSize int
    QueueSize      int
    BatchSize      int
    GCInterval     time.Duration
}

// Load loads configuration from Viper
func Load() (*Config, error) {
    // This would typically load from viper, but since you're already
    // using viper directly in main.go, this can be a placeholder
    return &Config{}, nil
}
