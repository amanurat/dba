# 🔐 PostgreSQL Comprehensive Lock Monitoring Guide

> **Professional DBA Reference**: Complete guide for monitoring, analyzing, and resolving database locking issues in PostgreSQL production environments

---

## 📋 **Executive Summary**

This guide provides enterprise-grade lock monitoring strategies for PostgreSQL databases, with specific focus on:
- **Proactive lock monitoring** and alerting
- **Performance impact analysis** of locking patterns
- **Incident response procedures** for lock-related issues
- **Azure-specific monitoring** integration
- **Automated remediation** strategies

---

## 🎯 **Lock Monitoring Framework**

### **Critical Monitoring Areas**

| **Category** | **Monitoring Focus** | **Business Impact** | **Alert Threshold** |
|--------------|---------------------|-------------------|-------------------|
| 🔒 **Active Locks** | Current lock holders and waiters | Transaction delays | > 50 concurrent locks |
| ⛔ **Blocking Chains** | Multi-level blocking relationships | Application timeouts | > 3 blocked sessions |
| 🕒 **Lock Duration** | Long-held locks and transactions | Resource contention | > 5 minutes |
| 💀 **Deadlocks** | Circular lock dependencies | Transaction rollbacks | > 1 per hour |
| 🧟 **Idle Transactions** | Uncommitted idle sessions | Table bloat, lock waits | > 30 minutes idle |
| 🔥 **Lock Hotspots** | Tables with frequent lock contention | Scalability bottlenecks | > 100 locks/minute |

---

## 🔍 **Core Monitoring Queries**

### **1. Real-Time Lock Overview Dashboard**
```sql
-- Comprehensive lock status with performance metrics
SELECT 
    'LOCK_OVERVIEW' AS metric_type,
    COUNT(*) AS total_locks,
    COUNT(*) FILTER (WHERE NOT granted) AS waiting_locks,
    COUNT(*) FILTER (WHERE granted) AS granted_locks,
    COUNT(DISTINCT pid) AS sessions_with_locks,
    COUNT(DISTINCT relation) FILTER (WHERE relation IS NOT NULL) AS locked_tables,
    pg_size_pretty(
        SUM(pg_relation_size(relation)) FILTER (WHERE relation IS NOT NULL)
    ) AS total_locked_data_size
FROM pg_locks
WHERE locktype IN ('relation', 'tuple', 'transactionid');
```

### **2. Active Lock Analysis with Session Details**
```sql
-- Enhanced lock monitoring with session context
SELECT
    l.locktype,
    l.mode,
    l.granted,
    l.pid,
    a.usename,
    a.application_name,
    a.client_addr,
    a.state,
    a.query_start,
    a.xact_start,
    EXTRACT(EPOCH FROM (now() - a.query_start))::int AS query_duration_seconds,
    EXTRACT(EPOCH FROM (now() - a.xact_start))::int AS transaction_duration_seconds,
    CASE 
        WHEN l.relation IS NOT NULL THEN c.relname 
        ELSE l.locktype::text 
    END AS resource_name,
    CASE 
        WHEN l.relation IS NOT NULL THEN pg_size_pretty(pg_relation_size(l.relation))
        ELSE 'N/A'
    END AS resource_size,
    LEFT(a.query, 100) AS query_preview
FROM pg_locks l
JOIN pg_stat_activity a ON l.pid = a.pid
LEFT JOIN pg_class c ON l.relation = c.oid
WHERE l.mode IS NOT NULL
  AND a.state != 'idle'
ORDER BY 
    CASE WHEN NOT l.granted THEN 0 ELSE 1 END,
    EXTRACT(EPOCH FROM (now() - a.query_start)) DESC;
```

