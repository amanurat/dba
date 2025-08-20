# คู่มือการตั้งค่า effective_io_concurrency สำหรับ PostgreSQL

## ภาพรวม

`effective_io_concurrency` เป็นพารามิเตอร์สำคัญของ PostgreSQL ที่กำหนดจำนวนการทำงาน I/O พร้อมกันที่ระบบฐานข้อมูลสามารถจัดการได้อย่างมีประสิทธิภาพ การตั้งค่านี้มีผลโดยตรงต่อประสิทธิภาพของ query โดยเฉพาะการทำงานที่เกี่ยวข้องกับ bitmap heap scans และ query ที่ต้องอ่านข้อมูลจำนวนมาก

## effective_io_concurrency คืออะไร?

พารามิเตอร์ `effective_io_concurrency` บอกตัว query planner ของ PostgreSQL ว่าระบบจัดเก็บข้อมูล (storage) สามารถจัดการการทำงาน I/O พร้อมกันได้กี่รายการ ส่งผลต่อ:

- **Bitmap Heap Scans**: การอ่านข้อมูลจากหลาย pages พร้อมกัน
- **Prefetching**: การโหลดข้อมูลล่วงหน้าเพื่อลดเวลารอ
- **การทำงาน I/O แบบขนาน**: การประมวลผลหลาย I/O requests ในเวลาเดียวกัน

## ค่า Default และปัญหาที่เกิดขึ้น

### ค่า Default ปัจจุบัน
```sql
effective_io_concurrency = 1  -- Default ในทุก platform
```

### ทำไมค่า Default นี้ถึงเป็นปัญหา
- **มรดกทางประวัติศาสตร์**: ตั้งค่าในปี 2008 สำหรับ HDD แบบเก่า
- **การเลือกแบบระมัดระวัง**: ปลอดภัยแต่ประสิทธิภาพต่ำมากสำหรับ storage สมัยใหม่
- **ไม่เหมาะกับ Cloud**: ไม่เหมาะสมเลยสำหรับ SSD บน cloud
- **ผลกระทบต่อประสิทธิภาพ**: อาจทำให้ query ช้าลง 5-10 เท่าในระบบสมัยใหม่

## คำแนะนำตามประเภท Storage

### Traditional Hard Disk Drives (HDD)
```sql
-- แนะนำ: 1-4
ALTER SYSTEM SET effective_io_concurrency = 1;
```
**เหตุผล**: 
- มีหัวอ่าน/เขียนเพียงหัวเดียวต่อ disk
- การทำงานพร้อมกันสูงทำให้เกิด thrashing และใช้เวลา seek นาน
- การอ่านแบบลำดับจะมีประสิทธิภาพสูงสุด

### RAID Arrays
```sql
-- แนะนำ: 10-50 (ขึ้นอยู่กับ RAID level และจำนวน disk)
-- ตัวอย่างสำหรับ RAID-10 ที่มี 4 disks
ALTER SYSTEM SET effective_io_concurrency = 20;
```
**เหตุผล**:
- หลาย disks สามารถจัดการการทำงานแบบขนานได้
- ค่าที่เหมาะสมประมาณ จำนวน disks × 2-5

### SSD Storage
```sql
-- แนะนำ: 100-200
ALTER SYSTEM SET effective_io_concurrency = 150;
```
**เหตุผล**:
- ไม่มีชิ้นส่วนเคลื่อนไหว เข้าถึงข้อมูลแบบสุ่มได้ดีเยี่ยม
- สามารถจัดการการทำงานพร้อมกันหลายรายการได้อย่างมีประสิทธิภาพ
- NAND flash รองรับการเข้าถึงแบบขนานหลาย channel

### High-Performance NVMe SSD
```sql
-- แนะนำ: 200-500
ALTER SYSTEM SET effective_io_concurrency = 300;
```
**เหตุผล**:
- มี latency ต่ำมาก
- รองรับ queue depths สูง
- มีหลาย parallel channels

## คำแนะนำสำหรับ Cloud Platform

