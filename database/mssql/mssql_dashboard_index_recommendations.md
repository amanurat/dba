# 📊 SQL Server Dashboard: Index Recommendations & Performance Monitoring

> จุดประสงค์: ช่วยให้ Dev/DBA เห็นว่า query ใดในระบบควรใช้ index แต่ยังไม่มี index ที่เหมาะสม พร้อม integration กับ Azure

---

## 🧭 Dashboard Section 1: Missing Index Recommendations

```sql
-- หา Index ที่ขาดหายไปและมี impact สูง
SELECT TOP 20
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

📌 ใช้แสดงเป็น Data Grid พร้อม:
- **Improvement Measure** เรียงจากมากไปน้อย
- **Ready-to-use CREATE INDEX** statements  
- **Priority color coding** ตาม impact level
- **One-click execute** functionality

---

## 📈 Dashboard Section 2: Top Slow Queries from Query Store

```sql
-- Top 10 Query ช้าจาก Query Store
SELECT TOP 10
    qst.query_sql_text,
    qsp.plan_id,
    rs.count_executions,
    ROUND(rs.avg_duration / 1000.0, 2) AS avg_duration_ms,
    ROUND(rs.max_duration / 1000.0, 2) AS max_duration_ms,
    ROUND(rs.total_duration / 1000.0, 2) AS total_duration_ms,
    ROUND(rs.avg_cpu_time / 1000.0, 2) AS avg_cpu_time_ms,
    rs.avg_logical_io_reads,
    rs.avg_physical_io_reads,
    ROUND((rs.total_duration / 1000.0) / NULLIF(
        (SELECT SUM(rsx.total_duration) FROM sys.query_store_runtime_stats rsx 
         WHERE rsx.last_execution_time > DATEADD(hour, -24, GETUTCDATE())), 0
    ) * 100, 2) AS percentage_of_total_time,
    rs.last_execution_time,
    CASE 
        WHEN rs.avg_duration > 5000000 THEN '🔴 Critical'  -- > 5 seconds
        WHEN rs.avg_duration > 1000000 THEN '🟠 High'     -- > 1 second  
        WHEN rs.avg_duration > 200000 THEN '🟡 Medium'    -- > 200ms
        ELSE '🟢 Low'
    END AS priority_level
FROM sys.query_store_query_text qst
    INNER JOIN sys.query_store_query q ON qst.query_text_id = q.query_text_id
    INNER JOIN sys.query_store_plan qsp ON q.query_id = qsp.query_id
    INNER JOIN sys.query_store_runtime_stats rs ON qsp.plan_id = rs.plan_id
WHERE rs.last_execution_time > DATEADD(hour, -24, GETUTCDATE())
    AND qst.query_sql_text NOT LIKE '%sys.%'
    AND qst.query_sql_text NOT LIKE '%INFORMATION_SCHEMA%'
ORDER BY rs.avg_duration DESC;
```

📌 ใช้แสดงเป็น Interactive Table พร้อม:
- **Query text preview** (expandable)
- **Performance metrics** with trend arrows
- **Priority indicators** แบบสี
- **Drill-down** ไปดู execution plan

---

## 🔍 Dashboard Section 3: Index Usage Statistics

```sql
-- วิเคราะห์การใช้งาน Index
SELECT 
    OBJECT_SCHEMA_NAME(ius.object_id) AS schema_name,
    OBJECT_NAME(ius.object_id) AS table_name,
    i.name AS index_name,
    i.type_desc AS index_type,
    ius.user_seeks + ius.user_scans + ius.user_lookups AS total_reads,
    ius.user_updates,
    CASE 
        WHEN (ius.user_seeks + ius.user_scans + ius.user_lookups) = 0 THEN '🔴 Unused'
        WHEN (ius.user_seeks + ius.user_scans + ius.user_lookups) < 10 THEN '🟡 Low Usage'
        WHEN ius.user_updates > (ius.user_seeks + ius.user_scans + ius.user_lookups) * 2 THEN '🟠 High Maintenance'
        ELSE '🟢 Good'
    END AS usage_status,
    CAST((8.0 * SUM(a.used_pages)) / 1024 AS decimal(15,2)) AS index_size_mb,
    ius.last_user_seek,
    ius.last_user_scan,
    ius.last_user_lookup,
    ius.last_user_update,
    CASE 
        WHEN i.is_primary_key = 1 THEN 'Primary Key - Keep'
        WHEN i.is_unique_constraint = 1 THEN 'Unique Constraint - Keep'
        WHEN (ius.user_seeks + ius.user_scans + ius.user_lookups) = 0 
             AND ius.last_user_update > DATEADD(day, -30, GETDATE()) THEN 'Consider Dropping'
        WHEN ius.user_updates > (ius.user_seeks + ius.user_scans + ius.user_lookups) * 5 THEN 'Review Necessity'
        ELSE 'Keep'
    END AS recommendation
