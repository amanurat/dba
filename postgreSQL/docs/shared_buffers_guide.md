# PostgreSQL shared_buffers Configuration Guide

## 📋 ภาพรวม

`shared_buffers` เป็นพารามิเตอร์สำคัญที่สุดตัวหนึ่งของ PostgreSQL ที่ควบคุมจำนวน memory ที่ใช้สำหรับ cache ข้อมูลและ index pages ร่วมกันระหว่างทุก database connections

## 🎯 shared_buffers คืออะไร?

`shared_buffers` คือ **memory pool ที่แชร์กันใช้** สำหรับเก็บ:

- **Data pages** จาก tables
- **Index pages** จาก indexes  
- **WAL buffers** (ก่อนเขียนลง disk)
- **Metadata pages**
- **Temporary data** (บางส่วน)

### 🔍 การทำงานของ shared_buffers

```
┌─────────────────────────────────────┐
│           PostgreSQL Process        │
├─────────────────────────────────────┤
│  Connection 1 │ Connection 2 │ ... │
├─────────────────────────────────────┤
│        shared_buffers Pool          │  ← แชร์กันใช้
│  ┌──────┬──────┬──────┬──────┐      │
│  │Page 1│Page 2│Page 3│Page 4│ ...  │
│  └──────┴──────┴──────┴──────┘      │
├─────────────────────────────────────┤
│            OS File Cache            │
├─────────────────────────────────────┤
│              Disk Storage           │
└─────────────────────────────────────┘
```

## 📊 สถานการณ์ปัจจุบัน (2GB)

### ✅ การประเมินเบื้องต้น

ค่า **2GB** สำหรับ shared_buffers ถือว่า:
- **🟢 Excellent** ตามที่ระบบแสดง
- เหมาะสมสำหรับระบบที่มี RAM 8-16GB
- อยู่ในช่วง 15-25% ของ total RAM (ซึ่งเป็นค่าแนะนำ)

### 📈 ข้อดีของค่าปัจจุบัน

1. **Hit Ratio ดี**
   - Pages ที่เข้าถึงบ่อยอยู่ใน memory
   - ลดการ read จาก disk

2. **สมดุลกับ OS Cache**
   - ไม่แย่ง memory กับ OS มากเกินไป
   - OS ยังสามารถ cache files อื่นได้

## 🧠 การทำงานของ shared_buffers

### 1. **Page Management**

```sql
-- เมื่อ query ต้องการข้อมูل
SELECT * FROM products WHERE category_id = 5;

-- PostgreSQL จะ:
-- 1. ตรวจสอบใน shared_buffers ก่อน
-- 2. ถ้ามี → ใช้เลย (cache hit)  
-- 3. ถ้าไม่มี → อ่านจาก disk แล้วเก็บไว้ใน shared_buffers
```

### 2. **Buffer Replacement Algorithm**

PostgreSQL ใช้ **Clock Sweep Algorithm**:
- เก็บ pages ที่ใช้บ่อยไว้นานขึ้น
- เอา pages ที่ไม่ใช้ออกเมื่อต้องการพื้นที่

### 3. **Dirty Pages Handling**

```sql
-- เมื่อมีการ UPDATE/INSERT/DELETE
UPDATE products SET price = price * 1.1 WHERE category_id = 5;

-- PostgreSQL จะ:
-- 1. แก้ไขใน shared_buffers (dirty page)
-- 2. Background writer จะเขียนลง disk ภายหลัง
-- 3. ทำให้ write operations เร็วขึ้น
```

## ⚡ ผลดีของ shared_buffers ที่เพียงพอ

### 1. **Cache Hit Ratio สูง**
```sql
-- ตรวจสอบ hit ratio
SELECT 
    sum(heap_blks_read) as heap_read,
    sum(heap_blks_hit) as heap_hit,
    round(sum(heap_blks_hit) * 100.0 / (sum(heap_blks_hit) + sum(heap_blks_read)), 2) as hit_ratio
FROM pg_stat_user_tables;

-- Hit ratio ที่ดี: > 95%
-- Hit ratio ปัญหา: < 90%
```

