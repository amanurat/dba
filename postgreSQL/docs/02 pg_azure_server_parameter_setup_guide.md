
# ⚙️ PostgreSQL Azure – Server Parameter Setup Guide (Flexible Server)

> คู่มือการตั้งค่า Server Parameters สำหรับ Tuning และ Monitoring เพื่อใช้งานกับ Query Performance Insight, Log Analytics และ Performance Tuning บน Azure PostgreSQL Flexible Server

---

## 🟢 **1. Parameter ที่ควรตั้งค่า (Updated for Azure Flexible Server)**

| **ลำดับ** | **Parameter** | **ค่าแนะนำ** | **หมายเหตุ** |
|-----------|---------------|--------------|---------------|
| **1** | **azure.extensions** | **pg_stat_statements** | **⚠️ ต้องตั้งก่อน - อนุญาต extension** |
| **2** | shared_preload_libraries | pg_stat_statements | โหลด extension ตอน startup |
| 3 | pg_stat_statements.track | all | เก็บ query ทุกประเภท |
| 4 | pg_stat_statements.max | 10000 | เพิ่มจาก 5000 สำหรับ production |
| 5 | pg_stat_statements.save | on | เก็บ stats หลัง restart |
| 6 | track_activity_query_size | 4096 | เพิ่มจาก 2048 สำหรับ query ยาว |
| 7 | track_io_timing | on | เก็บเวลาการ I/O |
| 8 | log_min_duration_statement | 1000 | ms. Log เฉพาะ query ที่ช้ากว่า 1s |
| 9 | log_checkpoints | on | Log checkpoint activities |
| 10 | log_connections | on | Log connection attempts |
| 11 | log_disconnections | on | Log disconnections |
| 12 | log_lock_waits | on | Log lock wait events |

## 🔧 **ขั้นตอนการตั้งค่าที่ถูกต้อง**

### **Method 1: ใช้ Azure Portal (แนะนำ)**

**Step 1: เปิด azure.extensions**
1. ไปที่ **Azure Portal → PostgreSQL Flexible Server → Server Parameters**
2. ค้นหา `azure.extensions`
3. เพิ่ม `pg_stat_statements` ในรายการ (ถ้ามี extensions อื่นแล้ว ใส่ comma คั่น)
4. กด **Save**

**Step 2: ตั้งค่า shared_preload_libraries**
1. ค้นหา `shared_preload_libraries`
2. ตั้งค่าเป็น `pg_stat_statements`
3. กด **Save**

**Step 3: ตั้งค่า parameters อื่นๆ**
1. ตั้งค่าตามตารางด้านบน
2. กด **Save**
3. **Restart Server** (จำเป็นสำหรับ shared_preload_libraries)

**Step 4: สร้าง Extension**
```sql
-- หลัง restart server แล้ว รันคำสั่งนี้
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

### **Method 2: ใช้ Azure CLI**

```bash
# Step 1: เปิด azure.extensions
az postgres flexible-server parameter set \
  --resource-group <your-resource-group> \
  --server-name <your-server-name> \
  --name azure.extensions \
  --value "pg_stat_statements"

# Step 2: ตั้งค่า shared_preload_libraries
az postgres flexible-server parameter set \
  --resource-group <your-resource-group> \
  --server-name <your-server-name> \
  --name shared_preload_libraries \
  --value "pg_stat_statements"

# Step 3: ตั้งค่า pg_stat_statements parameters
az postgres flexible-server parameter set \
  --resource-group <your-resource-group> \
  --server-name <your-server-name> \
  --name pg_stat_statements.track \
  --value "all"

az postgres flexible-server parameter set \
  --resource-group <your-resource-group> \
  --server-name <your-server-name> \
  --name pg_stat_statements.max \
  --value "10000"

# Step 4: Restart server
az postgres flexible-server restart \
  --resource-group <your-resource-group> \
  --name <your-server-name>