FROM sys.indexes i
    INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
    INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
    LEFT JOIN sys.dm_db_index_usage_stats ius ON i.object_id = ius.object_id 
        AND i.index_id = ius.index_id AND ius.database_id = DB_ID()
WHERE OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
    AND i.index_id > 0  -- ไม่รวม heap
GROUP BY i.object_id, i.index_id, i.name, i.type_desc, i.is_primary_key, i.is_unique_constraint,
         ius.user_seeks, ius.user_scans, ius.user_lookups, ius.user_updates,
         ius.last_user_seek, ius.last_user_scan, ius.last_user_lookup, ius.last_user_update
ORDER BY 
    CASE usage_status 
        WHEN '🔴 Unused' THEN 1
        WHEN '🟠 High Maintenance' THEN 2
        WHEN '🟡 Low Usage' THEN 3
        ELSE 4
    END,
    index_size_mb DESC;
```

📌 แสดงเป็น Sortable Grid พร้อม:
- **Usage heat map** visualization
- **Size indicators** 
- **Action recommendations**
- **Last access timestamps**

---

## ⚠️ Dashboard Section 4: Database Health Overview

```sql
-- ภาพรวมสุขภาพ Database สำหรับ Azure SQL Database
SELECT 
    'Database Size' AS metric,
    CAST(SUM(CAST(FILEPROPERTY(name, 'SpaceUsed') AS bigint) * 8192.) / 1024 / 1024 AS decimal(15,2)) AS value_mb,
    'MB' AS unit,
    CASE 
        WHEN SUM(CAST(FILEPROPERTY(name, 'SpaceUsed') AS bigint) * 8192.) / 1024 / 1024 > 50000 THEN '🟠 Large'
        WHEN SUM(CAST(FILEPROPERTY(name, 'SpaceUsed') AS bigint) * 8192.) / 1024 / 1024 > 10000 THEN '🟡 Medium'
        ELSE '🟢 Small'
    END AS status
FROM sys.database_files
WHERE type_desc = 'ROWS'

UNION ALL

SELECT 
    'Total Tables',
    COUNT(*),
    'count',
    CASE 
        WHEN COUNT(*) > 500 THEN '🟠 Many'
        WHEN COUNT(*) > 100 THEN '🟡 Medium'
        ELSE '🟢 Few'
    END
FROM sys.tables

UNION ALL

SELECT 
    'Total Indexes',
    COUNT(*),
    'count',
    CASE 
        WHEN COUNT(*) > 2000 THEN '🟠 Many'
        WHEN COUNT(*) > 500 THEN '🟡 Medium'
        ELSE '🟢 Few'
    END
FROM sys.indexes
WHERE index_id > 0

UNION ALL

SELECT 
    'Unused Indexes',
    COUNT(*),
    'count',
    CASE 
        WHEN COUNT(*) > 50 THEN '🔴 Too Many'
        WHEN COUNT(*) > 20 THEN '🟠 Many'
        WHEN COUNT(*) > 5 THEN '🟡 Some'
        ELSE '🟢 Few'
    END
FROM sys.indexes i
    LEFT JOIN sys.dm_db_index_usage_stats ius ON i.object_id = ius.object_id 
        AND i.index_id = ius.index_id AND ius.database_id = DB_ID()
WHERE OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
    AND i.index_id > 0
    AND i.is_primary_key = 0
    AND i.is_unique_constraint = 0
    AND (ius.user_seeks IS NULL OR ius.user_seeks = 0)
    AND (ius.user_scans IS NULL OR ius.user_scans = 0)
    AND (ius.user_lookups IS NULL OR ius.user_lookups = 0);
