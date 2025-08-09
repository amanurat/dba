# 🔧 Azure PostgreSQL Troubleshooting Knowledge Base

> **DBA Quick Reference**: Common issues, solutions, and troubleshooting procedures for Azure PostgreSQL Flexible Server

**Last Updated**: January 8, 2025  
**Scope**: Azure PostgreSQL Flexible Server troubleshooting  
**Audience**: DBA Team, Support Engineers, DevOps  

---

## 🚨 **Critical Issues and Solutions**

### **Issue 1: pg_stat_statements Extension Not Available**

#### **Symptoms**
```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
-- ERROR: extension "pg_stat_statements" is not available
```

#### **Root Cause Analysis**
```sql
-- Check current configuration
SHOW azure.extensions;           -- May not show pg_stat_statements
SHOW shared_preload_libraries;   -- May not include pg_stat_statements
SELECT * FROM pg_available_extensions WHERE name = 'pg_stat_statements';
```

#### **Solution Steps**
1. **Configure azure.extensions**
   ```bash
   az postgres flexible-server parameter set \
     --resource-group <rg> \
     --server-name <server> \
     --name azure.extensions \
     --value "pg_stat_statements"
   ```

2. **Configure shared_preload_libraries**
   ```bash
   az postgres flexible-server parameter set \
     --resource-group <rg> \
     --server-name <server> \
     --name shared_preload_libraries \
     --value "pg_stat_statements"
   ```

3. **Restart Server (Critical)**
   ```bash
   az postgres flexible-server restart \
     --resource-group <rg> \
     --name <server>
   ```

4. **Verify and Create Extension**
   ```sql
   -- Wait 10-15 minutes after restart
   SHOW azure.extensions;
   SHOW shared_preload_libraries;
   CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
   ```

#### **Prevention**
- Always set both `azure.extensions` and `shared_preload_libraries`
- Always restart server after parameter changes
- Wait adequate time after restart before testing

---

### **Issue 2: Extension Works in One Database But Not Another**

#### **Symptoms**
```sql
\c postgres
SELECT COUNT(*) FROM pg_stat_statements;  -- Works

\c myapp
SELECT COUNT(*) FROM pg_stat_statements;  -- ERROR: relation does not exist
```

#### **Root Cause**
Extensions are **database-specific**, not server-wide

#### **Solution**
```sql
-- Create extension in each database where needed
\c postgres
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

\c myapp
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

\c analytics
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

#### **Verification Script**
```bash
#!/bin/bash
# Check extension status across databases
DATABASES=("postgres" "myapp" "analytics")
SERVER="myserver.postgres.database.azure.com"
USER="myuser"

for db in "${DATABASES[@]}"; do
    echo "=== Database: $db ==="
    psql "host=$SERVER user=$USER dbname=$db sslmode=require" -c "
        SELECT 
            '$db' as database,
            CASE WHEN EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements') 
                 THEN 'INSTALLED' 
                 ELSE 'NOT_INSTALLED' 
            END as status;
    "
done
```

---

### **Issue 3: Parameters Not Taking Effect**

#### **Symptoms**
- Set parameters in Azure Portal but `SHOW` commands show old values
- Extension still not available after configuration

#### **Root Cause Analysis**
```sql
-- Check if parameters are pending restart
SELECT name, setting, pending_restart 
FROM pg_settings 
WHERE name IN ('azure.extensions', 'shared_preload_libraries');

-- Check server uptime
SELECT pg_postmaster_start_time();
SELECT now() - pg_postmaster_start_time() as uptime;
```

#### **Solution Steps**
1. **Verify Parameter Status**
   ```bash
   # Check actual parameter values via CLI
   az postgres flexible-server parameter show \
     --resource-group <rg> \
     --server-name <server> \
     --name azure.extensions
   ```

2. **Force Parameter Update**
   ```bash
   # Re-apply parameters
   az postgres flexible-server parameter set \
     --resource-group <rg> \
     --server-name <server> \
     --name azure.extensions \
     --value "pg_stat_statements"
   ```

3. **Restart and Wait**
   ```bash
   # Restart server
   az postgres flexible-server restart \
     --resource-group <rg> \
     --name <server>
   
   # Wait 10-15 minutes for full initialization
   ```

4. **Verify Changes**
   ```sql
   -- Check that parameters are applied
   SELECT name, setting, pending_restart 
   FROM pg_settings 
   WHERE name = 'azure.extensions';
   ```

---

### **Issue 4: Permission Denied Creating Extensions**

#### **Symptoms**
```sql
CREATE EXTENSION pg_stat_statements;
-- ERROR: permission denied to create extension "pg_stat_statements"
```

#### **Root Cause Analysis**
```sql
-- Check current user and permissions
SELECT current_user, session_user;
SELECT rolname, rolsuper, rolcreatedb, rolcanlogin 
FROM pg_roles 
WHERE rolname = current_user;

