# SQL Server Performance Tuning and Monitoring Guide for Azure

## Table of Contents
1. [Performance Assessment](#performance-assessment)
2. [Query Store Configuration](#query-store-configuration)
3. [Key Performance Metrics](#key-performance-metrics)
4. [Index Management](#index-management)
5. [Query Optimization](#query-optimization)
6. [Azure SQL Database Specific Features](#azure-sql-database-specific-features)
7. [Monitoring and Alerting](#monitoring-and-alerting)
8. [Troubleshooting](#troubleshooting)

## Performance Assessment

### 1. Enable Query Store
```sql
-- Enable Query Store for performance monitoring
ALTER DATABASE [YourDatabase] SET QUERY_STORE = ON;

-- Configure Query Store settings
ALTER DATABASE [YourDatabase] SET QUERY_STORE (
    OPERATION_MODE = READ_WRITE,
    CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30),
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    INTERVAL_LENGTH_MINUTES = 60,
    MAX_STORAGE_SIZE_MB = 1000,
    QUERY_CAPTURE_MODE = AUTO,
    SIZE_BASED_CLEANUP_MODE = AUTO
);

-- Check Query Store status
SELECT 
    actual_state_desc,
    readonly_reason,
    current_storage_size_mb,
    max_storage_size_mb
FROM sys.database_query_store_options;
```

### 2. Database Health Overview
```sql
-- Database file sizes and growth
SELECT 
    DB_NAME() as database_name,
    name as logical_name,
    physical_name,
    size * 8 / 1024 as size_mb,
    max_size * 8 / 1024 as max_size_mb,
    growth,
    is_percent_growth
FROM sys.database_files;

-- Current database connections
SELECT 
    DB_NAME(database_id) as database_name,
    COUNT(*) as connection_count
FROM sys.dm_exec_sessions 
WHERE database_id > 0
GROUP BY database_id;
```

## Query Store Configuration

### 1. Query Store Analysis
```sql
-- Top resource consuming queries
SELECT TOP 10
    qsq.query_id,
    qsqt.query_sql_text,
    qsrs.count_executions,
    qsrs.avg_duration / 1000.0 as avg_duration_ms,
    qsrs.avg_cpu_time / 1000.0 as avg_cpu_time_ms,
    qsrs.avg_logical_io_reads,
    qsrs.avg_physical_io_reads,
    qsrs.last_execution_time
FROM sys.query_store_query qsq
JOIN sys.query_store_query_text qsqt ON qsq.query_text_id = qsqt.query_text_id
JOIN sys.query_store_runtime_stats qsrs ON qsq.query_id = qsrs.query_id
JOIN sys.query_store_runtime_stats_interval qsrsi ON qsrs.runtime_stats_interval_id = qsrsi.runtime_stats_interval_id
WHERE qsrsi.start_time >= DATEADD(day, -7, GETUTCDATE())
ORDER BY qsrs.avg_duration DESC;

-- Query performance regression detection
SELECT 
    qsq.query_id,
    qsqt.query_sql_text,
    qsrs_recent.avg_duration / 1000.0 as recent_avg_duration_ms,
    qsrs_history.avg_duration / 1000.0 as historical_avg_duration_ms,
    ((qsrs_recent.avg_duration - qsrs_history.avg_duration) * 100.0 / qsrs_history.avg_duration) as performance_change_percent
FROM sys.query_store_query qsq
JOIN sys.query_store_query_text qsqt ON qsq.query_text_id = qsqt.query_text_id
JOIN sys.query_store_runtime_stats qsrs_recent ON qsq.query_id = qsrs_recent.query_id
JOIN sys.query_store_runtime_stats_interval qsrsi_recent ON qsrs_recent.runtime_stats_interval_id = qsrsi_recent.runtime_stats_interval_id
JOIN sys.query_store_runtime_stats qsrs_history ON qsq.query_id = qsrs_history.query_id
JOIN sys.query_store_runtime_stats_interval qsrsi_history ON qsrs_history.runtime_stats_interval_id = qsrsi_history.runtime_stats_interval_id
WHERE qsrsi_recent.start_time >= DATEADD(day, -1, GETUTCDATE())
    AND qsrsi_history.start_time BETWEEN DATEADD(day, -8, GETUTCDATE()) AND DATEADD(day, -2, GETUTCDATE())
    AND qsrs_recent.avg_duration > qsrs_history.avg_duration * 1.5
ORDER BY performance_change_percent DESC;
```

## Key Performance Metrics

### 1. Wait Statistics Analysis
```sql
-- Current wait statistics
SELECT TOP 20
    wait_type,
    wait_time_ms,
    signal_wait_time_ms,
    wait_time_ms - signal_wait_time_ms as resource_wait_time_ms,
    waiting_tasks_count,
    wait_time_ms / waiting_tasks_count as avg_wait_time_ms,
    (wait_time_ms * 100.0) / SUM(wait_time_ms) OVER() as wait_percentage
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN (
    'CLR_SEMAPHORE', 'LAZYWRITER_SLEEP', 'RESOURCE_QUEUE', 'SLEEP_TASK',
    'SLEEP_SYSTEMTASK', 'SQLTRACE_BUFFER_FLUSH', 'WAITFOR', 'LOGMGR_QUEUE',
    'CHECKPOINT_QUEUE', 'REQUEST_FOR_DEADLOCK_SEARCH', 'XE_TIMER_EVENT',
    'BROKER_TO_FLUSH', 'BROKER_TASK_STOP', 'CLR_MANUAL_EVENT', 'CLR_AUTO_EVENT',
    'DISPATCHER_QUEUE_SEMAPHORE', 'FT_IFTS_SCHEDULER_IDLE_WAIT',
    'XE_DISPATCHER_WAIT', 'XE_DISPATCHER_JOIN'
)
AND waiting_tasks_count > 0
ORDER BY wait_time_ms DESC;

-- Reset wait statistics (use with caution)
-- DBCC SQLPERF('sys.dm_os_wait_stats', CLEAR);
```

### 2. Performance Counters
```sql
-- Key performance counters
SELECT 
    counter_name,
    instance_name,
    cntr_value,
    cntr_type
FROM sys.dm_os_performance_counters
WHERE object_name LIKE '%SQL Statistics%'
    OR object_name LIKE '%Buffer Manager%'
    OR object_name LIKE '%Memory Manager%'
ORDER BY object_name, counter_name;

-- Buffer cache hit ratio
SELECT 
    (a.cntr_value * 1.0 / b.cntr_value) * 100.0 as buffer_cache_hit_ratio
FROM sys.dm_os_performance_counters a
JOIN sys.dm_os_performance_counters b ON a.object_name = b.object_name
WHERE a.counter_name = 'Buffer cache hit ratio'
    AND b.counter_name = 'Buffer cache hit ratio base';
```

### 3. Resource Usage
```sql
-- CPU usage by database
SELECT 
    DB_NAME(database_id) as database_name,
    SUM(total_worker_time) as total_cpu_time_ms,
    SUM(execution_count) as total_executions,
    SUM(total_worker_time) / SUM(execution_count) as avg_cpu_per_execution_ms
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE database_id IS NOT NULL
GROUP BY database_id
ORDER BY total_cpu_time_ms DESC;

-- Memory usage
SELECT 
    type,
    SUM(pages_kb) as total_pages_kb,
    SUM(pages_kb) / 1024 as total_mb
FROM sys.dm_os_memory_clerks
GROUP BY type
ORDER BY total_pages_kb DESC;
```

## Index Management

### 1. Missing Index Analysis
```sql
-- Missing index suggestions
SELECT 
    migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans) as improvement_measure,
    'CREATE INDEX [IX_' + OBJECT_NAME(mid.object_id) + '_' + REPLACE(REPLACE(REPLACE(ISNULL(mid.equality_columns,''),', ','_'),'[',''),']','') + 
    CASE WHEN mid.inequality_columns IS NOT NULL THEN '_' + REPLACE(REPLACE(REPLACE(mid.inequality_columns,', ','_'),'[',''),']','') ELSE '' END + ']' +
    ' ON ' + mid.statement + ' (' + ISNULL(mid.equality_columns,'') +
    CASE WHEN mid.equality_columns IS NOT NULL AND mid.inequality_columns IS NOT NULL THEN ',' ELSE '' END +
    ISNULL(mid.inequality_columns, '') + ')' +
    ISNULL(' INCLUDE (' + mid.included_columns + ')', '') as create_index_statement,
    migs.user_seeks,
    migs.user_scans,
    migs.avg_total_user_cost,
    migs.avg_user_impact
FROM sys.dm_db_missing_index_groups mig
JOIN sys.dm_db_missing_index_group_stats migs ON migs.group_handle = mig.index_group_handle
JOIN sys.dm_db_missing_index_details mid ON mig.index_handle = mid.index_handle
WHERE migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans) > 10
ORDER BY improvement_measure DESC;
```

### 2. Index Usage Statistics
```sql
-- Index usage statistics
SELECT 
    OBJECT_NAME(ius.object_id) as table_name,
    i.name as index_name,
    i.type_desc as index_type,
    ius.user_seeks,
    ius.user_scans,
    ius.user_lookups,
    ius.user_updates,
    ius.user_seeks + ius.user_scans + ius.user_lookups as total_reads,
    ius.last_user_seek,
    ius.last_user_scan,
    ius.last_user_lookup,
    ius.last_user_update
FROM sys.dm_db_index_usage_stats ius
JOIN sys.indexes i ON ius.object_id = i.object_id AND ius.index_id = i.index_id
WHERE ius.database_id = DB_ID()
    AND OBJECT_NAME(ius.object_id) NOT LIKE 'sys%'
ORDER BY total_reads DESC;

-- Unused indexes
SELECT 
    OBJECT_NAME(i.object_id) as table_name,
    i.name as index_name,
    i.type_desc as index_type,
    i.is_disabled,
    i.is_hypothetical
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats ius ON i.object_id = ius.object_id AND i.index_id = ius.index_id AND ius.database_id = DB_ID()
WHERE OBJECT_NAME(i.object_id) NOT LIKE 'sys%'
    AND i.index_id > 0
    AND (ius.user_seeks + ius.user_scans + ius.user_lookups) IS NULL
ORDER BY OBJECT_NAME(i.object_id), i.name;
```

### 3. Index Fragmentation
```sql
-- Index fragmentation analysis
SELECT 
    OBJECT_NAME(ips.object_id) as table_name,
    i.name as index_name,
    ips.index_type_desc,
    ips.avg_fragmentation_in_percent,
    ips.page_count,
    CASE 
        WHEN ips.avg_fragmentation_in_percent > 30 THEN 'REBUILD'
        WHEN ips.avg_fragmentation_in_percent > 10 THEN 'REORGANIZE'
        ELSE 'NO ACTION'
    END as recommended_action
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.avg_fragmentation_in_percent > 10
    AND ips.page_count > 100
ORDER BY ips.avg_fragmentation_in_percent DESC;
```

## Query Optimization

### 1. Expensive Queries Analysis
```sql
-- Top CPU consuming queries
SELECT TOP 20
    qs.sql_handle,
    qs.execution_count,
    qs.total_worker_time as total_cpu_time,
    qs.total_worker_time / qs.execution_count as avg_cpu_time,
    qs.total_elapsed_time,
    qs.total_elapsed_time / qs.execution_count as avg_elapsed_time,
    qs.total_logical_reads,
    qs.total_logical_reads / qs.execution_count as avg_logical_reads,
    qs.creation_time,
    qs.last_execution_time,
    SUBSTRING(st.text, (qs.statement_start_offset/2)+1, 
        ((CASE qs.statement_end_offset
            WHEN -1 THEN DATALENGTH(st.text)
            ELSE qs.statement_end_offset
        END - qs.statement_start_offset)/2) + 1) as statement_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
ORDER BY qs.total_worker_time DESC;

-- Queries with high logical reads
SELECT TOP 20
    qs.sql_handle,
    qs.execution_count,
    qs.total_logical_reads,
    qs.total_logical_reads / qs.execution_count as avg_logical_reads,
    qs.total_worker_time / qs.execution_count as avg_cpu_time,
    qs.total_elapsed_time / qs.execution_count as avg_elapsed_time,
    SUBSTRING(st.text, (qs.statement_start_offset/2)+1, 
        ((CASE qs.statement_end_offset
            WHEN -1 THEN DATALENGTH(st.text)
            ELSE qs.statement_end_offset
        END - qs.statement_start_offset)/2) + 1) as statement_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
ORDER BY qs.total_logical_reads DESC;
```

### 2. Blocking and Deadlocks
```sql
-- Current blocking sessions
SELECT 
    blocking.session_id as blocking_session_id,
    blocked.session_id as blocked_session_id,
    blocking.login_name as blocking_user,
    blocked.login_name as blocked_user,
    blocked.wait_type,
    blocked.wait_time,
    blocked.wait_resource,
    blocking_sql.text as blocking_query,
    blocked_sql.text as blocked_query
FROM sys.dm_exec_sessions blocking
JOIN sys.dm_exec_sessions blocked ON blocking.session_id = blocked.blocking_session_id
CROSS APPLY sys.dm_exec_sql_text(blocking.most_recent_sql_handle) blocking_sql
CROSS APPLY sys.dm_exec_sql_text(blocked.most_recent_sql_handle) blocked_sql
WHERE blocked.blocking_session_id != 0;

-- Deadlock information (requires extended events or trace)
SELECT 
    xed.value('@timestamp', 'datetime2') as event_time,
    xed.query('.') as deadlock_graph
FROM (
    SELECT CAST(target_data AS XML) as target_data
    FROM sys.dm_xe_sessions xs
    JOIN sys.dm_xe_session_targets xt ON xs.address = xt.event_session_address
    WHERE xs.name = 'system_health'
        AND xt.target_name = 'ring_buffer'
) as tab
CROSS APPLY target_data.nodes('RingBufferTarget/event[@name="xml_deadlock_report"]') as t(xed);
```

## Azure SQL Database Specific Features

### 1. Azure SQL Database Recommendations
```sql
-- Performance recommendations from Azure
SELECT 
    recommendation_type,
    recommendation_reason,
    valid_since,
    last_refresh,
    state,
    details
FROM sys.dm_db_tuning_recommendations
WHERE state = 'Active';

-- Automatic tuning status
SELECT 
    name,
    desired_state_desc,
    actual_state_desc,
    reason_desc
FROM sys.database_automatic_tuning_options;
```

### 2. Resource Governance
```sql
-- Current resource usage (Azure SQL Database)
SELECT 
    end_time,
    avg_cpu_percent,
    avg_data_io_percent,
    avg_log_write_percent,
    avg_memory_usage_percent,
    xtp_storage_percent,
    max_worker_percent,
    max_session_percent
FROM sys.dm_db_resource_stats
ORDER BY end_time DESC;

-- Historical resource usage
SELECT 
    start_time,
    end_time,
    avg_cpu_percent,
    avg_data_io_percent,
    avg_log_write_percent,
    avg_memory_usage_percent
FROM sys.resource_stats
WHERE database_name = DB_NAME()
    AND start_time >= DATEADD(day, -7, GETUTCDATE())
ORDER BY start_time DESC;
```

## Monitoring and Alerting

### 1. Performance Monitoring Queries
```sql
-- Database performance dashboard
SELECT 
    'Current Time' as metric,
    GETDATE() as value
UNION ALL
SELECT 
    'Active Connections',
    CAST(COUNT(*) as VARCHAR(20))
FROM sys.dm_exec_sessions
WHERE is_user_process = 1
UNION ALL
SELECT 
    'Blocking Sessions',
    CAST(COUNT(DISTINCT blocking_session_id) as VARCHAR(20))
FROM sys.dm_exec_sessions
WHERE blocking_session_id != 0
UNION ALL
SELECT 
    'Long Running Queries (>30s)',
    CAST(COUNT(*) as VARCHAR(20))
FROM sys.dm_exec_requests
WHERE total_elapsed_time > 30000;
```

### 2. Alert Thresholds
```sql
-- Performance alert conditions
WITH performance_alerts AS (
    SELECT 
        'High CPU Usage' as alert_type,
        CASE WHEN AVG(avg_cpu_percent) > 80 THEN 'CRITICAL'
             WHEN AVG(avg_cpu_percent) > 60 THEN 'WARNING'
             ELSE 'OK' END as status,
        CAST(AVG(avg_cpu_percent) as DECIMAL(5,2)) as current_value,
        '80%' as threshold
    FROM sys.dm_db_resource_stats
    WHERE end_time >= DATEADD(minute, -15, GETUTCDATE())
    
    UNION ALL
    
    SELECT 
        'High IO Usage',
        CASE WHEN AVG(avg_data_io_percent) > 80 THEN 'CRITICAL'
             WHEN AVG(avg_data_io_percent) > 60 THEN 'WARNING'
             ELSE 'OK' END,
        CAST(AVG(avg_data_io_percent) as DECIMAL(5,2)),
        '80%'
    FROM sys.dm_db_resource_stats
    WHERE end_time >= DATEADD(minute, -15, GETUTCDATE())
    
    UNION ALL
    
    SELECT 
        'Blocking Sessions',
        CASE WHEN COUNT(DISTINCT blocking_session_id) > 5 THEN 'CRITICAL'
             WHEN COUNT(DISTINCT blocking_session_id) > 0 THEN 'WARNING'
             ELSE 'OK' END,
        CAST(COUNT(DISTINCT blocking_session_id) as VARCHAR(10)),
        '0'
    FROM sys.dm_exec_sessions
    WHERE blocking_session_id != 0
)
SELECT * FROM performance_alerts
WHERE status IN ('WARNING', 'CRITICAL');
```

## Troubleshooting

### 1. Performance Issues Diagnosis
```sql
-- Current performance bottlenecks
SELECT 
    'Wait Statistics' as analysis_type,
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    signal_wait_time_ms,
    wait_time_ms - signal_wait_time_ms as resource_wait_time_ms
FROM sys.dm_os_wait_stats
WHERE wait_time_ms > 1000
    AND wait_type NOT IN ('SLEEP_TASK', 'BROKER_TASK_STOP', 'SQLTRACE_INCREMENTAL_FLUSH_SLEEP')
ORDER BY wait_time_ms DESC;

-- Memory pressure indicators
SELECT 
    type,
    name,
    memory_node_id,
    pages_kb,
    pages_kb / 1024 as pages_mb
FROM sys.dm_os_memory_clerks
WHERE pages_kb > 1024
ORDER BY pages_kb DESC;
```

### 2. Query Performance Issues
```sql
-- Queries causing high resource usage
SELECT TOP 10
    DB_NAME(qp.dbid) as database_name,
    OBJECT_NAME(qp.objectid, qp.dbid) as object_name,
    qp.query_plan,
    qs.execution_count,
    qs.total_worker_time,
    qs.total_elapsed_time,
    qs.total_logical_reads,
    qs.total_physical_reads,
    SUBSTRING(qt.text, qs.statement_start_offset/2+1,
        (CASE WHEN qs.statement_end_offset = -1
              THEN LEN(CONVERT(nvarchar(max), qt.text)) * 2
              ELSE qs.statement_end_offset end - qs.statement_start_offset)/2) as query_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) as qt
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) as qp
ORDER BY qs.total_worker_time DESC;
```

## Performance Targets

### Success Criteria
- **CPU Usage**: < 70% average
- **IO Usage**: < 70% average  
- **Buffer Cache Hit Ratio**: > 95%
- **Query Response Time**: < 3 seconds for 95% of queries
- **Blocking Duration**: < 30 seconds
- **Index Fragmentation**: < 30%
- **Wait Time**: < 10% of total execution time

### Alert Thresholds
- **Critical**: CPU > 80%, IO > 80%, Blocking > 60 seconds
- **Warning**: CPU > 60%, IO > 60%, Blocking > 30 seconds
- **Critical**: Buffer cache hit ratio < 90%
- **Warning**: Index fragmentation > 30%