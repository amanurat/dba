# ⚙️ SQL Server Performance Tuning: Query Template Collection

รวม T-SQL Query Templates สำหรับใช้วิเคราะห์ ปรับจูน และตรวจสอบ performance ของ SQL Server บน Azure

---

## 🔍 1. ตรวจสอบ Slow Queries จาก Query Store

### 1.1 Top Slow Queries (Total Duration)
```sql
-- Top 10 Query ที่ใช้เวลารวมมากที่สุด
-- Top 10 Queries (Human-readable format) - Last 24 Hours
WITH top_queries AS (
    SELECT TOP 10
        qst.query_sql_text,
            q.query_id,
           rs.count_executions,
           rs.avg_duration / 1000.0 AS avg_duration_ms,
           (rs.avg_duration * rs.count_executions) / 1000.0 AS total_duration_ms,
           rs.avg_cpu_time / 1000.0 AS avg_cpu_time_ms
    FROM sys.query_store_query_text qst
             INNER JOIN sys.query_store_query q ON qst.query_text_id = q.query_text_id
             INNER JOIN sys.query_store_plan qsp ON q.query_id = qsp.query_id
             INNER JOIN sys.query_store_runtime_stats rs ON qsp.plan_id = rs.plan_id
    WHERE rs.last_execution_time > DATEADD(hour, -24, GETUTCDATE())
)
SELECT
    LEFT(REPLACE(REPLACE(query_sql_text, CHAR(10), ' '), CHAR(13), ' '), 120)
        + '...' AS [Query Text Preview],
    COUNT_EXECUTIONS AS [Executions],
    CAST(avg_duration_ms AS DECIMAL(10,2)) AS [Avg Duration (ms)],
    CAST(total_duration_ms AS DECIMAL(18,2)) AS [Total Duration (ms)],
    CAST(avg_cpu_time_ms AS DECIMAL(10,2)) AS [Avg CPU Time (ms)],
    CAST(100.0 * total_duration_ms / SUM(total_duration_ms) OVER() AS DECIMAL(5,2))
        AS [% of Total Duration]

FROM top_queries
ORDER BY total_duration_ms DESC;

```

### 1.2 Slowest Queries Per Execution
```sql
-- Top 10 Query ที่ช้าที่สุดต่อครั้ง
SELECT TOP 10
    qst.query_sql_text,
    qsp.plan_id,
    rs.count_executions,
    ROUND(rs.avg_duration / 1000.0, 2) AS avg_duration_ms,
    ROUND(rs.max_duration / 1000.0, 2) AS max_duration_ms,
    ROUND(rs.min_duration / 1000.0, 2) AS min_duration_ms,
    ROUND(rs.stdev_duration / 1000.0, 2) AS stdev_duration_ms,
    ROUND(rs.avg_cpu_time / 1000.0, 2) AS avg_cpu_time_ms,
    rs.avg_logical_io_reads,
    rs.last_execution_time
FROM sys.query_store_query_text qst
    INNER JOIN sys.query_store_query q ON qst.query_text_id = q.query_text_id
    INNER JOIN sys.query_store_plan qsp ON q.query_id = qsp.query_id
    INNER JOIN sys.query_store_runtime_stats rs ON qsp.plan_id = rs.plan_id
WHERE rs.last_execution_time > DATEADD(hour, -24, GETUTCDATE())
    AND rs.count_executions > 5  -- รันอย่างน้อย 5 ครั้ง
    AND qst.query_sql_text NOT LIKE '%sys.%'
ORDER BY rs.avg_duration DESC;
```

---

## 🔍 2. วิเคราะห์ Query จาก DMV (สำหรับ SQL Server ทุกเวอร์ชัน)

### 2.1 Current Slow Queries in Cache
```sql
-- Query ช้าที่อยู่ใน Plan Cache ปัจจุบัน
SELECT TOP 10
    SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
        ((CASE WHEN qs.statement_end_offset = -1
            THEN LEN(CONVERT(nvarchar(max), st.text)) * 2
            ELSE qs.statement_end_offset
        END - qs.statement_start_offset)/2) + 1) AS query_text,
    qs.execution_count,
    ROUND(qs.total_elapsed_time / 1000.0, 2) AS total_elapsed_time_ms,
    ROUND(qs.total_elapsed_time / qs.execution_count / 1000.0, 2) AS avg_elapsed_time_ms,
    ROUND(qs.max_elapsed_time / 1000.0, 2) AS max_elapsed_time_ms,
    ROUND(qs.total_worker_time / 1000.0, 2) AS total_cpu_time_ms,
    ROUND(qs.total_worker_time / qs.execution_count / 1000.0, 2) AS avg_cpu_time_ms,
    qs.total_logical_reads,
    ROUND(qs.total_logical_reads / CAST(qs.execution_count AS float), 0) AS avg_logical_reads,
    qs.total_physical_reads,
    qs.creation_time,
    qs.last_execution_time
FROM sys.dm_exec_query_stats qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE qs.last_execution_time > DATEADD(hour, -4, GETDATE())
ORDER BY qs.total_elapsed_time DESC;
```

