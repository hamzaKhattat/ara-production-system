-- Asterisk ARA Dynamic Call Router - Initial Schema
-- Full production schema with ARA tables and routing tables

-- Create database if not exists (handled by application)
-- USE asterisk_ara;

-- ========================================
-- ROUTING AND MANAGEMENT TABLES
-- ========================================

-- Providers table (S1, S3, S4 servers)
CREATE TABLE IF NOT EXISTS providers (
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
   metadata JSON,
   created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
   updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
   INDEX idx_type (type),
   INDEX idx_active (active),
   INDEX idx_priority (priority DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- DID pool for dynamic allocation
CREATE TABLE IF NOT EXISTS dids (
   id BIGINT AUTO_INCREMENT PRIMARY KEY,
   number VARCHAR(20) UNIQUE NOT NULL,
   provider_id INT,
   provider_name VARCHAR(100),
   in_use BOOLEAN DEFAULT FALSE,
   destination VARCHAR(100),
   country VARCHAR(50),
   city VARCHAR(100),
   rate_center VARCHAR(100),
   monthly_cost DECIMAL(10,2) DEFAULT 0,
   per_minute_cost DECIMAL(10,4) DEFAULT 0,
   allocated_at TIMESTAMP NULL,
   released_at TIMESTAMP NULL,
   last_used_at TIMESTAMP NULL,
   usage_count BIGINT DEFAULT 0,
   metadata JSON,
   created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
   updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
   INDEX idx_in_use (in_use),
   INDEX idx_provider (provider_name),
   INDEX idx_last_used (last_used_at),
   FOREIGN KEY (provider_id) REFERENCES providers(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Provider routes configuration
CREATE TABLE IF NOT EXISTS provider_routes (
   id INT AUTO_INCREMENT PRIMARY KEY,
   name VARCHAR(100) UNIQUE NOT NULL,
   description TEXT,
   inbound_provider VARCHAR(100) NOT NULL,
   intermediate_provider VARCHAR(100) NOT NULL,
   final_provider VARCHAR(100) NOT NULL,
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Call records with comprehensive tracking
CREATE TABLE IF NOT EXISTS call_records (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Call verifications for security
CREATE TABLE IF NOT EXISTS call_verifications (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Provider statistics for load balancing
CREATE TABLE IF NOT EXISTS provider_stats (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Real-time provider health
CREATE TABLE IF NOT EXISTS provider_health (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Audit log for compliance
CREATE TABLE IF NOT EXISTS audit_log (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ========================================
-- ASTERISK REALTIME ARCHITECTURE TABLES
-- ========================================

-- PJSIP transports
CREATE TABLE IF NOT EXISTS ps_transports (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- PJSIP endpoints
CREATE TABLE IF NOT EXISTS ps_endpoints (
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
   connected_line_method VARCHAR(40),
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
   rtp_timeout_hold INT DEFAULT 0,
   bind_rtp_to_media_address VARCHAR(3) DEFAULT 'no'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- PJSIP auth
CREATE TABLE IF NOT EXISTS ps_auths (
   id VARCHAR(40) PRIMARY KEY,
   auth_type VARCHAR(40) DEFAULT 'userpass',
   nonce_lifetime INT DEFAULT 32,
   md5_cred VARCHAR(40),
   password VARCHAR(80),
   realm VARCHAR(40),
   username VARCHAR(40)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- PJSIP AORs
CREATE TABLE IF NOT EXISTS ps_aors (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- PJSIP endpoint identifiers by IP
CREATE TABLE IF NOT EXISTS ps_endpoint_id_ips (
   id VARCHAR(40) PRIMARY KEY,
   endpoint VARCHAR(40),
   `match` VARCHAR(80),
   srv_lookups VARCHAR(3) DEFAULT 'yes',
   match_header VARCHAR(255)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- PJSIP globals
CREATE TABLE IF NOT EXISTS ps_globals (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Extensions table for dialplan
CREATE TABLE IF NOT EXISTS extensions (
   id INT AUTO_INCREMENT PRIMARY KEY,
   context VARCHAR(40) NOT NULL,
   exten VARCHAR(40) NOT NULL,
   priority INT NOT NULL,
   app VARCHAR(40) NOT NULL,
   appdata VARCHAR(256),
   UNIQUE KEY context_exten_priority (context, exten, priority),
   INDEX idx_context (context),
   INDEX idx_exten (exten)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- CDR table for call detail records
CREATE TABLE IF NOT EXISTS cdr (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ========================================
-- INITIAL DATA
-- ========================================

-- Create initial ps_globals entry
INSERT INTO ps_globals (id) VALUES ('global') ON DUPLICATE KEY UPDATE id=id;

-- Create initial transport
INSERT INTO ps_transports (id, bind, protocol) VALUES 
   ('transport-udp', '0.0.0.0:5060', 'udp'),
   ('transport-tcp', '0.0.0.0:5060', 'tcp'),
   ('transport-tls', '0.0.0.0:5061', 'tls')
ON DUPLICATE KEY UPDATE id=id;

-- ========================================
-- STORED PROCEDURES
-- ========================================

DELIMITER $$

-- Procedure to get available DID
CREATE PROCEDURE IF NOT EXISTS GetAvailableDID(
   IN p_provider_name VARCHAR(100),
   IN p_destination VARCHAR(100),
   OUT p_did VARCHAR(20)
)
BEGIN
   DECLARE v_did VARCHAR(20) DEFAULT NULL;
   
   START TRANSACTION;
   
   -- Try to get DID for specific provider first
   SELECT number INTO v_did
   FROM dids
   WHERE in_use = 0 
       AND (p_provider_name IS NULL OR provider_name = p_provider_name)
   ORDER BY last_used_at ASC, RAND()
   LIMIT 1
   FOR UPDATE;
   
   IF v_did IS NOT NULL THEN
       UPDATE dids 
       SET in_use = 1,
           destination = p_destination,
           allocated_at = NOW(),
           usage_count = usage_count + 1
       WHERE number = v_did;
   END IF;
   
   COMMIT;
   
   SET p_did = v_did;
END$$

-- Procedure to release DID
CREATE PROCEDURE IF NOT EXISTS ReleaseDID(
   IN p_did VARCHAR(20)
)
BEGIN
   UPDATE dids 
   SET in_use = 0,
       destination = NULL,
       released_at = NOW(),
       last_used_at = NOW()
   WHERE number = p_did;
END$$

-- Procedure to update provider stats
CREATE PROCEDURE IF NOT EXISTS UpdateProviderStats(
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
   
   -- Update hour stats
   INSERT INTO provider_stats (
       provider_name, stat_type, period_start,
       total_calls, completed_calls, failed_calls, total_duration
   ) VALUES (
       p_provider_name, 'hour', v_current_hour,
       1, IF(p_call_success, 1, 0), IF(p_call_success, 0, 1), p_duration
   )
   ON DUPLICATE KEY UPDATE
       total_calls = total_calls + 1,
       completed_calls = completed_calls + IF(p_call_success, 1, 0),
       failed_calls = failed_calls + IF(p_call_success, 0, 1),
       total_duration = total_duration + p_duration,
       asr = (completed_calls / total_calls) * 100,
       acd = IF(completed_calls > 0, total_duration / completed_calls, 0);
   
   -- Update day stats
   INSERT INTO provider_stats (
       provider_name, stat_type, period_start,
       total_calls, completed_calls, failed_calls, total_duration
   ) VALUES (
       p_provider_name, 'day', v_current_day,
       1, IF(p_call_success, 1, 0), IF(p_call_success, 0, 1), p_duration
   )
   ON DUPLICATE KEY UPDATE
       total_calls = total_calls + 1,
       completed_calls = completed_calls + IF(p_call_success, 1, 0),
       failed_calls = failed_calls + IF(p_call_success, 0, 1),
       total_duration = total_duration + p_duration,
       asr = (completed_calls / total_calls) * 100,
       acd = IF(completed_calls > 0, total_duration / completed_calls, 0);
END$$

DELIMITER ;

-- ========================================
-- VIEWS FOR REPORTING
-- ========================================

-- Active calls view
CREATE OR REPLACE VIEW v_active_calls AS
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
ORDER BY cr.start_time DESC;

-- Provider summary view
CREATE OR REPLACE VIEW v_provider_summary AS
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
   AND DATE(ps.period_start) = CURDATE();

-- DID utilization view
CREATE OR REPLACE VIEW v_did_utilization AS
SELECT 
   provider_name,
   COUNT(*) as total_dids,
   SUM(CASE WHEN in_use = 1 THEN 1 ELSE 0 END) as used_dids,
   SUM(CASE WHEN in_use = 0 THEN 1 ELSE 0 END) as available_dids,
   ROUND((SUM(CASE WHEN in_use = 1 THEN 1 ELSE 0 END) / COUNT(*)) * 100, 2) as utilization_percent
FROM dids
GROUP BY provider_name;

-- ========================================
-- INDEXES FOR PERFORMANCE
-- ========================================

-- Additional indexes for call_records
CREATE INDEX idx_call_records_composite ON call_records(status, start_time);
CREATE INDEX idx_call_records_route ON call_records(route_name, start_time);

-- Additional indexes for provider_stats
CREATE INDEX idx_provider_stats_composite ON provider_stats(provider_name, stat_type, period_start);

-- Additional indexes for audit_log
CREATE INDEX idx_audit_composite ON audit_log(entity_type, entity_id, created_at);
