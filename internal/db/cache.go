package db

import (
    "context"
    "encoding/json"
    "fmt"
    "time"
    
    "github.com/go-redis/redis/v8"
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
    "github.com/hamzaKhattat/ara-production-system/pkg/errors"
)

type CacheConfig struct {
    Host          string
    Port          int
    Password      string
    DB            int
    PoolSize      int
    MinIdleConns  int
    MaxRetries    int
}

type Cache struct {
    client *redis.Client
    prefix string
}

var (
    cacheInstance *Cache
)

func InitializeCache(cfg CacheConfig, prefix string) error {
    client := redis.NewClient(&redis.Options{
        Addr:         fmt.Sprintf("%s:%d", cfg.Host, cfg.Port),
        Password:     cfg.Password,
        DB:           cfg.DB,
        PoolSize:     cfg.PoolSize,
        MinIdleConns: cfg.MinIdleConns,
        MaxRetries:   cfg.MaxRetries,
    })
    
    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()
    
    if err := client.Ping(ctx).Err(); err != nil {
        return errors.Wrap(err, errors.ErrRedis, "failed to connect to Redis")
    }
    
    cacheInstance = &Cache{
        client: client,
        prefix: prefix,
    }
    
    logger.Info("Redis cache initialized")
    return nil
}

func GetCache() *Cache {
    if cacheInstance == nil {
        // Return nil cache that doesn't error
        return &Cache{}
    }
    return cacheInstance
}

func (c *Cache) key(k string) string {
    if c.prefix != "" {
        return fmt.Sprintf("%s:%s", c.prefix, k)
    }
    return k
}

func (c *Cache) Get(ctx context.Context, key string, dest interface{}) error {
    if c.client == nil {
        return nil // Cache miss
    }
    
    val, err := c.client.Get(ctx, c.key(key)).Result()
    if err == redis.Nil {
        return nil // Cache miss
    }
    if err != nil {
        logger.WithContext(ctx).WithField("key", key).WithField("error", err.Error()).Warn("Cache get failed")
        return nil // Don't fail on cache errors
    }
    
    if err := json.Unmarshal([]byte(val), dest); err != nil {
        logger.WithContext(ctx).WithField("key", key).WithField("error", err.Error()).Warn("Cache unmarshal failed")
        return nil
    }
    
    return nil
}

func (c *Cache) Set(ctx context.Context, key string, value interface{}, expiration time.Duration) error {
    if c.client == nil {
        return nil
    }
    
    data, err := json.Marshal(value)
    if err != nil {
        return nil // Don't fail on cache errors
    }
    
    if err := c.client.Set(ctx, c.key(key), data, expiration).Err(); err != nil {
        logger.WithContext(ctx).WithField("key", key).WithField("error", err.Error()).Warn("Cache set failed")
    }
    
    return nil
}

func (c *Cache) Delete(ctx context.Context, keys ...string) error {
    if c.client == nil {
        return nil
    }
    
    fullKeys := make([]string, len(keys))
    for i, k := range keys {
        fullKeys[i] = c.key(k)
    }
    
    if err := c.client.Del(ctx, fullKeys...).Err(); err != nil {
        logger.WithContext(ctx).WithField("error", err.Error()).Warn("Cache delete failed")
    }
    
    return nil
}

// Distributed lock
func (c *Cache) Lock(ctx context.Context, key string, ttl time.Duration) (func(), error) {
    if c.client == nil {
        return func() {}, nil // No-op
    }
    
    lockKey := c.key(fmt.Sprintf("lock:%s", key))
    value := fmt.Sprintf("%d", time.Now().UnixNano())
    
    ok, err := c.client.SetNX(ctx, lockKey, value, ttl).Result()
    if err != nil {
        return nil, errors.Wrap(err, errors.ErrRedis, "failed to acquire lock")
    }
    
    if !ok {
        return nil, errors.New(errors.ErrInternal, "lock already held")
    }
    
    // Return unlock function
    return func() {
        script := redis.NewScript(`
            if redis.call("get", KEYS[1]) == ARGV[1] then
                return redis.call("del", KEYS[1])
            else
                return 0
            end
        `)
        
        script.Run(ctx, c.client, []string{lockKey}, value)
    }, nil
}