### 2.2 Most CPU Intensive Queries
```sql
-- Query ที่ใช้ CPU มากที่สุด
SELECT TOP 10
    SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
        ((CASE WHEN qs.statement_end_offset = -1
            THEN LEN(CONVERT(nvarchar(max), st.text)) * 2
            ELSE qs.statement_end_offset
        END - qs.statement_start_offset)/2) + 1) AS query_text,
    qs.execution_count,
    ROUND(qs.total_worker_time / 1000.0, 2) AS total_cpu_time_ms,
    ROUND(qs.total_worker_time / qs.execution_count / 1000.0, 2) AS avg_cpu_time_ms,
    ROUND(qs.max_worker_time / 1000.0, 2) AS max_cpu_time_ms,
    ROUND(qs.total_elapsed_time / qs.execution_count / 1000.0, 2) AS avg_elapsed_time_ms,
    qs.total_logical_reads,
    ROUND(qs.total_logical_reads / CAST(qs.execution_count AS float), 0) AS avg_logical_reads,
    qs.creation_time,
    qs.last_execution_time,
    ROUND((qs.total_worker_time * 100.0) / 
        (SELECT SUM(total_worker_time) FROM sys.dm_exec_query_stats), 2) AS cpu_percentage
FROM sys.dm_exec_query_stats qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE qs.last_execution_time > DATEADD(hour, -4, GETDATE())
ORDER BY qs.total_worker_time DESC;
```

---

## 🔍 3. Index Analysis และ Missing Index Detection

### 3.1 Missing Index Recommendations
```sql
-- Index ที่ขาดหายไปและมี impact สูง
SELECT 
    migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans) AS improvement_measure,
    'CREATE NONCLUSTERED INDEX [IX_' + OBJECT_NAME(mid.object_id, mid.database_id) + '_' + 
        REPLACE(REPLACE(REPLACE(ISNULL(mid.equality_columns,''), ', ', '_'), '[', ''), ']', '') + 
        CASE WHEN mid.inequality_columns IS NOT NULL 
             THEN '_' + REPLACE(REPLACE(REPLACE(mid.inequality_columns, ', ', '_'), '[', ''), ']', '') 
             ELSE '' END + ']' +
    ' ON ' + mid.statement + ' (' + ISNULL(mid.equality_columns,'') +
    CASE WHEN mid.inequality_columns IS NOT NULL 
         THEN CASE WHEN mid.equality_columns IS NOT NULL THEN ',' ELSE '' END + mid.inequality_columns 
         ELSE '' END + ')' +
    ISNULL(' INCLUDE (' + mid.included_columns + ')', '') AS create_index_statement,
    migs.user_seeks,
    migs.user_scans,
    migs.avg_total_user_cost,
    migs.avg_user_impact,
    OBJECT_NAME(mid.object_id, mid.database_id) AS table_name,
    mid.equality_columns,
    mid.inequality_columns,
    mid.included_columns
FROM sys.dm_db_missing_index_groups mig
    INNER JOIN sys.dm_db_missing_index_group_stats migs ON migs.group_handle = mig.index_group_handle
    INNER JOIN sys.dm_db_missing_index_details mid ON mig.index_handle = mid.index_handle
WHERE migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans) > 10
    AND mid.database_id = DB_ID()
ORDER BY improvement_measure DESC;
```

### 3.2 Unused Index Detection
```sql
-- Index ที่ไม่ได้ใช้งาน (ควรพิจารณาลบ)

```

