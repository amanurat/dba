-- 1) Workload Characterization
/*
# Document current environment
echo "=== Environment Assessment ===" > baseline_prep.txt
echo "Date: $(date)" >> baseline_prep.txt
echo "Environment: $ENVIRONMENT" >> baseline_prep.txt
echo "Database Versions:" >> baseline_prep.txt

# SQL Server version
sqlcmd -Q "SELECT @@VERSION;" >> baseline_prep.txt

# Azure SQL Database version (if applicable)
sqlcmd -Q "SELECT SERVERPROPERTY('productversion'), SERVERPROPERTY ('productlevel'), SERVERPROPERTY ('edition');" >> baseline_prep.txt

# PostgreSQL version (if applicable)
psql -c "SELECT version();" >> baseline_prep.txt

# MySQL version (if applicable)
mysql -e "SELECT VERSION();" >> baseline_prep.txt
*/


-- 2) Workload Characterization
-- Identify peak usage patterns
-- Run this across all database types during different time periods

-- SQL Server workload analysis
SELECT
    FORMAT(GETDATE(), 'yyyy-MM-dd HH:00:00') as hour_period,
    COUNT(*) as connection_count,
    AVG(DATEDIFF(second, login_time, GETDATE())) as avg_session_duration_sec
FROM sys.dm_exec_sessions
WHERE is_user_process = 1
    AND status <> 'sleeping'
GROUP BY FORMAT(GETDATE(), 'yyyy-MM-dd HH:00:00')
ORDER BY hour_period;


-- 3) Configuration Documentation
/*
# Create configuration backup before baseline
mkdir -p baseline_configs/$(date +%Y%m%d)

# SQL Server configuration
sqlcmd -Q "SELECT name, value, value_in_use FROM sys.configurations;" > baseline_configs/$(date +%Y%m%d)/mssql_config.txt

# Azure SQL Database configuration (if applicable)
az sql db show --resource-group $RG --server $SQL_SERVER --name $DB_NAME > baseline_configs/$(date +%Y%m%d)/azure_sql_config.json

# PostgreSQL configuration (if applicable)
pg_dump --schema-only your_database > baseline_configs/$(date +%Y%m%d)/postgresql_schema.sql
psql -c "SHOW ALL;" > baseline_configs/$(date +%Y%m%d)/postgresql_config.txt

# MySQL configuration (if applicable)
mysqldump --no-data --routines your_database > baseline_configs/$(date +%Y%m%d)/mysql_schema.sql
mysql -e "SHOW VARIABLES;" > baseline_configs/$(date +%Y%m%d)/mysql_config.txt

# Document Azure configuration
az sql server show --resource-group $RG --name $SQL_SERVER > baseline_configs/$(date +%Y%m%d)/azure_sql_server_config.json
*/