### 2. **ลด Disk I/O**
- ข้อมูลที่ใช้บ่อยอยู่ใน memory
- Write operations รวมกันก่อนเขียนลง disk
- ลด random I/O, เพิ่ม sequential I/O

### 3. **ประสิทธิภาพ Query ดีขึ้น**
- Table scans เร็วขึ้น
- Index lookups เร็วขึ้น
- JOIN operations มีประสิทธิภาพมากขึ้น

## 📏 การคำนวณขนาดที่เหมาะสม

### สูตรแนะนำ

```
shared_buffers = 15-25% ของ Total RAM

สำหรับระบบประเภทต่างๆ:
```

| ประเภทระบบ | % ของ RAM | เหตุผล |
|------------|-----------|---------|
| **Dedicated DB Server** | 25-40% | DB เป็น workload หลัก |
| **Mixed Workload Server** | 15-25% | แชร์ RAM กับ applications อื่น |
| **Small/Development** | 25% | เน้นประสิทธิภาพ DB |
| **Very Large Systems** | 10-15% | เพื่อไม่ให้ระบบล่ม |

### ตัวอย่างการคำนวณ

```sql
-- ตรวจสอบ RAM ทั้งหมด (Linux)
-- cat /proc/meminfo | grep MemTotal

-- ตัวอย่าง: Server 16GB RAM
-- shared_buffers แนะนำ:
-- Conservative: 16GB × 15% = 2.4GB  ← ใกล้เคียงค่าปัจจุบัน
-- Optimal: 16GB × 25% = 4GB
-- Aggressive: 16GB × 35% = 5.6GB (ถ้าเป็น dedicated DB server)
```

## ⚠️ อันตรายของการตั้งค่าผิด

### 💥 shared_buffers สูงเกินไป

**อาการ:**
- ระบบช้าลงเมื่อ restart (ต้อง warm up cache นาน)
- OS out of memory
- Swapping เกิดขึ้น

**ตัวอย่างที่อันตราย:**
```
Server 8GB RAM
shared_buffers = 6GB  ← เกินไป!

เหลือให้ OS + Applications = 2GB เท่านั้น
→ OS จะ swap → ทุกอย่างช้า
```

### 📉 shared_buffers ต่ำเกินไป

**อาการ:**
- Cache hit ratio ต่ำ (< 90%)
- Disk I/O สูง
- Query ช้า แม้ว่าจะมี RAM เหลือเยอะ

**ตัวอย่าง:**
```
Server 32GB RAM
shared_buffers = 128MB  ← ต่ำเกินไป!

PostgreSQL ไม่สามารถใช้ RAM ได้เต็มที่
```

## 🔧 การปรับแต่งและตั้งค่า

### 1. **ขั้นตอนการปรับค่า**

```sql
-- ตรวจสอบค่าปัจจุบัน
SELECT name, setting, unit, short_desc 
FROM pg_settings 
WHERE name = 'shared_buffers';

-- คำนวณค่าใหม่ (ตัวอย่าง: เพิ่มจาก 2GB เป็น 4GB)
-- สำหรับ server 16GB RAM

-- วิธีที่ 1: แก้ไข postgresql.conf
-- shared_buffers = 4GB

-- วิธีที่ 2: ใช้ ALTER SYSTEM (PostgreSQL 9.4+)
ALTER SYSTEM SET shared_buffers = '4GB';

-- ⚠️ ต้อง restart PostgreSQL service
-- sudo systemctl restart postgresql
```

### 2. **ข้อควรระวังก่อนปรับค่า**

