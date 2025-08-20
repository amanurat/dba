# PostgreSQL work_mem Configuration Guide

## 📋 ภาพรวม

`work_mem` เป็นพารามิเตอร์สำคัญของ PostgreSQL ที่ควบคุมจำนวนหน่วยความจำที่จัดสรรให้กับแต่ละ operation ในการประมวลผล query

## 🎯 work_mem คืออะไร?

`work_mem` คือหน่วยความจำที่ PostgreSQL จัดสรรให้กับแต่ละ **operation** ในการทำงานของ query ประเภทต่างๆ:

- **การ sorting** (ORDER BY, CREATE INDEX)
- **Hash joins**
- **Hash-based aggregations** (GROUP BY)
- **Bitmap index scans**
- **Recursive queries**

### 🔍 ตัวอย่างการทำงาน

```sql
-- Query นี้อาจใช้ work_mem หลายครั้ง:
SELECT customer_id, COUNT(*), AVG(amount)
FROM orders o
JOIN customers c ON o.customer_id = c.id
WHERE order_date > '2024-01-01'
GROUP BY customer_id
ORDER BY COUNT(*) DESC;

-- Operations ที่ใช้ work_mem:
-- 1. Hash join (orders ⋈ customers)
-- 2. Hash aggregation (GROUP BY)  
-- 3. Sort (ORDER BY)
```

## 📊 สถานการณ์ปัจจุบัน (4MB)

### ❌ ปัญหาที่เกิดขึ้น

ค่า **4MB** ถือว่าต่ำมากสำหรับระบบที่มี `shared_buffers = 2GB` ซึ่งส่งผลให้:

1. **การใช้ Disk Temp Files**
   ```sql
   -- เมื่อข้อมูลที่ต้อง sort > 4MB
   SELECT * FROM large_table ORDER BY created_at;
   -- PostgreSQL จะ:
   -- ✗ เขียนข้อมูลลง /tmp 
   -- ✗ ทำ external sort (ช้า 10-100 เท่า)
   ```

2. **Performance ลดลง**
   - Query ที่มี JOIN ใหญ่ๆ ช้า
   - การทำ GROUP BY ช้า
   - INDEX creation ช้า

### 📈 การตรวจสอบปัญหา

```sql
-- ตรวจสอบ queries ที่ใช้ temp files
SELECT 
    query,
    calls,
    temp_blks_read,
    temp_blks_written,
    temp_blks_written * 8192 / 1024 / 1024 as temp_mb
FROM pg_stat_statements 
WHERE temp_blks_written > 0
ORDER BY temp_blks_written DESC
LIMIT 10;
```

## ⚡ ผลดีของการเพิ่ม work_mem

### 1. **ความเร็วเพิ่มขึ้นอย่างมาก**
- In-memory operations เร็วกว่า disk-based 10-100 เท่า
- Hash joins มีประสิทธิภาพสูงขึ้น
- Sorting ใน memory

### 2. **ลด I/O Load**
- ไม่ต้องเขียน temporary files
- ลดการใช้งาน storage
- ลด I/O bottleneck

### 3. **ประสิทธิภาพโดยรวมดีขึ้น**
- Concurrent queries แข่งขัน disk น้อยลง
- CPU ใช้งานมีประสิทธิภาพมากขึ้น

## ⚠️ อันตรายของการตั้งค่าสูงเกินไป

### 💥 Memory Overflow Risk

```
Total Memory Usage = work_mem × max_connections × operations_per_connection

ตัวอย่างที่อันตราย:
work_mem = 256MB
max_connections = 100  
operations per connection = 3
Total = 256MB × 100 × 3 = 76.8GB RAM!
```

### 🚨 ผลกระทบที่ตามมา

1. **Out of Memory (OOM)**
   - ระบบค้าง
   - PostgreSQL restart
   - Connection errors

2. **Swapping**
   - Performance ลดลงอย่างรุนแรง
   - I/O สูงผิดปกติ

## 🧮 การคำนวณค่าที่เหมาะสม

### สูตรแนะนำ

```
work_mem = (Available RAM × 0.20-0.25) / max_connections / 2-4

โดยที่:
- Available RAM = Total RAM - shared_buffers - OS overhead
- หาร 2-4 = จำนวน operations โดยเฉลี่ยต่อ connection
```

### ตัวอย่างการคำนวณ

```sql
-- ตรวจสอบค่าปัจจุบัน
SELECT name, setting, unit, short_desc 
FROM pg_settings 
WHERE name IN ('shared_buffers', 'max_connections', 'work_mem');

-- ตัวอย่าง: Server 16GB RAM
-- shared_buffers = 4GB
-- max_connections = 100
-- Available = 16GB - 4GB - 2GB (OS) = 10GB

-- คำนวณ work_mem:
-- work_mem = (10GB × 0.25) / 100 / 3 = 8.5MB ≈ 16MB
```

## 🔧 คำแนะนำการปรับค่า

### 1. **ขั้นตอนการปรับ (แบบระมัดระวัง)**

