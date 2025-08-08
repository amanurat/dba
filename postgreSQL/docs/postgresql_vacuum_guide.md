
# PostgreSQL VACUUM Guide

> **⚠️ LEGACY DOCUMENT**: This guide has been superseded by the [Comprehensive VACUUM Management Guide](./postgresql_comprehensive_vacuum_guide.md)
> 
> **Recommendation**: Use the comprehensive guide for complete enterprise-grade VACUUM management, bloat monitoring, and automated maintenance procedures.

---

## 📋 **Migration Notice**

This document contains basic VACUUM concepts and a simple lab exercise. For production environments, please refer to:
- **[PostgreSQL Comprehensive VACUUM Management Guide](./postgresql_comprehensive_vacuum_guide.md)** - Complete enterprise solution
- Advanced bloat detection and remediation procedures
- Automated maintenance scheduling and performance monitoring
- Azure-specific integration and alerting frameworks

---

## 🔄 **Legacy Content** (Educational Purpose Only)

This document explains the basic behavior of PostgreSQL's `VACUUM`, `VACUUM FULL`, and how table size grows over time with updates when autovacuum is disabled.

---

## 🔍 Objective

Understand how PostgreSQL handles:
- Tuple versioning (MVCC)
- Space bloat after updates
- Cleanup with `VACUUM` and `VACUUM FULL`

---

## 🧪 Step-by-Step Lab

### 1. Create a new database and connect

```bash
createdb vacuum_test
psql vacuum_test
```

### 2. Create table with autovacuum disabled

```sql
CREATE TABLE vacuum_test (
    id int
) WITH (autovacuum_enabled = off);
```

### 3. Insert 100,000 rows

```sql
INSERT INTO vacuum_test
SELECT * FROM generate_series(1, 100000);
```

### 4. Check initial size

```sql
SELECT pg_size_pretty(pg_relation_size('vacuum_test'));
-- Expected: ~3.5 MB
```

### 5. Update all rows (1st round)

```sql
UPDATE vacuum_test SET id = id + 1;
SELECT pg_size_pretty(pg_relation_size('vacuum_test'));
-- Expected: ~7 MB (size doubles)
```

### 6. Update all rows (2nd round)

```sql
UPDATE vacuum_test SET id = id + 1;
SELECT pg_size_pretty(pg_relation_size('vacuum_test'));
-- Expected: ~10 MB
```

### 7. Run regular VACUUM

```sql
VACUUM vacuum_test;
SELECT pg_size_pretty(pg_relation_size('vacuum_test'));
-- Still ~10 MB (no shrink)
```

### 8. Run VACUUM FULL

```sql
VACUUM FULL vacuum_test;
SELECT pg_size_pretty(pg_relation_size('vacuum_test'));
-- Shrinks back to ~3.5 MB
```

---

## ⚠️ Key Takeaways

| Operation       | Description                                  | Disk Space Reclaimed? | Locks Table? |
|----------------|----------------------------------------------|------------------------|--------------|
| `VACUUM`        | Cleans dead tuples, updates stats            | ❌ No                  | ❌ No         |
| `VACUUM FULL`   | Rewrites table to remove bloat               | ✅ Yes                 | ✅ Yes        |
| `UPDATE`        | Creates new tuple, marks old as dead         | ❌ No                  | ❌ No         |

---

## 💬 Notes

- PostgreSQL uses MVCC (Multi-Version Concurrency Control), so old versions of rows remain after updates until vacuumed.
- Autovacuum normally runs in the background — this lab disables it to demonstrate space growth clearly.
- To automate space cleanup, enable autovacuum or schedule manual `VACUUM FULL` during maintenance.

---

## 📚 References

- [PostgreSQL VACUUM Documentation](https://www.postgresql.org/docs/current/sql-vacuum.html)
