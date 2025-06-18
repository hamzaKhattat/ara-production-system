#!/bin/bash
# save as: setup_database.sh

# Database credentials
DB_USER="root"
DB_PASS="temppass"
DB_NAME="asterisk_ara"

echo "=== ARA Router Database Setup ==="
echo "This will create/recreate the database: $DB_NAME"
echo "Press Ctrl+C to cancel, or Enter to continue..."
read

# Backup existing database if it exists
if mysql -u $DB_USER -p$DB_PASS -e "USE $DB_NAME;" 2>/dev/null; then
    echo "Backing up existing database..."
    mysqldump -u $DB_USER -p$DB_PASS $DB_NAME > backup_${DB_NAME}_$(date +%Y%m%d_%H%M%S).sql
    echo "Backup saved to: backup_${DB_NAME}_$(date +%Y%m%d_%H%M%S).sql"
fi

# Create database
echo "Creating database..."
mysql -u $DB_USER -p$DB_PASS << EOF
DROP DATABASE IF EXISTS $DB_NAME;
CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON $DB_NAME.* TO 'asterisk'@'localhost' IDENTIFIED BY '$DB_PASS';
FLUSH PRIVILEGES;
USE $DB_NAME;

-- Migration tracking table
CREATE TABLE IF NOT EXISTS schema_migrations (
    version BIGINT NOT NULL PRIMARY KEY,
    dirty BOOLEAN NOT NULL DEFAULT FALSE
);

-- Providers table
CREATE TABLE IF NOT EXISTS providers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    type ENUM('inbound', 'intermediate', 'final') NOT NULL,
    host VARCHAR(255) NOT NULL,
    port INT DEFAULT 5060,
    username VARCHAR(100),
    password VARCHAR(255),
    auth_type ENUM('userpass', 'ip', 'md5') DEFAULT 'userpass',
    transport ENUM('udp', 'tcp', 'tls', 'ws', 'wss') DEFAULT 'udp',
    codecs JSON,
    dtmf_mode ENUM('rfc2833', 'info', 'inband', 'auto') DEFAULT 'rfc2833',
    nat BOOLEAN DEFAULT FALSE,
    qualify BOOLEAN DEFAULT TRUE,
    context VARCHAR(100),
    from_user VARCHAR(100),
    from_domain VARCHAR(255),
    insecure VARCHAR(50),
    direct_media BOOLEAN DEFAULT FALSE,
    media_encryption ENUM('no', 'sdes', 'dtls') DEFAULT 'no',
    trust_rpid BOOLEAN DEFAULT FALSE,
    send_rpid BOOLEAN DEFAULT FALSE,
    rewrite_contact BOOLEAN DEFAULT TRUE,
    force_rport BOOLEAN DEFAULT TRUE,
    rtp_symmetric BOOLEAN DEFAULT TRUE,
    max_channels INT DEFAULT 0,
    current_channels INT DEFAULT 0,
    priority INT DEFAULT 10,
    weight INT DEFAULT 1,
    cost_per_minute DECIMAL(10,4) DEFAULT 0.0000,
    active BOOLEAN DEFAULT TRUE,
    health_check_enabled BOOLEAN DEFAULT TRUE,
    health_check_interval INT DEFAULT 60,
    last_health_check TIMESTAMP NULL,
    health_status ENUM('healthy', 'degraded', 'unhealthy', 'unknown') DEFAULT 'unknown',
    country VARCHAR(50),
    region VARCHAR(100),
    city VARCHAR(100),
    metadata JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_type (type),
    INDEX idx_active (active),
    INDEX idx_health_status (health_status),
    INDEX idx_country (country),
    INDEX idx_region (region)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- DIDs table
