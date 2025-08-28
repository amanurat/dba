-- ================================================
-- SQL Server STEP-BY-STEP Performance Tuning Guide
-- Complete Performance Optimization Workflow
-- ================================================

-- ========================================
-- STEP 1: Environment Setup and Prerequisites
-- ========================================

-- Enable Query Store if not already enabled (SQL Server 2016+)
IF (SELECT actual_state FROM sys.database_query_store_options) = 0
BEGIN
    ALTER DATABASE CURRENT SET QUERY_STORE = ON 
    (
        OPERATION_MODE = READ_WRITE,
        CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30),
        DATA_FLUSH_INTERVAL_SECONDS = 900,
        INTERVAL_LENGTH_MINUTES = 60,
        MAX_STORAGE_SIZE_MB = 1000,
        QUERY_CAPTURE_MODE = AUTO,
        SIZE_BASED_CLEANUP_MODE = AUTO
    );
    PRINT 'Query Store enabled successfully.';
END
ELSE
    PRINT 'Query Store is already enabled.';

-- Enable execution statistics capture
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- Create performance tracking table
IF NOT EXISTS (SELECT * FROM sys.objects WHERE name = 'performance_tuning_log' AND type = 'U')
BEGIN
    CREATE TABLE performance_tuning_log (
        step_id INT IDENTITY(1,1) PRIMARY KEY,
        step_name NVARCHAR(100),
        action_description NVARCHAR(500),
        before_value DECIMAL(15,2),
        after_value DECIMAL(15,2),
        improvement_percentage DECIMAL(5,2),
        execution_time DATETIME2 DEFAULT GETDATE(),
        notes NVARCHAR(MAX)
    );
    PRINT 'Performance tracking table created.';
END;

-- ========================================
-- STEP 2: Initial Performance Assessment
-- ========================================

PRINT 'STEP 2: Conducting Initial Performance Assessment...';

-- 2.1 Database Size and Growth Analysis
SELECT 
    'Database Size Analysis' as assessment_type,
    DB_NAME() AS database_name,
    CAST(SUM(CAST(FILEPROPERTY(name, 'SpaceUsed') AS bigint) * 8192.) / 1024 / 1024 AS decimal(15,2)) AS space_used_mb,
    CAST(SUM(size) * 8192. / 1024 / 1024 AS decimal(15,2)) AS space_allocated_mb,
    CAST((SUM(CAST(FILEPROPERTY(name, 'SpaceUsed') AS bigint)) * 100.0 / SUM(size)) AS decimal(5,2)) AS space_utilization_percent
FROM sys.database_files
WHERE type_desc = 'ROWS';

-- 2.2 Connection and Session Analysis
SELECT 
    'Connection Analysis' as assessment_type,
    COUNT(*) as total_sessions,
    COUNT(CASE WHEN is_user_process = 1 THEN 1 END) as user_sessions,
    COUNT(CASE WHEN is_user_process = 1 AND status = 'running' THEN 1 END) as active_user_sessions,
    COUNT(CASE WHEN is_user_process = 1 AND status = 'sleeping' THEN 1 END) as sleeping_user_sessions,
    AVG(CASE WHEN is_user_process = 1 AND status = 'running' THEN DATEDIFF(second, last_request_start_time, GETDATE()) END) as avg_running_time_sec
FROM sys.dm_exec_sessions;

-- 2.3 Buffer Pool Hit Ratio
SELECT 
    'Buffer Pool Analysis' as assessment_type,
    counter_name,
    cntr_value,
    CASE 
        WHEN counter_name = 'Buffer cache hit ratio' THEN
            CASE 
                WHEN cntr_value > 98 THEN '🟢 Excellent (>98%)'
                WHEN cntr_value > 95 THEN '🟢 Good (95-98%)'
                WHEN cntr_value > 90 THEN '🟡 Fair (90-95%)'
                ELSE '🔴 Poor (<90%)'
            END
        WHEN counter_name = 'Page life expectancy' THEN
            CASE 
                WHEN cntr_value > 300 THEN '🟢 Good (>300s)'
                WHEN cntr_value > 120 THEN '🟡 Fair (120-300s)'
                ELSE '🔴 Poor (<120s)'
            END
        ELSE 'N/A'
    END as performance_status
FROM sys.dm_os_performance_counters
WHERE (counter_name = 'Buffer cache hit ratio' AND object_name LIKE '%Buffer Manager%')
    OR (counter_name = 'Page life expectancy' AND object_name LIKE '%Buffer Manager%');