```sql
-- ตรวจสอบ memory usage ปัจจุบัน
SELECT 
    pg_size_pretty(pg_total_relation_size('pg_class')) as system_catalog_size,
    pg_size_pretty(sum(pg_total_relation_size(schemaname||'.'||tablename))) as total_table_size
FROM pg_tables 
WHERE schemaname NOT IN ('information_schema', 'pg_catalog');

-- ตรวจสอบ current hit ratio รวมทั้ง Table และ Index hit ratio (Human-readable %)
SELECT
   'Table ฺBuffer Hit Ratio' AS metric,
   ROUND(SUM(t.heap_blks_hit) * 100.0 /
         NULLIF(SUM(t.heap_blks_hit) + SUM(t.heap_blks_read), 0), 2)::text || '%' AS value
FROM pg_statio_user_tables t

UNION ALL
SELECT
   'Index Hit Ratio' AS metric,
   ROUND(SUM(i.idx_blks_hit) * 100.0 /
         NULLIF(SUM(i.idx_blks_hit) + SUM(i.idx_blks_read), 0), 2)::text || '%' AS value
FROM pg_statio_user_indexes i

UNION ALL
SELECT
   'Total Cache Hit Ratio' AS metric,
   ROUND((SUM(t.heap_blks_hit) + SUM(i.idx_blks_hit)) * 100.0 /
         NULLIF(SUM(t.heap_blks_hit) + SUM(t.heap_blks_read) +
                SUM(i.idx_blks_hit) + SUM(i.idx_blks_read), 0), 2)::text || '%' AS value
FROM pg_statio_user_tables t
        JOIN pg_statio_user_indexes i ON t.relid = i.relid;

```

## 📊 การติดตามและตรวจสอบ

### 1. **Buffer Usage Statistics**

```sql
-- ตรวจสอบ buffer hit ratio (ใช้ pg_stat_database)
SELECT
   'Shared Buffers Hit Ratio' as metric,
   round(
           (sum(blks_hit) * 100.0) /
           NULLIF(sum(blks_hit) + sum(blks_read), 0), 2
   ) as hit_ratio_percent,
   CASE
      WHEN round(
                   (sum(blks_hit) * 100.0) /
                   NULLIF(sum(blks_hit) + sum(blks_read), 0), 2
           ) >= 95 THEN '🟢 Excellent'
      WHEN round(
                   (sum(blks_hit) * 100.0) /
                   NULLIF(sum(blks_hit) + sum(blks_read), 0), 2
           ) >= 90 THEN '🟡 Good'
      ELSE '🔴 Needs Improvement'
      END as status
FROM pg_stat_database
WHERE datname = current_database();

-- หรือใช้วิธีที่ง่ายกว่า (แนะนำ)
SELECT
   'Buffer Hit Ratio' as metric,
   round(
           (sum(blks_hit)::numeric / NULLIF(sum(blks_hit) + sum(blks_read), 0)) * 100, 2
   ) || '%' as hit_ratio,
   sum(blks_hit) as buffer_hits,
   sum(blks_read) as disk_reads,
   sum(blks_hit) + sum(blks_read) as total_reads
FROM pg_stat_database
WHERE datname = current_database();
```

### 2. **Buffer Usage by Tables**

```sql
-- Tables ที่ใช้ buffer มากที่สุด
SELECT
   s.schemaname,
   s.relname AS tablename,
   io.heap_blks_read + io.heap_blks_hit AS total_reads,
   io.heap_blks_hit,
   ROUND(
           io.heap_blks_hit * 100.0 / NULLIF(io.heap_blks_read + io.heap_blks_hit, 0),
           1
   ) AS hit_ratio,
   pg_size_pretty(
           pg_total_relation_size((s.schemaname || '.' || s.relname)::regclass)
   ) AS table_size
FROM pg_stat_user_tables s
        JOIN pg_statio_user_tables io ON s.relid = io.relid
WHERE io.heap_blks_read + io.heap_blks_hit > 0
ORDER BY total_reads DESC
LIMIT 10;

SELECT
   'Table ฺBuffer Hit Ratio' AS metric,
   ROUND(SUM(t.heap_blks_hit) * 100.0 /
         NULLIF(SUM(t.heap_blks_hit) + SUM(t.heap_blks_read), 0), 2)::text || '%' AS value
FROM pg_statio_user_tables t
```

