# 📊 MySQL Monitoring & Performance Complete Setup Guide (Azure Flexible Server)

> **Comprehensive Guide**: From quick Performance Schema setup to production-ready monitoring infrastructure on Azure MySQL Flexible Server

---

## 📋 **Table of Contents**

- [🚀1: Quick Start - Enable Performance Schema (5 minutes)](#-section-1-quick-start---enable-performance-schema-5-minutes)
- [⚙️2: Production Setup - Complete Parameters](#️-section-2-production-setup---complete-parameters)
- [🔧3: Advanced Features](#-section-3-advanced-features)
- [🚨4: Troubleshooting & Best Practices](#-section-4-troubleshooting--best-practices)

---

## 🚀 **Section 1: Quick Start - Enable Performance Schema (5 minutes)**

> สำหรับคนที่ต้องการแค่ Performance Monitoring ให้ทำงานเร็วที่สุด

### **✅ Why Enable `Performance Schema`?**

| Feature | Purpose |
|--------|---------|
| `Performance Schema` | Captures executed SQL queries, their execution time, and system performance metrics |
| Azure Monitor | Visualizes performance metrics using data from Performance Schema |
| Slow Query Log | Records queries that exceed specified execution time threshold |

### **🔧 Essential Parameters for Monitoring**

| Parameter | Recommended Value |
|-----------|-------------------|
| `performance_schema` | `ON` |
| `slow_query_log` | `ON` |
| `long_query_time` | `1.0` |
| `log_queries_not_using_indexes` | `ON` |
| `innodb_monitor_enable` | `ALL` |

### **⚡ Quick Setup Steps**

1. **Azure Portal** → MySQL Flexible Server → **Server Parameters**
2. Set parameters according to table above
3. **Save** and **Restart Server** (required for `performance_schema`)
4. Connect to database and run verification queries

### **🧪 Post-Setup Verification (Quick Start)**

```sql
-- Step 1: Check Performance Schema is active
SHOW VARIABLES LIKE 'performance_schema';
-- Expected: ON

-- Step 2: Verify slow query log is enabled
SHOW VARIABLES LIKE 'slow_query_log';
SHOW VARIABLES LIKE 'long_query_time';
-- Expected: slow_query_log = ON, long_query_time = 1.000000

-- Generate some test activity
SELECT VERSION();
SELECT DATABASE();
SELECT COUNT(*) FROM information_schema.tables;

-- Step 3: Verify query stats are being collected
SELECT 
    LEFT(DIGEST_TEXT, 80) as query_preview,
    COUNT_STAR as execution_count,
    ROUND(SUM_TIMER_WAIT/1000000000000, 2) as total_time_seconds,
    ROUND(AVG_TIMER_WAIT/1000000000000, 4) as avg_time_seconds
FROM performance_schema.events_statements_summary_by_digest
WHERE DIGEST_TEXT IS NOT NULL
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 10;
-- Expected: Should see the queries you just ran
```

### **📊 Azure Monitor Verification**
1. Go to **Azure Portal** → MySQL Server → **Monitoring** → **Metrics**
2. Should see performance data within **15-30 minutes**
3. Key metrics to check: CPU percentage, Memory percentage, Active connections

### **🔄 Restart Required?**

| Parameter | Requires Restart? |
|-----------|--------------------|
| `performance_schema` | ✅ Yes |
| `slow_query_log` | ❌ No |
| `long_query_time` | ❌ No |
| `log_queries_not_using_indexes` | ❌ No |

---

## ⚙️ **Section 2: Production Setup - Complete Parameters**

> สำหรับ production environment ที่ต้องการ comprehensive monitoring

### **🟢 Complete Parameter List**

| **Priority** | **Parameter** | **Recommended Value** | **Notes** |
|--------------|---------------|----------------------|-----------|
| **1**        | **performance_schema** | **ON** | **⚠️ Must restart server** |
| 2            | performance_schema_max_sql_text_length | 4096 | Capture longer SQL queries |
| 3            | slow_query_log | ON | Enable slow query logging |
| 4            | long_query_time | 1.0 | Log queries slower than 1 second |
| 5            | log_queries_not_using_indexes | ON | Log queries without indexes |
| 6            | log_slow_admin_statements | ON | Log slow admin statements |
| 7            | log_slow_slave_statements | ON | Log slow replication statements |
| 8            | innodb_monitor_enable | '%' | Enable all InnoDB monitors |
| 9            | general_log | OFF | Keep disabled for performance |

### **🔧 Production Setup Methods**

#### **Method 1: Azure Portal (Recommended)**

**Step 1: Enable Performance Schema**
1. Go to **Azure Portal → MySQL Flexible Server → Server Parameters**
2. Search for `performance_schema`
3. Set value: `ON`
4. Click **Save**

**Step 2: Configure Performance Schema Settings**
1. Search for `performance_schema_max_table_instances`
2. Set value: `12500`
3. Search for `performance_schema_max_sql_text_length`
4. Set value: `4096`
5. Click **Save**

**Step 3: Configure Slow Query Log**
1. Set `slow_query_log = ON`
2. Set `long_query_time = 1.0`
3. Set `log_queries_not_using_indexes = ON`
4. Set `log_slow_admin_statements = ON`
5. Click **Save**

**Step 4: Restart Server**
```bash
# Azure CLI method
az mysql flexible-server restart \
  --resource-group your-rg \
  --name your-server
```

### **🧪 Post-Setup Verification (Production)**

```sql
-- Step 1: Verify all parameters are set correctly
SHOW VARIABLES LIKE 'performance_schema';
-- Expected: ON

SHOW VARIABLES LIKE 'slow_query_log';
-- Expected: ON

SHOW VARIABLES LIKE 'long_query_time';
-- Expected: 1.000000

SHOW VARIABLES LIKE 'log_queries_not_using_indexes';
-- Expected: ON

-- Step 2: Verify consumers are enabled
SELECT NAME, ENABLED 
FROM performance_schema.setup_consumers 
WHERE NAME IN (
    'events_statements_history_long'
);
-- Expected: All should show ENABLED = YES

-- Step 3: Test comprehensive functionality
SELECT COUNT(*) as active_instruments
FROM performance_schema.setup_instruments 
WHERE ENABLED = 'YES';
-- Expected: Non-zero number (many instruments enabled)

-- Step 4: Test with sample workload
CREATE TEMPORARY TABLE test_monitoring (
    id INT AUTO_INCREMENT PRIMARY KEY,
    data VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO test_monitoring (data) 
SELECT CONCAT('test_data_', i) 
FROM (
    SELECT 1 as i UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5
    UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9 UNION SELECT 10
) numbers;

SELECT COUNT(*) FROM test_monitoring WHERE id > 5;
DROP TABLE test_monitoring;

-- Step 5: Verify our test queries are tracked
SELECT 
    LEFT(DIGEST_TEXT, 80) as query_preview,
    COUNT_STAR as execution_count,
    ROUND(SUM_TIMER_WAIT/1000000000000, 2) as total_time_seconds,
    ROUND(AVG_TIMER_WAIT/1000000000000, 4) as avg_time_seconds
FROM performance_schema.events_statements_summary_by_digest 
WHERE DIGEST_TEXT LIKE '%test_monitoring%'
ORDER BY SUM_TIMER_WAIT DESC;
-- Expected: Should see our INSERT, SELECT, DROP queries

-- Step 6: Check top queries overall
SELECT 
    LEFT(DIGEST_TEXT, 80) as query_preview,
    COUNT_STAR as execution_count,
    ROUND(SUM_TIMER_WAIT/1000000000000, 2) as total_time_seconds,
    ROUND(AVG_TIMER_WAIT/1000000000000, 4) as avg_time_seconds
FROM performance_schema.events_statements_summary_by_digest 
WHERE DIGEST_TEXT IS NOT NULL
ORDER BY SUM_TIMER_WAIT DESC 
LIMIT 10;
-- Expected: Top 10 slowest queries in your system
```

### **📊 Production Monitoring Verification**

```sql
-- Database performance overview
SELECT 
    'Total Queries Executed' as metric,
    FORMAT(SUM(COUNT_STAR), 0) as value
FROM performance_schema.events_statements_summary_by_digest

UNION ALL

SELECT 
    'Total Execution Time (seconds)',
    FORMAT(SUM(SUM_TIMER_WAIT)/1000000000000, 2)
FROM performance_schema.events_statements_summary_by_digest

UNION ALL

SELECT 
    'Average Query Time (ms)',
    FORMAT(AVG(AVG_TIMER_WAIT)/1000000000, 2)
FROM performance_schema.events_statements_summary_by_digest

UNION ALL

SELECT
    'Buffer Pool Hit Ratio (%)' AS metric,
    FORMAT(
            100 - (
                (SELECT VARIABLE_VALUE
                 FROM performance_schema.global_status
                 WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads') * 100 /
                (SELECT VARIABLE_VALUE
                 FROM performance_schema.global_status
                 WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests')
                ),
            2
    ) AS value;
-- Expected: Comprehensive statistics about your database workload
```

---

## 🔧 **Section 3: Advanced Features**

> สำหรับ enterprise environments ที่ต้องการ deep monitoring และ analytics

### **🔍 Enable Comprehensive Wait Analysis**

```sql
-- Enable all wait event monitoring
UPDATE performance_schema.setup_instruments 
SET ENABLED = 'YES', TIMED = 'YES'
WHERE NAME LIKE 'wait/%';

-- Enable file I/O monitoring
UPDATE performance_schema.setup_instruments 
SET ENABLED = 'YES', TIMED = 'YES'
WHERE NAME LIKE 'wait/io/file/%';

-- Enable table I/O monitoring
UPDATE performance_schema.setup_instruments 
SET ENABLED = 'YES', TIMED = 'YES'
WHERE NAME LIKE 'wait/io/table/%';
```

### **⏱️ Enable Memory Usage Monitoring (MySQL 5.7+)**

```sql
-- Enable memory instruments
UPDATE performance_schema.setup_instruments 
SET ENABLED = 'YES' 
WHERE NAME LIKE 'memory/%';

-- Enable memory consumers
UPDATE performance_schema.setup_consumers 
SET ENABLED = 'YES' 
WHERE NAME LIKE '%memory%';
```

### **📈 Advanced Azure-Specific Parameters**

```sql
-- Azure MySQL specific optimizations
SET GLOBAL innodb_adaptive_hash_index = ON;
SET GLOBAL innodb_buffer_pool_dump_at_shutdown = ON;
SET GLOBAL innodb_buffer_pool_load_at_startup = ON;

-- For better monitoring granularity
SET GLOBAL innodb_monitor_enable = 'innodb_rwlock_%';
SET GLOBAL innodb_monitor_enable = 'innodb_buffer_pool_%';
```

### **🧪 Post-Setup Verification (Advanced Features)**

```sql
-- Step 1: Verify wait event monitoring
SELECT COUNT(*) as enabled_wait_instruments
FROM performance_schema.setup_instruments 
WHERE NAME LIKE 'wait/%' AND ENABLED = 'YES';
-- Expected: Many instruments enabled (100+)

-- Step 2: Verify memory monitoring (MySQL 5.7+)
SELECT COUNT(*) as enabled_memory_instruments
FROM performance_schema.setup_instruments 
WHERE NAME LIKE 'memory/%' AND ENABLED = 'YES';
-- Expected: Many memory instruments enabled

-- Step 3: Test comprehensive monitoring
-- Generate some I/O activity
SELECT COUNT(*) FROM information_schema.tables;
SELECT COUNT(*) FROM information_schema.columns;

-- Check wait statistics
SELECT 
    EVENT_NAME,
    COUNT_STAR as event_count,
    ROUND(SUM_TIMER_WAIT/1000000000000, 4) as total_wait_time_seconds
FROM performance_schema.events_waits_summary_global_by_event_name
WHERE COUNT_STAR > 0
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 10;
-- Expected: Various wait events with timing data

-- Step 4: Memory usage analysis (MySQL 5.7+)
SELECT 
    EVENT_NAME,
    CURRENT_NUMBER_OF_BYTES_USED as current_bytes,
    HIGH_NUMBER_OF_BYTES_USED as high_bytes
FROM performance_schema.memory_summary_global_by_event_name
WHERE CURRENT_NUMBER_OF_BYTES_USED > 0
ORDER BY CURRENT_NUMBER_OF_BYTES_USED DESC
LIMIT 10;
-- Expected: Memory usage statistics by component

-- Step 4: Memory usage analysis (Human readable)
SELECT
    EVENT_NAME AS component,
    ROUND(CURRENT_NUMBER_OF_BYTES_USED / 1024 / 1024, 2) AS current_mb,
    ROUND(HIGH_NUMBER_OF_BYTES_USED / 1024 / 1024, 2) AS high_mb,
    ROUND(
            (CURRENT_NUMBER_OF_BYTES_USED /
             (SELECT SUM(CURRENT_NUMBER_OF_BYTES_USED)
              FROM performance_schema.memory_summary_global_by_event_name)
                ) * 100,
            2) AS pct_of_total
FROM performance_schema.memory_summary_global_by_event_name
WHERE CURRENT_NUMBER_OF_BYTES_USED > 0
ORDER BY CURRENT_NUMBER_OF_BYTES_USED DESC
LIMIT 10;
    

-- Step 5: Table I/O statistics
SELECT
    OBJECT_SCHEMA AS db_name,
    OBJECT_NAME AS table_name,
    COUNT_READ AS `read_ops`,
        COUNT_WRITE AS `write_ops`,
        ROUND(SUM_TIMER_READ/1e12, 2) AS read_time_sec,
    ROUND(SUM_TIMER_WRITE/1e12, 2) AS write_time_sec,
    ROUND((SUM_TIMER_READ + SUM_TIMER_WRITE)/1e12, 2) AS total_time_sec,
    ROUND(
            ( (SUM_TIMER_READ + SUM_TIMER_WRITE) /
              (SELECT SUM(SUM_TIMER_READ + SUM_TIMER_WRITE)
               FROM performance_schema.table_io_waits_summary_by_table
               WHERE OBJECT_SCHEMA = DATABASE())
                ) * 100,
            2
    ) AS pct_of_total
FROM performance_schema.table_io_waits_summary_by_table
WHERE OBJECT_SCHEMA = DATABASE()
  AND (COUNT_READ > 0 OR COUNT_WRITE > 0)
ORDER BY total_time_sec DESC
LIMIT 10;
-- Expected: I/O statistics for your database tables
```

---

## 🚨 **Section 4: Troubleshooting & Best Practices**

> Common issues และวิธีแก้ปัญหาทั้งหมดที่พบบ่อย

### **🔍 Common Issues and Solutions**

#### **Issue 1: Performance Schema Disabled After Configuration**

**Symptoms:**
```sql
SHOW VARIABLES LIKE 'performance_schema';
-- Returns: OFF (despite being set to ON)
```

**Diagnostic Commands:**
```sql
-- Check error log for startup issues
SHOW VARIABLES LIKE 'log_error';

-- Check if server was properly restarted
SHOW STATUS LIKE 'Uptime';

-- Verify current parameter settings
SHOW VARIABLES LIKE 'performance_schema%';
```

**Solution Steps:**
1. Verify server was actually restarted after parameter change
2. Check Azure Activity Log for any restart failures
3. Ensure sufficient memory allocation (Performance Schema needs ~10% of total memory)
4. Try manual restart via Azure Portal or CLI

**Verification:**
```sql
-- Should work after fix
SHOW VARIABLES LIKE 'performance_schema';
-- Expected: ON
```

#### **Issue 2: No Query Data in Performance Schema**

**Symptoms:**
- Performance Schema enabled but no query statistics
- `events_statements_summary_by_digest` table is empty

**Diagnostic Commands:**
```sql
-- Check if consumers are enabled
SELECT NAME, ENABLED 
FROM performance_schema.setup_consumers 
WHERE NAME LIKE '%statement%';

-- Check if instruments are enabled
SELECT COUNT(*) as enabled_instruments
FROM performance_schema.setup_instruments 
WHERE NAME LIKE 'statement/%' AND ENABLED = 'YES';

-- Check for recent activity
SELECT COUNT(*) FROM performance_schema.events_statements_summary_by_digest;
```

**Solution Steps:**
1. Enable statement consumers manually
2. Enable statement instruments
3. Generate some database activity
4. Wait a few minutes for data collection

**Solution Queries:**
```sql
-- Enable consumers
UPDATE performance_schema.setup_consumers 
SET ENABLED = 'YES' 
WHERE NAME = 'events_statements_summary_by_digest';

-- Generate test activity
SELECT VERSION();
SELECT DATABASE();
```

**Verification:**
```sql
-- Generate test activity
SELECT COUNT(*) FROM information_schema.tables;

-- Verify tracking
SELECT 
    LEFT(DIGEST_TEXT, 50) as query,
    COUNT_STAR as executions
FROM performance_schema.events_statements_summary_by_digest 
WHERE DIGEST_TEXT LIKE '%information_schema%'
LIMIT 5;
-- Expected: Should see your test queries
```

#### **Issue 3: High Performance Schema Memory Usage**

**Symptoms:**
- Server memory usage increased significantly
- Performance degradation after enabling Performance Schema
- Out of memory errors

**Diagnostic Commands:**
```sql
-- Check Performance Schema memory usage
SHOW ENGINE PERFORMANCE_SCHEMA STATUS;

-- Check current memory parameters
SHOW VARIABLES LIKE 'performance_schema_max%';

-- Check system memory usage
SHOW STATUS LIKE 'Memory_used';
```

**Solution Steps:**
1. Reduce Performance Schema memory allocation
2. Disable unnecessary instruments/consumers
3. Increase server memory if needed

**Solution Queries:**
```sql
-- Disable heavy consumers if not needed
UPDATE performance_schema.setup_consumers 
SET ENABLED = 'NO' 
WHERE NAME = 'events_statements_history_long';

-- Disable detailed wait events if not needed
UPDATE performance_schema.setup_instruments 
SET ENABLED = 'NO' 
WHERE NAME LIKE 'wait/synch/%';
```

### **🎯 Best Practices Summary**

#### **✅ Do's**

- **Always backup parameters** before making changes
- **Test in development first** before applying to production  
- **Start with basic monitoring** then add advanced features gradually
- **Monitor Performance Schema memory usage** regularly
- **Use Azure Monitor** for long-term trend analysis
- **Implement automated health checks** with monitoring scripts
- **Document your monitoring setup** for team knowledge

#### **❌ Don'ts**

- **Don't enable all instruments at once** in production
- **Don't ignore memory impact** of Performance Schema
- **Don't forget to restart** after enabling Performance Schema
- **Don't use `SELECT *`** from large Performance Schema tables
- **Don't enable general_log** in production (performance impact)
- **Don't assume immediate data availability** after setup

### **📊 Final Verification Checklist**

Use this checklist after completing any section:

```sql
-- ✅ Complete System Health Check
SELECT 
    'Performance Schema Status' as check_type,
    CASE WHEN @@performance_schema = 1 THEN '✅ ENABLED' ELSE '❌ DISABLED' END as status

UNION ALL

SELECT 
    'Statement Monitoring',
    CASE WHEN COUNT(*) > 0 THEN '✅ ACTIVE' ELSE '❌ INACTIVE' END
FROM performance_schema.events_statements_summary_by_digest
WHERE DIGEST_TEXT IS NOT NULL

UNION ALL

SELECT 
    'Slow Query Log',
    CASE WHEN @@slow_query_log = 1 THEN '✅ ENABLED' ELSE '❌ DISABLED' END

UNION ALL

SELECT 
    'Data Collection',
    CASE WHEN COUNT(*) > 0 THEN '✅ WORKING' ELSE '❌ NO DATA' END
FROM performance_schema.events_statements_summary_by_digest
WHERE COUNT_STAR > 0;
```

**Expected Result:**
```
check_type                | status
--------------------------|----------
Performance Schema Status | ✅ ENABLED
Statement Monitoring      | ✅ ACTIVE  
Slow Query Log           | ✅ ENABLED
Data Collection          | ✅ WORKING
```

### **🔧 Useful Azure CLI Commands**

```bash
# Check server status
az mysql flexible-server show \
  --resource-group your-rg \
  --name your-server

# Update parameters
az mysql flexible-server parameter set \
  --resource-group your-rg \
  --server-name your-server \
  --name performance_schema \
  --value ON

# Restart server
az mysql flexible-server restart \
  --resource-group your-rg \
  --name your-server

# Check parameters
az mysql flexible-server parameter list \
  --resource-group your-rg \
  --server-name your-server \
  --query "[?contains(name, 'performance_schema')]"
```

---

## 📚 **Resources and References**

### **Official Azure Documentation**
- [Azure MySQL Flexible Server Parameters](https://docs.microsoft.com/en-us/azure/mysql/flexible-server/concepts-server-parameters)
- [Azure MySQL Monitoring](https://docs.microsoft.com/en-us/azure/mysql/flexible-server/concepts-monitoring)
- [Azure Monitor for MySQL](https://docs.microsoft.com/en-us/azure/mysql/flexible-server/concepts-monitoring)

### **MySQL Official Documentation**
- [MySQL Performance Schema](https://dev.mysql.com/doc/refman/8.0/en/performance-schema.html)
- [Performance Schema Setup](https://dev.mysql.com/doc/refman/8.0/en/performance-schema-startup-configuration.html)
- [Performance Schema Queries](https://dev.mysql.com/doc/refman/8.0/en/performance-schema-examples.html)

### **Performance Tuning Guides**
- [MySQL Performance Tuning Best Practices](https://dev.mysql.com/doc/refman/8.0/en/optimization.html)
- [Azure MySQL Best Practices](https://docs.microsoft.com/en-us/azure/mysql/flexible-server/concepts-performance-recommendations)

---

## 🎯 **Quick Reference Cards**

### **Essential Monitoring Queries**

```sql
-- Top 5 slowest queries
SELECT 
    LEFT(DIGEST_TEXT, 100) as query,
    COUNT_STAR as count,
    ROUND(AVG_TIMER_WAIT/1000000000000, 4) as avg_seconds
FROM performance_schema.events_statements_summary_by_digest 
ORDER BY AVG_TIMER_WAIT DESC LIMIT 5;

-- Buffer pool hit ratio
SELECT ROUND(100 - (
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads') * 100 /
    (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests')
), 2) AS hit_ratio_percent;

-- Current connections
SELECT VARIABLE_VALUE as current_connections
FROM information_schema.GLOBAL_STATUS 
WHERE VARIABLE_NAME = 'Threads_connected';

-- Table scan statistics
SELECT 
    OBJECT_SCHEMA,
    OBJECT_NAME,
    COUNT_READ as table_scans
FROM performance_schema.table_io_waits_summary_by_table
WHERE OBJECT_SCHEMA = DATABASE()
ORDER BY COUNT_READ DESC LIMIT 10;
```

### **Reset Commands for Testing**

```sql
-- Reset Performance Schema statistics
CALL sys.ps_truncate_all_tables(FALSE);

-- Reset specific statement statistics
TRUNCATE TABLE performance_schema.events_statements_summary_by_digest;

-- Reset InnoDB status counters
SET GLOBAL innodb_monitor_reset_all = '';
```

---

**🎉 การตั้งค่า MySQL Monitoring เสร็จสิ้น!**

ตอนนี้คุณมีระบบ monitoring ที่ครบครันสำหรับ MySQL บน Azure แล้ว ระบบนี้จะช่วยให้คุณติดตามประสิทธิภาพ หาปัญหา และปรับปรุง database ได้อย่างมีประสิทธิภาพ

**💡 จำไว้: การ Monitor ที่ดี = การแก้ปัญหาที่รวดเร็ว = ระบบที่เสถียร**