### 3.3 Index Usage Statistics
```sql
-- สถิติการใช้งาน Index
SELECT
    OBJECT_SCHEMA_NAME(i.object_id) AS schema_name,
    OBJECT_NAME(i.object_id) AS table_name,
    i.name AS index_name,
    i.type_desc AS index_type,
    SUM(ISNULL(ius.user_seeks, 0)) AS user_seeks,
    SUM(ISNULL(ius.user_scans, 0)) AS user_scans,
    SUM(ISNULL(ius.user_lookups, 0)) AS user_lookups,
    SUM(ISNULL(ius.user_seeks, 0) + ISNULL(ius.user_scans, 0) + ISNULL(ius.user_lookups, 0)) AS total_reads,
    SUM(ISNULL(ius.user_updates, 0)) AS user_updates,
    CAST(SUM(ps.used_page_count) * 8.0 / 1024 AS decimal(15,2)) AS index_size_mb,
    MAX(ius.last_user_seek) AS last_user_seek,
    MAX(ius.last_user_scan) AS last_user_scan,
    MAX(ius.last_user_lookup) AS last_user_lookup,
    MAX(ius.last_user_update) AS last_user_update,
    'DROP INDEX [' + i.name + '] ON [' + OBJECT_SCHEMA_NAME(i.object_id) + '].[' + OBJECT_NAME(i.object_id) + '];' AS drop_statement
FROM sys.indexes i
         INNER JOIN sys.dm_db_partition_stats ps
                    ON i.object_id = ps.object_id AND i.index_id = ps.index_id
         LEFT JOIN sys.dm_db_index_usage_stats ius
                   ON i.object_id = ius.object_id
                       AND i.index_id = ius.index_id
                       AND ius.database_id = DB_ID()
WHERE OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
  AND i.index_id > 0                -- ไม่รวม heap
  AND i.is_primary_key = 0          -- ไม่รวม primary key
  AND i.is_unique_constraint = 0    -- ไม่รวม unique constraint
GROUP BY i.object_id, i.index_id, i.name, i.type_desc
HAVING CAST(SUM(ps.used_page_count) * 8.0 / 1024 AS decimal(15,2)) > 1   -- Index > 1MB
   AND SUM(ISNULL(ius.user_seeks,0) + ISNULL(ius.user_scans,0) + ISNULL(ius.user_lookups,0)) = 0
ORDER BY index_size_mb DESC;


```

---

## 🔍 4. Wait Statistics Analysis

### 4.1 Current Wait Statistics
```sql
-- Wait Statistics ปัจจุบัน
SELECT TOP 20
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    max_wait_time_ms,
    signal_wait_time_ms,
    CAST(100.0 * wait_time_ms / SUM(wait_time_ms) OVER() AS decimal(5,2)) AS percentage,
    CAST(wait_time_ms / waiting_tasks_count AS decimal(15,2)) AS avg_wait_time_ms,
    CASE 
        WHEN wait_type LIKE 'PAGEIOLATCH%' THEN 'I/O Bottleneck'
        WHEN wait_type LIKE 'LCK_%' THEN 'Locking Issue'
        WHEN wait_type LIKE 'PAGELATCH%' THEN 'Memory Pressure'
        WHEN wait_type LIKE 'CXPACKET%' THEN 'Parallelism Issue'
        WHEN wait_type = 'SOS_SCHEDULER_YIELD' THEN 'CPU Pressure'
        WHEN wait_type LIKE 'WRITELOG%' THEN 'Log I/O Issue'
        ELSE 'Other'
    END AS wait_category
FROM sys.dm_os_wait_stats
WHERE waiting_tasks_count > 0
    AND wait_type NOT IN (
        'CLR_SEMAPHORE', 'LAZYWRITER_SLEEP', 'RESOURCE_QUEUE', 'SLEEP_TASK',
        'SLEEP_SYSTEMTASK', 'SQLTRACE_WAIT_ENTRIES', 'WAITFOR', 'BROKER_EVENTHANDLER',
        'CHECKPOINT_QUEUE', 'REQUEST_FOR_DEADLOCK_SEARCH', 'XE_TIMER_EVENT'
    )
ORDER BY wait_time_ms DESC;
```

### 4.2 Wait Statistics สำหรับ Azure SQL Database
```sql
-- Wait Statistics เฉพาะสำหรับ Azure SQL Database
SELECT TOP 15
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    max_wait_time_ms,
    signal_wait_time_ms,
    CAST(100.0 * wait_time_ms / SUM(wait_time_ms) OVER() AS decimal(5,2)) AS percentage,
    CAST(wait_time_ms / waiting_tasks_count AS decimal(15,2)) AS avg_wait_time_ms,
    CASE 
        WHEN wait_type = 'RESOURCE_SEMAPHORE' THEN 'Memory Grant Queue - Consider increasing DWU/DTU'
        WHEN wait_type LIKE 'PAGEIOLATCH%' THEN 'Storage I/O - Consider Premium storage or higher tier'
        WHEN wait_type = 'LOG_RATE_GOVERNOR' THEN 'Log rate throttling - Consider higher service tier'
        WHEN wait_type LIKE 'POOL_%' THEN 'Resource pool limits - Consider scaling up'
        WHEN wait_type = 'HADR_THROTTLE_LOG_RATE_GOVERNOR' THEN 'Geo-replication throttling'
        WHEN wait_type LIKE 'LCK_%' THEN 'Locking - Review query patterns and indexes'
        WHEN wait_type = 'SOS_SCHEDULER_YIELD' THEN 'CPU pressure - Consider higher service tier'
        ELSE 'Review Azure SQL documentation'
    END AS azure_recommendation
FROM sys.dm_os_wait_stats
WHERE waiting_tasks_count > 0
    AND wait_type NOT IN (
        'CLR_SEMAPHORE', 'LAZYWRITER_SLEEP', 'RESOURCE_QUEUE', 'SLEEP_TASK',
        'SLEEP_SYSTEMTASK', 'SQLTRACE_WAIT_ENTRIES', 'WAITFOR', 'BROKER_EVENTHANDLER'
    )
ORDER BY wait_time_ms DESC;
```