### 3. **Buffer Pool Status**

```sql
-- ข้อมูลเกี่ยวกับ shared_buffers pool
SELECT 
    'Total Shared Buffers' as metric,
    pg_size_pretty(setting::bigint * 8192) as size_pretty,
    setting as blocks
FROM pg_settings 
WHERE name = 'shared_buffers'

UNION ALL

SELECT 
    'Block Size' as metric,
    pg_size_pretty(setting::bigint) as size_pretty,
    setting as blocks  
FROM pg_settings 
WHERE name = 'block_size';
```

### 4. **Monitoring Script**

```sql
-- Script สำหรับ monitor shared_buffers effectiveness
-- Script สำหรับ monitor shared_buffers effectiveness (แก้ไขแล้ว)
WITH buffer_stats AS (
   SELECT
      sum(blks_read) as total_reads,
      sum(blks_hit) as total_hits,
      round(
              sum(blks_hit)::numeric * 100.0 /
              NULLIF(sum(blks_hit) + sum(blks_read), 0), 2
      ) as hit_ratio
   FROM pg_stat_database
   WHERE datname = current_database()
),
     buffer_size AS (
        SELECT
           setting::bigint * 8192 as shared_buffers_bytes,
           pg_size_pretty(setting::bigint * 8192) as shared_buffers_pretty
        FROM pg_settings
        WHERE name = 'shared_buffers'
     )
SELECT
   bs.shared_buffers_pretty as "Shared Buffers Size",
   bf.hit_ratio || '%' as "Hit Ratio",
   CASE
      WHEN bf.hit_ratio >= 95 THEN '🟢 Excellent - Current size is good'
      WHEN bf.hit_ratio >= 90 THEN '🟡 Good - Monitor for potential increase'
      WHEN bf.hit_ratio >= 85 THEN '🟠 Fair - Consider increasing shared_buffers'
      ELSE '🔴 Poor - Definitely increase shared_buffers'
      END as "Recommendation",
   bf.total_reads as "Total Block Reads",
   bf.total_hits as "Total Block Hits"
FROM buffer_stats bf
        CROSS JOIN buffer_size bs;
```

## 🎛️ Best Practices

### 1. **การตั้งค่าตาม Environment**

```bash
# Production Server (Dedicated DB)
shared_buffers = 25% of RAM

# Development Server  
shared_buffers = 25% of RAM (for testing realistic performance)

# Mixed Workload Server
shared_buffers = 15% of RAM
```

### 2. **การทดสอบก่อนใช้งาน**

```sql
-- ก่อนเปลี่ยน: บันทึก baseline metrics
CREATE TABLE buffer_baseline AS
SELECT 
    now() as measured_at,
    sum(heap_blks_read) as reads,
    sum(heap_blks_hit) as hits,
    round(sum(heap_blks_hit) * 100.0 / NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0), 2) as hit_ratio
FROM pg_stat_user_tables;

-- หลังเปลี่ยน: เปรียบเทียบผล
-- รอ warm-up period (อย่างน้อย 1 ชั่วโมง)
```

### 3. **การ Monitor อย่างต่อเนื่อง**

```sql
-- สร้าง monitoring view
CREATE OR REPLACE VIEW buffer_performance AS
SELECT 
    current_timestamp as check_time,
    (SELECT setting FROM pg_settings WHERE name = 'shared_buffers') as shared_buffers_setting,
    sum(heap_blks_read + heap_blks_hit) as total_buffer_accesses,
    round(sum(heap_blks_hit) * 100.0 / NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0), 2) as hit_ratio_percent,
    sum(heap_blks_read) as disk_reads,
    sum(heap_blks_hit) as buffer_hits
FROM pg_stat_user_tables;
```

