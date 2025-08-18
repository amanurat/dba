# 📊 SQL Server Monitoring & Performance Complete Setup Guide (Azure)

> **Comprehensive Guide**: From quick Query Store setup to production-ready monitoring infrastructure on Azure SQL Database/Managed Instance

---

## 📋 **Table of Contents**

- [🚀1: Quick Start - Enable Query Store (5 minutes)](#-section-1-quick-start---enable-query-store-5-minutes)
- [⚙️2: Production Setup - Complete Configuration](#️-section-2-production-setup---complete-configuration)
- [🔧3: Advanced Features](#-section-3-advanced-features)
- [🚨4: Troubleshooting & Best Practices](#-section-4-troubleshooting--best-practices)

---

## 🚀 **Section 1: Quick Start - Enable Query Store (5 minutes)**

> สำหรับคนที่ต้องการแค่ Query Performance monitoring ให้ทำงานเร็วที่สุด

### **✅ Why Enable `Query Store`?**

| Feature | Purpose |
|--------|---------|
| `Query Store` | Captures executed SQL queries, execution plans, and runtime statistics |
| Azure SQL Insights | Visualizes performance metrics using Query Store data |
| Automatic Tuning | Uses Query Store data for automatic plan correction |

### **🔧 Essential Settings for Query Store**

| Parameter | Recommended Value |
|-----------|-------------------|
| `OPERATION_MODE` | `READ_WRITE` |
| `CLEANUP_POLICY` | `(STALE_QUERY_THRESHOLD_DAYS = 30)` |
| `DATA_FLUSH_INTERVAL_SECONDS` | `900` |
| `INTERVAL_LENGTH_MINUTES` | `60` |
| `MAX_STORAGE_SIZE_MB` | `1000` |
| `QUERY_CAPTURE_MODE` | `AUTO` |

### **⚡ Quick Setup Steps**

1. **Connect to your database** using SSMS, Azure Data Studio, or Azure Portal Query Editor
2. **Enable Query Store** with recommended settings
3. **Verify setup** with validation queries
4. **Wait 15-30 minutes** for data collection

### **🧪 Post-Setup Verification (Quick Start)**

```sql
-- Step 1: Check Query Store is enabled
SELECT 
    actual_state_desc,
    readonly_reason,
    desired_state_desc,
    current_storage_size_mb,
    max_storage_size_mb
FROM sys.database_query_store_options;
-- Expected: actual_state_desc = 'READ_WRITE'

-- Step 2: Enable Query Store (if not already enabled)
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

-- Step 3: Generate some test activity
SELECT GETDATE() AS current_time;
SELECT COUNT(*) FROM sys.tables;
SELECT TOP 10 * FROM sys.objects;

-- Step 4: Verify query tracking (wait 5-10 minutes after running queries above)
SELECT TOP 10
    qst.query_sql_text,
    qsp.plan_id,
    rs.count_executions,
    rs.avg_duration / 1000.0 AS avg_duration_ms
FROM sys.query_store_query_text qst
    INNER JOIN sys.query_store_query q ON qst.query_text_id = q.query_text_id
    INNER JOIN sys.query_store_plan qsp ON q.query_id = qsp.query_id
    INNER JOIN sys.query_store_runtime_stats rs ON qsp.plan_id = rs.plan_id
WHERE rs.last_execution_time > DATEADD(hour, -1, GETUTCDATE())
ORDER BY rs.count_executions DESC;
-- Expected: Should see your test queries above
```

### **📊 Azure Portal Verification**
1. Go to **Azure Portal** → SQL Database → **Query Performance Insight**
2. Should see query data within **15-30 minutes**
3. Check **Intelligent Insights** for automatic recommendations

### **🔄 Configuration Changes**

| Setting | Requires Restart? | Takes Effect |
|---------|-------------------|--------------|
| `OPERATION_MODE` | ❌ No | Immediately |
| `QUERY_CAPTURE_MODE` | ❌ No | Next query execution |
| `MAX_STORAGE_SIZE_MB` | ❌ No | Immediately |
| `CLEANUP_POLICY` | ❌ No | Next cleanup cycle |

---

## ⚙️ **Section 2: Production Setup - Complete Configuration**

> สำหรับ production environment ที่ต้องการ comprehensive monitoring

### **🟢 Complete Configuration Parameters**

| **Priority** | **Parameter** | **Recommended Value** | **Notes** |
|-------------|---------------|----------------------|-----------|
| **1** | **OPERATION_MODE** | **READ_WRITE** | **Enable full functionality** |
| **2** | MAX_STORAGE_SIZE_MB | 2000 | Increased for production workload |
| 3 | STALE_QUERY_THRESHOLD_DAYS | 30 | Keep 30 days of history |
| 4 | DATA_FLUSH_INTERVAL_SECONDS | 900 | Flush every 15 minutes |
| 5 | INTERVAL_LENGTH_MINUTES | 60 | 1-hour aggregation intervals |
| 6 | QUERY_CAPTURE_MODE | ALL | Capture all queries (use AUTO for high-volume) |
| 7 | SIZE_BASED_CLEANUP_MODE | AUTO | Automatic cleanup when full |
| 8 | MAX_PLANS_PER_QUERY | 200 | Increased from default 200 |

### **🔧 Production Setup Methods**

#### **Method 1: T-SQL Configuration (Recommended)**

**Step 1: Configure Query Store with Production Settings**
```sql
-- Enable Query Store with production-optimized settings
ALTER DATABASE CURRENT SET QUERY_STORE = ON 
(
    OPERATION_MODE = READ_WRITE,
    CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30),
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    INTERVAL_LENGTH_MINUTES = 60,
    MAX_STORAGE_SIZE_MB = 2000,
    QUERY_CAPTURE_MODE = AUTO,  -- Use ALL for comprehensive capture (may impact performance)
    SIZE_BASED_CLEANUP_MODE = AUTO,
    MAX_PLANS_PER_QUERY = 200
);
```

**Step 2: Enable Extended Events for Additional Monitoring**
```sql
-- Create Extended Events session for detailed monitoring
CREATE EVENT SESSION [Azure_SQL_Performance_Monitoring] ON DATABASE 
ADD EVENT sqlserver.sql_statement_completed(
    ACTION(sqlserver.client_app_name, sqlserver.database_id, sqlserver.session_id, sqlserver.sql_text)
    WHERE ([duration] > 1000000)  -- Only capture statements > 1 second
),
ADD EVENT sqlserver.rpc_completed(
    ACTION(sqlserver.client_app_name, sqlserver.database_id, sqlserver.session_id)
    WHERE ([duration] > 1000000)  -- Only capture RPCs > 1 second
)
ADD TARGET package0.ring_buffer(SET max_memory = 4096);

-- Start the session
ALTER EVENT SESSION [Azure_SQL_Performance_Monitoring] ON DATABASE STATE = START;
```

**Step 3: Configure Database Scoped Configurations**
```sql
-- Optimize for Azure SQL Database
ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 0;  -- Let Azure optimize
ALTER DATABASE SCOPED CONFIGURATION SET LEGACY_CARDINALITY_ESTIMATION = OFF;
ALTER DATABASE SCOPED CONFIGURATION SET PARAMETER_SNIFFING = ON;
ALTER DATABASE SCOPED CONFIGURATION SET QUERY_OPTIMIZER_HOTFIXES = ON;
```

### **🧪 Post-Setup Verification (Production)**

```sql
-- Step 1: Comprehensive Query Store verification
SELECT 
    'Query Store Status' AS check_type,
    actual_state_desc AS status,
    readonly_reason,
    current_storage_size_mb,
    max_storage_size_mb,
    CAST(current_storage_size_mb * 100.0 / max_storage_size_mb AS decimal(5,2)) AS storage_usage_percentage
FROM sys.database_query_store_options;

-- Step 2: Verify Extended Events session
SELECT 
    s.name AS session_name,
    s.create_time,
    CASE 
        WHEN s.startup_state = 1 THEN 'Started'
        ELSE 'Stopped'
    END AS startup_state
FROM sys.database_event_sessions s
WHERE s.name = 'Azure_SQL_Performance_Monitoring';

-- Step 3: Check database scoped configurations
SELECT 
    configuration_id,
    name,
    value,
    value_for_secondary
FROM sys.database_scoped_configurations
WHERE name IN ('MAXDOP', 'LEGACY_CARDINALITY_ESTIMATION', 'PARAMETER_SNIFFING', 'QUERY_OPTIMIZER_HOTFIXES');

-- Step 4: Test comprehensive functionality with sample workload
DECLARE @i INT = 1;
WHILE @i <= 100
BEGIN
    SELECT 
        @i AS iteration,
        GETDATE() AS execution_time,
        @@ROWCOUNT AS row_count;
    
    SELECT COUNT(*) FROM sys.objects WHERE type = 'U';
    
    SET @i = @i + 1;
END;

-- Step 5: Verify query capture (run after 10-15 minutes)
SELECT 
    'Total Queries Captured' AS metric,
    COUNT(*) AS value
FROM sys.query_store_query_text
UNION ALL
SELECT 
    'Total Execution Plans',
    COUNT(*)
FROM sys.query_store_plan
UNION ALL
SELECT 
    'Runtime Stats Records',
    COUNT(*)
FROM sys.query_store_runtime_stats;

-- Step 6: Top performing queries verification
SELECT TOP 10
    qst.query_sql_text,
    q.query_id,
    rs.count_executions,
    rs.avg_duration / 1000.0 AS avg_duration_ms,
    rs.total_duration / 1000.0 AS total_duration_ms,
    rs.avg_cpu_time / 1000.0 AS avg_cpu_time_ms
FROM sys.query_store_query_text qst
    INNER JOIN sys.query_store_query q ON qst.query_text_id = q.query_text_id
    INNER JOIN sys.query_store_plan qsp ON q.query_id = qsp.query_id
    INNER JOIN sys.query_store_runtime_stats rs ON qsp.plan_id = rs.plan_id
WHERE rs.last_execution_time > DATEADD(hour, -24, GETUTCDATE())
ORDER BY rs.total_duration DESC;
-- Expected: Comprehensive query statistics with performance metrics
```

### **📊 Production Monitoring Verification**

```sql
-- Database performance overview
SELECT 
    'Query Store Storage Usage' as metric,
    CONCAT(
        CAST(current_storage_size_mb AS varchar(10)), 
        ' MB / ', 
        CAST(max_storage_size_mb AS varchar(10)), 
        ' MB (', 
        CAST(ROUND(current_storage_size_mb * 100.0 / max_storage_size_mb, 1) AS varchar(10)),
        '%)'
    ) as value
FROM sys.database_query_store_options

UNION ALL

SELECT 
    'Total Unique Queries',
    CAST(COUNT(*) AS varchar(20))
FROM sys.query_store_query

UNION ALL

SELECT 
    'Queries Executed (Last 24h)',
    CAST(SUM(rs.count_executions) AS varchar(20))
FROM sys.query_store_runtime_stats rs
WHERE rs.last_execution_time > DATEADD(hour, -24, GETUTCDATE())

UNION ALL

SELECT 
    'Average Query Duration (ms)',
    CAST(ROUND(AVG(rs.avg_duration / 1000.0), 2) AS varchar(20))
FROM sys.query_store_runtime_stats rs
WHERE rs.last_execution_time > DATEADD(hour, -24, GETUTCDATE());
```

---

## 🔧 **Section 3: Advanced Features**

> สำหรับ enterprise environments ที่ต้องการ deep monitoring และ automatic tuning

### **🔍 Enable Automatic Tuning (Azure SQL Database)**

```sql
-- Enable automatic plan correction
ALTER DATABASE CURRENT SET AUTOMATIC_TUNING (FORCE_LAST_GOOD_PLAN = ON);

-- Check automatic tuning status
SELECT 
    name,
    desired_state_desc,
    actual_state_desc,
    reason_desc
FROM sys.database_automatic_tuning_options;
```

### **⏱️ Enable Intelligent Insights**

```sql
-- Intelligent Insights is automatically enabled for Azure SQL Database
-- Check if diagnostic logs are configured
SELECT 
    name,
    value
FROM sys.database_scoped_configurations
WHERE name LIKE '%INTELLIGENT%';

-- View automatic tuning recommendations
SELECT 
    reason,
    score,
    details.value('(/@implementationDetails)[1]', 'nvarchar(4000)') as implementation_details,
    state.value('(/@currentValue)[1]', 'nvarchar(4000)') as current_value,
    state.value('(/@desiredValue)[1]', 'nvarchar(4000)') as desired_value
FROM sys.dm_db_tuning_recommendations
CROSS APPLY details.nodes('/tuningRecommendation/details') AS details_table(details)
CROSS APPLY state.nodes('/tuningRecommendation/state') AS state_table(state);
```

### **📈 Advanced Wait Statistics Analysis**

```sql
-- Enable wait statistics collection
-- This is automatically available in Azure SQL Database

-- Create custom views for wait analysis
CREATE OR ALTER VIEW vw_wait_stats_analysis AS
SELECT 
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    max_wait_time_ms,
    signal_wait_time_ms,
    CAST(100.0 * wait_time_ms / SUM(wait_time_ms) OVER() AS decimal(5,2)) AS percentage,
    CAST(wait_time_ms / waiting_tasks_count AS decimal(15,2)) AS avg_wait_time_ms
FROM sys.dm_os_wait_stats
WHERE waiting_tasks_count > 0
    AND wait_type NOT IN (
        'CLR_SEMAPHORE', 'LAZYWRITER_SLEEP', 'RESOURCE_QUEUE', 'SLEEP_TASK',
        'SLEEP_SYSTEMTASK', 'SQLTRACE_WAIT_ENTRIES', 'WAITFOR', 'BROKER_EVENTHANDLER'
    );
```

### **🔧 Memory and Resource Monitoring**

```sql
-- Create views for resource monitoring
CREATE OR ALTER VIEW vw_resource_stats AS
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
WHERE end_time > DATEADD(hour, -24, GETUTCDATE());

-- Memory usage breakdown
CREATE OR ALTER VIEW vw_memory_usage AS
SELECT 
    type AS memory_type,
    SUM(single_pages_kb + multi_pages_kb) AS total_memory_kb
FROM sys.dm_os_memory_clerks
GROUP BY type
HAVING SUM(single_pages_kb + multi_pages_kb) > 1024;  -- Only show > 1MB
```

### **🧪 Post-Setup Verification (Advanced Features)**

```sql
-- Step 1: Verify automatic tuning
SELECT 
    'Automatic Tuning Status' AS feature,
    STRING_AGG(
        CONCAT(name, ': ', actual_state_desc), 
        ', '
    ) AS status
FROM sys.database_automatic_tuning_options;

-- Step 2: Check custom views
SELECT 'Wait Stats View' AS view_name, COUNT(*) AS record_count
FROM vw_wait_stats_analysis
UNION ALL
SELECT 'Resource Stats View', COUNT(*)
FROM vw_resource_stats
UNION ALL
SELECT 'Memory Usage View', COUNT(*)
FROM vw_memory_usage;

-- Step 3: Advanced performance analysis
SELECT TOP 5
    wait_type,
    percentage,
    avg_wait_time_ms
FROM vw_wait_stats_analysis
ORDER BY percentage DESC;

-- Step 4: Resource utilization trends
SELECT 
    DATEPART(hour, end_time) AS hour_of_day,
    AVG(avg_cpu_percent) AS avg_cpu,
    AVG(avg_data_io_percent) AS avg_io,
    AVG(avg_memory_usage_percent) AS avg_memory
FROM vw_resource_stats
GROUP BY DATEPART(hour, end_time)
ORDER BY hour_of_day;
```

---

## 🚨 **Section 4: Troubleshooting & Best Practices**

> Common issues และวิธีแก้ปัญหาทั้งหมดที่พบบ่อย

### **🔍 Common Issues and Solutions**

#### **Issue 1: Query Store Not Collecting Data**

**Symptoms:**
```sql
SELECT actual_state_desc FROM sys.database_query_store_options;
-- Returns: 'READ_ONLY' or 'OFF'
```

**Diagnostic Commands:**
```sql
-- Check Query Store status and reasons
SELECT 
    actual_state_desc,
    readonly_reason,
    current_storage_size_mb,
    max_storage_size_mb
FROM sys.database_query_store_options;

-- Check for storage issues
SELECT 
    CASE 
        WHEN current_storage_size_mb >= max_storage_size_mb * 0.9 THEN 'Storage Almost Full'
        WHEN readonly_reason > 0 THEN 'Read-Only Mode Active'
        ELSE 'Normal'
    END AS status_analysis
FROM sys.database_query_store_options;
```

**Solution Steps:**
1. Check if storage is full and increase MAX_STORAGE_SIZE_MB
2. Enable auto-cleanup if not already enabled
3. Clear old data if necessary

**Solution Queries:**
```sql
-- Increase storage size
ALTER DATABASE CURRENT SET QUERY_STORE (MAX_STORAGE_SIZE_MB = 2000);

-- Enable auto cleanup
ALTER DATABASE CURRENT SET QUERY_STORE (SIZE_BASED_CLEANUP_MODE = AUTO);

-- Manual cleanup (if needed)
ALTER DATABASE CURRENT SET QUERY_STORE CLEAR;
```

**Verification:**
```sql
-- Should show READ_WRITE after fix
SELECT actual_state_desc, readonly_reason 
FROM sys.database_query_store_options;
```

#### **Issue 2: Poor Query Store Performance Impact**

**Symptoms:**
- Database performance degraded after enabling Query Store
- High CPU usage related to Query Store operations

**Diagnostic Commands:**
```sql
-- Check Query Store overhead
SELECT 
    query_capture_mode_desc,
    size_based_cleanup_mode_desc,
    current_storage_size_mb,
    flush_interval_seconds
FROM sys.database_query_store_options;

-- Check capture mode impact
SELECT 
    COUNT(*) AS total_queries_captured,
    COUNT(CASE WHEN q.last_execution_time > DATEADD(hour, -1, GETUTCDATE()) THEN 1 END) AS recent_queries
FROM sys.query_store_query q;
```

**Solution Steps:**
1. Change QUERY_CAPTURE_MODE from ALL to AUTO
2. Increase DATA_FLUSH_INTERVAL_SECONDS
3. Reduce MAX_STORAGE_SIZE_MB if too large

**Solution Queries:**
```sql
-- Optimize Query Store for performance
ALTER DATABASE CURRENT SET QUERY_STORE 
(
    QUERY_CAPTURE_MODE = AUTO,  -- Changed from ALL
    DATA_FLUSH_INTERVAL_SECONDS = 1800,  -- Increased to 30 minutes
    MAX_STORAGE_SIZE_MB = 1000  -- Reduced if was larger
);
```

#### **Issue 3: Missing Query Performance Insights in Azure Portal**

**Symptoms:**
- Query Store enabled but no data in Azure Portal
- Performance recommendations not appearing

**Diagnostic Commands:**
```sql
-- Check if there's sufficient query activity
SELECT 
    COUNT(*) AS total_queries,
    COUNT(CASE WHEN rs.last_execution_time > DATEADD(hour, -24, GETUTCDATE()) THEN 1 END) AS queries_last_24h,
    MAX(rs.last_execution_time) AS latest_execution
FROM sys.query_store_runtime_stats rs;

-- Check for performance issues
SELECT TOP 5
    qst.query_sql_text,
    rs.avg_duration / 1000.0 AS avg_duration_ms,
    rs.count_executions
FROM sys.query_store_query_text qst
    INNER JOIN sys.query_store_query q ON qst.query_text_id = q.query_text_id
    INNER JOIN sys.query_store_plan qsp ON q.query_id = qsp.query_id
    INNER JOIN sys.query_store_runtime_stats rs ON qsp.plan_id = rs.plan_id
WHERE rs.last_execution_time > DATEADD(hour, -24, GETUTCDATE())
    AND rs.avg_duration > 50000  -- > 50ms
ORDER BY rs.avg_duration DESC;
```

**Solution Steps:**
1. Wait 2-4 hours for data to appear in Azure Portal
2. Ensure there's sufficient query activity
3. Check Azure Monitor configuration

**Verification:**
```sql
-- Generate test workload for Portal visibility
DECLARE @counter INT = 0;
WHILE @counter < 50
BEGIN
    SELECT 
        @counter AS iteration,
        COUNT(*) AS table_count 
    FROM sys.tables
    WHERE create_date > DATEADD(day, -30, GETDATE());
    
    SELECT 
        name,
        create_date
    FROM sys.tables
    WHERE type = 'U'
    ORDER BY create_date DESC;
    
    SET @counter = @counter + 1;
END;
```

### **🎯 Best Practices Summary**

#### **✅ Do's**

- **Start with AUTO capture mode** then move to ALL if needed
- **Monitor storage usage** regularly and set appropriate limits
- **Use automatic cleanup** to prevent storage issues
- **Enable automatic tuning** for Azure SQL Database
- **Set up alerts** for Query Store storage usage
- **Regular maintenance** - check Query Store health weekly
- **Combine with Azure Monitor** for comprehensive monitoring

#### **❌ Don'ts**

- **Don't use ALL capture mode** without understanding the impact
- **Don't ignore storage warnings** - can cause read-only mode
- **Don't disable Query Store** without backup monitoring
- **Don't manually clear Query Store** frequently in production
- **Don't set storage too low** for production workloads
- **Don't forget to test** configuration changes in non-production first

### **📊 Final Verification Checklist**

Use this checklist after completing any section:

```sql
-- ✅ Complete System Health Check
SELECT 
    'Query Store Status' as check_type,
    CASE 
        WHEN actual_state_desc = 'READ_WRITE' THEN '✅ ENABLED'
        WHEN actual_state_desc = 'READ_ONLY' THEN '⚠️ READ_ONLY'
        ELSE '❌ DISABLED'
    END as status,
    CONCAT(
        CAST(current_storage_size_mb AS varchar(10)), 
        ' / ', 
        CAST(max_storage_size_mb AS varchar(10)), 
        ' MB'
    ) as storage_usage
FROM sys.database_query_store_options

UNION ALL

SELECT 
    'Data Collection',
    CASE 
        WHEN COUNT(*) > 0 THEN '✅ ACTIVE'
        ELSE '❌ NO DATA'
    END,
    CONCAT(CAST(COUNT(*) AS varchar(10)), ' queries captured')
FROM sys.query_store_query
WHERE last_execution_time > DATEADD(hour, -24, GETUTCDATE())

UNION ALL

SELECT 
    'Automatic Tuning',
    CASE 
        WHEN COUNT(CASE WHEN actual_state_desc = 'ON' THEN 1 END) > 0 THEN '✅ ENABLED'
        ELSE '⚠️ DISABLED'
    END,
    STRING_AGG(CONCAT(name, ': ', actual_state_desc), ', ')
FROM sys.database_automatic_tuning_options;
```

**Expected Result:**
```
check_type          | status        | storage_usage
--------------------|---------------|---------------------------
Query Store Status  | ✅ ENABLED    | 45 / 2000 MB
Data Collection     | ✅ ACTIVE     | 1247 queries captured
Automatic Tuning    | ✅ ENABLED    | FORCE_LAST_GOOD_PLAN: ON
```

### **🔧 Useful Azure CLI Commands**

```bash
# Check database status
az sql db show \
  --resource-group myResourceGroup \
  --server myServer \
  --name myDatabase

# Get performance metrics
az monitor metrics list \
  --resource /subscriptions/{subscription-id}/resourceGroups/{resource-group}/providers/Microsoft.Sql/servers/{server}/databases/{database} \
  --metric "cpu_percent,dtu_consumption_percent" \
  --interval PT1M

# Configure diagnostic settings
az monitor diagnostic-settings create \
  --resource /subscriptions/{subscription-id}/resourceGroups/{resource-group}/providers/Microsoft.Sql/servers/{server}/databases/{database} \
  --name "SQLDatabaseDiagnostics" \
  --logs '[{"category":"QueryStoreRuntimeStatistics","enabled":true},{"category":"QueryStoreWaitStatistics","enabled":true}]' \
  --workspace /subscriptions/{subscription-id}/resourceGroups/{resource-group}/providers/Microsoft.OperationalInsights/workspaces/{workspace}
```

---

## 📚 **Resources and References**

### **Official Azure Documentation**
- [Azure SQL Database Query Store](https://docs.microsoft.com/en-us/azure/azure-sql/database/query-store-settings)
- [Automatic Tuning](https://docs.microsoft.com/en-us/azure/azure-sql/database/automatic-tuning-overview)
- [Intelligent Insights](https://docs.microsoft.com/en-us/azure/azure-sql/database/intelligent-insights-overview)

### **SQL Server Documentation**
- [Query Store Overview](https://docs.microsoft.com/en-us/sql/relational-databases/performance/query-store-overview)
- [Extended Events](https://docs.microsoft.com/en-us/sql/relational-databases/extended-events/extended-events)
- [Wait Statistics](https://docs.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-os-wait-stats-transact-sql)

---

## 🎯 **Quick Reference Cards**

### **Essential Monitoring Queries**

```sql
-- Top 5 slowest queries
SELECT TOP 5
    qst.query_sql_text,
    rs.avg_duration / 1000.0 AS avg_duration_ms,
    rs.count_executions
FROM sys.query_store_query_text qst
    INNER JOIN sys.query_store_query q ON qst.query_text_id = q.query_text_id
    INNER JOIN sys.query_store_plan qsp ON q.query_id = qsp.query_id
    INNER JOIN sys.query_store_runtime_stats rs ON qsp.plan_id = rs.plan_id
ORDER BY rs.avg_duration DESC;

-- Current wait statistics
SELECT TOP 10
    wait_type,
    CAST(100.0 * wait_time_ms / SUM(wait_time_ms) OVER() AS decimal(5,2)) AS percentage,
    CAST(wait_time_ms / waiting_tasks_count AS decimal(15,2)) AS avg_wait_ms
FROM sys.dm_os_wait_stats
WHERE waiting_tasks_count > 0
ORDER BY wait_time_ms DESC;

-- Resource utilization (last hour)
SELECT 
    end_time,
    avg_cpu_percent,
    avg_data_io_percent,
    avg_memory_usage_percent
FROM sys.dm_db_resource_stats
WHERE end_time > DATEADD(hour, -1, GETUTCDATE())
ORDER BY end_time DESC;
```

### **Maintenance Commands**

```sql
-- Check Query Store health
SELECT 
    actual_state_desc,
    CAST(current_storage_size_mb * 100.0 / max_storage_size_mb AS decimal(5,2)) AS storage_usage_percent
FROM sys.database_query_store_options;

-- Clean up old data (use carefully)
-- ALTER DATABASE CURRENT SET QUERY_STORE CLEAR;

-- Reset wait statistics (use for baseline measurements)
-- DBCC SQLPERF('sys.dm_os_wait_stats', CLEAR);
```

---

**🎉 SQL Server Monitoring Setup เสร็จสิ้น!**

ตอนนี้คุณมีระบบ monitoring ที่ครบครันสำหรับ SQL Server บน Azure แล้ว ระบบนี้จะช่วยให้คุณติดตามประสิทธิภาพ หาปัญหา และปรับปรุง database ได้อย่างมีประสิทธิภาพ

**💡 จำไว้: การ Monitor ที่ดี = การแก้ปัญหาที่รวดเร็ว = ระบบที่เสถียร**