---

## 🔍 5. Connection และ Session Monitoring

### 5.1 Current Active Sessions
```sql
-- Session ที่กำลัง active
SELECT 
    s.session_id,
    s.login_time,
    s.login_name,
    s.program_name,
    s.host_name,
    s.status,
    s.cpu_time,
    s.memory_usage * 8 AS memory_usage_kb,
    s.total_scheduled_time,
    s.total_elapsed_time,
    s.reads,
    s.writes,
    s.logical_reads,
    r.command,
    r.wait_type,
    r.wait_time,
    r.blocking_session_id,
    SUBSTRING(st.text, (r.statement_start_offset/2)+1,
        ((CASE WHEN r.statement_end_offset = -1
            THEN LEN(CONVERT(nvarchar(max), st.text)) * 2
            ELSE r.statement_end_offset
        END - r.statement_start_offset)/2) + 1) AS current_query
FROM sys.dm_exec_sessions s
    LEFT JOIN sys.dm_exec_requests r ON s.session_id = r.session_id
    OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) st
WHERE s.is_user_process = 1
    AND s.status IN ('running', 'runnable', 'suspended')
ORDER BY s.cpu_time DESC;
```

### 5.2 Blocking Chains
```sql
-- Blocking chains และ deadlock detection
WITH BlockingChain AS (
    SELECT 
        r.session_id,
        r.blocking_session_id,
        s.login_name,
        s.program_name,
        r.command,
        r.wait_type,
        r.wait_time,
        r.cpu_time,
        SUBSTRING(st.text, (r.statement_start_offset/2)+1,
            ((CASE WHEN r.statement_end_offset = -1
                THEN LEN(CONVERT(nvarchar(max), st.text)) * 2
                ELSE r.statement_end_offset
            END - r.statement_start_offset)/2) + 1) AS query_text,
        0 AS level
    FROM sys.dm_exec_requests r
        INNER JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
        OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) st
    WHERE r.blocking_session_id = 0
        AND EXISTS (SELECT 1 FROM sys.dm_exec_requests r2 WHERE r2.blocking_session_id = r.session_id)
    
    UNION ALL
    
    SELECT 
        r.session_id,
        r.blocking_session_id,
        s.login_name,
        s.program_name,
        r.command,
        r.wait_type,
        r.wait_time,
        r.cpu_time,
        SUBSTRING(st.text, (r.statement_start_offset/2)+1,
            ((CASE WHEN r.statement_end_offset = -1
                THEN LEN(CONVERT(nvarchar(max), st.text)) * 2
                ELSE r.statement_end_offset
            END - r.statement_start_offset)/2) + 1) AS query_text,
        bc.level + 1
    FROM sys.dm_exec_requests r
        INNER JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
        INNER JOIN BlockingChain bc ON r.blocking_session_id = bc.session_id
        OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) st
    WHERE bc.level < 10  -- Prevent infinite recursion
)
SELECT 
    session_id,
    blocking_session_id,
    level,
    login_name,
    program_name,
    command,
    wait_type,
    wait_time,
    cpu_time,
    query_text
FROM BlockingChain
ORDER BY level, session_id;
```

---

## 🔍 6. Resource Utilization (Azure SQL Database)

### 6.1 Database Resource Usage
```sql
-- Resource utilization สำหรับ Azure SQL Database
SELECT 
    end_time,
    avg_cpu_percent,
    avg_data_io_percent,
    avg_log_write_percent,
    avg_memory_usage_percent,
    xtp_storage_percent,
    max_worker_percent,
    max_session_percent,
    dtu_limit,
    cpu_limit,
    CASE 
        WHEN avg_cpu_percent > 80 THEN 'High CPU Usage'
        WHEN avg_data_io_percent > 80 THEN 'High Data I/O'
        WHEN avg_log_write_percent > 80 THEN 'High Log I/O'
        WHEN max_worker_percent > 80 THEN 'High Worker Thread Usage'
        WHEN max_session_percent > 80 THEN 'High Session Usage'
        ELSE 'Normal'
    END AS resource_pressure
FROM sys.dm_db_resource_stats
WHERE end_time > DATEADD(hour, -24, GETUTCDATE())
ORDER BY end_time DESC;
```

