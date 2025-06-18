/*M!999999\- enable the sandbox mode */ 
-- MariaDB dump 10.19  Distrib 10.11.13-MariaDB, for debian-linux-gnu (x86_64)
--
-- Host: localhost    Database: asterisk_ara
-- ------------------------------------------------------
-- Server version	10.11.13-MariaDB-0ubuntu0.24.04.1

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `call_records`
--

DROP TABLE IF EXISTS `call_records`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `call_records` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `call_id` varchar(100) NOT NULL,
  `route_id` int(11) DEFAULT NULL,
  `route_name` varchar(100) DEFAULT NULL,
  `status` enum('INITIATED','ALLOCATING_DID','ROUTING','CONNECTED','COMPLETED','FAILED') NOT NULL,
  `direction` enum('inbound','outbound') DEFAULT 'inbound',
  `original_ani` varchar(50) DEFAULT NULL,
  `original_dnis` varchar(50) DEFAULT NULL,
  `transformed_ani` varchar(50) DEFAULT NULL,
  `assigned_did` varchar(50) DEFAULT NULL,
  `current_step` enum('ORIGIN','INTERMEDIATE','FINAL','RETURN') DEFAULT 'ORIGIN',
  `inbound_provider` varchar(100) DEFAULT NULL,
  `intermediate_provider` varchar(100) DEFAULT NULL,
  `final_provider` varchar(100) DEFAULT NULL,
  `start_time` timestamp NULL DEFAULT current_timestamp(),
  `answer_time` timestamp NULL DEFAULT NULL,
  `end_time` timestamp NULL DEFAULT NULL,
  `duration` int(11) DEFAULT 0,
  `billable_duration` int(11) DEFAULT 0,
  `hangup_cause` varchar(50) DEFAULT NULL,
  `hangup_cause_q850` int(11) DEFAULT NULL,
  `sip_response_code` int(11) DEFAULT NULL,
  `error_message` text DEFAULT NULL,
  `metadata` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`metadata`)),
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `call_id` (`call_id`),
  KEY `idx_call_id` (`call_id`),
  KEY `idx_status` (`status`),
  KEY `idx_start_time` (`start_time`),
  KEY `idx_assigned_did` (`assigned_did`),
  KEY `idx_route` (`route_id`),
  CONSTRAINT `call_records_ibfk_1` FOREIGN KEY (`route_id`) REFERENCES `provider_routes` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `call_records`
--