-- 2.4 Top Wait Types
SELECT TOP 10
    'Wait Statistics Analysis' as assessment_type,
    wait_type,
    wait_time_ms,
    waiting_tasks_count,
    CAST(100.0 * wait_time_ms / SUM(wait_time_ms) OVER() AS decimal(5,2)) AS percentage,
    CAST(wait_time_ms / waiting_tasks_count AS decimal(15,2)) AS avg_wait_time_ms,
    CASE 
        WHEN wait_type LIKE 'PAGEIOLATCH_%' THEN '💾 I/O bottleneck'
        WHEN wait_type LIKE 'LCK_%' THEN '🔒 Lock contention'
        WHEN wait_type LIKE 'SOS_SCHEDULER_YIELD' THEN '🖥️ CPU pressure'
        WHEN wait_type LIKE 'CXPACKET' THEN '⚡ Parallelism issue'
        WHEN wait_type LIKE 'WRITELOG' THEN '📝 Log write bottleneck'
        ELSE '❓ Other'
    END as bottleneck_type
FROM sys.dm_os_wait_stats
WHERE waiting_tasks_count > 0
    AND wait_type NOT IN ('CLR_SEMAPHORE', 'LAZYWRITER_SLEEP', 'RESOURCE_QUEUE', 'SLEEP_TASK', 'SQLTRACE_INCREMENTAL_FLUSH_SLEEP')
ORDER BY wait_time_ms DESC;

-- Log initial assessment
INSERT INTO performance_tuning_log (step_name, action_description, notes)
VALUES ('Step 2', 'Initial Performance Assessment', 'Baseline measurements captured');

-- ========================================
-- STEP 3: Query Performance Analysis
-- ========================================

PRINT 'STEP 3: Analyzing Query Performance...';

-- 3.1 Top Resource-Consuming Queries (Query Store)
IF EXISTS (SELECT 1 FROM sys.database_query_store_options WHERE actual_state > 0)
BEGIN
    PRINT 'Using Query Store for query analysis...';
    
    SELECT TOP 15
        'Top CPU Consuming Queries' as analysis_type,
        qst.query_sql_text,
        rs.count_executions,
        ROUND(rs.avg_cpu_time / 1000.0, 2) as avg_cpu_ms,
        ROUND(rs.total_cpu_time / 1000.0, 2) as total_cpu_ms,
        ROUND(rs.avg_duration / 1000.0, 2) as avg_duration_ms,
        ROUND(rs.avg_logical_io_reads, 0) as avg_logical_reads,
        qsp.last_execution_time
    FROM sys.query_store_query_text qst
        INNER JOIN sys.query_store_query q ON qst.query_text_id = q.query_text_id
        INNER JOIN sys.query_store_plan qsp ON q.query_id = qsp.query_id
        INNER JOIN sys.query_store_runtime_stats rs ON qsp.plan_id = rs.plan_id
    WHERE rs.last_execution_time > DATEADD(hour, -24, GETUTCDATE())
        AND rs.count_executions > 5
        AND LEN(qst.query_sql_text) > 50
    ORDER BY rs.total_cpu_time DESC;
END
ELSE
BEGIN
    PRINT 'Using DMVs for query analysis...';
    
    -- 3.2 Alternative: Top Queries from DMVs
    SELECT TOP 15
        'Top CPU Consuming Queries (DMV)' as analysis_type,
        SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
            ((CASE WHEN qs.statement_end_offset = -1
                THEN LEN(CONVERT(nvarchar(max), st.text)) * 2
                ELSE qs.statement_end_offset
            END - qs.statement_start_offset)/2) + 1) AS query_text,
        qs.execution_count,
        ROUND(qs.total_worker_time / qs.execution_count / 1000.0, 2) AS avg_cpu_ms,
        ROUND(qs.total_worker_time / 1000.0, 2) AS total_cpu_ms,
        ROUND(qs.total_elapsed_time / qs.execution_count / 1000.0, 2) AS avg_duration_ms,
        ROUND(qs.total_logical_reads / qs.execution_count, 0) AS avg_logical_reads,
        qs.last_execution_time
    FROM sys.dm_exec_query_stats qs
        CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
    WHERE qs.last_execution_time > DATEADD(hour, -24, GETDATE())
        AND qs.execution_count > 5
        AND LEN(st.text) > 50
    ORDER BY qs.total_worker_time DESC;
END;

