# 📊 MySQL Dashboard: Index Recommendations & Performance Monitoring

> จุดประสงค์: ช่วยให้ Dev/DBA เห็นว่า query ใดในระบบควรใช้ index แต่ยังไม่มี index ที่เหมาะสม

---

## 🧭 Dashboard Section 1: Tables with High Table Scan Activity

```sql
-- หา Table ที่มี Table Scan สูงจาก Performance Schema
SELECT 
    OBJECT_SCHEMA AS database_name,
    OBJECT_NAME AS table_name,
    COUNT_READ AS full_table_scans,
    COUNT_WRITE AS table_writes,
    COUNT_READ + COUNT_WRITE AS total_operations,
    ROUND(COUNT_READ / NULLIF(COUNT_READ + COUNT_WRITE, 0) * 100, 2) AS scan_percentage,
    ROUND((SUM_TIMER_READ + SUM_TIMER_WRITE) / 1000000000000, 2) AS total_time_seconds
FROM performance_schema.table_io_waits_summary_by_table
WHERE OBJECT_SCHEMA NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')
    AND COUNT_READ > 100  -- Tables with significant scan activity
ORDER BY COUNT_READ DESC
LIMIT 10;
```

📌 ใช้แสดงเป็น Bar Chart:
- X-axis: table name
- Y-axis: Number of full table scans
- Color coding: สีแดงถ้า scan_percentage > 80%

---

## 📈 Dashboard Section 2: Top 10 Slow Queries (Need Index)

```sql
-- หา Query ช้าที่อาจต้องการ Index
SELECT 
    LEFT(DIGEST_TEXT, 100) AS query_preview,
    COUNT_STAR AS execution_count,
    ROUND(AVG_TIMER_WAIT/1000000000000, 4) AS avg_execution_time_seconds,
    ROUND(SUM_TIMER_WAIT/1000000000000, 2) AS total_time_seconds,
    ROUND((SUM_TIMER_WAIT / 
        (SELECT SUM(SUM_TIMER_WAIT) 
         FROM performance_schema.events_statements_summary_by_digest) * 100), 2) AS time_percentage
FROM performance_schema.events_statements_summary_by_digest
WHERE DIGEST_TEXT IS NOT NULL
    AND DIGEST_TEXT NOT LIKE '%performance_schema%'
    AND DIGEST_TEXT NOT LIKE '%information_schema%'
    AND AVG_TIMER_WAIT/1000000000000 > 0.1  -- Queries slower than 100ms
    AND COUNT_STAR > 10  -- Executed more than 10 times
ORDER BY AVG_TIMER_WAIT DESC
LIMIT 10;
```

📌 ใช้แสดงเป็น Data Table พร้อม:
- Query preview (clickable สำหรับดู full query)
- Execution count
- Average time
- Percentage of total database time

---

## 🔍 Dashboard Section 3: Tables With No Indexes

```sql
-- หา Table ที่ไม่มี Index เลย (นอกจาก Primary Key)
SELECT 
    t.TABLE_SCHEMA AS database_name,
    t.TABLE_NAME AS table_name,
    t.TABLE_ROWS AS estimated_rows,
    ROUND((t.DATA_LENGTH + t.INDEX_LENGTH) / 1024 / 1024, 2) AS size_mb,
    CASE 
        WHEN t.TABLE_ROWS > 10000 THEN '🔴 High Priority'
        WHEN t.TABLE_ROWS > 1000 THEN '🟡 Medium Priority'
        ELSE '🟢 Low Priority'
    END AS priority
FROM information_schema.TABLES t
WHERE t.TABLE_SCHEMA NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')
    AND t.TABLE_TYPE = 'BASE TABLE'
    AND t.TABLE_NAME NOT IN (
        SELECT DISTINCT s.TABLE_NAME
        FROM information_schema.STATISTICS s
        WHERE s.TABLE_SCHEMA = t.TABLE_SCHEMA
            AND s.TABLE_NAME = t.TABLE_NAME
            AND s.INDEX_NAME != 'PRIMARY'
    )
ORDER BY t.TABLE_ROWS DESC;
```

📌 แสดงเป็น Alert List พร้อม priority indicators

---

## ⚠️ Dashboard Section 4: Unused Indexes (Index Cleanup)

