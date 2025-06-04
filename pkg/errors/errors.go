package errors

import (
    "fmt"
    "runtime"
    "strings"
)

type ErrorCode string

const (
    // System errors
    ErrInternal         ErrorCode = "INTERNAL_ERROR"
    ErrDatabase         ErrorCode = "DATABASE_ERROR"
    ErrRedis            ErrorCode = "REDIS_ERROR"
    ErrConfiguration    ErrorCode = "CONFIG_ERROR"
    
    // Business logic errors
    ErrProviderNotFound ErrorCode = "PROVIDER_NOT_FOUND"
    ErrDIDNotAvailable  ErrorCode = "DID_NOT_AVAILABLE"
    ErrRouteNotFound    ErrorCode = "ROUTE_NOT_FOUND"
    ErrCallNotFound     ErrorCode = "CALL_NOT_FOUND"
    ErrInvalidIP        ErrorCode = "INVALID_IP"
    ErrAuthFailed       ErrorCode = "AUTH_FAILED"
    ErrQuotaExceeded    ErrorCode = "QUOTA_EXCEEDED"
    
    // AGI errors
    ErrAGITimeout       ErrorCode = "AGI_TIMEOUT"
    ErrAGIInvalidCmd    ErrorCode = "AGI_INVALID_COMMAND"
    ErrAGIConnection    ErrorCode = "AGI_CONNECTION_ERROR"
)

type AppError struct {
    Code       ErrorCode
    Message    string
    Err        error
    StatusCode int
    Context    map[string]interface{}
    Stack      string
}

func New(code ErrorCode, message string) *AppError {
    return &AppError{
        Code:       code,
        Message:    message,
        StatusCode: 500,
        Context:    make(map[string]interface{}),
        Stack:      getStack(),
    }
}

func Wrap(err error, code ErrorCode, message string) *AppError {
    if err == nil {
        return nil
    }
    
    // If already an AppError, enhance it
    if appErr, ok := err.(*AppError); ok {
        appErr.Message = fmt.Sprintf("%s: %s", message, appErr.Message)
        return appErr
    }
    
    return &AppError{
        Code:       code,
        Message:    message,
        Err:        err,
        StatusCode: 500,
        Context:    make(map[string]interface{}),
        Stack:      getStack(),
    }
}

func (e *AppError) Error() string {
    if e.Err != nil {
        return fmt.Sprintf("[%s] %s: %v", e.Code, e.Message, e.Err)
    }
    return fmt.Sprintf("[%s] %s", e.Code, e.Message)
}

func (e *AppError) Unwrap() error {
    return e.Err
}

func (e *AppError) WithContext(key string, value interface{}) *AppError {
    e.Context[key] = value
    return e
}

func (e *AppError) WithStatusCode(code int) *AppError {
    e.StatusCode = code
    return e
}

func (e *AppError) IsRetryable() bool {
    switch e.Code {
    case ErrDatabase, ErrRedis, ErrAGITimeout, ErrAGIConnection:
        return true
    default:
        return false
    }
}

func getStack() string {
    var pcs [32]uintptr
    n := runtime.Callers(3, pcs[:])
    
    var builder strings.Builder
    frames := runtime.CallersFrames(pcs[:n])
    
    for {
        frame, more := frames.Next()
        if !strings.Contains(frame.File, "runtime/") {
            builder.WriteString(fmt.Sprintf("%s:%d %s\n", frame.File, frame.Line, frame.Function))
        }
        if !more {
            break
        }
    }
    
    return builder.String()
}

// Error checking helpers
func Is(err error, code ErrorCode) bool {
    if err == nil {
        return false
    }
    
    appErr, ok := err.(*AppError)
    if !ok {
        return false
    }
    
    return appErr.Code == code
}