CREATE TABLE IF NOT EXISTS dids (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    did VARCHAR(50) UNIQUE NOT NULL,
    provider_id INT NOT NULL,
    provider_name VARCHAR(100) NOT NULL,
    in_use BOOLEAN DEFAULT FALSE,
    allocated_to VARCHAR(255),
    allocation_time TIMESTAMP NULL,
    country VARCHAR(50),
    region VARCHAR(100),
    city VARCHAR(100),
    monthly_cost DECIMAL(10,2) DEFAULT 0.00,
    setup_cost DECIMAL(10,2) DEFAULT 0.00,
    per_minute_cost DECIMAL(10,4) DEFAULT 0.0000,
    active BOOLEAN DEFAULT TRUE,
    metadata JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_provider (provider_id),
    INDEX idx_in_use (in_use),
    INDEX idx_country (country),
    FOREIGN KEY (provider_id) REFERENCES providers(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Provider routes table
CREATE TABLE IF NOT EXISTS provider_routes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    inbound_provider VARCHAR(100) NOT NULL,
    intermediate_provider VARCHAR(100) NOT NULL,
    final_provider VARCHAR(100) NOT NULL,
    inbound_is_group BOOLEAN DEFAULT FALSE,
    intermediate_is_group BOOLEAN DEFAULT FALSE,
    final_is_group BOOLEAN DEFAULT FALSE,
    load_balance_mode ENUM('round_robin', 'least_used', 'weight', 'random', 'failover') DEFAULT 'round_robin',
    priority INT DEFAULT 10,
    weight INT DEFAULT 1,
    max_concurrent_calls INT DEFAULT 0,
    current_calls INT DEFAULT 0,
    enabled BOOLEAN DEFAULT TRUE,
    failover_routes JSON,
    routing_rules JSON,
    metadata JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_inbound (inbound_provider),
    INDEX idx_enabled (enabled),
    INDEX idx_priority (priority)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Call records table
CREATE TABLE IF NOT EXISTS call_records (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    call_id VARCHAR(100) UNIQUE NOT NULL,
    route_id INT,
    route_name VARCHAR(100),
    status ENUM('INITIATED', 'ALLOCATING_DID', 'ROUTING', 'CONNECTED', 'COMPLETED', 'FAILED') NOT NULL,
    direction ENUM('inbound', 'outbound') DEFAULT 'inbound',
    original_ani VARCHAR(50),
    original_dnis VARCHAR(50),
    transformed_ani VARCHAR(50),
    assigned_did VARCHAR(50),
    current_step ENUM('ORIGIN', 'INTERMEDIATE', 'FINAL', 'RETURN') DEFAULT 'ORIGIN',
    inbound_provider VARCHAR(100),
    intermediate_provider VARCHAR(100),
    final_provider VARCHAR(100),
    start_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    answer_time TIMESTAMP NULL,
    end_time TIMESTAMP NULL,
    duration INT DEFAULT 0,
    billable_duration INT DEFAULT 0,
    hangup_cause VARCHAR(50),
    hangup_cause_q850 INT,
    sip_response_code INT,
    error_message TEXT,
    metadata JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_call_id (call_id),
    INDEX idx_status (status),
    INDEX idx_start_time (start_time),
    INDEX idx_assigned_did (assigned_did),
    INDEX idx_route (route_id),
    FOREIGN KEY (route_id) REFERENCES provider_routes(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Asterisk Realtime tables for PJSIP
-- Transports
CREATE TABLE IF NOT EXISTS ps_transports (
    id VARCHAR(40) NOT NULL PRIMARY KEY,
    async_operations INT,
    bind VARCHAR(40),
    ca_list_file VARCHAR(200),
    ca_list_path VARCHAR(200),
    cert_file VARCHAR(200),
    cipher VARCHAR(200),
    cos INT,
    domain VARCHAR(40),
    external_media_address VARCHAR(40),
    external_signaling_address VARCHAR(40),
    external_signaling_port INT,
    local_net VARCHAR(40),
    method ENUM('default','unspecified','tlsv1','sslv2','sslv3','sslv23'),
    password VARCHAR(40),
    priv_key_file VARCHAR(200),
    protocol ENUM('udp','tcp','tls','ws','wss'),
    require_client_cert ENUM('yes','no'),
    symmetric_transport ENUM('yes','no'),
    tos INT,
    verify_client ENUM('yes','no'),
    verify_server ENUM('yes','no'),
    websocket_write_timeout INT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- PJSIP AORs (Address of Record)
CREATE TABLE IF NOT EXISTS ps_aors (
    id VARCHAR(40) NOT NULL PRIMARY KEY,
    contact VARCHAR(255),
    default_expiration INT,
    mailboxes VARCHAR(80),
    max_contacts INT,
    minimum_expiration INT,
    remove_existing ENUM('yes','no'),
    qualify_frequency INT,
    authenticate_qualify ENUM('yes','no'),
    maximum_expiration INT,
    outbound_proxy VARCHAR(256),
    support_path ENUM('yes','no'),
    qualify_timeout DECIMAL(3,1),
    voicemail_extension VARCHAR(40),
    remove_unavailable ENUM('yes','no')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- PJSIP Endpoints
CREATE TABLE IF NOT EXISTS ps_endpoints (
    id VARCHAR(40) NOT NULL PRIMARY KEY,
    transport VARCHAR(40),
    aors VARCHAR(200),
    auth VARCHAR(40),
    context VARCHAR(40),
    disallow VARCHAR(200),
    allow VARCHAR(200),
    direct_media ENUM('yes','no'),
    connected_line_method ENUM('invite','reinvite','update'),
    direct_media_method ENUM('invite','reinvite','update'),
    direct_media_glare_mitigation ENUM('none','outgoing','incoming'),
    disable_direct_media_on_nat ENUM('yes','no'),
    dtmf_mode ENUM('rfc4733','inband','info','auto','auto_info'),
    external_media_address VARCHAR(40),
    force_rport ENUM('yes','no'),
    ice_support ENUM('yes','no'),
    identify_by VARCHAR(80),
    mailboxes VARCHAR(40),
    media_address VARCHAR(40),
    media_encryption ENUM('no','sdes','dtls'),
    media_encryption_optimistic ENUM('yes','no'),
    media_use_received_transport ENUM('yes','no'),
    moh_suggest VARCHAR(40),
    mwi_from_user VARCHAR(40),
    mwi_subscribe_replaces_unsolicited ENUM('yes','no'),
    named_call_group VARCHAR(40),
    named_pickup_group VARCHAR(40),
    notify_early_inuse_ringing ENUM('yes','no'),
    outbound_auth VARCHAR(40),
    outbound_proxy VARCHAR(256),
    rewrite_contact ENUM('yes','no'),
    rpid_immediate ENUM('yes','no'),
    rtcp_mux ENUM('yes','no'),
    rtp_engine VARCHAR(40),
    rtp_ipv6 ENUM('yes','no'),
    rtp_symmetric ENUM('yes','no'),
    send_diversion ENUM('yes','no'),
    send_pai ENUM('yes','no'),
    send_rpid ENUM('yes','no'),
    set_var TEXT,
    timers_min_se INT,
    timers ENUM('forced','no','required','yes'),
    timers_sess_expires INT,
    tone_zone VARCHAR(40),
    tos_audio VARCHAR(10),
    tos_video VARCHAR(10),
    trust_id_inbound ENUM('yes','no'),
    trust_id_outbound ENUM('yes','no'),
    use_avpf ENUM('yes','no'),
    use_ptime ENUM('yes','no'),
    webrtc ENUM('yes','no'),
    dtls_verify VARCHAR(40),
    dtls_rekey INT,
    dtls_auto_generate_cert ENUM('yes','no'),
    dtls_cert_file VARCHAR(200),
    dtls_private_key VARCHAR(200),
    dtls_cipher VARCHAR(200),
    dtls_ca_file VARCHAR(200),
    dtls_ca_path VARCHAR(200),
    dtls_setup ENUM('active','passive','actpass'),
    dtls_fingerprint ENUM('SHA-1','SHA-256'),
    100rel ENUM('no','required','yes'),
    aggregate_mwi ENUM('yes','no'),
    bind_rtp_to_media_address ENUM('yes','no'),
    bundle ENUM('yes','no'),
    call_group VARCHAR(40),
    callerid VARCHAR(40),
    callerid_privacy ENUM('allowed_not_screened','allowed_passed_screened','allowed_failed_screened','allowed','prohib_not_screened','prohib_passed_screened','prohib_failed_screened','prohib','unavailable'),
    callerid_tag VARCHAR(40),
    contact_acl VARCHAR(40),
    device_state_busy_at INT,
    fax_detect ENUM('yes','no'),
    fax_detect_timeout INT,
    follow_early_media_fork ENUM('yes','no'),
    from_domain VARCHAR(40),
    from_user VARCHAR(40),
    g726_non_standard ENUM('yes','no'),
    inband_progress ENUM('yes','no'),
    incoming_mwi_mailbox VARCHAR(40),
    language VARCHAR(40),
    max_audio_streams INT,
    max_video_streams INT,
    message_context VARCHAR(40),
    moh_passthrough ENUM('yes','no'),
    one_touch_recording ENUM('yes','no'),
    pickup_group VARCHAR(40),
    preferred_codec_only ENUM('yes','no'),
    record_off_feature VARCHAR(40),
    record_on_feature VARCHAR(40),
    refer_blind_progress ENUM('yes','no'),
    rtp_keepalive INT,
    rtp_timeout INT,
    rtp_timeout_hold INT,
    sdp_owner VARCHAR(40),
    sdp_session VARCHAR(40),
    send_connected_line ENUM('yes','no'),
    send_history_info ENUM('yes','no'),
    srtp_tag_32 ENUM('yes','no'),
    stream_topology VARCHAR(40),
    sub_min_expiry INT,
    subscribe_context VARCHAR(40),
    suppress_q850_reason_headers ENUM('yes','no'),
    t38_udptl ENUM('yes','no'),
    t38_udptl_ec ENUM('none','fec','redundancy'),
    t38_udptl_ipv6 ENUM('yes','no'),
    t38_udptl_maxdatagram INT,
    t38_udptl_nat ENUM('yes','no'),
    user_eq_phone ENUM('yes','no'),
    voicemail_extension VARCHAR(40),
    asymmetric_rtp_codec ENUM('yes','no'),
    incoming_call_offer_pref ENUM('local','local_first','remote','remote_first'),
    moh_suggest_default ENUM('yes','no'),
    outgoing_call_offer_pref ENUM('local','local_merge','local_first','remote','remote_merge','remote_first'),
    redirect_method ENUM('user','uri_core','uri_pjsip'),
    stir_shaken ENUM('yes','no')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- PJSIP Auth
CREATE TABLE IF NOT EXISTS ps_auths (
    id VARCHAR(40) NOT NULL PRIMARY KEY,
    auth_type ENUM('userpass','md5'),
    nonce_lifetime INT,
    md5_cred VARCHAR(40),
    password VARCHAR(80),
    realm VARCHAR(40),
    username VARCHAR(40)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- PJSIP Endpoint identifiers (for IP auth)
CREATE TABLE IF NOT EXISTS ps_endpoint_id_ips (
    id INT AUTO_INCREMENT PRIMARY KEY,
    endpoint VARCHAR(40),
    match VARCHAR(80),
    srv_lookups ENUM('yes','no'),
    match_header VARCHAR(255),
    INDEX idx_endpoint (endpoint)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- PJSIP Globals
CREATE TABLE IF NOT EXISTS ps_globals (
    id VARCHAR(40) NOT NULL PRIMARY KEY,
    max_forwards INT,
    user_agent VARCHAR(255),
    default_outbound_endpoint VARCHAR(40),
    debug ENUM('yes','no'),
    endpoint_identifier_order VARCHAR(40),
    max_initial_qualify_time INT,
    default_from_user VARCHAR(80),
    keep_alive_interval INT,
    regcontext VARCHAR(80),
    contact_expiration_check_interval INT,
    default_voicemail_extension VARCHAR(40),
    disable_multi_domain ENUM('yes','no'),
    unidentified_request_count INT,
    unidentified_request_period INT,
    unidentified_request_prune_interval INT,
    default_realm VARCHAR(40),
    mwi_tps_queue_high INT,
    mwi_tps_queue_low INT,
    mwi_disable_initial_unsolicited ENUM('yes','no'),
    ignore_uri_user_options ENUM('yes','no'),
    use_callerid_contact ENUM('yes','no'),
    send_contact_status_on_update_registration ENUM('yes','no')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Dialplan extensions table
CREATE TABLE IF NOT EXISTS extensions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    context VARCHAR(40) NOT NULL,
    exten VARCHAR(40) NOT NULL,
    priority INT NOT NULL,
    app VARCHAR(40) NOT NULL,
    appdata VARCHAR(256),
    UNIQUE KEY unique_context_exten_priority (context, exten, priority),
    INDEX idx_context (context),
    INDEX idx_exten (exten)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Provider groups table
CREATE TABLE IF NOT EXISTS provider_groups (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    group_type ENUM('manual', 'regex', 'metadata', 'dynamic') DEFAULT 'manual',
    match_pattern VARCHAR(255),
    match_field VARCHAR(100),
    match_operator ENUM('equals', 'contains', 'starts_with', 'ends_with', 'regex', 'in', 'not_in') DEFAULT 'equals',
    match_value JSON,
    provider_type ENUM('inbound', 'intermediate', 'final', 'any') DEFAULT 'any',
    enabled BOOLEAN DEFAULT TRUE,
    priority INT DEFAULT 10,
    metadata JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_enabled (enabled),
    INDEX idx_type (group_type),
    INDEX idx_provider_type (provider_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Provider group members
CREATE TABLE IF NOT EXISTS provider_group_members (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    group_id INT NOT NULL,
    provider_id INT NOT NULL,
    provider_name VARCHAR(100) NOT NULL,
    added_manually BOOLEAN DEFAULT FALSE,
    matched_by_rule BOOLEAN DEFAULT FALSE,
    priority_override INT,
    weight_override INT,
    metadata JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY unique_group_provider (group_id, provider_id),
    INDEX idx_group (group_id),
    INDEX idx_provider (provider_name),
    FOREIGN KEY (group_id) REFERENCES provider_groups(id) ON DELETE CASCADE,
    FOREIGN KEY (provider_id) REFERENCES providers(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Statistics tables
CREATE TABLE IF NOT EXISTS provider_stats (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    provider_name VARCHAR(100) NOT NULL,
    stat_type ENUM('minute', 'hour', 'day') NOT NULL,
    period_start TIMESTAMP NOT NULL,
    total_calls BIGINT DEFAULT 0,
    completed_calls BIGINT DEFAULT 0,
    failed_calls BIGINT DEFAULT 0,
    total_duration BIGINT DEFAULT 0,
    total_cost DECIMAL(10,2) DEFAULT 0.00,
    asr DECIMAL(5,2) DEFAULT 0.00,
    acd DECIMAL(10,2) DEFAULT 0.00,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY unique_provider_period (provider_name, stat_type, period_start),
    INDEX idx_provider (provider_name),
    INDEX idx_period (period_start)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Insert default data
INSERT INTO ps_globals (id, max_forwards, user_agent, debug) 
VALUES ('global', 70, 'ARA-Router/2.0', 'no');

INSERT INTO ps_transports (id, bind, protocol) 
VALUES ('transport-udp', '0.0.0.0:5060', 'udp');

-- Mark initial migration as complete
INSERT INTO schema_migrations (version, dirty) VALUES (1, false);

EOF

echo "✓ Database setup complete!"
echo ""
echo "Database: $DB_NAME"
echo "User: root"
echo "Password: $DB_PASS"
echo ""
echo "Tables created:"
mysql -u $DB_USER -p$DB_PASS $DB_NAME -e "SHOW TABLES;" 2>/dev/null
chmod +x setup_database.sh
./setup_database.sh
