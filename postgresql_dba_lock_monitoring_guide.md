
# 🔐 PostgreSQL Lock Monitoring Guide for DBA

> A professional reference for Database Administrators to monitor and manage locking behavior in PostgreSQL, especially when running on Azure Cloud or in production systems.

---

## ✅ What DBA Should Monitor Related to Locks

| Category | What to Check | Why It Matters |
|---------|----------------|----------------|
| 🔍 Active Locks | Who is currently holding a lock? (`pg_locks`, `pg_stat_activity`) | Identify transactions holding critical resources |
| ⛔ Blocked Queries | Which query is being blocked, and by whom? | Troubleshoot performance issues and waiting queries |
| 🕒 Long-Running Locks | Locks held for an unusually long time (`query_start`, `xact_start`) | Can indicate forgotten commits or stuck jobs |
| 🔄 Lock Mode | Which lock types are most common? | E.g., `RowExclusiveLock`, `AccessExclusiveLock` |
| 📊 Lock Frequency by Table | Which tables are locked most frequently? | Detect hotspots and tuning opportunities |
| 💥 Deadlocks | Are there any deadlocks occurring? | Leads to aborted transactions and user complaints |
| 🧼 Idle Transactions | Long `idle in transaction` sessions | Causes bloat, lock waits, and resource waste |

---

## 🔧 Key Queries (with Purpose)

### 1. View All Current Locks
```sql
SELECT
    pg_stat_activity.pid,
    pg_stat_activity.usename,
    pg_locks.locktype,
    pg_locks.mode,
    pg_locks.granted,
    pg_stat_activity.query,
    pg_stat_activity.state,
    pg_stat_activity.query_start
FROM pg_locks
JOIN pg_stat_activity ON pg_locks.pid = pg_stat_activity.pid
WHERE pg_locks.mode IS NOT NULL
ORDER BY pg_stat_activity.query_start;
```

---

### 2. Detect Blocking / Blocked Relationships
```sql
-- Already shared earlier: join pg_locks with itself and pg_stat_activity
-- Output shows who is blocking whom and for how long
```

---

### 3. Lock Type Summary
```sql
SELECT mode, COUNT(*) AS count
FROM pg_locks
GROUP BY mode
ORDER BY count DESC;
```

---

### 4. Lock Frequency by Table
```sql
SELECT 
    c.relname AS table_name,
    l.mode,
    COUNT(*) AS lock_count
FROM pg_locks l
JOIN pg_class c ON c.oid = l.relation
GROUP BY c.relname, l.mode
ORDER BY lock_count DESC;
```

---

### 5. Idle In Transaction Check
```sql
SELECT pid, usename, state, query, query_start
FROM pg_stat_activity
WHERE state = 'idle in transaction'
ORDER BY query_start;
```

---

## 📦 Azure-Specific Lock Monitoring

| Tool | What You Can Monitor |
|------|----------------------|
| Log Analytics Workspace | Search lock-related logs using KQL |
| Intelligent Performance | Detect long queries with potential blocking |
| Query Store (if enabled) | Analyze I/O-intensive or long-running queries |
| Alerts | Configure alert: “Blocked connections > 5” or “Lock wait > 10s” |

---

## 🔁 Monitoring Frequency

| When | Frequency |
|------|-----------|
| Dev/UAT Deployments | Before every deploy |
| Production Daily Ops | Twice daily (morning + evening summary) |
| Production Realtime | On-demand or upon alert trigger |
| Pre-Restart | Always check for open transactions and locks |

---

## 🧠 Pro DBA Techniques

- Use Grafana + pgwatch2 or Azure Workbook dashboards
- Extract top blocked queries weekly for RCA (root cause analysis)
- Coach developers to avoid `BEGIN` without `COMMIT`
- Simulate lock contention under load testing using tools like JMeter

---

## 📁 Optional Assets

- SQL script: [`postgresql_lock_monitoring_queries.sql`](./postgresql_lock_monitoring_queries.sql)
- Grafana JSON Panel (ask to generate)
- Excel/Google Sheet Lock Audit Template (ask to generate)

