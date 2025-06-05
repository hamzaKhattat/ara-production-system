package ara

import (
    "context"
    "database/sql"
//    "encoding/json"
    "fmt"
    "strings"
    "time"
    
    "github.com/hamzaKhattat/ara-production-system/internal/models"
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
    "github.com/hamzaKhattat/ara-production-system/pkg/errors"
)

type Manager struct {
    db    *sql.DB
    cache CacheInterface
}

type CacheInterface interface {
    Get(ctx context.Context, key string, dest interface{}) error
    Set(ctx context.Context, key string, value interface{}, expiration time.Duration) error
    Delete(ctx context.Context, keys ...string) error
}

func NewManager(db *sql.DB, cache CacheInterface) *Manager {
    return &Manager{
        db:    db,
        cache: cache,
    }
}


func (m *Manager) CreateEndpoint(ctx context.Context, provider *models.Provider) error {
    log := logger.WithContext(ctx)
    
    // Start transaction
    tx, err := m.db.BeginTx(ctx, nil)
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to start transaction")
    }
    defer tx.Rollback()
    
    endpointID := fmt.Sprintf("endpoint-%s", provider.Name)
    authID := fmt.Sprintf("auth-%s", provider.Name)
    aorID := fmt.Sprintf("aor-%s", provider.Name)
    
    // Create/update AOR
    aorQuery := `
        INSERT INTO ps_aors (id, max_contacts, remove_existing, qualify_frequency)
        VALUES (?, 1, 'yes', ?)
        ON DUPLICATE KEY UPDATE
            qualify_frequency = VALUES(qualify_frequency)`
    
    qualifyFreq := 60
    if provider.HealthCheckEnabled {
        qualifyFreq = 30
    }
    
    if _, err := tx.ExecContext(ctx, aorQuery, aorID, qualifyFreq); err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to create AOR")
    }
    
    // Create/update Auth if using credentials
    if provider.AuthType == "credentials" || provider.AuthType == "both" {
        authQuery := `
            INSERT INTO ps_auths (id, auth_type, username, password, realm)
            VALUES (?, 'userpass', ?, ?, ?)
            ON DUPLICATE KEY UPDATE
                username = VALUES(username),
                password = VALUES(password)`
        
        realm := provider.Host
        if _, err := tx.ExecContext(ctx, authQuery, authID, provider.Username, provider.Password, realm); err != nil {
            return errors.Wrap(err, errors.ErrDatabase, "failed to create auth")
        }
    }
    
    // Create/update Endpoint
    codecs := strings.Join(provider.Codecs, ",")
    if codecs == "" {
        codecs = "ulaw,alaw"
    }
    
    // Determine context based on provider type
    context := fmt.Sprintf("from-provider-%s", provider.Type)
    
    // Build endpoint query
    endpointQuery := `
        INSERT INTO ps_endpoints (
            id, transport, aors, auth, context, 
            disallow, allow, direct_media, trust_id_inbound, trust_id_outbound,
            send_pai, send_rpid, rtp_symmetric, force_rport, rewrite_contact,
            timers, timers_min_se, timers_sess_expires, dtmf_mode,
            media_encryption, rtp_timeout, rtp_timeout_hold
        ) VALUES (
            ?, 'transport-udp', ?, ?, ?,
            'all', ?, 'no', 'yes', 'yes',
            'yes', 'yes', 'yes', 'yes', 'yes',
            'yes', 90, 1800, 'rfc4733',
            'no', 120, 60
        )
        ON DUPLICATE KEY UPDATE
            transport = VALUES(transport),
            aors = VALUES(aors),
            auth = VALUES(auth),
            context = VALUES(context),
            allow = VALUES(allow),
            direct_media = VALUES(direct_media)`
    
    authRef := ""
    if provider.AuthType == "credentials" || provider.AuthType == "both" {
        authRef = authID
    }
    
    if _, err := tx.ExecContext(ctx, endpointQuery, endpointID, aorID, authRef, context, codecs); err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to create endpoint")
    }
    
    // Create IP-based authentication if needed
    if provider.AuthType == "ip" || provider.AuthType == "both" {
        ipQuery := `
            INSERT INTO ps_endpoint_id_ips (id, endpoint, ` + "`match`" + `)
            VALUES (?, ?, ?)
            ON DUPLICATE KEY UPDATE
                endpoint = VALUES(endpoint),
                ` + "`match`" + ` = VALUES(` + "`match`" + `)`
        
        ipID := fmt.Sprintf("ip-%s", provider.Name)
        match := fmt.Sprintf("%s/32", provider.Host)
        
        if _, err := tx.ExecContext(ctx, ipQuery, ipID, endpointID, match); err != nil {
            return errors.Wrap(err, errors.ErrDatabase, "failed to create IP auth")
        }
    }
    
    // Commit transaction
    if err := tx.Commit(); err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to commit transaction")
    }
    
    // Clear cache
    m.cache.Delete(ctx, fmt.Sprintf("endpoint:%s", provider.Name))
    
    log.WithFields(map[string]interface{}{
        "provider": provider.Name,
        "auth_type": provider.AuthType,
        "endpoint_id": endpointID,
    }).Info("ARA endpoint created/updated")
    
    return nil
}
// DeleteEndpoint removes PJSIP endpoint from ARA
func (m *Manager) DeleteEndpoint(ctx context.Context, providerName string) error {
    tx, err := m.db.BeginTx(ctx, nil)
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to start transaction")
    }
    defer tx.Rollback()
    
    endpointID := fmt.Sprintf("endpoint-%s", providerName)
    authID := fmt.Sprintf("auth-%s", providerName)
    aorID := fmt.Sprintf("aor-%s", providerName)
    ipID := fmt.Sprintf("ip-%s", providerName)
    
    // Delete in reverse order
    queries := []string{
        fmt.Sprintf("DELETE FROM ps_endpoint_id_ips WHERE id = '%s'", ipID),
        fmt.Sprintf("DELETE FROM ps_endpoints WHERE id = '%s'", endpointID),
        fmt.Sprintf("DELETE FROM ps_auths WHERE id = '%s'", authID),
        fmt.Sprintf("DELETE FROM ps_aors WHERE id = '%s'", aorID),
    }
    
    for _, query := range queries {
        if _, err := tx.ExecContext(ctx, query); err != nil {
            logger.WithContext(ctx).WithError(err).Warn("Failed to delete ARA component")
        }
    }
    
    if err := tx.Commit(); err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to commit transaction")
    }
    
    // Clear cache
    m.cache.Delete(ctx, fmt.Sprintf("endpoint:%s", providerName))
    
    return nil
}