### Amazon RDS/EC2 with EBS
```sql
-- GP3/GP2 SSD
ALTER SYSTEM SET effective_io_concurrency = 150;

-- io1/io2 High-Performance SSD
ALTER SYSTEM SET effective_io_concurrency = 200;

-- st1 Throughput Optimized HDD
ALTER SYSTEM SET effective_io_concurrency = 4;
```

### Microsoft Azure Database for PostgreSQL
```sql
-- Premium SSD (Default สำหรับ tier ส่วนใหญ่)
ALTER SYSTEM SET effective_io_concurrency = 200;

-- Ultra SSD (High-performance tiers)
ALTER SYSTEM SET effective_io_concurrency = 300;
```

### Google Cloud SQL PostgreSQL
```sql
-- Standard Persistent Disk (SSD)
ALTER SYSTEM SET effective_io_concurrency = 150;

-- High-Performance Persistent Disk
ALTER SYSTEM SET effective_io_concurrency = 200;
```

## คำแนะนำเฉพาะสำหรับ Azure Database for PostgreSQL

### การคำนวณตาม Azure Instance Size

สำหรับ Azure Database for PostgreSQL แนะนำให้คำนวณจาก **Max IOPS** ของแต่ละ tier:

**สูตรการคำนวณ**: `effective_io_concurrency = Max IOPS × 0.1`

### ตัวอย่าง Azure Database Tiers

#### Basic Tier (ไม่แนะนำให้ปรับ)
```sql
-- Basic tier มี IOPS จำกัดมาก ใช้ค่า default
effective_io_concurrency = 1;  -- Keep default
```

#### General Purpose (Standard_B series - Burstable)
```sql
-- Standard_B1ms (1 vCore, 2GB, 640 IOPS)
ALTER SYSTEM SET effective_io_concurrency = 64;

-- Standard_B2s (2 vCores, 4GB, 1280 IOPS) 
ALTER SYSTEM SET effective_io_concurrency = 128;

-- Standard_B2ms (2 vCores, 8GB, 1280 IOPS)
ALTER SYSTEM SET effective_io_concurrency = 128;

-- Standard_B4ms (4 vCores, 16GB, 2560 IOPS)
ALTER SYSTEM SET effective_io_concurrency = 200;
```

#### General Purpose (Standard_D series)
```sql
-- Standard_D2s_v3 (2 vCores, 8GB, 3200 IOPS)
ALTER SYSTEM SET effective_io_concurrency = 200;

-- Standard_D4s_v3 (4 vCores, 16GB, 6400 IOPS)
ALTER SYSTEM SET effective_io_concurrency = 300;

-- Standard_D8s_v3 (8 vCores, 32GB, 12800 IOPS)
ALTER SYSTEM SET effective_io_concurrency = 400;
```

#### Memory Optimized (Standard_E series)
```sql
-- Standard_E2s_v3 (2 vCores, 16GB, 3200 IOPS)
ALTER SYSTEM SET effective_io_concurrency = 200;

-- Standard_E4s_v3 (4 vCores, 32GB, 6400 IOPS)
ALTER SYSTEM SET effective_io_concurrency = 300;

-- Standard_E8s_v3 (8 vCores, 64GB, 12800 IOPS)
ALTER SYSTEM SET effective_io_concurrency = 400;
```

### การปรับแต่งสำหรับ Azure B-series (Burstable)

**สำคัญ**: B-series ใช้ CPU Credit system จึงต้องระมัดระวังพิเศษ

```sql
-- สำหรับ B-series ควรเริ่มต้นด้วยค่าต่ำกว่าการคำนวณ
-- เพื่อป้องกัน CPU credit หมด

-- แทนที่จะใช้ค่าเต็ม ให้ใช้ 50-70% ของค่าที่คำนวณได้
-- Standard_B2s: แทน 128 → ใช้ 64-90
-- Standard_B4ms: แทน 256 → ใช้ 128-180
```

### การ Monitor สำหรับ Azure

