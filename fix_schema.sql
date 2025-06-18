-- Fix DID table schema to match the Go code expectations
ALTER TABLE dids 
ADD COLUMN IF NOT EXISTS `number` VARCHAR(20) AFTER `did`,
ADD COLUMN IF NOT EXISTS `destination` VARCHAR(100) AFTER `allocated_to`,
ADD COLUMN IF NOT EXISTS `usage_count` BIGINT DEFAULT 0 AFTER `per_minute_cost`,
ADD COLUMN IF NOT EXISTS `last_used_at` TIMESTAMP NULL AFTER `usage_count`;

-- Copy data from existing columns
UPDATE dids SET `number` = `did` WHERE `number` IS NULL;
UPDATE dids SET `destination` = `allocated_to` WHERE `destination` IS NULL;

-- Create indexes on new columns
CREATE INDEX IF NOT EXISTS idx_dids_number ON dids(`number`);
CREATE INDEX IF NOT EXISTS idx_dids_destination ON dids(`destination`);

-- Update stored procedures to use correct column names
DELIMITER $$

DROP PROCEDURE IF EXISTS GetAvailableDID$$
CREATE PROCEDURE GetAvailableDID(
   IN p_provider_name VARCHAR(100),
   IN p_destination VARCHAR(100),
   OUT p_did VARCHAR(20)
)
BEGIN
   DECLARE v_did VARCHAR(20) DEFAULT NULL;
   
   START TRANSACTION;
   
   -- Try to get DID for specific provider first
   SELECT did INTO v_did
   FROM dids
   WHERE in_use = 0 
       AND (p_provider_name IS NULL OR provider_name = p_provider_name)
   ORDER BY last_used_at ASC, RAND()
   LIMIT 1
   FOR UPDATE;
   
   IF v_did IS NOT NULL THEN
       UPDATE dids 
       SET in_use = 1,
           allocated_to = p_destination,
           destination = p_destination,
           allocation_time = NOW(),
           usage_count = usage_count + 1,
           updated_at = NOW()
       WHERE did = v_did;
   END IF;
   
   COMMIT;
   
   SET p_did = v_did;
END$$

DROP PROCEDURE IF EXISTS ReleaseDID$$
CREATE PROCEDURE ReleaseDID(
   IN p_did VARCHAR(20)
)
BEGIN
   UPDATE dids 
   SET in_use = 0,
       allocated_to = NULL,
       destination = NULL,
       allocation_time = NULL,
       last_used_at = NOW(),
       updated_at = NOW()
   WHERE did = p_did;
END$$

DELIMITER ;

-- Add missing columns to provider_routes for group support
ALTER TABLE provider_routes
ADD COLUMN IF NOT EXISTS `inbound_is_group` BOOLEAN DEFAULT FALSE AFTER `metadata`,
ADD COLUMN IF NOT EXISTS `intermediate_is_group` BOOLEAN DEFAULT FALSE AFTER `inbound_is_group`,
ADD COLUMN IF NOT EXISTS `final_is_group` BOOLEAN DEFAULT FALSE AFTER `intermediate_is_group`;

-- Add provider groups table
CREATE TABLE IF NOT EXISTS provider_groups (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    group_type ENUM('manual', 'regex', 'metadata', 'dynamic') NOT NULL DEFAULT 'manual',
    match_pattern VARCHAR(255),
    match_field VARCHAR(100),
    match_operator ENUM('equals', 'contains', 'starts_with', 'ends_with', 'regex', 'in', 'not_in'),
    match_value JSON,
    provider_type ENUM('inbound', 'intermediate', 'final', 'any') DEFAULT 'any',
    enabled BOOLEAN DEFAULT TRUE,
    priority INT DEFAULT 10,
    metadata JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_name (name),
    INDEX idx_type (group_type),
    INDEX idx_enabled (enabled)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Add provider group members table
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

-- Add missing columns to providers table
ALTER TABLE providers
ADD COLUMN IF NOT EXISTS `country` VARCHAR(50) AFTER `metadata`,
ADD COLUMN IF NOT EXISTS `region` VARCHAR(100) AFTER `country`,
ADD COLUMN IF NOT EXISTS `city` VARCHAR(100) AFTER `region`;