```

---

## 🚀 Dashboard Section 5: Query Store Health & Configuration

```sql
-- สถานะ Query Store และการใช้งาน
SELECT 
    'Query Store Status' AS metric,
    actual_state_desc AS value,
    CASE actual_state_desc
        WHEN 'READ_WRITE' THEN '🟢 Healthy'
        WHEN 'READ_ONLY' THEN '🟡 Read Only'
        ELSE '🔴 Issue'
    END AS status,
    readonly_reason,
    current_storage_size_mb,
    max_storage_size_mb,
    CAST(current_storage_size_mb * 100.0 / max_storage_size_mb AS decimal(5,2)) AS storage_usage_percent
FROM sys.database_query_store_options

UNION ALL

SELECT 
    'Total Queries Captured',
    CAST(COUNT(*) AS nvarchar(50)),
    CASE 
        WHEN COUNT(*) > 10000 THEN '🟢 Active'
        WHEN COUNT(*) > 1000 THEN '🟡 Moderate'
        ELSE '🟠 Low Activity'
    END,
    '',
    NULL,
    NULL,
    NULL
FROM sys.query_store_query

UNION ALL

SELECT 
    'Plans in Store',
    CAST(COUNT(*) AS nvarchar(50)),
    CASE 
        WHEN COUNT(*) > 5000 THEN '🟢 Active'
        WHEN COUNT(*) > 500 THEN '🟡 Moderate'
        ELSE '🟠 Low Activity'
    END,
    '',
    NULL,
    NULL,
    NULL
FROM sys.query_store_plan;
```

---

## 📊 Dashboard Section 6: Wait Statistics Analysis

```sql
-- Top Wait Types ที่บ่งบอกปัญหา Performance
SELECT TOP 15
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    max_wait_time_ms,
    signal_wait_time_ms,
    CAST(100.0 * wait_time_ms / SUM(wait_time_ms) OVER() AS decimal(5,2)) AS percentage,
    CAST(wait_time_ms / waiting_tasks_count AS decimal(15,2)) AS avg_wait_time_ms,
    CASE 
        WHEN wait_type LIKE 'PAGEIOLATCH%' THEN '💽 I/O Bottleneck'
        WHEN wait_type LIKE 'LCK_%' THEN '🔒 Locking Issue'
        WHEN wait_type LIKE 'PAGELATCH%' THEN '⚡ Memory Pressure'
        WHEN wait_type LIKE 'CXPACKET%' THEN '🔄 Parallelism Issue'
        WHEN wait_type = 'SOS_SCHEDULER_YIELD' THEN '🖥️ CPU Pressure'
        WHEN wait_type LIKE 'WRITELOG%' THEN '📝 Log I/O Issue'
        ELSE '❓ Other'
    END AS wait_category,
    CASE 
        WHEN CAST(100.0 * wait_time_ms / SUM(wait_time_ms) OVER() AS decimal(5,2)) > 20 THEN '🔴 Critical'
        WHEN CAST(100.0 * wait_time_ms / SUM(wait_time_ms) OVER() AS decimal(5,2)) > 10 THEN '🟠 High'
        WHEN CAST(100.0 * wait_time_ms / SUM(wait_time_ms) OVER() AS decimal(5,2)) > 5 THEN '🟡 Medium'
        ELSE '🟢 Low'
    END AS priority
FROM sys.dm_os_wait_stats
WHERE waiting_tasks_count > 0
    AND wait_type NOT IN (
        'CLR_SEMAPHORE', 'LAZYWRITER_SLEEP', 'RESOURCE_QUEUE', 'SLEEP_TASK',
        'SLEEP_SYSTEMTASK', 'SQLTRACE_WAIT_ENTRIES', 'WAITFOR', 'BROKER_EVENTHANDLER',
        'CHECKPOINT_QUEUE', 'REQUEST_FOR_DEADLOCK_SEARCH', 'XE_TIMER_EVENT'
    )