```sql
-- เริ่มจาก 4MB → 16MB
ALTER SYSTEM SET work_mem = '16MB';
SELECT pg_reload_conf();

-- รอสักพัก แล้วตรวจสอบผล
-- ถ้าดี ค่อยเพิ่มเป็น 32MB
ALTER SYSTEM SET work_mem = '32MB';
SELECT pg_reload_conf();
```

### 2. **ค่าแนะนำตาม Workload**

| ประเภทระบบ | work_mem แนะนำ | เหตุผล |
|------------|---------------|---------|
| **OLTP** (Transaction สูง) | 4-16MB | Connections เยอะ, operations เล็ก |
| **OLAP** (Analytics) | 64-256MB | Connections น้อย, operations ใหญ่ |
| **Mixed Workload** | 16-64MB | สมดุลระหว่าง OLTP/OLAP |
| **Data Warehouse** | 256MB-1GB | Batch processing, connections จำกัด |

### 3. **การปรับแบบ Dynamic**

```sql
-- สำหรับ session ที่ต้องการ work_mem สูง
SET work_mem = '256MB';

-- รัน heavy analytical query
EXPLAIN (ANALYZE, BUFFERS) 
SELECT department, AVG(salary), COUNT(*)
FROM employees e
JOIN departments d ON e.dept_id = d.id
GROUP BY department
ORDER BY AVG(salary) DESC;

-- Reset กลับค่าเดิม
RESET work_mem;
```

## 📊 การติดตามและตรวจสอบ

### 1. **ตรวจสอบ Temp File Usage**

```sql
-- Top queries ที่ใช้ temp files มากที่สุด
SELECT 
    substring(query, 1, 60) as query_preview,
    calls,
    temp_blks_written,
    temp_blks_written * 8192 / 1024 / 1024 as temp_mb,
    mean_exec_time
FROM pg_stat_statements 
WHERE temp_blks_written > 0
ORDER BY temp_blks_written DESC
LIMIT 10;
```

### 2. **ตรวจสอบ Memory Usage**

```sql
-- ตรวจสอบ memory usage ของ connections
SELECT 
    pid,
    usename,
    application_name,
    state,
    query_start,
    substring(query, 1, 50) as query_preview
FROM pg_stat_activity 
WHERE state = 'active'
ORDER BY query_start;
```

### 3. **Monitoring Script**

```sql
-- Script สำหรับติดตาม work_mem effectiveness
WITH temp_usage AS (
    SELECT 
        COUNT(*) as queries_using_temp,
        SUM(temp_blks_written) as total_temp_blocks,
        SUM(temp_blks_written * 8192 / 1024 / 1024) as total_temp_mb
    FROM pg_stat_statements 
    WHERE temp_blks_written > 0
)
SELECT 
    queries_using_temp,
    total_temp_mb,
    CASE 
        WHEN queries_using_temp > 100 THEN '🔴 Consider increasing work_mem'
        WHEN queries_using_temp > 10 THEN '🟡 Monitor closely' 
        ELSE '🟢 work_mem seems adequate'
    END as recommendation
FROM temp_usage;
```

## 🎛️ Best Practices

### 1. **การตั้งค่าแบบ Conservative**
```sql
-- เริ่มต้นด้วยค่าปลอดภัย
work_mem = (Total RAM × 0.20) / max_connections / 4
```

### 2. **การทดสอบก่อนใช้งานจริง**
```sql
-- ทดสอบใน development environment
-- Load test ด้วย realistic workload
-- Monitor memory usage
```

### 3. **การใช้ Connection Pooling**
```sql
-- ใช้ PgBouncer หรือ connection pooler
-- ลด max_connections จริง
-- เพิ่ม work_mem ได้มากขึ้น
```

## 🚀 สรุปและข้อแนะนำ

### สำหรับระบบปัจจุบัน (work_mem = 4MB, shared_buffers = 2GB):

1. **ขั้นตอนที่ 1**: เพิ่มเป็น **16MB** (ปลอดภัย)
2. **ขั้นตอนที่ 2**: หากไม่มีปัญหา เพิ่มเป็น **32MB**
3. **ขั้นตอนที่ 3**: Monitor และปรับตาม workload

### เครื่องมือช่วย:
- ใช้ `pg_stat_statements` ติดตาม temp file usage
- ใช้ `EXPLAIN (ANALYZE, BUFFERS)` ดู query plans
- Monitor system memory usage

### สัญญาณที่ควรเพิ่ม work_mem:
- ✓ Queries ใช้ temp files บ่อย
- ✓ Sort/Hash operations ช้า
- ✓ มี RAM เหลือเยอะ

### สัญญาณที่ควรลด work_mem:
- ✗ Out of memory errors
- ✗ Excessive swapping
- ✗ Connection failures

---

> **💡 Tips**: การปรับ work_mem เป็นการ tune ที่ให้ผลดีมาก แต่ต้องทำอย่างระมัดระวัง เริ่มจากค่าเล็กๆ แล้วค่อยๆ เพิ่ม และติดตามผลอย่างใกล้ชิด