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