### **3. Advanced Blocking Chain Analysis**
```sql
-- Multi-level blocking relationship detection
WITH RECURSIVE blocking_tree AS (
    -- Base case: find all blocked sessions
    SELECT 
        blocked.pid AS blocked_pid,
        blocked.usename AS blocked_user,
        blocking.pid AS blocking_pid,
        blocking.usename AS blocking_user,
        blocked.query AS blocked_query,
        blocking.query AS blocking_query,
        blocked.query_start AS blocked_start,
        blocking.query_start AS blocking_start,
        EXTRACT(EPOCH FROM (now() - blocked.query_start))::int AS wait_duration_seconds,
        1 AS level,
        ARRAY[blocked.pid] AS blocking_chain
    FROM pg_locks blocked_locks
    JOIN pg_stat_activity blocked ON blocked.pid = blocked_locks.pid
    JOIN pg_locks blocking_locks ON (
        blocking_locks.locktype = blocked_locks.locktype
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
    )
    JOIN pg_stat_activity blocking ON blocking.pid = blocking_locks.pid
    WHERE NOT blocked_locks.granted
    
    UNION ALL
    
    -- Recursive case: find sessions blocking the blockers
    SELECT 
        bt.blocked_pid,
        bt.blocked_user,
        blocking.pid AS blocking_pid,
        blocking.usename AS blocking_user,
        bt.blocked_query,
        blocking.query AS blocking_query,
        bt.blocked_start,
        blocking.query_start AS blocking_start,
        bt.wait_duration_seconds,
        bt.level + 1,
        bt.blocking_chain || blocking.pid
    FROM blocking_tree bt
    JOIN pg_locks blocked_locks ON blocked_locks.pid = bt.blocking_pid
    JOIN pg_locks blocking_locks ON (
        blocking_locks.locktype = blocked_locks.locktype
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
    )
    JOIN pg_stat_activity blocking ON blocking.pid = blocking_locks.pid
    WHERE NOT blocked_locks.granted
      AND bt.level < 10  -- Prevent infinite recursion
      AND blocking.pid != ALL(bt.blocking_chain)  -- Prevent cycles
)
SELECT 
    blocked_pid,
    blocked_user,
    blocking_pid,
    blocking_user,
    wait_duration_seconds,
    level AS blocking_depth,
    array_length(blocking_chain, 1) AS chain_length,
    LEFT(blocked_query, 80) AS blocked_query_preview,
    LEFT(blocking_query, 80) AS blocking_query_preview
FROM blocking_tree
ORDER BY wait_duration_seconds DESC, level;
```

### **4. Lock Contention Hotspot Analysis**
```sql
-- Identify tables and operations with highest lock contention
SELECT 
    c.relname AS table_name,
    n.nspname AS schema_name,
    l.mode AS lock_mode,
    COUNT(*) AS lock_count,
    COUNT(*) FILTER (WHERE NOT l.granted) AS waiting_count,
    COUNT(DISTINCT l.pid) AS session_count,
    pg_size_pretty(pg_total_relation_size(c.oid)) AS table_size,
    ROUND(
        COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2
    ) AS lock_percentage,
    -- Calculate lock pressure score
    CASE 
        WHEN COUNT(*) FILTER (WHERE NOT l.granted) > 0 THEN
            (COUNT(*) FILTER (WHERE NOT l.granted) * 10) + COUNT(*)
        ELSE COUNT(*)
    END AS contention_score
FROM pg_locks l
JOIN pg_class c ON l.relation = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE l.locktype = 'relation'
  AND n.nspname NOT IN ('information_schema', 'pg_catalog', 'pg_toast')
GROUP BY c.relname, n.nspname, l.mode, c.oid
HAVING COUNT(*) > 1
ORDER BY contention_score DESC, waiting_count DESC
LIMIT 20;
```

