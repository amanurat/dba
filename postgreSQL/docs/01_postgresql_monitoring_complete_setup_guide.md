# 📊 PostgreSQL Monitoring & Performance Complete Setup Guide (Azure Flexible Server)

> **Comprehensive Guide**: From quick QPI setup to production-ready monitoring infrastructure on Azure PostgreSQL Flexible Server

---

## 📋 **Table of Contents**

- [🚀 Section 1: Quick Start - Enable QPI (5 minutes)](#-section-1-quick-start---enable-qpi-5-minutes)
- [⚙️ Section 2: Production Setup - Complete Parameters](#️-section-2-production-setup---complete-parameters)
- [🔧 Section 3: Advanced Features](#-section-3-advanced-features)
- [🤖 Section 4: Automation & Scripts](#-section-4-automation--scripts)
- [🚨 Section 5: Troubleshooting & Best Practices](#-section-5-troubleshooting--best-practices)

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

**Step 3: Configure other parameters**
1. Set all parameters according to table above
2. Click **Save**
3. **Restart Server** (required for shared_preload_libraries)

**Step 4: Create Extension**
```sql
-- After server restart, run this command
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

#### **Method 2: Azure CLI (For DevOps)**

```bash
# Variables (replace with your values)
RESOURCE_GROUP="your-resource-group"
SERVER_NAME="your-server-name"

# Step 1: Enable azure.extensions
az postgres flexible-server parameter set \
  --resource-group $RESOURCE_GROUP \
  --server-name $SERVER_NAME \
  --name azure.extensions \
  --value "pg_stat_statements,pg_buffercache,pg_prewarm"

# Step 2: Configure shared_preload_libraries
az postgres flexible-server parameter set \
  --resource-group $RESOURCE_GROUP \
  --server-name $SERVER_NAME \
  --name shared_preload_libraries \
  --value "pg_stat_statements"

# Step 3: Configure pg_stat_statements parameters
az postgres flexible-server parameter set \
  --resource-group $RESOURCE_GROUP \
  --server-name $SERVER_NAME \
  --name pg_stat_statements.track \
  --value "all"

az postgres flexible-server parameter set \
  --resource-group $RESOURCE_GROUP \
  --server-name $SERVER_NAME \
  --name pg_stat_statements.max \
  --value "10000"

az postgres flexible-server parameter set \
  --resource-group $RESOURCE_GROUP \
  --server-name $SERVER_NAME \
  --name pg_stat_statements.save \
  --value "on"

# Step 4: Restart server
az postgres flexible-server restart \
  --resource-group $RESOURCE_GROUP \
  --name $SERVER_NAME
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
    LEFT(query, 60) as query_preview,
    calls,
    total_exec_time,
    mean_exec_time,
    rows
FROM pg_stat_statements 
WHERE query LIKE '%test_monitoring%'
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
FROM pg_stat_statements;
-- Expected: Comprehensive statistics about your database workload
```

---

## 🔧 **Section 3: Advanced Features**

> สำหรับ enterprise environments ที่ต้องการ deep monitoring และ analytics

### **🔍 Enable Query Store (pg_qs)**

| Parameter | Value | Note |
|-----------|-------|------|
| pg_qs.query_capture_mode | ALL | Capture every query |
| pg_qs.query_capture_sample_rate | 1.0 | 100% capture rate |

**Setup:**
```bash
az postgres flexible-server parameter set \
  --name pg_qs.query_capture_mode \
  --value "ALL"

az postgres flexible-server parameter set \
  --name pg_qs.query_capture_sample_rate \
  --value "1.0"
```

### **⏱️ Enable Wait Sampling (pgms_wait_sampling)**

| Parameter | Value | Note |
|-----------|-------|------|
| pgms_wait_sampling.query_capture_mode | All | Case-sensitive |

**Setup:**
```bash
az postgres flexible-server parameter set \
  --name pgms_wait_sampling.query_capture_mode \
  --value "All"
```

### **📈 Advanced Performance Parameters**

```sql
-- Memory and Performance parameters for Azure
shared_buffers = '25% of RAM'                    -- Azure manages automatically
effective_cache_size = '75% of RAM'              -- Azure manages automatically  
work_mem = '4MB'                                 -- Increase for complex queries
maintenance_work_mem = '64MB'                    -- Increase for VACUUM, CREATE INDEX
checkpoint_completion_target = 0.9              -- Reduce I/O spikes
wal_buffers = '16MB'                            -- Increase WAL performance
random_page_cost = 1.1                         -- For SSD storage
effective_io_concurrency = 200                 -- For SSD storage
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
SELECT COUNT(*) FROM qs_test;
DROP TABLE qs_test;

-- Check if Query Store captured the queries
SELECT 
    query_sql_text,
    execution_count,
    total_query_exec_time,
    mean_query_exec_time
FROM query_store.qs_view
WHERE query_sql_text LIKE '%qs_test%'
ORDER BY total_query_exec_time DESC;
-- Expected: Should see our test queries

-- Step 4: Performance parameters verification
SHOW work_mem;
SHOW maintenance_work_mem; 
SHOW checkpoint_completion_target;
SHOW random_page_cost;
-- Expected: Values should match your configuration

-- Step 5: Advanced monitoring query
SELECT 
    'pg_stat_statements' as source,
    COUNT(*) as tracked_queries,
    ROUND(SUM(total_exec_time)) as total_time_ms
FROM pg_stat_statements

UNION ALL

SELECT 
    'query_store',
    COUNT(*),
    ROUND(SUM(total_query_exec_time))
FROM query_store.qs_view;
-- Expected: Both sources should show query statistics
```

---

## 🤖 **Section 4: Automation & Scripts**

> Tools และ scripts สำหรับการจัดการ monitoring แบบอัตโนมัติ

### **📦 ARM Template (Infrastructure as Code)**

```json
{
  "type": "Microsoft.DBforPostgreSQL/flexibleServers/configurations",
  "apiVersion": "2021-06-01",
  "name": "[concat(parameters('serverName'), '/azure.extensions')]",
  "properties": {
    "value": "pg_stat_statements,pg_buffercache,pg_prewarm",
    "source": "user-override"
  }
},
{
  "type": "Microsoft.DBforPostgreSQL/flexibleServers/configurations", 
  "apiVersion": "2021-06-01",
  "name": "[concat(parameters('serverName'), '/shared_preload_libraries')]",
  "properties": {
    "value": "pg_stat_statements",
    "source": "user-override"
  }
},
{
  "type": "Microsoft.DBforPostgreSQL/flexibleServers/configurations",
  "apiVersion": "2021-06-01", 
  "name": "[concat(parameters('serverName'), '/pg_stat_statements.max')]",
  "properties": {
    "value": "10000",
    "source": "user-override"
  }
}
```

### **🔍 Health Check Script**

```bash
#!/bin/bash
# postgresql_monitoring_health_check.sh
# Comprehensive health check for PostgreSQL monitoring setup

SERVER_NAME="your-server-name"
RESOURCE_GROUP="your-resource-group"
DB_HOST="$SERVER_NAME.postgres.database.azure.com"
DB_USER="your_user"
DB_NAME="your_database"

echo "=== PostgreSQL Monitoring Health Check ==="
echo "Server: $SERVER_NAME"
echo "Date: $(date)"
echo "User: $DB_USER"
echo

# Check server status
echo "1. Server Status:"
az postgres flexible-server show \
  --resource-group $RESOURCE_GROUP \
  --name $SERVER_NAME \
  --query "state" -o tsv

# Check parameters
echo "2. Parameter Configuration:"
psql "host=$DB_HOST user=$DB_USER dbname=$DB_NAME sslmode=require" -c "
    SELECT 'azure.extensions' as parameter, setting as value FROM pg_settings WHERE name = 'azure.extensions'
    UNION ALL
    SELECT 'shared_preload_libraries', setting FROM pg_settings WHERE name = 'shared_preload_libraries'
    UNION ALL  
    SELECT 'pg_stat_statements.track', setting FROM pg_settings WHERE name = 'pg_stat_statements.track'
    UNION ALL
    SELECT 'pg_stat_statements.max', setting FROM pg_settings WHERE name = 'pg_stat_statements.max';
"

# Check extensions
echo "3. Extension Status:"
psql "host=$DB_HOST user=$DB_USER dbname=$DB_NAME sslmode=require" -c "
    SELECT 
        extname as extension_name,
        extversion as version,
        CASE WHEN extname IS NOT NULL THEN 'INSTALLED' ELSE 'NOT_INSTALLED' END as status
    FROM pg_extension 
    WHERE extname IN ('pg_stat_statements', 'pg_buffercache');
"

# Check functionality  
echo "4. Functionality Test:"
psql "host=$DB_HOST user=$DB_USER dbname=$DB_NAME sslmode=require" -c "
    SELECT 
        COUNT(*) as tracked_queries,
        ROUND(SUM(total_exec_time)) as total_execution_time_ms,
        ROUND(AVG(mean_exec_time), 2) as avg_execution_time_ms
    FROM pg_stat_statements;
"

# Top 5 queries
echo "5. Top 5 Slow Queries:"
psql "host=$DB_HOST user=$DB_USER dbname=$DB_NAME sslmode=require" -c "
    SELECT 
        LEFT(query, 60) as query_preview,
        calls,
        ROUND(total_exec_time, 2) as total_time_ms,
        ROUND(mean_exec_time, 2) as avg_time_ms
    FROM pg_stat_statements 
    WHERE query NOT LIKE '%pg_stat_statements%'
    ORDER BY total_exec_time DESC 
    LIMIT 5;
"

echo "=== End of Health Check ==="
```

### **💾 Parameter Backup Script**

```bash
#!/bin/bash
# backup_postgresql_parameters.sh
# Backup current server parameters for disaster recovery

RESOURCE_GROUP="your-resource-group"
SERVER_NAME="your-server-name"
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)

echo "Backing up PostgreSQL parameters..."

# Backup all user-override parameters
az postgres flexible-server parameter list \
  --resource-group $RESOURCE_GROUP \
  --server-name $SERVER_NAME \
  --query "[?source=='user-override'].{name:name,value:value}" \
  -o json > "postgresql_parameters_backup_${BACKUP_DATE}.json"

# Create restore script
cat > "restore_parameters_${BACKUP_DATE}.sh" << EOF
#!/bin/bash
# Auto-generated restore script for PostgreSQL parameters
# Generated on: $(date)
# Server: $SERVER_NAME
# Resource Group: $RESOURCE_GROUP

RESOURCE_GROUP="$RESOURCE_GROUP"
SERVER_NAME="$SERVER_NAME"

echo "Restoring PostgreSQL parameters..."
EOF

# Extract parameters and create restore commands
az postgres flexible-server parameter list \
  --resource-group $RESOURCE_GROUP \
  --server-name $SERVER_NAME \
  --query "[?source=='user-override'].{name:name,value:value}" \
  -o tsv | while IFS=$'\t' read -r name value; do
    echo "az postgres flexible-server parameter set --resource-group \$RESOURCE_GROUP --server-name \$SERVER_NAME --name \"$name\" --value \"$value\"" >> "restore_parameters_${BACKUP_DATE}.sh"
done

chmod +x "restore_parameters_${BACKUP_DATE}.sh"

echo "Parameters backed up to:"
echo "  - postgresql_parameters_backup_${BACKUP_DATE}.json"
echo "  - restore_parameters_${BACKUP_DATE}.sh"
```

### **🧪 Post-Setup Verification (Automation)**

```bash
# Test the health check script
./postgresql_monitoring_health_check.sh

# Expected output should show:
# - Server state: Ready
# - All parameters correctly configured
# - Extensions installed and working
# - Query statistics being collected
# - Top queries visible

# Test the backup script
./backup_postgresql_parameters.sh

# Expected output:
# - Backup JSON file created
# - Restore script generated
# - All files have correct permissions

# Verify backup contents
cat postgresql_parameters_backup_$(date +%Y%m%d)*.json | jq .
# Expected: JSON array with all your custom parameters
```

---

## 🚨 **Section 5: Troubleshooting & Best Practices**

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

#### **Issue 3: Permission Denied Errors**

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

#### **Issue 4: Inconsistent Query Statistics**

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
- **Enable logging parameters** for comprehensive monitoring
- **Implement health checks** with automated scripts
- **Wait 15-30 minutes** after setup before expecting full data in QPI

#### **❌ Don'ts**

- **Don't skip the restart** after changing `shared_preload_libraries`
- **Don't use `SELECT *`** from `pg_stat_statements` in production (can be large)
- **Don't reset statistics** frequently in production
- **Don't ignore Azure extension whitelist** (`azure.extensions`)
- **Don't assume immediate data availability** in monitoring tools

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
FROM pg_stat_statements;
```

**Expected Result:**
```
check_type                | status
--------------------------|----------
Parameter Check           | ✅ PASS
Extension Check           | ✅ PASS  
Functionality Check       | ✅ PASS
Data Collection Check     | ✅ PASS
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

### **Related DBA Guides**
- [PostgreSQL Performance Query Templates](./03_postgresql_performance_query_templates.md)
- [PostgreSQL Database Connection & Extension Management Guide](./06_postgresql_database_connection_extension_management_guide.md)
- [PostgreSQL Comprehensive Lock Monitoring Guide](./postgresql_comprehensive_lock_monitoring_guide.md)

---

*This comprehensive guide covers everything from quick QPI setup to enterprise-grade monitoring infrastructure. Each section includes detailed post-verification steps to ensure successful implementation.*