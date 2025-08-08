# 📊 PostgreSQL Index Analysis & Cost Estimation Guide

> Comprehensive guide for analyzing index usage, performance metrics, and query cost estimation in PostgreSQL databases

---

## 🎯 **Purpose**

This guide provides DBA tools and queries for:
- Analyzing index usage patterns and efficiency
- Estimating query execution costs
- Identifying performance bottlenecks
- Optimizing database performance through cost-based analysis

---

## 🔍 **1. Index Usage Analysis**

### **Query: Index Usage Statistics**
```sql
-- Analyze index usage and size across all user tables
SELECT 
    schemaname,
    relname AS table_name,
    indexrelname AS index_name,
    idx_scan AS index_scans,
    idx_tup_read AS tuples_read,
    idx_tup_fetch AS tuples_fetched,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    pg_relation_size(indexrelid) AS index_size_bytes
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC, pg_relation_size(indexrelid) DESC;
```

**Purpose**: Identify which indexes are being used frequently and their storage impact

**Key Metrics**:
- `idx_scan`: Number of index scans performed
- `idx_tup_read`: Number of index entries returned by scans
- `idx_tup_fetch`: Number of live table rows fetched by simple index scans
- `index_size`: Physical storage size of the index

**Analysis Guidelines**:
- **High Usage**: `idx_scan > 1000` indicates frequently used indexes
- **Unused Indexes**: `idx_scan = 0` may indicate candidates for removal
- **Large Indexes**: Monitor size vs. usage ratio for optimization opportunities

---

## 🧪 **2. Query Performance Analysis**

### **Query: Detailed Execution Plan Analysis**
```sql
-- Comprehensive execution plan with all performance metrics
EXPLAIN (
    ANALYZE true,     -- Execute and show actual times
    VERBOSE true,     -- Show additional details
    COSTS true,       -- Show cost estimates
    TIMING true,      -- Show timing information
    BUFFERS true      -- Show buffer usage
) 
SELECT * FROM your_table_name ORDER BY random();
```

**Purpose**: Get detailed performance metrics for query optimization

**Output Interpretation**:
- **Planning Time**: Time spent creating the execution plan
- **Execution Time**: Actual query execution time
- **Buffer Usage**: Memory and disk I/O patterns
- **Cost Estimates**: PostgreSQL's internal cost calculations

---

## 💰 **3. Cost Estimation Analysis**

### **Query: Sequential Scan Cost Calculation**
```sql
-- Calculate estimated costs for sequential scans
SELECT 
    relname AS table_name,
    relpages AS total_pages,
    current_setting('seq_page_cost')::decimal AS seq_page_cost_setting,
    relpages * current_setting('seq_page_cost')::decimal AS total_page_cost,
    reltuples AS estimated_rows,
    current_setting('cpu_tuple_cost')::decimal AS cpu_tuple_cost_setting,
    reltuples * current_setting('cpu_tuple_cost')::decimal AS total_tuple_cost,
    (relpages * current_setting('seq_page_cost')::decimal + 
     reltuples * current_setting('cpu_tuple_cost')::decimal) AS total_seq_scan_cost
FROM pg_class
WHERE relkind = 'r'  -- Regular tables only
  AND relname NOT LIKE 'pg_%'  -- Exclude system tables
ORDER BY total_seq_scan_cost DESC;
```

**Purpose**: Understand PostgreSQL's cost model for sequential scans

**Cost Components**:
- **Page Cost**: I/O cost for reading table pages from disk
- **CPU Tuple Cost**: Processing cost per row examined
- **Total Cost**: Combined I/O and CPU costs

---

## 🧪 **4. Performance Testing Framework**

### **Setup: Create Test Environment**
```sql
-- Create test table with known data distribution
DROP TABLE IF EXISTS performance_test_table;
CREATE TABLE performance_test_table AS 
SELECT 
    generate_series(1, 100000) AS id,
    'test_data_' || generate_series(1, 100000) AS description,
    random() * 1000 AS value,
    now() - (random() * interval '365 days') AS created_date;

-- Update table statistics for accurate cost estimation
ANALYZE performance_test_table;

-- Create various index types for testing
CREATE INDEX idx_perf_test_id ON performance_test_table(id);
CREATE INDEX idx_perf_test_value ON performance_test_table(value);
CREATE INDEX idx_perf_test_date ON performance_test_table(created_date);
CREATE INDEX idx_perf_test_composite ON performance_test_table(value, created_date);
```

### **Test: Function-Based Query Performance**
```sql
-- Test expensive function calls in WHERE clauses
EXPLAIN (ANALYZE, BUFFERS) 
SELECT * FROM performance_test_table 
WHERE cos(value) < 0.5;

-- Compare with indexed column filtering
EXPLAIN (ANALYZE, BUFFERS) 
SELECT * FROM performance_test_table 
WHERE value < 500;
```

**Analysis Points**:
- Function-based filters prevent index usage
- Compare execution times and buffer usage
- Identify opportunities for functional indexes

