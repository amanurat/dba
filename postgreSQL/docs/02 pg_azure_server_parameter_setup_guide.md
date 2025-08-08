
# ⚙️ PostgreSQL Azure – Server Parameter Setup Guide (Flexible Server)

> คู่มือการตั้งค่า Server Parameters สำหรับ Tuning และ Monitoring เพื่อใช้งานกับ Query Performance Insight, Log Analytics และ Performance Tuning บน Azure

---

## 🟢 **1. Parameter ที่ควรตั้งค่า**

| Parameter                  | ค่าแนะนำ           | หมายเหตุ                          |
|----------------------------|--------------------|-----------------------------------|
| shared_preload_libraries   | pg_stat_statements | ต้อง Save & Restart Server        |
| pg_stat_statements.track   | all                | เก็บ query ทุกประเภท              |
| pg_stat_statements.max     | 5000               | หรือมากกว่า ขึ้นกับ workload      |
| track_activity_query_size  | 2048               | หรือมากกว่า สำหรับ query ยาวๆ     |
| track_io_timing            | on                 | เก็บเวลาการ I/O                   |
| log_min_duration_statement | 1000               | ms. Log เฉพาะ query ที่ช้ากว่า 1s |

**How To:**
- Go to **Azure Portal → PostgreSQL Flexible Server → Server Parameters**
- Set above values
- Save and **Restart Server**
- After restart, connect to your database and run:
    ```sql
    CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
    ```

---

## 2️⃣ **Enable Query Store (pg_qs)**

| Parameter                      | Value      | Note                     |
|---------------------------------|------------|--------------------------|
| pg_qs.query_capture_mode        | ALL or TOP | ALL = capture every query<br>TOP = capture top queries only |
| pg_qs.query_capture_sample_rate | 1.0        | (100% capture)           |

**How To:**
- In **Server Parameters**, search for `pg_qs`
- Set:
   - `pg_qs.query_capture_mode = ALL`
   - `pg_qs.query_capture_sample_rate = 1.0`
- Save (restart usually not required, but do so if prompted)

---
## 3️⃣ **Enable Wait Sampling (pgms_wait_sampling)**

| Parameter                                  | Value    | Note                |
|---------------------------------------------|----------|---------------------|
| pgms_wait_sampling.query_capture_mode       | All      | Case-sensitive      |

**How To:**
- In **Server Parameters**, search for `wait_sampling`
- Set: `pgms_wait_sampling.query_capture_mode = All`
- Save (restart if required)

---

## 🟡 **2. วิธีตั้งค่าใน Azure Portal**

1. ไปที่ Azure Portal → PostgreSQL Flexible Server → **Server Parameters**
2. ค้นหาคำว่า “stat” หรือ “track” เพื่อเจอ parameter เหล่านี้
3. ตั้งค่าตามตารางด้านบน
4. Save (ถ้าค่าต้อง restart ระบบจะแจ้งเตือน)
5. ทำการ Restart Server (ถ้ามีค่าที่ต้อง restart)
6. (ถ้ายังไม่มี extension)  
   รันใน SQL editor:  
   ```sql
   CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
   ```

---

## 🧪 **3. ตรวจสอบผล**

รันคำสั่ง SQL ต่อไปนี้ เพื่อเช็คค่าปัจจุบัน

```sql
SHOW shared_preload_libraries;
SHOW pg_stat_statements.track;
SHOW track_io_timing;
SHOW log_min_duration_statement;
SELECT * FROM pg_extension WHERE extname = 'pg_stat_statements';
```

---

## ✅ **4. หมายเหตุเพิ่มเติม**

- `shared_preload_libraries` ต้อง restart server เสมอ
- `log_min_duration_statement` ใส่ค่า 0 = log ทุก query (ไม่แนะนำบน production)
- ตั้งค่าเหล่านี้ก่อนเปิด Log Analytics/Diagnostics เพื่อให้ log มี data สำคัญ

---


## 4️⃣ **Verify Setup**

After configuration, connect to your DB and check:

```sql
-- Should show an installed row
SELECT * FROM pg_extension WHERE extname = 'pg_stat_statements';

-- Query Store/Wait Sampling: check on Query Performance Insight page

SELECT * FROM pg_settings WHERE name IN ('pg_qs.query_capture_mode', 'pgms_wait_sampling.query');

```


## 📦 **Resource**

- [Azure PostgreSQL Monitoring](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-monitoring)
- [PostgreSQL pg_stat_statements Docs](https://www.postgresql.org/docs/current/pgstatstatements.html)
