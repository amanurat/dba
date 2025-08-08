-- =====================================================================
-- PostgreSQL Index Analysis & Cost Estimation Script
-- =====================================================================
-- Purpose: Comprehensive analysis of index usage, performance metrics,
--          and query cost estimation for database optimization
-- Author: DBA Team
-- Version: 1.0
-- Last Updated: 2025-01-08
-- =====================================================================

-- =====================================================================
-- 1. INDEX USAGE ANALYSIS
-- =====================================================================

-- Analyze index usage patterns and storage efficiency
SELECT 
    schemaname,
    relname AS table_name,
    indexrelname AS index_name,
    idx_scan AS total_scans,
    idx_tup_read AS tuples_read,
    idx_tup_fetch AS tuples_fetched,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    CASE 
        WHEN idx_scan > 0 THEN 
            pg_relation_size(indexrelid) / idx_scan 
        ELSE pg_relation_size(indexrelid)
    END AS bytes_per_scan
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC, pg_relation_size(indexrelid) DESC;

-- =====================================================================
-- 2. QUERY PERFORMANCE ANALYSIS
-- =====================================================================

-- Comprehensive execution plan analysis with all performance metrics
-- Note: Replace 'your_table_name' with actual table name
EXPLAIN (
    ANALYZE true,     -- Execute and show actual times
    VERBOSE true,     -- Show additional details  
    COSTS true,       -- Show cost estimates
    TIMING true,      -- Show timing information
    BUFFERS true      -- Show buffer usage statistics
) 
SELECT * FROM your_table_name ORDER BY random();

-- =====================================================================
-- 3. COST ESTIMATION ANALYSIS
-- =====================================================================

-- Calculate sequential scan costs for performance planning
-- Note: Replace 'your_table_name' with actual table name for specific analysis
SELECT 
    relname AS table_name,
    relpages AS total_pages,
    current_setting('seq_page_cost')::decimal AS seq_page_cost_setting,
    relpages * current_setting('seq_page_cost')::decimal AS total_page_cost,
    reltuples AS estimated_rows,
    current_setting('cpu_tuple_cost')::decimal AS cpu_tuple_cost_setting,
    reltuples * current_setting('cpu_tuple_cost')::decimal AS total_tuple_cost,
    (relpages * current_setting('seq_page_cost')::decimal + 
     reltuples * current_setting('cpu_tuple_cost')::decimal) AS total_estimated_cost
FROM pg_class
WHERE relname = 'your_table_name'  -- Replace with actual table name
   OR relname = 'pgbench_tellers';  -- Example table

-- =====================================================================
-- 4. PERFORMANCE TESTING FRAMEWORK
-- =====================================================================

-- Create test environment for performance analysis
DROP TABLE IF EXISTS performance_test_estimates;
CREATE TABLE performance_test_estimates AS 
SELECT 
    generate_series(1, 10000) AS id,
    'test_data_' || generate_series(1, 10000) AS description,
    random() * 1000 AS value_column
FROM generate_series(1, 10000);

-- Update planner statistics for accurate cost estimation
ANALYZE performance_test_estimates;

-- Create index for comparison testing
CREATE INDEX IF NOT EXISTS idx_perf_test_id ON performance_test_estimates(id);
CREATE INDEX IF NOT EXISTS idx_perf_test_value ON performance_test_estimates(value_column);

-- =====================================================================
-- 5. FUNCTION-BASED QUERY PERFORMANCE TESTING
-- =====================================================================

-- Test 1: Function-based filter (prevents index usage)
EXPLAIN (ANALYZE, BUFFERS, COSTS) 
SELECT * FROM performance_test_estimates 
WHERE cos(id) < 0.5;

-- Test 2: Function-based filter with different selectivity
EXPLAIN (ANALYZE, BUFFERS, COSTS) 
SELECT * FROM performance_test_estimates 
WHERE cos(id) > 0.5;

-- Test 3: Regular indexed column filter for comparison
EXPLAIN (ANALYZE, BUFFERS, COSTS) 
SELECT * FROM performance_test_estimates 
WHERE id < 5000;

-- =====================================================================
-- 6. INDEX EFFICIENCY ANALYSIS
-- =====================================================================

-- Calculate index efficiency metrics
SELECT 
    schemaname,
    relname AS table_name,
    indexrelname AS index_name,
    idx_scan AS scan_count,
    idx_tup_read AS tuples_read,
    idx_tup_fetch AS tuples_fetched,
    CASE 
        WHEN idx_tup_read > 0 THEN 
            round((idx_tup_fetch::decimal / idx_tup_read) * 100, 2)
        ELSE 0 
    END AS selectivity_percent,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE idx_scan > 0
ORDER BY selectivity_percent DESC, idx_scan DESC;

-- =====================================================================
-- 7. PROBLEM DETECTION QUERIES
-- =====================================================================

-- Find unused indexes consuming space
SELECT 
    schemaname,
    relname AS table_name,
    indexrelname AS unused_index,
    pg_size_pretty(pg_relation_size(indexrelid)) AS wasted_space
FROM pg_stat_user_indexes
WHERE idx_scan = 0
  AND pg_relation_size(indexrelid) > 1024 * 1024  -- > 1MB
ORDER BY pg_relation_size(indexrelid) DESC;

-- Find tables without any indexes
SELECT 
    schemaname,
    tablename AS table_without_indexes,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS table_size
FROM pg_tables 
WHERE schemaname = 'public'
  AND tablename NOT IN (
      SELECT DISTINCT tablename 
      FROM pg_indexes 
      WHERE schemaname = 'public'
  )
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- =====================================================================
-- 8. CLEANUP (Optional - Run only if needed)
-- =====================================================================

-- Clean up test table (uncomment to execute)
-- DROP TABLE IF EXISTS performance_test_estimates;

-- =====================================================================
-- END OF SCRIPT
-- =====================================================================    