-- ### SQL Server Baseline ####
-- 1. Performance Metrics Collection
-- Create baseline monitoring view
CREATE OR ALTER VIEW baseline_mssql_performance AS
SELECT
    GETDATE() as sample_time,
    -- Connection metrics
    (SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process = 1) as active_connections,
    (SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process = 1 AND status = 'running') as running_connections,
    
    -- Database statistics
    (SELECT SUM(CAST(FILEPROPERTY(name, 'SpaceUsed') AS bigint) * 8192) FROM sys.database_files WHERE type_desc = 'ROWS') as database_size_bytes,
    
    -- Transaction statistics
    (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Transactions/sec' AND object_name LIKE '%Databases%') as total_transactions_sec,
    (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Write Transactions/sec' AND object_name LIKE '%Databases%') as write_transactions_sec,
    
    -- Buffer Pool statistics
    (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Buffer cache hit ratio' AND object_name LIKE '%Buffer Manager%') as buffer_cache_hit_ratio,
    (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Page life expectancy' AND object_name LIKE '%Buffer Manager%') as page_life_expectancy,
    
    -- Cache metrics calculation
    (SELECT 
        CASE 
            WHEN b.cntr_value = 0 THEN 0
            ELSE (a.cntr_value * 1.0 / b.cntr_value) * 100.0 
        END
    FROM sys.dm_os_performance_counters a
        INNER JOIN sys.dm_os_performance_counters b ON a.object_name = b.object_name
    WHERE a.counter_name = 'Buffer cache hit ratio'
        AND b.counter_name = 'Buffer cache hit ratio base'
        AND a.object_name LIKE '%Buffer Manager%') as calculated_cache_hit_ratio,
    
    -- CPU and Wait statistics
    (SELECT AVG(signal_wait_time_ms) FROM sys.dm_os_wait_stats WHERE waiting_tasks_count > 0) as avg_signal_wait_ms,
    (SELECT TOP 1 wait_type FROM sys.dm_os_wait_stats WHERE waiting_tasks_count > 0 ORDER BY wait_time_ms DESC) as top_wait_type,
    
    -- SQL Server specific metrics
    (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Batch Requests/sec' AND object_name LIKE '%SQL Statistics%') as batch_requests_sec,
    (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'SQL Compilations/sec' AND object_name LIKE '%SQL Statistics%') as compilations_sec,
    (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'SQL Re-Compilations/sec' AND object_name LIKE '%SQL Statistics%') as recompilations_sec,
    
    -- Lock statistics
    (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Lock Waits/sec' AND object_name LIKE '%Locks%' AND instance_name = '_Total') as lock_waits_sec,
    (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Lock Timeouts/sec' AND object_name LIKE '%Locks%' AND instance_name = '_Total') as lock_timeouts_sec,
    
    -- Memory statistics
    (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Total Server Memory (KB)' AND object_name LIKE '%Memory Manager%') as total_server_memory_kb,
    (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Target Server Memory (KB)' AND object_name LIKE '%Memory Manager%') as target_server_memory_kb;

-- Baseline data collection table
CREATE TABLE IF NOT EXISTS baseline_mssql_metrics (
    sample_time DATETIME2 DEFAULT GETDATE(),
    active_connections INT,
    running_connections INT,
    database_size_bytes BIGINT,
    total_transactions_sec BIGINT,
    write_transactions_sec BIGINT,
    buffer_cache_hit_ratio DECIMAL(5,2),
    page_life_expectancy BIGINT,
    calculated_cache_hit_ratio DECIMAL(5,2),
    avg_signal_wait_ms DECIMAL(15,2),
    top_wait_type NVARCHAR(120),
    batch_requests_sec BIGINT,
    compilations_sec BIGINT,
    recompilations_sec BIGINT,
    lock_waits_sec BIGINT,
    lock_timeouts_sec BIGINT,
    total_server_memory_kb BIGINT,
    target_server_memory_kb BIGINT,
    INDEX idx_sample_time (sample_time)
);

-- Insert baseline sample (run every 5 minutes via SQL Server Agent Job)
-- INSERT INTO baseline_mssql_metrics 
-- SELECT * FROM baseline_mssql_performance;

-- Alternative: Use SQL Server Agent Job or Windows Task Scheduler to collect metrics
/*
# PowerShell script for automated collection
$query = "INSERT INTO baseline_mssql_metrics SELECT * FROM baseline_mssql_performance"
Invoke-SqlCmd -ServerInstance "YourServer" -Database "YourDatabase" -Query $query

# Create scheduled task to run every 5 minutes
schtasks /create /tn "SQL Server Baseline Collection" /tr "powershell.exe -File C:\Scripts\collect_baseline.ps1" /sc minute /mo 5
*/

-- 2. Query Performance Baseline (using Query Store for SQL Server 2016+)
-- Top queries baseline
CREATE TABLE IF NOT EXISTS baseline_mssql_queries AS
SELECT
    GETDATE() as baseline_date,
    qst.query_sql_text,
    rs.count_executions as calls,
    rs.total_duration / 1000000.0 as total_exec_time_sec,
    rs.avg_duration / 1000000.0 as mean_exec_time_sec,
    rs.total_logical_io_reads as total_logical_reads,
    rs.total_physical_io_reads as total_physical_reads,
    rs.total_cpu_time / 1000000.0 as total_cpu_time_sec,
    qsp.first_execution_time,
    qsp.last_execution_time
FROM sys.query_store_query_text qst
    INNER JOIN sys.query_store_query q ON qst.query_text_id = q.query_text_id
    INNER JOIN sys.query_store_plan qsp ON q.query_id = qsp.query_id
    INNER JOIN sys.query_store_runtime_stats rs ON qsp.plan_id = rs.plan_id
WHERE rs.count_executions > 100  -- Only frequently executed queries
    AND qst.query_sql_text NOT LIKE '%sys.%'
    AND qst.query_sql_text NOT LIKE '%INFORMATION_SCHEMA%'
    AND rs.last_execution_time > DATEADD(day, -7, GETDATE()) -- Last 7 days
    AND LEN(qst.query_sql_text) > 50 -- Filter out very short queries
ORDER BY rs.total_duration DESC;

-- Alternative for older SQL Server versions using DMVs
-- CREATE TABLE IF NOT EXISTS baseline_mssql_queries_dmv AS
-- SELECT
--     GETDATE() as baseline_date,
--     SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
--         ((CASE WHEN qs.statement_end_offset = -1
--             THEN LEN(CONVERT(nvarchar(max), st.text)) * 2
--             ELSE qs.statement_end_offset
--         END - qs.statement_start_offset)/2) + 1) AS query_text,
--     qs.execution_count as calls,
--     qs.total_elapsed_time / 1000000.0 as total_exec_time_sec,
--     qs.total_elapsed_time / qs.execution_count / 1000000.0 as mean_exec_time_sec,
--     qs.total_logical_reads,
--     qs.total_physical_reads,
--     qs.total_worker_time / 1000000.0 as total_cpu_time_sec,
--     qs.creation_time,
--     qs.last_execution_time
-- FROM sys.dm_exec_query_stats qs
--     CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
-- WHERE qs.execution_count > 100
--     AND qs.last_execution_time > DATEADD(day, -7, GETDATE())
--     AND LEN(st.text) > 50
-- ORDER BY qs.total_elapsed_time DESC;

-- Clear Query Store statistics after baseline period (if needed)
-- ALTER DATABASE CURRENT SET QUERY_STORE CLEAR;

-- 3. System Resource Baseline
/*
# SQL Server system resource baseline collection using PowerShell
# Run every 5 minutes during baseline period

$BASELINE_DIR = "C:\Logs\SQLServer\baseline"
New-Item -ItemType Directory -Force -Path $BASELINE_DIR

# CPU and Memory
$cpu = Get-WmiObject win32_processor | Measure-Object -property LoadPercentage -Average | Select Average
$mem = Get-WmiObject -Class win32_operatingsystem | Select @{Name = "MemoryUsage"; Expression = {"{0:N2}" -f ((($_.TotalVisibleMemorySize - $_.FreePhysicalMemory)*100)/ $_.TotalVisibleMemorySize) }}
"$(Get-Date),$($cpu.Average),$($mem.MemoryUsage)" | Add-Content "$BASELINE_DIR\system_metrics.csv"

# Disk I/O using Performance Counters
$diskReads = (Get-Counter "\PhysicalDisk(_Total)\Disk Reads/sec").CounterSamples.CookedValue
$diskWrites = (Get-Counter "\PhysicalDisk(_Total)\Disk Writes/sec").CounterSamples.CookedValue
"$(Get-Date),$diskReads,$diskWrites" | Add-Content "$BASELINE_DIR\disk_io.csv"

# Network connections
$connections = (Get-NetTCPConnection -LocalPort 1433 -State Established).Count
"$(Get-Date),$connections" | Add-Content "$BASELINE_DIR\network_connections.csv"

# SQL Server specific metrics
$query = @"
SELECT 
    GETDATE() as sample_time,
    counter_name, 
    cntr_value 
FROM sys.dm_os_performance_counters 
WHERE object_name LIKE '%Buffer Manager%'
    OR object_name LIKE '%Memory Manager%'
    OR object_name LIKE '%SQL Statistics%'
    OR object_name LIKE '%Locks%'
ORDER BY object_name, counter_name;
"@
Invoke-SqlCmd -ServerInstance "YourServer" -Database "YourDatabase" -Query $query | Export-Csv "$BASELINE_DIR\sql_server_counters.csv" -Append -NoTypeInformation
*/

-- ### Baseline Analysis and Reporting ####
-- 1. SQL Server baseline analysis
SELECT 
    'Baseline Analysis Report' as report_title,
    DATEADD(day, -30, GETDATE()) as analysis_period_start,
    GETDATE() as analysis_period_end;

WITH baseline_stats AS (
    SELECT
        'active_connections' as metric,
        AVG(CAST(active_connections AS FLOAT)) as avg_value,
        MIN(active_connections) as min_value,
        MAX(active_connections) as max_value,
        STDEV(CAST(active_connections AS FLOAT)) as std_dev,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY active_connections) OVER() as p95_value
    FROM baseline_mssql_metrics
    WHERE sample_time >= DATEADD(day, -30, GETDATE())

    UNION ALL

    SELECT
        'calculated_cache_hit_ratio',
        AVG(calculated_cache_hit_ratio),
        MIN(calculated_cache_hit_ratio),
        MAX(calculated_cache_hit_ratio),
        STDEV(calculated_cache_hit_ratio),
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY calculated_cache_hit_ratio) OVER()
    FROM baseline_mssql_metrics
    WHERE sample_time >= DATEADD(day, -30, GETDATE())
      AND calculated_cache_hit_ratio IS NOT NULL

    UNION ALL

    SELECT
        'batch_requests_sec',
        AVG(CAST(batch_requests_sec AS FLOAT)),
        MIN(batch_requests_sec),
        MAX(batch_requests_sec),
        STDEV(CAST(batch_requests_sec AS FLOAT)),
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY batch_requests_sec) OVER()
    FROM baseline_mssql_metrics
    WHERE sample_time >= DATEADD(day, -30, GETDATE())

    UNION ALL

    SELECT
        'running_connections',
        AVG(CAST(running_connections AS FLOAT)),
        MIN(running_connections),
        MAX(running_connections),
        STDEV(CAST(running_connections AS FLOAT)),
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY running_connections) OVER()
    FROM baseline_mssql_metrics
    WHERE sample_time >= DATEADD(day, -30, GETDATE())

    UNION ALL

    SELECT
        'page_life_expectancy',
        AVG(CAST(page_life_expectancy AS FLOAT)),
        MIN(page_life_expectancy),
        MAX(page_life_expectancy),
        STDEV(CAST(page_life_expectancy AS FLOAT)),
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY page_life_expectancy) OVER()
    FROM baseline_mssql_metrics
    WHERE sample_time >= DATEADD(day, -30, GETDATE())
)
SELECT
    metric,
    ROUND(avg_value, 2) as average,
    ROUND(min_value, 2) as minimum,
    ROUND(max_value, 2) as maximum,
    ROUND(std_dev, 2) as std_deviation,
    ROUND(p95_value, 2) as percentile_95,
    ROUND(avg_value + (2 * std_dev), 2) as upper_threshold,
    ROUND(CASE WHEN avg_value - (2 * std_dev) < 0 THEN 0 ELSE avg_value - (2 * std_dev) END, 2) as lower_threshold,
    CASE 
        WHEN metric = 'calculated_cache_hit_ratio' AND avg_value < 95 THEN 'WARNING: Low cache hit ratio'
        WHEN metric = 'active_connections' AND avg_value > 80 THEN 'WARNING: High connection usage'
        WHEN metric = 'page_life_expectancy' AND avg_value < 300 THEN 'WARNING: Low page life expectancy'
        WHEN metric = 'batch_requests_sec' AND (max_value - min_value) > (avg_value * 5) THEN 'WARNING: High batch request variance'
        ELSE 'OK'
    END as status_alert
FROM baseline_stats
ORDER BY 
    CASE metric 
        WHEN 'active_connections' THEN 1
        WHEN 'running_connections' THEN 2
        WHEN 'calculated_cache_hit_ratio' THEN 3
        WHEN 'page_life_expectancy' THEN 4
        WHEN 'batch_requests_sec' THEN 5
        ELSE 6
    END;

-- 2. Performance Trend Analysis
SELECT 
    'Performance Trend Analysis - Last 7 Days' as analysis_title;

SELECT
    FORMAT(sample_time, 'yyyy-MM-dd HH:00:00') as hour_period,
    AVG(CAST(active_connections AS FLOAT)) as avg_connections,
    AVG(CAST(running_connections AS FLOAT)) as avg_running,
    AVG(calculated_cache_hit_ratio) as avg_cache_hit_ratio,
    AVG(CAST(page_life_expectancy AS FLOAT)) as avg_page_life_expectancy,
    AVG(CAST(batch_requests_sec AS FLOAT)) as avg_batch_requests,
    COUNT(*) as sample_count
FROM baseline_mssql_metrics
WHERE sample_time >= DATEADD(day, -7, GETDATE())
GROUP BY FORMAT(sample_time, 'yyyy-MM-dd HH:00:00')
ORDER BY hour_period DESC;

-- 3. Query Performance Analysis
SELECT 
    'Top Resource-Consuming Queries' as query_analysis_title;

SELECT TOP 20
    LEFT(query_sql_text, 100) as query_preview,
    calls,
    ROUND(total_exec_time_sec, 3) as total_time_sec,
    ROUND(mean_exec_time_sec, 3) as avg_time_sec,
    total_logical_reads,
    total_physical_reads,
    ROUND(total_cpu_time_sec, 3) as total_cpu_time_sec,
    CASE 
        WHEN mean_exec_time_sec > 1 THEN 'CRITICAL: Very slow query'
        WHEN mean_exec_time_sec > 0.1 THEN 'WARNING: Slow query'
        WHEN total_physical_reads > total_logical_reads * 0.1 THEN 'WARNING: High physical reads'
        ELSE 'OK'
    END as performance_status
FROM baseline_mssql_queries
WHERE baseline_date >= DATEADD(day, -30, GETDATE())
ORDER BY total_exec_time_sec DESC;

-- 4. Connection Analysis
SELECT 
    'Connection Pattern Analysis' as connection_analysis_title;

SELECT
    DATEPART(hour, sample_time) as hour_of_day,
    AVG(CAST(active_connections AS FLOAT)) as avg_active_connections,
    MAX(active_connections) as peak_connections,
    AVG(CAST(running_connections AS FLOAT)) as avg_running_connections,
    MAX(running_connections) as peak_running_connections,
    COUNT(*) as samples
FROM baseline_mssql_metrics
WHERE sample_time >= DATEADD(day, -30, GETDATE())
GROUP BY DATEPART(hour, sample_time)
ORDER BY hour_of_day;

-- 5. Database Growth Analysis
SELECT 
    'Database Growth Analysis' as growth_analysis_title;

SELECT
    CAST(sample_time AS DATE) as date,
    MIN(database_size_bytes / 1024.0 / 1024.0 / 1024.0) as min_size_gb,
    MAX(database_size_bytes / 1024.0 / 1024.0 / 1024.0) as max_size_gb,
    (MAX(database_size_bytes) - MIN(database_size_bytes)) / 1024.0 / 1024.0 as daily_growth_mb
FROM baseline_mssql_metrics
WHERE sample_time >= DATEADD(day, -30, GETDATE())
    AND database_size_bytes IS NOT NULL
GROUP BY CAST(sample_time AS DATE)
ORDER BY date DESC;

-- ### Threshold Calculation ####
-- Calculate dynamic thresholds based on baseline data

CREATE OR ALTER FUNCTION calculate_mssql_thresholds(
    @metric_name VARCHAR(50), 
    @baseline_days INT = 30
)
RETURNS NVARCHAR(MAX)
AS
BEGIN
    DECLARE @result NVARCHAR(MAX);
    DECLARE @avg_val DECIMAL(10,2), @std_dev DECIMAL(10,2), @p95_val DECIMAL(10,2);
    
    IF @metric_name = 'active_connections'
    BEGIN
        SELECT 
            @avg_val = AVG(CAST(active_connections AS FLOAT)),
            @std_dev = STDEV(CAST(active_connections AS FLOAT)),
            @p95_val = PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY active_connections) OVER()
        FROM baseline_mssql_metrics
        WHERE sample_time >= DATEADD(day, -@baseline_days, GETDATE());
    END
    ELSE IF @metric_name = 'calculated_cache_hit_ratio'
    BEGIN
        SELECT 
            @avg_val = AVG(calculated_cache_hit_ratio),
            @std_dev = STDEV(calculated_cache_hit_ratio),
            @p95_val = PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY calculated_cache_hit_ratio) OVER()
        FROM baseline_mssql_metrics
        WHERE sample_time >= DATEADD(day, -@baseline_days, GETDATE())
          AND calculated_cache_hit_ratio IS NOT NULL;
    END
    ELSE IF @metric_name = 'page_life_expectancy'
    BEGIN
        SELECT 
            @avg_val = AVG(CAST(page_life_expectancy AS FLOAT)),
            @std_dev = STDEV(CAST(page_life_expectancy AS FLOAT)),
            @p95_val = PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY page_life_expectancy) OVER()
        FROM baseline_mssql_metrics
        WHERE sample_time >= DATEADD(day, -@baseline_days, GETDATE());
    END
    ELSE
    BEGIN
        SET @avg_val = 0;
        SET @std_dev = 0; 
        SET @p95_val = 0;
    END
    
    SET @result = CONCAT('{"metric":"', @metric_name, 
                        '","average":', ROUND(ISNULL(@avg_val, 0), 2),
                        ',"std_deviation":', ROUND(ISNULL(@std_dev, 0), 2),
                        ',"warning_threshold":', ROUND(ISNULL(@avg_val, 0) + (1.5 * ISNULL(@std_dev, 0)), 2),
                        ',"critical_threshold":', ROUND(ISNULL(@avg_val, 0) + (2.5 * ISNULL(@std_dev, 0)), 2),
                        ',"p95_threshold":', ROUND(ISNULL(@p95_val, 0), 2), '}');
    
    RETURN @result;
