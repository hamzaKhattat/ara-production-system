package models

import (
    "database/sql/driver"
    "encoding/json"
    "time"
)

// Provider types
type ProviderType string

const (
    ProviderTypeInbound      ProviderType = "inbound"
    ProviderTypeIntermediate ProviderType = "intermediate"
    ProviderTypeFinal        ProviderType = "final"
)

// Load balance modes
type LoadBalanceMode string

const (
    LoadBalanceModeRoundRobin       LoadBalanceMode = "round_robin"
    LoadBalanceModeWeighted         LoadBalanceMode = "weighted"
    LoadBalanceModePriority         LoadBalanceMode = "priority"
    LoadBalanceModeFailover         LoadBalanceMode = "failover"
    LoadBalanceModeLeastConnections LoadBalanceMode = "least_connections"
    LoadBalanceModeResponseTime     LoadBalanceMode = "response_time"
    LoadBalanceModeHash             LoadBalanceMode = "hash"
)

// Call status
type CallStatus string

const (
    CallStatusInitiated      CallStatus = "INITIATED"
    CallStatusActive         CallStatus = "ACTIVE"
    CallStatusReturnedFromS3 CallStatus = "RETURNED_FROM_S3"
    CallStatusRoutingToS4    CallStatus = "ROUTING_TO_S4"
    CallStatusCompleted      CallStatus = "COMPLETED"
    CallStatusFailed         CallStatus = "FAILED"
    CallStatusAbandoned      CallStatus = "ABANDONED"
    CallStatusTimeout        CallStatus = "TIMEOUT"
)

// JSON field for database storage
type JSON map[string]interface{}

func (j JSON) Value() (driver.Value, error) {
    return json.Marshal(j)
}

func (j *JSON) Scan(value interface{}) error {
    if value == nil {
        *j = make(JSON)
        return nil
    }
    
    bytes, ok := value.([]byte)
    if !ok {
        return nil
    }
    
    return json.Unmarshal(bytes, j)
}

// Provider represents an external server
type Provider struct {
    ID                 int             `json:"id" db:"id"`
    Name               string          `json:"name" db:"name"`
    Type               ProviderType    `json:"type" db:"type"`
    Host               string          `json:"host" db:"host"`
    Port               int             `json:"port" db:"port"`
    Username           string          `json:"username,omitempty" db:"username"`
    Password           string          `json:"password,omitempty" db:"password"`
    AuthType           string          `json:"auth_type" db:"auth_type"`
    Transport          string          `json:"transport" db:"transport"`
    Codecs             []string        `json:"codecs" db:"codecs"`
    MaxChannels        int             `json:"max_channels" db:"max_channels"`
    CurrentChannels    int             `json:"current_channels" db:"current_channels"`
    Priority           int             `json:"priority" db:"priority"`
    Weight             int             `json:"weight" db:"weight"`
    CostPerMinute      float64         `json:"cost_per_minute" db:"cost_per_minute"`
    Active             bool            `json:"active" db:"active"`
    HealthCheckEnabled bool            `json:"health_check_enabled" db:"health_check_enabled"`
    LastHealthCheck    *time.Time      `json:"last_health_check,omitempty" db:"last_health_check"`
    HealthStatus       string          `json:"health_status" db:"health_status"`
    Metadata           JSON            `json:"metadata,omitempty" db:"metadata"`
    CreatedAt          time.Time       `json:"created_at" db:"created_at"`
    UpdatedAt          time.Time       `json:"updated_at" db:"updated_at"`
}

// DID represents a phone number
type DID struct {
    ID            int64      `json:"id" db:"id"`
    Number        string     `json:"number" db:"number"`
    ProviderID    *int       `json:"provider_id,omitempty" db:"provider_id"`
    ProviderName  string     `json:"provider_name" db:"provider_name"`
    InUse         bool       `json:"in_use" db:"in_use"`
    Destination   string     `json:"destination,omitempty" db:"destination"`
    Country       string     `json:"country,omitempty" db:"country"`
    City          string     `json:"city,omitempty" db:"city"`
    RateCenter    string     `json:"rate_center,omitempty" db:"rate_center"`
    MonthlyCost   float64    `json:"monthly_cost" db:"monthly_cost"`
    PerMinuteCost float64    `json:"per_minute_cost" db:"per_minute_cost"`
    AllocatedAt   *time.Time `json:"allocated_at,omitempty" db:"allocated_at"`
    ReleasedAt    *time.Time `json:"released_at,omitempty" db:"released_at"`
    LastUsedAt    *time.Time `json:"last_used_at,omitempty" db:"last_used_at"`
    UsageCount    int64      `json:"usage_count" db:"usage_count"`
    Metadata      JSON       `json:"metadata,omitempty" db:"metadata"`
    CreatedAt     time.Time  `json:"created_at" db:"created_at"`
    UpdatedAt     time.Time  `json:"updated_at" db:"updated_at"`
}

// ProviderRoute defines routing rules
type ProviderRoute struct {
    ID                   int             `json:"id" db:"id"`
    Name                 string          `json:"name" db:"name"`
    Description          string          `json:"description,omitempty" db:"description"`
    InboundProvider      string          `json:"inbound_provider" db:"inbound_provider"`
    IntermediateProvider string          `json:"intermediate_provider" db:"intermediate_provider"`
    FinalProvider        string          `json:"final_provider" db:"final_provider"`
    LoadBalanceMode      LoadBalanceMode `json:"load_balance_mode" db:"load_balance_mode"`
    Priority             int             `json:"priority" db:"priority"`
    Weight               int             `json:"weight" db:"weight"`
    MaxConcurrentCalls   int             `json:"max_concurrent_calls" db:"max_concurrent_calls"`
    CurrentCalls         int             `json:"current_calls" db:"current_calls"`
    Enabled              bool            `json:"enabled" db:"enabled"`
    FailoverRoutes       []string        `json:"failover_routes,omitempty" db:"failover_routes"`
    RoutingRules         JSON            `json:"routing_rules,omitempty" db:"routing_rules"`
    Metadata             JSON            `json:"metadata,omitempty" db:"metadata"`
    CreatedAt            time.Time       `json:"created_at" db:"created_at"`
    UpdatedAt            time.Time       `json:"updated_at" db:"updated_at"`
}