## 🚀 การเพิ่มประสิทธิภาพเพิ่มเติม

### 1. **พารามิเตอร์ที่เกี่ยวข้อง**

```sql
-- ตั้งค่าให้สอดคล้องกับ shared_buffers
ALTER SYSTEM SET effective_cache_size = '12GB';  -- รวม shared_buffers + OS cache
ALTER SYSTEM SET checkpoint_completion_target = 0.9;  -- ช่วยลด I/O spikes
ALTER SYSTEM SET wal_buffers = '64MB';  -- เพิ่มจาก default 
```

### 2. **Background Writer Tuning**

```sql
-- ปรับ background writer ให้เหมาะสม
ALTER SYSTEM SET bgwriter_lru_maxpages = 1000;
ALTER SYSTEM SET bgwriter_lru_multiplier = 10.0;
ALTER SYSTEM SET bgwriter_delay = 10ms;
```

### 3. **การใช้ pg_prewarm**

```sql
-- Extension สำหรับ warm up cache
CREATE EXTENSION IF NOT EXISTS pg_prewarm;

-- Preload ตาราง important เข้า shared_buffers
SELECT pg_prewarm('important_table');
SELECT pg_prewarm('frequently_used_index');
```

## 📋 Checklist การปรับ shared_buffers

### ก่อนปรับค่า:
- [ ] ตรวจสอบ current hit ratio
- [ ] วัด baseline performance
- [ ] ตรวจสอบ available RAM
- [ ] วางแผน downtime (ต้อง restart)
- [ ] Backup configuration

### ระหว่างปรับค่า:
- [ ] แก้ไข postgresql.conf หรือใช้ ALTER SYSTEM
- [ ] Restart PostgreSQL service
- [ ] รอ warm-up period

### หลังปรับค่า:
- [ ] ตรวจสอบ hit ratio ใหม่
- [ ] Monitor memory usage
- [ ] ตรวจสอบ query performance
- [ ] เปรียบเทียบกับ baseline

## 🏁 สรุปและข้อแนะนำ

### สำหรับระบบปัจจุบัน (shared_buffers = 2GB):

**ค่าปัจจุบันดีแล้ว** หากระบบมี RAM ประมาณ 8-16GB

**แต่ถ้าต้องการเพิ่มประสิทธิภาพ:**

1. **ตรวจสอบ hit ratio ก่อน**
   ```sql
   -- ถ้า < 95% อาจควรเพิ่ม shared_buffers
   ```

2. **เพิ่มเป็น 3-4GB** (ถ้ามี RAM 16GB+)
   ```sql
   ALTER SYSTEM SET shared_buffers = '4GB';
   -- ต้อง restart PostgreSQL
   ```

3. **Monitor ผลลัพธ์อย่างใกล้ชิด**
   - Hit ratio ควรเพิ่มขึ้น
   - Query performance ดีขึ้น
   - ไม่เกิด memory pressure

### สัญญาณที่ควรเพิ่ม shared_buffers:
- ✓ Hit ratio < 95%
- ✓ มี RAM เหลือเยอะ
- ✓ Disk I/O สูง
- ✓ Working set ใหญ่กว่า current shared_buffers

### สัญญาณที่ไม่ควรเพิ่ม shared_buffers:
- ✗ Hit ratio > 98% อยู่แล้ว
- ✗ Memory pressure สูง
- ✗ Swapping เกิดขึ้น
- ✗ ระบบใช้ memory mixed workload

---

> **💡 Key Takeaway**: shared_buffers = 2GB น่าจะเหมาะสมสำหรับระบบส่วนใหญ่ แต่ถ้าต้องการประสิทธิภาพสูงสุดและมี RAM เพียงพอ การเพิ่มเป็น 3-4GB อาจช่วยได้ โดยต้อง monitor ผลอย่างใกล้ชิด!