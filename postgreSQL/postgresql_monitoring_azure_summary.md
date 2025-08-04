
# 📘 PostgreSQL Monitoring & Performance Insight on Azure (Flexible Server)

รวมขั้นตอน + คำสั่งทั้งหมดสำหรับการเปิด Monitoring, วิเคราะห์ Slow Query, และ Benchmark PostgreSQL บน Azure แบบเข้าใจง่าย ✅

---

## 🧭 ขั้นตอนเริ่มต้น: เตรียม PostgreSQL บน Azure

1. ไปที่ Azure Portal > PostgreSQL Flexible Server
2. เปิดเมนู **Server Parameters**
3. ตั้งค่าดังนี้:

| Parameter                     | ค่า |
|------------------------------|-----|
| `shared_preload_libraries`   | `pg_stat_statements` |
| `pg_stat_statements.track`   | `all` |
| `pg_stat_statements.max`     | `10000` |
| `pg_stat_statements.save`    | `on` |

4. กด Save แล้ว **Restart Server**

---

## 🔍 ตรวจสอบว่า pg_stat_statements ทำงานหรือยัง

```sql
SHOW shared_preload_libraries;
SHOW pg_stat_statements.track;
SELECT * FROM pg_available_extensions WHERE name = 'pg_stat_statements';
SELECT * FROM pg_catalog.pg_stat_statements ORDER BY total_time DESC LIMIT 10;
```

> ⚠️ บน Azure อาจไม่สามารถรัน SELECT จาก `pg_stat_statements` ได้โดยตรง (ถูกจำกัด)

---

## 🔧 สร้าง Sample Data เพื่อทดสอบ Monitoring

```sql
CREATE TABLE customers (
  id SERIAL PRIMARY KEY,
  name TEXT,
  email TEXT,
  age INT,
  country TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO customers (name, email, age, country, created_at)
SELECT
  'Customer ' || i,
  'customer' || i || '@example.com',
  (random() * 60 + 18)::INT,
  CASE WHEN i % 5 = 0 THEN 'USA'
       WHEN i % 5 = 1 THEN 'Thailand'
       WHEN i % 5 == 2 THEN 'Germany'
       WHEN i % 5 == 3 THEN 'Japan'
       ELSE 'Brazil' END,
  NOW() - (random() * INTERVAL '365 days')
FROM generate_series(1, 100000) AS s(i);
```

---

## 🧪 จำลอง Slow Query

```sql
SELECT * FROM customers WHERE name LIKE '%5000%';
SELECT * FROM customers ORDER BY created_at DESC LIMIT 100;
SELECT COUNT(*) FROM customers WHERE age BETWEEN 30 AND 40;
```

---

## 📈 ใช้งาน Query Performance Insight (Azure Portal)

1. ไปที่ PostgreSQL Server > เมนู **Query Performance Insight**
2. ดู Top Query, Duration, Execution Count, Wait Stats
3. ใช้เพื่อวิเคราะห์ Slow Query และปัญหา Performance ได้โดยไม่ต้องใช้ SQL

---

## 📊 ใช้ Log Analytics ดู Raw Query Logs

### 1. ไปที่: Log Analytics Workspace > Logs
### 2. รัน Query เหล่านี้:

```kusto
// ดูทุก PostgreSQL log ล่าสุด
AzureDiagnostics
| where Category == "PostgreSQLLogs"
| sort by TimeGenerated desc
| limit 100

// ดูเฉพาะ slow query (duration)
AzureDiagnostics
| where Category == "PostgreSQLLogs"
| where message has "duration"
| project TimeGenerated, message
| sort by TimeGenerated desc

// ดู statement ที่เกี่ยวข้องกับ SELECT
AzureDiagnostics
| where Category == "PostgreSQLLogs"
| where statement_s has "SELECT"
| project TimeGenerated, statement_s
| sort by TimeGenerated desc
```

---

## 🛠 Tips & Troubleshooting

| ปัญหา | วิธีแก้ |
|--------|--------|
| `pg_stat_statements` ไม่โผล่ | เช็คว่า preload + restart แล้วจริง |
| SELECT จาก `pg_stat_statements` ไม่ได้ | ใช้ QPI หรือ Log Analytics แทน |
| log_s ไม่มีใน Kusto | ใช้ `| take 5` เพื่อดู schema ก่อน |
| ไม่มี query ใน QPI | รอ 5–15 นาที หรือรัน workload เพิ่ม |

---

## ✅ เครื่องมือแนะนำ

- Azure Data Studio + PostgreSQL Extension
- DBeaver / pgAdmin
- Log Analytics + Kusto Query (UI)
- Azure Query Performance Insight