### **5. Idle Transaction Detection and Impact Analysis**
```sql
-- Comprehensive idle transaction monitoring
SELECT 
    pid,
    usename,
    application_name,
    client_addr,
    state,
    xact_start,
    query_start,
    EXTRACT(EPOCH FROM (now() - xact_start))::int AS transaction_age_seconds,
    EXTRACT(EPOCH FROM (now() - query_start))::int AS query_age_seconds,
    -- Calculate potential impact
    CASE 
        WHEN EXTRACT(EPOCH FROM (now() - xact_start)) > 3600 THEN 'CRITICAL'
        WHEN EXTRACT(EPOCH FROM (now() - xact_start)) > 1800 THEN 'HIGH'
        WHEN EXTRACT(EPOCH FROM (now() - xact_start)) > 600 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS impact_level,
    -- Check if holding locks
    (SELECT COUNT(*) FROM pg_locks WHERE pid = a.pid AND granted) AS locks_held,
    LEFT(query, 100) AS last_query
FROM pg_stat_activity a
WHERE state IN ('idle in transaction', 'idle in transaction (aborted)')
  AND xact_start IS NOT NULL
ORDER BY xact_start;
```

### **6. Deadlock Detection and Analysis**
```sql
-- Historical deadlock analysis (requires log_lock_waits = on)
-- This query works with PostgreSQL logs parsed into a table
-- For real-time deadlock monitoring, check pg_stat_database.deadlocks

SELECT 
    datname AS database_name,
    deadlocks AS total_deadlocks,
    deadlocks - LAG(deadlocks) OVER (ORDER BY stats_reset) AS deadlocks_since_last_reset,
    stats_reset AS last_stats_reset,
    EXTRACT(EPOCH FROM (now() - stats_reset))/3600 AS hours_since_reset,
    CASE 
        WHEN EXTRACT(EPOCH FROM (now() - stats_reset)) > 0 THEN
            ROUND(deadlocks / (EXTRACT(EPOCH FROM (now() - stats_reset))/3600), 2)
        ELSE 0
    END AS deadlocks_per_hour
FROM pg_stat_database
WHERE datname NOT IN ('template0', 'template1', 'postgres')
  AND deadlocks > 0
ORDER BY deadlocks DESC;
```

---

## 🚨 **Alert Configuration Framework**

### **Critical Alerts (Immediate Response)**
```sql
-- Alert: Long-running blocking sessions (> 5 minutes)
SELECT 
    'CRITICAL_BLOCKING' AS alert_type,
    COUNT(*) AS blocked_sessions,
    MAX(EXTRACT(EPOCH FROM (now() - blocked_activity.query_start))) AS max_wait_seconds
FROM pg_locks blocked_locks
JOIN pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
WHERE NOT blocked_locks.granted
  AND EXTRACT(EPOCH FROM (now() - blocked_activity.query_start)) > 300
HAVING COUNT(*) > 0;

-- Alert: Excessive lock count (> 1000 active locks)
SELECT 
    'EXCESSIVE_LOCKS' AS alert_type,
    COUNT(*) AS total_locks,
    COUNT(DISTINCT pid) AS sessions_with_locks
FROM pg_locks
WHERE granted = true
HAVING COUNT(*) > 1000;

-- Alert: Long idle transactions (> 30 minutes)
SELECT 
    'LONG_IDLE_TRANSACTION' AS alert_type,
    COUNT(*) AS idle_transaction_count,
    MAX(EXTRACT(EPOCH FROM (now() - xact_start))) AS max_idle_seconds
FROM pg_stat_activity
WHERE state = 'idle in transaction'
  AND EXTRACT(EPOCH FROM (now() - xact_start)) > 1800
HAVING COUNT(*) > 0;
```

### **Warning Alerts (Monitor Closely)**
```sql
-- Alert: High lock contention on specific tables
SELECT 
    'HIGH_TABLE_CONTENTION' AS alert_type,
    c.relname AS table_name,
    COUNT(*) AS concurrent_locks,
    COUNT(*) FILTER (WHERE NOT l.granted) AS waiting_locks
FROM pg_locks l
JOIN pg_class c ON l.relation = c.oid
WHERE l.locktype = 'relation'
GROUP BY c.relname
HAVING COUNT(*) > 20 OR COUNT(*) FILTER (WHERE NOT l.granted) > 5
ORDER BY waiting_locks DESC, concurrent_locks DESC;
```

---

