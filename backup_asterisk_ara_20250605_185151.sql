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
