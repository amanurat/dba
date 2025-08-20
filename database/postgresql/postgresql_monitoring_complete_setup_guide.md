# 📊 PostgreSQL Monitoring & Performance Complete Setup Guide (Azure Flexible Server)

> **Comprehensive Guide**: From quick QPI setup to production-ready monitoring infrastructure on Azure PostgreSQL Flexible Server

---

## 📋 **Table of Contents**

- [🚀1: Quick Start - Enable QPI (5 minutes)](#-section-1-quick-start---enable-qpi-5-minutes)
- [⚙️2: Production Setup - Complete Parameters](#️-section-2-production-setup---complete-parameters)
- [🔧3: Advanced Features](#-section-3-advanced-features)
- [🚨4: Troubleshooting & Best Practices](#-section-5-troubleshooting--best-practices)

---

## 🚀 **Section 1: Quick Start - Enable QPI (5 minutes)**

> สำหรับคนที่ต้องการแค่ Query Performance Insight ให้ทำงานเร็วที่สุด

### **✅ Why Enable `pg_stat_statements`?**

| Feature | Purpose |
|--------|---------|
| `pg_stat_statements` | Captures executed SQL queries, their execution time, and usage stats |
| Query Performance Insight (QPI) | Visualizes slow/high-cost queries using data from `pg_stat_statements` |

### **🔧 Essential Parameters for QPI**

| Parameter | Recommended Value |
|-----------|-------------------|
| `azure.extensions` | `pg_stat_statements` |
| `shared_preload_libraries` | `pg_stat_statements` |
| `pg_stat_statements.track` | `all` |
| `pg_stat_statements.max` | `5000` |
| `track_io_timing` | `on` |

### **⚡ Quick Setup Steps**

1. **Azure Portal** → PostgreSQL Flexible Server → **Server Parameters**
2. Set parameters according to table above
3. **Save** and **Restart Server** (required for `shared_preload_libraries`)
4. Connect to database and run:
   ```sql
   CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
   ```

### **🧪 Post-Setup Verification (Quick Start)**

```sql
-- Step 1: Check extension is active
SELECT * FROM pg_extension WHERE extname = 'pg_stat_statements';
-- Expected: Should return 1 row with pg_stat_statements

-- Step 2: Verify parameters are set
SHOW shared_preload_libraries;
-- Expected: pg_stat_statements

SHOW pg_stat_statements.track;
-- Expected: all

-- Step 3: Test query tracking (generate some activity first)
SELECT version();
SELECT current_database();
SELECT COUNT(*) FROM information_schema.tables;

-- Step 4: Verify query stats are being collected
SELECT query, total_exec_time, mean_exec_time, calls
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
-- Expected: Should see the queries you just ran
```

### **📊 Azure QPI Verification**
1. Go to **Azure Portal** → PostgreSQL Server → **Query Performance Insight**
2. Should see query data within **15-30 minutes**
3. If no data appears: wait longer or check troubleshooting section

### **🔄 Restart Required?**

| Parameter | Requires Restart? |
|-----------|--------------------|
| `azure.extensions` | ⚠️ Usually yes |
| `shared_preload_libraries` | ✅ Yes |
| `pg_stat_statements.track` | ✅ Yes |
| `track_io_timing` | ⚠️ Often yes |

---

## ⚙️ **Section 2: Production Setup - Complete Parameters**

> สำหรับ production environment ที่ต้องการ comprehensive monitoring

### **🟢 Complete Parameter List**

| **Priority** | **Parameter** | **Recommended Value** | **Notes** |
|-------------|---------------|----------------------|-----------|
| **1** | **azure.extensions** | **pg_stat_statements,pg_buffercache,pg_prewarm** | **⚠️ Must set first - whitelist extensions** |
| **2** | shared_preload_libraries | pg_stat_statements | Load extension at startup |
| 3 | pg_stat_statements.track | all | Track all query types |
| 4 | pg_stat_statements.max | 10000 | Increased from 5000 for production |
| 5 | pg_stat_statements.save | on | Persist stats after restart |
| 6 | track_activity_query_size | 4096 | Increased from 2048 for long queries |
| 7 | track_io_timing | on | Track I/O timing |
| 8 | log_min_duration_statement | 1000 | Log queries slower than 1s |
| 9 | log_checkpoints | on | Log checkpoint activities |
| 10 | log_connections | on | Log connection attempts |
| 11 | log_disconnections | on | Log disconnections |
| 12 | log_lock_waits | on | Log lock wait events |
| **13** | **effective_io_concurrency** | **128-200** | **🔥 Critical for SSD performance** |

### **🎯 effective_io_concurrency Configuration by Azure Tier**

| **Azure Instance** | **vCores** | **Memory** | **Max IOPS** | **Recommended effective_io_concurrency** |
|-------------------|------------|------------|-------------|------------------------------------------|
| **B-series (Burstable)** |
| Standard_B1ms | 1 | 2 GB | 640 | 64 |
| Standard_B2s | 2 | 4 GB | 1,280 | **128** |
| Standard_B2ms | 2 | 8 GB | 1,280 | **128** |
| Standard_B4ms | 4 | 16 GB | 2,560 | 150-200 |
| **D-series (General Purpose)** |
| Standard_D2s_v3 | 2 | 8 GB | 3,200 | 200 |
| Standard_D4s_v3 | 4 | 16 GB | 6,400 | 300 |
| Standard_D8s_v3 | 8 | 32 GB | 12,800 | 400 |
| **E-series (Memory Optimized)** |
| Standard_E2s_v3 | 2 | 16 GB | 3,200 | 200 |
| Standard_E4s_v3 | 4 | 32 GB | 6,400 | 300 |
| Standard_E8s_v3 | 8 | 64 GB | 12,800 | 400 |

**คำนวณสูตร**: `effective_io_concurrency = Max IOPS × 0.1` (ปรับลดสำหรับ B-series)

### **🔧 Production Setup Methods**

#### **Method 1: Azure Portal (Recommended)**

**Step 1: Enable azure.extensions**
1. Go to **Azure Portal → PostgreSQL Flexible Server → Server Parameters**
2. Search for `azure.extensions`
3. Set value: `pg_stat_statements,pg_buffercache,pg_prewarm`
4. Click **Save**

**Step 2: Configure shared_preload_libraries**
1. Search for `shared_preload_libraries`
2. Set value: `pg_stat_statements`
3. Click **Save**

**Step 3: Configure performance parameters**
1. Set all parameters according to table above
2. **Important**: Set `effective_io_concurrency` according to your Azure tier
3. Click **Save**
4. **Restart Server** (required for shared_preload_libraries)

**Step 4: Create Extension**
```sql
-- After server restart, run this command
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

### **🧪 Post-Setup Verification (Production)**

```sql
-- Step 1: Verify all parameters are set correctly
SHOW azure.extensions;
-- Expected: pg_stat_statements,pg_buffercache,pg_prewarm

SHOW shared_preload_libraries;
-- Expected: pg_stat_statements

SHOW pg_stat_statements.track;
-- Expected: all

SHOW pg_stat_statements.max;
-- Expected: 10000

SHOW pg_stat_statements.save;
-- Expected: on

SHOW track_activity_query_size;
-- Expected: 4096

SHOW track_io_timing;
-- Expected: on

SHOW log_min_duration_statement;
-- Expected: 1000

-- Step 1.5: Verify effective_io_concurrency (CRITICAL!)
SHOW effective_io_concurrency;
-- Expected: 128-400 depending on your Azure tier
-- B2s should show: 128
-- D4s_v3 should show: 300

-- Step 2: Verify extension is installed
SELECT * FROM pg_extension WHERE extname = 'pg_stat_statements';
-- Expected: 1 row showing pg_stat_statements with version

-- Step 3: Test comprehensive functionality
SELECT COUNT(*) FROM pg_stat_statements;
-- Expected: Non-zero number (queries being tracked)

-- Step 4: Test with sample workload
CREATE TEMP TABLE test_monitoring (id INT, data TEXT);
INSERT INTO test_monitoring SELECT i, 'data_' || i FROM generate_series(1,1000) i;
SELECT COUNT(*) FROM test_monitoring WHERE id > 500;
DROP TABLE test_monitoring;

-- Step 5: Verify our test queries are tracked
SELECT 
    LEFT(query, 80) as query_preview,
    calls,
    total_exec_time,
    mean_exec_time,
    rows
FROM pg_stat_statements 
WHERE query LIKE '%S%'
ORDER BY total_exec_time DESC;
-- Expected: Should see our INSERT, SELECT, DROP queries

-- Step 6: Check top queries
SELECT 
    LEFT(query, 80) as query_preview,
    calls,
    total_exec_time,
    mean_exec_time,
    rows
FROM pg_stat_statements 
WHERE query NOT LIKE '%pg_stat_statements%'
ORDER BY total_exec_time DESC 
LIMIT 10;
-- Expected: Top 10 slowest queries in your system
```

### **📊 Production Monitoring Verification**

```sql
-- Database performance overview
SELECT
   'Total Queries' as metric,
   COUNT(*)::TEXT as value
FROM pg_stat_statements

UNION ALL

SELECT
   'Total Execution Time (ms)',
   ROUND(SUM(total_exec_time)::numeric)::TEXT
FROM pg_stat_statements

UNION ALL

SELECT
   'Average Query Time (ms)',
   ROUND(AVG(mean_exec_time)::numeric, 2)::TEXT
FROM pg_stat_statements

UNION ALL

SELECT
   'I/O Concurrency Setting',
   current_setting('effective_io_concurrency')
FROM pg_stat_statements
LIMIT 1;
-- Expected: Comprehensive statistics about your database workload including I/O settings
```

---

## 🔧 **Section 3: Advanced Features**

> สำหรับ enterprise environments ที่ต้องการ deep monitoring และ analytics

### **🔍 Enable Query Store (pg_qs)**

| Parameter | Value | Note |
|-----------|-------|------|
| pg_qs.query_capture_mode | ALL | Capture every query |
| pg_qs.query_capture_sample_rate | 1.0 | 100% capture rate |

### **⏱️ Enable Wait Sampling (pgms_wait_sampling)**

| Parameter | Value | Note |
|-----------|-------|------|
| pgms_wait_sampling.query_capture_mode | All | Case-sensitive |

### **📈 Advanced Performance Parameters**

```sql
-- Memory and Performance parameters for Azure
shared_buffers = '25% of RAM'                    -- Azure manages automatically
effective_cache_size = '75% of RAM'              -- Azure manages automatically  
work_mem = '4MB'                                 -- Increase for complex queries
maintenance_work_mem = '64MB'                    -- Increase for VACUUM, CREATE INDEX
checkpoint_completion_target = 0.9              -- Reduce I/O spikes
wal_buffers = '16MB'                            -- Increase WAL performance
random_page_cost = 1.1                         -- For SSD storage (Azure uses Premium SSD)
effective_io_concurrency = 200                 -- For SSD storage (adjust per tier)
```

### **🎯 I/O Performance Optimization for Azure**

```sql
-- Azure Database for PostgreSQL uses Premium SSD
-- Optimal settings for different workload types:

-- OLTP Workload (Many small transactions)
ALTER SYSTEM SET effective_io_concurrency = 128;  -- For B2s tier
ALTER SYSTEM SET random_page_cost = 1.1;
ALTER SYSTEM SET seq_page_cost = 1.0;

-- OLAP Workload (Large analytical queries)
ALTER SYSTEM SET effective_io_concurrency = 200;  -- For D4s_v3 tier
ALTER SYSTEM SET work_mem = '8MB';
ALTER SYSTEM SET maintenance_work_mem = '256MB';

-- Mixed Workload
ALTER SYSTEM SET effective_io_concurrency = 150;  -- Balanced setting
ALTER SYSTEM SET work_mem = '6MB';

-- Apply changes
SELECT pg_reload_conf();
```

### **🧪 Post-Setup Verification (Advanced Features)**

```sql
-- Step 1: Verify Query Store is active
SHOW pg_qs.query_capture_mode;
-- Expected: ALL

SHOW pg_qs.query_capture_sample_rate;
-- Expected: 1

-- Step 2: Verify Wait Sampling is active
SHOW pgms_wait_sampling.query_capture_mode;
-- Expected: All

-- Step 3: Test Query Store functionality
-- Generate some test load
SELECT pg_sleep(0.1);
CREATE TEMP TABLE qs_test AS SELECT * FROM generate_series(1,10000) i;
SELECT * FROM qs_test WHERE i > 5000;
DROP TABLE qs_test;

-- Step 4: Performance parameters verification
SHOW work_mem;
SHOW maintenance_work_mem; 
SHOW checkpoint_completion_target;
SHOW random_page_cost;
SHOW effective_io_concurrency;  -- Should match your Azure tier
-- Expected: Values should match your configuration

-- Step 5: I/O Performance Test
EXPLAIN (ANALYZE, BUFFERS) 
SELECT COUNT(*) FROM information_schema.columns 
WHERE table_name LIKE '%user%';
-- Expected: Should show buffer usage and timing information

-- Step 6: Advanced monitoring query
SELECT 
    'pg_stat_statements' as source,
    COUNT(*) as tracked_queries,
    ROUND(SUM(total_exec_time)) as total_time_ms,
    current_setting('effective_io_concurrency') as io_concurrency
FROM pg_stat_statements;
-- Expected: Query statistics with I/O concurrency setting
```

---

## 🚨 **Section 4: Troubleshooting & Best Practices**

> Common issues และวิธีแก้ปัญหาทั้งหมดที่พบบ่อย

### **🔍 Common Issues and Solutions**

#### **Issue 1: Extension Not Found After Server Configuration**

**Symptoms:**
```sql
CREATE EXTENSION pg_stat_statements;
-- ERROR: extension "pg_stat_statements" is not available
```

**Diagnostic Commands:**
```sql
-- Check server parameters
SHOW azure.extensions;           -- Should include pg_stat_statements
SHOW shared_preload_libraries;   -- Should include pg_stat_statements

-- Check available extensions
SELECT * FROM pg_available_extensions WHERE name = 'pg_stat_statements';
```

**Solution Steps:**
1. Verify `azure.extensions` includes `pg_stat_statements`
2. Verify `shared_preload_libraries` includes `pg_stat_statements`
3. Restart server if parameters were recently changed
4. Wait 10-15 minutes after restart for full initialization

**Verification:**
```sql
-- Should work after fix
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
SELECT * FROM pg_extension WHERE extname = 'pg_stat_statements';
```

#### **Issue 2: No Data in Query Performance Insight**

**Symptoms:**
- Azure QPI shows empty or "No data available"
- Parameters appear correct

**Diagnostic Commands:**
```sql
-- Check if queries are being tracked
SELECT COUNT(*) FROM pg_stat_statements;
-- Expected: > 0

-- Check tracking settings
SHOW pg_stat_statements.track;  -- Should be 'all'
SHOW pg_stat_statements.max;    -- Should be adequate (5000+)

-- Check recent activity
SELECT NOW() - pg_postmaster_start_time() as uptime;
-- Should be reasonable time for data collection
```

**Solution Steps:**
1. Wait 15-30 minutes after setup for data to appear
2. Generate some database activity
3. Reset statistics if needed: `SELECT pg_stat_statements_reset();`
4. Verify diagnostic settings are enabled in Azure Portal

**Verification:**
```sql
-- Generate test activity
SELECT version();
SELECT COUNT(*) FROM information_schema.tables;

-- Verify tracking
SELECT query, calls, total_exec_time 
FROM pg_stat_statements 
WHERE query LIKE '%information_schema%';
-- Expected: Should see your test queries
```

#### **Issue 3: Poor I/O Performance Despite Monitoring Setup**

**Symptoms:**
- Slow query performance on large tables
- High buffer read counts
- Bitmap heap scans taking longer than expected

**Diagnostic Commands:**
```sql
-- Check current I/O settings
SHOW effective_io_concurrency;
SHOW random_page_cost;
SHOW shared_buffers;

-- Check I/O patterns
SELECT 
    schemaname,
    tablename,
    heap_blks_read,
    heap_blks_hit,
    CASE 
        WHEN heap_blks_read + heap_blks_hit > 0 
        THEN ROUND(heap_blks_hit::numeric * 100.0 / (heap_blks_read + heap_blks_hit), 2)
        ELSE 0 
    END as buffer_hit_ratio
FROM pg_statio_user_tables
WHERE heap_blks_read + heap_blks_hit > 1000
ORDER BY heap_blks_read DESC
LIMIT 10;
```

**Solution Steps:**
1. Verify `effective_io_concurrency` matches your Azure tier:
   ```sql
   -- For Standard_B2s (1280 IOPS)
   ALTER SYSTEM SET effective_io_concurrency = 128;
   
   -- For Standard_D4s_v3 (6400 IOPS)  
   ALTER SYSTEM SET effective_io_concurrency = 300;
   
   SELECT pg_reload_conf();
   ```

2. Optimize for SSD storage:
   ```sql
   ALTER SYSTEM SET random_page_cost = 1.1;
   SELECT pg_reload_conf();
   ```

3. Test performance improvement:
   ```sql
   EXPLAIN (ANALYZE, BUFFERS) 
   SELECT * FROM your_large_table 
   WHERE your_indexed_column IN (SELECT ...);
   ```

#### **Issue 4: Permission Denied Errors**

**Symptoms:**
```sql
CREATE EXTENSION pg_stat_statements;
-- ERROR: permission denied to create extension
```

**Diagnostic Commands:**
```sql
-- Check current user and permissions
SELECT current_user, session_user;
SELECT rolname, rolsuper, rolcreatedb, rolcanlogin 
FROM pg_roles 
WHERE rolname = current_user;
```

**Solution Steps:**
1. Ensure user has `azure_pg_admin` role
2. Connect with proper administrative credentials
3. Verify database ownership permissions

**Verification:**
```sql
-- Should work after permission fix
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

#### **Issue 5: Inconsistent Query Statistics**

**Symptoms:**
- Different query counts between sessions
- Missing expected queries in statistics
- Statistics reset unexpectedly

**Diagnostic Commands:**
```sql
-- Check configuration
SHOW pg_stat_statements.save;    -- Should be 'on' for persistence
SHOW pg_stat_statements.max;     -- Check if too low

-- Check statistics age
SELECT pg_postmaster_start_time(), now();
SELECT stats_reset FROM pg_stat_database WHERE datname = current_database();
```

**Solution Steps:**
1. Set `pg_stat_statements.save = on` for persistence
2. Increase `pg_stat_statements.max` if hitting limits
3. Avoid manual statistics resets in production

**Verification:**
```sql
-- Test persistence across sessions
SELECT pg_stat_statements_reset();
SELECT version(); -- Generate activity
\q
-- Reconnect
SELECT COUNT(*) FROM pg_stat_statements;
-- Expected: Should have data if save=on
```

### **🎯 Best Practices Summary**

#### **✅ Do's**

- **Always backup parameters** before making changes
- **Test in development first** before applying to production
- **Set `pg_stat_statements.save = on`** for persistence across restarts
- **Use `pg_stat_statements.max = 10000`** for production workloads
- **Set `effective_io_concurrency` based on your Azure tier** for optimal I/O performance
- **Enable logging parameters** for comprehensive monitoring
- **Implement health checks** with automated scripts
- **Wait 15-30 minutes** after setup before expecting full data in QPI
- **Use appropriate I/O settings for Azure Premium SSD** (`random_page_cost = 1.1`)

#### **❌ Don'ts**

- **Don't skip the restart** after changing `shared_preload_libraries`
- **Don't use `SELECT *`** from `pg_stat_statements` in production (can be large)
- **Don't reset statistics** frequently in production
- **Don't ignore Azure extension whitelist** (`azure.extensions`)
- **Don't assume immediate data availability** in monitoring tools
- **Don't use default `effective_io_concurrency = 1`** on Azure (severely impacts performance)
- **Don't set `effective_io_concurrency` too high** for B-series instances (can exhaust CPU credits)

### **📊 Final Verification Checklist**

Use this checklist after completing any section:

```sql
-- ✅ Complete System Health Check
SELECT 
    'Parameter Check' as check_type,
    CASE WHEN setting LIKE '%pg_stat_statements%' THEN '✅ PASS' ELSE '❌ FAIL' END as status
FROM pg_settings WHERE name = 'shared_preload_libraries'

UNION ALL

SELECT 
    'Extension Check',
    CASE WHEN COUNT(*) > 0 THEN '✅ PASS' ELSE '❌ FAIL' END
FROM pg_extension WHERE extname = 'pg_stat_statements'

UNION ALL

SELECT 
    'Functionality Check',
    CASE WHEN COUNT(*) > 0 THEN '✅ PASS' ELSE '❌ FAIL' END  
FROM pg_stat_statements

UNION ALL

SELECT 
    'Data Collection Check',
    CASE WHEN MAX(calls) > 0 THEN '✅ PASS' ELSE '❌ FAIL' END
FROM pg_stat_statements

UNION ALL

SELECT 
    'I/O Concurrency Check',
    CASE 
        WHEN current_setting('effective_io_concurrency')::int >= 64 THEN '✅ PASS' 
        ELSE '❌ FAIL (Still using default=1)' 
    END
FROM pg_stat_statements LIMIT 1;
```

**Expected Result:**
```
check_type                | status
--------------------------|----------
Parameter Check           | ✅ PASS
Extension Check           | ✅ PASS  
Functionality Check       | ✅ PASS
Data Collection Check     | ✅ PASS
I/O Concurrency Check     | ✅ PASS
```

### **🚀 Performance Impact Verification**

```sql
-- Test I/O performance improvement
CREATE TEMP TABLE perf_test AS 
SELECT i, md5(i::text) as data 
FROM generate_series(1, 100000) i;

-- Test with bitmap scan
EXPLAIN (ANALYZE, BUFFERS) 
SELECT * FROM perf_test 
WHERE i IN (1000, 5000, 10000, 15000, 20000, 25000);

-- Expected: With proper effective_io_concurrency, should see:
-- - Reasonable execution time for bitmap heap scan
-- - Efficient buffer usage
-- - No excessive sequential reads
```

---

## 📚 **Resources and References**

### **Official Azure Documentation**
- [Azure PostgreSQL Flexible Server Parameters](https://docs.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-server-parameters)
- [Azure PostgreSQL Extensions](https://docs.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-extensions)
- [Query Performance Insight](https://docs.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-query-performance-insight)

### **PostgreSQL Official Documentation**
- [pg_stat_statements Extension](https://www.postgresql.org/docs/current/pgstatstatements.html)
- [Server Configuration](https://www.postgresql.org/docs/current/runtime-config.html)
- [Monitoring Database Activity](https://www.postgresql.org/docs/current/monitoring.html)

### **Performance Tuning Resources**
- [PostgreSQL I/O Concurrency Guide](https://www.postgresql.org/docs/current/runtime-config-resource.html#GUC-EFFECTIVE-IO-CONCURRENCY)
- [Azure Database for PostgreSQL Performance Best Practices](https://docs.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-performance-recommendations)

---