### 6.2 Storage Usage
```sql
-- การใช้ Storage space
SELECT 
    'Database Size' AS metric,
    CAST(SUM(CAST(FILEPROPERTY(name, 'SpaceUsed') AS bigint) * 8192.) / 1024 / 1024 AS decimal(15,2)) AS used_space_mb,
    CAST(SUM(size) * 8192. / 1024 / 1024 AS decimal(15,2)) AS allocated_space_mb,
    CAST((SUM(CAST(FILEPROPERTY(name, 'SpaceUsed') AS bigint)) * 100.0 / SUM(size)) AS decimal(5,2)) AS space_used_percent
FROM sys.database_files
WHERE type_desc = 'ROWS'

UNION ALL

SELECT 
    'Log Size',
    CAST(SUM(CAST(FILEPROPERTY(name, 'SpaceUsed') AS bigint) * 8192.) / 1024 / 1024 AS decimal(15,2)),
    CAST(SUM(size) * 8192. / 1024 / 1024 AS decimal(15,2)),
    CAST((SUM(CAST(FILEPROPERTY(name, 'SpaceUsed') AS bigint)) * 100.0 / SUM(size)) AS decimal(5,2))
FROM sys.database_files
WHERE type_desc = 'LOG';
```

---

## 🔍 7. Query Store Health Monitoring

### 7.1 Query Store Configuration Status
```sql
-- สถานะการตั้งค่า Query Store
SELECT
    actual_state_desc AS current_state,
    readonly_reason AS readonly_reason_code,   -- ตัวเลข code
    desired_state_desc AS desired_state,
    current_storage_size_mb,
    max_storage_size_mb,
    CAST(current_storage_size_mb * 100.0 / NULLIF(max_storage_size_mb,0) AS decimal(5,2)) AS storage_usage_percent,
    flush_interval_seconds,
    interval_length_minutes,
    stale_query_threshold_days,
    size_based_cleanup_mode_desc,
    query_capture_mode_desc,
    max_plans_per_query,
    wait_stats_capture_mode_desc
FROM sys.database_query_store_options;

/*SELECT
    readonly_reason,
    CASE readonly_reason
        WHEN 1 THEN 'Database is in read-only mode'
        WHEN 2 THEN 'Database is in single-user mode'
        WHEN 3 THEN 'Database is in emergency mode'
        WHEN 4 THEN 'Database is secondary replica (read-only)'
        WHEN 5 THEN 'Query Store internal error'
        WHEN 6 THEN 'Database is in restoring state'
        ELSE 'Other / Unknown'
        END AS readonly_reason_desc
FROM sys.database_query_store_options;*/



```

### 7.2 Query Store Statistics
```sql
-- สถิติ Query Store
SELECT 
    'Total Queries' AS metric,
    COUNT(*) AS count_value,
    NULL AS size_mb
FROM sys.query_store_query

UNION ALL

SELECT 
    'Total Plans',
    COUNT(*),
    NULL
FROM sys.query_store_plan

UNION ALL

SELECT 
    'Total Runtime Stats',
    COUNT(*),
    NULL
FROM sys.query_store_runtime_stats

UNION ALL

SELECT 
    'Queries (Last 24h)',
    COUNT(DISTINCT q.query_id),
    NULL
FROM sys.query_store_query q
    INNER JOIN sys.query_store_plan p ON q.query_id = p.query_id
    INNER JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
WHERE rs.last_execution_time > DATEADD(hour, -24, GETUTCDATE())

UNION ALL

SELECT 
    'Average Queries per Hour',
    COUNT(DISTINCT q.query_id) / 24,
    NULL
FROM sys.query_store_query q
    INNER JOIN sys.query_store_plan p ON q.query_id = p.query_id
    INNER JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
WHERE rs.last_execution_time > DATEADD(hour, -24, GETUTCDATE());
```

---

## 🔍 8. Plan Regression Detection

