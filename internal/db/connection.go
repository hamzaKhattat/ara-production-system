package db

import (
    "context"
    "database/sql"
    "fmt"
    "sync"
    "time"
    
    _ "github.com/go-sql-driver/mysql"
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
    "github.com/hamzaKhattat/ara-production-system/pkg/errors"
)

type Config struct {
    Driver           string
    Host             string
    Port             int
    Username         string
    Password         string
    Database         string
    MaxOpenConns     int
    MaxIdleConns     int
    ConnMaxLifetime  time.Duration
    RetryAttempts    int
    RetryDelay       time.Duration
}

type DB struct {
    *sql.DB
    cfg    Config
    mu     sync.RWMutex
    health bool
}

var (
    instance *DB
    once     sync.Once
)

func Initialize(cfg Config) error {
    var err error
    once.Do(func() {
        instance, err = newDB(cfg)
    })
    return err
}

func GetDB() *DB {
    if instance == nil {
        panic("database not initialized")
    }
    return instance
}

func newDB(cfg Config) (*DB, error) {
    dsn := fmt.Sprintf("%s:%s@tcp(%s:%d)/%s?parseTime=true&multiStatements=true&interpolateParams=true",
        cfg.Username, cfg.Password, cfg.Host, cfg.Port, cfg.Database)
    
    var db *sql.DB
    var err error
    
    // Retry connection
    for i := 0; i <= cfg.RetryAttempts; i++ {
        db, err = sql.Open(cfg.Driver, dsn)
        if err == nil {
            err = db.Ping()
            if err == nil {
                break
            }
        }
        
        if i < cfg.RetryAttempts {
            logger.WithField("attempt", i+1).WithError(err).Warn("Database connection failed, retrying...")
            time.Sleep(cfg.RetryDelay * time.Duration(i+1))
        }
    }
    
    if err != nil {
        return nil, errors.Wrap(err, errors.ErrDatabase, "failed to connect to database")
    }
    
    // Configure connection pool
    db.SetMaxOpenConns(cfg.MaxOpenConns)
    db.SetMaxIdleConns(cfg.MaxIdleConns)
    db.SetConnMaxLifetime(cfg.ConnMaxLifetime)
    
    wrapper := &DB{
        DB:     db,
        cfg:    cfg,
        health: true,
    }
    
    // Start health checker
    go wrapper.healthCheck()
    
    logger.Info("Database connection established")
    return wrapper, nil
}

func (db *DB) healthCheck() {
    ticker := time.NewTicker(30 * time.Second)
    defer ticker.Stop()
    
    for range ticker.C {
        ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
        err := db.PingContext(ctx)
        cancel()
        
        db.mu.Lock()
        oldHealth := db.health
        db.health = err == nil
        db.mu.Unlock()
        
        if oldHealth != db.health {
            if db.health {
                logger.Info("Database connection recovered")
            } else {
                logger.WithError(err).Error("Database connection lost")
            }
        }
    }
}

func (db *DB) IsHealthy() bool {
    db.mu.RLock()
    defer db.mu.RUnlock()
    return db.health
}

// Transaction with retry
func (db *DB) Transaction(ctx context.Context, fn func(*sql.Tx) error) error {
    var err error
    for i := 0; i <= db.cfg.RetryAttempts; i++ {
        err = db.transaction(ctx, fn)
        if err == nil {
            return nil
        }
        
        if !isRetryableError(err) {
            return err
        }
        
        if i < db.cfg.RetryAttempts {
            select {
            case <-ctx.Done():
                return ctx.Err()
            case <-time.After(db.cfg.RetryDelay * time.Duration(i+1)):
                logger.WithField("attempt", i+1).WithError(err).Warn("Transaction failed, retrying...")
            }
        }
    }
    
    return errors.Wrap(err, errors.ErrDatabase, "transaction failed after retries")
}

func (db *DB) transaction(ctx context.Context, fn func(*sql.Tx) error) error {
    tx, err := db.BeginTx(ctx, nil)
    if err != nil {
        return err
    }
    
    defer func() {
        if p := recover(); p != nil {
            tx.Rollback()
            panic(p)
        }
    }()
    
    err = fn(tx)
    if err != nil {
        tx.Rollback()
        return err
    }
    
    return tx.Commit()
}

func isRetryableError(err error) bool {
    if err == nil {
        return false
    }
    
    errStr := err.Error()
    retryableErrors := []string{
        "connection refused",
        "connection reset",
        "broken pipe",
        "timeout",
        "deadlock",
        "try restarting transaction",
    }
    
    for _, e := range retryableErrors {
        if strings.Contains(strings.ToLower(errStr), e) {
            return true
        }
    }
    
    return false
}

// Prepared statement cache
type StmtCache struct {
    mu    sync.RWMutex
    stmts map[string]*sql.Stmt
    db    *sql.DB
}

func NewStmtCache(db *sql.DB) *StmtCache {
    return &StmtCache{
        stmts: make(map[string]*sql.Stmt),
        db:    db,
    }
}

func (c *StmtCache) Prepare(query string) (*sql.Stmt, error) {
    c.mu.RLock()
    stmt, exists := c.stmts[query]
    c.mu.RUnlock()
    
    if exists {
        return stmt, nil
    }
    
    c.mu.Lock()
    defer c.mu.Unlock()
    
    // Double-check
    if stmt, exists := c.stmts[query]; exists {
        return stmt, nil
    }
    
    stmt, err := c.db.Prepare(query)
    if err != nil {
        return nil, err
    }
    
    c.stmts[query] = stmt
    return stmt, nil
}

func (c *StmtCache) Close() {
    c.mu.Lock()
    defer c.mu.Unlock()
    
    for _, stmt := range c.stmts {
        stmt.Close()
    }
    
    c.stmts = make(map[string]*sql.Stmt)
}