---

## 📈 **5. Index Efficiency Metrics**

### **Query: Index Efficiency Analysis**
```sql
-- Calculate index efficiency ratios
SELECT 
    schemaname,
    relname AS table_name,
    indexrelname AS index_name,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch,
    CASE 
        WHEN idx_tup_read > 0 THEN 
            round((idx_tup_fetch::decimal / idx_tup_read) * 100, 2)
        ELSE 0 
    END AS fetch_ratio_percent,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    CASE 
        WHEN idx_scan > 0 THEN 
            pg_relation_size(indexrelid) / idx_scan 
        ELSE pg_relation_size(indexrelid)
    END AS bytes_per_scan
FROM pg_stat_user_indexes
WHERE idx_scan > 0
ORDER BY bytes_per_scan DESC;
```

**Efficiency Indicators**:
- **Fetch Ratio**: Higher ratios indicate more selective indexes
- **Bytes per Scan**: Lower values suggest more efficient index usage
- **Scan Frequency**: Regular usage justifies index maintenance overhead

---

## 🚨 **6. Problem Detection Queries**

### **Query: Identify Problematic Patterns**
```sql
-- Find tables with no indexes (potential performance issues)
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS table_size
FROM pg_tables 
WHERE schemaname = 'public'
  AND tablename NOT IN (
      SELECT DISTINCT tablename 
      FROM pg_indexes 
      WHERE schemaname = 'public'
  )
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Find unused indexes consuming significant space
SELECT 
    schemaname,
    relname AS table_name,
    indexrelname AS unused_index,
    pg_size_pretty(pg_relation_size(indexrelid)) AS wasted_space,
    pg_relation_size(indexrelid) AS bytes_wasted
FROM pg_stat_user_indexes
WHERE idx_scan = 0
  AND pg_relation_size(indexrelid) > 10 * 1024 * 1024  -- > 10MB
ORDER BY pg_relation_size(indexrelid) DESC;
```

---

## 🛠 **7. Optimization Recommendations**

### **Index Maintenance Best Practices**

1. **Regular Analysis**
   ```sql
   -- Update statistics weekly or after significant data changes
   ANALYZE;
   ```

2. **Monitor Index Bloat**
   ```sql
   -- Check for index bloat and consider REINDEX if needed
   SELECT 
       schemaname, 
       tablename, 
       indexname,
       pg_size_pretty(pg_relation_size(indexname::regclass)) as size
   FROM pg_indexes 
   WHERE schemaname = 'public'
   ORDER BY pg_relation_size(indexname::regclass) DESC;
   ```

3. **Cost Parameter Tuning**
   ```sql
   -- Review and adjust cost parameters based on hardware
   SHOW seq_page_cost;      -- Default: 1.0
   SHOW random_page_cost;   -- Default: 4.0 (adjust for SSD: 1.1)
   SHOW cpu_tuple_cost;     -- Default: 0.01
   SHOW cpu_index_tuple_cost; -- Default: 0.005
   ```

---

## 📊 **8. Performance Monitoring Dashboard Queries**

### **Daily Index Health Check**
```sql
-- Daily index performance summary
SELECT 
    'Index Usage Summary' AS metric_type,
    COUNT(*) AS total_indexes,
    COUNT(*) FILTER (WHERE idx_scan > 0) AS used_indexes,
    COUNT(*) FILTER (WHERE idx_scan = 0) AS unused_indexes,
    pg_size_pretty(SUM(pg_relation_size(indexrelid))) AS total_index_size,
    pg_size_pretty(SUM(pg_relation_size(indexrelid)) FILTER (WHERE idx_scan = 0)) AS unused_index_size
FROM pg_stat_user_indexes;
```

---

## ✅ **9. Implementation Checklist**

- [ ] **Baseline Establishment**: Run initial index analysis
- [ ] **Regular Monitoring**: Schedule weekly index usage reviews
- [ ] **Cost Parameter Optimization**: Tune based on hardware characteristics
- [ ] **Index Cleanup**: Remove unused indexes consuming significant space
- [ ] **Performance Testing**: Validate changes in non-production environment
- [ ] **Documentation**: Maintain index strategy documentation
- [ ] **Alerting**: Set up monitoring for index usage patterns

---

## 🔗 **Related Documentation**

- [PostgreSQL EXPLAIN ANALYZE Guide](./06%20postgresql_explain_analyze_guide.md)
- [PostgreSQL Performance Query Templates](./04%20postgresql_performance_query_templates.md)
- [PostgreSQL Dashboard Index Recommendations](./05%20postgresql_dashboard_index_recommendations.md)

---

## 📚 **References**

- [PostgreSQL Query Planner Documentation](https://www.postgresql.org/docs/current/planner-optimizer.html)
- [PostgreSQL Statistics Collector](https://www.postgresql.org/docs/current/monitoring-stats.html)
- [Index Usage Patterns](https://www.postgresql.org/docs/current/indexes-types.html)