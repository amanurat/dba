
-- 🔍 View All Current Locks
SELECT
    pg_stat_activity.pid,
    pg_stat_activity.usename,
    pg_locks.locktype,
    pg_locks.mode,
    pg_locks.granted,
    pg_stat_activity.query,
    pg_stat_activity.state,
    pg_stat_activity.query_start,
    pg_stat_activity.backend_start,
    pg_stat_activity.application_name,
    pg_stat_activity.client_addr
FROM pg_locks
JOIN pg_stat_activity
    ON pg_locks.pid = pg_stat_activity.pid
WHERE pg_locks.mode IS NOT NULL
ORDER BY pg_stat_activity.query_start;

-- 🔄 Detect Blocking and Blocked Queries
SELECT
    blocked_locks.pid AS blocked_pid,
    blocked_activity.usename AS blocked_user,
    blocking_locks.pid AS blocking_pid,
    blocking_activity.usename AS blocking_user,
    blocked_activity.query AS blocked_query,
    blocking_activity.query AS blocking_query,
    blocked_activity.query_start AS blocked_query_start,
    now() - blocked_activity.query_start AS blocked_duration
FROM pg_locks blocked_locks
JOIN pg_stat_activity blocked_activity
    ON blocked_activity.pid = blocked_locks.pid
JOIN pg_locks blocking_locks
    ON blocking_locks.locktype = blocked_locks.locktype
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
JOIN pg_stat_activity blocking_activity
    ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;

-- 📊 Count of Locks by Type
SELECT mode, COUNT(*) as count
FROM pg_locks
GROUP BY mode
ORDER BY count DESC;

-- 📋 Locks by Table (replace your_table_name_here)
SELECT 
    c.relname AS table_name,
    l.mode,
    l.granted,
    a.query,
    a.state,
    a.query_start
FROM pg_locks l
JOIN pg_class c ON c.oid = l.relation
JOIN pg_stat_activity a ON a.pid = l.pid
WHERE c.relname = 'your_table_name_here';

-- ⛔ Terminate Backend (use with caution)
-- SELECT pg_terminate_backend(<blocked_pid>);
