
# 📊 PostgreSQL Dashboard: Queries That Should Use Index

> จุดประสงค์: ช่วยให้ Dev/DBA เห็นว่า query ใดในระบบควรใช้ index แต่ยังใช้ `Seq Scan` อยู่

---

## 🧭 Dashboard Section 1: Tables with High Sequential Scan Ratio

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

📌 ใช้แสดงเป็น Bar Chart:
- X-axis: table name
- Y-axis: % Sequential Scan

---

## 📈 Dashboard Section 2: Top 10 Slow Queries (No Index)

```sql
SELECT query, calls, mean_time, rows
FROM pg_stat_statements
WHERE query NOT ILIKE '%index%'
AND mean_time > 50
ORDER BY mean_time DESC
LIMIT 10;
```

📌 ใช้แสดงเป็น Data Table + optionally exportable

---

## 🔍 Dashboard Section 3: Tables With No Index At All

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

---

## ⚠️ Dashboard Section 4: Unused Indexes (Optional)

```sql
SELECT relname AS indexname,
       idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes
JOIN pg_index USING (indexrelid)
WHERE NOT indisunique
AND idx_scan = 0;
```

📌 แสดงเพื่อช่วย DBA ทำ index cleanup

---

## 🎯 Dashboard View Design

- 🔵 Graph 1: Sequential Scan Ratio (Bar Chart)
- 🔵 Table 2: Top Slow Queries without Index (Data Grid)
- 🔵 Warning List: Tables without any index
- 🔵 Optional Chart: Unused Indexes

---

## ✅ Tools to Build This Dashboard

| Platform | Notes |
|----------|-------|
| Grafana (via PostgreSQL plugin) | Real-time charts |
| Azure Workbooks (Log Analytics) | ใช้ KQL + Custom chart |
| pgAdmin Dashboards | Basic graph |
| Metabase / Redash | Visual-friendly |

---

## 🧠 Suggestion: Add auto-refresh every 15 mins and export to Notion / Jira if slow query is detected