### 8.1 Plan Performance Regression
```sql
-- ตรวจหา Plan regression
WITH PlanPerformance AS (
    SELECT 
        q.query_id,
        qst.query_sql_text,
        p.plan_id,
        rs.runtime_stats_interval_id,
        rs.avg_duration,
        rs.count_executions,
        rsi.start_time,
        rsi.end_time,
        ROW_NUMBER() OVER (PARTITION BY q.query_id ORDER BY rsi.start_time DESC) AS rn_latest,
        ROW_NUMBER() OVER (PARTITION BY q.query_id ORDER BY rsi.start_time ASC) AS rn_oldest
    FROM sys.query_store_query q
        INNER JOIN sys.query_store_query_text qst ON q.query_text_id = qst.query_text_id
        INNER JOIN sys.query_store_plan p ON q.query_id = p.query_id
        INNER JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
        INNER JOIN sys.query_store_runtime_stats_interval rsi ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
    WHERE rs.count_executions > 10
        AND rsi.start_time > DATEADD(day, -7, GETUTCDATE())
),
PerformanceComparison AS (
    SELECT 
        latest.query_id,
        latest.query_sql_text,
        latest.plan_id AS latest_plan_id,
        latest.avg_duration AS latest_avg_duration,
        latest.count_executions AS latest_executions,
        oldest.plan_id AS oldest_plan_id,
        oldest.avg_duration AS oldest_avg_duration,
        oldest.count_executions AS oldest_executions,
        CASE 
            WHEN oldest.avg_duration > 0 
            THEN CAST((latest.avg_duration - oldest.avg_duration) * 100.0 / oldest.avg_duration AS decimal(10,2))
            ELSE NULL
        END AS performance_change_percent
    FROM PlanPerformance latest
        INNER JOIN PlanPerformance oldest ON latest.query_id = oldest.query_id
    WHERE latest.rn_latest = 1
        AND oldest.rn_oldest = 1
        AND latest.plan_id <> oldest.plan_id  -- Different plans
)
SELECT 
    query_id,
    LEFT(query_sql_text, 100) AS query_text_preview,
    latest_plan_id,
    oldest_plan_id,
    latest_avg_duration / 1000.0 AS latest_avg_duration_ms,
    oldest_avg_duration / 1000.0 AS oldest_avg_duration_ms,
    performance_change_percent,
    latest_executions,
    oldest_executions,
    CASE 
        WHEN performance_change_percent > 50 THEN 'Significant Regression'
        WHEN performance_change_percent > 20 THEN 'Moderate Regression'
        WHEN performance_change_percent < -20 THEN 'Performance Improvement'
        ELSE 'Stable'
    END AS regression_status
FROM PerformanceComparison
WHERE ABS(performance_change_percent) > 20  -- Only significant changes
ORDER BY performance_change_percent DESC;
```

---

## 🔍 9. Database Schema Analysis

### 9.1 Table Size และ Row Count
```sql
-- ขนาดของ Table และจำนวน rows
SELECT 
    OBJECT_SCHEMA_NAME(t.object_id) AS schema_name,
    t.name AS table_name,
    p.rows AS row_count,
    CAST((8.0 * SUM(a.used_pages)) / 1024 AS decimal(15,2)) AS used_space_mb,
    CAST((8.0 * SUM(a.total_pages)) / 1024 AS decimal(15,2)) AS allocated_space_mb,
    CAST((8.0 * (SUM(a.total_pages) - SUM(a.used_pages))) / 1024 AS decimal(15,2)) AS unused_space_mb,
    COUNT(i.index_id) - 1 AS index_count,  -- -1 เพราะไม่นับ heap/clustered index
    CASE 
        WHEN p.rows = 0 THEN 'Empty'
        WHEN p.rows < 1000 THEN 'Small'
        WHEN p.rows < 100000 THEN 'Medium'
        WHEN p.rows < 1000000 THEN 'Large'
        ELSE 'Very Large'
    END AS table_size_category
FROM sys.tables t
    INNER JOIN sys.partitions p ON t.object_id = p.object_id
    INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
    LEFT JOIN sys.indexes i ON t.object_id = i.object_id AND i.index_id > 0
WHERE p.index_id IN (0, 1)  -- Heap or clustered index
GROUP BY t.object_id, t.name, p.rows
ORDER BY used_space_mb DESC;
```

### 9.2 Column Statistics Health
```sql
-- สถานะ Statistics ของ columns
;WITH stats_health AS (
    SELECT
        CASE
            WHEN sp.last_updated < DATEADD(day, -7, GETDATE()) THEN 'Outdated'
            WHEN sp.modification_counter > sp.rows * 0.2 THEN 'High Modifications'
            WHEN sp.rows_sampled < sp.rows * 0.1 THEN 'Low Sample Rate'
            ELSE 'Good'
            END AS stats_health,
        CAST(sp.rows_sampled * 100.0 / NULLIF(sp.rows, 0) AS decimal(5,2)) AS sample_percent
    FROM sys.stats s
             CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
    WHERE OBJECTPROPERTY(s.object_id, 'IsUserTable') = 1
      AND sp.rows > 0
)
 SELECT
     stats_health,
     COUNT(*) AS total_stats,
     CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER() AS decimal(5,2)) AS percent_of_total,
     CAST(AVG(sample_percent) AS decimal(5,2)) AS avg_sample_percent
 FROM stats_health
 GROUP BY stats_health
 ORDER BY
     CASE stats_health
         WHEN 'Outdated' THEN 1
         WHEN 'High Modifications' THEN 2
         WHEN 'Low Sample Rate' THEN 3
         ELSE 4
         END;

-- Sample Output (Statistics Health Report)
-- stats_health       | total_stats | percent_of_total | avg_sample_percent
-----------------+-------------+------------------+--------------------
-- Outdated           | 5           | 12.50%           | 95.20
-- High Modifications | 3           | 7.50%            | 98.70
-- Low Sample Rate    | 2           | 5.00%            | 8.30
-- Good               | 30          | 75.00%           | 100.00
    
-- สมมติใน database ของคุณมี 40 statistics ทั้งหมด
-- 5 อัน → last updated เกิน 7 วัน → จัดเป็น Outdated
-- 3 อัน → มี row modifications เกิน 20% → จัดเป็น High Modifications
-- 2 อัน → sample น้อยกว่า 10% → จัดเป็น Low Sample Rate
-- 30 อัน → ปกติ → จัดเป็น Good
    
    
-- รายละเอียดทุก Statistics object
SELECT
    OBJECT_SCHEMA_NAME(s.object_id) AS schema_name,
    OBJECT_NAME(s.object_id) AS table_name,
    s.name AS stats_name,
    sp.last_updated,
    sp.rows,
    sp.rows_sampled,
    CAST(sp.rows_sampled * 100.0 / NULLIF(sp.rows, 0) AS decimal(5,2)) AS sample_percent,
    sp.steps AS histogram_steps,
    sp.modification_counter
FROM sys.stats s
         CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE OBJECTPROPERTY(s.object_id, 'IsUserTable') = 1
  AND sp.rows > 0
ORDER BY schema_name, table_name, stats_name;


``` 


