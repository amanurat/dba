-- MySQL Performance Monitoring Queries for Azure
-- Use these queries for daily monitoring and performance analysis

-- 🔍 HEALTH CHECK: Overall Database Health
SELECT 
    'Database Health Check' as section,
    NOW() as check_time;

-- 📊 CONNECTIONS: Current connection status
SELECT 
    'Connection Status' as metric,
    VARIABLE_VALUE as current_value,
    CASE 
        WHEN VARIABLE_NAME = 'Threads_connected' THEN 'Current Connections'
        WHEN VARIABLE_NAME = 'Threads_running' THEN 'Active Threads'
        WHEN VARIABLE_NAME = 'Max_used_connections' THEN 'Peak Connections'
        WHEN VARIABLE_NAME = 'Aborted_connects' THEN 'Failed Connections'
    END as description
FROM INFORMATION_SCHEMA.GLOBAL_STATUS 
WHERE VARIABLE_NAME IN ('Threads_connected', 'Threads_running', 'Max_used_connections', 'Aborted_connects');

-- 🎯 BUFFER POOL: InnoDB Buffer Pool Efficiency
SELECT 
    'InnoDB Buffer Pool Hit Ratio' as metric,
    CONCAT(
        ROUND(
            (1 - (
                (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads') /
                (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests')
            )) * 100, 2
        ), '%'
    ) as hit_ratio,
    'Target: >99%' as target
FROM DUAL;

-- 🐌 SLOW QUERIES: Top 10 slowest queries
SELECT 
    'Top Slow Queries' as section;

SELECT 
    TRUNCATE(DIGEST_TEXT, 100) as query_preview,
    COUNT_STAR as execution_count,
    ROUND(AVG_TIMER_WAIT/1000000000000, 3) as avg_time_seconds,
    ROUND(SUM_TIMER_WAIT/1000000000000, 3) as total_time_seconds,
    SUM_ROWS_EXAMINED as total_rows_examined,
    SUM_ROWS_SENT as total_rows_sent,
    ROUND(SUM_ROWS_EXAMINED/COUNT_STAR, 0) as avg_rows_examined
FROM performance_schema.events_statements_summary_by_digest 
WHERE DIGEST_TEXT IS NOT NULL
ORDER BY AVG_TIMER_WAIT DESC 
LIMIT 10;

-- 📈 QUERY STATS: Queries not using indexes
SELECT 
    'Queries Not Using Indexes' as section;

SELECT 
    TRUNCATE(DIGEST_TEXT, 100) as query_preview,
    COUNT_STAR as execution_count,
    SUM_NO_INDEX_USED as no_index_used_count,
    SUM_NO_GOOD_INDEX_USED as no_good_index_used_count,
    ROUND(AVG_TIMER_WAIT/1000000000000, 3) as avg_time_seconds
FROM performance_schema.events_statements_summary_by_digest 
WHERE SUM_NO_INDEX_USED > 0 OR SUM_NO_GOOD_INDEX_USED > 0
ORDER BY SUM_NO_INDEX_USED DESC
LIMIT 10;

-- 💾 STORAGE: Database and table sizes
SELECT 
    'Database Storage Usage' as section;

SELECT 
    table_schema AS database_name,
    COUNT(table_name) as table_count,
    ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS total_size_mb,
    ROUND(SUM(data_length) / 1024 / 1024, 2) AS data_size_mb,
    ROUND(SUM(index_length) / 1024 / 1024, 2) AS index_size_mb
FROM information_schema.tables 
WHERE table_schema NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys')
GROUP BY table_schema
ORDER BY total_size_mb DESC;

-- 🔧 LARGEST TABLES: Top 10 largest tables
SELECT 
    'Largest Tables' as section;

SELECT 
    table_name,
    table_rows,
    ROUND(((data_length + index_length) / 1024 / 1024), 2) AS total_size_mb,
    ROUND((data_length / 1024 / 1024), 2) AS data_size_mb,
    ROUND((index_length / 1024 / 1024), 2) AS index_size_mb,
    ROUND((index_length / data_length) * 100, 2) AS index_ratio_percent
FROM information_schema.tables 
WHERE table_schema = DATABASE()
    AND table_type = 'BASE TABLE'
ORDER BY (data_length + index_length) DESC
LIMIT 10;

-- 🔍 INDEX USAGE: Index utilization statistics
SELECT 
    'Index Usage Statistics' as section;

SELECT 
    OBJECT_NAME as table_name,
    INDEX_NAME as index_name,
    COUNT_FETCH as select_operations,
    COUNT_INSERT as insert_operations,
    COUNT_UPDATE as update_operations,
    COUNT_DELETE as delete_operations,
    COUNT_FETCH + COUNT_INSERT + COUNT_UPDATE + COUNT_DELETE as total_operations
FROM performance_schema.table_io_waits_summary_by_index_usage 
WHERE OBJECT_SCHEMA = DATABASE()
    AND INDEX_NAME IS NOT NULL
ORDER BY total_operations DESC
LIMIT 15;

-- ❌ UNUSED INDEXES: Potentially unused indexes
SELECT 
    'Potentially Unused Indexes' as section;

SELECT 
    OBJECT_NAME as table_name,
    INDEX_NAME as index_name,
    'No usage detected' as status
FROM performance_schema.table_io_waits_summary_by_index_usage 
WHERE OBJECT_SCHEMA = DATABASE()
    AND INDEX_NAME IS NOT NULL
    AND INDEX_NAME != 'PRIMARY'
    AND COUNT_STAR = 0
ORDER BY OBJECT_NAME, INDEX_NAME;

-- 🔄 ACTIVE PROCESSES: Current running processes
SELECT 
    'Active Database Processes' as section;

SELECT 
    ID as process_id,
    USER as username,
    HOST as client_host,
    DB as database_name,
    COMMAND as command_type,
    TIME as duration_seconds,
    STATE as current_state,
    LEFT(INFO, 100) as query_preview
FROM INFORMATION_SCHEMA.PROCESSLIST 
WHERE COMMAND != 'Sleep'
    AND ID != CONNECTION_ID()
ORDER BY TIME DESC;

-- 📊 MEMORY USAGE: Temporary table statistics
SELECT 
    'Memory Usage Statistics' as section;

SELECT 
    'Temporary Tables' as metric,
    (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Created_tmp_tables') as total_tmp_tables,
    (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Created_tmp_disk_tables') as disk_tmp_tables,
    CONCAT(
        ROUND(
            (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Created_tmp_disk_tables') /
            (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Created_tmp_tables') * 100, 2
        ), '%'
    ) as disk_tmp_ratio,
    'Target: <10%' as target
FROM DUAL;

-- 🚨 PERFORMANCE ALERTS: Key metrics that need attention
SELECT 
    'Performance Alerts' as section;

SELECT 
    alert_type,
    metric_name,
    current_value,
    threshold,
    status
FROM (
    SELECT 
        'CRITICAL' as alert_type,
        'Buffer Pool Hit Ratio' as metric_name,
        CONCAT(
            ROUND(
                (1 - (
                    (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads') /
                    (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests')
                )) * 100, 2
            ), '%'
        ) as current_value,
        '>99%' as threshold,
        CASE 
            WHEN (1 - (
                (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads') /
                (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests')
            )) * 100 < 99 THEN 'ALERT'
            ELSE 'OK'
        END as status
    
    UNION ALL
    
    SELECT 
        'WARNING' as alert_type,
        'Connection Usage' as metric_name,
        CONCAT(
            ROUND(
                (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Threads_connected') /
                (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_VARIABLES WHERE VARIABLE_NAME = 'max_connections') * 100, 2
            ), '%'
        ) as current_value,
        '<80%' as threshold,
        CASE 
            WHEN (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Threads_connected') /
                 (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_VARIABLES WHERE VARIABLE_NAME = 'max_connections') * 100 > 80 THEN 'ALERT'
            ELSE 'OK'
        END as status
    
    UNION ALL
    
    SELECT 
        'WARNING' as alert_type,
        'Disk Temp Table Ratio' as metric_name,
        CONCAT(
            ROUND(
                (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Created_tmp_disk_tables') /
                (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Created_tmp_tables') * 100, 2
            ), '%'
        ) as current_value,
        '<10%' as threshold,
        CASE 
            WHEN (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Created_tmp_disk_tables') /
                 (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Created_tmp_tables') * 100 > 10 THEN 'ALERT'
            ELSE 'OK'
        END as status
) alerts
WHERE status = 'ALERT';

-- 📋 CONFIGURATION: Key MySQL configuration parameters
SELECT 
    'MySQL Configuration Review' as section;

SELECT 
    VARIABLE_NAME as parameter,
    VARIABLE_VALUE as current_value,
    CASE 
        WHEN VARIABLE_NAME = 'innodb_buffer_pool_size' THEN 'Should be 70-80% of RAM'
        WHEN VARIABLE_NAME = 'max_connections' THEN 'Adjust based on workload'
        WHEN VARIABLE_NAME = 'query_cache_size' THEN 'Deprecated in MySQL 8.0'
        WHEN VARIABLE_NAME = 'slow_query_log' THEN 'Should be ON for monitoring'
        WHEN VARIABLE_NAME = 'long_query_time' THEN 'Recommended: 1-2 seconds'
        ELSE 'Review documentation'
    END as recommendation
FROM INFORMATION_SCHEMA.GLOBAL_VARIABLES 
WHERE VARIABLE_NAME IN (
    'innodb_buffer_pool_size',
    'max_connections',
    'query_cache_size',
    'slow_query_log',
    'long_query_time',
    'innodb_log_file_size',
    'key_buffer_size'
)
ORDER BY VARIABLE_NAME;