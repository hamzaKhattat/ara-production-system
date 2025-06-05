package models

import (
//   "database/sql/driver"
    "encoding/json"
    "time"
)

// GroupType defines how providers are grouped
type GroupType string

const (
    GroupTypeManual   GroupType = "manual"    // Manually added providers
    GroupTypeRegex    GroupType = "regex"     // Pattern matching on provider names
    GroupTypeMetadata GroupType = "metadata"  // Match based on metadata fields
    GroupTypeDynamic  GroupType = "dynamic"   // Dynamically evaluated
)

// MatchOperator defines how to match providers
type MatchOperator string

const (
    MatchOperatorEquals     MatchOperator = "equals"
    MatchOperatorContains   MatchOperator = "contains"
    MatchOperatorStartsWith MatchOperator = "starts_with"
    MatchOperatorEndsWith   MatchOperator = "ends_with"
    MatchOperatorRegex      MatchOperator = "regex"
    MatchOperatorIn         MatchOperator = "in"
    MatchOperatorNotIn      MatchOperator = "not_in"
)

// ProviderGroup represents a logical grouping of providers
type ProviderGroup struct {
    ID           int             `json:"id" db:"id"`
    Name         string          `json:"name" db:"name"`
    Description  string          `json:"description" db:"description"`
    GroupType    GroupType       `json:"group_type" db:"group_type"`
    MatchPattern string          `json:"match_pattern,omitempty" db:"match_pattern"`
    MatchField   string          `json:"match_field,omitempty" db:"match_field"`
    MatchOperator MatchOperator  `json:"match_operator,omitempty" db:"match_operator"`
    MatchValue   json.RawMessage `json:"match_value,omitempty" db:"match_value"`
    ProviderType ProviderType    `json:"provider_type,omitempty" db:"provider_type"`
    Enabled      bool            `json:"enabled" db:"enabled"`
    Priority     int             `json:"priority" db:"priority"`
    Metadata     JSON            `json:"metadata,omitempty" db:"metadata"`
    CreatedAt    time.Time       `json:"created_at" db:"created_at"`
    UpdatedAt    time.Time       `json:"updated_at" db:"updated_at"`
    
    // Computed fields
    MemberCount int         `json:"member_count,omitempty" db:"-"`
    Members     []*Provider `json:"members,omitempty" db:"-"`
}

// ProviderGroupMember represents membership in a group
type ProviderGroupMember struct {
    ID              int64     `json:"id" db:"id"`
    GroupID         int       `json:"group_id" db:"group_id"`
    ProviderID      int       `json:"provider_id" db:"provider_id"`
    ProviderName    string    `json:"provider_name" db:"provider_name"`
    AddedManually   bool      `json:"added_manually" db:"added_manually"`
    MatchedByRule   bool      `json:"matched_by_rule" db:"matched_by_rule"`
    PriorityOverride *int     `json:"priority_override,omitempty" db:"priority_override"`
    WeightOverride   *int     `json:"weight_override,omitempty" db:"weight_override"`
    Metadata        JSON      `json:"metadata,omitempty" db:"metadata"`
    CreatedAt       time.Time `json:"created_at" db:"created_at"`
}

// GroupMatchRule defines a matching rule for dynamic groups
type GroupMatchRule struct {
    Field    string      `json:"field"`
    Operator string      `json:"operator"`
    Value    interface{} `json:"value"`
}

// ProviderGroupStats represents group statistics
type ProviderGroupStats struct {
    GroupName      string    `json:"group_name" db:"group_name"`
    TotalCalls     int64     `json:"total_calls" db:"total_calls"`
    CompletedCalls int64     `json:"completed_calls" db:"completed_calls"`
    FailedCalls    int64     `json:"failed_calls" db:"failed_calls"`
    ActiveCalls    int64     `json:"active_calls" db:"active_calls"`
    SuccessRate    float64   `json:"success_rate" db:"success_rate"`
    AvgCallDuration float64  `json:"avg_call_duration" db:"avg_call_duration"`
    LastCallTime   time.Time `json:"last_call_time" db:"last_call_time"`
}
