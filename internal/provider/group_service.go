package provider

import (
    "context"
    "database/sql"
    "encoding/json"
    "fmt"
    "regexp"
    "strings"
    "time"
    
    "github.com/hamzaKhattat/ara-production-system/internal/models"
    "github.com/hamzaKhattat/ara-production-system/pkg/errors"
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
)

// GroupService handles provider group operations
type GroupService struct {
    db    *sql.DB
    cache CacheInterface
}

// NewGroupService creates a new group service
func NewGroupService(db *sql.DB, cache CacheInterface) *GroupService {
    return &GroupService{
        db:    db,
        cache: cache,
    }
}

// CreateGroup creates a new provider group
func (gs *GroupService) CreateGroup(ctx context.Context, group *models.ProviderGroup) error {
    // Validate group
    if err := gs.validateGroup(group); err != nil {
        return err
    }
    
    // Start transaction
    tx, err := gs.db.BeginTx(ctx, nil)
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to start transaction")
    }
    defer tx.Rollback()
    
    // Insert group
    matchValue, _ := json.Marshal(group.MatchValue)
    metadata, _ := json.Marshal(group.Metadata)
    
    query := `
        INSERT INTO provider_groups (
            name, description, group_type, match_pattern, match_field,
            match_operator, match_value, provider_type, enabled, priority, metadata
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    
    result, err := tx.ExecContext(ctx, query,
        group.Name, group.Description, group.GroupType, group.MatchPattern,
        group.MatchField, group.MatchOperator, matchValue,
        group.ProviderType, group.Enabled, group.Priority, metadata,
    )
    
    if err != nil {
        if strings.Contains(err.Error(), "Duplicate entry") {
            return errors.New(errors.ErrInternal, "group already exists")
        }
        return errors.Wrap(err, errors.ErrDatabase, "failed to insert group")
    }
    
    groupID, _ := result.LastInsertId()
    group.ID = int(groupID)
    
    // If it's a dynamic group, populate members based on rules
    if group.GroupType != models.GroupTypeManual {
        if err := gs.populateGroupMembers(ctx, tx, group); err != nil {
            return errors.Wrap(err, errors.ErrInternal, "failed to populate group members")
        }
    }
    
    if err := tx.Commit(); err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to commit transaction")
    }
    
    // Clear cache
    gs.cache.Delete(ctx, fmt.Sprintf("group:%s", group.Name))
    gs.cache.Delete(ctx, "groups:all")
    
    logger.WithContext(ctx).WithFields(map[string]interface{}{
        "group_id": group.ID,
        "name": group.Name,
        "type": group.GroupType,
    }).Info("Provider group created")
    
    return nil
}

// populateGroupMembers fills group members based on matching rules
func (gs *GroupService) populateGroupMembers(ctx context.Context, tx *sql.Tx, group *models.ProviderGroup) error {
    // Get all providers
    providers, err := gs.getMatchingProviders(ctx, tx, group)
    if err != nil {
        return err
    }
    
    // Insert matching providers as group members
    stmt, err := tx.PrepareContext(ctx, `
        INSERT INTO provider_group_members (
            group_id, provider_id, provider_name, matched_by_rule
        ) VALUES (?, ?, ?, true)
        ON DUPLICATE KEY UPDATE matched_by_rule = true`)
    
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to prepare statement")
    }
    defer stmt.Close()
    
    for _, provider := range providers {
        if _, err := stmt.ExecContext(ctx, group.ID, provider.ID, provider.Name); err != nil {
            logger.WithContext(ctx).WithError(err).Warn("Failed to add provider to group")
        }
    }
    
    return nil
}

// getMatchingProviders returns providers that match the group criteria
func (gs *GroupService) getMatchingProviders(ctx context.Context, tx *sql.Tx, group *models.ProviderGroup) ([]*models.Provider, error) {
    query := "SELECT id, name, type, host, country, region, city, metadata FROM providers WHERE active = 1"
    var args []interface{}
    
    // Filter by provider type if specified
    if group.ProviderType != "" && group.ProviderType != "any" {
        query += " AND type = ?"
        args = append(args, group.ProviderType)
    }
    
    rows, err := tx.QueryContext(ctx, query, args...)
    if err != nil {
        return nil, errors.Wrap(err, errors.ErrDatabase, "failed to query providers")
    }
    defer rows.Close()
    
    var matchingProviders []*models.Provider
    
    for rows.Next() {
        var provider models.Provider
        var country, region, city sql.NullString
        var metadataJSON sql.NullString
        
        err := rows.Scan(&provider.ID, &provider.Name, &provider.Type, 
            &provider.Host, &country, &region, &city, &metadataJSON)
        if err != nil {
            continue
        }
        
        // Build provider metadata for matching
        providerData := map[string]interface{}{
            "name": provider.Name,
            "type": string(provider.Type),
            "host": provider.Host,
        }
        
        if country.Valid {
            providerData["country"] = country.String
        }
        if region.Valid {
            providerData["region"] = region.String
        }
        if city.Valid {
            providerData["city"] = city.String
        }
        
        if metadataJSON.Valid {
            var metadata map[string]interface{}
            if err := json.Unmarshal([]byte(metadataJSON.String), &metadata); err == nil {
                for k, v := range metadata {
                    providerData["metadata."+k] = v
                }
            }
        }
        
        // Check if provider matches group criteria
        if gs.providerMatchesGroup(group, providerData) {
            matchingProviders = append(matchingProviders, &provider)
        }
    }
    
    return matchingProviders, nil
}

// providerMatchesGroup checks if a provider matches group criteria
func (gs *GroupService) providerMatchesGroup(group *models.ProviderGroup, providerData map[string]interface{}) bool {
    switch group.GroupType {
    case models.GroupTypeRegex:
        return gs.matchRegex(group.MatchPattern, providerData["name"].(string))
    
    case models.GroupTypeMetadata:
        fieldValue, exists := providerData[group.MatchField]
        if !exists {
            return false
        }
        return gs.matchValue(group.MatchOperator, fieldValue, group.MatchValue)
    
    case models.GroupTypeDynamic:
        // For dynamic groups, parse match rules from metadata
        if group.Metadata != nil {
            if rules, ok := group.Metadata["match_rules"].([]interface{}); ok {
                return gs.matchDynamicRules(rules, providerData)
            }
        }
        return false
    
    default:
        return false
    }
}

// matchRegex checks if a string matches a regex pattern
func (gs *GroupService) matchRegex(pattern, value string) bool {
    matched, err := regexp.MatchString(pattern, value)
    if err != nil {
        logger.WithField("pattern", pattern).WithError(err).Warn("Invalid regex pattern")
        return false
    }
    return matched
}

// matchValue checks if a value matches based on operator
func (gs *GroupService) matchValue(operator models.MatchOperator, fieldValue interface{}, matchValue json.RawMessage) bool {
    fieldStr := fmt.Sprintf("%v", fieldValue)
    
    switch operator {
    case models.MatchOperatorEquals:
        var value string
        if err := json.Unmarshal(matchValue, &value); err == nil {
            return fieldStr == value
        }
    
    case models.MatchOperatorContains:
        var value string
        if err := json.Unmarshal(matchValue, &value); err == nil {
            return strings.Contains(fieldStr, value)
        }
    
    case models.MatchOperatorStartsWith:
        var value string
        if err := json.Unmarshal(matchValue, &value); err == nil {
            return strings.HasPrefix(fieldStr, value)
        }
    
    case models.MatchOperatorEndsWith:
        var value string
        if err := json.Unmarshal(matchValue, &value); err == nil {
            return strings.HasSuffix(fieldStr, value)
        }
    
    case models.MatchOperatorRegex:
        var pattern string
        if err := json.Unmarshal(matchValue, &pattern); err == nil {
            return gs.matchRegex(pattern, fieldStr)
        }
    
    case models.MatchOperatorIn:
        var values []string
        if err := json.Unmarshal(matchValue, &values); err == nil {
            for _, v := range values {
                if fieldStr == v {
                    return true
                }
            }
        }
    
    case models.MatchOperatorNotIn:
        var values []string
        if err := json.Unmarshal(matchValue, &values); err == nil {
            for _, v := range values {
                if fieldStr == v {
                    return false
                }
            }
            return true
        }
    }
    
    return false
}

// matchDynamicRules checks if provider matches dynamic rules
func (gs *GroupService) matchDynamicRules(rules []interface{}, providerData map[string]interface{}) bool {
    // All rules must match (AND logic)
    for _, rule := range rules {
        ruleMap, ok := rule.(map[string]interface{})
        if !ok {
            continue
        }
        
        field, _ := ruleMap["field"].(string)
        operator, _ := ruleMap["operator"].(string)
        value := ruleMap["value"]
        
        fieldValue, exists := providerData[field]
        if !exists {
            return false
        }
        
        valueJSON, _ := json.Marshal(value)
        if !gs.matchValue(models.MatchOperator(operator), fieldValue, valueJSON) {
            return false
        }
    }
    
    return true
}

// AddProviderToGroup manually adds a provider to a group
func (gs *GroupService) AddProviderToGroup(ctx context.Context, groupName, providerName string, overrides map[string]interface{}) error {
    // Get group
    group, err := gs.GetGroup(ctx, groupName)
    if err != nil {
        return err
    }
    
    // Get provider
    var providerID int
    err = gs.db.QueryRowContext(ctx, 
        "SELECT id FROM providers WHERE name = ?", providerName).Scan(&providerID)
    if err != nil {
        return errors.New(errors.ErrProviderNotFound, "provider not found")
    }
    
    // Insert member
    query := `
        INSERT INTO provider_group_members (
            group_id, provider_id, provider_name, added_manually,
            priority_override, weight_override, metadata
        ) VALUES (?, ?, ?, true, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            added_manually = true,
            priority_override = VALUES(priority_override),
            weight_override = VALUES(weight_override),
            metadata = VALUES(metadata)`
    
    var priorityOverride, weightOverride sql.NullInt64
    var metadata []byte
    
    if p, ok := overrides["priority"].(int); ok {
        priorityOverride.Valid = true
        priorityOverride.Int64 = int64(p)
    }
    if w, ok := overrides["weight"].(int); ok {
        weightOverride.Valid = true
        weightOverride.Int64 = int64(w)
    }
    if m, ok := overrides["metadata"]; ok {
        metadata, _ = json.Marshal(m)
    }
    
    _, err = gs.db.ExecContext(ctx, query, 
        group.ID, providerID, providerName, 
        priorityOverride, weightOverride, metadata)
    
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to add provider to group")
    }
    
    // Clear cache
    gs.cache.Delete(ctx, fmt.Sprintf("group:%s:members", groupName))
    
    return nil
}

// RemoveProviderFromGroup removes a provider from a group
func (gs *GroupService) RemoveProviderFromGroup(ctx context.Context, groupName, providerName string) error {
    query := `
        DELETE pgm FROM provider_group_members pgm
        JOIN provider_groups pg ON pgm.group_id = pg.id
        WHERE pg.name = ? AND pgm.provider_name = ?`
    
    result, err := gs.db.ExecContext(ctx, query, groupName, providerName)
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to remove provider from group")
    }
    
    rows, _ := result.RowsAffected()
    if rows == 0 {
        return errors.New(errors.ErrInternal, "provider not found in group")
    }
    
    // Clear cache
    gs.cache.Delete(ctx, fmt.Sprintf("group:%s:members", groupName))
    
    return nil
}

// GetGroup retrieves a group by name
func (gs *GroupService) GetGroup(ctx context.Context, name string) (*models.ProviderGroup, error) {
    // Try cache first
    cacheKey := fmt.Sprintf("group:%s", name)
    var group models.ProviderGroup
    
    if err := gs.cache.Get(ctx, cacheKey, &group); err == nil {
        return &group, nil
    }
    
    // Query database
    query := `
        SELECT id, name, description, group_type, match_pattern, match_field,
               match_operator, match_value, provider_type, enabled, priority,
               metadata, created_at, updated_at,
               (SELECT COUNT(*) FROM provider_group_members WHERE group_id = pg.id) as member_count
        FROM provider_groups pg
        WHERE name = ?`
    
    var matchValue, metadata sql.NullString
    var providerType sql.NullString
    
    err := gs.db.QueryRowContext(ctx, query, name).Scan(
        &group.ID, &group.Name, &group.Description, &group.GroupType,
        &group.MatchPattern, &group.MatchField, &group.MatchOperator,
        &matchValue, &providerType, &group.Enabled, &group.Priority,
        &metadata, &group.CreatedAt, &group.UpdatedAt, &group.MemberCount,
    )
    
    if err == sql.ErrNoRows {
        return nil, errors.New(errors.ErrInternal, "group not found")
    }
    if err != nil {
        return nil, errors.Wrap(err, errors.ErrDatabase, "failed to query group")
    }
    
    // Parse JSON fields
    if matchValue.Valid {
        group.MatchValue = json.RawMessage(matchValue.String)
    }
    if metadata.Valid {
        json.Unmarshal([]byte(metadata.String), &group.Metadata)
    }
    if providerType.Valid {
        group.ProviderType = models.ProviderType(providerType.String)
    }
    
    // Cache for 5 minutes
    gs.cache.Set(ctx, cacheKey, group, 5*time.Minute)
    
    return &group, nil
}

// GetGroupMembers retrieves all providers in a group
func (gs *GroupService) GetGroupMembers(ctx context.Context, groupName string) ([]*models.Provider, error) {
    // Try cache first
    cacheKey := fmt.Sprintf("group:%s:members", groupName)
    var members []*models.Provider
    
    if err := gs.cache.Get(ctx, cacheKey, &members); err == nil {
        return members, nil
    }
    
    // Query database
    query := `
        SELECT p.id, p.name, p.type, p.host, p.port, p.username, p.password,
               p.auth_type, p.transport, p.codecs, p.max_channels, p.current_channels,
               COALESCE(pgm.priority_override, p.priority) as priority,
               COALESCE(pgm.weight_override, p.weight) as weight,
               p.cost_per_minute, p.active, p.health_check_enabled,
               p.last_health_check, p.health_status, p.metadata,
               p.created_at, p.updated_at
        FROM providers p
        JOIN provider_group_members pgm ON p.id = pgm.provider_id
        JOIN provider_groups pg ON pgm.group_id = pg.id
        WHERE pg.name = ? AND p.active = 1
        ORDER BY priority DESC, p.name`
    
    rows, err := gs.db.QueryContext(ctx, query, groupName)
    if err != nil {
        return nil, errors.Wrap(err, errors.ErrDatabase, "failed to query group members")
    }
    defer rows.Close()
    
    members = make([]*models.Provider, 0)
    
    for rows.Next() {
        var provider models.Provider
        var codecsJSON string
        var metadataJSON sql.NullString
        
        err := rows.Scan(
            &provider.ID, &provider.Name, &provider.Type, &provider.Host, &provider.Port,
            &provider.Username, &provider.Password, &provider.AuthType, &provider.Transport,
            &codecsJSON, &provider.MaxChannels, &provider.CurrentChannels,
            &provider.Priority, &provider.Weight, &provider.CostPerMinute,
            &provider.Active, &provider.HealthCheckEnabled, &provider.LastHealthCheck,
            &provider.HealthStatus, &metadataJSON, &provider.CreatedAt, &provider.UpdatedAt,
        )
        
        if err != nil {
            logger.WithContext(ctx).WithError(err).Warn("Failed to scan provider")
            continue
        }
        
        // Parse JSON fields
        if codecsJSON != "" {
            json.Unmarshal([]byte(codecsJSON), &provider.Codecs)
        }
        if metadataJSON.Valid {
            json.Unmarshal([]byte(metadataJSON.String), &provider.Metadata)
        }
        
        members = append(members, &provider)
    }
    
    // Cache for 1 minute
    gs.cache.Set(ctx, cacheKey, members, time.Minute)
    
    return members, nil
}

// ListGroups returns all groups with optional filtering
func (gs *GroupService) ListGroups(ctx context.Context, filter map[string]interface{}) ([]*models.ProviderGroup, error) {
    query := `
        SELECT id, name, description, group_type, match_pattern, match_field,
               match_operator, match_value, provider_type, enabled, priority,
               metadata, created_at, updated_at,
               (SELECT COUNT(*) FROM provider_group_members WHERE group_id = pg.id) as member_count
        FROM provider_groups pg
        WHERE 1=1`
    
    var args []interface{}
    
    if groupType, ok := filter["type"].(string); ok && groupType != "" {
        query += " AND group_type = ?"
        args = append(args, groupType)
    }
    
    if providerType, ok := filter["provider_type"].(string); ok && providerType != "" {
        query += " AND provider_type = ?"
        args = append(args, providerType)
    }
    
    if enabled, ok := filter["enabled"].(bool); ok {
        query += " AND enabled = ?"
        args = append(args, enabled)
    }
    
    query += " ORDER BY priority DESC, name"
    
    rows, err := gs.db.QueryContext(ctx, query, args...)
    if err != nil {
        return nil, errors.Wrap(err, errors.ErrDatabase, "failed to query groups")
    }
    defer rows.Close()
    
    var groups []*models.ProviderGroup
    
    for rows.Next() {
        var group models.ProviderGroup
        var matchValue, metadata sql.NullString
        var providerType sql.NullString
        
        err := rows.Scan(
            &group.ID, &group.Name, &group.Description, &group.GroupType,
            &group.MatchPattern, &group.MatchField, &group.MatchOperator,
            &matchValue, &providerType, &group.Enabled, &group.Priority,
            &metadata, &group.CreatedAt, &group.UpdatedAt, &group.MemberCount,
        )
        
        if err != nil {
            logger.WithContext(ctx).WithError(err).Warn("Failed to scan group")
            continue
        }
        
        // Parse JSON fields
        if matchValue.Valid {
            group.MatchValue = json.RawMessage(matchValue.String)
        }
        if metadata.Valid {
            json.Unmarshal([]byte(metadata.String), &group.Metadata)
        }
        if providerType.Valid {
            group.ProviderType = models.ProviderType(providerType.String)
        }
        
        groups = append(groups, &group)
    }
    
    return groups, nil
}

// UpdateGroup updates a provider group
func (gs *GroupService) UpdateGroup(ctx context.Context, name string, updates map[string]interface{}) error {
    // Build update query
    var setClause []string
    var args []interface{}
    
    for key, value := range updates {
        switch key {
        case "description", "match_pattern", "match_field", "match_operator",
             "provider_type", "enabled", "priority":
            setClause = append(setClause, fmt.Sprintf("%s = ?", key))
            args = append(args, value)
        case "match_value", "metadata":
            jsonValue, _ := json.Marshal(value)
            setClause = append(setClause, fmt.Sprintf("%s = ?", key))
            args = append(args, jsonValue)
        }
    }
    
    if len(setClause) == 0 {
        return nil // Nothing to update
    }
    
    // Add updated_at
    setClause = append(setClause, "updated_at = NOW()")
    
    // Add WHERE clause
    args = append(args, name)
    
    query := fmt.Sprintf("UPDATE provider_groups SET %s WHERE name = ?", strings.Join(setClause, ", "))
    
    result, err := gs.db.ExecContext(ctx, query, args...)
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to update group")
    }
    
    rows, _ := result.RowsAffected()
    if rows == 0 {
        return errors.New(errors.ErrInternal, "group not found")
    }
    
    // If group rules changed, repopulate members
    if _, hasPattern := updates["match_pattern"]; hasPattern {
        group, err := gs.GetGroup(ctx, name)
        if err != nil {
            return err
        }
        
        if group.GroupType != models.GroupTypeManual {
            tx, err := gs.db.BeginTx(ctx, nil)
            if err != nil {
                return err
            }
            defer tx.Rollback()
            
            // Clear existing auto-matched members
            _, err = tx.ExecContext(ctx, `
                DELETE FROM provider_group_members 
                WHERE group_id = ? AND matched_by_rule = true`, group.ID)
            if err != nil {
                return errors.Wrap(err, errors.ErrDatabase, "failed to clear members")
            }
            
            // Repopulate
            if err := gs.populateGroupMembers(ctx, tx, group); err != nil {
                return err
            }
            
            if err := tx.Commit(); err != nil {
                return errors.Wrap(err, errors.ErrDatabase, "failed to commit")
            }
        }
    }
    
    // Clear cache
    gs.cache.Delete(ctx, fmt.Sprintf("group:%s", name))
    gs.cache.Delete(ctx, fmt.Sprintf("group:%s:members", name))
    
    return nil
}

// DeleteGroup deletes a provider group
func (gs *GroupService) DeleteGroup(ctx context.Context, name string) error {
    // Check if group is in use by routes
    var inUse bool
    err := gs.db.QueryRowContext(ctx, `
        SELECT EXISTS(
            SELECT 1 FROM provider_routes 
            WHERE (inbound_provider = ? AND inbound_is_group = 1)
               OR (intermediate_provider = ? AND intermediate_is_group = 1)
               OR (final_provider = ? AND final_is_group = 1)
        )`, name, name, name).Scan(&inUse)
    
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to check group usage")
    }
    
    if inUse {
        return errors.New(errors.ErrInternal, "group is in use by routes")
    }
    
    // Delete group (members will be cascade deleted)
    result, err := gs.db.ExecContext(ctx, "DELETE FROM provider_groups WHERE name = ?", name)
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to delete group")
    }
    
    rows, _ := result.RowsAffected()
    if rows == 0 {
        return errors.New(errors.ErrInternal, "group not found")
    }
    
    // Clear cache
    gs.cache.Delete(ctx, fmt.Sprintf("group:%s", name))
    gs.cache.Delete(ctx, fmt.Sprintf("group:%s:members", name))
    gs.cache.Delete(ctx, "groups:all")
    
    return nil
}

// RefreshGroupMembers refreshes dynamic group members
func (gs *GroupService) RefreshGroupMembers(ctx context.Context, groupName string) error {
    group, err := gs.GetGroup(ctx, groupName)
    if err != nil {
        return err
    }
    
    if group.GroupType == models.GroupTypeManual {
        return errors.New(errors.ErrInternal, "cannot refresh manual group")
    }
    
    tx, err := gs.db.BeginTx(ctx, nil)
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to start transaction")
    }
    defer tx.Rollback()
    
    // Clear existing auto-matched members
    _, err = tx.ExecContext(ctx, `
        DELETE FROM provider_group_members 
        WHERE group_id = ? AND matched_by_rule = true`, group.ID)
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to clear members")
    }
    
    // Repopulate
    if err := gs.populateGroupMembers(ctx, tx, group); err != nil {
        return err
    }
    
    if err := tx.Commit(); err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to commit")
    }
    
    // Clear cache
    gs.cache.Delete(ctx, fmt.Sprintf("group:%s:members", groupName))
    
    logger.WithContext(ctx).WithField("group", groupName).Info("Group members refreshed")
    
    return nil
}

// validateGroup validates group configuration
func (gs *GroupService) validateGroup(group *models.ProviderGroup) error {
    if group.Name == "" {
        return errors.New(errors.ErrInternal, "group name is required")
    }
    
    switch group.GroupType {
    case models.GroupTypeRegex:
        if group.MatchPattern == "" {
            return errors.New(errors.ErrInternal, "match pattern is required for regex groups")
        }
        // Validate regex
        _, err := regexp.Compile(group.MatchPattern)
        if err != nil {
            return errors.New(errors.ErrInternal, "invalid regex pattern")
        }
    
    case models.GroupTypeMetadata:
        if group.MatchField == "" || group.MatchOperator == "" {
            return errors.New(errors.ErrInternal, "match field and operator are required for metadata groups")
        }
    
    case models.GroupTypeDynamic:
        if group.Metadata == nil || group.Metadata["match_rules"] == nil {
            return errors.New(errors.ErrInternal, "match rules are required for dynamic groups")
        }
    }
    
    return nil
}
