-- SQL Server Performance Monitoring Queries for Azure
-- Use these queries for daily monitoring and performance analysis

-- 🔍 HEALTH CHECK: Overall Database Health
SELECT 
    'SQL Server Health Check' as section,
    GETDATE() as check_time,
    @@VERSION as sql_version;

-- 📊 CONNECTIONS: Current connection and session status
SELECT 
    'Connection Status' as section;

SELECT 
    'Active Sessions' as metric,
    COUNT(*) as current_value,
    'User sessions currently active' as description
FROM sys.dm_exec_sessions
WHERE is_user_process = 1
UNION ALL
SELECT 
    'Blocked Sessions',
    COUNT(DISTINCT blocking_session_id),
    'Sessions currently being blocked'
FROM sys.dm_exec_sessions
WHERE blocking_session_id != 0
UNION ALL
SELECT 
    'Running Requests',
    COUNT(*),
    'Currently executing requests'
FROM sys.dm_exec_requests
WHERE status = 'running';

-- 🎯 BUFFER CACHE: Buffer cache hit ratio
SELECT 
    'Buffer Cache Performance' as section;

SELECT 
    'Buffer Cache Hit Ratio' as metric,
    CAST((a.cntr_value * 1.0 / b.cntr_value) * 100.0 as DECIMAL(5,2)) as hit_ratio_percent,
    'Target: >95%' as target
FROM sys.dm_os_performance_counters a
JOIN sys.dm_os_performance_counters b ON a.object_name = b.object_name
WHERE a.counter_name = 'Buffer cache hit ratio'
    AND b.counter_name = 'Buffer cache hit ratio base';

-- 🐌 SLOW QUERIES: Top resource consuming queries from Query Store
SELECT 
    'Top Resource Consuming Queries (Last 24 Hours)' as section;

SELECT TOP 10
    qsq.query_id,
    LEFT(qsqt.query_sql_text, 100) as query_preview,
    qsrs.count_executions as execution_count,
    CAST(qsrs.avg_duration / 1000.0 as DECIMAL(10,2)) as avg_duration_ms,
    CAST(qsrs.avg_cpu_time / 1000.0 as DECIMAL(10,2)) as avg_cpu_time_ms,
    qsrs.avg_logical_io_reads,
    qsrs.avg_physical_io_reads,
    qsrs.last_execution_time
FROM sys.query_store_query qsq
JOIN sys.query_store_query_text qsqt ON qsq.query_text_id = qsqt.query_text_id
JOIN sys.query_store_runtime_stats qsrs ON qsq.query_id = qsrs.query_id
JOIN sys.query_store_runtime_stats_interval qsrsi ON qsrs.runtime_stats_interval_id = qsrsi.runtime_stats_interval_id
WHERE qsrsi.start_time >= DATEADD(day, -1, GETUTCDATE())
ORDER BY qsrs.avg_duration DESC;

-- ⚠️ WAIT STATISTICS: Current wait statistics
SELECT 
    'Wait Statistics Analysis' as section;

SELECT TOP 15
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    signal_wait_time_ms,
    wait_time_ms - signal_wait_time_ms as resource_wait_time_ms,
    CAST(wait_time_ms / waiting_tasks_count as DECIMAL(10,2)) as avg_wait_time_ms,
    CAST((wait_time_ms * 100.0) / SUM(wait_time_ms) OVER() as DECIMAL(5,2)) as wait_percentage
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN (
    'CLR_SEMAPHORE', 'LAZYWRITER_SLEEP', 'RESOURCE_QUEUE', 'SLEEP_TASK',
    'SLEEP_SYSTEMTASK', 'SQLTRACE_BUFFER_FLUSH', 'WAITFOR', 'LOGMGR_QUEUE',
    'CHECKPOINT_QUEUE', 'REQUEST_FOR_DEADLOCK_SEARCH', 'XE_TIMER_EVENT',
    'BROKER_TO_FLUSH', 'BROKER_TASK_STOP', 'CLR_MANUAL_EVENT', 'CLR_AUTO_EVENT'
)
AND waiting_tasks_count > 0
AND wait_time_ms > 1000
ORDER BY wait_time_ms DESC;

-- 💾 STORAGE: Database file sizes and usage
SELECT 
    'Database Storage Usage' as section;

