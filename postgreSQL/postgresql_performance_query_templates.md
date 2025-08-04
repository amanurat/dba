
# ⚙️ PostgreSQL Performance Tuning: Query Template Collection

รวม Query Template สำหรับใช้วิเคราะห์ ปรับจูน และตรวจสอบ performance ของ PostgreSQL

---

## 🔍 1. ตรวจสอบ Slow Queries จาก `pg_stat_statements`

```sql
SELECT query, calls, total_time, mean_time, rows
FROM pg_stat_statements
ORDER BY total_time DESC
LIMIT 10;
```

> แสดง query ที่ใช้เวลารวมมากที่สุด

---

## 🔍 2. ตรวจสอบ Query ที่รันบ่อยที่สุด

```sql
SELECT query, calls, total_time, mean_time
FROM pg_stat_statements
ORDER BY calls DESC
LIMIT 10;
```

> ใช้หา query ที่เกิดขึ้นถี่ อาจใช้ connection pool หรือ optimize logic

---

## 🔍 3. ตรวจสอบ Query ที่ช้าที่สุดต่อครั้ง (Mean Time)

```sql
SELECT query, calls, mean_time, total_time
FROM pg_stat_statements
WHERE calls > 10
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
ORDER BY seq_scan_ratio DESC
LIMIT 10;
```

> ตารางที่มี seq scan เยอะ = น่าจะต้องสร้าง index เพิ่ม

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
