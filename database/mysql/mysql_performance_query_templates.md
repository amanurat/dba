# ⚙️ MySQL Performance Tuning: Query Template Collection

รวม Query Template สำหรับใช้วิเคราะห์ ปรับจูน และตรวจสอบ performance ของ MySQL บน Azure

---

## 🔍 1. ตรวจสอบ Slow Queries จาก Performance Schema

```sql
-- Top 10 Query ที่ใช้เวลารวมมากที่สุด
SELECT 
    LEFT(DIGEST_TEXT, 100) AS query_preview,
    COUNT_STAR AS execution_count,
    ROUND(SUM_TIMER_WAIT/1000000000000, 2) AS total_time_seconds,
    ROUND(AVG_TIMER_WAIT/1000000000000, 4) AS avg_time_seconds,
    ROUND((SUM_TIMER_WAIT / 
        (SELECT SUM(SUM_TIMER_WAIT) 
         FROM performance_schema.events_statements_summary_by_digest) * 100), 2) AS time_percentage
FROM performance_schema.events_statements_summary_by_digest
WHERE DIGEST_TEXT IS NOT NULL
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 10;
```

> แสดง query ที่ใช้เวลารวมมากที่สุด

---

## 🔍 2. ตรวจสอบ Query ที่รันบ่อยที่สุด

```sql
-- Top 10 Query ที่ execute บ่อยที่สุด
SELECT 
    LEFT(DIGEST_TEXT, 100) AS query_preview,
    COUNT_STAR AS execution_count,
    ROUND(AVG_TIMER_WAIT/1000000000000, 4) AS avg_time_seconds,
    ROUND(SUM_TIMER_WAIT/1000000000000, 2) AS total_time_seconds
FROM performance_schema.events_statements_summary_by_digest
WHERE DIGEST_TEXT IS NOT NULL
ORDER BY COUNT_STAR DESC
LIMIT 10;
```

> ใช้หา query ที่เกิดขึ้นถี่ อาจใช้ connection pool หรือ optimize logic

---

## 🔍 3. ตรวจสอบ Query ที่ช้าที่สุดต่อครั้ง (Mean Time)

```sql
-- Top 10 Query ที่ช้าที่สุดต่อครั้ง
SELECT 
    LEFT(DIGEST_TEXT, 100) AS query_preview,
    COUNT_STAR AS execution_count,
    ROUND(AVG_TIMER_WAIT/1000000000000, 4) AS avg_time_seconds,
    ROUND(MAX_TIMER_WAIT/1000000000000, 2) AS max_time_seconds,
    ROUND(MIN_TIMER_WAIT/1000000000000, 4) AS min_time_seconds
FROM performance_schema.events_statements_summary_by_digest
WHERE DIGEST_TEXT IS NOT NULL
    AND COUNT_STAR > 10  -- รันมากกว่า 10 ครั้งเพื่อกรอง noise
ORDER BY AVG_TIMER_WAIT DESC
LIMIT 10;
```

> คัดเฉพาะ query ที่รันมากกว่า 10 ครั้ง เพื่อกรอง noise

---

## 🔍 4. ตรวจสอบ Query ที่ไม่ใช้ Index

```sql
-- หา Query ที่อาจต้องการ Index
SELECT 
    LEFT(DIGEST_TEXT, 100) AS query_preview,
    COUNT_STAR AS execution_count,
    ROUND(AVG_TIMER_WAIT/1000000000000, 4) AS avg_time_seconds,
    SUM_ROWS_EXAMINED AS total_rows_examined,
    SUM_ROWS_SENT AS total_rows_returned,
    ROUND(SUM_ROWS_EXAMINED / NULLIF(SUM_ROWS_SENT, 0), 2) AS efficiency_ratio
FROM performance_schema.events_statements_summary_by_digest
WHERE DIGEST_TEXT IS NOT NULL
    AND DIGEST_TEXT NOT LIKE '%performance_schema%'
    AND DIGEST_TEXT NOT LIKE '%information_schema%'
    AND AVG_TIMER_WAIT/1000000000000 > 0.1  -- ช้ากว่า 100ms
    AND (SUM_ROWS_EXAMINED / NULLIF(SUM_ROWS_SENT, 0)) > 100  -- ตรวจสอบ rows เยอะกว่าที่ส่งกลับ
ORDER BY efficiency_ratio DESC
LIMIT 10;
```