SELECT 
    DB_NAME() as database_name,
    name as logical_name,
    physical_name,
    CAST(size * 8.0 / 1024 as DECIMAL(10,2)) as size_mb,
    CASE 
        WHEN max_size = -1 THEN 'Unlimited'
        ELSE CAST(max_size * 8.0 / 1024 as VARCHAR(20))
    END as max_size_mb,
    CASE 
        WHEN is_percent_growth = 1 THEN CAST(growth as VARCHAR(10)) + '%'
        ELSE CAST(growth * 8.0 / 1024 as VARCHAR(20)) + ' MB'
    END as growth_setting,
    type_desc as file_type
FROM sys.database_files
ORDER BY type_desc, name;

-- 🔧 INDEX ANALYSIS: Missing indexes with high impact
SELECT 
    'Missing Index Analysis' as section;

SELECT TOP 10
    CAST(migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans) as DECIMAL(10,2)) as improvement_measure,
    'CREATE INDEX [IX_' + OBJECT_NAME(mid.object_id) + '_Missing] ON ' + mid.statement + 
    ' (' + ISNULL(mid.equality_columns,'') +
    CASE WHEN mid.equality_columns IS NOT NULL AND mid.inequality_columns IS NOT NULL THEN ',' ELSE '' END +
    ISNULL(mid.inequality_columns, '') + ')' +
    ISNULL(' INCLUDE (' + mid.included_columns + ')', '') as suggested_index,
    migs.user_seeks,
    migs.user_scans,
    CAST(migs.avg_total_user_cost as DECIMAL(10,2)) as avg_total_user_cost,
    CAST(migs.avg_user_impact as DECIMAL(5,2)) as avg_user_impact_percent
FROM sys.dm_db_missing_index_groups mig
JOIN sys.dm_db_missing_index_group_stats migs ON migs.group_handle = mig.index_group_handle
JOIN sys.dm_db_missing_index_details mid ON mig.index_handle = mid.index_handle
WHERE migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans) > 10
ORDER BY improvement_measure DESC;

-- 📈 INDEX USAGE: Index usage statistics
SELECT 
    'Index Usage Statistics' as section;

SELECT TOP 15
    OBJECT_NAME(ius.object_id) as table_name,
    i.name as index_name,
    i.type_desc as index_type,
    ius.user_seeks,
    ius.user_scans,
    ius.user_lookups,
    ius.user_updates,
    ius.user_seeks + ius.user_scans + ius.user_lookups as total_reads,
    CASE 
        WHEN ius.user_updates > 0 THEN 
            CAST((ius.user_seeks + ius.user_scans + ius.user_lookups) * 1.0 / ius.user_updates as DECIMAL(10,2))
        ELSE NULL
    END as read_write_ratio,
    ius.last_user_seek,
    ius.last_user_scan,
    ius.last_user_lookup
FROM sys.dm_db_index_usage_stats ius
JOIN sys.indexes i ON ius.object_id = i.object_id AND ius.index_id = i.index_id
WHERE ius.database_id = DB_ID()
    AND OBJECT_NAME(ius.object_id) NOT LIKE 'sys%'
    AND i.type_desc != 'HEAP'
ORDER BY total_reads DESC;

-- ❌ UNUSED INDEXES: Potentially unused indexes
SELECT 
    'Potentially Unused Indexes' as section;

SELECT 
    OBJECT_NAME(i.object_id) as table_name,
    i.name as index_name,
    i.type_desc as index_type,
    'No usage detected since last restart' as status,
    i.is_disabled,
    i.is_hypothetical
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats ius ON i.object_id = ius.object_id 
    AND i.index_id = ius.index_id 
    AND ius.database_id = DB_ID()
WHERE OBJECT_NAME(i.object_id) NOT LIKE 'sys%'
    AND i.index_id > 0
    AND i.type_desc != 'HEAP'
    AND i.is_primary_key = 0
    AND i.is_unique_constraint = 0
    AND (ius.user_seeks + ius.user_scans + ius.user_lookups) IS NULL
ORDER BY OBJECT_NAME(i.object_id), i.name;

-- 🔄 ACTIVE PROCESSES: Current running processes and requests
SELECT 
    'Active Database Processes' as section;

