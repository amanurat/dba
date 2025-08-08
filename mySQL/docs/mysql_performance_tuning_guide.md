# MySQL Performance Tuning and Monitoring Guide for Azure

## Table of Contents
1. [Performance Assessment](#performance-assessment)
2. [Key Performance Metrics](#key-performance-metrics)
3. [Configuration Tuning](#configuration-tuning)
4. [Query Optimization](#query-optimization)
5. [Index Management](#index-management)
6. [Monitoring Setup](#monitoring-setup)
7. [Troubleshooting](#troubleshooting)

## Performance Assessment

### 1. Enable Performance Schema
```sql
-- Check if Performance Schema is enabled
SHOW VARIABLES LIKE 'performance_schema';

-- Enable Performance Schema (requires restart)
SET GLOBAL performance_schema = ON;
```

### 2. Enable Slow Query Log
```sql
-- Enable slow query logging
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 2;
SET GLOBAL log_queries_not_using_indexes = 'ON';

-- Check current settings
SHOW VARIABLES LIKE 'slow_query_log%';
SHOW VARIABLES LIKE 'long_query_time';
```

### 3. Current Performance Overview
```sql
-- Database size and table information
SELECT 
    table_schema AS 'Database',
    ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)'
FROM information_schema.tables 
GROUP BY table_schema;

-- Connection status
SHOW STATUS LIKE 'Connections';
SHOW STATUS LIKE 'Max_used_connections';
SHOW VARIABLES LIKE 'max_connections';
```

## Key Performance Metrics

### 1. Top Slow Queries
```sql
-- Using Performance Schema (MySQL 5.7+)
SELECT 
    DIGEST_TEXT as query,
    COUNT_STAR as exec_count,
    AVG_TIMER_WAIT/1000000000000 as avg_time_sec,
    SUM_TIMER_WAIT/1000000000000 as total_time_sec,
    SUM_ROWS_EXAMINED as rows_examined,
    SUM_ROWS_SENT as rows_sent
FROM performance_schema.events_statements_summary_by_digest 
ORDER BY AVG_TIMER_WAIT DESC 
LIMIT 10;
```

### 2. Buffer Pool Efficiency
```sql
-- InnoDB Buffer Pool Hit Ratio (should be > 99%)
SELECT 
    VARIABLE_NAME,
    VARIABLE_VALUE,
    CASE 
        WHEN VARIABLE_NAME = 'Innodb_buffer_pool_read_requests' THEN 'Read Requests'
        WHEN VARIABLE_NAME = 'Innodb_buffer_pool_reads' THEN 'Physical Reads'
    END as Description
FROM INFORMATION_SCHEMA.GLOBAL_STATUS 
WHERE VARIABLE_NAME IN ('Innodb_buffer_pool_read_requests', 'Innodb_buffer_pool_reads');

-- Calculate hit ratio
SELECT 
    ROUND(
        (1 - (
            (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads') /
            (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests')
        )) * 100, 2
    ) AS buffer_pool_hit_ratio_percent;
```

### 3. Connection Analysis
```sql
-- Current connections
SELECT 
    USER,
    HOST,
    DB,
    COMMAND,
    TIME,
    STATE,
    LEFT(INFO, 50) as QUERY_PREVIEW
FROM INFORMATION_SCHEMA.PROCESSLIST 
WHERE COMMAND != 'Sleep'
ORDER BY TIME DESC;

-- Connection statistics
SHOW STATUS LIKE 'Threads_connected';
SHOW STATUS LIKE 'Threads_running';
SHOW STATUS LIKE 'Aborted_connects';
```

### 4. Table and Index Statistics
```sql
-- Table sizes and row counts
SELECT 
    table_name,
    table_rows,
    ROUND(((data_length + index_length) / 1024 / 1024), 2) AS size_mb,
    ROUND((data_length / 1024 / 1024), 2) AS data_mb,
    ROUND((index_length / 1024 / 1024), 2) AS index_mb
FROM information_schema.tables 
WHERE table_schema = DATABASE()
ORDER BY (data_length + index_length) DESC;

-- Index usage statistics
SELECT 
    OBJECT_SCHEMA,
    OBJECT_NAME,
    INDEX_NAME,
    COUNT_FETCH,
    COUNT_INSERT,
    COUNT_UPDATE,
    COUNT_DELETE
FROM performance_schema.table_io_waits_summary_by_index_usage 
WHERE OBJECT_SCHEMA = DATABASE()
ORDER BY COUNT_FETCH DESC;
```

## Configuration Tuning

### 1. Memory Configuration
```sql
-- Key buffer size (for MyISAM tables)
SET GLOBAL key_buffer_size = 268435456; -- 256MB

-- InnoDB buffer pool size (should be 70-80% of available RAM)
-- This requires restart
-- innodb_buffer_pool_size = 2G

-- Query cache (deprecated in MySQL 8.0)
SET GLOBAL query_cache_size = 67108864; -- 64MB
SET GLOBAL query_cache_type = ON;
```

### 2. Connection Settings
```sql
-- Maximum connections
SET GLOBAL max_connections = 200;

-- Connection timeout
SET GLOBAL wait_timeout = 28800;
SET GLOBAL interactive_timeout = 28800;
```

### 3. InnoDB Settings
```sql
-- InnoDB log file size (requires restart)
-- innodb_log_file_size = 256M

-- InnoDB flush method (requires restart)
-- innodb_flush_method = O_DIRECT

-- InnoDB thread concurrency
SET GLOBAL innodb_thread_concurrency = 0; -- Let InnoDB decide
```

## Query Optimization

### 1. Identify Problematic Queries
```sql
-- Queries not using indexes
SELECT 
    DIGEST_TEXT as query,
    COUNT_STAR as exec_count,
    SUM_NO_INDEX_USED as no_index_used_count,
    SUM_NO_GOOD_INDEX_USED as no_good_index_used_count
FROM performance_schema.events_statements_summary_by_digest 
WHERE SUM_NO_INDEX_USED > 0 OR SUM_NO_GOOD_INDEX_USED > 0
ORDER BY SUM_NO_INDEX_USED DESC;
```

### 2. Query Execution Analysis
```sql
-- Use EXPLAIN to analyze query execution plans
EXPLAIN FORMAT=JSON SELECT * FROM your_table WHERE condition;

-- Use EXPLAIN ANALYZE for actual execution statistics (MySQL 8.0+)
EXPLAIN ANALYZE SELECT * FROM your_table WHERE condition;
```

## Index Management

### 1. Missing Index Analysis
```sql
-- Tables without primary keys
SELECT 
    table_schema,
    table_name
FROM information_schema.tables t
LEFT JOIN information_schema.table_constraints tc
    ON t.table_schema = tc.table_schema 
    AND t.table_name = tc.table_name 
    AND tc.constraint_type = 'PRIMARY KEY'
WHERE t.table_schema NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys')
    AND tc.constraint_name IS NULL;

-- Unused indexes
SELECT 
    OBJECT_SCHEMA,
    OBJECT_NAME,
    INDEX_NAME
FROM performance_schema.table_io_waits_summary_by_index_usage 
WHERE INDEX_NAME IS NOT NULL
    AND COUNT_STAR = 0
    AND OBJECT_SCHEMA = DATABASE()
    AND INDEX_NAME != 'PRIMARY';
```

### 2. Index Optimization
```sql
-- Duplicate indexes detection
SELECT 
    a.table_schema,
    a.table_name,
    a.index_name as index1,
    b.index_name as index2,
    a.column_name
FROM information_schema.statistics a
JOIN information_schema.statistics b 
    ON a.table_schema = b.table_schema
    AND a.table_name = b.table_name
    AND a.column_name = b.column_name
    AND a.index_name != b.index_name
WHERE a.table_schema = DATABASE()
ORDER BY a.table_name, a.column_name;
```

## Monitoring Setup

### 1. Azure MySQL Monitoring
```sql
-- Enable Azure monitoring features
-- Configure in Azure Portal:
-- - Enable Query Performance Insight
-- - Set up Performance Recommendations
-- - Configure Diagnostic Settings
```

### 2. Custom Monitoring Queries
```sql
-- Daily health check query
SELECT 
    'Buffer Pool Hit Ratio' as metric,
    CONCAT(
        ROUND(
            (1 - (
                (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads') /
                (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests')
            )) * 100, 2
        ), '%'
    ) as value
UNION ALL
SELECT 
    'Current Connections',
    (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Threads_connected')
UNION ALL
SELECT 
    'Slow Queries',
    (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Slow_queries');
```

## Troubleshooting

### 1. High CPU Usage
```sql
-- Find CPU-intensive queries
SELECT 
    DIGEST_TEXT as query,
    COUNT_STAR as exec_count,
    AVG_TIMER_WAIT/1000000000000 as avg_time_sec,
    SUM_TIMER_WAIT/1000000000000 as total_time_sec
FROM performance_schema.events_statements_summary_by_digest 
ORDER BY SUM_TIMER_WAIT DESC 
LIMIT 10;
```

### 2. Lock Contention
```sql
-- Check for metadata locks
SELECT 
    OBJECT_TYPE,
    OBJECT_SCHEMA,
    OBJECT_NAME,
    LOCK_TYPE,
    LOCK_DURATION,
    LOCK_STATUS
FROM performance_schema.metadata_locks
WHERE OBJECT_SCHEMA = DATABASE();
```

### 3. Memory Issues
```sql
-- Check memory usage
SHOW STATUS LIKE 'Created_tmp_disk_tables';
SHOW STATUS LIKE 'Created_tmp_tables';

-- Temporary table ratio (should be < 10%)
SELECT 
    ROUND(
        (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Created_tmp_disk_tables') /
        (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Created_tmp_tables') * 100, 2
    ) as tmp_disk_table_ratio_percent;
```

## Performance Targets

### Success Criteria
- **Buffer Pool Hit Ratio**: > 99%
- **Query Response Time**: < 2 seconds for 95% of queries
- **Connection Efficiency**: < 80% of max_connections used
- **Slow Query Count**: < 1% of total queries
- **Index Hit Ratio**: > 95%
- **Temporary Disk Table Ratio**: < 10%

### Alert Thresholds
- **Critical**: Buffer pool hit ratio < 95%
- **Warning**: Average query time > 5 seconds
- **Critical**: Connections > 90% of max_connections
- **Warning**: Slow queries > 100 per hour
- **Critical**: Disk space > 85% full