ORDER BY wait_time_ms DESC;
```

---

## 🎯 Dashboard View Design

### 📊 แผงควบคุมหลัก (Main Dashboard Layout):

```
┌─────────────────┬─────────────────┬─────────────────┐
│   🏥 Health     │   📈 Performance │   🔍 Analysis   │
│   Overview      │   Metrics       │   Tools         │
│                 │                 │                 │
│ • DB Size       │ • Top Slow      │ • Missing Index │
│ • Index Count   │   Queries       │ • Usage Stats   │
│ • QS Status     │ • Wait Stats    │ • Recommendations│
└─────────────────┴─────────────────┴─────────────────┘
┌─────────────────────────────────────────────────────┐
│              📋 Action Items & Alerts              │
│                                                     │
│ • High-impact missing indexes                      │
│ • Unused indexes (candidates for removal)          │
│ • Query Store storage warnings                     │
│ • Performance regression alerts                    │
└─────────────────────────────────────────────────────┘
```

### 🎨 Color Coding System:
- 🟢 **Green**: Good performance / Low priority
- 🟡 **Yellow**: Warning / Medium priority  
- 🟠 **Orange**: Attention needed / High priority
- 🔴 **Red**: Critical issue / Immediate action

---

## 🛠 Tools & Platforms สำหรับ Dashboard

### 🏆 **Recommended for Azure SQL Database:**

| Platform | Azure Integration | Pros | Cons | Best For |
|----------|-------------------|------|------|----------|
| **Power BI** | ✅ Native | Rich visualizations, Azure AD integration | Cost for Pro licenses | Executive dashboards |
| **Azure Workbooks** | ✅ Perfect | Free, native integration, ARM templates | Limited customization | Technical monitoring |
| **Grafana** | 🟡 Good | Open source, highly customizable | Requires ODBC setup | DevOps teams |
| **SSRS** | 🟡 Partial | SQL Server native, parameterized reports | Limited modern UI | Traditional reporting |
| **Azure Data Studio** | ✅ Good | Free, cross-platform, extensions | Not web-based | Developer workstations |

### 🔧 **Implementation Examples:**

#### Azure Workbooks Template:
```json
{
    "version": "Notebook/1.0",
    "items": [
        {
            "type": 3,
            "content": {
                "version": "KqlItem/1.0",
                "query": "AzureDiagnostics\n| where Category == \"QueryStoreRuntimeStatistics\"\n| where TimeGenerated > ago(24h)\n| summarize AvgDuration = avg(avg_duration_d) by query_hash_s\n| order by AvgDuration desc\n| limit 10",
                "size": 0,
                "title": "Top 10 Slowest Queries (24h)",
                "queryType": 0,
                "visualization": "table"
            }
        }
    ]
}
```

#### Power BI Connection:
```sql
-- Create view for Power BI consumption
CREATE VIEW vw_PowerBI_MissingIndexes AS
SELECT 
    improvement_measure,
    table_name,
    equality_columns,
    inequality_columns,
    included_columns,
    user_seeks + user_scans AS total_requests,
    avg_user_impact,
    create_index_statement,
    GETDATE() AS last_updated
FROM (
    -- Missing index query from Section 1
    -- ... (previous missing index query)
) mi
WHERE improvement_measure > 50;  -- Only significant recommendations
```

---

## 🚨 Automated Alerting Configuration

### Critical Alerts:
```sql
-- Stored Procedure สำหรับ Alert Detection
CREATE PROCEDURE sp_DetectPerformanceIssues
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @alerts TABLE (
        alert_type NVARCHAR(50),
        severity NVARCHAR(20),
        message NVARCHAR(500),
        recommendation NVARCHAR(1000)
    );
    
    -- Alert 1: Query Store storage > 90%
    INSERT INTO @alerts
    SELECT 
        'Query Store Storage',
        'Critical',
        'Query Store storage usage: ' + CAST(CAST(current_storage_size_mb * 100.0 / max_storage_size_mb AS int) AS nvarchar(10)) + '%',
        'Increase MAX_STORAGE_SIZE_MB or enable auto-cleanup'
    FROM sys.database_query_store_options
    WHERE current_storage_size_mb * 100.0 / max_storage_size_mb > 90;
    
    -- Alert 2: High-impact missing indexes
    INSERT INTO @alerts
    SELECT 
        'Missing Index',
        'High',
        'High-impact missing index on table: ' + OBJECT_NAME(mid.object_id),
        'Consider creating index: ' + ISNULL(mid.equality_columns, '') + 
        CASE WHEN mid.inequality_columns IS NOT NULL THEN ', ' + mid.inequality_columns ELSE '' END
    FROM sys.dm_db_missing_index_groups mig
        INNER JOIN sys.dm_db_missing_index_group_stats migs ON migs.group_handle = mig.index_group_handle
        INNER JOIN sys.dm_db_missing_index_details mid ON mig.index_handle = mid.index_handle
    WHERE migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans) > 100
        AND mid.database_id = DB_ID();
    
    -- Alert 3: Queries with significant regression
    INSERT INTO @alerts
    SELECT 
        'Query Regression',
        'Medium',
        'Query performance regression detected',
        'Review Query Store for plan forcing opportunities'
    FROM sys.dm_db_tuning_recommendations
    WHERE reason = 'PlanRegression'
        AND score > 80;
    
    -- Return all alerts
    SELECT 
        alert_type,
        severity,
        message,
        recommendation,
        GETDATE() AS alert_time
    FROM @alerts
    ORDER BY 
        CASE severity 
            WHEN 'Critical' THEN 1
            WHEN 'High' THEN 2
            WHEN 'Medium' THEN 3
            ELSE 4
        END;