#### ตรวจสอบ IOPS Usage
```sql
-- Monitor I/O patterns
SELECT 
    datname,
    blks_read as disk_reads,
    blks_hit as buffer_hits,
    CASE 
        WHEN (blks_read + blks_hit) > 0 
        THEN ROUND(blks_hit::numeric * 100.0 / (blks_read + blks_hit), 2) 
        ELSE 0 
    END as buffer_hit_ratio_percent
FROM pg_stat_database 
WHERE datname NOT IN ('template0', 'template1', 'postgres')
ORDER BY (blks_read + blks_hit) DESC;
```

#### ตรวจสอบ CPU Credit (สำหรับ B-series)
```bash
# ใช้ Azure CLI หรือ Portal ดู CPU Credit Balance
# หาก CPU Credit ต่ำ ควรลดค่า effective_io_concurrency
```

### แนวทางการทดสอบสำหรับ Azure

#### 1. Baseline Testing
```sql
-- ก่อนเปลี่ยนค่า: ทดสอบ query สำคัญ
SET effective_io_concurrency = 1;  -- Default
EXPLAIN (ANALYZE, BUFFERS, TIMING) 
SELECT * FROM critical_table 
WHERE important_conditions;
-- บันทึกเวลาและ buffer statistics
```

#### 2. Incremental Testing
```sql
-- ทดสอบค่าต่างๆ แบบค่อยเป็นค่อยไป
SET effective_io_concurrency = 50;
-- รัน test queries และบันทึกผล

SET effective_io_concurrency = 100;  
-- รัน test queries และบันทึกผล

SET effective_io_concurrency = 150;
-- รัน test queries และบันทึกผล
```

#### 3. Production Testing
```sql
-- เมื่อหาค่าที่ดีที่สุดแล้ว ใช้งานจริง
ALTER SYSTEM SET effective_io_concurrency = [optimal_value];
SELECT pg_reload_conf();

-- Monitor ต่อเนื่องเป็นระยะเวลา 1-2 สัปดาห์
```

### ข้อควรระวังเฉพาะ Azure

#### 1. **Burstable Performance (B-series)**
- อย่าตั้งค่าสูงเกินไปหาก CPU credit ไม่เพียงพอ
- Monitor CPU utilization ควบคู่กับ I/O performance

#### 2. **Storage Scaling**
- Azure Database สามารถ auto-scale storage ได้
- เมื่อ storage เพิ่มขึ้น IOPS ก็เพิ่มตาม → อาจต้องปรับค่าใหม่

#### 3. **Connection Pooling**
- ใช้ connection pooling (pgBouncer) เพื่อลดแรงกดดันต่อระบบ
- effective_io_concurrency ทำงานร่วมกับ connection pooling ได้ดี

### ตารางอ้างอิงสำหรับ Azure

| Azure Tier | vCores | Memory | Max IOPS | แนะนำ effective_io_concurrency |
|------------|--------|--------|----------|--------------------------------|
| B1ms       | 1      | 2 GB   | 640      | 64                            |
| B2s        | 2      | 4 GB   | 1,280    | 90-128                        |
| B2ms       | 2      | 8 GB   | 1,280    | 90-128                        |
| B4ms       | 4      | 16 GB  | 2,560    | 150-200                       |
| D2s_v3     | 2      | 8 GB   | 3,200    | 200-250                       |
| D4s_v3     | 4      | 16 GB  | 6,400    | 300-400                       |
| E2s_v3     | 2      | 16 GB  | 3,200    | 200-250                       |
| E4s_v3     | 4      | 32 GB  | 6,400    | 300-400                       |

## ตัวอย่างผลกระทบต่อประสิทธิภาพ

### ก่อนการ Optimize (Default = 1)
```sql
-- Query ที่มี bitmap heap scan
EXPLAIN (ANALYZE, BUFFERS) 
SELECT * FROM large_table 
WHERE category_id IN (1, 5, 10, 15, 20);

-- ผลลัพธ์ทั่วไป:
-- Bitmap Heap Scan: 2500ms
-- Buffers: read=10000 (อ่านแบบลำดับทั้งหมด)
```