SELECT 
    s.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    r.status,
    r.command,
    r.total_elapsed_time / 1000 as elapsed_time_seconds,
    r.cpu_time,
    r.logical_reads,
    r.reads,
    r.writes,
    LEFT(st.text, 100) as query_preview,
    r.blocking_session_id,
    r.wait_type,
    r.wait_time,
    r.wait_resource
FROM sys.dm_exec_sessions s
LEFT JOIN sys.dm_exec_requests r ON s.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) st
WHERE s.is_user_process = 1
    AND (r.session_id IS NOT NULL OR s.open_transaction_count > 0)
ORDER BY r.total_elapsed_time DESC, s.session_id;

-- 🚫 BLOCKING ANALYSIS: Current blocking chains
SELECT 
    'Blocking Analysis' as section;

SELECT 
    blocking.session_id as blocking_session_id,
    blocked.session_id as blocked_session_id,
    blocking.login_name as blocking_user,
    blocked.login_name as blocked_user,
    blocked.wait_type,
    blocked.wait_time / 1000 as wait_time_seconds,
    blocked.wait_resource,
    LEFT(blocking_sql.text, 100) as blocking_query,
    LEFT(blocked_sql.text, 100) as blocked_query
FROM sys.dm_exec_sessions blocking
JOIN sys.dm_exec_sessions blocked ON blocking.session_id = blocked.blocking_session_id
OUTER APPLY sys.dm_exec_sql_text(blocking.most_recent_sql_handle) blocking_sql
OUTER APPLY sys.dm_exec_sql_text(blocked.most_recent_sql_handle) blocked_sql
WHERE blocked.blocking_session_id != 0;

-- 📊 RESOURCE USAGE: Current resource utilization (Azure SQL Database)
SELECT 
    'Resource Utilization (Last 15 Minutes)' as section;

SELECT 
    'CPU Usage' as resource_type,
    CAST(AVG(avg_cpu_percent) as DECIMAL(5,2)) as avg_percent,
    CAST(MAX(avg_cpu_percent) as DECIMAL(5,2)) as max_percent,
    'Target: <70%' as target
FROM sys.dm_db_resource_stats
WHERE end_time >= DATEADD(minute, -15, GETUTCDATE())
UNION ALL
SELECT 
    'Data IO Usage',
    CAST(AVG(avg_data_io_percent) as DECIMAL(5,2)),
    CAST(MAX(avg_data_io_percent) as DECIMAL(5,2)),
    'Target: <70%'
FROM sys.dm_db_resource_stats
WHERE end_time >= DATEADD(minute, -15, GETUTCDATE())
UNION ALL
SELECT 
    'Log Write Usage',
    CAST(AVG(avg_log_write_percent) as DECIMAL(5,2)),
    CAST(MAX(avg_log_write_percent) as DECIMAL(5,2)),
    'Target: <70%'
FROM sys.dm_db_resource_stats
WHERE end_time >= DATEADD(minute, -15, GETUTCDATE())
UNION ALL
SELECT 
    'Memory Usage',
    CAST(AVG(avg_memory_usage_percent) as DECIMAL(5,2)),
    CAST(MAX(avg_memory_usage_percent) as DECIMAL(5,2)),
    'Target: <80%'
FROM sys.dm_db_resource_stats
WHERE end_time >= DATEADD(minute, -15, GETUTCDATE());

-- 🔍 INDEX FRAGMENTATION: High fragmentation indexes
SELECT 
    'Index Fragmentation Analysis' as section;

SELECT TOP 15
    OBJECT_NAME(ips.object_id) as table_name,
    i.name as index_name,
    ips.index_type_desc,
    CAST(ips.avg_fragmentation_in_percent as DECIMAL(5,2)) as fragmentation_percent,
    ips.page_count,
    CASE 
        WHEN ips.avg_fragmentation_in_percent > 30 THEN 'REBUILD RECOMMENDED'
        WHEN ips.avg_fragmentation_in_percent > 10 THEN 'REORGANIZE RECOMMENDED'
        ELSE 'NO ACTION NEEDED'
    END as recommended_action,
    'ALTER INDEX [' + i.name + '] ON [' + OBJECT_NAME(ips.object_id) + '] ' +
    CASE 
        WHEN ips.avg_fragmentation_in_percent > 30 THEN 'REBUILD'
        WHEN ips.avg_fragmentation_in_percent > 10 THEN 'REORGANIZE'
        ELSE ''
    END as maintenance_command
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.avg_fragmentation_in_percent > 10
    AND ips.page_count > 100
    AND i.name IS NOT NULL