END;

-- Example usage
SELECT dbo.calculate_mssql_thresholds('active_connections', 30) as connection_thresholds;
SELECT dbo.calculate_mssql_thresholds('calculated_cache_hit_ratio', 30) as cache_thresholds;
SELECT dbo.calculate_mssql_thresholds('page_life_expectancy', 30) as ple_thresholds;

-- 6. Alerting Query Examples
-- Queries to identify when metrics exceed baseline thresholds

-- Current metrics vs baseline thresholds
SELECT 
    'Current Status vs Baseline Thresholds' as alert_check_title,
    GETDATE() as check_time;

WITH current_thresholds AS (
    SELECT 
        'active_connections' as metric_name,
        (SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process = 1) as current_value,
        (SELECT AVG(CAST(active_connections AS FLOAT)) FROM baseline_mssql_metrics WHERE sample_time >= DATEADD(day, -30, GETDATE())) as baseline_avg,
        (SELECT AVG(CAST(active_connections AS FLOAT)) + (1.5 * STDEV(CAST(active_connections AS FLOAT))) FROM baseline_mssql_metrics WHERE sample_time >= DATEADD(day, -30, GETDATE())) as threshold_warning,
        (SELECT AVG(CAST(active_connections AS FLOAT)) + (2.5 * STDEV(CAST(active_connections AS FLOAT))) FROM baseline_mssql_metrics WHERE sample_time >= DATEADD(day, -30, GETDATE())) as threshold_critical
        
    UNION ALL
    
    SELECT 
        'buffer_cache_hit_ratio',
        (SELECT 
            CASE 
                WHEN b.cntr_value = 0 THEN 0
                ELSE (a.cntr_value * 1.0 / b.cntr_value) * 100.0 
            END
        FROM sys.dm_os_performance_counters a
            INNER JOIN sys.dm_os_performance_counters b ON a.object_name = b.object_name
        WHERE a.counter_name = 'Buffer cache hit ratio'
            AND b.counter_name = 'Buffer cache hit ratio base'
            AND a.object_name LIKE '%Buffer Manager%'),
        (SELECT AVG(calculated_cache_hit_ratio) FROM baseline_mssql_metrics WHERE sample_time >= DATEADD(day, -30, GETDATE()) AND calculated_cache_hit_ratio IS NOT NULL),
        (SELECT AVG(calculated_cache_hit_ratio) - (1.5 * STDEV(calculated_cache_hit_ratio)) FROM baseline_mssql_metrics WHERE sample_time >= DATEADD(day, -30, GETDATE()) AND calculated_cache_hit_ratio IS NOT NULL),
        (SELECT AVG(calculated_cache_hit_ratio) - (2.5 * STDEV(calculated_cache_hit_ratio)) FROM baseline_mssql_metrics WHERE sample_time >= DATEADD(day, -30, GETDATE()) AND calculated_cache_hit_ratio IS NOT NULL)

    UNION ALL

    SELECT 
        'page_life_expectancy',
        (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Page life expectancy' AND object_name LIKE '%Buffer Manager%'),
        (SELECT AVG(CAST(page_life_expectancy AS FLOAT)) FROM baseline_mssql_metrics WHERE sample_time >= DATEADD(day, -30, GETDATE())),
        (SELECT AVG(CAST(page_life_expectancy AS FLOAT)) - (1.5 * STDEV(CAST(page_life_expectancy AS FLOAT))) FROM baseline_mssql_metrics WHERE sample_time >= DATEADD(day, -30, GETDATE())),
        (SELECT AVG(CAST(page_life_expectancy AS FLOAT)) - (2.5 * STDEV(CAST(page_life_expectancy AS FLOAT))) FROM baseline_mssql_metrics WHERE sample_time >= DATEADD(day, -30, GETDATE()))
)
SELECT
    metric_name,
    ROUND(current_value, 2) as current_value,
    ROUND(baseline_avg, 2) as baseline_avg,
    ROUND(threshold_warning, 2) as threshold_warning,
    ROUND(threshold_critical, 2) as threshold_critical,
    CASE
        WHEN metric_name = 'buffer_cache_hit_ratio' THEN
            CASE
                WHEN current_value < threshold_critical THEN 'CRITICAL'
                WHEN current_value < threshold_warning THEN 'WARNING'
                ELSE 'OK'
            END
        WHEN metric_name = 'page_life_expectancy' THEN
            CASE
                WHEN current_value < threshold_critical THEN 'CRITICAL'
                WHEN current_value < threshold_warning THEN 'WARNING'
                ELSE 'OK'
            END
        ELSE
            CASE
                WHEN current_value > threshold_critical THEN 'CRITICAL'
                WHEN current_value > threshold_warning THEN 'WARNING'
                ELSE 'OK'
            END
    END as status
FROM current_thresholds;

-- Summary Report
SELECT 
    '=== SQL Server Baseline Performance Analysis Summary ===' as summary_title,
    GETDATE() as report_generated,
    (SELECT COUNT(*) FROM baseline_mssql_metrics WHERE sample_time >= DATEADD(day, -30, GETDATE())) as total_samples_30days,
    (SELECT MIN(sample_time) FROM baseline_mssql_metrics) as oldest_sample,
    (SELECT MAX(sample_time) FROM baseline_mssql_metrics) as newest_sample,
    'Baseline analysis complete - Review thresholds and alerts above' as status;