## 🔧 **Automated Remediation Procedures**

### **Safe Lock Resolution Script**
```sql
-- Function to safely terminate problematic sessions
CREATE OR REPLACE FUNCTION terminate_blocking_session(
    p_blocking_pid INTEGER,
    p_max_wait_seconds INTEGER DEFAULT 300
) RETURNS TEXT AS $$
DECLARE
    v_wait_duration INTEGER;
    v_query TEXT;
    v_user TEXT;
BEGIN
    -- Get session details
    SELECT 
        EXTRACT(EPOCH FROM (now() - query_start))::INTEGER,
        LEFT(query, 100),
        usename
    INTO v_wait_duration, v_query, v_user
    FROM pg_stat_activity 
    WHERE pid = p_blocking_pid;
    
    -- Safety checks
    IF v_wait_duration IS NULL THEN
        RETURN 'Session not found: ' || p_blocking_pid;
    END IF;
    
    IF v_wait_duration < p_max_wait_seconds THEN
        RETURN 'Session not terminated - wait duration (' || v_wait_duration || 's) below threshold (' || p_max_wait_seconds || 's)';
    END IF;
    
    IF v_user = 'postgres' THEN
        RETURN 'Cannot terminate postgres superuser session for safety';
    END IF;
    
    -- Attempt graceful termination first
    PERFORM pg_cancel_backend(p_blocking_pid);
    
    -- Wait 5 seconds for graceful shutdown
    PERFORM pg_sleep(5);
    
    -- Check if session still exists
    IF EXISTS (SELECT 1 FROM pg_stat_activity WHERE pid = p_blocking_pid) THEN
        -- Force termination
        PERFORM pg_terminate_backend(p_blocking_pid);
        RETURN 'Session ' || p_blocking_pid || ' terminated (user: ' || v_user || ', query: ' || v_query || ')';
    ELSE
        RETURN 'Session ' || p_blocking_pid || ' cancelled gracefully';
    END IF;
END;
$$ LANGUAGE plpgsql;
```

---

## 📊 **Azure-Specific Monitoring Integration**

### **Log Analytics KQL Queries**
```kusto
// Lock-related log analysis in Azure Log Analytics
AzureDiagnostics
| where Category == "PostgreSQLLogs"
| where Message contains "deadlock" or Message contains "lock timeout"
| extend LogLevel = case(
    Message contains "ERROR", "ERROR",
    Message contains "WARNING", "WARNING", 
    "INFO"
)
| summarize Count = count() by LogLevel, bin(TimeGenerated, 1h)
| order by TimeGenerated desc

// Query Performance Insight integration
AzureDiagnostics
| where Category == "QueryStoreRuntimeStatistics"
| where total_time_d > 5000  // Queries running longer than 5 seconds
| project TimeGenerated, query_id_d, total_time_d, mean_time_d, calls_d
| order by total_time_d desc
```

### **Azure Monitor Alerts**
```json
{
  "alertName": "PostgreSQL High Lock Contention",
  "description": "Alert when lock wait time exceeds threshold",
  "severity": "2",
  "condition": {
    "query": "AzureDiagnostics | where Message contains 'lock timeout' | summarize count()",
    "threshold": 5,
    "timeWindow": "PT5M"
  }
}
```

---

## 📈 **Performance Impact Analysis**