> หา Query ที่ตรวจสอบ rows เยอะแต่ส่งกลับน้อย = อาจต้องการ index

---

## 🧠 5. ดู Table ที่มี Full Table Scan สูง

```sql
-- Table ที่มี Table Scan เยอะ
SELECT 
    OBJECT_SCHEMA AS database_name,
    OBJECT_NAME AS table_name,
    COUNT_READ AS table_scans,
    COUNT_WRITE AS table_writes,
    COUNT_READ + COUNT_WRITE AS total_operations,
    ROUND(COUNT_READ / NULLIF(COUNT_READ + COUNT_WRITE, 0) * 100, 2) AS scan_percentage,
    ROUND((SUM_TIMER_READ + SUM_TIMER_WRITE) / 1000000000000, 2) AS total_time_seconds
FROM performance_schema.table_io_waits_summary_by_table
WHERE OBJECT_SCHEMA NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')
    AND COUNT_READ > 100  -- Tables ที่มี scan activity มาก
ORDER BY COUNT_READ DESC
LIMIT 10;
```

> ตารางที่มี table scan เยอะ = น่าจะต้องสร้าง index เพิ่ม

---

## 🔍 6. ดู Table ที่ไม่มี Index เลย (No Index At All)

```sql
-- หา Table ที่ไม่มี Index นอกจาก Primary Key
SELECT 
    t.TABLE_SCHEMA AS database_name,
    t.TABLE_NAME AS table_name,
    t.TABLE_ROWS AS estimated_rows,
    ROUND((t.DATA_LENGTH + t.INDEX_LENGTH) / 1024 / 1024, 2) AS size_mb,
    t.ENGINE
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

📌 Table ที่ไม่มี index แต่มีข้อมูลเยอะอาจต้องสร้าง index

---

## ⚠️ 7. หา Unused Indexes

```sql
-- หา Index ที่ไม่ได้ใช้งาน
SELECT 
    OBJECT_SCHEMA AS database_name,
    OBJECT_NAME AS table_name,
    INDEX_NAME,
    COUNT_READ AS read_operations,
    COUNT_WRITE AS write_operations,
    COUNT_FETCH AS fetch_operations,
    COUNT_READ + COUNT_WRITE + COUNT_FETCH AS total_operations
FROM performance_schema.table_io_waits_summary_by_index_usage
WHERE OBJECT_SCHEMA NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')
    AND INDEX_NAME IS NOT NULL
    AND INDEX_NAME != 'PRIMARY'
    AND (COUNT_READ + COUNT_WRITE + COUNT_FETCH) = 0  -- ไม่ได้ใช้เลย
ORDER BY OBJECT_NAME, INDEX_NAME;
```

📌 แสดงเพื่อช่วย DBA ทำ index cleanup

---

## 🔍 8. ดูตารางที่มีการเขียน (INSERT/UPDATE/DELETE) สูง

```sql
-- Table ที่มี Write Activity สูง
SELECT 
    OBJECT_SCHEMA AS database_name,
    OBJECT_NAME AS table_name,
    COUNT_WRITE AS write_operations,
    COUNT_READ AS read_operations,
    ROUND(SUM_TIMER_WRITE / 1000000000000, 4) AS write_time_seconds,
    ROUND(SUM_TIMER_READ / 1000000000000, 4) AS read_time_seconds,
    ROUND(COUNT_WRITE / NULLIF(COUNT_READ + COUNT_WRITE, 0) * 100, 2) AS write_percentage
FROM performance_schema.table_io_waits_summary_by_table
WHERE OBJECT_SCHEMA NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')
    AND (COUNT_READ + COUNT_WRITE) > 0
