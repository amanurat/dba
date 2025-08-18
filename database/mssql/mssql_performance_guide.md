# 🚀 คู่มือปรับแต่ง SQL Server Performance บน Azure (ฉบับใช้งานง่าย)

> **คู่มือครบครันสำหรับการปรับแต่งประสิทธิภาพ SQL Server บน Azure SQL Database/Managed Instance**  
> เริ่มต้นได้ทันที ไม่ต้องเป็นผู้เชี่ยวชาญ | เวลาใช้งาน 1-2 ชั่วโมง

---

## 📋 สารบัญด่วน

| หัวข้อ | ความยาก | ผลลัพธ์ |
|--------|---------|---------|
| [🎯 ภาพรวมการทำงาน](#-ภาพรวมการทำงาน) | 🟢 | เข้าใจขั้นตอน |
| [⏰ การวางแผนเวลา](#-การวางแผนเวลา) | 🟢 | รู้จักความเสี่ยง |
| [🔍 Step 1: ตรวจสุขภาพระบบ](#-step-1-ตรวจสุขภาพระบบ) | 🟢 | รู้สถานะปัจจุบัน |
| [📊 Step 2: วิเคราะห์ Query ช้า](#-step-2-วิเคราะห์-query-ช้า) | 🟢 | หาจุดปัญหา |
| [🗂️ Step 3: ตรวจสอบ Index](#-step-3-ตรวจสอบ-index) | 🟢 | ประเมิน Index |
| [📈 Step 4: คำนวณคะแนน](#-step-4-คำนวณคะแนน) | 🟢 | ให้คะแนนระบบ |
| [⚡ Step 5: แก้ไขปัญหา](#-step-5-แก้ไขปัญหา) | 🟡 | ปรับปรุงระบบ |
| [✅ Step 6: ตรวจสอบผล](#-step-6-ตรวจสอบผล) | 🟢 | วัดผลการปรับปรุง |

---

## 🎯 ภาพรวมการทำงาน

### กระบวนการทำงาน 6 ขั้นตอน
```
🔍 ตรวจสอบ → 📊 วิเคราะห์ → 🏷️ จัดหมวดหมู่ → 🔧 แก้ไข → 📈 ตรวจสอบผล
```

### ปัญหาที่จะแก้ไข
- ✅ **Database ทำงานช้า** → เร็วขึ้น 2-5 เท่า
- ✅ **การใช้ Memory มากเกิน** → ลดลง 20-40%
- ✅ **Index ไม่มีประสิทธิภาพ** → Query เร็วขึ้นทันที
- ✅ **การตั้งค่าไม่เหมาะสม** → ระบบเสถียรขึ้น

### เป้าหมายหลัก
- 🚀 **Performance เพิ่มขึ้น**: Database เร็วขึ้น 2-5 เท่า
- 💾 **Memory ประหยัดขึ้น**: ใช้ Buffer Pool ลดลง 20-40%
- 📊 **Response Time ดีขึ้น**: User รอน้อยลง
- 🎯 **ระบบคงที่**: ไม่ค้าง ไม่ช้า ไม่พัง

---

## ⏰ การวางแผนเวลา

### ตารางเวลาแบบละเอียด

| ขั้นตอน | งาน | ความเสี่ยง | หมายเหตุ |
|---------|-----|-----------|----------|
| **เตรียมการ** | Backup + Planning | 🟢 ปลอดภัย | ทำก่อนเริ่ม |
| **Step 1-4** | วิเคราะห์และตรวจสอบ | 🟢 ปลอดภัย | ไม่กระทบระบบ |
| **Step 5** | แก้ไขปัญหา | 🟡 ระวัง | ส่วนที่มีความเสี่ยง |
| **Step 6** | ตรวจสอบผลลัพธ์ | 🟢 ปลอดภัย | วัดผลการปรับปรุง |
| **สรุป** | บันทึกและวางแผนต่อ | 🟢 ปลอดภัย | Documentation |

**⏱️ รวมเวลาทั้งหมด: 1.5-2.5 ชั่วโมง**

### ⚠️ ข้อควรระวังสำคัญ

#### 🔴 สิ่งที่ห้ามทำ
- **ห้ามทำใน Production โดยตรง** → ทดสอบใน Development ก่อนเสมอ
- **ห้ามทำโดยไม่ Backup** → สำรองข้อมูลก่อนทุกครั้ง
- **ห้ามทำในชั่วโมงเร่งด่วน** → เลือกช่วง Maintenance Window

#### 🟡 สิ่งที่ต้องระวัง
- **แก้ทีละอย่าง** → ดูผลก่อนทำต่อ
- **ตรวจสอบ Dependencies** → Index อาจมีผลต่อ Query อื่น
- **เตรียมแผน Rollback** → หากเกิดปัญหาต้องย้อนกลับได้

#### 🟢 Best Practices
- **ทำในช่วงที่ User น้อย** → เช้าตรู่หรือดึก
- **แจ้ง Team ให้ทราบ** → เตรียมความพร้อมช่วยแก้ปัญหา
- **Monitor ระหว่างทำ** → ดูผลกระทบแบบ Real-time

---

## 🔍 Step 1: ตรวจสุขภาพระบบ

เหมือนการไปตรวจสุขภาพประจำปี - ต้องรู้สถานะปัจจุบันก่อน

### 🩺 ตรวจสอบสิ่งสำคัญ 4 อย่าง

#### 1.1 ขนาดฐานข้อมูล
```sql
-- ดูขนาด Database ปัจจุบัน (Azure SQL Database)
SELECT 
    DB_NAME() AS database_name,
    CAST(SUM(CAST(FILEPROPERTY(name, 'SpaceUsed') AS bigint) * 8192.) / 1024 / 1024 AS decimal(15,2)) AS space_used_mb,
    CAST(SUM(size) * 8192. / 1024 / 1024 AS decimal(15,2)) AS space_allocated_mb
FROM sys.database_files
WHERE type_desc = 'ROWS';

-- สำหรับ SQL Server on-premises
SELECT 
    DB_NAME(database_id) AS database_name,
    CAST(SUM(size) * 8.0 / 1024 AS decimal(15,2)) AS size_mb
FROM sys.master_files
WHERE database_id = DB_ID()
GROUP BY database_id;
```

**📏 มาตรฐานการประเมิน:**
- **< 500 MB** = 🟢 เล็ก (ปรับแต่งง่าย)
- **500 MB - 5 GB** = 🟡 กลาง (ต้องระวัง)
- **5 GB - 50 GB** = 🟠 ใหญ่ (ต้องวางแผน)
- **> 50 GB** = 🔴 ใหญ่มาก (ต้องมีผู้เชี่ยวชาญ)

#### 1.2 การใช้งาน Connection
```sql
-- ดูจำนวน Connection ปัจจุบัน
SELECT 
    COUNT(*) AS total_connections,
    COUNT(CASE WHEN status = 'sleeping' THEN 1 END) AS sleeping_connections,
    COUNT(CASE WHEN status = 'running' THEN 1 END) AS active_connections
FROM sys.dm_exec_sessions
WHERE is_user_process = 1;

-- ดู Connection limit
SELECT 
    name,
    value,
    value_in_use
FROM sys.configurations
WHERE name = 'user connections';
```

**👥 มาตรฐานการประเมิน:**
- **< 20 Active** = 🟢 น้อย (ปกติ)
- **20-50 Active** = 🟡 ปานกลาง
- **50-100 Active** = 🟠 เยอะ (ควรใช้ Connection Pool)
- **> 100 Active** = 🔴 เยอะมาก (ต้องจัดการ)

#### 1.3 ประสิทธิภาพ Buffer Pool
```sql
-- ดู Buffer Pool Hit Ratio (ตัวชี้วัดสำคัญ)
SELECT 
    cntr_value AS buffer_cache_hit_ratio
FROM sys.dm_os_performance_counters
WHERE counter_name = 'Buffer cache hit ratio'
    AND object_name LIKE '%Buffer Manager%';

-- ดูรายละเอียด Buffer Pool
SELECT 
    (a.cntr_value * 1.0 / b.cntr_value) * 100.0 AS buffer_cache_hit_ratio
FROM sys.dm_os_performance_counters a
    INNER JOIN sys.dm_os_performance_counters b ON a.object_name = b.object_name
WHERE a.counter_name = 'Buffer cache hit ratio'
    AND b.counter_name = 'Buffer cache hit ratio base'
    AND a.object_name LIKE '%Buffer Manager%';
```

**💾 มาตรฐานการประเมิน:**
- **> 98%** = 🟢 ดีเยี่ยม (Memory เพียงพอมาก)
- **95-98%** = 🟢 ดี (Memory เพียงพอ)
- **90-95%** = 🟡 พอใช้ (ควรเพิ่ม Memory)
- **85-90%** = 🟠 ต่ำ (ต้องเพิ่ม Memory)
- **< 85%** = 🔴 ต่ำมาก (Memory ไม่พอเลย)

#### 1.4 ตรวจสอบ CPU และ Wait Statistics
```sql
-- ดู CPU utilization
SELECT 
    record.value('(./Record/@id)[1]', 'int') AS record_id,
    record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS system_idle,
    record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS sql_cpu_utilization,
    DATEADD(ms, -1 * (ts_now - [timestamp]), GETDATE()) AS event_time
FROM (
    SELECT timestamp, CONVERT(xml, record) AS record, ts_now
    FROM sys.dm_os_ring_buffers
    CROSS APPLY (SELECT DATEDIFF(ms, GETDATE(), GETDATE()) + ms_ticks AS ts_now FROM sys.dm_os_sys_info) x
    WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
) AS t
ORDER BY record_id DESC;

-- ดู Top Wait Types
SELECT TOP 10
    wait_type,
    wait_time_ms,
    percentage = CAST(100.0 * wait_time_ms / SUM(wait_time_ms) OVER() AS decimal(5,2)),
    avg_wait_time_ms = CAST(wait_time_ms / waiting_tasks_count AS decimal(15,2))
FROM sys.dm_os_wait_stats
WHERE waiting_tasks_count > 0
    AND wait_type NOT IN ('CLR_SEMAPHORE', 'LAZYWRITER_SLEEP', 'RESOURCE_QUEUE', 'SLEEP_TASK')
ORDER BY wait_time_ms DESC;
```

### 📝 แบบฟอร์มบันทึกผล Step 1

```
✅ Step 1 - สุขภาพระบบ (วันที่: ____/____/____)

📏 ขนาด Database: _______ MB/GB  สี: 🟢🟡🟠🔴
👥 Active Connections: _______   สี: 🟢🟡🟠🔴  
💾 Buffer Cache Hit Ratio: _______%    สี: 🟢🟡🟠🔴
🖥️ CPU Utilization: _______%    สี: 🟢🟡🟠🔴

📊 คะแนนรวม Step 1: ____/10
📝 ปัญหาที่พบ: _________________________________
```

---

## 📊 Step 2: วิเคราะห์ Query ช้า

หาคนร้ายที่ทำให้ระบบช้า - มักจะเป็น Query ไม่กี่ตัวที่ทำให้ทั้งระบบช้า

### 🎯 เป้าหมาย: หา Top 5 Query ที่ช้าที่สุด

#### 2.1 ตรวจสอบระบบ Query Store (Azure SQL Database)
```sql
-- ตรวจสอบว่าเปิด Query Store หรือยัง
SELECT 
    actual_state_desc,
    readonly_reason,
    desired_state_desc
FROM sys.database_query_store_options;

-- เปิด Query Store ถ้ายังไม่เปิด
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
```

#### 2.2 หา Query ช้าอันดับ 1-5 (จาก Query Store)
```sql
-- Top 5 Query ที่ใช้เวลานานสุด
SELECT TOP 5
    qst.query_sql_text,
    qsp.plan_id,
    rs.count_executions,
    rs.avg_duration / 1000.0 AS avg_duration_ms,
    rs.max_duration / 1000.0 AS max_duration_ms,
    rs.total_duration / 1000.0 AS total_duration_ms
FROM sys.query_store_query_text qst
    INNER JOIN sys.query_store_query q ON qst.query_text_id = q.query_text_id
    INNER JOIN sys.query_store_plan qsp ON q.query_id = qsp.query_id
    INNER JOIN sys.query_store_runtime_stats rs ON qsp.plan_id = rs.plan_id
WHERE rs.last_execution_time > DATEADD(hour, -24, GETUTCDATE())
ORDER BY rs.total_duration DESC;
```

#### 2.3 หา Query ช้าจาก DMV (สำหรับทุก SQL Server)
```sql
-- Top 5 Query ที่ช้าที่สุดจาก DMV
SELECT TOP 5
    qs.total_elapsed_time / qs.execution_count / 1000.0 AS avg_elapsed_time_ms,
    qs.total_elapsed_time / 1000.0 AS total_elapsed_time_ms,
    qs.execution_count,
    qs.total_worker_time / qs.execution_count / 1000.0 AS avg_cpu_time_ms,
    qs.total_logical_reads / qs.execution_count AS avg_logical_reads,
    SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
        ((CASE WHEN qs.statement_end_offset = -1
            THEN LEN(CONVERT(nvarchar(max), st.text)) * 2
            ELSE qs.statement_end_offset
        END - qs.statement_start_offset)/2) + 1) AS query_text
FROM sys.dm_exec_query_stats qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE qs.last_execution_time > DATEADD(hour, -24, GETDATE())
ORDER BY qs.total_elapsed_time DESC;
```

#### 2.4 หา Query ที่ใช้ CPU สูง
```sql
-- Top 5 Query ที่ใช้ CPU มากที่สุด
SELECT TOP 5
    qs.total_worker_time / 1000.0 AS total_cpu_time_ms,
    qs.total_worker_time / qs.execution_count / 1000.0 AS avg_cpu_time_ms,
    qs.execution_count,
    qs.total_elapsed_time / qs.execution_count / 1000.0 AS avg_elapsed_time_ms,
    SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
        ((CASE WHEN qs.statement_end_offset = -1
            THEN LEN(CONVERT(nvarchar(max), st.text)) * 2
            ELSE qs.statement_end_offset
        END - qs.statement_start_offset)/2) + 1) AS query_text
FROM sys.dm_exec_query_stats qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE qs.last_execution_time > DATEADD(hour, -24, GETDATE())
ORDER BY qs.total_worker_time DESC;
```

### 📊 การแปลผลลัพธ์

**🚨 เกณฑ์ความช้า:**
- **< 50ms** = 🟢 เร็วดี
- **50-200ms** = 🟡 พอใช้ได้
- **200-1000ms** = 🟠 ช้า
- **> 1000ms** = 🔴 ช้ามาก (ต้องแก้ด่วน)

**🎯 เกณฑ์ผลกระทบ:**
- **Total Time > 1000ms** = Query นี้กินเวลามากที่สุด
- **Execution Count > 1000** = Query ที่ใช้บ่อย
- **Max Duration > 10000ms** = มี Query บางครั้งช้ามาก

### 📝 แบบฟอร์มบันทึกผล Step 2

```
✅ Step 2 - Query ช้า (วันที่: ____/____/____)

🥇 Query ช้าอันดับ 1:
   Preview: _________________________________
   เฉลี่ย: ______ms  สี: 🟢🟡🟠🔴
   
🥈 Query ช้าอันดับ 2:
   Preview: _________________________________
   เฉลี่ย: ______ms  สี: 🟢🟡🟠🔴
   
🥉 Query ช้าอันดับ 3:
   Preview: _________________________________
   เฉลี่ย: ______ms  สี: 🟢🟡🟠🔴

📊 สรุป: มี Query ช้า _____ ตัว (สี 🟠🔴)
```

---

## 🗂️ Step 3: ตรวจสอบ Index

Index เหมือนสารบัญหนังสือ - ช่วยหาข้อมูลเร็วขึ้น แต่ถ้ามีมากเกินไปก็เปลือง

### 🎯 ตรวจสอบ 3 เรื่องสำคัญ

#### 3.1 Index ที่ไม่ได้ใช้เลย (เปลือง Space)
```sql
-- หา Index ที่ไม่เคยใช้
SELECT 
    OBJECT_SCHEMA_NAME(i.object_id) AS schema_name,
    OBJECT_NAME(i.object_id) AS table_name,
    i.name AS index_name,
    i.type_desc AS index_type,
    us.user_seeks,
    us.user_scans,
    us.user_lookups,
    us.user_updates,
    p.rows AS table_rows,
    CAST((8.0 * SUM(a.used_pages)) / 1024 AS decimal(15,2)) AS index_size_mb
FROM sys.indexes i
    INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
    INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
    LEFT JOIN sys.dm_db_index_usage_stats us ON i.object_id = us.object_id AND i.index_id = us.index_id AND us.database_id = DB_ID()
WHERE OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
    AND i.index_id > 0  -- ไม่รวม heap
    AND i.is_primary_key = 0  -- ไม่รวม primary key
    AND i.is_unique_constraint = 0  -- ไม่รวม unique constraint
    AND (us.user_seeks IS NULL OR us.user_seeks = 0)
    AND (us.user_scans IS NULL OR us.user_scans = 0)
    AND (us.user_lookups IS NULL OR us.user_lookups = 0)
GROUP BY i.object_id, i.index_id, i.name, i.type_desc, us.user_seeks, us.user_scans, us.user_lookups, us.user_updates, p.rows
ORDER BY index_size_mb DESC;
```

#### 3.2 Table ที่อาจต้องการ Index เพิ่ม
```sql
-- หา Table ที่ Table Scan บ่อยเกินไป
SELECT 
    OBJECT_SCHEMA_NAME(ius.object_id) AS schema_name,
    OBJECT_NAME(ius.object_id) AS table_name,
    SUM(ius.user_scans) AS table_scans,
    SUM(ius.user_seeks + ius.user_scans + ius.user_lookups) AS total_reads,
    CASE 
        WHEN SUM(ius.user_seeks + ius.user_scans + ius.user_lookups) > 0 
        THEN CAST(100.0 * SUM(ius.user_scans) / SUM(ius.user_seeks + ius.user_scans + ius.user_lookups) AS decimal(5,2))
        ELSE 0
    END AS scan_percentage,
    p.rows AS table_rows,
    CAST((8.0 * SUM(a.used_pages)) / 1024 AS decimal(15,2)) AS table_size_mb
FROM sys.dm_db_index_usage_stats ius
    INNER JOIN sys.indexes i ON ius.object_id = i.object_id AND ius.index_id = i.index_id
    INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
    INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
WHERE ius.database_id = DB_ID()
    AND OBJECTPROPERTY(ius.object_id, 'IsUserTable') = 1
GROUP BY ius.object_id, p.rows
HAVING SUM(ius.user_scans) > 100  -- Tables ที่ scan มากกว่า 100 ครั้ง
    AND CASE 
        WHEN SUM(ius.user_seeks + ius.user_scans + ius.user_lookups) > 0 
        THEN CAST(100.0 * SUM(ius.user_scans) / SUM(ius.user_seeks + ius.user_scans + ius.user_lookups) AS decimal(5,2))
        ELSE 0
    END > 70  -- Scan percentage > 70%
ORDER BY scan_percentage DESC, table_scans DESC;
```

#### 3.3 Index ที่ทำงานหนักสุด (ดี)
```sql
-- Top Index ที่ใช้งานเยอะสุด
SELECT TOP 10
    OBJECT_SCHEMA_NAME(ius.object_id) AS schema_name,
    OBJECT_NAME(ius.object_id) AS table_name,
    i.name AS index_name,
    i.type_desc AS index_type,
    ius.user_seeks,
    ius.user_scans,
    ius.user_lookups,
    ius.user_seeks + ius.user_scans + ius.user_lookups AS total_reads,
    ius.user_updates,
    CAST((8.0 * SUM(a.used_pages)) / 1024 AS decimal(15,2)) AS index_size_mb
FROM sys.dm_db_index_usage_stats ius
    INNER JOIN sys.indexes i ON ius.object_id = i.object_id AND ius.index_id = i.index_id
    INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
    INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
WHERE ius.database_id = DB_ID()
    AND OBJECTPROPERTY(ius.object_id, 'IsUserTable') = 1
    AND (ius.user_seeks + ius.user_scans + ius.user_lookups) > 0
GROUP BY ius.object_id, ius.index_id, i.name, i.type_desc, ius.user_seeks, ius.user_scans, ius.user_lookups, ius.user_updates
ORDER BY total_reads DESC;
```

### 📊 การแปลผลลัพธ์

**🔴 Index ไม่ได้ใช้:**
- `total_reads = 0` และ `index_size_mb > 10` = ควรลบ
- ตรวจสอบให้แน่ใจว่าไม่มี Application อื่นใช้

**🟡 Table ต้องการ Index:**
- `scan_percentage > 70%` และ `table_size_mb > 50` = ต้องการ Index
- ดู Query ช้าจาก Step 2 ว่าเกี่ยวข้องกับ Table นี้ไหม

**🟢 Index ที่ดี:**
- `total_reads > 1000` = Index ที่มีประโยชน์
- เก็บไว้และอาจต้องทำแบบเดียวกันกับ Table อื่น

### 📝 แบบฟอร์มบันทึกผล Step 3

```
✅ Step 3 - Index Analysis (วันที่: ____/____/____)

🔴 Index ไม่ได้ใช้ (ควรลบ):
1. Table: _____________ Index: _____________ Size: _______MB
2. Table: _____________ Index: _____________ Size: _______MB

🟡 Table ต้องการ Index (ควรเพิ่ม):
1. Table: _____________ Scan %: ______% Size: _______MB
2. Table: _____________ Scan %: ______% Size: _______MB

🟢 Index ที่ดี (เก็บไว้):
1. Table: _____________ Index: _____________ Reads: _______
2. Table: _____________ Index: _____________ Reads: _______

📊 สรุป: ลบได้ _____ ตัว | เพิ่ม _____ ตัว
```

---

## 📈 Step 4: คำนวณคะแนน

ให้คะแนนฐานข้อมูลเพื่อรู้ว่าปัญหาหลักอยู่ตรงไหน

### 🎯 ระบบให้คะแนน (คะแนนเต็ม 100)

#### 4.1 Memory Performance (30 คะแนน)
**จาก Buffer Cache Hit Ratio ใน Step 1:**
- **> 98%** → 30 คะแนน 🟢
- **95-98%** → 25 คะแนน 🟢
- **90-95%** → 20 คะแนน 🟡
- **85-90%** → 15 คะแนน 🟠
- **< 85%** → 10 คะแนน 🔴

#### 4.2 Query Performance (30 คะแนน)
**จากจำนวน Query ช้า (>200ms) ใน Step 2:**
- **0 ตัว** → 30 คะแนน 🟢
- **1-2 ตัว** → 25 คะแนน 🟢
- **3-5 ตัว** → 20 คะแนน 🟡
- **6-10 ตัว** → 15 คะแนน 🟠
- **>10 ตัว** → 10 คะแนน 🔴

#### 4.3 Index Efficiency (25 คะแนน)
**จาก Index ไม่ได้ใช้ใน Step 3:**
- **0-1 ตัว** → 25 คะแนน 🟢
- **2-3 ตัว** → 20 คะแนน 🟡
- **4-5 ตัว** → 15 คะแนน 🟠
- **>5 ตัว** → 10 คะแนน 🔴

#### 4.4 CPU & Wait Performance (15 คะแนน)
**จาก CPU utilization และ Wait Stats:**
- **CPU < 70% และ Wait < 20%** → 15 คะแนน 🟢
- **CPU < 80% และ Wait < 30%** → 12 คะแนน 🟢
- **CPU < 90% และ Wait < 40%** → 10 คะแนน 🟡
- **CPU > 90% หรือ Wait > 40%** → 8 คะแนน 🟠

### 📊 แบบฟอร์มคำนวณคะแนน

```
🎯 PERFORMANCE SCORECARD
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Memory Performance:      ____/30  (Buffer Hit: ____%)
Query Performance:       ____/30  (Slow Queries: ____)
Index Efficiency:        ____/25  (Unused Index: ____)
CPU & Wait Performance:  ____/15  (CPU: ___% Wait: __%)
                         ──────
TOTAL SCORE:             ____/100

PERFORMANCE GRADE: ____________
```

### 🏆 เกรด Performance

- **90-100** = 🟢 **A (ยอดเยี่ยม)** - ระบบสมบูรณ์แบบ
- **80-89** = 🟢 **B (ดีมาก)** - ปรับปรุงเล็กน้อย
- **70-79** = 🟡 **C (ดี)** - ปรับปรุงบางส่วน
- **60-69** = 🟠 **D (พอใช้)** - ต้องปรับปรุงหลายจุด
- **< 60** = 🔴 **F (แย่)** - ต้องแก้ไขด่วน

### 🎯 การระบุปัญหาหลัก

**จากคะแนนแต่ละหมวด ปัญหาหลักคือ:**
- [ ] **Memory ไม่เพียงพอ** (Memory Score < 20)
- [ ] **Query ช้าเยอะ** (Query Score < 20)
- [ ] **Index ไม่เหมาะสม** (Index Score < 20)
- [ ] **CPU/Wait ปัญหา** (CPU Score < 10)

---

## ⚡ Step 5: แก้ไขปัญหา

ตอนนี้รู้ปัญหาแล้ว เริ่มแก้ไขกัน! **ระวัง: ส่วนนี้มีความเสี่ยง ต้องระมัดระวัง**

### 🚨 เตรียมความพร้อมก่อนแก้ไข

#### ก่อนเริ่ม ต้องทำ:
```sql
-- 1. Backup ฐานข้อมูล (Azure SQL Database)
-- ใช้ Azure Portal หรือ Azure CLI

-- 2. ตรวจสอบ Current Configuration
SELECT name, value, value_in_use, is_dynamic
FROM sys.configurations
WHERE name IN ('max server memory (MB)', 'max degree of parallelism', 'cost threshold for parallelism');

-- 3. ดู Current Wait Stats
SELECT TOP 5 wait_type, wait_time_ms, percentage
FROM (
    SELECT wait_type, wait_time_ms,
        CAST(100.0 * wait_time_ms / SUM(wait_time_ms) OVER() AS decimal(5,2)) AS percentage
    FROM sys.dm_os_wait_stats
    WHERE waiting_tasks_count > 0
) x
ORDER BY percentage DESC;
```

### 5.1 แก้ไขปัญหา Memory (🟡 ความเสี่ยงกลาง)

**เมื่อไหร่ต้องแก้:** Buffer Cache Hit Ratio < 95%

#### วิธีแก้ที่ 1: ปรับ Max Server Memory (SQL Server on-premises)

```sql
-- ดูค่าปัจจุบัน
SELECT name, value, value_in_use 
FROM sys.configurations 
WHERE name = 'max server memory (MB)';

-- ตัวอย่างการคำนวณ (สำหรับ server ที่มี RAM 16GB)
-- ให้ SQL Server ใช้ประมาณ 12GB (12288 MB)
-- เหลือ 4GB ให้ OS
EXEC sp_configure 'max server memory (MB)', 12288;
RECONFIGURE;
```

#### วิธีแก้ที่ 2: Upgrade Service Tier (Azure SQL Database)

**ใน Azure Portal:**
1. เข้า SQL Database → Settings → Compute + storage
2. เลือก Service tier ที่สูงขึ้น
3. Monitor performance หลัง upgrade

**ใน Azure CLI:**
```bash
# Upgrade to higher service tier
az sql db update \
  --resource-group myResourceGroup \
  --server myServer \
  --name myDatabase \
  --service-objective S2  # หรือ P1, P2, etc.
```

### 5.2 แก้ไขปัญหา Query ช้า (🟡 ความเสี่ยงกลาง)

**เมื่อไหร่ต้องแก้:** มี Query > 200ms มากกว่า 3 ตัว

#### Pattern การสร้าง Index

**Pattern 1: WHERE clause**
```sql
-- Query ช้า: SELECT * FROM Orders WHERE Status = 'Pending'
-- Index ที่ต้องการ:
CREATE NONCLUSTERED INDEX IX_Orders_Status 
ON Orders (Status);
```

**Pattern 2: ORDER BY**
```sql
-- Query ช้า: SELECT * FROM Users ORDER BY CreatedDate DESC
-- Index ที่ต้องการ:
CREATE NONCLUSTERED INDEX IX_Users_CreatedDate 
ON Users (CreatedDate DESC);
```

**Pattern 3: JOIN**
```sql
-- Query ช้า: SELECT * FROM Orders o JOIN Customers c ON o.CustomerId = c.Id
-- Index ที่ต้องการ:
CREATE NONCLUSTERED INDEX IX_Orders_CustomerId 
ON Orders (CustomerId);
```

**Pattern 4: Multiple WHERE conditions**
```sql
-- Query ช้า: SELECT * FROM Orders WHERE Status = 'Pending' AND CreatedDate > '2024-01-01'
-- Index ที่ต้องการ:
CREATE NONCLUSTERED INDEX IX_Orders_Status_CreatedDate 
ON Orders (Status, CreatedDate);
```

**Pattern 5: LIKE searches**
```sql
-- Query ช้า: SELECT * FROM Products WHERE Name LIKE '%phone%'
-- Full-text index ที่ต้องการ:
CREATE FULLTEXT CATALOG ProductCatalog;
CREATE FULLTEXT INDEX ON Products (Name) KEY INDEX PK_Products;
```

#### 🔧 Template การสร้าง Index

```sql
-- Template สำหรับ Index ทั่วไป
CREATE NONCLUSTERED INDEX IX_{table}_{column}
ON {table} ({column});

-- Template สำหรับ Covering Index
CREATE NONCLUSTERED INDEX IX_{table}_{key_columns}
ON {table} ({key_columns})
INCLUDE ({non_key_columns});

-- Template สำหรับ Filtered Index
CREATE NONCLUSTERED INDEX IX_{table}_{column}_Active
ON {table} ({column})
WHERE Status = 'Active';
```

### 5.3 แก้ไขปัญหา Index ไม่เหมาะสม (🟡 ความเสี่ยงกลาง)

#### 5.3.1 ลบ Index ที่ไม่ได้ใช้

**⚠️ ขั้นตอนที่ปลอดภัย:**
```sql
-- 1. ตรวจสอบอีกครั้ง
SELECT 
    i.name AS index_name,
    us.user_seeks,
    us.user_scans,
    us.user_lookups,
    us.user_updates
FROM sys.indexes i
    LEFT JOIN sys.dm_db_index_usage_stats us ON i.object_id = us.object_id AND i.index_id = us.index_id
WHERE i.object_id = OBJECT_ID('YourTable')
    AND i.name = 'IX_YourIndex';

-- 2. ถ้า user_seeks + user_scans + user_lookups = 0 และแน่ใจว่าไม่ใช้
BEGIN TRANSACTION;
DROP INDEX IX_YourIndex ON YourTable;
-- ทดสอบระบบ 5-10 นาที
-- ถ้าไม่มีปัญหา
COMMIT;
-- ถ้ามีปัญหา
-- ROLLBACK;
```

#### 5.3.2 เพิ่ม Index ที่ขาดหายไป

**จาก Step 3 - Table ที่ต้องการ Index:**
```sql
-- สำหรับ Table ที่ Table Scan สูง
-- ดูก่อนว่า Query ส่วนใหญ่เป็นอะไร

-- ตัวอย่าง: Orders table
-- ถ้า Query ส่วนใหญ่เป็น WHERE Status = ?
CREATE NONCLUSTERED INDEX IX_Orders_Status ON Orders (Status);

-- ถ้า Query ส่วนใหญ่เป็น WHERE CustomerId = ?
CREATE NONCLUSTERED INDEX IX_Orders_CustomerId ON Orders (CustomerId);

-- ถ้า Query ส่วนใหญ่เป็น ORDER BY CreatedDate
CREATE NONCLUSTERED INDEX IX_Orders_CreatedDate ON Orders (CreatedDate);
```

### 5.4 แก้ไขปัญหา CPU และ Wait Stats (🟠 ความเสี่ยงสูง)

**เมื่อไหร่ต้องแก้:** CPU > 80% หรือ Wait Stats ผิดปกติ

#### 5.4.1 ปรับ Max Degree of Parallelism (MAXDOP)
```sql
-- ดูค่าปัจจุบัน
SELECT name, value, value_in_use 
FROM sys.configurations 
WHERE name = 'max degree of parallelism';

-- สำหรับ server ที่มี 8 cores แนะนำ MAXDOP = 4
EXEC sp_configure 'max degree of parallelism', 4;
RECONFIGURE;
```

#### 5.4.2 ปรับ Cost Threshold for Parallelism
```sql
-- ดูค่าปัจจุบัน (default = 5 ซึ่งต่ำเกินไป)
SELECT name, value, value_in_use 
FROM sys.configurations 
WHERE name = 'cost threshold for parallelism';

-- เพิ่มเป็น 50 เพื่อลด parallelism ที่ไม่จำเป็น
EXEC sp_configure 'cost threshold for parallelism', 50;
RECONFIGURE;
```

#### 5.4.3 Update Statistics
```sql
-- Update statistics สำหรับ Table ที่มีปัญหา
UPDATE STATISTICS Orders WITH FULLSCAN;
UPDATE STATISTICS Customers WITH FULLSCAN;

-- หรือ update ทั้ง database
EXEC sp_updatestats;
```

### 📝 แบบฟอร์มบันทึกการแก้ไข

```
⚡ Step 5 - การแก้ไขที่ทำ (วันที่: ____/____/____)

🔧 Memory Optimization:
□ เพิ่ม Max Server Memory จาก ____MB เป็น ____MB
□ Upgrade Service Tier จาก ____ เป็น ____
□ Restart/Apply: เวลา ____:____

🔧 Query Optimization (Index ที่เพิ่ม):
□ Table: _______ Index: _______ Columns: _______
□ Table: _______ Index: _______ Columns: _______
□ Table: _______ Index: _______ Columns: _______

🔧 Index Cleanup (Index ที่ลบ):
□ Index: _______ Table: _______ Saved Space
□ Index: _______ Table: _______ Saved Space

🔧 CPU/Wait Optimization:
□ MAXDOP: จาก ____ เป็น ____
□ Cost Threshold: จาก ____ เป็น ____
□ Update Statistics: เสร็จเวลา ____:____

⏰ เวลาเริ่ม: ____:____ | เวลาเสร็จ: ____:____
🎯 รวมเวลา: _______ นาที
```

---

## ✅ Step 6: ตรวจสอบผล

วัดผลการปรับปรุงว่าดีขึ้นเท่าไหร่

### 🔍 6.1 ตรวจสอบ Memory Performance

```sql
-- ดู Buffer Cache Hit Ratio หลังการปรับปรุง
SELECT 
    (a.cntr_value * 1.0 / b.cntr_value) * 100.0 AS buffer_cache_hit_ratio_after
FROM sys.dm_os_performance_counters a
    INNER JOIN sys.dm_os_performance_counters b ON a.object_name = b.object_name
WHERE a.counter_name = 'Buffer cache hit ratio'
    AND b.counter_name = 'Buffer cache hit ratio base'
    AND a.object_name LIKE '%Buffer Manager%';
```

### 🔍 6.2 ตรวจสอบ Query Performance

```sql
-- รีเซ็ต Query Store เพื่อวัดผลใหม่ (ถ้าต้องการ)
ALTER DATABASE CURRENT SET QUERY_STORE CLEAR;

-- รอ 15-30 นาที แล้วดูใหม่
SELECT TOP 5
    qst.query_sql_text,
    rs.count_executions,
    rs.avg_duration / 1000.0 AS avg_duration_ms_after,
    rs.total_duration / 1000.0 AS total_duration_ms_after
FROM sys.query_store_query_text qst
    INNER JOIN sys.query_store_query q ON qst.query_text_id = q.query_text_id
    INNER JOIN sys.query_store_plan qsp ON q.query_id = qsp.query_id
    INNER JOIN sys.query_store_runtime_stats rs ON qsp.plan_id = rs.plan_id
WHERE rs.last_execution_time > DATEADD(hour, -1, GETUTCDATE())
ORDER BY rs.avg_duration DESC;
```

### 🔍 6.3 ทดสอบ Query เฉพาะที่แก้ไข

```sql
-- เปิดการวัดเวลาและ I/O
SET STATISTICS TIME ON;
SET STATISTICS IO ON;

-- ทดสอบ Query ที่เคยช้า
SELECT * FROM Orders WHERE Status = 'Pending';
SELECT * FROM Users ORDER BY CreatedDate DESC;

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
```

### 🔍 6.4 ตรวจสอบการใช้ Index ใหม่

```sql
-- ดูว่า Index ใหม่ถูกใช้หรือไม่
SELECT 
    OBJECT_SCHEMA_NAME(ius.object_id) AS schema_name,
    OBJECT_NAME(ius.object_id) AS table_name,
    i.name AS index_name,
    ius.user_seeks + ius.user_scans + ius.user_lookups AS total_reads_after,
    ius.user_updates,
    ius.last_user_seek,
    ius.last_user_scan,
    ius.last_user_lookup
FROM sys.dm_db_index_usage_stats ius
    INNER JOIN sys.indexes i ON ius.object_id = i.object_id AND ius.index_id = i.index_id
WHERE ius.database_id = DB_ID()
    AND i.name LIKE 'IX_%'  -- Index ที่เราสร้างใหม่
    AND (ius.user_seeks + ius.user_scans + ius.user_lookups) > 0
ORDER BY total_reads_after DESC;
```

### 📊 6.5 คำนวณคะแนนใหม่

ใช้วิธีเดียวกับ Step 4 คำนวณคะแนนใหม่:

```
🎉 PERFORMANCE IMPROVEMENT REPORT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

                        BEFORE    AFTER    IMPROVEMENT
Memory Performance:     ___/30 → ___/30   (+___ points)
Query Performance:      ___/30 → ___/30   (+___ points)  
Index Efficiency:       ___/25 → ___/25   (+___ points)
CPU & Wait Performance: ___/15 → ___/15   (+___ points)
                        ─────     ─────
TOTAL SCORE:           ___/100 → ___/100  (+___ points)

GRADE IMPROVEMENT: ____ → ____

🚀 KEY IMPROVEMENTS:
□ Buffer Hit Ratio: ___% → ___% (+___%)
□ Average Query Time: ___ms → ___ms (___x faster)
□ Database Grade: ____ → ____
```

### 🎯 6.6 การประเมินผลสำเร็จ

**🟢 ผลการปรับปรุงที่ดี:**
- Buffer Cache Hit Ratio เพิ่มขึ้น > 2%
- Query เร็วขึ้น > 50%
- คะแนนรวมเพิ่มขึ้น > 10 points

**🟡 ผลการปรับปรุงที่พอใช้:**
- Buffer Cache Hit Ratio เพิ่มขึ้น 1-2%
- Query เร็วขึ้น 20-50%
- คะแนนรวมเพิ่มขึ้น 5-10 points

**🔴 ผลการปรับปรุงที่ไม่ดี:**
- ไม่มีการเปลี่ยนแปลงหรือแย่ลง
- ต้องตรวจสอบว่าการแก้ไขถูกต้องหรือไม่

---

## 🎓 สรุปและคำแนะนำ

### 🏆 สิ่งที่เราทำสำเร็จ

✅ **วิเคราะห์ปัญหาอย่างเป็นระบบ** - รู้จุดอ่อนของ Database  
✅ **แก้ไขปัญหาแบบเป็นขั้นตอน** - Memory, Query, Index, CPU  
✅ **วัดผลลัพธ์อย่างชัดเจน** - ใช้ตัวเลขประกอบการตัดสินใจ  
✅ **เพิ่มประสิทธิภาพโดยรวม** - Database เร็วขึ้น เสถียรขึ้น

### 📚 บทเรียนสำคัญ

**🎯 หลักการหลัก:**
- **Memory เป็นพื้นฐาน** → Buffer Cache Hit Ratio ต้อง > 95%
- **Index เป็นกุญแจสำคัญ** → Query เร็วขึ้นได้หลายเท่า
- **ลบของเก่าที่ไม่ใช้** → ประหยัด Space และ Performance
- **วัดผลทุกครั้ง** → ใช้ข้อมูลตัดสินใจ ไม่เดาเอา

**⚠️ ข้อระวัง:**
- **ความปลอดภัยก่อน** → Test ใน Development เสมอ
- **ทำทีละขั้นตอน** → อย่าแก้ครั้งละหลายอย่าง
- **Backup ก่อนแก้ไข** → เผื่อต้องย้อนกลับ
- **Monitor หลังแก้ไข** → ดูผลกระทบ Real-time

### ⏰ แผนการบำรุงรักษา

#### 📅 รายสัปดาห์
- ตรวจสอบ Query ช้าใหม่ที่อาจเกิดขึ้น
- ดู Buffer Cache Hit Ratio ว่ายังคงดีอยู่หรือไม่
- Monitor การใช้ Connection และ CPU

#### 📅 รายเดือน
- รันการวิเคราะห์นี้อีกครั้งเต็มรูปแบบ (Step 1-4)
- ตรวจสอบ Index ใหม่ที่อาจไม่ได้ใช้
- ทำ UPDATE STATISTICS สำหรับ Table ที่เปลี่ยนแปลงเยอะ

#### 📅 รายไตรมาส
- ทำ Index maintenance (REBUILD/REORGANIZE)
- ทบทวน Configuration Parameters
- วางแผนการขยาย Hardware หากจำเป็น

### 🔗 เอกสารอ้างอิงเพิ่มเติม

**สำหรับผู้เริ่มต้น:**
- **Setup Monitoring** → วิธีเปิด Query Store และ Monitor tools
- **Basic Query Templates** → T-SQL สำเร็จรูปสำหรับการตรวจสอบ
- **Azure SQL Best Practices** → แนวทางปฏิบัติใน Cloud

**สำหรับระดับกลาง:**
- **Execution Plan Guide** → วิเคราะห์ Query Plan อย่างละเอียด
- **Advanced Index Strategies** → Index แบบ Covering, Filtered, Columnstore
- **Wait Statistics Analysis** → เข้าใจ Wait Events ต่างๆ

**สำหรับผู้ดูแลระบบ:**
- **High Availability Setup** → ตั้งค่า Always On และ Failover
- **Backup and Recovery** → กลยุทธ์การสำรองข้อมูลแบบสมบูรณ์
- **Monitoring and Alerting** → ระบบแจ้งเตือนเมื่อมีปัญหา

### 💡 เคล็ดลับจากผู้เชี่ยวชาญ

**🎯 สำหรับการปรับปรุงครั้งต่อไป:**
1. **80/20 Rule** → 80% ของปัญหามาจาก Query 20% ตัว แก้ไขตรงจุดนี้
2. **Index Maintenance** → Index ดีในช่วงแรก แต่จะเสื่อมประสิทธิภาพเมื่อข้อมูลเยอะขึ้น
3. **Hardware vs Software** → บางครั้ง Upgrade Service Tier ประสิทธิผลดีกว่าการ Optimize
4. **Application Level** → การแก้ไขใน Application บางครั้งได้ผลดีกว่าการแก้ Database

**⚡ Quick Wins สำหรับประสิทธิภาพ:**
- ปรับ Max Server Memory หรือ Upgrade Service Tier เป็นวิธีที่ได้ผลเร็วที่สุด
- ลบ Index ที่ไม่ใช้จะเห็นผลทันที
- ใช้ TOP หรือ WHERE clause เพื่อจำกัดข้อมูล
- หลีกเลี่ยง SELECT * ในระบบ Production

---

**🎉 ยินดีด้วย! คุณผ่านการปรับแต่ง SQL Server Performance เรียบร้อยแล้ว!**

ตอนนี้ Database ของคุณควรมีประสิทธิภาพดีขึ้นอย่างเห็นได้ชัด การปรับแต่ง Performance เป็นกระบวนการต่อเนื่อง ยิ่งทำบ่อยๆ ยิ่งเก่งขึ้นและได้ผลดีขึ้น

**💪 จำไว้: Database ที่ดี = Application ที่เร็ว = User ที่พอใจ**