```

### **Method 3: ใช้ ARM Template (สำหรับ Infrastructure as Code)**

```json
{
  "type": "Microsoft.DBforPostgreSQL/flexibleServers/configurations",
  "apiVersion": "2021-06-01",
  "name": "[concat(parameters('serverName'), '/azure.extensions')]",
  "properties": {
    "value": "pg_stat_statements",
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
}
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

## 🧪 **3. ตรวจสอบการตั้งค่า**

### **Step 1: ตรวจสอบ Parameters**
```sql
-- ตรวจสอบ azure.extensions
SHOW azure.extensions;

-- ตรวจสอบ shared_preload_libraries
SHOW shared_preload_libraries;

-- ตรวจสอบ pg_stat_statements parameters
SHOW pg_stat_statements.track;
SHOW pg_stat_statements.max;
SHOW pg_stat_statements.save;

-- ตรวจสอบ logging parameters
SHOW track_io_timing;
SHOW log_min_duration_statement;
SHOW log_checkpoints;
SHOW log_connections;
SHOW log_lock_waits;
```

### **Step 2: ตรวจสอบ Extension**
```sql
-- ตรวจสอบว่า extension ถูกสร้างแล้ว
SELECT * FROM pg_extension WHERE extname = 'pg_stat_statements';

-- ตรวจสอบว่า pg_stat_statements ทำงาน
SELECT COUNT(*) FROM pg_stat_statements;

-- ดู top 5 queries
SELECT 
    query,
    calls,
    total_exec_time,
    mean_exec_time,
    rows
FROM pg_stat_statements 
ORDER BY total_exec_time DESC 
LIMIT 5;
```

### **Step 3: ตรวจสอบ Azure Query Performance Insight**
1. ไปที่ **Azure Portal → PostgreSQL Flexible Server → Query Performance Insight**
2. ควรเห็น query statistics และ performance data
3. ถ้าไม่เห็นข้อมูล รอ 15-30 นาทีหลังจาก restart

## 🚨 **4. Troubleshooting**

### **ปัญหาที่พบบ่อย**

| **ปัญหา** | **สาเหตุ** | **วิธีแก้** |
|-----------|------------|-------------|
| `CREATE EXTENSION` ไม่ได้ | ไม่ได้ตั้ง `azure.extensions` | ตั้งค่า `azure.extensions` ก่อน |
| `pg_stat_statements` ไม่มีข้อมูล | ไม่ได้ restart หลังตั้งค่า | Restart server |
| Query Performance Insight ว่าง | รอเวลาไม่พอ | รอ 15-30 นาที |
| Extension หายหลัง restart | ไม่ได้ตั้ง `pg_stat_statements.save = on` | ตั้งค่า save parameter |

### **คำสั่งแก้ปัญหา**
```sql
-- ถ้า extension หาย ให้สร้างใหม่
DROP EXTENSION IF EXISTS pg_stat_statements;
CREATE EXTENSION pg_stat_statements;

-- Reset pg_stat_statements data
SELECT pg_stat_statements_reset();

-- ตรวจสอบ server version และ extensions ที่รองรับ
SELECT version();
SELECT * FROM pg_available_extensions WHERE name LIKE '%stat%';
```

## ✅ **5. หมายเหตุสำคัญสำหรับ Azure Flexible Server**

### **ข้อจำกัดของ Azure**
- ⚠️ **azure.extensions** เป็น whitelist - ต้องเปิดก่อนใช้ extension ใดๆ
- ⚠️ **shared_preload_libraries** ต้อง restart server เสมอ
- ⚠️ บาง extensions ไม่รองรับใน Azure (เช่น file_fdw)
- ⚠️ **superuser privileges** ไม่มีใน Azure - ใช้ azure_pg_admin แทน

### **Best Practices**
- 🟢 ตั้งค่า `pg_stat_statements.save = on` เพื่อเก็บ stats หลัง restart
- 🟢 ใช้ `pg_stat_statements.max = 10000` สำหรับ production workload
- 🟢 เปิด logging parameters เพื่อใช้กับ Log Analytics
- 🟢 ตั้งค่าเหล่านี้ก่อนเปิด Diagnostic Settings

### **Production Recommendations**
```sql
-- สำหรับ production environment
azure.extensions = "pg_stat_statements,pg_buffercache,pg_prewarm"
shared_preload_libraries = "pg_stat_statements"
pg_stat_statements.max = 10000
pg_stat_statements.track = "all"
pg_stat_statements.save = "on"
track_activity_query_size = 4096
log_min_duration_statement = 1000
log_checkpoints = "on"
log_connections = "on"
log_disconnections = "on"
log_lock_waits = "on"
```

---


## 6️⃣ **Advanced Configuration**

### **Multiple Extensions Setup**
```bash
# ตั้งค่า extensions หลายตัวพร้อมกัน
az postgres flexible-server parameter set \
  --name azure.extensions \
  --value "pg_stat_statements,pg_buffercache,pg_prewarm,pgstattuple,pg_freespacemap"

# ตั้งค่า shared_preload_libraries หลายตัว
az postgres flexible-server parameter set \
  --name shared_preload_libraries \
  --value "pg_stat_statements,pg_prewarm"
```

### **Performance Tuning Parameters**
```sql
-- Memory และ Performance parameters สำหรับ Azure
shared_buffers = '25% of RAM'                    -- Azure จัดการอัตโนมัติ
effective_cache_size = '75% of RAM'              -- Azure จัดการอัตโนมัติ
work_mem = '4MB'                                 -- เพิ่มสำหรับ complex queries
maintenance_work_mem = '64MB'                    -- เพิ่มสำหรับ VACUUM, CREATE INDEX
checkpoint_completion_target = 0.9              -- ลด I/O spikes
wal_buffers = '16MB'                            -- เพิ่ม WAL performance
random_page_cost = 1.1                         -- สำหรับ SSD storage
effective_io_concurrency = 200                 -- สำหรับ SSD storage
```

### **Monitoring และ Logging Parameters**
```sql
-- Advanced logging สำหรับ production monitoring
log_statement = 'ddl'                          -- Log DDL statements
log_temp_files = 10240                         -- Log temp files > 10MB
log_autovacuum_min_duration = 0                -- Log all autovacuum activities
track_functions = 'all'                        -- Track function calls
track_counts = on                              -- Track table/index usage
autovacuum_naptime = '1min'                    -- More frequent autovacuum checks
```

## 7️⃣ **Integration with Azure Services**

### **Log Analytics Integration**
```bash
# เปิด Diagnostic Settings
az monitor diagnostic-settings create \
  --resource <server-resource-id> \
  --name "PostgreSQL-Diagnostics" \
  --workspace <log-analytics-workspace-id> \
  --logs '[
    {
      "category": "PostgreSQLLogs",
      "enabled": true,
      "retentionPolicy": {"days": 30, "enabled": true}
    },
    {
      "category": "QueryStoreRuntimeStatistics", 
      "enabled": true,
      "retentionPolicy": {"days": 30, "enabled": true}
    }
  ]' \
  --metrics '[
    {
      "category": "AllMetrics",
      "enabled": true,
      "retentionPolicy": {"days": 30, "enabled": true}
    }
  ]'
```

### **Query Performance Insight KQL Queries**
```kusto
// Top slow queries from Log Analytics
AzureDiagnostics
| where Category == "PostgreSQLLogs"
| where Message contains "duration:"
| extend Duration = extract(@"duration: ([\d.]+) ms", 1, Message)
| extend Query = extract(@"statement: (.+)", 1, Message)
| where todouble(Duration) > 1000
| summarize Count = count(), AvgDuration = avg(todouble(Duration)) by Query
| order by AvgDuration desc
| limit 10

// Connection monitoring
AzureDiagnostics
| where Category == "PostgreSQLLogs"
| where Message contains "connection"
| summarize ConnectionEvents = count() by bin(TimeGenerated, 1h)
| render timechart
```

## 8️⃣ **Automation Scripts**

### **Health Check Script**
```bash
#!/bin/bash
# PostgreSQL Azure Health Check

SERVER_NAME="your-server-name"
RESOURCE_GROUP="your-resource-group"

echo "=== PostgreSQL Azure Health Check ==="
echo "Server: $SERVER_NAME"
echo "Date: $(date)"
echo

# Check server status
echo "1. Server Status:"
az postgres flexible-server show \
  --resource-group $RESOURCE_GROUP \
  --name $SERVER_NAME \
  --query "state" -o tsv

# Check pg_stat_statements configuration
echo "2. pg_stat_statements Configuration:"
psql "host=$SERVER_NAME.postgres.database.azure.com user=your_user dbname=your_db sslmode=require" \
  -c "SHOW azure.extensions;" \
  -c "SHOW shared_preload_libraries;" \
  -c "SELECT COUNT(*) as pg_stat_statements_queries FROM pg_stat_statements;"

# Check top queries
echo "3. Top 5 Slow Queries:"
psql "host=$SERVER_NAME.postgres.database.azure.com user=your_user dbname=your_db sslmode=require" \
  -c "SELECT LEFT(query, 50) as query_preview, calls, total_exec_time, mean_exec_time 
      FROM pg_stat_statements 
      ORDER BY total_exec_time DESC 
      LIMIT 5;"
```

### **Parameter Backup Script**
```bash
#!/bin/bash
# Backup current server parameters

az postgres flexible-server parameter list \
  --resource-group $RESOURCE_GROUP \
  --server-name $SERVER_NAME \
  --query "[?source=='user-override'].{name:name,value:value}" \
  -o json > "postgresql_parameters_backup_$(date +%Y%m%d).json"

echo "Parameters backed up to postgresql_parameters_backup_$(date +%Y%m%d).json"
```

## 📦 **Resources และ Documentation**

### **Official Azure Documentation**
- [Azure PostgreSQL Flexible Server Parameters](https://docs.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-server-parameters)
- [Azure PostgreSQL Extensions](https://docs.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-extensions)
- [Query Performance Insight](https://docs.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-query-performance-insight)
- [Monitoring and Metrics](https://docs.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-monitoring)

### **PostgreSQL Official Documentation**
- [pg_stat_statements Extension](https://www.postgresql.org/docs/current/pgstatstatements.html)
- [Server Configuration](https://www.postgresql.org/docs/current/runtime-config.html)
- [Monitoring Database Activity](https://www.postgresql.org/docs/current/monitoring.html)

### **Related DBA Guides**
- [PostgreSQL Performance Query Templates](./04%20postgresql_performance_query_templates.md)
- [PostgreSQL Monitoring Azure Summary](./03%20postgresql_monitoring_azure_summary.md)
- [PostgreSQL Comprehensive Lock Monitoring Guide](./postgresql_comprehensive_lock_monitoring_guide.md)
