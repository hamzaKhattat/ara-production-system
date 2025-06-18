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
-- Table structure for table `audit_log`
--

DROP TABLE IF EXISTS `audit_log`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `audit_log` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `event_type` varchar(50) NOT NULL,
  `entity_type` varchar(50) NOT NULL,
  `entity_id` varchar(100) DEFAULT NULL,
  `user_id` varchar(100) DEFAULT NULL,
  `ip_address` varchar(45) DEFAULT NULL,
  `action` varchar(50) NOT NULL,
  `old_value` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`old_value`)),
  `new_value` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`new_value`)),
  `metadata` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`metadata`)),
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_event_type` (`event_type`),
  KEY `idx_entity` (`entity_type`,`entity_id`),
  KEY `idx_created` (`created_at`),
  KEY `idx_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `audit_log`
--

LOCK TABLES `audit_log` WRITE;
/*!40000 ALTER TABLE `audit_log` DISABLE KEYS */;
/*!40000 ALTER TABLE `audit_log` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `call_records`
--

DROP TABLE IF EXISTS `call_records`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `call_records` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `call_id` varchar(100) NOT NULL,
  `original_ani` varchar(20) NOT NULL,
  `original_dnis` varchar(20) NOT NULL,
  `transformed_ani` varchar(20) DEFAULT NULL,
  `assigned_did` varchar(20) DEFAULT NULL,
  `inbound_provider` varchar(100) DEFAULT NULL,
  `intermediate_provider` varchar(100) DEFAULT NULL,
  `final_provider` varchar(100) DEFAULT NULL,
  `route_name` varchar(100) DEFAULT NULL,
  `status` enum('INITIATED','ACTIVE','RETURNED_FROM_S3','ROUTING_TO_S4','COMPLETED','FAILED','ABANDONED','TIMEOUT') DEFAULT 'INITIATED',
  `current_step` varchar(50) DEFAULT NULL,
  `failure_reason` varchar(255) DEFAULT NULL,
  `start_time` timestamp NULL DEFAULT current_timestamp(),
  `answer_time` timestamp NULL DEFAULT NULL,
  `end_time` timestamp NULL DEFAULT NULL,
  `duration` int(11) DEFAULT 0,
  `billable_duration` int(11) DEFAULT 0,
  `recording_path` varchar(255) DEFAULT NULL,
  `sip_response_code` int(11) DEFAULT NULL,
  `quality_score` decimal(3,2) DEFAULT NULL,
  `metadata` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`metadata`)),
  PRIMARY KEY (`id`),
  UNIQUE KEY `call_id` (`call_id`),
  KEY `idx_call_id` (`call_id`),
  KEY `idx_status` (`status`),
  KEY `idx_start_time` (`start_time`),
  KEY `idx_providers` (`inbound_provider`,`intermediate_provider`,`final_provider`),
  KEY `idx_did` (`assigned_did`)
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
-- Table structure for table `call_verifications`
--

DROP TABLE IF EXISTS `call_verifications`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `call_verifications` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `call_id` varchar(100) NOT NULL,
  `verification_step` varchar(50) NOT NULL,
  `expected_ani` varchar(20) DEFAULT NULL,
  `expected_dnis` varchar(20) DEFAULT NULL,
  `received_ani` varchar(20) DEFAULT NULL,
  `received_dnis` varchar(20) DEFAULT NULL,
  `source_ip` varchar(45) DEFAULT NULL,
  `expected_ip` varchar(45) DEFAULT NULL,
  `verified` tinyint(1) DEFAULT 0,
  `failure_reason` varchar(255) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_call_id` (`call_id`),
  KEY `idx_verified` (`verified`),
  KEY `idx_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `call_verifications`
--

LOCK TABLES `call_verifications` WRITE;
/*!40000 ALTER TABLE `call_verifications` DISABLE KEYS */;
/*!40000 ALTER TABLE `call_verifications` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `dids`
--

DROP TABLE IF EXISTS `dids`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `dids` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `number` varchar(20) NOT NULL,
  `provider_id` int(11) DEFAULT NULL,
  `provider_name` varchar(100) DEFAULT NULL,
  `in_use` tinyint(1) DEFAULT 0,
  `destination` varchar(100) DEFAULT NULL,
  `country` varchar(50) DEFAULT NULL,
  `city` varchar(100) DEFAULT NULL,
  `rate_center` varchar(100) DEFAULT NULL,
  `monthly_cost` decimal(10,2) DEFAULT 0.00,
  `per_minute_cost` decimal(10,4) DEFAULT 0.0000,
  `allocated_at` timestamp NULL DEFAULT NULL,
  `released_at` timestamp NULL DEFAULT NULL,
  `last_used_at` timestamp NULL DEFAULT NULL,
  `usage_count` bigint(20) DEFAULT 0,
  `metadata` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`metadata`)),
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `number` (`number`),
  KEY `idx_in_use` (`in_use`),
  KEY `idx_provider` (`provider_name`),
  KEY `idx_last_used` (`last_used_at`),
  KEY `provider_id` (`provider_id`),
  CONSTRAINT `dids_ibfk_1` FOREIGN KEY (`provider_id`) REFERENCES `providers` (`id`) ON DELETE SET NULL
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
-- Table structure for table `provider_health`
--

DROP TABLE IF EXISTS `provider_health`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `provider_health` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `provider_name` varchar(100) NOT NULL,
  `health_score` int(11) DEFAULT 100,
  `latency_ms` int(11) DEFAULT 0,
  `packet_loss` decimal(5,2) DEFAULT 0.00,
  `jitter_ms` int(11) DEFAULT 0,
  `active_calls` int(11) DEFAULT 0,
  `max_calls` int(11) DEFAULT 0,
  `last_success_at` timestamp NULL DEFAULT NULL,
  `last_failure_at` timestamp NULL DEFAULT NULL,
  `consecutive_failures` int(11) DEFAULT 0,
  `is_healthy` tinyint(1) DEFAULT 1,
  `updated_at` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `provider_name` (`provider_name`),
  KEY `idx_healthy` (`is_healthy`),
  KEY `idx_updated` (`updated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `provider_health`
--

LOCK TABLES `provider_health` WRITE;
/*!40000 ALTER TABLE `provider_health` DISABLE KEYS */;
/*!40000 ALTER TABLE `provider_health` ENABLE KEYS */;
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
  `load_balance_mode` enum('round_robin','weighted','priority','failover','least_connections','response_time','hash') DEFAULT 'round_robin',
  `priority` int(11) DEFAULT 0,
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
  KEY `idx_priority` (`priority` DESC)
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
-- Table structure for table `provider_stats`
--