```sql
-- หา Index ที่ไม่ได้ใช้งาน
SELECT 
    OBJECT_SCHEMA AS database_name,
    OBJECT_NAME AS table_name,
    INDEX_NAME AS index_name,
    COUNT_READ AS read_operations,
    COUNT_WRITE AS write_operations,
    COUNT_FETCH AS fetch_operations,
    COUNT_INSERT AS insert_operations,
    COUNT_UPDATE AS update_operations,
    COUNT_DELETE AS delete_operations,
    CASE 
        WHEN (COUNT_READ + COUNT_WRITE + COUNT_FETCH) = 0 THEN '🔴 Never Used'
        WHEN (COUNT_READ + COUNT_WRITE + COUNT_FETCH) < 10 THEN '🟡 Rarely Used'
        ELSE '🟢 Active'
    END AS usage_status
FROM performance_schema.table_io_waits_summary_by_index_usage
WHERE OBJECT_SCHEMA NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')
    AND INDEX_NAME IS NOT NULL
    AND INDEX_NAME != 'PRIMARY'
    AND (COUNT_READ + COUNT_WRITE + COUNT_FETCH) < 10  -- Low usage indexes
ORDER BY (COUNT_READ + COUNT_WRITE + COUNT_FETCH) ASC;
```

📌 แสดงเพื่อช่วย DBA ทำ index cleanup

---

## 🚀 Dashboard Section 5: Index Efficiency Analysis

```sql
-- วิเคราะห์ประสิทธิภาพของ Index ที่มีอยู่
SELECT 
    OBJECT_SCHEMA AS database_name,
    OBJECT_NAME AS table_name,
    INDEX_NAME,
    COUNT_READ AS read_count,
    ROUND(SUM_TIMER_READ/1000000000000, 4) AS total_read_time_seconds,
    ROUND((SUM_TIMER_READ/NULLIF(COUNT_READ, 0))/1000000000, 2) AS avg_read_time_ms,
    CASE 
        WHEN (SUM_TIMER_READ/NULLIF(COUNT_READ, 0))/1000000000 < 1 THEN '🟢 Fast'
        WHEN (SUM_TIMER_READ/NULLIF(COUNT_READ, 0))/1000000000 < 5 THEN '🟡 Moderate'
        ELSE '🔴 Slow'
    END AS performance_rating
FROM performance_schema.table_io_waits_summary_by_index_usage
WHERE OBJECT_SCHEMA NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')
    AND INDEX_NAME IS NOT NULL
    AND COUNT_READ > 0
ORDER BY (SUM_TIMER_READ/NULLIF(COUNT_READ, 0)) DESC
LIMIT 15;
```

---

## 📊 Dashboard Section 6: Query Pattern Analysis

```sql
-- วิเคราะห์ Pattern ของ Query เพื่อแนะนำ Index
SELECT 
    CASE 
        WHEN DIGEST_TEXT LIKE '%WHERE%AND%' THEN 'Composite Index Candidate'
        WHEN DIGEST_TEXT LIKE '%ORDER BY%' THEN 'Sorting Index Candidate'
        WHEN DIGEST_TEXT LIKE '%GROUP BY%' THEN 'Grouping Index Candidate'
        WHEN DIGEST_TEXT LIKE '%JOIN%ON%' THEN 'JOIN Index Candidate'
        WHEN DIGEST_TEXT LIKE '%WHERE%LIKE%' THEN 'Text Search Index Candidate'
        ELSE 'Single Column Index Candidate'
    END AS index_type_recommendation,
    COUNT(*) AS query_count,
    ROUND(AVG(AVG_TIMER_WAIT/1000000000000), 4) AS avg_execution_time,
    ROUND(SUM(SUM_TIMER_WAIT/1000000000000), 2) AS total_impact_seconds
FROM performance_schema.events_statements_summary_by_digest
WHERE DIGEST_TEXT IS NOT NULL
    AND DIGEST_TEXT NOT LIKE '%performance_schema%'
    AND DIGEST_TEXT NOT LIKE '%information_schema%'
    AND COUNT_STAR > 5
GROUP BY 1
ORDER BY total_impact_seconds DESC;
```

---

## 🎯 Dashboard View Design

### 📊 แผงควบคุมหลัก (Main Dashboard):
- 🔵 **Graph 1**: Table Scan Activity (Bar Chart)
- 🔵 **Table 2**: Top Slow Queries (Data Grid)
- 🔵 **Alert List**: Tables without indexes
- 🔵 **Cleanup Section**: Unused indexes
- 🔵 **Performance Chart**: Index efficiency ratings

### 🎨 Color Coding System:
- 🟢 Green: Good performance / Low priority
- 🟡 Yellow: Moderate performance / Medium priority  
- 🔴 Red: Poor performance / High priority

---

## 🛠 Tools to Build This Dashboard

| Platform | Pros | Cons | Azure Integration |
|----------|------|------|-------------------|
| **Grafana** | Real-time, beautiful charts | Requires setup | ✅ Native MySQL connector |
| **Azure Workbooks** | Native Azure integration | Limited customization | ✅ Perfect fit |
| **Power BI** | Rich visualizations | Licensing cost | ✅ Good integration |
| **MySQL Workbench** | Free, built-in | Basic visualization | ❌ Manual only |
| **Metabase/Superset** | Open source, flexible | Self-hosted | 🟡 Custom connection |

---

## 🔧 Azure-Specific Implementation