---

## 💡 10. Maintenance และ Health Check Queries

### 10.1 Index Fragmentation
```sql
-- ตรวจสอบ Index fragmentation
SELECT 
    OBJECT_SCHEMA_NAME(ips.object_id) AS schema_name,
    OBJECT_NAME(ips.object_id) AS table_name,
    i.name AS index_name,
    i.type_desc AS index_type,
    ips.index_depth,
    ips.avg_fragmentation_in_percent,
    ips.fragment_count,
    ips.avg_fragment_size_in_pages,
    ips.page_count,
    CASE 
        WHEN ips.avg_fragmentation_in_percent > 30 THEN 'REBUILD'
        WHEN ips.avg_fragmentation_in_percent > 10 THEN 'REORGANIZE'
        ELSE 'NO ACTION'
    END AS maintenance_action,
    CASE 
        WHEN ips.avg_fragmentation_in_percent > 30 THEN 
            'ALTER INDEX [' + i.name + '] ON [' + OBJECT_SCHEMA_NAME(ips.object_id) + '].[' + OBJECT_NAME(ips.object_id) + '] REBUILD;'
        WHEN ips.avg_fragmentation_in_percent > 10 THEN 
            'ALTER INDEX [' + i.name + '] ON [' + OBJECT_SCHEMA_NAME(ips.object_id) + '].[' + OBJECT_NAME(ips.object_id) + '] REORGANIZE;'
        ELSE NULL
    END AS maintenance_command
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
    INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.avg_fragmentation_in_percent > 5  -- Only show fragmented indexes
    AND ips.page_count > 100  -- Only indexes with significant size
    AND i.index_id > 0  -- Skip heap
ORDER BY ips.avg_fragmentation_in_percent DESC;
```

### 10.2 Database Consistency Check
```sql
-- ตรวจสอบ Database consistency (ใช้อย่างระมัดระวังใน production)
-- สำหรับ Azure SQL Database ใช้ command นี้แทน DBCC CHECKDB
SELECT 
    'Run DBCC CHECKDB' AS recommendation,
    'DBCC CHECKDB(''' + DB_NAME() + ''') WITH NO_INFOMSGS, ALL_ERRORMSGS;' AS command,
    'Schedule during maintenance window' AS note

UNION ALL

SELECT 
    'Check for Corruption',
    'SELECT * FROM sys.dm_db_persisted_sku_features;',
    'Monitor for any corruption indicators'

UNION ALL

SELECT 
    'Verify Backup',
    'Check backup history and test restore procedures',
    'Ensure backup and recovery strategy is working';
```

---

## ✅ 11. Automated Health Check Script