-- Check database ownership
SELECT datname, datdba, rolname as owner
FROM pg_database d
JOIN pg_roles r ON d.datdba = r.oid
WHERE datname = current_database();
```

#### **Solution**
1. **Use azure_pg_admin Role**
   ```sql
   -- Connect with admin user
   psql "host=server.postgres.database.azure.com user=admin_user dbname=postgres sslmode=require"
   ```

2. **Grant Necessary Permissions**
   ```sql
   -- If using non-admin user, grant permissions
   GRANT azure_pg_admin TO your_user;
   ```

3. **Verify Permissions**
   ```sql
   SELECT current_user, 
          pg_has_role(current_user, 'azure_pg_admin', 'member') as is_admin;
   ```

---

### **Issue 5: Query Performance Insight Not Showing Data**

#### **Symptoms**
- Azure Portal Query Performance Insight shows no data
- pg_stat_statements working but QPI empty

#### **Root Cause Analysis**
```sql
-- Check if pg_stat_statements has data
SELECT COUNT(*) FROM pg_stat_statements;

-- Check Query Store parameters
SELECT name, setting FROM pg_settings 
WHERE name LIKE 'pg_qs%' OR name LIKE 'pgms_wait%';
```

#### **Solution Steps**
1. **Enable Query Store Parameters**
   ```bash
   # Set Query Store parameters
   az postgres flexible-server parameter set \
     --name pg_qs.query_capture_mode \
     --value "ALL"
   
   az postgres flexible-server parameter set \
     --name pgms_wait_sampling.query_capture_mode \
     --value "All"
   ```

2. **Wait for Data Collection**
   - QPI requires 15-30 minutes to show data
   - Generate some query activity to populate statistics

3. **Verify Data Flow**
   ```sql
   -- Check if Query Store is collecting data
   SELECT * FROM pg_settings WHERE name LIKE 'pg_qs%';
   
   -- Generate test queries
   SELECT COUNT(*) FROM information_schema.tables;
   SELECT * FROM pg_stat_statements LIMIT 5;
   ```

---

## 🔍 **Diagnostic Procedures**

### **Complete Health Check Script**

```bash
#!/bin/bash
# comprehensive_postgresql_health_check.sh

SERVER="$1"
USER="$2"
DATABASE="${3:-postgres}"