### หลังการ Optimize (SSD = 200)
```sql
-- Query เดียวกัน
EXPLAIN (ANALYZE, BUFFERS) 
SELECT * FROM large_table 
WHERE category_id IN (1, 5, 10, 15, 20);

-- ผลลัพธ์หลัง optimize:
-- Bitmap Heap Scan: 450ms (เร็วขึ้น 5.5 เท่า)
-- Buffers: read=10000 (parallel prefetch)
```

## คู่มือการ Implementation

### ขั้นตอนที่ 1: ตรวจสอบการตั้งค่าปัจจุบัน
```sql
SELECT name, setting, unit, context 
FROM pg_settings 
WHERE name = 'effective_io_concurrency';
```

### ขั้นตอนที่ 2: ระบุประเภท Storage ของคุณ
```bash
# บน Linux ตรวจสอบประเภท disk
lsblk -d -o name,rota
# rota=1: HDD, rota=0: SSD

# สำหรับ cloud environments ให้ดูจาก service tier documentation
```

### ขั้นตอนที่ 3: ใช้งาน Configuration
```sql
-- วิธีที่ 1: ALTER SYSTEM (ต้องมี superuser privileges)
ALTER SYSTEM SET effective_io_concurrency = 200;
SELECT pg_reload_conf();

-- วิธีที่ 2: แก้ไขไฟล์ postgresql.conf
-- เพิ่มบรรทัด: effective_io_concurrency = 200
-- จากนั้น restart PostgreSQL
```

### ขั้นตอนที่ 4: ตรวจสอบการเปลี่ยนแปลง
```sql
-- ตรวจสอบค่าปัจจุบัน
SHOW effective_io_concurrency;

-- ตรวจสอบว่ามีผลแล้ว
SELECT name, setting, pending_restart 
FROM pg_settings 
WHERE name = 'effective_io_concurrency';
```

## การ Monitoring และ Testing

### การทดสอบประสิทธิภาพ Query
```sql
-- สร้างสถานการณ์ทดสอบ
EXPLAIN (ANALYZE, BUFFERS, TIMING) 
SELECT * FROM your_large_table 
WHERE indexed_column IN (
    SELECT id FROM another_table 
    WHERE condition = 'test'
);
```

### การ Monitor สถิติ I/O
```sql
-- สถิติ I/O ระดับ database
SELECT datname, 
       blks_read, 
       blks_hit,
       tup_returned,
       tup_fetched
FROM pg_stat_database 
WHERE datname = current_database();

-- สถิติ I/O ระดับ table
SELECT schemaname, tablename,
       heap_blks_read,
       heap_blks_hit,
       idx_blks_read,
       idx_blks_hit
FROM pg_statio_user_tables
ORDER BY heap_blks_read DESC;
```

## ข้อผิดพลาดทั่วไปและการแก้ไข

### การตั้งค่าสูงเกินไป
**ปัญหา**: `effective_io_concurrency = 1000` บน hardware ปานกลาง
**อาการ**: 
- Context switching เพิ่มขึ้น
- Memory pressure
- ประสิทธิภาพไม่ดีขึ้นหรือแย่ลง

**วิธีแก้**: เริ่มต้นด้วยค่าต่ำๆ แล้วค่อยเพิ่มทีละน้อย

### การตั้งค่าต่ำเกินไป
**ปัญหา**: `effective_io_concurrency = 1` บน high-performance SSD
**อาการ**:
- Bitmap heap scans ช้า
- ไม่ใช้ประโยชน์จาก storage IOPS เต็มที่
- ประสิทธิภาพแย่ในคำสั่ง query ที่ซับซ้อน

**วิธีแก้**: เพิ่มค่าให้เหมาะสมกับ storage