### 11.1 Complete Database Health Assessment
```sql
-- Comprehensive health check script
DECLARE @results TABLE (
    category NVARCHAR(50),
    check_name NVARCHAR(100),
    status NVARCHAR(20),
    value NVARCHAR(100),
    recommendation NVARCHAR(500)
);

-- Check 1: Query Store Health
INSERT INTO @results
SELECT 
    'Query Store',
    'Status',
    CASE actual_state_desc 
        WHEN 'READ_write' THEN 'Good'
        WHEN 'read_only' THEN 'Warning'
        ELSE 'Critical'
    END,
    actual_state_desc,
    CASE actual_state_desc 
        WHEN 'read_write' THEN 'Query Store is functioning normally'
        WHEN 'read_only' THEN 'Query Store is read-only - check storage usage'
        ELSE 'Query Store is disabled - enable for performance monitoring'
    END
FROM sys.database_query_store_options;

-- Check 2: Storage Usage
INSERT INTO @results
SELECT 
    'Storage',
    'Query Store Usage',
    CASE 
        WHEN CAST(current_storage_size_mb * 100.0 / max_storage_size_mb AS int) > 90 THEN 'Critical'
        WHEN CAST(current_storage_size_mb * 100.0 / max_storage_size_mb AS int) > 80 THEN 'Warning'
        ELSE 'Good'
    END,
    CAST(CAST(current_storage_size_mb * 100.0 / max_storage_size_mb AS int) AS nvarchar(10)) + '%',
    CASE 
        WHEN CAST(current_storage_size_mb * 100.0 / max_storage_size_mb AS int) > 90 THEN 'Increase MAX_STORAGE_SIZE_MB or enable cleanup'
        WHEN CAST(current_storage_size_mb * 100.0 / max_storage_size_mb AS int) > 80 THEN 'Monitor storage usage closely'
        ELSE 'Storage usage is within normal limits'
    END
FROM sys.database_query_store_options;

-- Check 3: Performance Issues
INSERT INTO @results
SELECT 
    'Performance',
    'Slow Queries',
    CASE 
        WHEN COUNT(*) > 10 THEN 'Critical'
        WHEN COUNT(*) > 5 THEN 'Warning'
        ELSE 'Good'
    END,
    CAST(COUNT(*) AS nvarchar(10)) + ' queries > 1sec avg',
    CASE 
        WHEN COUNT(*) > 10 THEN 'Multiple slow queries detected - review and optimize'
        WHEN COUNT(*) > 5 THEN 'Some slow queries detected - investigate'
        ELSE 'Query performance is acceptable'
    END
FROM sys.query_store_query_text qst
    INNER JOIN sys.query_store_query q ON qst.query_text_id = q.query_text_id
    INNER JOIN sys.query_store_plan qsp ON q.query_id = qsp.query_id
    INNER JOIN sys.query_store_runtime_stats rs ON qsp.plan_id = rs.plan_id
WHERE rs.last_execution_time > DATEADD(hour, -24, GETUTCDATE())
    AND rs.avg_duration > 1000000  -- > 1 second
    AND rs.count_executions > 5;

-- Check 4: Missing Indexes
INSERT INTO @results
SELECT 
    'Indexes',
    'Missing High-Impact Indexes',
    CASE 
        WHEN COUNT(*) > 10 THEN 'Critical'
        WHEN COUNT(*) > 5 THEN 'Warning'
        ELSE 'Good'
    END,
    CAST(COUNT(*) AS nvarchar(10)) + ' recommendations',
    CASE 
        WHEN COUNT(*) > 10 THEN 'Many missing indexes - prioritize high-impact ones'
        WHEN COUNT(*) > 5 THEN 'Some missing indexes - review recommendations'
        ELSE 'Index coverage appears adequate'
    END
FROM sys.dm_db_missing_index_groups mig
    INNER JOIN sys.dm_db_missing_index_group_stats migs ON migs.group_handle = mig.index_group_handle
    INNER JOIN sys.dm_db_missing_index_details mid ON mig.index_handle = mid.index_handle
WHERE migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans) > 50
    AND mid.database_id = DB_ID();

-- Return results
SELECT 
    category,
    check_name,
    status,
    value,
    recommendation,
    GETDATE() AS check_time
FROM @results
ORDER BY 
    CASE status 
        WHEN 'Critical' THEN 1
        WHEN 'Warning' THEN 2
        ELSE 3
    END,
    category,
    check_name;
```

---

## 💡 Tips การใช้งาน:

### ✅ **Best Practices:**
- ใช้ **Query Store** เป็นหลักสำหรับการวิเคราะห์ performance
- **Schedule** health check queries ให้รันประจำ
- เก็บ **baseline metrics** เพื่อเปรียบเทียบ
- ใช้ **DMV queries** สำหรับ real-time monitoring
- **Filter out system queries** เพื่อมุ่งเน้นแค่ user queries

### ⚠️ **ข้อควรระวัง:**
- Query Store ใช้ **additional storage** และอาจมี **performance overhead**
- **Reset statistics** อย่างระมัดระวังใน production
- **Large result sets** จาก DMV อาจใช้ resource มาก
- บาง DMV **reset** หลัง SQL Server restart

### 🔧 **การใช้งานใน Azure:**
```sql
-- เช็คการตั้งค่าเฉพาะ Azure SQL Database
SELECT 
    name,
    value,
    value_in_use,
    description
FROM sys.configurations
WHERE name IN (
    'max degree of parallelism',
    'cost threshold for parallelism',
    'max server memory (MB)'
)
ORDER BY name;
```

---

**🚀 เมื่อใช้ query templates เหล่านี้ร่วมกับ monitoring dashboard จะทำให้การ optimize SQL Server มีประสิทธิภาพและเป็นระบบมากขึ้น!**

การใช้ Query Store ร่วมกับ DMV จะให้ภาพรวมที่ครบถ้วนของ database performance ทั้งแบบ historical และ real-time