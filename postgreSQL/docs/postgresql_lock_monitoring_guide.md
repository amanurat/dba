
# 🔐 PostgreSQL Lock Monitoring Guide

> **⚠️ LEGACY DOCUMENT**: This guide has been superseded by the [Comprehensive Lock Monitoring Guide](./postgresql_comprehensive_lock_monitoring_guide.md)
> 
> **Recommendation**: Use the comprehensive guide for complete enterprise-grade lock monitoring capabilities with advanced features, alerting, and Azure integration.

---

## 📋 **Migration Notice**

This document contains basic lock monitoring queries. For production environments, please refer to:
- **[PostgreSQL Comprehensive Lock Monitoring Guide](./postgresql_comprehensive_lock_monitoring_guide.md)** - Complete enterprise solution
- **[Enhanced Lock Monitoring Queries](../postgresql_lock_monitoring_queries.sql)** - Professional SQL scripts

---

## 🔄 **Legacy Content** (Maintained for Reference)

---

## 🔍 1. View All Current Locks

```sql
SELECT
    pg_stat_activity.pid,
    pg_stat_activity.usename,
    pg_locks.locktype,
    pg_locks.mode,
    pg_locks.granted,
    pg_stat_activity.query,
    pg_stat_activity.state,
    pg_stat_activity.query_start,
    pg_stat_activity.backend_start,
    pg_stat_activity.application_name,
    pg_stat_activity.client_addr
FROM pg_locks
JOIN pg_stat_activity
    ON pg_locks.pid = pg_stat_activity.pid
WHERE pg_locks.mode IS NOT NULL
ORDER BY pg_stat_activity.query_start;
```

✅ Shows active locks, which queries are running, and who holds them.

---

## 🔄 2. Detect Blocking and Blocked Queries

```sql
SELECT
    blocked_locks.pid AS blocked_pid,
    blocked_activity.usename AS blocked_user,
    blocking_locks.pid AS blocking_pid,
    blocking_activity.usename AS blocking_user,
    blocked_activity.query AS blocked_query,
    blocking_activity.query AS blocking_query,
    blocked_activity.query_start AS blocked_query_start,
    now() - blocked_activity.query_start AS blocked_duration
FROM pg_locks blocked_locks
JOIN pg_stat_activity blocked_activity
    ON blocked_activity.pid = blocked_locks.pid
JOIN pg_locks blocking_locks
    ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
    AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
    AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
    AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
    AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
    AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
    AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
    AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
    AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_stat_activity blocking_activity
    ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;
```

✅ Identifies who is blocking whom, and the duration of the block.

---

## 📊 3. Count of Locks by Type

```sql
SELECT mode, COUNT(*) as count
FROM pg_locks
GROUP BY mode
ORDER BY count DESC;
```

✅ Helps you detect lock types that are overused or abnormally frequent.

---

## 📋 4. Locks by Table

```sql
SELECT 
    c.relname AS table_name,
    l.mode,
    l.granted,
    a.query,
    a.state,
    a.query_start
FROM pg_locks l
JOIN pg_class c ON c.oid = l.relation
JOIN pg_stat_activity a ON a.pid = l.pid
WHERE c.relname = 'your_table_name_here';
```

✅ Useful for monitoring locks on critical business tables.

---

## ⛔ 5. Terminate Blocking Session (Use with Caution)

```sql
SELECT pg_terminate_backend(<blocked_pid>);
```

⚠️ Only use when a query is stuck or causes critical production issues.

---

## ✅ Tips for DBA

- Monitor locks during peak transaction hours.
- Avoid long-running uncommitted transactions.
- Always check `pg_stat_activity` alongside `pg_locks`.

