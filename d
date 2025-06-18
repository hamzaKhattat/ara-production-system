-- Provider groups table
CREATE TABLE IF NOT EXISTS provider_groups (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    group_type ENUM('manual', 'regex', 'metadata', 'dynamic') DEFAULT 'manual',
    match_pattern VARCHAR(255),
    match_field VARCHAR(100), -- e.g., 'name', 'country', 'city', 'metadata.region'
    match_operator ENUM('equals', 'contains', 'starts_with', 'ends_with', 'regex', 'in', 'not_in') DEFAULT 'equals',
    match_value JSON, -- Can store single value or array of values
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

-- Provider group members (for manual groups and cached dynamic groups)
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

-- Update provider_routes to support groups
ALTER TABLE provider_routes 
    ADD COLUMN inbound_is_group BOOLEAN DEFAULT FALSE AFTER inbound_provider,
    ADD COLUMN intermediate_is_group BOOLEAN DEFAULT FALSE AFTER intermediate_provider,
    ADD COLUMN final_is_group BOOLEAN DEFAULT FALSE AFTER final_provider;

-- Group statistics
CREATE TABLE IF NOT EXISTS provider_group_stats (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    group_name VARCHAR(100) NOT NULL,
    stat_type ENUM('minute', 'hour', 'day') NOT NULL,
    period_start TIMESTAMP NOT NULL,
    total_calls BIGINT DEFAULT 0,
    completed_calls BIGINT DEFAULT 0,
    failed_calls BIGINT DEFAULT 0,
    total_duration BIGINT DEFAULT 0,
    avg_duration DECIMAL(10,2) DEFAULT 0,
    asr DECIMAL(5,2) DEFAULT 0,
    acd DECIMAL(10,2) DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY unique_group_period (group_name, stat_type, period_start),
    INDEX idx_group (group_name),
    INDEX idx_period (period_start)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Add country and region to providers if not exists
ALTER TABLE providers 
    ADD COLUMN country VARCHAR(50) AFTER host,
    ADD COLUMN region VARCHAR(100) AFTER country,
    ADD COLUMN city VARCHAR(100) AFTER region,
    ADD INDEX idx_country (country),
    ADD INDEX idx_region (region);
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
  KEY `idx_user` (`user_id`),
  KEY `idx_audit_composite` (`entity_type`,`entity_id`,`created_at`)
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
  KEY `idx_did` (`assigned_did`),
  KEY `idx_call_records_composite` (`status`,`start_time`),
  KEY `idx_call_records_route` (`route_name`,`start_time`)
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
-- Table structure for table `cdr`
--

DROP TABLE IF EXISTS `cdr`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `cdr` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `accountcode` varchar(20) DEFAULT NULL,
  `src` varchar(80) DEFAULT NULL,
  `dst` varchar(80) DEFAULT NULL,
  `dcontext` varchar(80) DEFAULT NULL,
  `clid` varchar(80) DEFAULT NULL,
  `channel` varchar(80) DEFAULT NULL,
  `dstchannel` varchar(80) DEFAULT NULL,
  `lastapp` varchar(80) DEFAULT NULL,
  `lastdata` varchar(80) DEFAULT NULL,
  `start` datetime DEFAULT NULL,
  `answer` datetime DEFAULT NULL,
  `end` datetime DEFAULT NULL,
  `duration` int(11) DEFAULT NULL,
  `billsec` int(11) DEFAULT NULL,
  `disposition` varchar(45) DEFAULT NULL,
  `amaflags` int(11) DEFAULT NULL,
  `uniqueid` varchar(32) DEFAULT NULL,
  `userfield` varchar(255) DEFAULT NULL,
  `peeraccount` varchar(20) DEFAULT NULL,
  `linkedid` varchar(32) DEFAULT NULL,
  `sequence` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_start` (`start`),
  KEY `idx_src` (`src`),
  KEY `idx_dst` (`dst`),
  KEY `idx_uniqueid` (`uniqueid`),
  KEY `idx_accountcode` (`accountcode`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `cdr`
--

LOCK TABLES `cdr` WRITE;
/*!40000 ALTER TABLE `cdr` DISABLE KEYS */;
/*!40000 ALTER TABLE `cdr` ENABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `dids`
--

LOCK TABLES `dids` WRITE;
/*!40000 ALTER TABLE `dids` DISABLE KEYS */;
INSERT INTO `dids` VALUES
(1,'584148757547',NULL,'s3',0,NULL,NULL,NULL,NULL,0.00,0.0000,NULL,NULL,NULL,0,NULL,'2025-06-05 15:29:37','2025-06-05 15:29:37'),
(2,'584148757548',NULL,'s3',0,NULL,NULL,NULL,NULL,0.00,0.0000,NULL,NULL,NULL,0,NULL,'2025-06-05 15:29:37','2025-06-05 15:29:37'),
(3,'584148757549',NULL,'s3',0,NULL,NULL,NULL,NULL,0.00,0.0000,NULL,NULL,NULL,0,NULL,'2025-06-05 15:29:37','2025-06-05 15:29:37'),
(4,'584249726299',NULL,'s3',0,NULL,NULL,NULL,NULL,0.00,0.0000,NULL,NULL,NULL,0,NULL,'2025-06-05 15:29:37','2025-06-05 15:29:37'),
(5,'584249726300',NULL,'s3',0,NULL,NULL,NULL,NULL,0.00,0.0000,NULL,NULL,NULL,0,NULL,'2025-06-05 15:29:37','2025-06-05 15:29:37'),
(6,'584249726301',NULL,'s3',0,NULL,NULL,NULL,NULL,0.00,0.0000,NULL,NULL,NULL,0,NULL,'2025-06-05 15:29:37','2025-06-05 15:29:37');
/*!40000 ALTER TABLE `dids` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `extensions`
--

DROP TABLE IF EXISTS `extensions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `extensions` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `context` varchar(40) NOT NULL,
  `exten` varchar(40) NOT NULL,
  `priority` int(11) NOT NULL,
  `app` varchar(40) NOT NULL,
  `appdata` varchar(256) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `context_exten_priority` (`context`,`exten`,`priority`),
  KEY `idx_context` (`context`),
  KEY `idx_exten` (`exten`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `extensions`
--

LOCK TABLES `extensions` WRITE;
/*!40000 ALTER TABLE `extensions` DISABLE KEYS */;
/*!40000 ALTER TABLE `extensions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `provider_group_members`
--

DROP TABLE IF EXISTS `provider_group_members`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `provider_group_members` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `group_id` int(11) NOT NULL,
  `provider_id` int(11) NOT NULL,
  `provider_name` varchar(100) NOT NULL,
  `added_manually` tinyint(1) DEFAULT 0,
  `matched_by_rule` tinyint(1) DEFAULT 0,
  `priority_override` int(11) DEFAULT NULL,
  `weight_override` int(11) DEFAULT NULL,
  `metadata` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`metadata`)),
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_group_provider` (`group_id`,`provider_id`),
  KEY `idx_group` (`group_id`),
  KEY `idx_provider` (`provider_name`),
  KEY `provider_id` (`provider_id`),
  CONSTRAINT `provider_group_members_ibfk_1` FOREIGN KEY (`group_id`) REFERENCES `provider_groups` (`id`) ON DELETE CASCADE,
  CONSTRAINT `provider_group_members_ibfk_2` FOREIGN KEY (`provider_id`) REFERENCES `providers` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `provider_group_members`
--

LOCK TABLES `provider_group_members` WRITE;
/*!40000 ALTER TABLE `provider_group_members` DISABLE KEYS */;
/*!40000 ALTER TABLE `provider_group_members` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `provider_group_stats`
--

DROP TABLE IF EXISTS `provider_group_stats`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `provider_group_stats` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `group_name` varchar(100) NOT NULL,
  `stat_type` enum('minute','hour','day') NOT NULL,
  `period_start` timestamp NOT NULL,
  `total_calls` bigint(20) DEFAULT 0,
  `completed_calls` bigint(20) DEFAULT 0,
  `failed_calls` bigint(20) DEFAULT 0,
  `total_duration` bigint(20) DEFAULT 0,
  `avg_duration` decimal(10,2) DEFAULT 0.00,
  `asr` decimal(5,2) DEFAULT 0.00,
  `acd` decimal(10,2) DEFAULT 0.00,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_group_period` (`group_name`,`stat_type`,`period_start`),
  KEY `idx_group` (`group_name`),
  KEY `idx_period` (`period_start`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `provider_group_stats`
--

LOCK TABLES `provider_group_stats` WRITE;
/*!40000 ALTER TABLE `provider_group_stats` DISABLE KEYS */;
/*!40000 ALTER TABLE `provider_group_stats` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `provider_groups`
--

DROP TABLE IF EXISTS `provider_groups`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `provider_groups` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL,
  `description` text DEFAULT NULL,
  `group_type` enum('manual','regex','metadata','dynamic') DEFAULT 'manual',
  `match_pattern` varchar(255) DEFAULT NULL,
  `match_field` varchar(100) DEFAULT NULL,
  `match_operator` enum('equals','contains','starts_with','ends_with','regex','in','not_in') DEFAULT 'equals',
  `match_value` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`match_value`)),
  `provider_type` enum('inbound','intermediate','final','any') DEFAULT 'any',
  `enabled` tinyint(1) DEFAULT 1,
  `priority` int(11) DEFAULT 10,
  `metadata` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`metadata`)),
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`),
  KEY `idx_enabled` (`enabled`),
  KEY `idx_type` (`group_type`),
  KEY `idx_provider_type` (`provider_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `provider_groups`
--

LOCK TABLES `provider_groups` WRITE;
/*!40000 ALTER TABLE `provider_groups` DISABLE KEYS */;
/*!40000 ALTER TABLE `provider_groups` ENABLE KEYS */;
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
  `inbound_is_group` tinyint(1) DEFAULT 0,
  `intermediate_provider` varchar(100) NOT NULL,
  `intermediate_is_group` tinyint(1) DEFAULT 0,
  `final_provider` varchar(100) NOT NULL,
  `final_is_group` tinyint(1) DEFAULT 0,
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
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `provider_routes`
--

LOCK TABLES `provider_routes` WRITE;
/*!40000 ALTER TABLE `provider_routes` DISABLE KEYS */;
INSERT INTO `provider_routes` VALUES
(2,'main-route','','s1',0,'s3',0,'s4',0,'round_robin',10,1,100,0,1,NULL,NULL,NULL,'2025-06-05 15:37:30','2025-06-05 15:37:30');
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
  KEY `idx_period` (`period_start`),
  KEY `idx_provider_stats_composite` (`provider_name`,`stat_type`,`period_start`)
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
  `country` varchar(50) DEFAULT NULL,
  `region` varchar(100) DEFAULT NULL,
  `city` varchar(100) DEFAULT NULL,
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
  KEY `idx_priority` (`priority` DESC),
  KEY `idx_country` (`country`),
  KEY `idx_region` (`region`)
) ENGINE=InnoDB AUTO_INCREMENT=9 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `providers`
--

LOCK TABLES `providers` WRITE;
/*!40000 ALTER TABLE `providers` DISABLE KEYS */;
INSERT INTO `providers` VALUES
(6,'s3','intermediate','10.0.0.3',NULL,NULL,NULL,5060,'','','ip','udp','[\"ulaw\",\"alaw\"]',0,0,10,1,0.0000,1,1,NULL,'unknown','null','2025-06-05 15:29:37','2025-06-05 15:29:37'),
(7,'s4','final','10.0.0.4',NULL,NULL,NULL,5060,'','','ip','udp','[\"ulaw\",\"alaw\"]',0,0,10,1,0.0000,1,1,NULL,'unknown','null','2025-06-05 15:29:37','2025-06-05 15:29:37'),
(8,'s1','inbound','10.0.0.1',NULL,NULL,NULL,5060,'','','ip','udp','[\"ulaw\",\"alaw\"]',0,0,10,1,0.0000,1,1,NULL,'unknown','null','2025-06-05 15:37:23','2025-06-05 15:37:23');
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
  `default_expiration` int(11) DEFAULT 3600,
  `mailboxes` varchar(80) DEFAULT NULL,
  `max_contacts` int(11) DEFAULT 1,
  `minimum_expiration` int(11) DEFAULT 60,
  `remove_existing` varchar(3) DEFAULT 'yes',
  `qualify_frequency` int(11) DEFAULT 0,
  `authenticate_qualify` varchar(3) DEFAULT 'no',
  `maximum_expiration` int(11) DEFAULT 7200,
  `outbound_proxy` varchar(40) DEFAULT NULL,
  `support_path` varchar(3) DEFAULT 'no',
  `qualify_timeout` decimal(5,3) DEFAULT 3.000,
  `voicemail_extension` varchar(40) DEFAULT NULL,
  `remove_unavailable` varchar(3) DEFAULT 'no',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `ps_aors`
--

LOCK TABLES `ps_aors` WRITE;
/*!40000 ALTER TABLE `ps_aors` DISABLE KEYS */;
INSERT INTO `ps_aors` VALUES
('aor-s1',NULL,3600,NULL,1,60,'yes',30,'no',7200,NULL,'no',3.000,NULL,'no'),
('aor-s3',NULL,3600,NULL,1,60,'yes',30,'no',7200,NULL,'no',3.000,NULL,'no'),
('aor-s4',NULL,3600,NULL,1,60,'yes',30,'no',7200,NULL,'no',3.000,NULL,'no');
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
  `auth_type` varchar(40) DEFAULT 'userpass',
  `nonce_lifetime` int(11) DEFAULT 32,
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
-- Table structure for table `ps_endpoint_id_ips`
--

DROP TABLE IF EXISTS `ps_endpoint_id_ips`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `ps_endpoint_id_ips` (
  `id` varchar(40) NOT NULL,
  `endpoint` varchar(40) DEFAULT NULL,
  `match` varchar(80) DEFAULT NULL,
  `srv_lookups` varchar(3) DEFAULT 'yes',
  `match_header` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `ps_endpoint_id_ips`
--

LOCK TABLES `ps_endpoint_id_ips` WRITE;
/*!40000 ALTER TABLE `ps_endpoint_id_ips` DISABLE KEYS */;
INSERT INTO `ps_endpoint_id_ips` VALUES
('ip-s1','endpoint-s1','10.0.0.1/32','yes',NULL),
('ip-s3','endpoint-s3','10.0.0.3/32','yes',NULL),
('ip-s4','endpoint-s4','10.0.0.4/32','yes',NULL);
/*!40000 ALTER TABLE `ps_endpoint_id_ips` ENABLE KEYS */;
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
  `auth` varchar(100) DEFAULT NULL,
  `context` varchar(40) DEFAULT 'default',
  `disallow` varchar(200) DEFAULT 'all',
  `allow` varchar(200) DEFAULT NULL,
  `direct_media` varchar(3) DEFAULT 'yes',
  `connected_line_method` varchar(40) DEFAULT 'invite',
  `direct_media_method` varchar(40) DEFAULT 'invite',
  `direct_media_glare_mitigation` varchar(40) DEFAULT 'none',
  `disable_direct_media_on_nat` varchar(3) DEFAULT 'no',
  `dtmf_mode` varchar(40) DEFAULT 'rfc4733',
  `external_media_address` varchar(40) DEFAULT NULL,
  `force_rport` varchar(3) DEFAULT 'yes',
  `ice_support` varchar(3) DEFAULT 'no',
  `identify_by` varchar(40) DEFAULT 'username,ip',
  `mailboxes` varchar(40) DEFAULT NULL,
  `moh_suggest` varchar(40) DEFAULT 'default',
  `outbound_auth` varchar(40) DEFAULT NULL,
  `outbound_proxy` varchar(40) DEFAULT NULL,
  `rewrite_contact` varchar(3) DEFAULT 'no',
  `rtp_ipv6` varchar(3) DEFAULT 'no',
  `rtp_symmetric` varchar(3) DEFAULT 'no',
  `send_diversion` varchar(3) DEFAULT 'yes',
  `send_pai` varchar(3) DEFAULT 'no',
  `send_rpid` varchar(3) DEFAULT 'no',
  `timers_min_se` int(11) DEFAULT 90,
  `timers` varchar(3) DEFAULT 'yes',
  `timers_sess_expires` int(11) DEFAULT 1800,
  `callerid` varchar(40) DEFAULT NULL,
  `callerid_privacy` varchar(40) DEFAULT NULL,
  `callerid_tag` varchar(40) DEFAULT NULL,
  `trust_id_inbound` varchar(3) DEFAULT 'no',
  `trust_id_outbound` varchar(3) DEFAULT 'no',
  `send_connected_line` varchar(3) DEFAULT 'yes',
  `accountcode` varchar(20) DEFAULT NULL,
  `language` varchar(10) DEFAULT 'en',
  `rtp_engine` varchar(40) DEFAULT 'asterisk',
  `dtls_verify` varchar(40) DEFAULT NULL,
  `dtls_rekey` varchar(40) DEFAULT NULL,
  `dtls_cert_file` varchar(200) DEFAULT NULL,
  `dtls_private_key` varchar(200) DEFAULT NULL,
  `dtls_cipher` varchar(200) DEFAULT NULL,
  `dtls_ca_file` varchar(200) DEFAULT NULL,
  `dtls_ca_path` varchar(200) DEFAULT NULL,
  `dtls_setup` varchar(40) DEFAULT NULL,
  `srtp_tag_32` varchar(3) DEFAULT 'no',
  `media_encryption` varchar(40) DEFAULT 'no',
  `use_avpf` varchar(3) DEFAULT 'no',
  `force_avp` varchar(3) DEFAULT 'no',
  `media_use_received_transport` varchar(3) DEFAULT 'no',
  `rtp_timeout` int(11) DEFAULT 0,
  `rtp_timeout_hold` int(11) DEFAULT 0,
  `rtp_keepalive` int(11) DEFAULT 0,
  `record_on_feature` varchar(40) DEFAULT NULL,
  `record_off_feature` varchar(40) DEFAULT NULL,
  `allow_transfer` varchar(3) DEFAULT 'yes',
  `user_eq_phone` varchar(3) DEFAULT 'no',
  `moh_passthrough` varchar(3) DEFAULT 'no',
  `media_encryption_optimistic` varchar(3) DEFAULT 'no',
  `rpid_immediate` varchar(3) DEFAULT 'no',
  `g726_non_standard` varchar(3) DEFAULT 'no',
  `inband_progress` varchar(3) DEFAULT 'no',
  `call_group` varchar(40) DEFAULT NULL,
  `pickup_group` varchar(40) DEFAULT NULL,
  `named_call_group` varchar(40) DEFAULT NULL,
  `named_pickup_group` varchar(40) DEFAULT NULL,
  `device_state_busy_at` int(11) DEFAULT 0,
  `t38_udptl` varchar(3) DEFAULT 'no',
  `t38_udptl_ec` varchar(40) DEFAULT NULL,
  `t38_udptl_maxdatagram` int(11) DEFAULT 0,
  `fax_detect` varchar(3) DEFAULT 'no',
  `fax_detect_timeout` int(11) DEFAULT 0,
  `t38_udptl_nat` varchar(3) DEFAULT 'no',
  `t38_udptl_ipv6` varchar(3) DEFAULT 'no',
  `rtcp_mux` varchar(3) DEFAULT 'no',
  `allow_overlap` varchar(3) DEFAULT 'yes',
  `bundle` varchar(3) DEFAULT 'no',
  `webrtc` varchar(3) DEFAULT 'no',
  `dtls_fingerprint` varchar(40) DEFAULT NULL,
  `incoming_mwi_mailbox` varchar(40) DEFAULT NULL,
  `follow_early_media_fork` varchar(3) DEFAULT 'yes',
  `accept_multiple_sdp_answers` varchar(3) DEFAULT 'no',
  `suppress_q850_reason_headers` varchar(3) DEFAULT 'no',
  `trust_connected_line` varchar(3) DEFAULT 'yes',
  `send_history_info` varchar(3) DEFAULT 'no',
  `prefer_ipv6` varchar(3) DEFAULT 'no',
  `bind_rtp_to_media_address` varchar(3) DEFAULT 'no',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `ps_endpoints`
--

LOCK TABLES `ps_endpoints` WRITE;
/*!40000 ALTER TABLE `ps_endpoints` DISABLE KEYS */;
INSERT INTO `ps_endpoints` VALUES
('endpoint-s1','transport-udp','aor-s1','','from-provider-inbound','all','ulaw,alaw','no','invite','invite','none','no','rfc4733',NULL,'yes','no','username,ip',NULL,'default',NULL,NULL,'yes','no','yes','yes','yes','yes',90,'yes',1800,NULL,NULL,NULL,'yes','yes','yes',NULL,'en','asterisk',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'no','no','no','no','no',120,60,0,NULL,NULL,'yes','no','no','no','no','no','no',NULL,NULL,NULL,NULL,0,'no',NULL,0,'no',0,'no','no','no','yes','no','no',NULL,NULL,'yes','no','no','yes','no','no','no'),
('endpoint-s3','transport-udp','aor-s3','','from-provider-intermediate','all','ulaw,alaw','no','invite','invite','none','no','rfc4733',NULL,'yes','no','username,ip',NULL,'default',NULL,NULL,'yes','no','yes','yes','yes','yes',90,'yes',1800,NULL,NULL,NULL,'yes','yes','yes',NULL,'en','asterisk',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'no','no','no','no','no',120,60,0,NULL,NULL,'yes','no','no','no','no','no','no',NULL,NULL,NULL,NULL,0,'no',NULL,0,'no',0,'no','no','no','yes','no','no',NULL,NULL,'yes','no','no','yes','no','no','no'),
('endpoint-s4','transport-udp','aor-s4','','from-provider-final','all','ulaw,alaw','no','invite','invite','none','no','rfc4733',NULL,'yes','no','username,ip',NULL,'default',NULL,NULL,'yes','no','yes','yes','yes','yes',90,'yes',1800,NULL,NULL,NULL,'yes','yes','yes',NULL,'en','asterisk',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'no','no','no','no','no',120,60,0,NULL,NULL,'yes','no','no','no','no','no','no',NULL,NULL,NULL,NULL,0,'no',NULL,0,'no',0,'no','no','no','yes','no','no',NULL,NULL,'yes','no','no','yes','no','no','no');
/*!40000 ALTER TABLE `ps_endpoints` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `ps_globals`
--

DROP TABLE IF EXISTS `ps_globals`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `ps_globals` (
  `id` varchar(40) NOT NULL,
  `max_forwards` int(11) DEFAULT 70,
  `user_agent` varchar(255) DEFAULT 'Asterisk PBX',
  `default_outbound_endpoint` varchar(40) DEFAULT NULL,
  `debug` varchar(3) DEFAULT 'no',
  `endpoint_identifier_order` varchar(40) DEFAULT 'ip,username,anonymous',
  `max_initial_qualify_time` int(11) DEFAULT 0,
  `keep_alive_interval` int(11) DEFAULT 30,
  `contact_expiration_check_interval` int(11) DEFAULT 30,
  `disable_multi_domain` varchar(3) DEFAULT 'no',
  `unidentified_request_count` int(11) DEFAULT 5,
  `unidentified_request_period` int(11) DEFAULT 5,
  `unidentified_request_prune_interval` int(11) DEFAULT 30,
  `default_from_user` varchar(80) DEFAULT 'asterisk',
  `default_voicemail_extension` varchar(40) DEFAULT NULL,
  `mwi_tps_queue_high` int(11) DEFAULT 500,
  `mwi_tps_queue_low` int(11) DEFAULT -1,
  `mwi_disable_initial_unsolicited` varchar(3) DEFAULT 'no',
  `ignore_uri_user_options` varchar(3) DEFAULT 'no',
  `send_contact_status_on_update_registration` varchar(3) DEFAULT 'no',
  `default_realm` varchar(40) DEFAULT NULL,
  `regcontext` varchar(80) DEFAULT NULL,
  `contact_cache_expire` int(11) DEFAULT 0,
  `disable_initial_options` varchar(3) DEFAULT 'no',
  `use_callerid_contact` varchar(3) DEFAULT 'no',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `ps_globals`
--

LOCK TABLES `ps_globals` WRITE;
/*!40000 ALTER TABLE `ps_globals` DISABLE KEYS */;
INSERT INTO `ps_globals` VALUES
('global',70,'Asterisk PBX',NULL,'no','ip,username,anonymous',0,30,30,'no',5,5,30,'asterisk',NULL,500,-1,'no','no','no',NULL,NULL,0,'no','no');
/*!40000 ALTER TABLE `ps_globals` ENABLE KEYS */;
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
INSERT INTO `ps_transports` VALUES
('transport-tcp',1,'0.0.0.0:5060',NULL,NULL,NULL,NULL,0,NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,'tcp',NULL,0,NULL,NULL,'yes','no'),
('transport-tls',1,'0.0.0.0:5061',NULL,NULL,NULL,NULL,0,NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,'tls',NULL,0,NULL,NULL,'yes','no'),
('transport-udp',1,'0.0.0.0:5060',NULL,NULL,NULL,NULL,0,NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,'udp',NULL,0,NULL,NULL,'yes','no');
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
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

--
-- Temporary table structure for view `v_active_calls`
--

DROP TABLE IF EXISTS `v_active_calls`;
/*!50001 DROP VIEW IF EXISTS `v_active_calls`*/;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8mb4;
/*!50001 CREATE VIEW `v_active_calls` AS SELECT
 1 AS `call_id`,
  1 AS `original_ani`,
  1 AS `original_dnis`,
  1 AS `assigned_did`,
  1 AS `route_name`,
  1 AS `status`,
  1 AS `current_step`,
  1 AS `start_time`,
  1 AS `duration_seconds`,
  1 AS `inbound_provider`,
  1 AS `intermediate_provider`,
  1 AS `final_provider` */;
SET character_set_client = @saved_cs_client;

--
-- Temporary table structure for view `v_did_utilization`
--

DROP TABLE IF EXISTS `v_did_utilization`;
/*!50001 DROP VIEW IF EXISTS `v_did_utilization`*/;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8mb4;
/*!50001 CREATE VIEW `v_did_utilization` AS SELECT
 1 AS `provider_name`,
  1 AS `total_dids`,
  1 AS `used_dids`,
  1 AS `available_dids`,
  1 AS `utilization_percent` */;
SET character_set_client = @saved_cs_client;

--
-- Temporary table structure for view `v_provider_summary`
--

DROP TABLE IF EXISTS `v_provider_summary`;
/*!50001 DROP VIEW IF EXISTS `v_provider_summary`*/;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8mb4;
/*!50001 CREATE VIEW `v_provider_summary` AS SELECT
 1 AS `name`,
  1 AS `type`,
  1 AS `active`,
  1 AS `health_score`,
  1 AS `active_calls`,
  1 AS `is_healthy`,
  1 AS `calls_today`,
  1 AS `asr_today`,
  1 AS `acd_today` */;
SET character_set_client = @saved_cs_client;

--
-- Final view structure for view `v_active_calls`
--

/*!50001 DROP VIEW IF EXISTS `v_active_calls`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8mb3 */;
/*!50001 SET character_set_results     = utf8mb3 */;
/*!50001 SET collation_connection      = utf8mb3_general_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 DEFINER=`root`@`localhost` SQL SECURITY DEFINER */
/*!50001 VIEW `v_active_calls` AS select `cr`.`call_id` AS `call_id`,`cr`.`original_ani` AS `original_ani`,`cr`.`original_dnis` AS `original_dnis`,`cr`.`assigned_did` AS `assigned_did`,`cr`.`route_name` AS `route_name`,`cr`.`status` AS `status`,`cr`.`current_step` AS `current_step`,`cr`.`start_time` AS `start_time`,timestampdiff(SECOND,`cr`.`start_time`,current_timestamp()) AS `duration_seconds`,`cr`.`inbound_provider` AS `inbound_provider`,`cr`.`intermediate_provider` AS `intermediate_provider`,`cr`.`final_provider` AS `final_provider` from `call_records` `cr` where `cr`.`status` in ('INITIATED','ACTIVE','RETURNED_FROM_S3','ROUTING_TO_S4') order by `cr`.`start_time` desc */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;

--
-- Final view structure for view `v_did_utilization`
--

/*!50001 DROP VIEW IF EXISTS `v_did_utilization`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8mb3 */;
/*!50001 SET character_set_results     = utf8mb3 */;
/*!50001 SET collation_connection      = utf8mb3_general_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 DEFINER=`root`@`localhost` SQL SECURITY DEFINER */
/*!50001 VIEW `v_did_utilization` AS select `dids`.`provider_name` AS `provider_name`,count(0) AS `total_dids`,sum(case when `dids`.`in_use` = 1 then 1 else 0 end) AS `used_dids`,sum(case when `dids`.`in_use` = 0 then 1 else 0 end) AS `available_dids`,round(sum(case when `dids`.`in_use` = 1 then 1 else 0 end) / count(0) * 100,2) AS `utilization_percent` from `dids` group by `dids`.`provider_name` */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;

--
-- Final view structure for view `v_provider_summary`
--

/*!50001 DROP VIEW IF EXISTS `v_provider_summary`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8mb3 */;
/*!50001 SET character_set_results     = utf8mb3 */;
/*!50001 SET collation_connection      = utf8mb3_general_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 DEFINER=`root`@`localhost` SQL SECURITY DEFINER */
/*!50001 VIEW `v_provider_summary` AS select `p`.`name` AS `name`,`p`.`type` AS `type`,`p`.`active` AS `active`,`ph`.`health_score` AS `health_score`,`ph`.`active_calls` AS `active_calls`,`ph`.`is_healthy` AS `is_healthy`,`ps`.`total_calls` AS `calls_today`,`ps`.`asr` AS `asr_today`,`ps`.`acd` AS `acd_today` from ((`providers` `p` left join `provider_health` `ph` on(`p`.`name` = `ph`.`provider_name`)) left join `provider_stats` `ps` on(`p`.`name` = `ps`.`provider_name` and `ps`.`stat_type` = 'day' and cast(`ps`.`period_start` as date) = curdate())) */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2025-06-05 17:15:04
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
  KEY `idx_user` (`user_id`),
  KEY `idx_audit_composite` (`entity_type`,`entity_id`,`created_at`)
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
  KEY `idx_did` (`assigned_did`),
  KEY `idx_call_records_composite` (`status`,`start_time`),
  KEY `idx_call_records_route` (`route_name`,`start_time`)
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
-- Table structure for table `cdr`
--

DROP TABLE IF EXISTS `cdr`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `cdr` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `accountcode` varchar(20) DEFAULT NULL,
  `src` varchar(80) DEFAULT NULL,
  `dst` varchar(80) DEFAULT NULL,
  `dcontext` varchar(80) DEFAULT NULL,
  `clid` varchar(80) DEFAULT NULL,
  `channel` varchar(80) DEFAULT NULL,
  `dstchannel` varchar(80) DEFAULT NULL,
  `lastapp` varchar(80) DEFAULT NULL,
  `lastdata` varchar(80) DEFAULT NULL,
  `start` datetime DEFAULT NULL,
  `answer` datetime DEFAULT NULL,
  `end` datetime DEFAULT NULL,
  `duration` int(11) DEFAULT NULL,
  `billsec` int(11) DEFAULT NULL,
  `disposition` varchar(45) DEFAULT NULL,
  `amaflags` int(11) DEFAULT NULL,
  `uniqueid` varchar(32) DEFAULT NULL,
  `userfield` varchar(255) DEFAULT NULL,
  `peeraccount` varchar(20) DEFAULT NULL,
  `linkedid` varchar(32) DEFAULT NULL,
  `sequence` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_start` (`start`),
  KEY `idx_src` (`src`),
  KEY `idx_dst` (`dst`),
  KEY `idx_uniqueid` (`uniqueid`),
  KEY `idx_accountcode` (`accountcode`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `cdr`
--

LOCK TABLES `cdr` WRITE;
/*!40000 ALTER TABLE `cdr` DISABLE KEYS */;
/*!40000 ALTER TABLE `cdr` ENABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `dids`
--

LOCK TABLES `dids` WRITE;
/*!40000 ALTER TABLE `dids` DISABLE KEYS */;
INSERT INTO `dids` VALUES
(1,'584148757547',NULL,'s3',0,NULL,NULL,NULL,NULL,0.00,0.0000,NULL,NULL,NULL,0,NULL,'2025-06-05 15:29:37','2025-06-05 15:29:37'),
(2,'584148757548',NULL,'s3',0,NULL,NULL,NULL,NULL,0.00,0.0000,NULL,NULL,NULL,0,NULL,'2025-06-05 15:29:37','2025-06-05 15:29:37'),
(3,'584148757549',NULL,'s3',0,NULL,NULL,NULL,NULL,0.00,0.0000,NULL,NULL,NULL,0,NULL,'2025-06-05 15:29:37','2025-06-05 15:29:37'),
(4,'584249726299',NULL,'s3',0,NULL,NULL,NULL,NULL,0.00,0.0000,NULL,NULL,NULL,0,NULL,'2025-06-05 15:29:37','2025-06-05 15:29:37'),
(5,'584249726300',NULL,'s3',0,NULL,NULL,NULL,NULL,0.00,0.0000,NULL,NULL,NULL,0,NULL,'2025-06-05 15:29:37','2025-06-05 15:29:37'),
(6,'584249726301',NULL,'s3',0,NULL,NULL,NULL,NULL,0.00,0.0000,NULL,NULL,NULL,0,NULL,'2025-06-05 15:29:37','2025-06-05 15:29:37');
/*!40000 ALTER TABLE `dids` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `extensions`
--

DROP TABLE IF EXISTS `extensions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `extensions` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `context` varchar(40) NOT NULL,
  `exten` varchar(40) NOT NULL,
  `priority` int(11) NOT NULL,
  `app` varchar(40) NOT NULL,
  `appdata` varchar(256) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `context_exten_priority` (`context`,`exten`,`priority`),
  KEY `idx_context` (`context`),
  KEY `idx_exten` (`exten`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `extensions`
--

LOCK TABLES `extensions` WRITE;
/*!40000 ALTER TABLE `extensions` DISABLE KEYS */;
/*!40000 ALTER TABLE `extensions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `provider_group_members`
--

DROP TABLE IF EXISTS `provider_group_members`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `provider_group_members` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `group_id` int(11) NOT NULL,
  `provider_id` int(11) NOT NULL,
  `provider_name` varchar(100) NOT NULL,
  `added_manually` tinyint(1) DEFAULT 0,
  `matched_by_rule` tinyint(1) DEFAULT 0,
  `priority_override` int(11) DEFAULT NULL,
  `weight_override` int(11) DEFAULT NULL,
  `metadata` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`metadata`)),
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_group_provider` (`group_id`,`provider_id`),
  KEY `idx_group` (`group_id`),
  KEY `idx_provider` (`provider_name`),
  KEY `provider_id` (`provider_id`),
  CONSTRAINT `provider_group_members_ibfk_1` FOREIGN KEY (`group_id`) REFERENCES `provider_groups` (`id`) ON DELETE CASCADE,
  CONSTRAINT `provider_group_members_ibfk_2` FOREIGN KEY (`provider_id`) REFERENCES `providers` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `provider_group_members`
--

LOCK TABLES `provider_group_members` WRITE;
/*!40000 ALTER TABLE `provider_group_members` DISABLE KEYS */;
/*!40000 ALTER TABLE `provider_group_members` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `provider_group_stats`
--

DROP TABLE IF EXISTS `provider_group_stats`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `provider_group_stats` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `group_name` varchar(100) NOT NULL,
  `stat_type` enum('minute','hour','day') NOT NULL,
  `period_start` timestamp NOT NULL,
  `total_calls` bigint(20) DEFAULT 0,
  `completed_calls` bigint(20) DEFAULT 0,
  `failed_calls` bigint(20) DEFAULT 0,
  `total_duration` bigint(20) DEFAULT 0,
  `avg_duration` decimal(10,2) DEFAULT 0.00,
  `asr` decimal(5,2) DEFAULT 0.00,
  `acd` decimal(10,2) DEFAULT 0.00,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_group_period` (`group_name`,`stat_type`,`period_start`),
  KEY `idx_group` (`group_name`),
  KEY `idx_period` (`period_start`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `provider_group_stats`
--

LOCK TABLES `provider_group_stats` WRITE;
/*!40000 ALTER TABLE `provider_group_stats` DISABLE KEYS */;
/*!40000 ALTER TABLE `provider_group_stats` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `provider_groups`
--

DROP TABLE IF EXISTS `provider_groups`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `provider_groups` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL,
  `description` text DEFAULT NULL,
  `group_type` enum('manual','regex','metadata','dynamic') DEFAULT 'manual',
  `match_pattern` varchar(255) DEFAULT NULL,
  `match_field` varchar(100) DEFAULT NULL,
  `match_operator` enum('equals','contains','starts_with','ends_with','regex','in','not_in') DEFAULT 'equals',
  `match_value` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`match_value`)),
  `provider_type` enum('inbound','intermediate','final','any') DEFAULT 'any',
  `enabled` tinyint(1) DEFAULT 1,
  `priority` int(11) DEFAULT 10,
  `metadata` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`metadata`)),
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`),
  KEY `idx_enabled` (`enabled`),
  KEY `idx_type` (`group_type`),
  KEY `idx_provider_type` (`provider_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `provider_groups`
--

LOCK TABLES `provider_groups` WRITE;
/*!40000 ALTER TABLE `provider_groups` DISABLE KEYS */;
/*!40000 ALTER TABLE `provider_groups` ENABLE KEYS */;
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
  `inbound_is_group` tinyint(1) DEFAULT 0,
  `intermediate_provider` varchar(100) NOT NULL,
  `intermediate_is_group` tinyint(1) DEFAULT 0,
  `final_provider` varchar(100) NOT NULL,
  `final_is_group` tinyint(1) DEFAULT 0,
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
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `provider_routes`
--

LOCK TABLES `provider_routes` WRITE;
/*!40000 ALTER TABLE `provider_routes` DISABLE KEYS */;
INSERT INTO `provider_routes` VALUES
(2,'main-route','','s1',0,'s3',0,'s4',0,'round_robin',10,1,100,0,1,NULL,NULL,NULL,'2025-06-05 15:37:30','2025-06-05 15:37:30');
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
  KEY `idx_period` (`period_start`),
  KEY `idx_provider_stats_composite` (`provider_name`,`stat_type`,`period_start`)
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
  `country` varchar(50) DEFAULT NULL,
  `region` varchar(100) DEFAULT NULL,
  `city` varchar(100) DEFAULT NULL,
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
  KEY `idx_priority` (`priority` DESC),
  KEY `idx_country` (`country`),
  KEY `idx_region` (`region`)
) ENGINE=InnoDB AUTO_INCREMENT=9 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `providers`
--

LOCK TABLES `providers` WRITE;
/*!40000 ALTER TABLE `providers` DISABLE KEYS */;
INSERT INTO `providers` VALUES
(6,'s3','intermediate','10.0.0.3',NULL,NULL,NULL,5060,'','','ip','udp','[\"ulaw\",\"alaw\"]',0,0,10,1,0.0000,1,1,NULL,'unknown','null','2025-06-05 15:29:37','2025-06-05 15:29:37'),
(7,'s4','final','10.0.0.4',NULL,NULL,NULL,5060,'','','ip','udp','[\"ulaw\",\"alaw\"]',0,0,10,1,0.0000,1,1,NULL,'unknown','null','2025-06-05 15:29:37','2025-06-05 15:29:37'),
(8,'s1','inbound','10.0.0.1',NULL,NULL,NULL,5060,'','','ip','udp','[\"ulaw\",\"alaw\"]',0,0,10,1,0.0000,1,1,NULL,'unknown','null','2025-06-05 15:37:23','2025-06-05 15:37:23');
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
  `default_expiration` int(11) DEFAULT 3600,
  `mailboxes` varchar(80) DEFAULT NULL,
  `max_contacts` int(11) DEFAULT 1,
  `minimum_expiration` int(11) DEFAULT 60,
  `remove_existing` varchar(3) DEFAULT 'yes',
  `qualify_frequency` int(11) DEFAULT 0,
  `authenticate_qualify` varchar(3) DEFAULT 'no',
  `maximum_expiration` int(11) DEFAULT 7200,
  `outbound_proxy` varchar(40) DEFAULT NULL,
  `support_path` varchar(3) DEFAULT 'no',
  `qualify_timeout` decimal(5,3) DEFAULT 3.000,
  `voicemail_extension` varchar(40) DEFAULT NULL,
  `remove_unavailable` varchar(3) DEFAULT 'no',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `ps_aors`
--

LOCK TABLES `ps_aors` WRITE;
/*!40000 ALTER TABLE `ps_aors` DISABLE KEYS */;
INSERT INTO `ps_aors` VALUES
('aor-s1',NULL,3600,NULL,1,60,'yes',30,'no',7200,NULL,'no',3.000,NULL,'no'),
('aor-s3',NULL,3600,NULL,1,60,'yes',30,'no',7200,NULL,'no',3.000,NULL,'no'),
('aor-s4',NULL,3600,NULL,1,60,'yes',30,'no',7200,NULL,'no',3.000,NULL,'no');
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
  `auth_type` varchar(40) DEFAULT 'userpass',
  `nonce_lifetime` int(11) DEFAULT 32,
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
-- Table structure for table `ps_endpoint_id_ips`
--

DROP TABLE IF EXISTS `ps_endpoint_id_ips`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `ps_endpoint_id_ips` (
  `id` varchar(40) NOT NULL,
  `endpoint` varchar(40) DEFAULT NULL,
  `match` varchar(80) DEFAULT NULL,
  `srv_lookups` varchar(3) DEFAULT 'yes',
  `match_header` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `ps_endpoint_id_ips`
--

LOCK TABLES `ps_endpoint_id_ips` WRITE;
/*!40000 ALTER TABLE `ps_endpoint_id_ips` DISABLE KEYS */;
INSERT INTO `ps_endpoint_id_ips` VALUES
('ip-s1','endpoint-s1','10.0.0.1/32','yes',NULL),
('ip-s3','endpoint-s3','10.0.0.3/32','yes',NULL),
('ip-s4','endpoint-s4','10.0.0.4/32','yes',NULL);
/*!40000 ALTER TABLE `ps_endpoint_id_ips` ENABLE KEYS */;
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
  `auth` varchar(100) DEFAULT NULL,
  `context` varchar(40) DEFAULT 'default',
  `disallow` varchar(200) DEFAULT 'all',
  `allow` varchar(200) DEFAULT NULL,
  `direct_media` varchar(3) DEFAULT 'yes',
  `connected_line_method` varchar(40) DEFAULT 'invite',
  `direct_media_method` varchar(40) DEFAULT 'invite',
  `direct_media_glare_mitigation` varchar(40) DEFAULT 'none',
  `disable_direct_media_on_nat` varchar(3) DEFAULT 'no',
  `dtmf_mode` varchar(40) DEFAULT 'rfc4733',
  `external_media_address` varchar(40) DEFAULT NULL,
  `force_rport` varchar(3) DEFAULT 'yes',
  `ice_support` varchar(3) DEFAULT 'no',
  `identify_by` varchar(40) DEFAULT 'username,ip',
  `mailboxes` varchar(40) DEFAULT NULL,
  `moh_suggest` varchar(40) DEFAULT 'default',
  `outbound_auth` varchar(40) DEFAULT NULL,
  `outbound_proxy` varchar(40) DEFAULT NULL,
  `rewrite_contact` varchar(3) DEFAULT 'no',
  `rtp_ipv6` varchar(3) DEFAULT 'no',
  `rtp_symmetric` varchar(3) DEFAULT 'no',
  `send_diversion` varchar(3) DEFAULT 'yes',
  `send_pai` varchar(3) DEFAULT 'no',
  `send_rpid` varchar(3) DEFAULT 'no',
  `timers_min_se` int(11) DEFAULT 90,
  `timers` varchar(3) DEFAULT 'yes',
  `timers_sess_expires` int(11) DEFAULT 1800,
  `callerid` varchar(40) DEFAULT NULL,
  `callerid_privacy` varchar(40) DEFAULT NULL,
  `callerid_tag` varchar(40) DEFAULT NULL,
  `trust_id_inbound` varchar(3) DEFAULT 'no',
  `trust_id_outbound` varchar(3) DEFAULT 'no',
  `send_connected_line` varchar(3) DEFAULT 'yes',
  `accountcode` varchar(20) DEFAULT NULL,
  `language` varchar(10) DEFAULT 'en',
  `rtp_engine` varchar(40) DEFAULT 'asterisk',
  `dtls_verify` varchar(40) DEFAULT NULL,
  `dtls_rekey` varchar(40) DEFAULT NULL,
  `dtls_cert_file` varchar(200) DEFAULT NULL,
  `dtls_private_key` varchar(200) DEFAULT NULL,
  `dtls_cipher` varchar(200) DEFAULT NULL,
  `dtls_ca_file` varchar(200) DEFAULT NULL,
  `dtls_ca_path` varchar(200) DEFAULT NULL,
  `dtls_setup` varchar(40) DEFAULT NULL,
  `srtp_tag_32` varchar(3) DEFAULT 'no',
  `media_encryption` varchar(40) DEFAULT 'no',
  `use_avpf` varchar(3) DEFAULT 'no',
  `force_avp` varchar(3) DEFAULT 'no',
  `media_use_received_transport` varchar(3) DEFAULT 'no',
  `rtp_timeout` int(11) DEFAULT 0,
  `rtp_timeout_hold` int(11) DEFAULT 0,
  `rtp_keepalive` int(11) DEFAULT 0,
  `record_on_feature` varchar(40) DEFAULT NULL,
  `record_off_feature` varchar(40) DEFAULT NULL,
  `allow_transfer` varchar(3) DEFAULT 'yes',
  `user_eq_phone` varchar(3) DEFAULT 'no',
  `moh_passthrough` varchar(3) DEFAULT 'no',
  `media_encryption_optimistic` varchar(3) DEFAULT 'no',
  `rpid_immediate` varchar(3) DEFAULT 'no',
  `g726_non_standard` varchar(3) DEFAULT 'no',
  `inband_progress` varchar(3) DEFAULT 'no',
  `call_group` varchar(40) DEFAULT NULL,
  `pickup_group` varchar(40) DEFAULT NULL,
  `named_call_group` varchar(40) DEFAULT NULL,
  `named_pickup_group` varchar(40) DEFAULT NULL,
  `device_state_busy_at` int(11) DEFAULT 0,
  `t38_udptl` varchar(3) DEFAULT 'no',
  `t38_udptl_ec` varchar(40) DEFAULT NULL,
  `t38_udptl_maxdatagram` int(11) DEFAULT 0,
  `fax_detect` varchar(3) DEFAULT 'no',
  `fax_detect_timeout` int(11) DEFAULT 0,
  `t38_udptl_nat` varchar(3) DEFAULT 'no',
  `t38_udptl_ipv6` varchar(3) DEFAULT 'no',
  `rtcp_mux` varchar(3) DEFAULT 'no',
  `allow_overlap` varchar(3) DEFAULT 'yes',
  `bundle` varchar(3) DEFAULT 'no',
  `webrtc` varchar(3) DEFAULT 'no',
  `dtls_fingerprint` varchar(40) DEFAULT NULL,
  `incoming_mwi_mailbox` varchar(40) DEFAULT NULL,
  `follow_early_media_fork` varchar(3) DEFAULT 'yes',
  `accept_multiple_sdp_answers` varchar(3) DEFAULT 'no',
  `suppress_q850_reason_headers` varchar(3) DEFAULT 'no',
  `trust_connected_line` varchar(3) DEFAULT 'yes',
  `send_history_info` varchar(3) DEFAULT 'no',
  `prefer_ipv6` varchar(3) DEFAULT 'no',
  `bind_rtp_to_media_address` varchar(3) DEFAULT 'no',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `ps_endpoints`
--

LOCK TABLES `ps_endpoints` WRITE;
/*!40000 ALTER TABLE `ps_endpoints` DISABLE KEYS */;
INSERT INTO `ps_endpoints` VALUES
('endpoint-s1','transport-udp','aor-s1','','from-provider-inbound','all','ulaw,alaw','no','invite','invite','none','no','rfc4733',NULL,'yes','no','username,ip',NULL,'default',NULL,NULL,'yes','no','yes','yes','yes','yes',90,'yes',1800,NULL,NULL,NULL,'yes','yes','yes',NULL,'en','asterisk',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'no','no','no','no','no',120,60,0,NULL,NULL,'yes','no','no','no','no','no','no',NULL,NULL,NULL,NULL,0,'no',NULL,0,'no',0,'no','no','no','yes','no','no',NULL,NULL,'yes','no','no','yes','no','no','no'),
('endpoint-s3','transport-udp','aor-s3','','from-provider-intermediate','all','ulaw,alaw','no','invite','invite','none','no','rfc4733',NULL,'yes','no','username,ip',NULL,'default',NULL,NULL,'yes','no','yes','yes','yes','yes',90,'yes',1800,NULL,NULL,NULL,'yes','yes','yes',NULL,'en','asterisk',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'no','no','no','no','no',120,60,0,NULL,NULL,'yes','no','no','no','no','no','no',NULL,NULL,NULL,NULL,0,'no',NULL,0,'no',0,'no','no','no','yes','no','no',NULL,NULL,'yes','no','no','yes','no','no','no'),
('endpoint-s4','transport-udp','aor-s4','','from-provider-final','all','ulaw,alaw','no','invite','invite','none','no','rfc4733',NULL,'yes','no','username,ip',NULL,'default',NULL,NULL,'yes','no','yes','yes','yes','yes',90,'yes',1800,NULL,NULL,NULL,'yes','yes','yes',NULL,'en','asterisk',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'no','no','no','no','no',120,60,0,NULL,NULL,'yes','no','no','no','no','no','no',NULL,NULL,NULL,NULL,0,'no',NULL,0,'no',0,'no','no','no','yes','no','no',NULL,NULL,'yes','no','no','yes','no','no','no');
/*!40000 ALTER TABLE `ps_endpoints` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `ps_globals`
--

DROP TABLE IF EXISTS `ps_globals`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `ps_globals` (
  `id` varchar(40) NOT NULL,
  `max_forwards` int(11) DEFAULT 70,
  `user_agent` varchar(255) DEFAULT 'Asterisk PBX',
  `default_outbound_endpoint` varchar(40) DEFAULT NULL,
  `debug` varchar(3) DEFAULT 'no',
  `endpoint_identifier_order` varchar(40) DEFAULT 'ip,username,anonymous',
  `max_initial_qualify_time` int(11) DEFAULT 0,
  `keep_alive_interval` int(11) DEFAULT 30,
  `contact_expiration_check_interval` int(11) DEFAULT 30,
  `disable_multi_domain` varchar(3) DEFAULT 'no',
  `unidentified_request_count` int(11) DEFAULT 5,
  `unidentified_request_period` int(11) DEFAULT 5,
  `unidentified_request_prune_interval` int(11) DEFAULT 30,
  `default_from_user` varchar(80) DEFAULT 'asterisk',
  `default_voicemail_extension` varchar(40) DEFAULT NULL,
  `mwi_tps_queue_high` int(11) DEFAULT 500,
  `mwi_tps_queue_low` int(11) DEFAULT -1,
  `mwi_disable_initial_unsolicited` varchar(3) DEFAULT 'no',
  `ignore_uri_user_options` varchar(3) DEFAULT 'no',
  `send_contact_status_on_update_registration` varchar(3) DEFAULT 'no',
  `default_realm` varchar(40) DEFAULT NULL,
  `regcontext` varchar(80) DEFAULT NULL,
  `contact_cache_expire` int(11) DEFAULT 0,
  `disable_initial_options` varchar(3) DEFAULT 'no',
  `use_callerid_contact` varchar(3) DEFAULT 'no',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `ps_globals`
--

LOCK TABLES `ps_globals` WRITE;
/*!40000 ALTER TABLE `ps_globals` DISABLE KEYS */;
INSERT INTO `ps_globals` VALUES
('global',70,'Asterisk PBX',NULL,'no','ip,username,anonymous',0,30,30,'no',5,5,30,'asterisk',NULL,500,-1,'no','no','no',NULL,NULL,0,'no','no');
/*!40000 ALTER TABLE `ps_globals` ENABLE KEYS */;
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
INSERT INTO `ps_transports` VALUES
('transport-tcp',1,'0.0.0.0:5060',NULL,NULL,NULL,NULL,0,NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,'tcp',NULL,0,NULL,NULL,'yes','no'),
('transport-tls',1,'0.0.0.0:5061',NULL,NULL,NULL,NULL,0,NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,'tls',NULL,0,NULL,NULL,'yes','no'),
('transport-udp',1,'0.0.0.0:5060',NULL,NULL,NULL,NULL,0,NULL,NULL,NULL,0,NULL,NULL,NULL,NULL,'udp',NULL,0,NULL,NULL,'yes','no');
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
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

--
-- Temporary table structure for view `v_active_calls`
--

DROP TABLE IF EXISTS `v_active_calls`;
/*!50001 DROP VIEW IF EXISTS `v_active_calls`*/;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8mb4;
/*!50001 CREATE VIEW `v_active_calls` AS SELECT
 1 AS `call_id`,
  1 AS `original_ani`,
  1 AS `original_dnis`,
  1 AS `assigned_did`,
  1 AS `route_name`,
  1 AS `status`,
  1 AS `current_step`,
  1 AS `start_time`,
  1 AS `duration_seconds`,
  1 AS `inbound_provider`,
  1 AS `intermediate_provider`,
  1 AS `final_provider` */;
SET character_set_client = @saved_cs_client;

--
-- Temporary table structure for view `v_did_utilization`
--

DROP TABLE IF EXISTS `v_did_utilization`;
/*!50001 DROP VIEW IF EXISTS `v_did_utilization`*/;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8mb4;
/*!50001 CREATE VIEW `v_did_utilization` AS SELECT
 1 AS `provider_name`,
  1 AS `total_dids`,
  1 AS `used_dids`,
  1 AS `available_dids`,
  1 AS `utilization_percent` */;
SET character_set_client = @saved_cs_client;

--
-- Temporary table structure for view `v_provider_summary`
--

DROP TABLE IF EXISTS `v_provider_summary`;
/*!50001 DROP VIEW IF EXISTS `v_provider_summary`*/;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8mb4;
/*!50001 CREATE VIEW `v_provider_summary` AS SELECT
 1 AS `name`,
  1 AS `type`,
  1 AS `active`,
  1 AS `health_score`,
  1 AS `active_calls`,
  1 AS `is_healthy`,
  1 AS `calls_today`,
  1 AS `asr_today`,
  1 AS `acd_today` */;
SET character_set_client = @saved_cs_client;

--
-- Final view structure for view `v_active_calls`
--

/*!50001 DROP VIEW IF EXISTS `v_active_calls`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8mb3 */;
/*!50001 SET character_set_results     = utf8mb3 */;
/*!50001 SET collation_connection      = utf8mb3_general_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 DEFINER=`root`@`localhost` SQL SECURITY DEFINER */
/*!50001 VIEW `v_active_calls` AS select `cr`.`call_id` AS `call_id`,`cr`.`original_ani` AS `original_ani`,`cr`.`original_dnis` AS `original_dnis`,`cr`.`assigned_did` AS `assigned_did`,`cr`.`route_name` AS `route_name`,`cr`.`status` AS `status`,`cr`.`current_step` AS `current_step`,`cr`.`start_time` AS `start_time`,timestampdiff(SECOND,`cr`.`start_time`,current_timestamp()) AS `duration_seconds`,`cr`.`inbound_provider` AS `inbound_provider`,`cr`.`intermediate_provider` AS `intermediate_provider`,`cr`.`final_provider` AS `final_provider` from `call_records` `cr` where `cr`.`status` in ('INITIATED','ACTIVE','RETURNED_FROM_S3','ROUTING_TO_S4') order by `cr`.`start_time` desc */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;

--
-- Final view structure for view `v_did_utilization`
--

/*!50001 DROP VIEW IF EXISTS `v_did_utilization`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8mb3 */;
/*!50001 SET character_set_results     = utf8mb3 */;
/*!50001 SET collation_connection      = utf8mb3_general_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 DEFINER=`root`@`localhost` SQL SECURITY DEFINER */
/*!50001 VIEW `v_did_utilization` AS select `dids`.`provider_name` AS `provider_name`,count(0) AS `total_dids`,sum(case when `dids`.`in_use` = 1 then 1 else 0 end) AS `used_dids`,sum(case when `dids`.`in_use` = 0 then 1 else 0 end) AS `available_dids`,round(sum(case when `dids`.`in_use` = 1 then 1 else 0 end) / count(0) * 100,2) AS `utilization_percent` from `dids` group by `dids`.`provider_name` */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;

--
-- Final view structure for view `v_provider_summary`
--

/*!50001 DROP VIEW IF EXISTS `v_provider_summary`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8mb3 */;
/*!50001 SET character_set_results     = utf8mb3 */;
/*!50001 SET collation_connection      = utf8mb3_general_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 DEFINER=`root`@`localhost` SQL SECURITY DEFINER */
/*!50001 VIEW `v_provider_summary` AS select `p`.`name` AS `name`,`p`.`type` AS `type`,`p`.`active` AS `active`,`ph`.`health_score` AS `health_score`,`ph`.`active_calls` AS `active_calls`,`ph`.`is_healthy` AS `is_healthy`,`ps`.`total_calls` AS `calls_today`,`ps`.`asr` AS `asr_today`,`ps`.`acd` AS `acd_today` from ((`providers` `p` left join `provider_health` `ph` on(`p`.`name` = `ph`.`provider_name`)) left join `provider_stats` `ps` on(`p`.`name` = `ps`.`provider_name` and `ps`.`stat_type` = 'day' and cast(`ps`.`period_start` as date) = curdate())) */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2025-06-05 18:51:52
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

-- Dump completed on 2025-06-05 18:53:24
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

-- Dump completed on 2025-06-05 18:55:59
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
#!/bin/bash

# ARA Production System - Database Setup Script
# This script sets up the complete MySQL database for the Asterisk ARA Router

# Configuration
DB_HOST="localhost"
DB_PORT="3306"
DB_ROOT_USER="root"
DB_ROOT_PASS="temppass"
DB_NAME="asterisk_ara"
DB_USER="root"
DB_PASS="temppass"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "ARA Production System - Database Setup"
echo "=========================================="
echo ""

# Function to execute MySQL commands
mysql_exec() {
    if [ -z "$DB_ROOT_PASS" ]; then
        mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_ROOT_USER" -e "$1"
    else
        mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASS" -e "$1"
    fi
}

# Function to execute MySQL commands on specific database
mysql_db_exec() {
    if [ -z "$DB_ROOT_PASS" ]; then
        mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_ROOT_USER" "$DB_NAME" -e "$1"
    else
        mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASS" "$DB_NAME" -e "$1"
    fi
}

# Check MySQL connection
echo -n "Checking MySQL connection... "
if mysql_exec "SELECT 1" &>/dev/null; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    echo "Cannot connect to MySQL. Please check your credentials and try again."
    exit 1
fi

# Create database
echo -n "Creating database '$DB_NAME'... "
mysql_exec "CREATE DATABASE IF NOT EXISTS $DB_NAME DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
echo -e "${GREEN}OK${NC}"

# Create user and grant privileges
echo -n "Creating user '$DB_USER'... "
mysql_exec "CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$DB_PASS';"
mysql_exec "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'%';"
mysql_exec "FLUSH PRIVILEGES;"
echo -e "${GREEN}OK${NC}"

# Create the complete schema
echo "Creating database schema..."

cat > /tmp/ara_schema.sql << 'EOF'
-- Asterisk ARA Dynamic Call Router - Complete Schema
-- Full production schema with ARA tables and routing tables

USE asterisk_ara;

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

-- Create initial transports
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

-- ========================================
-- SAMPLE DATA (OPTIONAL)
-- ========================================

-- Sample providers (commented out - uncomment if needed)
/*
INSERT INTO providers (name, type, host, port, auth_type) VALUES
    ('s1-primary', 'inbound', '10.0.0.10', 5060, 'ip'),
    ('s1-backup', 'inbound', '10.0.0.11', 5060, 'ip'),
    ('s3-provider1', 'intermediate', '172.16.0.20', 5060, 'both'),
    ('s3-provider2', 'intermediate', '172.16.0.21', 5060, 'both'),
    ('s4-termination1', 'final', '192.168.1.30', 5060, 'credentials'),
    ('s4-termination2', 'final', '192.168.1.31', 5060, 'credentials');

-- Sample DIDs
INSERT INTO dids (number, provider_name, country, city) VALUES
    ('18001234567', 's3-provider1', 'US', 'New York'),
    ('18001234568', 's3-provider1', 'US', 'New York'),
    ('18001234569', 's3-provider2', 'US', 'Los Angeles'),
    ('18001234570', 's3-provider2', 'US', 'Los Angeles');

-- Sample route
INSERT INTO provider_routes (name, description, inbound_provider, intermediate_provider, final_provider, load_balance_mode) VALUES
    ('main-route', 'Primary routing path', 'inbound', 'intermediate', 'final', 'round_robin');
*/

EOF

# Execute the schema
echo "Executing schema..."
if [ -z "$DB_ROOT_PASS" ]; then
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_ROOT_USER" < /tmp/ara_schema.sql
else
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_ROOT_USER" -p"$DB_ROOT_PASS" < /tmp/ara_schema.sql
fi

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Schema created successfully${NC}"
else
    echo -e "${RED}Failed to create schema${NC}"
    exit 1
fi

# Clean up
rm -f /tmp/ara_schema.sql

echo ""
echo "=========================================="
echo -e "${GREEN}Database setup completed successfully!${NC}"
echo "=========================================="
echo ""
echo "Database Information:"
echo "  Host: $DB_HOST:$DB_PORT"
echo "  Database: $DB_NAME"
echo "  User: $DB_USER"
echo "  Password: $DB_PASS"
echo ""
echo "You can now configure your application with these credentials."
echo ""
echo "To test the connection:"
echo "  mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p'$DB_PASS' $DB_NAME"
echo ""