### Azure Monitor Workbook Template:

```kql
// KQL Query สำหรับ Azure Log Analytics
// (ต้อง setup Azure Monitor for MySQL ก่อน)

MySqlSlowLogs
| where TimeGenerated > ago(24h)
| where QueryTime_s > 1.0  // Queries slower than 1 second
| summarize 
    ExecutionCount = count(),
    AvgQueryTime = avg(QueryTime_s),
    MaxQueryTime = max(QueryTime_s)
    by QueryText_s
| order by AvgQueryTime desc
| limit 10
```

### Azure CLI Setup:
```bash
# Enable slow query log
az mysql flexible-server parameter set \
  --resource-group myResourceGroup \
  --server-name myMySQLServer \
  --name slow_query_log \
  --value ON

# Set query time threshold
az mysql flexible-server parameter set \
  --resource-group myResourceGroup \
  --server-name myMySQLServer \
  --name long_query_time \
  --value 1.0
```

---

## 📈 Automated Recommendations Engine

```sql
-- Stored Procedure สำหรับ Index Recommendations
DELIMITER //

CREATE PROCEDURE GetIndexRecommendations()
BEGIN
    -- Create temporary table for recommendations
    CREATE TEMPORARY TABLE index_recommendations (
        database_name VARCHAR(64),
        table_name VARCHAR(64),
        recommendation_type VARCHAR(100),
        suggested_columns VARCHAR(500),
        impact_level ENUM('HIGH', 'MEDIUM', 'LOW'),
        reason TEXT
    );
    
    -- Recommendation 1: Tables with high scan activity
    INSERT INTO index_recommendations
    SELECT 
        OBJECT_SCHEMA,
        OBJECT_NAME,
        'Add Index for High Scan Activity',
        'Analyze query patterns for column suggestions',
        CASE 
            WHEN COUNT_READ > 10000 THEN 'HIGH'
            WHEN COUNT_READ > 1000 THEN 'MEDIUM'
            ELSE 'LOW'
        END,
        CONCAT('Table scanned ', COUNT_READ, ' times')
    FROM performance_schema.table_io_waits_summary_by_table
    WHERE OBJECT_SCHEMA NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')
        AND COUNT_READ > 500;
    
    -- Return recommendations
    SELECT * FROM index_recommendations ORDER BY impact_level, table_name;
    
    DROP TEMPORARY TABLE index_recommendations;
END //

DELIMITER ;

-- Usage
CALL GetIndexRecommendations();
```

---

## 🚨 Alert Configuration

### Critical Alerts:
```sql
-- Query สำหรับ Alert: Table scan > 1000 per hour
SELECT 
    OBJECT_NAME AS table_name,
    COUNT_READ AS scans_per_hour
FROM performance_schema.table_io_waits_summary_by_table
WHERE OBJECT_SCHEMA = DATABASE()
    AND COUNT_READ > 1000;

-- Query สำหรับ Alert: Slow query > 5 seconds average
SELECT 
    LEFT(DIGEST_TEXT, 50) AS slow_query,
    ROUND(AVG_TIMER_WAIT/1000000000000, 2) AS avg_seconds
FROM performance_schema.events_statements_summary_by_digest
WHERE AVG_TIMER_WAIT/1000000000000 > 5.0
    AND COUNT_STAR > 5;
```

---

## 📅 Refresh Schedule Recommendations

| Dashboard Component | Refresh Frequency | Reason |
|---------------------|-------------------|---------|
| Slow Queries | Every 5 minutes | Real-time performance issues |
| Table Scans | Every 15 minutes | Index optimization opportunities |
| Unused Indexes | Every hour | Cleanup recommendations |
| Query Patterns | Every 30 minutes | Index planning |

---

## 🧠 Integration with Ticketing Systems

### Auto-create JIRA/Azure DevOps tickets:
```python
# Python script example for automated ticket creation
import requests

def create_index_recommendation_ticket(table_name, scan_count, recommendation):
    ticket_data = {
        "summary": f"Index Recommendation: {table_name}",
        "description": f"""
        Table: {table_name}
        Full Table Scans: {scan_count}
        Recommendation: {recommendation}
        
        Priority: {'HIGH' if scan_count > 10000 else 'MEDIUM'}
        """,
        "priority": "High" if scan_count > 10000 else "Medium"
    }
    
    # Create ticket via API
    # Implementation depends on your ticketing system
```

---

**🎯 การใช้ Dashboard นี้จะช่วยให้ DBA ทำงานเชิงรุกมากขึ้น แทนที่จะรอให้ปัญหาเกิดขึ้นก่อน!**

เมื่อ setup เสร็จแล้ว Dashboard จะช่วยระบุปัญหาและแนะนำแนวทางแก้ไขอย่างเป็นระบบ ทำให้การดูแล Database มีประสิทธิภาพมากขึ้น