DROP TABLE IF EXISTS `provider_stats`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `provider_stats` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `provider_name` varchar(100) NOT NULL,
  `stat_type` enum('minute','hour','day') NOT NULL,
  `period_start` timestamp NOT NULL,
  `total_calls` bigint(20) DEFAULT 0,
  `completed_calls` bigint(20) DEFAULT 0,
  `failed_calls` bigint(20) DEFAULT 0,
  `total_duration` bigint(20) DEFAULT 0,
  `avg_duration` decimal(10,2) DEFAULT 0.00,
  `asr` decimal(5,2) DEFAULT 0.00,
  `acd` decimal(10,2) DEFAULT 0.00,
  `avg_response_time` int(11) DEFAULT 0,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_provider_period` (`provider_name`,`stat_type`,`period_start`),
  KEY `idx_provider` (`provider_name`),
  KEY `idx_period` (`period_start`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `provider_stats`
--

LOCK TABLES `provider_stats` WRITE;
/*!40000 ALTER TABLE `provider_stats` DISABLE KEYS */;
/*!40000 ALTER TABLE `provider_stats` ENABLE KEYS */;
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
  `password` varchar(100) DEFAULT NULL,
  `auth_type` enum('ip','credentials','both') DEFAULT 'ip',
  `transport` varchar(10) DEFAULT 'udp',
  `codecs` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`codecs`)),
  `max_channels` int(11) DEFAULT 0,
  `current_channels` int(11) DEFAULT 0,
  `priority` int(11) DEFAULT 10,
  `weight` int(11) DEFAULT 1,
  `cost_per_minute` decimal(10,4) DEFAULT 0.0000,
  `active` tinyint(1) DEFAULT 1,
  `health_check_enabled` tinyint(1) DEFAULT 1,
  `last_health_check` timestamp NULL DEFAULT NULL,
  `health_status` varchar(50) DEFAULT 'unknown',
  `metadata` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`metadata`)),
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`),
  KEY `idx_type` (`type`),
  KEY `idx_active` (`active`),
  KEY `idx_priority` (`priority` DESC)
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
-- Table structure for table `ps_transports`
--

DROP TABLE IF EXISTS `ps_transports`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `ps_transports` (
  `id` varchar(40) NOT NULL,
  `async_operations` int(11) DEFAULT 1,
  `bind` varchar(40) DEFAULT NULL,
  `ca_list_file` varchar(200) DEFAULT NULL,
  `ca_list_path` varchar(200) DEFAULT NULL,
  `cert_file` varchar(200) DEFAULT NULL,
  `cipher` varchar(200) DEFAULT NULL,
  `cos` int(11) DEFAULT 0,
  `domain` varchar(40) DEFAULT NULL,
  `external_media_address` varchar(40) DEFAULT NULL,
  `external_signaling_address` varchar(40) DEFAULT NULL,
  `external_signaling_port` int(11) DEFAULT 0,
  `local_net` varchar(40) DEFAULT NULL,
  `method` varchar(40) DEFAULT NULL,
  `password` varchar(40) DEFAULT NULL,
  `priv_key_file` varchar(200) DEFAULT NULL,
  `protocol` varchar(40) DEFAULT NULL,
  `require_client_cert` varchar(40) DEFAULT NULL,
  `tos` int(11) DEFAULT 0,
  `verify_client` varchar(40) DEFAULT NULL,
  `verify_server` varchar(40) DEFAULT NULL,
  `allow_reload` varchar(3) DEFAULT 'yes',
  `symmetric_transport` varchar(3) DEFAULT 'no',
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
  `dirty` tinyint(1) NOT NULL,
  PRIMARY KEY (`version`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `schema_migrations`
--

LOCK TABLES `schema_migrations` WRITE;
/*!40000 ALTER TABLE `schema_migrations` DISABLE KEYS */;
INSERT INTO `schema_migrations` VALUES
(1,1);
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

-- Dump completed on 2025-06-05 17:22:31
