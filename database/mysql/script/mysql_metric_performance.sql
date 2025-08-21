-- 1) Workload Characterization
/*
# Document current environment
echo "=== Environment Assessment ===" > baseline_prep.txt
echo "Date: $(date)" >> baseline_prep.txt
echo "Environment: $ENVIRONMENT" >> baseline_prep.txt
echo "Database Versions:" >> baseline_prep.txt

# MySQL version
mysql -e "SELECT VERSION();" >> baseline_prep.txt

# PostgreSQL version (if applicable)
psql -c "SELECT version();" >> baseline_prep.txt

# SQL Server version (if applicable)
sqlcmd -Q "SELECT @@VERSION;" >> baseline_prep.txt
*/


-- 2) Workload Characterization
-- Identify peak usage patterns
-- Run this across all database types during different time periods

-- MySQL workload analysis
SELECT
    DATE_FORMAT(NOW(), '%Y-%m-%d %H:00:00') as hour_period,
    COUNT(*) as connection_count,
    AVG(TIME_TO_SEC(TIMEDIFF(NOW(), TIME))) as avg_session_duration_sec
FROM information_schema.PROCESSLIST
WHERE COMMAND != 'Sleep'
GROUP BY hour_period
ORDER BY hour_period;


-- 3) Configuration Documentation
/*
# Create configuration backup before baseline
mkdir -p baseline_configs/$(date +%Y%m%d)

# MySQL configuration
mysqldump --no-data --routines your_database > baseline_configs/$(date +%Y%m%d)/mysql_schema.sql
mysql -e "SHOW VARIABLES;" > baseline_configs/$(date +%Y%m%d)/mysql_config.txt

# PostgreSQL configuration (if applicable)
pg_dump --schema-only your_database > baseline_configs/$(date +%Y%m%d)/postgresql_schema.sql
psql -c "SHOW ALL;" > baseline_configs/$(date +%Y%m%d)/postgresql_config.txt

# Document Azure configuration
az mysql server configuration list --resource-group $RG --server-name $MYSQL_SERVER > baseline_configs/$(date +%Y%m%d)/azure_mysql_config.json
az postgres server configuration list --resource-group $RG --server-name $PG_SERVER > baseline_configs/$(date +%Y%m%d)/azure_pg_config.json
 */