-- 3.3 Long Running Queries Currently Active
SELECT 
    'Currently Running Long Queries' as analysis_type,
    s.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    r.status,
    r.command,
    DATEDIFF(second, r.start_time, GETDATE()) as runtime_seconds,
    r.cpu_time,
    r.logical_reads,
    r.wait_type,
    r.wait_time,
    SUBSTRING(st.text, (r.statement_start_offset/2)+1,
        ((CASE WHEN r.statement_end_offset = -1
            THEN LEN(CONVERT(nvarchar(max), st.text)) * 2
            ELSE r.statement_end_offset
        END - r.statement_start_offset)/2) + 1) AS current_statement
FROM sys.dm_exec_sessions s
    INNER JOIN sys.dm_exec_requests r ON s.session_id = r.session_id
    CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) st
WHERE s.is_user_process = 1
    AND r.status = 'running'
    AND DATEDIFF(second, r.start_time, GETDATE()) > 10  -- Running for more than 10 seconds
ORDER BY runtime_seconds DESC;

-- ========================================
-- STEP 4: Index Analysis and Optimization
-- ========================================

PRINT 'STEP 4: Analyzing Index Usage and Performance...';

-- 4.1 Unused Indexes (Candidates for Removal)
SELECT 
    'Unused Index Analysis' as analysis_type,
    OBJECT_SCHEMA_NAME(i.object_id) AS schema_name,
    OBJECT_NAME(i.object_id) AS table_name,
    i.name AS index_name,
    i.type_desc AS index_type,
    ISNULL(ius.user_seeks, 0) AS user_seeks,
    ISNULL(ius.user_scans, 0) AS user_scans,
    ISNULL(ius.user_lookups, 0) AS user_lookups,
    ISNULL(ius.user_updates, 0) AS user_updates,
    CAST((a.used_pages * 8.0) / 1024 AS decimal(15,2)) AS index_size_mb,
    CASE 
        WHEN ISNULL(ius.user_seeks + ius.user_scans + ius.user_lookups, 0) = 0 AND ISNULL(ius.user_updates, 0) > 0
            THEN '🔴 Consider dropping - Only writes, no reads'
        WHEN ISNULL(ius.user_seeks + ius.user_scans + ius.user_lookups, 0) = 0 
            THEN '🔴 Consider dropping - No usage'
        WHEN ISNULL(ius.user_seeks + ius.user_scans + ius.user_lookups, 0) < 10 AND ISNULL(ius.user_updates, 0) > 100
            THEN '🟡 Low benefit - High maintenance cost'
        ELSE '🟢 Keep - Good usage'
    END AS recommendation
FROM sys.indexes i
    INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
    INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
    LEFT JOIN sys.dm_db_index_usage_stats ius ON i.object_id = ius.object_id AND i.index_id = ius.index_id AND ius.database_id = DB_ID()
WHERE OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
    AND i.index_id > 0  -- Exclude heap
    AND i.is_primary_key = 0  -- Exclude PK
    AND i.is_unique_constraint = 0  -- Exclude unique constraints
GROUP BY i.object_id, i.index_id, i.name, i.type_desc, ius.user_seeks, ius.user_scans, ius.user_lookups, ius.user_updates, a.used_pages
ORDER BY index_size_mb DESC, user_updates DESC;

-- 4.2 Missing Index Suggestions
SELECT 
    'Missing Index Analysis' as analysis_type,
    migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans) AS improvement_measure,
    'CREATE NONCLUSTERED INDEX IX_' + OBJECT_NAME(mid.object_id) + '_' + 
    REPLACE(REPLACE(REPLACE(ISNULL(mid.equality_columns,''),', ','_'),']',''),']','') + 
    CASE WHEN mid.inequality_columns IS NOT NULL THEN '_' + REPLACE(REPLACE(REPLACE(mid.inequality_columns,', ','_'),']',''),']','') ELSE '' END AS suggested_index_name,
    'CREATE NONCLUSTERED INDEX IX_' + OBJECT_NAME(mid.object_id) + '_' + 
    REPLACE(REPLACE(REPLACE(ISNULL(mid.equality_columns,''),', ','_'),']',''),']','') + 
    CASE WHEN mid.inequality_columns IS NOT NULL THEN '_' + REPLACE(REPLACE(REPLACE(mid.inequality_columns,', ','_'),']',''),']','') ELSE '' END +
    ' ON ' + mid.statement + ' (' + ISNULL(mid.equality_columns,'') +
    CASE WHEN mid.inequality_columns IS NOT NULL AND mid.equality_columns IS NOT NULL THEN ',' ELSE '' END +
    ISNULL(mid.inequality_columns, '') + ')' +
    CASE WHEN mid.included_columns IS NOT NULL THEN ' INCLUDE (' + mid.included_columns + ')' ELSE '' END AS create_statement,
    OBJECT_NAME(mid.object_id) AS table_name,
    migs.unique_compiles,
    migs.user_seeks,
    migs.user_scans,
    migs.avg_total_user_cost,
    migs.avg_user_impact,
    mid.equality_columns,
    mid.inequality_columns,
    mid.included_columns