### ไม่ได้ Reload Configuration
**ปัญหา**: แก้ไข postgresql.conf แล้วแต่ไม่ได้ reload
**ตรวจสอบ**:
```sql
SELECT name, setting, pending_restart 
FROM pg_settings 
WHERE name = 'effective_io_concurrency';
-- หาก pending_restart = true แสดงว่าต้อง restart
```

## การตั้งค่าแบบ Advanced

### การตั้งค่าแต่ละ Tablespace
```sql
-- ตั้งค่าต่างกันสำหรับ tablespace ที่ต่างกัน
ALTER TABLESPACE fast_ssd_tablespace 
SET (effective_io_concurrency = 300);

ALTER TABLESPACE archive_hdd_tablespace 
SET (effective_io_concurrency = 2);
```

### การ Tune ตาม Workload
```sql
-- สำหรับ OLTP workloads (หลาย small queries)
effective_io_concurrency = 100-150

-- สำหรับ OLAP workloads (large analytical queries)  
effective_io_concurrency = 200-400

-- สำหรับ Mixed workloads
effective_io_concurrency = 150-200
```

## พารามิเตอร์ที่เกี่ยวข้อง

พารามิเตอร์เหล่านี้ทำงานร่วมกับ `effective_io_concurrency`:

```sql
-- Random page cost (ควรต่ำสำหรับ SSD)
random_page_cost = 1.1;  -- Default 4.0 เหมาะสำหรับ HDD

-- Sequential page cost
seq_page_cost = 1.0;     -- มักจะคงไว้เป็น 1.0

-- Maintenance work memory (สำหรับการ maintenance)
maintenance_work_mem = '256MB';
```

## Script สำหรับ Benchmarking

```sql
-- สร้างตารางทดสอบ
CREATE TABLE io_test AS
SELECT generate_series(1, 1000000) as id,
       md5(random()::text) as data,
       random() * 100 as category;

CREATE INDEX idx_io_test_category ON io_test(category);

-- ทดสอบ query ด้วยการตั้งค่าต่างกัน
SET effective_io_concurrency = 1;
EXPLAIN (ANALYZE, BUFFERS) 
SELECT * FROM io_test WHERE category BETWEEN 10 AND 20;

SET effective_io_concurrency = 200;
EXPLAIN (ANALYZE, BUFFERS) 
SELECT * FROM io_test WHERE category BETWEEN 10 AND 20;
```

## สรุป

พารามิเตอร์ `effective_io_concurrency` เป็นหนึ่งในการตั้งค่า PostgreSQL ที่มีผลกระทบสูงที่สุด แต่กลับถูกมองข้ามบ่อยครั้ง สำหรับการ deploy บน cloud สมัยใหม่ที่ใช้ SSD storage การเปลี่ยนจากค่า default (1) ไปเป็นค่าที่เหมาะสม (โดยทั่วไป 150-200) สามารถให้ผลลัพธ์ที่ดีขึ้นอย่างทันทีและมีนัยสำคัญโดยไม่มีข้อเสียใดๆ

**สิ่งสำคัญที่ควรจำ**:
- ค่า default (1) ล้าสมัยมากสำหรับ storage สมัยใหม่
- SSD storage บน cloud ควรใช้ค่า 150-200+  
- การเปลี่ยนแปลงต้องการเพียงการปรับ config และ reload
- การปรับปรุงประสิทธิภาพอาจมีนัยสำคัญมาก (query เร็วขึ้น 5-10 เท่า)
- ควรทดสอบและ monitor หลังการเปลี่ยนแปลงเสมอ

**รายการสิ่งที่ต้องทำ**:
1. ตรวจสอบการตั้งค่าปัจจุบัน
2. ระบุประเภท storage ของคุณ
3. ใช้ค่าที่เหมาะสมจากคู่มือนี้
4. ทดสอบ critical queries ก่อนและหลัง
5. Monitor เมตริกประสิทธิภาพ

จำไว้ว่า: นี่คือการ optimize แบบความเสี่ยงต่ำ ผลตอบแทนสูง ที่ทุกการ deploy PostgreSQL บน storage สมัยใหม่ควรจะดำเนินการ