LOCK TABLES `call_records` WRITE;
/*!40000 ALTER TABLE `call_records` DISABLE KEYS */;
/*!40000 ALTER TABLE `call_records` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `dids`
--

DROP TABLE IF EXISTS `dids`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `dids` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `did` varchar(50) NOT NULL,
  `provider_id` int(11) NOT NULL,
  `provider_name` varchar(100) NOT NULL,
  `in_use` tinyint(1) DEFAULT 0,
  `allocated_to` varchar(255) DEFAULT NULL,
  `allocation_time` timestamp NULL DEFAULT NULL,
  `country` varchar(50) DEFAULT NULL,
  `region` varchar(100) DEFAULT NULL,
  `city` varchar(100) DEFAULT NULL,
  `monthly_cost` decimal(10,2) DEFAULT 0.00,
  `setup_cost` decimal(10,2) DEFAULT 0.00,
  `per_minute_cost` decimal(10,4) DEFAULT 0.0000,
  `active` tinyint(1) DEFAULT 1,
  `metadata` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`metadata`)),
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `did` (`did`),
  KEY `idx_provider` (`provider_id`),
  KEY `idx_in_use` (`in_use`),
  KEY `idx_country` (`country`),
  CONSTRAINT `dids_ibfk_1` FOREIGN KEY (`provider_id`) REFERENCES `providers` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `dids`
--

LOCK TABLES `dids` WRITE;
/*!40000 ALTER TABLE `dids` DISABLE KEYS */;
/*!40000 ALTER TABLE `dids` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `provider_routes`
--

DROP TABLE IF EXISTS `provider_routes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `provider_routes` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL,
  `description` text DEFAULT NULL,
  `inbound_provider` varchar(100) NOT NULL,
  `intermediate_provider` varchar(100) NOT NULL,
  `final_provider` varchar(100) NOT NULL,
  `inbound_is_group` tinyint(1) DEFAULT 0,
  `intermediate_is_group` tinyint(1) DEFAULT 0,
  `final_is_group` tinyint(1) DEFAULT 0,
  `load_balance_mode` enum('round_robin','least_used','weight','random','failover') DEFAULT 'round_robin',
  `priority` int(11) DEFAULT 10,
  `weight` int(11) DEFAULT 1,
  `max_concurrent_calls` int(11) DEFAULT 0,
  `current_calls` int(11) DEFAULT 0,
  `enabled` tinyint(1) DEFAULT 1,
  `failover_routes` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`failover_routes`)),
  `routing_rules` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`routing_rules`)),
  `metadata` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`metadata`)),
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`),
  KEY `idx_inbound` (`inbound_provider`),
  KEY `idx_enabled` (`enabled`),
  KEY `idx_priority` (`priority`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `provider_routes`
--

LOCK TABLES `provider_routes` WRITE;
/*!40000 ALTER TABLE `provider_routes` DISABLE KEYS */;
/*!40000 ALTER TABLE `provider_routes` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `providers`
--

DROP TABLE IF EXISTS `providers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `providers` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL,
  `type` enum('inbound','intermediate','final') NOT NULL,
  `host` varchar(255) NOT NULL,
  `port` int(11) DEFAULT 5060,
  `username` varchar(100) DEFAULT NULL,
  `password` varchar(255) DEFAULT NULL,
  `auth_type` enum('userpass','ip','md5') DEFAULT 'userpass',
  `transport` enum('udp','tcp','tls','ws','wss') DEFAULT 'udp',
  `codecs` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`codecs`)),
  `dtmf_mode` enum('rfc2833','info','inband','auto') DEFAULT 'rfc2833',
  `nat` tinyint(1) DEFAULT 0,
  `qualify` tinyint(1) DEFAULT 1,
  `context` varchar(100) DEFAULT NULL,
  `from_user` varchar(100) DEFAULT NULL,
  `from_domain` varchar(255) DEFAULT NULL,
  `insecure` varchar(50) DEFAULT NULL,
  `direct_media` tinyint(1) DEFAULT 0,
  `media_encryption` enum('no','sdes','dtls') DEFAULT 'no',
  `trust_rpid` tinyint(1) DEFAULT 0,
  `send_rpid` tinyint(1) DEFAULT 0,
  `rewrite_contact` tinyint(1) DEFAULT 1,
  `force_rport` tinyint(1) DEFAULT 1,
  `rtp_symmetric` tinyint(1) DEFAULT 1,
  `max_channels` int(11) DEFAULT 0,
  `current_channels` int(11) DEFAULT 0,
  `priority` int(11) DEFAULT 10,
  `weight` int(11) DEFAULT 1,
  `cost_per_minute` decimal(10,4) DEFAULT 0.0000,
  `active` tinyint(1) DEFAULT 1,
  `health_check_enabled` tinyint(1) DEFAULT 1,
  `health_check_interval` int(11) DEFAULT 60,
  `last_health_check` timestamp NULL DEFAULT NULL,
  `health_status` enum('healthy','degraded','unhealthy','unknown') DEFAULT 'unknown',
  `country` varchar(50) DEFAULT NULL,
  `region` varchar(100) DEFAULT NULL,
  `city` varchar(100) DEFAULT NULL,
  `metadata` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`metadata`)),
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`),
  KEY `idx_type` (`type`),
  KEY `idx_active` (`active`),
  KEY `idx_health_status` (`health_status`),
  KEY `idx_country` (`country`),
  KEY `idx_region` (`region`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `providers`
--

LOCK TABLES `providers` WRITE;
/*!40000 ALTER TABLE `providers` DISABLE KEYS */;
/*!40000 ALTER TABLE `providers` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `ps_aors`
--

DROP TABLE IF EXISTS `ps_aors`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `ps_aors` (
  `id` varchar(40) NOT NULL,
  `contact` varchar(255) DEFAULT NULL,
  `default_expiration` int(11) DEFAULT NULL,
  `mailboxes` varchar(80) DEFAULT NULL,
  `max_contacts` int(11) DEFAULT NULL,
  `minimum_expiration` int(11) DEFAULT NULL,
  `remove_existing` enum('yes','no') DEFAULT NULL,
  `qualify_frequency` int(11) DEFAULT NULL,
  `authenticate_qualify` enum('yes','no') DEFAULT NULL,
  `maximum_expiration` int(11) DEFAULT NULL,
  `outbound_proxy` varchar(256) DEFAULT NULL,
  `support_path` enum('yes','no') DEFAULT NULL,
  `qualify_timeout` decimal(3,1) DEFAULT NULL,
  `voicemail_extension` varchar(40) DEFAULT NULL,
  `remove_unavailable` enum('yes','no') DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `ps_aors`
--

LOCK TABLES `ps_aors` WRITE;
/*!40000 ALTER TABLE `ps_aors` DISABLE KEYS */;
/*!40000 ALTER TABLE `ps_aors` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `ps_auths`
--

DROP TABLE IF EXISTS `ps_auths`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `ps_auths` (
  `id` varchar(40) NOT NULL,
  `auth_type` enum('userpass','md5') DEFAULT NULL,
  `nonce_lifetime` int(11) DEFAULT NULL,
  `md5_cred` varchar(40) DEFAULT NULL,
  `password` varchar(80) DEFAULT NULL,
  `realm` varchar(40) DEFAULT NULL,
  `username` varchar(40) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `ps_auths`
--

LOCK TABLES `ps_auths` WRITE;
/*!40000 ALTER TABLE `ps_auths` DISABLE KEYS */;
/*!40000 ALTER TABLE `ps_auths` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `ps_endpoints`
--

DROP TABLE IF EXISTS `ps_endpoints`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `ps_endpoints` (
  `id` varchar(40) NOT NULL,
  `transport` varchar(40) DEFAULT NULL,
  `aors` varchar(200) DEFAULT NULL,
  `auth` varchar(40) DEFAULT NULL,
  `context` varchar(40) DEFAULT NULL,
  `disallow` varchar(200) DEFAULT NULL,
  `allow` varchar(200) DEFAULT NULL,
  `direct_media` enum('yes','no') DEFAULT NULL,
  `connected_line_method` enum('invite','reinvite','update') DEFAULT NULL,
  `direct_media_method` enum('invite','reinvite','update') DEFAULT NULL,
  `direct_media_glare_mitigation` enum('none','outgoing','incoming') DEFAULT NULL,
  `disable_direct_media_on_nat` enum('yes','no') DEFAULT NULL,
  `dtmf_mode` enum('rfc4733','inband','info','auto','auto_info') DEFAULT NULL,
  `external_media_address` varchar(40) DEFAULT NULL,
  `force_rport` enum('yes','no') DEFAULT NULL,
  `ice_support` enum('yes','no') DEFAULT NULL,
  `identify_by` varchar(80) DEFAULT NULL,
  `mailboxes` varchar(40) DEFAULT NULL,
  `media_address` varchar(40) DEFAULT NULL,
  `media_encryption` enum('no','sdes','dtls') DEFAULT NULL,
  `media_encryption_optimistic` enum('yes','no') DEFAULT NULL,
  `media_use_received_transport` enum('yes','no') DEFAULT NULL,
  `moh_suggest` varchar(40) DEFAULT NULL,
  `mwi_from_user` varchar(40) DEFAULT NULL,
  `mwi_subscribe_replaces_unsolicited` enum('yes','no') DEFAULT NULL,
  `named_call_group` varchar(40) DEFAULT NULL,
  `named_pickup_group` varchar(40) DEFAULT NULL,
  `notify_early_inuse_ringing` enum('yes','no') DEFAULT NULL,
  `outbound_auth` varchar(40) DEFAULT NULL,
  `outbound_proxy` varchar(256) DEFAULT NULL,
  `rewrite_contact` enum('yes','no') DEFAULT NULL,
  `rpid_immediate` enum('yes','no') DEFAULT NULL,
  `rtcp_mux` enum('yes','no') DEFAULT NULL,
  `rtp_engine` varchar(40) DEFAULT NULL,
  `rtp_ipv6` enum('yes','no') DEFAULT NULL,
  `rtp_symmetric` enum('yes','no') DEFAULT NULL,
  `send_diversion` enum('yes','no') DEFAULT NULL,
  `send_pai` enum('yes','no') DEFAULT NULL,
  `send_rpid` enum('yes','no') DEFAULT NULL,
  `set_var` text DEFAULT NULL,
  `timers_min_se` int(11) DEFAULT NULL,
  `timers` enum('forced','no','required','yes') DEFAULT NULL,
  `timers_sess_expires` int(11) DEFAULT NULL,
  `tone_zone` varchar(40) DEFAULT NULL,
  `tos_audio` varchar(10) DEFAULT NULL,
  `tos_video` varchar(10) DEFAULT NULL,
  `trust_id_inbound` enum('yes','no') DEFAULT NULL,
  `trust_id_outbound` enum('yes','no') DEFAULT NULL,
  `use_avpf` enum('yes','no') DEFAULT NULL,
  `use_ptime` enum('yes','no') DEFAULT NULL,
  `webrtc` enum('yes','no') DEFAULT NULL,
  `dtls_verify` varchar(40) DEFAULT NULL,
  `dtls_rekey` int(11) DEFAULT NULL,
  `dtls_auto_generate_cert` enum('yes','no') DEFAULT NULL,
  `dtls_cert_file` varchar(200) DEFAULT NULL,
  `dtls_private_key` varchar(200) DEFAULT NULL,
  `dtls_cipher` varchar(200) DEFAULT NULL,
  `dtls_ca_file` varchar(200) DEFAULT NULL,
  `dtls_ca_path` varchar(200) DEFAULT NULL,
  `dtls_setup` enum('active','passive','actpass') DEFAULT NULL,
  `dtls_fingerprint` enum('SHA-1','SHA-256') DEFAULT NULL,
  `100rel` enum('no','required','yes') DEFAULT NULL,
  `aggregate_mwi` enum('yes','no') DEFAULT NULL,
  `bind_rtp_to_media_address` enum('yes','no') DEFAULT NULL,
  `bundle` enum('yes','no') DEFAULT NULL,
  `call_group` varchar(40) DEFAULT NULL,
  `callerid` varchar(40) DEFAULT NULL,
  `callerid_privacy` enum('allowed_not_screened','allowed_passed_screened','allowed_failed_screened','allowed','prohib_not_screened','prohib_passed_screened','prohib_failed_screened','prohib','unavailable') DEFAULT NULL,
  `callerid_tag` varchar(40) DEFAULT NULL,
  `contact_acl` varchar(40) DEFAULT NULL,
  `device_state_busy_at` int(11) DEFAULT NULL,
  `fax_detect` enum('yes','no') DEFAULT NULL,
  `fax_detect_timeout` int(11) DEFAULT NULL,
  `follow_early_media_fork` enum('yes','no') DEFAULT NULL,
  `from_domain` varchar(40) DEFAULT NULL,
  `from_user` varchar(40) DEFAULT NULL,
  `g726_non_standard` enum('yes','no') DEFAULT NULL,
  `inband_progress` enum('yes','no') DEFAULT NULL,
  `incoming_mwi_mailbox` varchar(40) DEFAULT NULL,
  `language` varchar(40) DEFAULT NULL,
  `max_audio_streams` int(11) DEFAULT NULL,
  `max_video_streams` int(11) DEFAULT NULL,
  `message_context` varchar(40) DEFAULT NULL,
  `moh_passthrough` enum('yes','no') DEFAULT NULL,
  `one_touch_recording` enum('yes','no') DEFAULT NULL,
  `pickup_group` varchar(40) DEFAULT NULL,
  `preferred_codec_only` enum('yes','no') DEFAULT NULL,
  `record_off_feature` varchar(40) DEFAULT NULL,
  `record_on_feature` varchar(40) DEFAULT NULL,
  `refer_blind_progress` enum('yes','no') DEFAULT NULL,
  `rtp_keepalive` int(11) DEFAULT NULL,
  `rtp_timeout` int(11) DEFAULT NULL,
  `rtp_timeout_hold` int(11) DEFAULT NULL,
  `sdp_owner` varchar(40) DEFAULT NULL,
  `sdp_session` varchar(40) DEFAULT NULL,
  `send_connected_line` enum('yes','no') DEFAULT NULL,
  `send_history_info` enum('yes','no') DEFAULT NULL,
  `srtp_tag_32` enum('yes','no') DEFAULT NULL,
  `stream_topology` varchar(40) DEFAULT NULL,
  `sub_min_expiry` int(11) DEFAULT NULL,
  `subscribe_context` varchar(40) DEFAULT NULL,
  `suppress_q850_reason_headers` enum('yes','no') DEFAULT NULL,
  `t38_udptl` enum('yes','no') DEFAULT NULL,
  `t38_udptl_ec` enum('none','fec','redundancy') DEFAULT NULL,
  `t38_udptl_ipv6` enum('yes','no') DEFAULT NULL,
  `t38_udptl_maxdatagram` int(11) DEFAULT NULL,
  `t38_udptl_nat` enum('yes','no') DEFAULT NULL,
  `user_eq_phone` enum('yes','no') DEFAULT NULL,
  `voicemail_extension` varchar(40) DEFAULT NULL,
  `asymmetric_rtp_codec` enum('yes','no') DEFAULT NULL,
  `incoming_call_offer_pref` enum('local','local_first','remote','remote_first') DEFAULT NULL,
  `moh_suggest_default` enum('yes','no') DEFAULT NULL,
  `outgoing_call_offer_pref` enum('local','local_merge','local_first','remote','remote_merge','remote_first') DEFAULT NULL,
  `redirect_method` enum('user','uri_core','uri_pjsip') DEFAULT NULL,
  `stir_shaken` enum('yes','no') DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `ps_endpoints`
--

LOCK TABLES `ps_endpoints` WRITE;
/*!40000 ALTER TABLE `ps_endpoints` DISABLE KEYS */;
/*!40000 ALTER TABLE `ps_endpoints` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `ps_transports`
--

DROP TABLE IF EXISTS `ps_transports`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `ps_transports` (
  `id` varchar(40) NOT NULL,
  `async_operations` int(11) DEFAULT NULL,
  `bind` varchar(40) DEFAULT NULL,
  `ca_list_file` varchar(200) DEFAULT NULL,
  `ca_list_path` varchar(200) DEFAULT NULL,
  `cert_file` varchar(200) DEFAULT NULL,
  `cipher` varchar(200) DEFAULT NULL,
  `cos` int(11) DEFAULT NULL,
  `domain` varchar(40) DEFAULT NULL,
  `external_media_address` varchar(40) DEFAULT NULL,
  `external_signaling_address` varchar(40) DEFAULT NULL,
  `external_signaling_port` int(11) DEFAULT NULL,
  `local_net` varchar(40) DEFAULT NULL,
  `method` enum('default','unspecified','tlsv1','sslv2','sslv3','sslv23') DEFAULT NULL,
  `password` varchar(40) DEFAULT NULL,
  `priv_key_file` varchar(200) DEFAULT NULL,
  `protocol` enum('udp','tcp','tls','ws','wss') DEFAULT NULL,
  `require_client_cert` enum('yes','no') DEFAULT NULL,
  `symmetric_transport` enum('yes','no') DEFAULT NULL,
  `tos` int(11) DEFAULT NULL,
  `verify_client` enum('yes','no') DEFAULT NULL,
  `verify_server` enum('yes','no') DEFAULT NULL,
  `websocket_write_timeout` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `ps_transports`
--

LOCK TABLES `ps_transports` WRITE;
/*!40000 ALTER TABLE `ps_transports` DISABLE KEYS */;
/*!40000 ALTER TABLE `ps_transports` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `schema_migrations`
--

DROP TABLE IF EXISTS `schema_migrations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `schema_migrations` (
  `version` bigint(20) NOT NULL,
  `dirty` tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`version`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `schema_migrations`
--

LOCK TABLES `schema_migrations` WRITE;
/*!40000 ALTER TABLE `schema_migrations` DISABLE KEYS */;
/*!40000 ALTER TABLE `schema_migrations` ENABLE KEYS */;
UNLOCK TABLES;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2025-06-05 18:56:04
