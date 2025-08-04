
# 📊 Enabling `pg_stat_statements` for Azure Query Performance Insight

> This guide explains how to enable the `pg_stat_statements` extension in Azure PostgreSQL Flexible Server, which is **required** for Query Performance Insight (QPI) to function correctly.

---

## ✅ Why Enable `pg_stat_statements`?

| Feature | Purpose |
|--------|---------|
| `pg_stat_statements` | Captures executed SQL queries, their execution time, and usage stats |
| Query Performance Insight (QPI) | Visualizes slow/high-cost queries using data from `pg_stat_statements` |

---

## 🔧 Required Server Parameters

| Parameter | Recommended Value |
|-----------|-------------------|
| `shared_preload_libraries` | `pg_stat_statements` |
| `pg_stat_statements.track` | `all` |
| `pg_stat_statements.max` | `5000` or more |
| `track_activity_query_size` | `2048` |
| `track_io_timing` | `on` |

> 📌 Change these settings in:  
> Azure Portal → PostgreSQL Server → **Server Parameters**

---

## 🔄 Restart Required?

| Parameter | Requires Restart? |
|-----------|--------------------|
| `shared_preload_libraries` | ✅ Yes |
| `pg_stat_statements.track` | ✅ Yes |
| `track_activity_query_size` | ✅ Yes |
| Others (`max`, `io_timing`) | ⚠️ Often yes |

After saving changes, **manually restart the PostgreSQL server** to apply them.

---

## 🧪 Post-Setup Verification

```sql
-- Check if extension is active
SELECT * FROM pg_extension WHERE extname = 'pg_stat_statements';

-- Check query stats are being collected
SELECT query, total_time, mean_time, calls
FROM pg_stat_statements
ORDER BY total_time DESC
LIMIT 10;
```

---

## 🚫 If Not Enabled

| Impact | Explanation |
|--------|-------------|
| QPI won't show queries | It relies entirely on `pg_stat_statements` data |
| Index recommendations fail | Insight cannot detect high-cost scans |
| Less visibility | You lose key tuning insight for query optimization |

---

## 🧠 Pro Tips

- Always test in UAT before enabling in production
- Expect slight performance overhead (~2–5%) from tracking
- You can pair `pg_stat_statements` with `auto_explain` for deep diagnostics

---

## 📘 References

- Azure Docs: [pg_stat_statements on Azure PostgreSQL](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-monitoring#pg_stat_statements)
- PostgreSQL Official Docs: https://www.postgresql.org/docs/current/pgstatstatements.html