if [ $# -lt 2 ]; then
    echo "Usage: $0 <server> <user> [database]"
    exit 1
fi

echo "=== PostgreSQL Health Check ==="
echo "Server: $SERVER"
echo "User: $USER"
echo "Database: $DATABASE"
echo "Date: $(date)"
echo

# Connection test
echo "1. Connection Test:"
if psql "host=$SERVER user=$USER dbname=$DATABASE sslmode=require" -c "SELECT 1;" >/dev/null 2>&1; then
    echo "   ✅ Connection successful"
else
    echo "   ❌ Connection failed"
    exit 1
fi

# Server information
echo "2. Server Information:"
psql "host=$SERVER user=$USER dbname=$DATABASE sslmode=require" -c "
    SELECT 'Version' as info, version() as value
    UNION ALL
    SELECT 'Uptime', (now() - pg_postmaster_start_time())::text
    UNION ALL
    SELECT 'Current Database', current_database()
    UNION ALL
    SELECT 'Current User', current_user;
"

# Parameter check
echo "3. Critical Parameters:"
psql "host=$SERVER user=$USER dbname=$DATABASE sslmode=require" -c "
    SELECT name, setting, pending_restart
    FROM pg_settings 
    WHERE name IN ('azure.extensions', 'shared_preload_libraries', 
                   'pg_stat_statements.track', 'pg_stat_statements.max')
    ORDER BY name;
"

# Extension status
echo "4. Extension Status:"
psql "host=$SERVER user=$USER dbname=$DATABASE sslmode=require" -c "
    SELECT 
        'pg_stat_statements' as extension,
        CASE WHEN EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements') 
             THEN 'INSTALLED' 
             ELSE 'NOT_INSTALLED' 
        END as status,
        CASE WHEN EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_stat_statements')
             THEN 'AVAILABLE'
             ELSE 'NOT_AVAILABLE'
        END as availability;
"

# Query statistics
echo "5. Query Statistics:"
psql "host=$SERVER user=$USER dbname=$DATABASE sslmode=require" -c "
    SELECT 
        COUNT(*) as total_queries,
        SUM(calls) as total_calls,
        ROUND(SUM(total_exec_time)::numeric, 2) as total_time_ms,
        ROUND(AVG(mean_exec_time)::numeric, 2) as avg_time_ms
    FROM pg_stat_statements;
" 2>/dev/null || echo "   pg_stat_statements not available"

# Top queries
echo "6. Top 5 Queries by Total Time:"
psql "host=$SERVER user=$USER dbname=$DATABASE sslmode=require" -c "
    SELECT 
        LEFT(query, 60) as query_preview,
        calls,
        ROUND(total_exec_time::numeric, 2) as total_time_ms,
        ROUND(mean_exec_time::numeric, 2) as avg_time_ms
    FROM pg_stat_statements 
    WHERE query NOT LIKE '%pg_stat_statements%'
    ORDER BY total_exec_time DESC 
    LIMIT 5;
" 2>/dev/null || echo "   pg_stat_statements not available"

echo
echo "=== Health Check Complete ==="
```

### **Parameter Validation Script**

```bash
#!/bin/bash
# validate_postgresql_parameters.sh

SERVER="$1"
USER="$2"

echo "=== Parameter Validation ==="

# Required parameters for pg_stat_statements
REQUIRED_PARAMS=(
    "azure.extensions:pg_stat_statements"
    "shared_preload_libraries:pg_stat_statements"
    "pg_stat_statements.track:all"
    "pg_stat_statements.max:5000"
)

for param_check in "${REQUIRED_PARAMS[@]}"; do
    IFS=':' read -r param expected <<< "$param_check"
    
    actual=$(psql "host=$SERVER user=$USER dbname=postgres sslmode=require" -t -c "
        SELECT setting FROM pg_settings WHERE name = '$param';
    " 2>/dev/null | xargs)
    
    if [[ "$actual" == *"$expected"* ]]; then
        echo "✅ $param: $actual"
    else
        echo "❌ $param: Expected '$expected', Got '$actual'"
    fi
done
```

---

## 📋 **Quick Reference Checklists**

### **pg_stat_statements Setup Checklist**
- [ ] Set `azure.extensions` to include `pg_stat_statements`
- [ ] Set `shared_preload_libraries` to include `pg_stat_statements`
- [ ] Restart PostgreSQL server
- [ ] Wait 10-15 minutes after restart
- [ ] Connect to target database
- [ ] Run `CREATE EXTENSION IF NOT EXISTS pg_stat_statements;`
- [ ] Verify with `SELECT COUNT(*) FROM pg_stat_statements;`
- [ ] Repeat extension creation for each database

### **Troubleshooting Checklist**
- [ ] Check current database with `SELECT current_database();`
- [ ] Verify user permissions with role checks
- [ ] Check server parameters with `SHOW` commands
- [ ] Verify server restart time with `pg_postmaster_start_time()`
- [ ] Check Azure Portal Activity Log for errors
- [ ] Test with different databases
- [ ] Verify extension availability before creation

### **Performance Monitoring Checklist**
- [ ] Verify pg_stat_statements is collecting data
- [ ] Check Query Performance Insight in Azure Portal
- [ ] Set up Log Analytics integration
- [ ] Configure diagnostic settings
- [ ] Test alert thresholds
- [ ] Document baseline performance metrics

---

## 🔗 **Related Resources**

### **Internal Documentation**
- [PostgreSQL Azure Server Parameter Setup Guide](./02%20pg_azure_server_parameter_setup_guide.md)
- [PostgreSQL Database Connection & Extension Management Guide](./postgresql_database_connection_extension_management_guide.md)
- [PostgreSQL Performance Query Templates](./04%20postgresql_performance_query_templates.md)

### **External Resources**
- [Azure PostgreSQL Flexible Server Documentation](https://docs.microsoft.com/en-us/azure/postgresql/flexible-server/)
- [PostgreSQL pg_stat_statements Documentation](https://www.postgresql.org/docs/current/pgstatstatements.html)
- [Azure CLI PostgreSQL Commands](https://docs.microsoft.com/en-us/cli/azure/postgres/flexible-server)

---

**Knowledge Base Maintained By**: DBA Team  
**Update Frequency**: Monthly or as issues are discovered  
**Feedback**: Submit issues and solutions to DBA team for inclusion