ORDER BY COUNT_WRITE DESC
LIMIT 10;
```

---

## 🔍 9. ตรวจสอบ Buffer Pool Hit Ratio

```sql
-- Buffer Pool Monitoring
SELECT 
    'Buffer Pool Hit Ratio' AS metric,
    CONCAT(
        ROUND(100 - (
            (SELECT VARIABLE_VALUE 
             FROM performance_schema.global_status 
             WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads') * 100 /
            (SELECT VARIABLE_VALUE 
             FROM performance_schema.global_status 
             WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests')
        ), 2), '%'
    ) AS value,
    CASE 
        WHEN (100 - (
            (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads') * 100 /
            (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests')
        )) > 99 THEN '🟢 Excellent'
        WHEN (100 - (
            (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads') * 100 /
            (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests')
        )) > 95 THEN '🟢 Good'
        WHEN (100 - (
            (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads') * 100 /
            (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests')
        )) > 90 THEN '🟡 Fair'
        ELSE '🔴 Poor'
    END AS status

UNION ALL

SELECT 
    'Buffer Pool Size',
    ROUND(@@innodb_buffer_pool_size / 1024 / 1024 / 1024, 2),
    'Current Setting (GB)'

UNION ALL

SELECT 
    'Buffer Pool Pages Total',
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status 
     WHERE VARIABLE_NAME = 'Innodb_buffer_pool_pages_total'),
    'Total Pages'

UNION ALL

SELECT 
    'Buffer Pool Pages Free',
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status 
     WHERE VARIABLE_NAME = 'Innodb_buffer_pool_pages_free'),
    'Free Pages';
```

---

## 🔧 10. ตรวจสอบ Connection และ Thread Status

```sql
-- ดูสถานะ Connection ปัจจุบัน
SELECT
    'Current Connections' AS metric,
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Threads_connected') AS current_value,
    (SELECT VARIABLE_VALUE FROM performance_schema.global_variables WHERE VARIABLE_NAME = 'max_connections') AS max_allowed,
    ROUND(
            (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Threads_connected') /
            (SELECT VARIABLE_VALUE FROM performance_schema.global_variables WHERE VARIABLE_NAME = 'max_connections') * 100, 2
    ) AS usage_percentage

UNION ALL

SELECT
    'Max Used Connections',
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Max_used_connections'),
    (SELECT VARIABLE_VALUE FROM performance_schema.global_variables WHERE VARIABLE_NAME = 'max_connections'),
    ROUND(
            (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Max_used_connections') /
            (SELECT VARIABLE_VALUE FROM performance_schema.global_variables WHERE VARIABLE_NAME = 'max_connections') * 100, 2
    )

UNION ALL

SELECT
    'Threads Running',
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Threads_running'),
    'N/A',
    'Active Queries';

```

---

## 🔍 11. ตรวจสอบ Long Running Queries

```sql
-- ดู Query ที่รันนานเกิน 30 วินาที
SELECT 
    ID AS process_id,
    USER AS user_name,
    HOST AS client_host,
    DB AS database_name,
    COMMAND AS command_type,
    TIME AS runtime_seconds,
    STATE AS current_state,
    LEFT(INFO, 100) AS query_preview
FROM information_schema.PROCESSLIST
WHERE COMMAND != 'Sleep'
    AND TIME > 30  -- Query ที่รันนานกว่า 30 วินาที
    AND USER != 'azure_superuser'  -- กรอง Azure system user
ORDER BY TIME DESC;
```

---

## 🔍 12. ตรวจสอบ Deadlock และ Lock Wait

```sql
-- ดู Deadlock & Lock Wait Statistics
SELECT
    'Deadlocks' AS metric,
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_deadlocks') AS total_count,
    'Since Server Start' AS period

UNION ALL

SELECT
    'Lock Waits',
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_row_lock_waits'),
    'Total Row Lock Waits'

UNION ALL

SELECT
    'Lock Wait Time (seconds)',
    ROUND(
            (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_row_lock_time') / 1000,
            2
    ),
    'Total Time Spent Waiting'

UNION ALL

SELECT
    'Average Lock Wait Time (ms)',
    ROUND(
            (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_row_lock_time') /
            NULLIF(
                    (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_row_lock_waits'),
                    0
            ),
            2
    ),
    'Per Lock Wait';
```

---

## 💡 13. Database Size และ Growth Analysis

```sql
-- วิเคราะห์ขนาด Database และ Table
SELECT 
    TABLE_SCHEMA AS database_name,
    TABLE_NAME AS table_name,
    TABLE_ROWS AS estimated_rows,
    ROUND((DATA_LENGTH) / 1024 / 1024, 2) AS data_size_mb,
    ROUND((INDEX_LENGTH) / 1024 / 1024, 2) AS index_size_mb,
    ROUND((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024, 2) AS total_size_mb,
    ROUND((INDEX_LENGTH / NULLIF(DATA_LENGTH + INDEX_LENGTH, 0)) * 100, 2) AS index_percentage,
    ENGINE
FROM information_schema.TABLES
WHERE TABLE_SCHEMA NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')
    AND TABLE_TYPE = 'BASE TABLE'
ORDER BY (DATA_LENGTH + INDEX_LENGTH) DESC
LIMIT 20;
```

---

## 🔍 14. Query Pattern Analysis สำหรับ Index Planning

```sql
-- วิเคราะห์ Query Pattern เพื่อวางแผน Index
SELECT 
    CASE 
        WHEN DIGEST_TEXT LIKE '%WHERE%AND%' THEN 'Composite Index Candidate'
        WHEN DIGEST_TEXT LIKE '%ORDER BY%' THEN 'Sorting Index Candidate'
        WHEN DIGEST_TEXT LIKE '%GROUP BY%' THEN 'Grouping Index Candidate'
        WHEN DIGEST_TEXT LIKE '%JOIN%ON%' THEN 'JOIN Index Candidate'
        WHEN DIGEST_TEXT LIKE '%WHERE%LIKE%' OR DIGEST_TEXT LIKE '%MATCH%AGAINST%' THEN 'Full-Text Search Candidate'
        WHEN DIGEST_TEXT LIKE '%WHERE%' THEN 'Single Column Index Candidate'
        ELSE 'Other'
    END AS index_recommendation_type,
    COUNT(*) AS query_pattern_count,
    ROUND(AVG(AVG_TIMER_WAIT/1000000000000), 4) AS avg_execution_time_seconds,
    ROUND(SUM(SUM_TIMER_WAIT/1000000000000), 2) AS total_impact_seconds,
    ROUND((SUM(SUM_TIMER_WAIT) / 
        (SELECT SUM(SUM_TIMER_WAIT) 
         FROM performance_schema.events_statements_summary_by_digest) * 100), 2) AS percentage_of_total_time
FROM performance_schema.events_statements_summary_by_digest
WHERE DIGEST_TEXT IS NOT NULL
    AND DIGEST_TEXT NOT LIKE '%performance_schema%'
    AND DIGEST_TEXT NOT LIKE '%information_schema%'
    AND COUNT_STAR > 5
GROUP BY 1
ORDER BY total_impact_seconds DESC;
```

---

## 💡 Tips การใช้งาน:

### ✅ Best Practices:
- ใช้คู่กับ `EXPLAIN` เพื่อเข้าใจ execution plan
- เช็ค table ที่ใหญ่ แต่ไม่มี index
- อย่าลืม `ANALYZE TABLE` หลัง bulk update/insert
- ใช้ Connection Pool เช่น ProxySQL ช่วยเรื่อง connection management

### ⚠️ ข้อควรระวัง:
- Performance Schema ใช้ memory เพิ่ม ~10% ของ total memory
- อย่าลืมเปิด Performance Schema ก่อนใช้ query เหล่านี้
- ใน Azure MySQL ควรใช้ Flexible Server เพื่อ performance ที่ดีกว่า

### 🔧 การ Reset Statistics:
```sql
-- Reset Performance Schema statistics เพื่อเริ่มวัดใหม่
CALL sys.ps_truncate_all_tables(FALSE);

-- หรือ Reset เฉพาะ statement statistics
TRUNCATE TABLE performance_schema.events_statements_summary_by_digest;
```

---

## ✅ Recommended Tools

- **MySQL Workbench** - Visual explain และ performance reports
- **Azure Data Studio** - Query performance insights
- **Grafana + Prometheus** - Real-time monitoring dashboard
- **Azure Monitor** - Native Azure integration
- **pt-query-digest** (Percona Toolkit) - Advanced slow query analysis

---

**🚀 เมื่อใช้ query templates เหล่านี้ร่วมกับ monitoring dashboard จะทำให้การ optimize MySQL มีประสิทธิภาพมากขึ้น!**