-- ### MySQL Baseline ####
-- 1. Performance Metrics Collection
-- Create baseline monitoring view
CREATE OR REPLACE VIEW baseline_mysql_performance AS
SELECT
    NOW() as sample_time,
    -- Connection metrics
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Threads_connected') as active_connections,
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Threads_running') as running_connections,
    
    -- Database statistics
    (SELECT SUM(DATA_LENGTH + INDEX_LENGTH) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()) as database_size_bytes,
    
    -- Transaction statistics
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Com_commit') as total_commits,
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Com_rollback') as total_rollbacks,
    
    -- InnoDB I/O statistics
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads') as buffer_pool_reads,
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests') as buffer_pool_read_requests,
    
    -- Cache hit ratio calculation
    CASE
        WHEN (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests') > 0
        THEN (
            100.0 * (1 - (
                (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads') /
                (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests')
            ))
        )
        ELSE 0
    END as cache_hit_ratio,
    
    -- Query cache statistics (if enabled)
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Qcache_hits') as query_cache_hits,
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Qcache_inserts') as query_cache_inserts,
    
    -- Additional MySQL-specific metrics
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Slow_queries') as slow_queries,
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Aborted_connects') as aborted_connects,
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Table_locks_waited') as table_locks_waited,
    
    -- Key buffer hit ratio (for MyISAM tables)
    CASE
        WHEN (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Key_reads') +
             (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Key_read_requests') > 0
        THEN (
            100.0 * (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Key_read_requests') /
            ((SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Key_reads') +
             (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Key_read_requests'))
        )
        ELSE 0
    END as key_buffer_hit_ratio;

-- Baseline data collection table
CREATE TABLE IF NOT EXISTS baseline_mysql_metrics (
    sample_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    active_connections INT,
    running_connections INT,
    database_size_bytes BIGINT,
    total_commits BIGINT,
    total_rollbacks BIGINT,
    buffer_pool_reads BIGINT,
    buffer_pool_read_requests BIGINT,
    cache_hit_ratio DECIMAL(5,2),
    query_cache_hits BIGINT,
    query_cache_inserts BIGINT,
    slow_queries BIGINT,
    aborted_connects BIGINT,
    table_locks_waited BIGINT,
    key_buffer_hit_ratio DECIMAL(5,2),
    INDEX idx_sample_time (sample_time)
);

-- Insert baseline sample (run every 5 minutes via cron)
-- INSERT INTO baseline_mysql_metrics 
-- SELECT * FROM baseline_mysql_performance;

-- Alternative: Use EVENT scheduler to automatically collect metrics
DELIMITER $$

CREATE EVENT IF NOT EXISTS collect_baseline_metrics
ON SCHEDULE EVERY 5 MINUTE
STARTS NOW()
DO
BEGIN
    INSERT INTO baseline_mysql_metrics 
    SELECT * FROM baseline_mysql_performance;
    
    -- Clean up old data (keep 90 days)
    DELETE FROM baseline_mysql_metrics 
    WHERE sample_time < DATE_SUB(NOW(), INTERVAL 90 DAY);
END$$

DELIMITER ;

-- Enable the event scheduler if not already enabled
-- SET GLOBAL event_scheduler = ON;

-- 2. Query Performance Baseline
-- Top queries baseline (using performance_schema)
CREATE TABLE IF NOT EXISTS baseline_mysql_queries AS
SELECT
    NOW() as baseline_date,
    DIGEST_TEXT as query_text,
    COUNT_STAR as calls,
    SUM_TIMER_WAIT / 1000000000000 as total_exec_time_sec,
    AVG_TIMER_WAIT / 1000000000000 as mean_exec_time_sec,
    SUM_ROWS_EXAMINED as total_rows_examined,
    SUM_ROWS_SENT as total_rows_returned,
    SUM_NO_INDEX_USED as queries_without_index,
    SUM_NO_GOOD_INDEX_USED as queries_with_bad_index,
    FIRST_SEEN,
    LAST_SEEN
FROM performance_schema.events_statements_summary_by_digest
WHERE COUNT_STAR > 100  -- Only frequently executed queries
    AND DIGEST_TEXT IS NOT NULL
    AND DIGEST_TEXT NOT LIKE '%performance_schema%'
    AND DIGEST_TEXT NOT LIKE '%information_schema%'
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 50;

-- Reset Performance Schema statistics after baseline period
-- CALL sys.ps_truncate_all_tables(FALSE);

-- 3. System Resource Baseline
/*
#!/bin/bash
# MySQL system resource baseline collection
# Run every 5 minutes during baseline period

BASELINE_DIR="/var/log/mysql/baseline"
mkdir -p $BASELINE_DIR

# CPU and Memory
echo "$(date),$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1),$(free | grep Mem | awk '{printf "%.2f", $3/$2 * 100.0}')" >> $BASELINE_DIR/system_metrics.csv

# Disk I/O
iostat -x 1 1 | grep -E "(Device|mysql)" >> $BASELINE_DIR/disk_io.log

# Network
ss -tuln | grep :3306 | wc -l >> $BASELINE_DIR/network_connections.log

# MySQL specific metrics
mysql -e "
SELECT 
    VARIABLE_NAME, 
    VARIABLE_VALUE 
FROM performance_schema.global_status 
WHERE VARIABLE_NAME IN (
    'Innodb_buffer_pool_pages_dirty',
    'Innodb_buffer_pool_pages_free',
    'Innodb_buffer_pool_pages_total',
    'Innodb_rows_read',
    'Innodb_rows_inserted',
    'Innodb_rows_updated',
    'Innodb_rows_deleted'
);" >> $BASELINE_DIR/innodb_metrics.log
*/

-- ### Baseline Analysis and Reporting ####
-- 1. MySQL baseline analysis
SELECT 
    'Baseline Analysis Report' as report_title,
    DATE_SUB(NOW(), INTERVAL 30 DAY) as analysis_period_start,
    NOW() as analysis_period_end;

WITH baseline_stats AS (
    SELECT
        'active_connections' as metric,
        AVG(active_connections) as avg_value,
        MIN(active_connections) as min_value,
        MAX(active_connections) as max_value,
        STDDEV(active_connections) as std_dev,
        (SELECT active_connections FROM baseline_mysql_metrics 
         WHERE sample_time >= DATE_SUB(NOW(), INTERVAL 30 DAY) 
         ORDER BY active_connections DESC 
         LIMIT 1 OFFSET FLOOR(0.95 * (
             SELECT COUNT(*) FROM baseline_mysql_metrics 
             WHERE sample_time >= DATE_SUB(NOW(), INTERVAL 30 DAY)
         ))) as p95_value
    FROM baseline_mysql_metrics
    WHERE sample_time >= DATE_SUB(NOW(), INTERVAL 30 DAY)

    UNION ALL

    SELECT
        'cache_hit_ratio',
        AVG(cache_hit_ratio),
        MIN(cache_hit_ratio),
        MAX(cache_hit_ratio),
        STDDEV(cache_hit_ratio),
        (SELECT cache_hit_ratio FROM baseline_mysql_metrics 
         WHERE sample_time >= DATE_SUB(NOW(), INTERVAL 30 DAY)
           AND cache_hit_ratio IS NOT NULL
         ORDER BY cache_hit_ratio DESC 
         LIMIT 1 OFFSET FLOOR(0.95 * (
             SELECT COUNT(*) FROM baseline_mysql_metrics 
             WHERE sample_time >= DATE_SUB(NOW(), INTERVAL 30 DAY)
               AND cache_hit_ratio IS NOT NULL
         )))
    FROM baseline_mysql_metrics
    WHERE sample_time >= DATE_SUB(NOW(), INTERVAL 30 DAY)
      AND cache_hit_ratio IS NOT NULL

    UNION ALL

    SELECT
        'slow_queries',
        AVG(slow_queries),
        MIN(slow_queries),
        MAX(slow_queries),
        STDDEV(slow_queries),
        (SELECT slow_queries FROM baseline_mysql_metrics 
         WHERE sample_time >= DATE_SUB(NOW(), INTERVAL 30 DAY) 
         ORDER BY slow_queries DESC 
         LIMIT 1 OFFSET FLOOR(0.95 * (
             SELECT COUNT(*) FROM baseline_mysql_metrics 
             WHERE sample_time >= DATE_SUB(NOW(), INTERVAL 30 DAY)
         )))
    FROM baseline_mysql_metrics
    WHERE sample_time >= DATE_SUB(NOW(), INTERVAL 30 DAY)

    UNION ALL

    SELECT
        'running_connections',
        AVG(running_connections),
        MIN(running_connections),
        MAX(running_connections),
        STDDEV(running_connections),
        (SELECT running_connections FROM baseline_mysql_metrics 
         WHERE sample_time >= DATE_SUB(NOW(), INTERVAL 30 DAY) 
         ORDER BY running_connections DESC 
         LIMIT 1 OFFSET FLOOR(0.95 * (
             SELECT COUNT(*) FROM baseline_mysql_metrics 
             WHERE sample_time >= DATE_SUB(NOW(), INTERVAL 30 DAY)
         )))
    FROM baseline_mysql_metrics
    WHERE sample_time >= DATE_SUB(NOW(), INTERVAL 30 DAY)
)
SELECT
    metric,
    ROUND(avg_value, 2) as average,
    ROUND(min_value, 2) as minimum,
    ROUND(max_value, 2) as maximum,
    ROUND(std_dev, 2) as std_deviation,
    ROUND(p95_value, 2) as percentile_95,
    ROUND(avg_value + (2 * std_dev), 2) as upper_threshold,
    ROUND(GREATEST(0, avg_value - (2 * std_dev)), 2) as lower_threshold,
    CASE 
        WHEN metric = 'cache_hit_ratio' AND avg_value < 95 THEN 'WARNING: Low cache hit ratio'
        WHEN metric = 'active_connections' AND avg_value > 80 THEN 'WARNING: High connection usage'
        WHEN metric = 'slow_queries' AND (max_value - min_value) > 100 THEN 'WARNING: Increasing slow queries'
        ELSE 'OK'
    END as status_alert
FROM baseline_stats
ORDER BY 
    CASE metric 
        WHEN 'active_connections' THEN 1
        WHEN 'running_connections' THEN 2
        WHEN 'cache_hit_ratio' THEN 3
        WHEN 'slow_queries' THEN 4
        ELSE 5
    END;

-- 2. Performance Trend Analysis
SELECT 
    'Performance Trend Analysis - Last 7 Days' as analysis_title;

SELECT
    DATE_FORMAT(sample_time, '%Y-%m-%d %H:00:00') as hour_period,
    AVG(active_connections) as avg_connections,
    AVG(running_connections) as avg_running,
    AVG(cache_hit_ratio) as avg_cache_hit_ratio,
    AVG(slow_queries) as avg_slow_queries,
    COUNT(*) as sample_count
FROM baseline_mysql_metrics
WHERE sample_time >= DATE_SUB(NOW(), INTERVAL 7 DAY)
GROUP BY DATE_FORMAT(sample_time, '%Y-%m-%d %H:00:00')
ORDER BY hour_period DESC
LIMIT 168; -- Last 7 days hourly

-- 3. Query Performance Analysis
SELECT 
    'Top Resource-Consuming Queries' as query_analysis_title;

SELECT
    LEFT(query_text, 100) as query_preview,
    calls,
    ROUND(total_exec_time_sec, 3) as total_time_sec,
    ROUND(mean_exec_time_sec, 3) as avg_time_sec,
    total_rows_examined,
    total_rows_returned,
    queries_without_index,
    queries_with_bad_index,
    CASE 
        WHEN mean_exec_time_sec > 1 THEN 'CRITICAL: Very slow query'
        WHEN mean_exec_time_sec > 0.1 THEN 'WARNING: Slow query'
        WHEN queries_without_index > 0 THEN 'WARNING: Missing index'
        ELSE 'OK'
    END as performance_status
FROM baseline_mysql_queries
WHERE baseline_date >= DATE_SUB(NOW(), INTERVAL 30 DAY)
ORDER BY total_exec_time_sec DESC
LIMIT 20;

-- 4. Connection Analysis
SELECT 
    'Connection Pattern Analysis' as connection_analysis_title;

SELECT
    HOUR(sample_time) as hour_of_day,
    AVG(active_connections) as avg_active_connections,
    MAX(active_connections) as peak_connections,
    AVG(running_connections) as avg_running_connections,
    MAX(running_connections) as peak_running_connections,
    COUNT(*) as samples
FROM baseline_mysql_metrics
WHERE sample_time >= DATE_SUB(NOW(), INTERVAL 30 DAY)
GROUP BY HOUR(sample_time)
ORDER BY hour_of_day;

-- 5. Database Growth Analysis
SELECT 
    'Database Growth Analysis' as growth_analysis_title;

SELECT
    DATE(sample_time) as date,
    MIN(database_size_bytes / 1024 / 1024 / 1024) as min_size_gb,
    MAX(database_size_bytes / 1024 / 1024 / 1024) as max_size_gb,
    (MAX(database_size_bytes) - MIN(database_size_bytes)) / 1024 / 1024 as daily_growth_mb
FROM baseline_mysql_metrics
WHERE sample_time >= DATE_SUB(NOW(), INTERVAL 30 DAY)
    AND database_size_bytes IS NOT NULL
GROUP BY DATE(sample_time)
ORDER BY date DESC
LIMIT 30;

-- ### Threshold Calculation ####
-- Calculate dynamic thresholds based on baseline data

DELIMITER $$

CREATE FUNCTION IF NOT EXISTS calculate_mysql_thresholds(
    metric_name VARCHAR(50), 
    baseline_days INT DEFAULT 30
)
RETURNS JSON
READS SQL DATA
DETERMINISTIC
BEGIN
    DECLARE result JSON;
    DECLARE avg_val, std_dev, p95_val DECIMAL(10,2);
    
    CASE metric_name
        WHEN 'active_connections' THEN
            SELECT 
                AVG(active_connections),
                STDDEV(active_connections),
                (SELECT active_connections 
                 FROM baseline_mysql_metrics 
                 WHERE sample_time >= DATE_SUB(NOW(), INTERVAL baseline_days DAY) 
                 ORDER BY active_connections DESC 
                 LIMIT 1 OFFSET FLOOR(0.95 * (
                     SELECT COUNT(*) FROM baseline_mysql_metrics 
                     WHERE sample_time >= DATE_SUB(NOW(), INTERVAL baseline_days DAY)
                 )))
            INTO avg_val, std_dev, p95_val
            FROM baseline_mysql_metrics
            WHERE sample_time >= DATE_SUB(NOW(), INTERVAL baseline_days DAY);
            
        WHEN 'cache_hit_ratio' THEN
            SELECT 
                AVG(cache_hit_ratio),
                STDDEV(cache_hit_ratio),
                (SELECT cache_hit_ratio 
                 FROM baseline_mysql_metrics 
                 WHERE sample_time >= DATE_SUB(NOW(), INTERVAL baseline_days DAY)
                   AND cache_hit_ratio IS NOT NULL
                 ORDER BY cache_hit_ratio DESC 
                 LIMIT 1 OFFSET FLOOR(0.95 * (
                     SELECT COUNT(*) FROM baseline_mysql_metrics 
                     WHERE sample_time >= DATE_SUB(NOW(), INTERVAL baseline_days DAY)
                       AND cache_hit_ratio IS NOT NULL
                 )))
            INTO avg_val, std_dev, p95_val
            FROM baseline_mysql_metrics
            WHERE sample_time >= DATE_SUB(NOW(), INTERVAL baseline_days DAY)
              AND cache_hit_ratio IS NOT NULL;
              
        WHEN 'slow_queries' THEN
            SELECT 
                AVG(slow_queries),
                STDDEV(slow_queries),
                (SELECT slow_queries 
                 FROM baseline_mysql_metrics 
                 WHERE sample_time >= DATE_SUB(NOW(), INTERVAL baseline_days DAY) 
                 ORDER BY slow_queries DESC 
                 LIMIT 1 OFFSET FLOOR(0.95 * (
                     SELECT COUNT(*) FROM baseline_mysql_metrics 
                     WHERE sample_time >= DATE_SUB(NOW(), INTERVAL baseline_days DAY)
                 )))
            INTO avg_val, std_dev, p95_val
            FROM baseline_mysql_metrics
            WHERE sample_time >= DATE_SUB(NOW(), INTERVAL baseline_days DAY);
            
        ELSE
            SET avg_val = 0, std_dev = 0, p95_val = 0;
    END CASE;
    
    SET result = JSON_OBJECT(
        'metric', metric_name,
        'average', ROUND(avg_val, 2),
        'std_deviation', ROUND(std_dev, 2),
        'warning_threshold', ROUND(avg_val + (1.5 * std_dev), 2),
        'critical_threshold', ROUND(avg_val + (2.5 * std_dev), 2),
        'p95_threshold', ROUND(p95_val, 2)
    );
    
    RETURN result;
END$$

DELIMITER ;

-- Example usage
SELECT calculate_mysql_thresholds('active_connections', 30) as connection_thresholds;
SELECT calculate_mysql_thresholds('cache_hit_ratio', 30) as cache_thresholds;
SELECT calculate_mysql_thresholds('slow_queries', 30) as slow_query_thresholds;

-- 6. Alerting Query Examples
-- Queries to identify when metrics exceed baseline thresholds

-- Current metrics vs baseline thresholds
SELECT 
    'Current Status vs Baseline Thresholds' as alert_check_title,
    NOW() as check_time;

SELECT
    metric_name,
    current_value,
    baseline_avg,
    threshold_warning,
    threshold_critical,
    CASE
        WHEN current_value > threshold_critical THEN 'CRITICAL'
        WHEN current_value > threshold_warning THEN 'WARNING'
        ELSE 'OK'
    END as status
FROM (
    SELECT 
        'active_connections' as metric_name,
        (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Threads_connected') as current_value,
        (SELECT AVG(active_connections) FROM baseline_mysql_metrics WHERE sample_time >= DATE_SUB(NOW(), INTERVAL 30 DAY)) as baseline_avg,
        (SELECT AVG(active_connections) + (1.5 * STDDEV(active_connections)) FROM baseline_mysql_metrics WHERE sample_time >= DATE_SUB(NOW(), INTERVAL 30 DAY)) as threshold_warning,
        (SELECT AVG(active_connections) + (2.5 * STDDEV(active_connections)) FROM baseline_mysql_metrics WHERE sample_time >= DATE_SUB(NOW(), INTERVAL 30 DAY)) as threshold_critical
        
    UNION ALL
    
    SELECT 
        'cache_hit_ratio',
        (SELECT 100.0 * (1 - (
            (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads') /
            (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests')
        ))),
        (SELECT AVG(cache_hit_ratio) FROM baseline_mysql_metrics WHERE sample_time >= DATE_SUB(NOW(), INTERVAL 30 DAY) AND cache_hit_ratio IS NOT NULL),
        (SELECT AVG(cache_hit_ratio) - (1.5 * STDDEV(cache_hit_ratio)) FROM baseline_mysql_metrics WHERE sample_time >= DATE_SUB(NOW(), INTERVAL 30 DAY) AND cache_hit_ratio IS NOT NULL),
        (SELECT AVG(cache_hit_ratio) - (2.5 * STDDEV(cache_hit_ratio)) FROM baseline_mysql_metrics WHERE sample_time >= DATE_SUB(NOW(), INTERVAL 30 DAY) AND cache_hit_ratio IS NOT NULL)
) current_vs_baseline;

-- Summary Report
SELECT 
    '=== MySQL Baseline Performance Analysis Summary ===' as summary_title,
    NOW() as report_generated,
    (SELECT COUNT(*) FROM baseline_mysql_metrics WHERE sample_time >= DATE_SUB(NOW(), INTERVAL 30 DAY)) as total_samples_30days,
    (SELECT MIN(sample_time) FROM baseline_mysql_metrics) as oldest_sample,
    (SELECT MAX(sample_time) FROM baseline_mysql_metrics) as newest_sample,
    'Baseline analysis complete - Review thresholds and alerts above' as status;
