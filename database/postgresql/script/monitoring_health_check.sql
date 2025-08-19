-- ตรวจสอบ Cache Hit Ratio
WITH cache_stats AS (
    SELECT
        ROUND(100.0 * sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0), 2) as cache_hit_ratio
    FROM pg_statio_user_tables
)
SELECT
    CASE
        WHEN cache_hit_ratio < 90 THEN 'CRITICAL: Cache Hit Ratio = ' || cache_hit_ratio || '%'
        WHEN cache_hit_ratio < 95 THEN 'WARNING: Cache Hit Ratio = ' || cache_hit_ratio || '%'
        ELSE 'OK: Cache Hit Ratio = ' || cache_hit_ratio || '%'
        END as memory_status
FROM cache_stats;

-- ตรวจสอบ Slow Queries
WITH slow_queries AS (
    SELECT count(*) as slow_count
    FROM pg_stat_statements
    WHERE mean_exec_time > 1000  -- ช้ากว่า 1 วินาที
)
SELECT
    CASE
        WHEN slow_count > 10 THEN 'CRITICAL: ' || slow_count || ' slow queries detected'
        WHEN slow_count > 5 THEN 'WARNING: ' || slow_count || ' slow queries detected'
        ELSE 'OK: ' || slow_count || ' slow queries'
        END as query_status
FROM slow_queries;

-- ตรวจสอบ Long Running Transactions
WITH long_transactions AS (
    SELECT count(*) as long_tx_count
    FROM pg_stat_activity
    WHERE state = 'active'
      AND NOW() - query_start > interval '5 minutes'
)
SELECT
    CASE
        WHEN long_tx_count > 5 THEN 'CRITICAL: ' || long_tx_count || ' long running transactions'
        WHEN long_tx_count > 2 THEN 'WARNING: ' || long_tx_count || ' long running transactions'
        ELSE 'OK: ' || long_tx_count || ' long running transactions'
        END as transaction_status
FROM long_transactions;