ORDER BY ips.avg_fragmentation_in_percent DESC;

-- 🚨 PERFORMANCE ALERTS: Critical performance indicators
SELECT 
    'Performance Alerts' as section;

WITH performance_alerts AS (
    SELECT 
        'HIGH CPU USAGE' as alert_type,
        CASE 
            WHEN AVG(avg_cpu_percent) > 80 THEN 'CRITICAL'
            WHEN AVG(avg_cpu_percent) > 60 THEN 'WARNING'
            ELSE 'OK' 
        END as status,
        CAST(AVG(avg_cpu_percent) as DECIMAL(5,2)) as current_value,
        '80% Critical, 60% Warning' as threshold
    FROM sys.dm_db_resource_stats
    WHERE end_time >= DATEADD(minute, -15, GETUTCDATE())
    
    UNION ALL
    
    SELECT 
        'HIGH IO USAGE',
        CASE 
            WHEN AVG(avg_data_io_percent) > 80 THEN 'CRITICAL'
            WHEN AVG(avg_data_io_percent) > 60 THEN 'WARNING'
            ELSE 'OK' 
        END,
        CAST(AVG(avg_data_io_percent) as DECIMAL(5,2)),
        '80% Critical, 60% Warning'
    FROM sys.dm_db_resource_stats
    WHERE end_time >= DATEADD(minute, -15, GETUTCDATE())
    
    UNION ALL
    
    SELECT 
        'BLOCKING SESSIONS',
        CASE 
            WHEN COUNT(DISTINCT blocking_session_id) > 5 THEN 'CRITICAL'
            WHEN COUNT(DISTINCT blocking_session_id) > 0 THEN 'WARNING'
            ELSE 'OK' 
        END,
        CAST(COUNT(DISTINCT blocking_session_id) as VARCHAR(10)),
        '5+ Critical, 1+ Warning'
    FROM sys.dm_exec_sessions
    WHERE blocking_session_id != 0
    
    UNION ALL
    
    SELECT 
        'BUFFER CACHE HIT RATIO',
        CASE 
            WHEN (a.cntr_value * 1.0 / b.cntr_value) * 100.0 < 90 THEN 'CRITICAL'
            WHEN (a.cntr_value * 1.0 / b.cntr_value) * 100.0 < 95 THEN 'WARNING'
            ELSE 'OK' 
        END,
        CAST((a.cntr_value * 1.0 / b.cntr_value) * 100.0 as VARCHAR(10)),
        '90% Critical, 95% Warning'
    FROM sys.dm_os_performance_counters a
    JOIN sys.dm_os_performance_counters b ON a.object_name = b.object_name
    WHERE a.counter_name = 'Buffer cache hit ratio'
        AND b.counter_name = 'Buffer cache hit ratio base'
)
SELECT 
    alert_type,
    status,
    current_value,
    threshold
FROM performance_alerts
WHERE status IN ('WARNING', 'CRITICAL')
ORDER BY 
    CASE status 
        WHEN 'CRITICAL' THEN 1 
        WHEN 'WARNING' THEN 2 
        ELSE 3 
    END;

-- 📋 CONFIGURATION: Key SQL Server configuration settings
SELECT 
    'SQL Server Configuration Review' as section;

SELECT 
    name as configuration_option,
    value as current_value,
    value_in_use as value_in_use,
    minimum as min_value,
    maximum as max_value,
    is_dynamic,
    is_advanced,
    CASE name
        WHEN 'max degree of parallelism' THEN 'Recommended: Number of CPU cores or 8, whichever is smaller'
        WHEN 'cost threshold for parallelism' THEN 'Recommended: 50 or higher'
        WHEN 'max server memory (MB)' THEN 'Should leave memory for OS (typically 80% of total RAM)'
        WHEN 'optimize for ad hoc workloads' THEN 'Recommended: 1 for OLTP workloads'
        ELSE 'Review SQL Server documentation'
    END as recommendation
FROM sys.configurations
WHERE name IN (
    'max degree of parallelism',
    'cost threshold for parallelism',
    'max server memory (MB)',
    'optimize for ad hoc workloads',
    'backup compression default',
    'remote admin connections'
)
ORDER BY name;