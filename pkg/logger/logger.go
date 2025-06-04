package logger

import (
    "context"
    "fmt"
    "os"
    "time"
    
    "github.com/sirupsen/logrus"
    "gopkg.in/natefinch/lumberjack.v2"
)

type Logger struct {
    *logrus.Logger
    fields logrus.Fields
}

var (
    defaultLogger *Logger
)

type Config struct {
    Level      string
    Format     string
    Output     string
    File       FileConfig
    Fields     map[string]interface{}
}

type FileConfig struct {
    Enabled    bool
    Path       string
    MaxSize    int
    MaxBackups int
    MaxAge     int
    Compress   bool
}

func Init(cfg Config) error {
    log := logrus.New()
    
    // Set log level
    level, err := logrus.ParseLevel(cfg.Level)
    if err != nil {
        return fmt.Errorf("invalid log level: %w", err)
    }
    log.SetLevel(level)
    
    // Set formatter
    switch cfg.Format {
    case "json":
        log.SetFormatter(&logrus.JSONFormatter{
            TimestampFormat: time.RFC3339Nano,
            FieldMap: logrus.FieldMap{
                logrus.FieldKeyTime:  "@timestamp",
                logrus.FieldKeyLevel: "level",
                logrus.FieldKeyMsg:   "message",
            },
        })
    default:
        log.SetFormatter(&logrus.TextFormatter{
            FullTimestamp:   true,
            TimestampFormat: "2006-01-02 15:04:05.000",
        })
    }
    
    // Set output
    if cfg.File.Enabled {
        log.SetOutput(&lumberjack.Logger{
            Filename:   cfg.File.Path,
            MaxSize:    cfg.File.MaxSize,
            MaxBackups: cfg.File.MaxBackups,
            MaxAge:     cfg.File.MaxAge,
            Compress:   cfg.File.Compress,
        })
    } else {
        log.SetOutput(os.Stdout)
    }
    
    // Set default fields
    fields := logrus.Fields{
        "app":     "asterisk-ara-router",
        "version": "2.0.0",
        "pid":     os.Getpid(),
    }
    
    for k, v := range cfg.Fields {
        fields[k] = v
    }
    
    defaultLogger = &Logger{
        Logger: log,
        fields: fields,
    }
    
    return nil
}

func WithContext(ctx context.Context) *Logger {
    if defaultLogger == nil {
        panic("logger not initialized")
    }
    
    fields := logrus.Fields{}
    
    // Extract common fields from context
    if reqID := ctx.Value("request_id"); reqID != nil {
        fields["request_id"] = reqID
    }
    if callID := ctx.Value("call_id"); callID != nil {
        fields["call_id"] = callID
    }
    if userID := ctx.Value("user_id"); userID != nil {
        fields["user_id"] = userID
    }
    
    return defaultLogger.WithFields(fields)
}

func (l *Logger) WithFields(fields map[string]interface{}) *Logger {
    newFields := make(logrus.Fields)
    for k, v := range l.fields {
        newFields[k] = v
    }
    for k, v := range fields {
        newFields[k] = v
    }
    
    entry := l.Logger.WithFields(newFields)
    return &Logger{
        Logger: entry.Logger,
        fields: newFields,
    }
}

func (l *Logger) WithField(key string, value interface{}) *Logger {
    return l.WithFields(map[string]interface{}{key: value})
}

func (l *Logger) WithError(err error) *Logger {
    return l.WithFields(map[string]interface{}{
        "error":      err.Error(),
        "error_type": fmt.Sprintf("%T", err),
    })
}

// Log methods that use the logger fields
func (l *Logger) Debug(args ...interface{}) {
    l.Logger.WithFields(l.fields).Debug(args...)
}

func (l *Logger) Info(args ...interface{}) {
    l.Logger.WithFields(l.fields).Info(args...)
}

func (l *Logger) Warn(args ...interface{}) {
    l.Logger.WithFields(l.fields).Warn(args...)
}

func (l *Logger) Error(args ...interface{}) {
    l.Logger.WithFields(l.fields).Error(args...)
}

func (l *Logger) Fatal(args ...interface{}) {
    l.Logger.WithFields(l.fields).Fatal(args...)
}

// Convenience functions
func Debug(args ...interface{}) {
    if defaultLogger != nil {
        defaultLogger.WithFields(defaultLogger.fields).Debug(args...)
    }
}

func Info(args ...interface{}) {
    if defaultLogger != nil {
        defaultLogger.WithFields(defaultLogger.fields).Info(args...)
    }
}

func Warn(args ...interface{}) {
    if defaultLogger != nil {
        defaultLogger.WithFields(defaultLogger.fields).Warn(args...)
    }
}

func Error(args ...interface{}) {
    if defaultLogger != nil {
        defaultLogger.WithFields(defaultLogger.fields).Error(args...)
    }
}

func Fatal(args ...interface{}) {
    if defaultLogger != nil {
        defaultLogger.WithFields(defaultLogger.fields).Fatal(args...)
    }
}

func WithField(key string, value interface{}) *Logger {
    if defaultLogger != nil {
        return defaultLogger.WithField(key, value)
    }
    return &Logger{Logger: logrus.New(), fields: make(logrus.Fields)}
}

func WithError(err error) *Logger {
    if defaultLogger != nil {
        return defaultLogger.WithError(err)
    }
    return &Logger{Logger: logrus.New(), fields: make(logrus.Fields)}
}