// CallRecord tracks call flow
type CallRecord struct {
    ID                   int64      `json:"id" db:"id"`
    CallID               string     `json:"call_id" db:"call_id"`
    OriginalANI          string     `json:"original_ani" db:"original_ani"`
    OriginalDNIS         string     `json:"original_dnis" db:"original_dnis"`
    TransformedANI       string     `json:"transformed_ani,omitempty" db:"transformed_ani"`
    AssignedDID          string     `json:"assigned_did,omitempty" db:"assigned_did"`
    InboundProvider      string     `json:"inbound_provider" db:"inbound_provider"`
    IntermediateProvider string     `json:"intermediate_provider" db:"intermediate_provider"`
    FinalProvider        string     `json:"final_provider" db:"final_provider"`
    RouteName            string     `json:"route_name,omitempty" db:"route_name"`
    Status               CallStatus `json:"status" db:"status"`
    CurrentStep          string     `json:"current_step,omitempty" db:"current_step"`
    FailureReason        string     `json:"failure_reason,omitempty" db:"failure_reason"`
    StartTime            time.Time  `json:"start_time" db:"start_time"`
    AnswerTime           *time.Time `json:"answer_time,omitempty" db:"answer_time"`
    EndTime              *time.Time `json:"end_time,omitempty" db:"end_time"`
    Duration             int        `json:"duration" db:"duration"`
    BillableDuration     int        `json:"billable_duration" db:"billable_duration"`
    RecordingPath        string     `json:"recording_path,omitempty" db:"recording_path"`
    SIPResponseCode      int        `json:"sip_response_code,omitempty" db:"sip_response_code"`
    QualityScore         float64    `json:"quality_score,omitempty" db:"quality_score"`
    Metadata             JSON       `json:"metadata,omitempty" db:"metadata"`
}

// CallVerification for security tracking
type CallVerification struct {
    ID               int64     `json:"id" db:"id"`
    CallID           string    `json:"call_id" db:"call_id"`
    VerificationStep string    `json:"verification_step" db:"verification_step"`
    ExpectedANI      string    `json:"expected_ani,omitempty" db:"expected_ani"`
    ExpectedDNIS     string    `json:"expected_dnis,omitempty" db:"expected_dnis"`
    ReceivedANI      string    `json:"received_ani,omitempty" db:"received_ani"`
    ReceivedDNIS     string    `json:"received_dnis,omitempty" db:"received_dnis"`
    SourceIP         string    `json:"source_ip,omitempty" db:"source_ip"`
    ExpectedIP       string    `json:"expected_ip,omitempty" db:"expected_ip"`
    Verified         bool      `json:"verified" db:"verified"`
    FailureReason    string    `json:"failure_reason,omitempty" db:"failure_reason"`
    CreatedAt        time.Time `json:"created_at" db:"created_at"`
}

// ProviderHealth tracks real-time health
type ProviderHealth struct {
    ID                  int       `json:"id" db:"id"`
    ProviderName        string    `json:"provider_name" db:"provider_name"`
    HealthScore         int       `json:"health_score" db:"health_score"`
    LatencyMs           int       `json:"latency_ms" db:"latency_ms"`
    PacketLoss          float64   `json:"packet_loss" db:"packet_loss"`
    JitterMs            int       `json:"jitter_ms" db:"jitter_ms"`
    ActiveCalls         int       `json:"active_calls" db:"active_calls"`
    MaxCalls            int       `json:"max_calls" db:"max_calls"`
    LastSuccessAt       *time.Time `json:"last_success_at,omitempty" db:"last_success_at"`
    LastFailureAt       *time.Time `json:"last_failure_at,omitempty" db:"last_failure_at"`
    ConsecutiveFailures int       `json:"consecutive_failures" db:"consecutive_failures"`
    IsHealthy           bool      `json:"is_healthy" db:"is_healthy"`
    UpdatedAt           time.Time `json:"updated_at" db:"updated_at"`
}

// AGI Response for call routing
type CallResponse struct {
    Status      string `json:"status"`
    DIDAssigned string `json:"did_assigned,omitempty"`
    NextHop     string `json:"next_hop,omitempty"`
    ANIToSend   string `json:"ani_to_send,omitempty"`
    DNISToSend  string `json:"dnis_to_send,omitempty"`
    Error       string `json:"error,omitempty"`
}

// Provider statistics
type ProviderStats struct {
    ProviderName     string    `json:"provider_name"`
    TotalCalls       int64     `json:"total_calls"`
    CompletedCalls   int64     `json:"completed_calls"`
    FailedCalls      int64     `json:"failed_calls"`
    ActiveCalls      int64     `json:"active_calls"`
    SuccessRate      float64   `json:"success_rate"`
    AvgCallDuration  float64   `json:"avg_call_duration"`
    AvgResponseTime  int       `json:"avg_response_time"`
    LastCallTime     time.Time `json:"last_call_time"`
    IsHealthy        bool      `json:"is_healthy"`
}