END;
```

### Azure Logic App Integration:
```json
{
    "definition": {
        "triggers": {
            "Recurrence": {
                "recurrence": {
                    "frequency": "Hour",
                    "interval": 1
                },
                "type": "Recurrence"
            }
        },
        "actions": {
            "Execute_SQL_Query": {
                "type": "ApiConnection",
                "inputs": {
                    "host": {
                        "connection": {
                            "name": "@parameters('$connections')['sql']['connectionId']"
                        }
                    },
                    "method": "post",
                    "body": {
                        "query": "EXEC sp_DetectPerformanceIssues"
                    },
                    "path": "/datasets/@{encodeURIComponent(encodeURIComponent('your-server'))},@{encodeURIComponent(encodeURIComponent('your-database'))}/query/sql"
                }
            }
        }
    }
}
```

---

## 📅 Refresh Schedule Recommendations

| Dashboard Component | Refresh Frequency | Reason | Resource Impact |
|---------------------|-------------------|---------|------------------|
| **Missing Indexes** | Every 30 minutes | Index needs change frequently | Low |
| **Slow Queries** | Every 5 minutes | Real-time performance monitoring | Medium |
| **Index Usage** | Every hour | Usage patterns are stable | Low |
| **Wait Statistics** | Every 15 minutes | Helps identify bottlenecks quickly | Medium |
| **Health Overview** | Every hour | Baseline metrics change slowly | Low |
| **Query Store Stats** | Every 30 minutes | Storage monitoring important | Low |

---

## 🔗 Integration with Azure Services

### Azure Monitor Integration:
```sql
-- Configure diagnostic settings via T-SQL (Azure SQL Database)
-- Enable Query Store data export to Log Analytics

-- Sample KQL queries for Azure Monitor
AzureDiagnostics
| where Category == "QueryStoreRuntimeStatistics"
| where TimeGenerated > ago(1h)
| summarize AvgDuration = avg(avg_duration_d), 
           MaxDuration = max(max_duration_d),
           ExecutionCount = sum(count_executions_d) 
  by query_hash_s
| order by AvgDuration desc
| limit 20
```

### Azure Automation Integration:
```powershell
# PowerShell script สำหรับ Azure Automation
param(
    [string]$ServerName,
    [string]$DatabaseName
)

$connectionString = "Server=$ServerName;Database=$DatabaseName;Integrated Security=true;"
$query = "EXEC sp_DetectPerformanceIssues"

$results = Invoke-Sqlcmd -ConnectionString $connectionString -Query $query

foreach ($alert in $results) {
    if ($alert.severity -eq "Critical") {
        # Send Teams notification
        Send-TeamsNotification -Message $alert.message -Webhook $env:TeamsWebhook
    }
}
```

---

**🎯 การใช้ Dashboard นี้จะทำให้การจัดการ SQL Server เป็นแบบ Proactive แทนที่จะเป็น Reactive!**

เมื่อ setup เสร็จแล้ว จะสามารถ:
- **ตรวจจับปัญหา Performance ก่อนที่ User จะสังเกตเห็น**
- **แนะนำ Index ที่มี impact สูง อย่างมีหลักฐาน**  
- **ติดตาม Query regression แบบอัตโนมัติ**
- **วางแผน Capacity และ Maintenance อย่างมีข้อมูล**