FROM sys.dm_db_missing_index_groups mig
    INNER JOIN sys.dm_db_missing_index_group_stats migs ON migs.group_handle = mig.index_group_handle
    INNER JOIN sys.dm_db_missing_index_details mid ON mig.index_handle = mid.index_handle
WHERE migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans) > 10
ORDER BY improvement_measure DESC;

-- 4.3 Index Fragmentation Analysis
SELECT 
    'Index Fragmentation Analysis' as analysis_type,
    OBJECT_SCHEMA_NAME(ips.object_id) AS schema_name,
    OBJECT_NAME(ips.object_id) AS table_name,
    i.name AS index_name,
    ips.index_type_desc,
    ips.avg_fragmentation_in_percent,
    ips.page_count,
    CAST(ips.page_count * 8.0 / 1024 AS decimal(15,2)) AS size_mb,
    CASE 
        WHEN ips.avg_fragmentation_in_percent > 30 THEN '🔴 REBUILD needed (>30%)'
        WHEN ips.avg_fragmentation_in_percent > 10 THEN '🟡 REORGANIZE needed (10-30%)'
        ELSE '🟢 Good condition (<10%)'
    END AS maintenance_action,
    CASE 
        WHEN ips.avg_fragmentation_in_percent > 30 THEN 
            'ALTER INDEX [' + i.name + '] ON [' + OBJECT_SCHEMA_NAME(ips.object_id) + '].[' + OBJECT_NAME(ips.object_id) + '] REBUILD;'
        WHEN ips.avg_fragmentation_in_percent > 10 THEN 
            'ALTER INDEX [' + i.name + '] ON [' + OBJECT_SCHEMA_NAME(ips.object_id) + '].[' + OBJECT_NAME(ips.object_id) + '] REORGANIZE;'
        ELSE 'No action needed'
    END AS maintenance_command
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
    INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.index_id > 0  -- Exclude heap
    AND ips.page_count > 100  -- Only indexes with significant size
    AND OBJECTPROPERTY(ips.object_id, 'IsUserTable') = 1
ORDER BY ips.avg_fragmentation_in_percent DESC, size_mb DESC;

-- ========================================
-- STEP 5: Memory and Buffer Pool Optimization
-- ========================================

PRINT 'STEP 5: Analyzing Memory Usage and Buffer Pool...';

-- 5.1 Memory Allocation Analysis
SELECT 
    'Memory Allocation Analysis' as analysis_type,
    counter_name,
    cntr_value,
    CASE counter_name
        WHEN 'Total Server Memory (KB)' THEN CAST(cntr_value / 1024.0 / 1024 AS decimal(10,2))
        WHEN 'Target Server Memory (KB)' THEN CAST(cntr_value / 1024.0 / 1024 AS decimal(10,2))
        ELSE cntr_value
    END AS value_formatted,
    CASE counter_name
        WHEN 'Total Server Memory (KB)' THEN 'GB'
        WHEN 'Target Server Memory (KB)' THEN 'GB'
        WHEN 'Buffer cache hit ratio' THEN '%'
        WHEN 'Page life expectancy' THEN 'seconds'
        ELSE 'count'
    END AS unit,
    CASE 
        WHEN counter_name = 'Buffer cache hit ratio' AND cntr_value < 95 THEN '🔴 Consider increasing memory'
        WHEN counter_name = 'Page life expectancy' AND cntr_value < 300 THEN '🔴 Memory pressure detected'
        WHEN counter_name = 'Total Server Memory (KB)' AND cntr_value < (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Target Server Memory (KB)' AND object_name LIKE '%Memory Manager%') * 0.95 THEN '🟡 Memory still allocating'
        ELSE '🟢 Normal'
    END AS status
FROM sys.dm_os_performance_counters
WHERE object_name LIKE '%Memory Manager%'
    AND counter_name IN ('Total Server Memory (KB)', 'Target Server Memory (KB)', 'Buffer cache hit ratio', 'Page life expectancy');

-- 5.2 Buffer Pool Usage by Database
SELECT 
    'Buffer Pool Usage by Database' as analysis_type,
    DB_NAME(database_id) AS database_name,
    COUNT(*) AS cached_pages,
    CAST(COUNT(*) * 8.0 / 1024 AS decimal(15,2)) AS cached_mb,
    CAST(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM sys.dm_os_buffer_descriptors) AS decimal(5,2)) AS percentage_of_buffer_pool
