package db

import (
    "context"
    "database/sql"
    "fmt"
    "strings"
    
    "github.com/hamzaKhattat/ara-production-system/pkg/logger"
)

// InitializeDatabase completely resets and recreates the database
func InitializeDatabase(ctx context.Context, db *sql.DB, dropExisting bool) error {
    log := logger.WithContext(ctx)
    
    if dropExisting {
        log.Warn("Dropping existing tables and data...")
        if err := dropAllTables(ctx, db); err != nil {
            return fmt.Errorf("failed to drop existing tables: %w", err)
        }
    }
    
    log.Info("Creating database schema...")
    
    // Create tables in correct order due to foreign key constraints
    if err := createCoreTables(ctx, db); err != nil {
        return fmt.Errorf("failed to create core tables: %w", err)
    }
    
    if err := createARATables(ctx, db); err != nil {
        return fmt.Errorf("failed to create ARA tables: %w", err)
    }
    
    if err := createStoredProcedures(ctx, db); err != nil {
        return fmt.Errorf("failed to create stored procedures: %w", err)
    }
    
    if err := createViews(ctx, db); err != nil {
        return fmt.Errorf("failed to create views: %w", err)
    }
    
    if err := insertInitialData(ctx, db); err != nil {
        return fmt.Errorf("failed to insert initial data: %w", err)
    }
    
    if err := createDialplan(ctx, db); err != nil {
        return fmt.Errorf("failed to create dialplan: %w", err)
    }
    
    log.Info("Database initialization completed successfully")
    return nil
}

func dropAllTables(ctx context.Context, db *sql.DB) error {
    // Disable foreign key checks
    if _, err := db.ExecContext(ctx, "SET FOREIGN_KEY_CHECKS = 0"); err != nil {
        return err
    }
    
    // Get all tables
    rows, err := db.QueryContext(ctx, `
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = DATABASE()
    `)
    if err != nil {
        return err
    }
    defer rows.Close()
    
    var tables []string
    for rows.Next() {
        var tableName string
        if err := rows.Scan(&tableName); err != nil {
            continue
        }
        tables = append(tables, tableName)
    }
    
    // Drop each table
    for _, table := range tables {
        if _, err := db.ExecContext(ctx, fmt.Sprintf("DROP TABLE IF EXISTS `%s`", table)); err != nil {
            logger.WithContext(ctx).WithError(err).WithField("table", table).Warn("Failed to drop table")
        }
    }
    
    // Re-enable foreign key checks
    if _, err := db.ExecContext(ctx, "SET FOREIGN_KEY_CHECKS = 1"); err != nil {
        return err
    }
    
    return nil
}

