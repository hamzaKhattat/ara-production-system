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