FROM sys.dm_os_buffer_descriptors
WHERE database_id > 4  -- Exclude system databases
GROUP BY database_id
ORDER BY cached_pages DESC;

-- 5.3 Buffer Pool Usage by Object
SELECT TOP 20
    'Top Objects in Buffer Pool' as analysis_type,
    OBJECT_SCHEMA_NAME(p.object_id) AS schema_name,
    OBJECT_NAME(p.object_id) AS object_name,
    i.name AS index_name,
    i.type_desc AS index_type,
    COUNT(*) AS cached_pages,
    CAST(COUNT(*) * 8.0 / 1024 AS decimal(15,2)) AS cached_mb,
    CAST(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM sys.dm_os_buffer_descriptors WHERE database_id = DB_ID()) AS decimal(5,2)) AS percentage_of_db_buffer
FROM sys.dm_os_buffer_descriptors bd
    INNER JOIN sys.allocation_units au ON bd.allocation_unit_id = au.allocation_unit_id
    INNER JOIN sys.partitions p ON au.container_id = p.partition_id
    INNER JOIN sys.indexes i ON p.object_id = i.object_id AND p.index_id = i.index_id
WHERE bd.database_id = DB_ID()
    AND OBJECTPROPERTY(p.object_id, 'IsUserTable') = 1
GROUP BY p.object_id, i.index_id, i.name, i.type_desc
ORDER BY cached_pages DESC;

-- ========================================
-- STEP 6: Configuration Optimization Recommendations
-- ========================================

PRINT 'STEP 6: Analyzing Configuration Settings...';

-- 6.1 Critical Configuration Settings Analysis
WITH config_analysis AS (
    SELECT 
        name,
        value,
        value_in_use,
        is_dynamic,
        is_advanced,
        CASE 
            WHEN name = 'max server memory (MB)' THEN
                CASE 
                    WHEN value = 2147483647 THEN '🟡 Default (unlimited) - Consider setting explicit limit'
                    WHEN value > (SELECT CAST(total_physical_memory_kb / 1024 AS bigint) FROM sys.dm_os_sys_memory) * 0.8 THEN '🟡 May be too high - Leave memory for OS'
                    ELSE '🟢 Configured'
                END
            WHEN name = 'max degree of parallelism' THEN
                CASE 
                    WHEN value = 0 THEN '🟡 Default (0) - Consider setting based on CPU cores'
                    WHEN value > (SELECT cpu_count FROM sys.dm_os_sys_info) THEN '🔴 Higher than CPU count'
                    WHEN value > 8 THEN '🟡 Consider max value of 8'
                    ELSE '🟢 Reasonable setting'
                END
            WHEN name = 'cost threshold for parallelism' THEN
                CASE 
                    WHEN value = 5 THEN '🟡 Default (5) is often too low - Consider 25-50'
                    WHEN value < 10 THEN '🟡 Consider increasing to 25-50'
                    ELSE '🟢 Good setting'
                END
            WHEN name = 'optimize for ad hoc workloads' THEN
                CASE 
                    WHEN value = 0 THEN '🟡 Consider enabling for OLTP workloads'
                    ELSE '🟢 Enabled'
                END
            ELSE '🟢 Standard'
        END as recommendation,
        CASE 
            WHEN name = 'max server memory (MB)' AND value = 2147483647 THEN 
                'EXEC sp_configure ''max server memory (MB)'', ' + CAST((SELECT CAST(total_physical_memory_kb / 1024 AS bigint) FROM sys.dm_os_sys_memory) * 0.75 AS VARCHAR(20)) + '; RECONFIGURE;'
            WHEN name = 'max degree of parallelism' AND value = 0 THEN 
                'EXEC sp_configure ''max degree of parallelism'', ' + CAST(CASE WHEN (SELECT cpu_count FROM sys.dm_os_sys_info) > 8 THEN 8 ELSE (SELECT cpu_count FROM sys.dm_os_sys_info) END AS VARCHAR(5)) + '; RECONFIGURE;'
            WHEN name = 'cost threshold for parallelism' AND value = 5 THEN 
                'EXEC sp_configure ''cost threshold for parallelism'', 25; RECONFIGURE;'
            WHEN name = 'optimize for ad hoc workloads' AND value = 0 THEN 
                'EXEC sp_configure ''optimize for ad hoc workloads'', 1; RECONFIGURE;'
            ELSE NULL
        END as suggested_command
    FROM sys.configurations
    WHERE name IN (
        'max server memory (MB)',
        'max degree of parallelism',
        'cost threshold for parallelism',
        'optimize for ad hoc workloads'
    )
)
SELECT 
    'Configuration Analysis' as analysis_type,
    name,
    value as current_value,
    value_in_use,
    is_dynamic,
    recommendation,
    suggested_command