// CreateDialplan creates the complete dialplan in ARA
func (m *Manager) CreateDialplan(ctx context.Context) error {
    log := logger.WithContext(ctx)
    
    // Clear existing dialplan for our contexts
    contexts := []string{
        "from-provider-inbound",
        "from-provider-intermediate",
        "from-provider-final",
        "router-outbound",
        "router-internal",
        "hangup-handler",
        "sub-recording",
    }
    
    tx, err := m.db.BeginTx(ctx, nil)
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to start transaction")
    }
    defer tx.Rollback()
    
    // Clear existing extensions
    for _, context := range contexts {
        if _, err := tx.ExecContext(ctx, "DELETE FROM extensions WHERE context = ?", context); err != nil {
            log.WithError(err).Warn("Failed to clear context")
        }
    }
    
    // Create inbound context (from S1)
    inboundExtensions := []DialplanExtension{
        {Exten: "_X.", Priority: 1, App: "NoOp", AppData: "Incoming call from S1: ${CALLERID(num)} -> ${EXTEN}"},
        {Exten: "_X.", Priority: 2, App: "Set", AppData: "CHANNEL(hangup_handler_push)=hangup-handler,s,1"},
        {Exten: "_X.", Priority: 3, App: "Set", AppData: "__CALLID=${UNIQUEID}"},
        {Exten: "_X.", Priority: 4, App: "Set", AppData: "__INBOUND_PROVIDER=${CHANNEL(endpoint)}"},
        {Exten: "_X.", Priority: 5, App: "Set", AppData: "__ORIGINAL_ANI=${CALLERID(num)}"},
        {Exten: "_X.", Priority: 6, App: "Set", AppData: "__ORIGINAL_DNIS=${EXTEN}"},
        {Exten: "_X.", Priority: 7, App: "Set", AppData: "__SOURCE_IP=${CHANNEL(pjsip,remote_addr)}"},
        {Exten: "_X.", Priority: 8, App: "Set", AppData: "CDR(inbound_provider)=${INBOUND_PROVIDER}"},
        {Exten: "_X.", Priority: 9, App: "Set", AppData: "CDR(original_ani)=${ORIGINAL_ANI}"},
        {Exten: "_X.", Priority: 10, App: "Set", AppData: "CDR(original_dnis)=${ORIGINAL_DNIS}"},
        {Exten: "_X.", Priority: 11, App: "MixMonitor", AppData: "${UNIQUEID}.wav,b,/usr/local/bin/post-recording.sh ${UNIQUEID}"},
        {Exten: "_X.", Priority: 12, App: "AGI", AppData: "agi://localhost:4573/processIncoming"},
        {Exten: "_X.", Priority: 13, App: "GotoIf", AppData: "$[\"${ROUTER_STATUS}\" = \"success\"]?route:failed"},
        {Exten: "_X.", Priority: 14, App: "Hangup", AppData: "21", Label: "failed"},
        {Exten: "_X.", Priority: 15, App: "Set", AppData: "CALLERID(num)=${ANI_TO_SEND}", Label: "route"},
        {Exten: "_X.", Priority: 16, App: "Set", AppData: "CDR(intermediate_provider)=${INTERMEDIATE_PROVIDER}"},
        {Exten: "_X.", Priority: 17, App: "Set", AppData: "CDR(assigned_did)=${DID_ASSIGNED}"},
        {Exten: "_X.", Priority: 18, App: "Dial", AppData: "PJSIP/${DNIS_TO_SEND}@${NEXT_HOP},180,U(sub-recording^${UNIQUEID})"},
        {Exten: "_X.", Priority: 19, App: "Set", AppData: "CDR(sip_response)=${HANGUPCAUSE}"},
        {Exten: "_X.", Priority: 20, App: "GotoIf", AppData: "$[\"${DIALSTATUS}\" = \"ANSWER\"]?end:failed"},
        {Exten: "_X.", Priority: 21, App: "Hangup", AppData: "", Label: "end"},
    }
    
    if err := m.insertExtensions(tx, "from-provider-inbound", inboundExtensions); err != nil {
        return err
    }
    
    // Create intermediate context (from S3)
    intermediateExtensions := []DialplanExtension{
        {Exten: "_X.", Priority: 1, App: "NoOp", AppData: "Return call from S3: ${CALLERID(num)} -> ${EXTEN}"},
        {Exten: "_X.", Priority: 2, App: "Set", AppData: "__INTERMEDIATE_PROVIDER=${CHANNEL(endpoint)}"},
        {Exten: "_X.", Priority: 3, App: "Set", AppData: "__SOURCE_IP=${CHANNEL(pjsip,remote_addr)}"},
        {Exten: "_X.", Priority: 4, App: "Set", AppData: "CDR(intermediate_return)=true"},
        {Exten: "_X.", Priority: 5, App: "AGI", AppData: "agi://localhost:4573/processReturn"},
        {Exten: "_X.", Priority: 6, App: "GotoIf", AppData: "$[\"${ROUTER_STATUS}\" = \"success\"]?route:failed"},
        {Exten: "_X.", Priority: 7, App: "Hangup", AppData: "21", Label: "failed"},
        {Exten: "_X.", Priority: 8, App: "Set", AppData: "CALLERID(num)=${ANI_TO_SEND}", Label: "route"},
        {Exten: "_X.", Priority: 9, App: "Set", AppData: "CDR(final_provider)=${FINAL_PROVIDER}"},
        {Exten: "_X.", Priority: 10, App: "Dial", AppData: "PJSIP/${DNIS_TO_SEND}@${NEXT_HOP},180"},
        {Exten: "_X.", Priority: 11, App: "Set", AppData: "CDR(final_sip_response)=${HANGUPCAUSE}"},
        {Exten: "_X.", Priority: 12, App: "Hangup", AppData: ""},
    }
    
    if err := m.insertExtensions(tx, "from-provider-intermediate", intermediateExtensions); err != nil {
        return err
    }
    
    // Create final context (from S4)
    finalExtensions := []DialplanExtension{
        {Exten: "_X.", Priority: 1, App: "NoOp", AppData: "Final call from S4: ${CALLERID(num)} -> ${EXTEN}"},
        {Exten: "_X.", Priority: 2, App: "Set", AppData: "__FINAL_PROVIDER=${CHANNEL(endpoint)}"},
        {Exten: "_X.", Priority: 3, App: "Set", AppData: "__SOURCE_IP=${CHANNEL(pjsip,remote_addr)}"},
        {Exten: "_X.", Priority: 4, App: "Set", AppData: "CDR(final_confirmation)=true"},
        {Exten: "_X.", Priority: 5, App: "AGI", AppData: "agi://localhost:4573/processFinal"},
        {Exten: "_X.", Priority: 6, App: "Congestion", AppData: "5"},
        {Exten: "_X.", Priority: 7, App: "Hangup", AppData: ""},
    }
    
    if err := m.insertExtensions(tx, "from-provider-final", finalExtensions); err != nil {
        return err
    }
    
    // Create hangup handler
    hangupExtensions := []DialplanExtension{
        {Exten: "s", Priority: 1, App: "NoOp", AppData: "Call ended: ${UNIQUEID}"},
        {Exten: "s", Priority: 2, App: "Set", AppData: "CDR(end_time)=${EPOCH}"},
        {Exten: "s", Priority: 3, App: "Set", AppData: "CDR(duration)=${CDR(billsec)}"},
        {Exten: "s", Priority: 4, App: "AGI", AppData: "agi://localhost:4573/hangup"},
        {Exten: "s", Priority: 5, App: "Return", AppData: ""},
    }
    
    if err := m.insertExtensions(tx, "hangup-handler", hangupExtensions); err != nil {
        return err
    }
    
    // Create recording subroutine
    recordingExtensions := []DialplanExtension{
        {Exten: "s", Priority: 1, App: "NoOp", AppData: "Starting recording on originated channel"},
        {Exten: "s", Priority: 2, App: "Set", AppData: "AUDIOHOOK_INHERIT(MixMonitor)=yes"},
        {Exten: "s", Priority: 3, App: "MixMonitor", AppData: "${ARG1}-out.wav,b"},
        {Exten: "s", Priority: 4, App: "Return", AppData: ""},
    }
    
    if err := m.insertExtensions(tx, "sub-recording", recordingExtensions); err != nil {
        return err
    }
    
    if err := tx.Commit(); err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to commit dialplan")
    }
    
    // Clear dialplan cache - using Delete with pattern
    m.cache.Delete(ctx, "dialplan:*")
    
    log.Info("Dialplan created successfully in ARA")
    return nil
}

