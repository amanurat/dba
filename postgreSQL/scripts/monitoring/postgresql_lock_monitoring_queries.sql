
-- =====================================================================
-- PostgreSQL Lock Monitoring Queries - Professional DBA Edition
-- =====================================================================
-- Purpose: Comprehensive lock monitoring and analysis for production PostgreSQL
-- Author: DBA Team
-- Version: 2.0
-- Last Updated: 2025-01-08
-- =====================================================================

-- =====================================================================
-- 1. REAL-TIME LOCK OVERVIEW DASHBOARD
-- =====================================================================

-- Lock summary metrics for monitoring dashboards
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

-- =====================================================================
-- 2. ACTIVE LOCK ANALYSIS WITH SESSION DETAILS
-- =====================================================================

-- Enhanced lock monitoring with comprehensive session context
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

-- =====================================================================
-- 3. BLOCKING CHAIN ANALYSIS (RECURSIVE)
-- =====================================================================

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

-- =====================================================================
-- 4. LOCK CONTENTION HOTSPOT ANALYSIS
-- =====================================================================

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

-- =====================================================================
-- 5. IDLE TRANSACTION DETECTION AND IMPACT ANALYSIS
-- =====================================================================

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

-- =====================================================================
-- 6. DEADLOCK ANALYSIS
-- =====================================================================

-- Historical deadlock analysis
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

-- =====================================================================
-- 7. CRITICAL ALERT QUERIES
-- =====================================================================

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

-- =====================================================================
-- 8. LOCK IMPACT ON QUERY PERFORMANCE
-- =====================================================================

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

-- =====================================================================
-- 9. SPECIFIC TABLE LOCK MONITORING
-- =====================================================================

-- Monitor locks on specific critical tables
-- Replace 'your_critical_table' with actual table names
SELECT 
    c.relname AS table_name,
    l.mode,
    l.granted,
    l.pid,
    a.usename,
    a.application_name,
    a.state,
    a.query_start,
    EXTRACT(EPOCH FROM (now() - a.query_start))::int AS duration_seconds,
    LEFT(a.query, 150) AS query_preview
FROM pg_locks l
JOIN pg_class c ON c.oid = l.relation
JOIN pg_stat_activity a ON a.pid = l.pid
WHERE c.relname IN ('your_critical_table', 'another_important_table')  -- Replace with actual table names
ORDER BY l.granted, a.query_start;

-- =====================================================================
-- 10. SAFE SESSION TERMINATION HELPERS
-- =====================================================================

-- View sessions that are safe to terminate (long idle transactions)
SELECT 
    pid,
    usename,
    application_name,
    state,
    EXTRACT(EPOCH FROM (now() - xact_start))::int AS idle_seconds,
    'SELECT pg_terminate_backend(' || pid || ');' AS termination_command
FROM pg_stat_activity
WHERE state = 'idle in transaction'
  AND EXTRACT(EPOCH FROM (now() - xact_start)) > 1800  -- > 30 minutes
  AND usename != 'postgres'  -- Safety: don't terminate superuser sessions
ORDER BY xact_start;

-- ⚠️ CAUTION: Only execute termination commands after careful review
-- Example termination (uncomment and replace PID):
-- SELECT pg_cancel_backend(12345);  -- Graceful cancellation first
-- SELECT pg_terminate_backend(12345);  -- Force termination if needed

-- =====================================================================
-- 11. GRAFANA DASHBOARD METRICS
-- =====================================================================

-- Metrics for time-series visualization in Grafana
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
WHERE NOT granted
UNION ALL
SELECT 
    EXTRACT(EPOCH FROM now()) AS time,
    'idle_transactions' AS metric,
    COUNT(*) AS value
FROM pg_stat_activity
WHERE state = 'idle in transaction';

-- =====================================================================
-- END OF SCRIPT
-- =====================================================================