FROM config_analysis;

-- ========================================
-- STEP 7: Performance Monitoring Recommendations
-- ========================================

PRINT 'STEP 7: Setting up Performance Monitoring...';

-- 7.1 Create monitoring views for ongoing performance tracking
CREATE OR ALTER VIEW v_performance_summary AS
SELECT 
    GETDATE() as capture_time,
    
    -- Connection metrics
    (SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process = 1) as user_connections,
    (SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process = 1 AND status = 'running') as active_connections,
    
    -- Buffer pool metrics
    (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Buffer cache hit ratio' AND object_name LIKE '%Buffer Manager%') as buffer_hit_ratio,
    (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Page life expectancy' AND object_name LIKE '%Buffer Manager%') as page_life_expectancy,
    
    -- SQL Server activity
    (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Batch Requests/sec' AND object_name LIKE '%SQL Statistics%') as batch_requests_sec,
    (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'SQL Compilations/sec' AND object_name LIKE '%SQL Statistics%') as compilations_sec,
    
    -- Top wait type
    (SELECT TOP 1 wait_type FROM sys.dm_os_wait_stats WHERE waiting_tasks_count > 0 ORDER BY wait_time_ms DESC) as top_wait_type,
    
    -- Database size
    CAST(SUM(CAST(FILEPROPERTY(name, 'SpaceUsed') AS bigint) * 8192.) / 1024 / 1024 AS decimal(15,2)) as database_size_mb
FROM sys.database_files
WHERE type_desc = 'ROWS';

-- 7.2 Performance alert thresholds
SELECT 
    'Performance Alert Thresholds' as analysis_type,
    'Buffer Cache Hit Ratio' as metric,
    '< 95%' as warning_threshold,
    '< 90%' as critical_threshold,
    CAST((SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Buffer cache hit ratio' AND object_name LIKE '%Buffer Manager%') AS VARCHAR(10)) + '%' as current_value

UNION ALL

SELECT 
    'Performance Alert Thresholds',
    'Page Life Expectancy',
    '< 300 seconds',
    '< 120 seconds',
    CAST((SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Page life expectancy' AND object_name LIKE '%Buffer Manager%') AS VARCHAR(10)) + ' seconds'

UNION ALL

SELECT 
    'Performance Alert Thresholds',
    'Active User Connections',
    '> 50',
    '> 100',
    CAST((SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process = 1 AND status = 'running') AS VARCHAR(10))

UNION ALL

SELECT 
    'Performance Alert Thresholds',
    'Long Running Queries',
    '> 30 seconds',
    '> 120 seconds',
    CAST((SELECT COUNT(*) FROM sys.dm_exec_requests r INNER JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id WHERE s.is_user_process = 1 AND DATEDIFF(second, r.start_time, GETDATE()) > 30) AS VARCHAR(10)) + ' queries';

-- ========================================
-- STEP 8: Action Plan Generation
-- ========================================

PRINT 'STEP 8: Generating Performance Tuning Action Plan...';

-- Generate prioritized action plan based on findings
WITH action_priorities AS (
    -- High priority: Critical performance issues
    SELECT 1 as priority, '🔴 CRITICAL' as severity, 'Fix Buffer Cache Hit Ratio' as action, 
           'Increase memory allocation or optimize queries' as description, 'Immediate' as timeline
    WHERE (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Buffer cache hit ratio' AND object_name LIKE '%Buffer Manager%') < 90

    UNION ALL

    SELECT 1, '🔴 CRITICAL', 'Address Memory Pressure', 
           'Page Life Expectancy is critically low', 'Immediate'
    WHERE (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Page life expectancy' AND object_name LIKE '%Buffer Manager%') < 120

    UNION ALL

    SELECT 1, '🔴 CRITICAL', 'Terminate Long Running Queries', 
           'Multiple queries running longer than 2 minutes', 'Immediate'
    WHERE (SELECT COUNT(*) FROM sys.dm_exec_requests r INNER JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id 
           WHERE s.is_user_process = 1 AND DATEDIFF(second, r.start_time, GETDATE()) > 120) > 0

    UNION ALL

    -- Medium priority: Performance optimization opportunities  
    SELECT 2, '🟡 MEDIUM', 'Implement Missing Indexes', 
           'Create high-impact missing indexes', 'This week'
    WHERE EXISTS (SELECT 1 FROM sys.dm_db_missing_index_groups mig
                  INNER JOIN sys.dm_db_missing_index_group_stats migs ON migs.group_handle = mig.index_group_handle
                  WHERE migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans) > 100)

    UNION ALL

    SELECT 2, '🟡 MEDIUM', 'Rebuild Fragmented Indexes', 
           'Address indexes with >30% fragmentation', 'This week'
    WHERE EXISTS (SELECT 1 FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') 
                  WHERE avg_fragmentation_in_percent > 30 AND page_count > 100)

    UNION ALL

    SELECT 2, '🟡 MEDIUM', 'Drop Unused Indexes', 
           'Remove indexes with no read activity', 'This week'
    WHERE EXISTS (SELECT 1 FROM sys.indexes i 
                  LEFT JOIN sys.dm_db_index_usage_stats ius ON i.object_id = ius.object_id AND i.index_id = ius.index_id
                  WHERE OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1 AND i.index_id > 0 
                  AND i.is_primary_key = 0 AND ISNULL(ius.user_seeks + ius.user_scans + ius.user_lookups, 0) = 0)

    UNION ALL

    -- Low priority: Configuration optimizations
    SELECT 3, '🟢 LOW', 'Optimize Configuration Settings', 
           'Update MAXDOP, Cost Threshold, and other settings', 'This month'
    WHERE EXISTS (SELECT 1 FROM sys.configurations WHERE name = 'max degree of parallelism' AND value = 0)
       OR EXISTS (SELECT 1 FROM sys.configurations WHERE name = 'cost threshold for parallelism' AND value = 5)

    UNION ALL

    SELECT 3, '🟢 LOW', 'Setup Performance Monitoring', 
           'Implement automated performance monitoring', 'This month'
)

SELECT 
    'Performance Tuning Action Plan' as plan_type,
    priority,
    severity,
    action,
    description,
    timeline,
    ROW_NUMBER() OVER (ORDER BY priority, action) as step_number
FROM action_priorities
ORDER BY priority, action;

-- Log completion
INSERT INTO performance_tuning_log (step_name, action_description, notes)
VALUES ('Step 8', 'Action Plan Generated', 'Performance tuning analysis completed');

-- ========================================
-- STEP 9: Implementation Templates
-- ========================================

PRINT 'STEP 9: Generating Implementation Scripts...';

-- 9.1 Index maintenance script template
PRINT '--=== INDEX MAINTENANCE SCRIPT ===--';
SELECT 
    'Index Maintenance Commands' as script_type,
    maintenance_command
FROM (
    SELECT DISTINCT
        CASE 
            WHEN ips.avg_fragmentation_in_percent > 30 THEN 
                'ALTER INDEX [' + i.name + '] ON [' + OBJECT_SCHEMA_NAME(ips.object_id) + '].[' + OBJECT_NAME(ips.object_id) + '] REBUILD WITH (ONLINE = ON, MAXDOP = 4);'
            WHEN ips.avg_fragmentation_in_percent > 10 THEN 
                'ALTER INDEX [' + i.name + '] ON [' + OBJECT_SCHEMA_NAME(ips.object_id) + '].[' + OBJECT_NAME(ips.object_id) + '] REORGANIZE;'
        END AS maintenance_command
    FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
        INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
    WHERE ips.avg_fragmentation_in_percent > 10 
        AND ips.page_count > 100
        AND OBJECTPROPERTY(ips.object_id, 'IsUserTable') = 1
) m
WHERE maintenance_command IS NOT NULL
ORDER BY maintenance_command;

-- 9.2 Configuration optimization script
PRINT '--=== CONFIGURATION OPTIMIZATION SCRIPT ===--';
SELECT 
    'Configuration Commands' as script_type,
    config_command
FROM (
    SELECT 'EXEC sp_configure ''show advanced options'', 1; RECONFIGURE;' as config_command, 1 as sort_order
    UNION ALL
    SELECT suggested_command as config_command, 2 as sort_order
    FROM (
        SELECT 
            CASE 
                WHEN name = 'max server memory (MB)' AND value = 2147483647 THEN 
                    'EXEC sp_configure ''max server memory (MB)'', ' + CAST((SELECT CAST(total_physical_memory_kb / 1024 AS bigint) FROM sys.dm_os_sys_memory) * 0.75 AS VARCHAR(20)) + '; RECONFIGURE;'
                WHEN name = 'max degree of parallelism' AND value = 0 THEN 
                    'EXEC sp_configure ''max degree of parallelism'', ' + CAST(CASE WHEN (SELECT cpu_count FROM sys.dm_os_sys_info) > 8 THEN 8 ELSE (SELECT cpu_count FROM sys.dm_os_sys_info) END AS VARCHAR(5)) + '; RECONFIGURE;'
                WHEN name = 'cost threshold for parallelism' AND value = 5 THEN 
                    'EXEC sp_configure ''cost threshold for parallelism'', 25; RECONFIGURE;'
                WHEN name = 'optimize for ad hoc workloads' AND value = 0 THEN 
                    'EXEC sp_configure ''optimize for ad hoc workloads'', 1; RECONFIGURE;'
            END as suggested_command
        FROM sys.configurations
        WHERE name IN (
            'max server memory (MB)',
            'max degree of parallelism', 
            'cost threshold for parallelism',
            'optimize for ad hoc workloads'
        )
    ) c
    WHERE suggested_command IS NOT NULL
) commands
ORDER BY sort_order, config_command;

-- ========================================
-- STEP 10: Final Summary Report
-- ========================================

PRINT 'STEP 10: Generating Final Performance Tuning Summary...';

SELECT 
    '🎯 SQL SERVER PERFORMANCE TUNING COMPLETE' as summary_title,
    GETDATE() as completion_time;

-- Performance summary
SELECT 
    'Performance Metrics Summary' as report_section,
    metric_name,
    current_value,
    status,
    recommendation
FROM (
    SELECT 
        'Buffer Cache Hit Ratio' as metric_name,
        CAST((SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Buffer cache hit ratio' AND object_name LIKE '%Buffer Manager%') AS VARCHAR(20)) + '%' as current_value,
        CASE 
            WHEN (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Buffer cache hit ratio' AND object_name LIKE '%Buffer Manager%') > 98 THEN '🟢 Excellent'
            WHEN (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Buffer cache hit ratio' AND object_name LIKE '%Buffer Manager%') > 95 THEN '🟢 Good'
            WHEN (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Buffer cache hit ratio' AND object_name LIKE '%Buffer Manager%') > 90 THEN '🟡 Fair'
            ELSE '🔴 Poor'
        END as status,
        CASE 
            WHEN (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Buffer cache hit ratio' AND object_name LIKE '%Buffer Manager%') <= 95 THEN 'Increase memory or optimize queries'
            ELSE 'Continue monitoring'
        END as recommendation

    UNION ALL

    SELECT 
        'Active User Connections',
        CAST((SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process = 1 AND status = 'running') AS VARCHAR(10)),
        CASE 
            WHEN (SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process = 1 AND status = 'running') > 100 THEN '🔴 High'
            WHEN (SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process = 1 AND status = 'running') > 50 THEN '🟡 Moderate'
            ELSE '🟢 Normal'
        END,
        CASE 
            WHEN (SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process = 1 AND status = 'running') > 50 THEN 'Investigate connection pooling'
            ELSE 'Connection levels are normal'
        END

    UNION ALL

    SELECT 
        'Database Size',
        CAST(CAST(SUM(CAST(FILEPROPERTY(name, 'SpaceUsed') AS bigint) * 8192.) / 1024 / 1024 / 1024 AS decimal(15,2)) AS VARCHAR(20)) + ' GB',
        '🟢 Measured',
        'Monitor growth trends'
    FROM sys.database_files
    WHERE type_desc = 'ROWS'
) summary;

-- Actions completed log
SELECT 
    'Actions Completed' as report_section,
    COUNT(*) as total_analysis_steps
FROM performance_tuning_log
WHERE execution_time >= CAST(GETDATE() AS DATE);

PRINT '✅ Performance tuning analysis completed successfully!';
PRINT '📋 Review the action plan above and implement recommendations based on priority.';
PRINT '📊 Use the v_performance_summary view for ongoing monitoring.';
PRINT '⚠️ Always test configuration changes in a development environment first!';

-- Disable statistics output
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;