### **Lock Impact on Query Performance**
```sql
-- Analyze correlation between locks and query performance
WITH lock_stats AS (
    SELECT 
        DATE_TRUNC('hour', now()) AS time_bucket,
        COUNT(*) AS total_locks,
        COUNT(*) FILTER (WHERE NOT granted) AS waiting_locks,
        AVG(EXTRACT(EPOCH FROM (now() - query_start))) FILTER (WHERE NOT granted) AS avg_wait_time
    FROM pg_locks l
    JOIN pg_stat_activity a ON l.pid = a.pid
    WHERE l.locktype IN ('relation', 'tuple', 'transactionid')
    GROUP BY DATE_TRUNC('hour', now())
),
query_stats AS (
    SELECT 
        DATE_TRUNC('hour', now()) AS time_bucket,
        COUNT(*) AS active_queries,
        AVG(EXTRACT(EPOCH FROM (now() - query_start))) AS avg_query_time
    FROM pg_stat_activity
    WHERE state = 'active'
    GROUP BY DATE_TRUNC('hour', now())
)
SELECT 
    l.time_bucket,
    l.total_locks,
    l.waiting_locks,
    l.avg_wait_time,
    q.active_queries,
    q.avg_query_time,
    CASE 
        WHEN l.waiting_locks > 10 THEN 'HIGH_CONTENTION'
        WHEN l.waiting_locks > 5 THEN 'MEDIUM_CONTENTION'
        ELSE 'LOW_CONTENTION'
    END AS contention_level
FROM lock_stats l
LEFT JOIN query_stats q ON l.time_bucket = q.time_bucket;
```

---

## 🎯 **Best Practices and Recommendations**

### **Proactive Lock Management**
1. **Connection Pooling**: Use pgBouncer to limit concurrent connections
2. **Transaction Timeout**: Set `statement_timeout` and `idle_in_transaction_session_timeout`
3. **Lock Timeout**: Configure `lock_timeout` for critical applications
4. **Query Optimization**: Minimize lock duration through efficient queries

### **Monitoring Schedule**
| **Frequency** | **Scope** | **Action** |
|---------------|-----------|------------|
| **Real-time** | Critical blocking (> 5 min) | Immediate investigation |
| **Every 5 minutes** | Lock contention hotspots | Trend analysis |
| **Hourly** | Idle transaction cleanup | Automated termination |
| **Daily** | Lock pattern analysis | Performance review |
| **Weekly** | Deadlock trend analysis | Root cause analysis |

### **Incident Response Procedures**
1. **Immediate**: Identify blocking chain root cause
2. **Assessment**: Evaluate business impact and affected users
3. **Resolution**: Apply appropriate remediation (cancel/terminate)
4. **Follow-up**: Analyze root cause and implement preventive measures
5. **Documentation**: Update runbooks and alert thresholds

---

## 🔗 **Integration with Existing Tools**

### **Grafana Dashboard Queries**
```sql
-- Metrics for Grafana visualization
SELECT 
    EXTRACT(EPOCH FROM now()) AS time,
    'locks_total' AS metric,
    COUNT(*) AS value
FROM pg_locks
UNION ALL
SELECT 
    EXTRACT(EPOCH FROM now()) AS time,
    'locks_waiting' AS metric,
    COUNT(*) AS value
FROM pg_locks
WHERE NOT granted;
```

### **Nagios/Icinga Check Script**
```bash
#!/bin/bash
# PostgreSQL lock monitoring check for Nagios
BLOCKED_COUNT=$(psql -t -c "SELECT COUNT(*) FROM pg_locks WHERE NOT granted;")
if [ "$BLOCKED_COUNT" -gt 10 ]; then
    echo "CRITICAL: $BLOCKED_COUNT blocked sessions"
    exit 2
elif [ "$BLOCKED_COUNT" -gt 5 ]; then
    echo "WARNING: $BLOCKED_COUNT blocked sessions"
    exit 1
else
    echo "OK: $BLOCKED_COUNT blocked sessions"
    exit 0
fi
```

---

## 📚 **Additional Resources**

- **PostgreSQL Documentation**: [Lock Monitoring](https://www.postgresql.org/docs/current/monitoring-locks.html)
- **Azure PostgreSQL**: [Performance Monitoring](https://docs.microsoft.com/en-us/azure/postgresql/concepts-monitoring)
- **Related Scripts**: [`postgresql_lock_monitoring_queries.sql`](../scripts/monitoring/postgresql_lock_monitoring_queries.sql)

---

*This guide provides enterprise-grade lock monitoring capabilities for PostgreSQL databases. Regular review and updates ensure continued effectiveness in production environments.*