-- fix-ara-database-entries.sql
-- Ensure database entries are correctly formatted for endpoint identification

USE asterisk_ara;

-- First, let's check current state
SELECT '=== Current ps_endpoint_id_ips entries ===' as Info;
SELECT * FROM ps_endpoint_id_ips;

-- Clear existing entries to start fresh
DELETE FROM ps_endpoint_id_ips;

-- Insert clean entries for each endpoint
-- For test1 (S1 - inbound provider at 10.0.0.1)
INSERT INTO ps_endpoint_id_ips (id, endpoint, `match`, srv_lookups, match_header) 
VALUES ('identify-test1', 'endpoint-test1', '10.0.0.1', 'yes', NULL);

-- For t3 (S3 - intermediate provider at 10.0.0.3)  
INSERT INTO ps_endpoint_id_ips (id, endpoint, `match`, srv_lookups, match_header)
VALUES ('identify-t3', 'endpoint-t3', '10.0.0.3', 'yes', NULL);

-- For t4 (S4 - final provider at 10.0.0.4)
INSERT INTO ps_endpoint_id_ips (id, endpoint, `match`, srv_lookups, match_header)
VALUES ('identify-t4', 'endpoint-t4', '10.0.0.4', 'yes', NULL);

-- Verify the entries
SELECT '=== Updated ps_endpoint_id_ips entries ===' as Info;
SELECT * FROM ps_endpoint_id_ips;

-- Update endpoints to ensure identify_by is set correctly
UPDATE ps_endpoints SET identify_by = 'ip' WHERE id IN ('endpoint-test1', 'endpoint-t3', 'endpoint-t4');

-- Verify endpoint configuration
SELECT '=== Endpoint identify_by configuration ===' as Info;
SELECT id, transport, aors, context, identify_by FROM ps_endpoints;

-- Ensure ps_globals has correct identifier order
UPDATE ps_globals SET endpoint_identifier_order = 'ip,username,anonymous' WHERE id = 'global';

-- Verify global settings
SELECT '=== Global settings ===' as Info;
SELECT id, endpoint_identifier_order FROM ps_globals;

-- Create static contacts for the endpoints (helps with endpoint availability)
DELETE FROM ps_contacts WHERE id IN ('contact-test1', 'contact-t3', 'contact-t4');

INSERT INTO ps_contacts (id, uri, endpoint_name, qualify_frequency, user_agent, expiration_time, via_addr, via_port, call_id)
VALUES 
('contact-test1', 'sip:test1@10.0.0.1:5060', 'endpoint-test1', 30, 'ARA-Router', 9999999999, '10.0.0.1', 5060, 'static-test1'),
('contact-t3', 'sip:t3@10.0.0.3:5060', 'endpoint-t3', 30, 'ARA-Router', 9999999999, '10.0.0.3', 5060, 'static-t3'),
('contact-t4', 'sip:t4@10.0.0.4:5060', 'endpoint-t4', 30, 'ARA-Router', 9999999999, '10.0.0.4', 5060, 'static-t4');

-- Update AORs to reference these contacts
UPDATE ps_aors SET contact = CONCAT('sip:', SUBSTRING_INDEX(id, '-', -1), '@', 
    CASE 
        WHEN id = 'aor-test1' THEN '10.0.0.1'
        WHEN id = 'aor-t3' THEN '10.0.0.3'
        WHEN id = 'aor-t4' THEN '10.0.0.4'
    END, ':5060')
WHERE id IN ('aor-test1', 'aor-t3', 'aor-t4');

-- Final verification
SELECT '=== Final AOR configuration ===' as Info;
SELECT id, contact, qualify_frequency FROM ps_aors;

SELECT '=== Final Contact configuration ===' as Info;
SELECT id, uri, endpoint_name FROM ps_contacts;