func createCoreTables(ctx context.Context, db *sql.DB) error {
    queries := []string{
        // Providers table
        `CREATE TABLE IF NOT EXISTS providers (
            id INT AUTO_INCREMENT PRIMARY KEY,
            name VARCHAR(100) UNIQUE NOT NULL,
            type ENUM('inbound', 'intermediate', 'final') NOT NULL,
            host VARCHAR(255) NOT NULL,
            port INT DEFAULT 5060,
            username VARCHAR(100),
            password VARCHAR(100),
            auth_type ENUM('ip', 'credentials', 'both') DEFAULT 'ip',
            transport VARCHAR(10) DEFAULT 'udp',
            codecs JSON,
            max_channels INT DEFAULT 0,
            current_channels INT DEFAULT 0,
            priority INT DEFAULT 10,
            weight INT DEFAULT 1,
            cost_per_minute DECIMAL(10,4) DEFAULT 0,
            active BOOLEAN DEFAULT TRUE,
            health_check_enabled BOOLEAN DEFAULT TRUE,
            last_health_check TIMESTAMP NULL,
            health_status VARCHAR(50) DEFAULT 'unknown',
            country VARCHAR(50),
            region VARCHAR(100),
            city VARCHAR(100),
            metadata JSON,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_type (type),
            INDEX idx_active (active),
            INDEX idx_priority (priority DESC)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // DIDs table
        `CREATE TABLE IF NOT EXISTS dids (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            number VARCHAR(20) UNIQUE NOT NULL,
            provider_id INT,
            provider_name VARCHAR(100),
            in_use BOOLEAN DEFAULT FALSE,
            destination VARCHAR(100),
            allocation_time TIMESTAMP NULL,
            released_at TIMESTAMP NULL,
            last_used_at TIMESTAMP NULL,
            usage_count BIGINT DEFAULT 0,
            country VARCHAR(50),
            city VARCHAR(100),
            rate_center VARCHAR(100),
            monthly_cost DECIMAL(10,2) DEFAULT 0,
            per_minute_cost DECIMAL(10,4) DEFAULT 0,
            metadata JSON,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_in_use (in_use),
            INDEX idx_provider (provider_name),
            INDEX idx_last_used (last_used_at),
            FOREIGN KEY (provider_id) REFERENCES providers(id) ON DELETE SET NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // Provider groups
        `CREATE TABLE IF NOT EXISTS provider_groups (
            id INT AUTO_INCREMENT PRIMARY KEY,
            name VARCHAR(100) UNIQUE NOT NULL,
            description TEXT,
            group_type ENUM('manual', 'regex', 'metadata', 'dynamic') NOT NULL,
            match_pattern VARCHAR(255),
            match_field VARCHAR(100),
            match_operator ENUM('equals', 'contains', 'starts_with', 'ends_with', 'regex', 'in', 'not_in'),
            match_value JSON,
            provider_type ENUM('inbound', 'intermediate', 'final', 'any') DEFAULT 'any',
            enabled BOOLEAN DEFAULT TRUE,
            priority INT DEFAULT 10,
            metadata JSON,
            member_count INT DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_type (group_type),
            INDEX idx_enabled (enabled)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // Provider group members
        `CREATE TABLE IF NOT EXISTS provider_group_members (
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
            INDEX idx_provider (provider_id),
            FOREIGN KEY (group_id) REFERENCES provider_groups(id) ON DELETE CASCADE,
            FOREIGN KEY (provider_id) REFERENCES providers(id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // Provider routes with group support
        `CREATE TABLE IF NOT EXISTS provider_routes (
            id INT AUTO_INCREMENT PRIMARY KEY,
            name VARCHAR(100) UNIQUE NOT NULL,
            description TEXT,
            inbound_provider VARCHAR(100) NOT NULL,
            intermediate_provider VARCHAR(100) NOT NULL,
            final_provider VARCHAR(100) NOT NULL,
            inbound_is_group BOOLEAN DEFAULT FALSE,
            intermediate_is_group BOOLEAN DEFAULT FALSE,
            final_is_group BOOLEAN DEFAULT FALSE,
            load_balance_mode ENUM('round_robin', 'weighted', 'priority', 'failover', 'least_connections', 'response_time', 'hash') DEFAULT 'round_robin',
            priority INT DEFAULT 0,
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
            INDEX idx_priority (priority DESC)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // Call records
        `CREATE TABLE IF NOT EXISTS call_records (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            call_id VARCHAR(100) UNIQUE NOT NULL,
            original_ani VARCHAR(20) NOT NULL,
            original_dnis VARCHAR(20) NOT NULL,
            transformed_ani VARCHAR(20),
            assigned_did VARCHAR(20),
            inbound_provider VARCHAR(100),
            intermediate_provider VARCHAR(100),
            final_provider VARCHAR(100),
            route_name VARCHAR(100),
            status ENUM('INITIATED', 'ACTIVE', 'RETURNED_FROM_S3', 'ROUTING_TO_S4', 'COMPLETED', 'FAILED', 'ABANDONED', 'TIMEOUT') DEFAULT 'INITIATED',
            current_step VARCHAR(50),
            failure_reason VARCHAR(255),
            start_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            answer_time TIMESTAMP NULL,
            end_time TIMESTAMP NULL,
            duration INT DEFAULT 0,
            billable_duration INT DEFAULT 0,
            recording_path VARCHAR(255),
            sip_response_code INT,
            quality_score DECIMAL(3,2),
            metadata JSON,
            INDEX idx_call_id (call_id),
            INDEX idx_status (status),
            INDEX idx_start_time (start_time),
            INDEX idx_providers (inbound_provider, intermediate_provider, final_provider),
            INDEX idx_did (assigned_did)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // Call verifications
        `CREATE TABLE IF NOT EXISTS call_verifications (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            call_id VARCHAR(100) NOT NULL,
            verification_step VARCHAR(50) NOT NULL,
            expected_ani VARCHAR(20),
            expected_dnis VARCHAR(20),
            received_ani VARCHAR(20),
            received_dnis VARCHAR(20),
            source_ip VARCHAR(45),
            expected_ip VARCHAR(45),
            verified BOOLEAN DEFAULT FALSE,
            failure_reason VARCHAR(255),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_call_id (call_id),
            INDEX idx_verified (verified),
            INDEX idx_created (created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // Provider statistics
        `CREATE TABLE IF NOT EXISTS provider_stats (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            provider_name VARCHAR(100) NOT NULL,
            stat_type ENUM('minute', 'hour', 'day') NOT NULL,
            period_start TIMESTAMP NOT NULL,
            total_calls BIGINT DEFAULT 0,
            completed_calls BIGINT DEFAULT 0,
            failed_calls BIGINT DEFAULT 0,
            total_duration BIGINT DEFAULT 0,
            avg_duration DECIMAL(10,2) DEFAULT 0,
            asr DECIMAL(5,2) DEFAULT 0,
            acd DECIMAL(10,2) DEFAULT 0,
            avg_response_time INT DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY unique_provider_period (provider_name, stat_type, period_start),
            INDEX idx_provider (provider_name),
            INDEX idx_period (period_start)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // Provider health
        `CREATE TABLE IF NOT EXISTS provider_health (
            id INT AUTO_INCREMENT PRIMARY KEY,
            provider_name VARCHAR(100) UNIQUE NOT NULL,
            health_score INT DEFAULT 100,
            latency_ms INT DEFAULT 0,
            packet_loss DECIMAL(5,2) DEFAULT 0,
            jitter_ms INT DEFAULT 0,
            active_calls INT DEFAULT 0,
            max_calls INT DEFAULT 0,
            last_success_at TIMESTAMP NULL,
            last_failure_at TIMESTAMP NULL,
            consecutive_failures INT DEFAULT 0,
            is_healthy BOOLEAN DEFAULT TRUE,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_healthy (is_healthy),
            INDEX idx_updated (updated_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // Audit log
        `CREATE TABLE IF NOT EXISTS audit_log (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            event_type VARCHAR(50) NOT NULL,
            entity_type VARCHAR(50) NOT NULL,
            entity_id VARCHAR(100),
            user_id VARCHAR(100),
            ip_address VARCHAR(45),
            action VARCHAR(50) NOT NULL,
            old_value JSON,
            new_value JSON,
            metadata JSON,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_event_type (event_type),
            INDEX idx_entity (entity_type, entity_id),
            INDEX idx_created (created_at),
            INDEX idx_user (user_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
    }
    
    for _, query := range queries {
        if _, err := db.ExecContext(ctx, query); err != nil {
            return fmt.Errorf("failed to execute query: %w", err)
        }
    }
    
    return nil
}

func createARATables(ctx context.Context, db *sql.DB) error {
    queries := []string{
        // PJSIP transports
        `CREATE TABLE IF NOT EXISTS ps_transports (
            id VARCHAR(40) PRIMARY KEY,
            async_operations INT DEFAULT 1,
            bind VARCHAR(40),
            ca_list_file VARCHAR(200),
            ca_list_path VARCHAR(200),
            cert_file VARCHAR(200),
            cipher VARCHAR(200),
            cos INT DEFAULT 0,
            domain VARCHAR(40),
            external_media_address VARCHAR(40),
            external_signaling_address VARCHAR(40),
            external_signaling_port INT DEFAULT 0,
            local_net VARCHAR(40),
            method VARCHAR(40),
            password VARCHAR(40),
            priv_key_file VARCHAR(200),
            protocol VARCHAR(40),
            require_client_cert VARCHAR(40),
            tos INT DEFAULT 0,
            verify_client VARCHAR(40),
            verify_server VARCHAR(40),
            allow_reload VARCHAR(3) DEFAULT 'yes',
            symmetric_transport VARCHAR(3) DEFAULT 'no'
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // PJSIP systems
        `CREATE TABLE IF NOT EXISTS ps_systems (
            id VARCHAR(40) PRIMARY KEY,
            timer_t1 INT DEFAULT 500,
            timer_b INT DEFAULT 32000,
            compact_headers VARCHAR(3) DEFAULT 'no',
            threadpool_initial_size INT DEFAULT 0,
            threadpool_auto_increment INT DEFAULT 5,
            threadpool_idle_timeout INT DEFAULT 60,
            threadpool_max_size INT DEFAULT 50,
            disable_tcp_switch VARCHAR(3) DEFAULT 'yes',
            follow_early_media_fork VARCHAR(3) DEFAULT 'yes',
            accept_multiple_sdp_answers VARCHAR(3) DEFAULT 'no',
            disable_rport VARCHAR(3) DEFAULT 'no',
            use_callerid_contact VARCHAR(3) DEFAULT 'no'
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // PJSIP endpoints
        `CREATE TABLE IF NOT EXISTS ps_endpoints (
            id VARCHAR(40) PRIMARY KEY,
            transport VARCHAR(40),
            aors VARCHAR(200),
            auth VARCHAR(100),
            context VARCHAR(40) DEFAULT 'default',
            disallow VARCHAR(200) DEFAULT 'all',
            allow VARCHAR(200),
            direct_media VARCHAR(3) DEFAULT 'yes',
            connected_line_method VARCHAR(40) DEFAULT 'invite',
            direct_media_method VARCHAR(40) DEFAULT 'invite',
            direct_media_glare_mitigation VARCHAR(40) DEFAULT 'none',
            disable_direct_media_on_nat VARCHAR(3) DEFAULT 'no',
            dtmf_mode VARCHAR(40) DEFAULT 'rfc4733',
            external_media_address VARCHAR(40),
            force_rport VARCHAR(3) DEFAULT 'yes',
            ice_support VARCHAR(3) DEFAULT 'no',
            identify_by VARCHAR(40) DEFAULT 'username,ip',
            mailboxes VARCHAR(40),
            moh_suggest VARCHAR(40) DEFAULT 'default',
            outbound_auth VARCHAR(40),
            outbound_proxy VARCHAR(40),
            rewrite_contact VARCHAR(3) DEFAULT 'no',
            rtp_ipv6 VARCHAR(3) DEFAULT 'no',
            rtp_symmetric VARCHAR(3) DEFAULT 'no',
            send_diversion VARCHAR(3) DEFAULT 'yes',
            send_pai VARCHAR(3) DEFAULT 'no',
            send_rpid VARCHAR(3) DEFAULT 'no',
            timers_min_se INT DEFAULT 90,
            timers VARCHAR(3) DEFAULT 'yes',
            timers_sess_expires INT DEFAULT 1800,
            callerid VARCHAR(40),
            callerid_privacy VARCHAR(40),
            callerid_tag VARCHAR(40),
            trust_id_inbound VARCHAR(3) DEFAULT 'no',
            trust_id_outbound VARCHAR(3) DEFAULT 'no',
            send_connected_line VARCHAR(3) DEFAULT 'yes',
            accountcode VARCHAR(20),
            language VARCHAR(10) DEFAULT 'en',
            rtp_engine VARCHAR(40) DEFAULT 'asterisk',
            dtls_verify VARCHAR(40),
            dtls_rekey VARCHAR(40),
            dtls_cert_file VARCHAR(200),
            dtls_private_key VARCHAR(200),
            dtls_cipher VARCHAR(200),
            dtls_ca_file VARCHAR(200),
            dtls_ca_path VARCHAR(200),
            dtls_setup VARCHAR(40),
            srtp_tag_32 VARCHAR(3) DEFAULT 'no',
            media_encryption VARCHAR(40) DEFAULT 'no',
            use_avpf VARCHAR(3) DEFAULT 'no',
            force_avp VARCHAR(3) DEFAULT 'no',
            media_use_received_transport VARCHAR(3) DEFAULT 'no',
            rtp_timeout INT DEFAULT 0,
            rtp_timeout_hold INT DEFAULT 0,
            rtp_keepalive INT DEFAULT 0,
            record_on_feature VARCHAR(40),
            record_off_feature VARCHAR(40),
            allow_transfer VARCHAR(3) DEFAULT 'yes',
            user_eq_phone VARCHAR(3) DEFAULT 'no',
            moh_passthrough VARCHAR(3) DEFAULT 'no',
            media_encryption_optimistic VARCHAR(3) DEFAULT 'no',
            rpid_immediate VARCHAR(3) DEFAULT 'no',
            g726_non_standard VARCHAR(3) DEFAULT 'no',
            inband_progress VARCHAR(3) DEFAULT 'no',
            call_group VARCHAR(40),
            pickup_group VARCHAR(40),
            named_call_group VARCHAR(40),
            named_pickup_group VARCHAR(40),
            device_state_busy_at INT DEFAULT 0,
            t38_udptl VARCHAR(3) DEFAULT 'no',
            t38_udptl_ec VARCHAR(40),
            t38_udptl_maxdatagram INT DEFAULT 0,
            fax_detect VARCHAR(3) DEFAULT 'no',
            fax_detect_timeout INT DEFAULT 0,
            t38_udptl_nat VARCHAR(3) DEFAULT 'no',
            t38_udptl_ipv6 VARCHAR(3) DEFAULT 'no',
            rtcp_mux VARCHAR(3) DEFAULT 'no',
            allow_overlap VARCHAR(3) DEFAULT 'yes',
            bundle VARCHAR(3) DEFAULT 'no',
            webrtc VARCHAR(3) DEFAULT 'no',
            dtls_fingerprint VARCHAR(40),
            incoming_mwi_mailbox VARCHAR(40),
            follow_early_media_fork VARCHAR(3) DEFAULT 'yes',
            accept_multiple_sdp_answers VARCHAR(3) DEFAULT 'no',
            suppress_q850_reason_headers VARCHAR(3) DEFAULT 'no',
            trust_connected_line VARCHAR(3) DEFAULT 'yes',
            send_history_info VARCHAR(3) DEFAULT 'no',
            prefer_ipv6 VARCHAR(3) DEFAULT 'no',
            bind_rtp_to_media_address VARCHAR(3) DEFAULT 'no',
            INDEX idx_identify_by (identify_by)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // PJSIP auth
        `CREATE TABLE IF NOT EXISTS ps_auths (
            id VARCHAR(40) PRIMARY KEY,
            auth_type VARCHAR(40) DEFAULT 'userpass',
            nonce_lifetime INT DEFAULT 32,
            md5_cred VARCHAR(40),
            password VARCHAR(80),
            realm VARCHAR(40),
            username VARCHAR(40)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // PJSIP AORs
        `CREATE TABLE IF NOT EXISTS ps_aors (
            id VARCHAR(40) PRIMARY KEY,
            contact VARCHAR(255),
            default_expiration INT DEFAULT 3600,
            mailboxes VARCHAR(80),
            max_contacts INT DEFAULT 1,
            minimum_expiration INT DEFAULT 60,
            remove_existing VARCHAR(3) DEFAULT 'yes',
            qualify_frequency INT DEFAULT 0,
            authenticate_qualify VARCHAR(3) DEFAULT 'no',
            maximum_expiration INT DEFAULT 7200,
            outbound_proxy VARCHAR(40),
            support_path VARCHAR(3) DEFAULT 'no',
            qualify_timeout DECIMAL(5,3) DEFAULT 3.0,
            voicemail_extension VARCHAR(40),
            remove_unavailable VARCHAR(3) DEFAULT 'no'
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // PJSIP endpoint identifiers by IP
        `CREATE TABLE IF NOT EXISTS ps_endpoint_id_ips (
            id VARCHAR(40) PRIMARY KEY,
            endpoint VARCHAR(40),
            ` + "`match`" + ` VARCHAR(80) NOT NULL,
            srv_lookups VARCHAR(3) DEFAULT 'yes',
            match_header VARCHAR(255),
            INDEX idx_endpoint (endpoint),
            INDEX idx_match (` + "`match`" + `)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // PJSIP contacts
        `CREATE TABLE IF NOT EXISTS ps_contacts (
            id VARCHAR(40) PRIMARY KEY,
            uri VARCHAR(255),
            endpoint_name VARCHAR(40),
            aor VARCHAR(40),
            qualify_frequency INT DEFAULT 0,
            user_agent VARCHAR(255)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // PJSIP globals
        `CREATE TABLE IF NOT EXISTS ps_globals (
            id VARCHAR(40) PRIMARY KEY,
            max_forwards INT DEFAULT 70,
            user_agent VARCHAR(255) DEFAULT 'Asterisk PBX',
            default_outbound_endpoint VARCHAR(40),
            debug VARCHAR(3) DEFAULT 'no',
            endpoint_identifier_order VARCHAR(40) DEFAULT 'ip,username,anonymous',
            max_initial_qualify_time INT DEFAULT 0,
            keep_alive_interval INT DEFAULT 30,
            contact_expiration_check_interval INT DEFAULT 30,
            disable_multi_domain VARCHAR(3) DEFAULT 'no',
            unidentified_request_count INT DEFAULT 5,
            unidentified_request_period INT DEFAULT 5,
            unidentified_request_prune_interval INT DEFAULT 30,
            default_from_user VARCHAR(80) DEFAULT 'asterisk',
            default_voicemail_extension VARCHAR(40),
            mwi_tps_queue_high INT DEFAULT 500,
            mwi_tps_queue_low INT DEFAULT -1,
            mwi_disable_initial_unsolicited VARCHAR(3) DEFAULT 'no',
            ignore_uri_user_options VARCHAR(3) DEFAULT 'no',
            send_contact_status_on_update_registration VARCHAR(3) DEFAULT 'no',
            default_realm VARCHAR(40),
            regcontext VARCHAR(80),
            contact_cache_expire INT DEFAULT 0,
            disable_initial_options VARCHAR(3) DEFAULT 'no',
            use_callerid_contact VARCHAR(3) DEFAULT 'no'
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // PJSIP domain aliases
        `CREATE TABLE IF NOT EXISTS ps_domain_aliases (
            id VARCHAR(40) PRIMARY KEY,
            domain VARCHAR(80),
            UNIQUE KEY domain_alias (domain)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // Extensions table for dialplan
        `CREATE TABLE IF NOT EXISTS extensions (
            id INT AUTO_INCREMENT PRIMARY KEY,
            context VARCHAR(40) NOT NULL,
            exten VARCHAR(40) NOT NULL,
            priority INT NOT NULL,
            app VARCHAR(40) NOT NULL,
            appdata VARCHAR(256),
            UNIQUE KEY context_exten_priority (context, exten, priority),
            INDEX idx_context (context),
            INDEX idx_exten (exten)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
        
        // CDR table
        `CREATE TABLE IF NOT EXISTS cdr (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            accountcode VARCHAR(20),
            src VARCHAR(80),
            dst VARCHAR(80),
            dcontext VARCHAR(80),
            clid VARCHAR(80),
            channel VARCHAR(80),
            dstchannel VARCHAR(80),
            lastapp VARCHAR(80),
            lastdata VARCHAR(80),
            start DATETIME,
            answer DATETIME,
            end DATETIME,
            duration INT,
            billsec INT,
            disposition VARCHAR(45),
            amaflags INT,
            uniqueid VARCHAR(32),
            userfield VARCHAR(255),
            peeraccount VARCHAR(20),
            linkedid VARCHAR(32),
            sequence INT,
            INDEX idx_start (start),
            INDEX idx_src (src),
            INDEX idx_dst (dst),
            INDEX idx_uniqueid (uniqueid),
            INDEX idx_accountcode (accountcode)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
    }
    
    for _, query := range queries {
        if _, err := db.ExecContext(ctx, query); err != nil {
            return fmt.Errorf("failed to create ARA table: %w", err)
        }
    }
    
    return nil
}

func createStoredProcedures(ctx context.Context, db *sql.DB) error {
    procedures := []string{
        `DROP PROCEDURE IF EXISTS GetAvailableDID`,
        `CREATE PROCEDURE GetAvailableDID(
            IN p_provider_name VARCHAR(100),
            IN p_destination VARCHAR(100),
            OUT p_did VARCHAR(20)
        )
        BEGIN
            DECLARE v_did VARCHAR(20) DEFAULT NULL;
            DECLARE exit handler for sqlexception
            BEGIN
                ROLLBACK;
                SET p_did = NULL;
            END;
            
            START TRANSACTION;
            
            SELECT number INTO v_did
            FROM dids
            WHERE in_use = 0 
                AND (p_provider_name IS NULL OR provider_name = p_provider_name)
            ORDER BY IFNULL(last_used_at, '1970-01-01'), RAND()
            LIMIT 1
            FOR UPDATE SKIP LOCKED;
            
            IF v_did IS NOT NULL THEN
                UPDATE dids 
                SET in_use = 1,
                    destination = p_destination,
                    allocation_time = NOW(),
                    usage_count = IFNULL(usage_count, 0) + 1,
                    updated_at = NOW()
                WHERE number = v_did;
                
                COMMIT;
            ELSE
                ROLLBACK;
            END IF;
            
            SET p_did = v_did;
        END`,
        
        `DROP PROCEDURE IF EXISTS ReleaseDID`,
        `CREATE PROCEDURE ReleaseDID(
            IN p_did VARCHAR(20)
        )
        BEGIN
            UPDATE dids 
            SET in_use = 0,
                destination = NULL,
                allocation_time = NULL,
                released_at = NOW(),
                last_used_at = NOW()
            WHERE number = p_did;
        END`,
        
        `DROP PROCEDURE IF EXISTS UpdateProviderStats`,
        `CREATE PROCEDURE UpdateProviderStats(
            IN p_provider_name VARCHAR(100),
            IN p_call_success BOOLEAN,
            IN p_duration INT
        )
        BEGIN
            DECLARE v_current_minute TIMESTAMP;
            DECLARE v_current_hour TIMESTAMP;
            DECLARE v_current_day TIMESTAMP;
            
            SET v_current_minute = DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:00');
            SET v_current_hour = DATE_FORMAT(NOW(), '%Y-%m-%d %H:00:00');
            SET v_current_day = DATE_FORMAT(NOW(), '%Y-%m-%d 00:00:00');
            
            -- Update minute stats
            INSERT INTO provider_stats (
                provider_name, stat_type, period_start, 
                total_calls, completed_calls, failed_calls, total_duration
            ) VALUES (
                p_provider_name, 'minute', v_current_minute,
                1, IF(p_call_success, 1, 0), IF(p_call_success, 0, 1), p_duration
            )
            ON DUPLICATE KEY UPDATE
                total_calls = total_calls + 1,
                completed_calls = completed_calls + IF(p_call_success, 1, 0),
                failed_calls = failed_calls + IF(p_call_success, 0, 1),
                total_duration = total_duration + p_duration,
                asr = (completed_calls / total_calls) * 100,
                acd = IF(completed_calls > 0, total_duration / completed_calls, 0);
        END`,
    }
    
    for _, proc := range procedures {
        if _, err := db.ExecContext(ctx, proc); err != nil {
            if !strings.Contains(err.Error(), "PROCEDURE") || !strings.Contains(err.Error(), "does not exist") {
                return fmt.Errorf("failed to create procedure: %w", err)
            }
        }
    }
    
    return nil
}

func createViews(ctx context.Context, db *sql.DB) error {
    views := []string{
        `CREATE OR REPLACE VIEW v_active_calls AS
        SELECT 
            cr.call_id,
            cr.original_ani,
            cr.original_dnis,
            cr.assigned_did,
            cr.route_name,
            cr.status,
            cr.current_step,
            cr.start_time,
            TIMESTAMPDIFF(SECOND, cr.start_time, NOW()) as duration_seconds,
            cr.inbound_provider,
            cr.intermediate_provider,
            cr.final_provider
        FROM call_records cr
        WHERE cr.status IN ('INITIATED', 'ACTIVE', 'RETURNED_FROM_S3', 'ROUTING_TO_S4')
        ORDER BY cr.start_time DESC`,
        
        `CREATE OR REPLACE VIEW v_provider_summary AS
        SELECT 
            p.name,
            p.type,
            p.active,
            ph.health_score,
            ph.active_calls,
            ph.is_healthy,
            ps.total_calls as calls_today,
            ps.asr as asr_today,
            ps.acd as acd_today
        FROM providers p
        LEFT JOIN provider_health ph ON p.name = ph.provider_name
        LEFT JOIN provider_stats ps ON p.name = ps.provider_name 
            AND ps.stat_type = 'day' 
            AND DATE(ps.period_start) = CURDATE()`,
        
        `CREATE OR REPLACE VIEW v_did_utilization AS
        SELECT 
            provider_name,
            COUNT(*) as total_dids,
            SUM(CASE WHEN in_use = 1 THEN 1 ELSE 0 END) as used_dids,
            SUM(CASE WHEN in_use = 0 THEN 1 ELSE 0 END) as available_dids,
            ROUND((SUM(CASE WHEN in_use = 1 THEN 1 ELSE 0 END) / COUNT(*)) * 100, 2) as utilization_percent
        FROM dids
        GROUP BY provider_name`,
    }
    
    for _, view := range views {
        if _, err := db.ExecContext(ctx, view); err != nil {
            return fmt.Errorf("failed to create view: %w", err)
        }
    }
    
    return nil
}

func insertInitialData(ctx context.Context, db *sql.DB) error {
    // Insert initial PJSIP data
    queries := []string{
        // Create initial ps_globals entry
        `INSERT INTO ps_globals (id, endpoint_identifier_order) VALUES ('global', 'ip,username,anonymous') 
         ON DUPLICATE KEY UPDATE endpoint_identifier_order='ip,username,anonymous'`,
        
        // Create initial ps_systems entry
        `INSERT INTO ps_systems (id) VALUES ('default') ON DUPLICATE KEY UPDATE id='default'`,
        
        // Create initial transports
        `INSERT INTO ps_transports (id, bind, protocol) VALUES 
            ('transport-udp', '0.0.0.0:5060', 'udp'),
            ('transport-tcp', '0.0.0.0:5060', 'tcp'),
            ('transport-tls', '0.0.0.0:5061', 'tls')
        ON DUPLICATE KEY UPDATE id=id`,
    }
    
    for _, query := range queries {
        if _, err := db.ExecContext(ctx, query); err != nil {
            return fmt.Errorf("failed to insert initial data: %w", err)
        }
    }
    
    return nil
}

func createDialplan(ctx context.Context, db *sql.DB) error {
    // Clear existing dialplan for our contexts
    if _, err := db.ExecContext(ctx, `
        DELETE FROM extensions WHERE context IN (
            'from-provider-inbound',
            'from-provider-intermediate', 
            'from-provider-final',
            'router-outbound',
            'router-internal',
            'hangup-handler',
            'sub-recording'
        )`); err != nil {
        return fmt.Errorf("failed to clear existing dialplan: %w", err)
    }
    
    // Execute the complete dialplan SQL
    dialplanSQL := getCompleteDialplanSQL()
    if _, err := db.ExecContext(ctx, dialplanSQL); err != nil {
        return fmt.Errorf("failed to create dialplan: %w", err)
    }
    
    return nil
}

func getCompleteDialplanSQL() string {
    return `
-- INBOUND CONTEXT (from S1 providers)
INSERT INTO extensions (context, exten, priority, app, appdata) VALUES
('from-provider-inbound', '_X.', 1, 'NoOp', 'Incoming call from S1: ${CALLERID(num)} -> ${EXTEN}'),
('from-provider-inbound', '_X.', 2, 'Set', 'CHANNEL(hangup_handler_push)=hangup-handler,s,1'),
('from-provider-inbound', '_X.', 3, 'Set', '__CALLID=${UNIQUEID}'),
('from-provider-inbound', '_X.', 4, 'Set', '__INBOUND_PROVIDER=${CHANNEL(endpoint)}'),
('from-provider-inbound', '_X.', 5, 'Set', '__ORIGINAL_ANI=${CALLERID(num)}'),
('from-provider-inbound', '_X.', 6, 'Set', '__ORIGINAL_DNIS=${EXTEN}'),
('from-provider-inbound', '_X.', 7, 'Set', '__SOURCE_IP=${CHANNEL(pjsip,remote_addr)}'),
('from-provider-inbound', '_X.', 8, 'Set', 'CDR(inbound_provider)=${INBOUND_PROVIDER}'),
('from-provider-inbound', '_X.', 9, 'Set', 'CDR(original_ani)=${ORIGINAL_ANI}'),
('from-provider-inbound', '_X.', 10, 'Set', 'CDR(original_dnis)=${ORIGINAL_DNIS}'),
('from-provider-inbound', '_X.', 11, 'Set', 'CDR(call_type)=inbound'),
('from-provider-inbound', '_X.', 12, 'MixMonitor', '${UNIQUEID}.wav,b,/usr/local/bin/post-recording.sh ${UNIQUEID}'),
('from-provider-inbound', '_X.', 13, 'AGI', 'agi://localhost:4573/processIncoming'),
('from-provider-inbound', '_X.', 14, 'GotoIf', '$["${ROUTER_STATUS}" = "success"]?route:failed'),
('from-provider-inbound', '_X.', 15, 'NoOp', 'Routing failed: ${ROUTER_ERROR}'),
('from-provider-inbound', '_X.', 16, 'Hangup', '21'),
('from-provider-inbound', '_X.', 17, 'NoOp', 'Routing to intermediate: ${INTERMEDIATE_PROVIDER}'),
('from-provider-inbound', '_X.', 18, 'Set', 'CALLERID(num)=${ANI_TO_SEND}'),
('from-provider-inbound', '_X.', 19, 'Set', 'CDR(intermediate_provider)=${INTERMEDIATE_PROVIDER}'),
('from-provider-inbound', '_X.', 20, 'Set', 'CDR(assigned_did)=${DID_ASSIGNED}'),
('from-provider-inbound', '_X.', 21, 'Dial', 'PJSIP/${DNIS_TO_SEND}@${NEXT_HOP},180,U(sub-recording^${UNIQUEID})'),
('from-provider-inbound', '_X.', 22, 'Set', 'CDR(sip_response)=${HANGUPCAUSE}'),
('from-provider-inbound', '_X.', 23, 'GotoIf', '$["${DIALSTATUS}" = "ANSWER"]?end:dial_failed'),
('from-provider-inbound', '_X.', 24, 'NoOp', 'Dial failed: ${DIALSTATUS}'),
('from-provider-inbound', '_X.', 25, 'Hangup', ''),
('from-provider-inbound', '_X.', 26, 'Hangup', ''),

-- INTERMEDIATE CONTEXT (from S3 providers)
('from-provider-intermediate', '_X.', 1, 'NoOp', 'Return call from S3: ${CALLERID(num)} -> ${EXTEN}'),
('from-provider-intermediate', '_X.', 2, 'Set', '__INTERMEDIATE_PROVIDER=${CHANNEL(endpoint)}'),
('from-provider-intermediate', '_X.', 3, 'Set', '__SOURCE_IP=${CHANNEL(pjsip,remote_addr)}'),
('from-provider-intermediate', '_X.', 4, 'Set', 'CDR(intermediate_return)=true'),
('from-provider-intermediate', '_X.', 5, 'AGI', 'agi://localhost:4573/processReturn'),
('from-provider-intermediate', '_X.', 6, 'GotoIf', '$["${ROUTER_STATUS}" = "success"]?route:failed'),
('from-provider-intermediate', '_X.', 7, 'NoOp', 'Return routing failed: ${ROUTER_ERROR}'),
('from-provider-intermediate', '_X.', 8, 'Hangup', '21'),
('from-provider-intermediate', '_X.', 9, 'NoOp', 'Routing to final: ${FINAL_PROVIDER}'),
('from-provider-intermediate', '_X.', 10, 'Set', 'CALLERID(num)=${ANI_TO_SEND}'),
('from-provider-intermediate', '_X.', 11, 'Set', 'CDR(final_provider)=${FINAL_PROVIDER}'),
('from-provider-intermediate', '_X.', 12, 'Dial', 'PJSIP/${DNIS_TO_SEND}@${NEXT_HOP},180'),
('from-provider-intermediate', '_X.', 13, 'Set', 'CDR(final_sip_response)=${HANGUPCAUSE}'),
('from-provider-intermediate', '_X.', 14, 'Hangup', ''),

-- FINAL CONTEXT (from S4 providers)
('from-provider-final', '_X.', 1, 'NoOp', 'Final call from S4: ${CALLERID(num)} -> ${EXTEN}'),
('from-provider-final', '_X.', 2, 'Set', '__FINAL_PROVIDER=${CHANNEL(endpoint)}'),
('from-provider-final', '_X.', 3, 'Set', '__SOURCE_IP=${CHANNEL(pjsip,remote_addr)}'),
('from-provider-final', '_X.', 4, 'Set', 'CDR(final_confirmation)=true'),
('from-provider-final', '_X.', 5, 'AGI', 'agi://localhost:4573/processFinal'),
('from-provider-final', '_X.', 6, 'Congestion', '5'),
('from-provider-final', '_X.', 7, 'Hangup', ''),

-- HANGUP HANDLER CONTEXT
('hangup-handler', 's', 1, 'NoOp', 'Call ended: ${UNIQUEID}'),
('hangup-handler', 's', 2, 'Set', 'CDR(end_time)=${EPOCH}'),
('hangup-handler', 's', 3, 'Set', 'CDR(duration)=${CDR(billsec)}'),
('hangup-handler', 's', 4, 'AGI', 'agi://localhost:4573/hangup'),
('hangup-handler', 's', 5, 'Return', ''),

-- RECORDING SUBROUTINE
('sub-recording', 's', 1, 'NoOp', 'Starting recording on originated channel'),
('sub-recording', 's', 2, 'Set', 'AUDIOHOOK_INHERIT(MixMonitor)=yes'),
('sub-recording', 's', 3, 'MixMonitor', '${ARG1}-out.wav,b'),
('sub-recording', 's', 4, 'Return', '');`
}
