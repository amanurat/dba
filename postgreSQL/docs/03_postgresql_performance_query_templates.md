
# ⚙️ PostgreSQL Performance Tuning: Query Template Collection

รวม Query Template สำหรับใช้วิเคราะห์ ปรับจูน และตรวจสอบ performance ของ PostgreSQL

---

## 🔍 1. ตรวจสอบ Slow Queries จาก `pg_stat_statements`

```sql
SELECT query, calls, total_exec_time, mean_exec_time, rows
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
```

> แสดง query ที่ใช้เวลารวมมากที่สุด

---

## 🔍 2. ตรวจสอบ Query ที่รันบ่อยที่สุด

```sql
SELECT query, calls, total_exec_time, mean_exec_time
FROM pg_stat_statements
ORDER BY calls DESC
LIMIT 10;
```

> ใช้หา query ที่เกิดขึ้นถี่ อาจใช้ connection pool หรือ optimize logic

---

## 🔍 3. ตรวจสอบ Query ที่ช้าที่สุดต่อครั้ง (Mean Time)

```sql
SELECT query, calls, mean_exec_time, total_exec_time
FROM pg_stat_statements
WHERE calls > 10
ORDER BY mean_exec_time DESC
LIMIT 10;
```

> คัดเฉพาะ query ที่รันมากกว่า 10 ครั้ง เพื่อกรอง noise



## 🔍 4. ตรวจสอบ Query ที่ช้าที่สุดต่อครั้ง (Mean Time) (No Index)

```sql
SELECT query, calls, mean_time, rows
FROM pg_stat_statements
WHERE query NOT ILIKE '%index%'
  AND mean_time > 50
ORDER BY mean_time DESC
LIMIT 10;
```

> คัดเฉพาะ query ที่รันมากกว่า 10 ครั้ง เพื่อกรอง noise


---

## 🧠 4. ดู Table ที่ไม่มี Index แล้วมี Sequential Scan

```sql
SELECT relname AS table,
       seq_scan, idx_scan,
       seq_scan + idx_scan AS total_accesses,
       round(100.0 * seq_scan / (seq_scan + idx_scan + 1), 2) AS seq_scan_ratio
FROM pg_stat_user_tables
WHERE seq_scan + idx_scan > 0
ORDER BY seq_scan_ratio DESC
LIMIT 10;
```

> ตารางที่มี seq scan เยอะ = น่าจะต้องสร้าง index เพิ่ม

## 🔍 ดู Table ที่ไม่มี Index เลย (No Index At All)

```sql
SELECT tablename
FROM pg_tables
WHERE schemaname = 'public'
AND tablename NOT IN (
    SELECT tablename
    FROM pg_indexes
    WHERE schemaname = 'public'
);
```

📌 แสดงเป็น Checklist หรือ Warning Icon ใน Dashboard


## ⚠️ Unused Indexes (Optional)

```sql
SELECT relname AS indexname,
       idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes
JOIN pg_index USING (indexrelid)
WHERE NOT indisunique
AND idx_scan = 0;
```
📌 แสดงเพื่อช่วย DBA ทำ index cleanup


## 🔍 ดูตารางที่มีการเขียน (INSERT/UPDATE/DELETE) สูง

```sql
SELECT relname,
       n_tup_ins, n_tup_upd, n_tup_del,
       n_tup_ins + n_tup_upd + n_tup_del AS total_writes
FROM pg_stat_user_tables
ORDER BY total_writes DESC
LIMIT 10;

```
## 🔍 ตรวจสอบ buffer cache hit ratio

```sql
SELECT
    sum(heap_blks_hit) / nullif(sum(heap_blks_hit + heap_blks_read), 0)::float AS hit_ratio
FROM pg_statio_user_tables;


```




---

## 🔧 5. ตรวจสอบ Deadlock

```sql
SELECT * FROM pg_locks l
JOIN pg_stat_activity a ON l.pid = a.pid
WHERE NOT granted;
```

> ใช้ดูว่าเกิด lock ตรงไหนในระบบ

---

## 🔍 6. ตรวจสอบ Connection ที่ใช้

```sql
SELECT state, count(*)
FROM pg_stat_activity
GROUP BY state;
```

> ใช้ดูว่า connection ตอนนี้อยู่ในสถานะอะไร เช่น idle, active

---

## 🔍 7. ตรวจสอบ Transaction ที่เปิดค้างไว้

```sql
SELECT pid, usename, state, xact_start, query
FROM pg_stat_activity
WHERE state != 'idle' AND xact_start IS NOT NULL
ORDER BY xact_start;
```

> ใช้หาคนเปิด transaction ทิ้งไว้ (เสี่ยง lock)

---

## 💡 Tips:

- ใช้คู่กับ `EXPLAIN ANALYZE` เพื่อเข้าใจ plan
- เช็ค table ที่ใหญ่ แต่ไม่มี index
- อย่าลืม `ANALYZE` หลัง bulk update/insert
- ใช้ Connection Pool เช่น pgBouncer ช่วยเรื่อง connection burst

---

## ✅ Recommended Tools

- DBeaver, Azure Data Studio
- pgAdmin
- pg_stat_statements + auto_explain
- Log Analytics / Azure Monitor