// DialplanExtension represents a dialplan extension
type DialplanExtension struct {
    Exten    string
    Priority int
    App      string
    AppData  string
    Label    string // For Asterisk labels
}

func (m *Manager) insertExtensions(tx *sql.Tx, context string, extensions []DialplanExtension) error {
    stmt, err := tx.Prepare(`
        INSERT INTO extensions (context, exten, priority, app, appdata)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            app = VALUES(app),
            appdata = VALUES(appdata)`)
    
    if err != nil {
        return errors.Wrap(err, errors.ErrDatabase, "failed to prepare statement")
    }
    defer stmt.Close()
    
    for _, ext := range extensions {
        if _, err := stmt.Exec(context, ext.Exten, ext.Priority, ext.App, ext.AppData); err != nil {
            return errors.Wrap(err, errors.ErrDatabase, fmt.Sprintf("failed to insert extension %s@%s", ext.Exten, context))
        }
    }
    
    return nil
}
func (m *Manager) GetEndpoint(ctx context.Context, name string) (*Endpoint, error) {
    cacheKey := fmt.Sprintf("endpoint:%s", name)
    
    // Try cache first
    var endpoint Endpoint
    if err := m.cache.Get(ctx, cacheKey, &endpoint); err == nil {
        return &endpoint, nil
    }
    
    // Query database
    query := `
        SELECT e.id, e.transport, e.aors, e.auth, e.context, e.allow,
               e.direct_media, e.dtmf_mode, e.media_encryption,
               a.username, a.password,
               i.` + "`match`" + ` as ip_match
        FROM ps_endpoints e
        LEFT JOIN ps_auths a ON e.auth = a.id
        LEFT JOIN ps_endpoint_id_ips i ON i.endpoint = e.id
        WHERE e.id = ?`
    
    err := m.db.QueryRowContext(ctx, query, fmt.Sprintf("endpoint-%s", name)).Scan(
        &endpoint.ID, &endpoint.Transport, &endpoint.AORs, &endpoint.Auth,
        &endpoint.Context, &endpoint.Allow, &endpoint.DirectMedia,
        &endpoint.DTMFMode, &endpoint.MediaEncryption,
        &endpoint.Username, &endpoint.Password, &endpoint.IPMatch,
    )
    
    if err == sql.ErrNoRows {
        return nil, errors.New(errors.ErrProviderNotFound, "endpoint not found")
    }
    if err != nil {
        return nil, errors.Wrap(err, errors.ErrDatabase, "failed to query endpoint")
    }
    
    // Cache for 5 minutes
    m.cache.Set(ctx, cacheKey, endpoint, 5*time.Minute)
    
    return &endpoint, nil
}

type Endpoint struct {
    ID              string
    Transport       string
    AORs            string
    Auth            string
    Context         string
    Allow           string
    DirectMedia     string
    DTMFMode        string
    MediaEncryption string
    Username        sql.NullString
    Password        sql.NullString
    IPMatch         sql.NullString
}

// ReloadEndpoints triggers Asterisk to reload PJSIP
func (m *Manager) ReloadEndpoints(ctx context.Context) error {
    // This would typically use AMI to reload
    // For now, we'll mark it as needing reload
    logger.WithContext(ctx).Info("PJSIP endpoints need reload")
    return nil
}

// ReloadDialplan triggers Asterisk to reload dialplan
func (m *Manager) ReloadDialplan(ctx context.Context) error {
    // This would typically use AMI to reload
    logger.WithContext(ctx).Info("Dialplan needs reload")
    return nil
}
