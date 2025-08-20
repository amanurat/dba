-- List all databases
SELECT datname FROM pg_database WHERE datistemplate = false AND datallowconn = true AND datname NOT IN ('postgres', 'template0', 'template1','azure_sys','azure_maintenance');

-- 1. ตรวจสอบค่าปัจจุบัน
SHOW shared_buffers;

-- 2. ดูการใช้ Memory จริง
SELECT
    pg_size_pretty(pg_total_relation_size('pg_class')) as pg_class_size,
    current_setting('shared_buffers') as shared_buffers_setting;


-- 1. ดู Cache Hit Ratio แต่ละ database
WITH db_stats AS (
    SELECT
        current_database() as db_name,
        sum(heap_blks_hit) as hits,
        sum(heap_blks_read) as reads,
        sum(heap_blks_hit + heap_blks_read) as total
    FROM pg_statio_user_tables
)
SELECT
    db_name,
    ROUND(100.0 * hits / NULLIF(total, 0), 1) as cache_hit_ratio,
    pg_size_pretty(total * 8192) as total_buffer_used
FROM db_stats;

-- 2. ดู Table ไหนใช้ buffer เยอะสุด
SELECT
    schemaname,
    relname,
    heap_blks_hit,
    heap_blks_read,
    ROUND(100.0 * heap_blks_hit / NULLIF(heap_blks_hit + heap_blks_read, 0), 1) as hit_ratio
FROM pg_statio_user_tables
WHERE heap_blks_hit + heap_blks_read > 0
ORDER BY heap_blks_hit + heap_blks_read DESC
LIMIT 10;

-- 3. ดู Query ที่ทำให้ Cache Miss เยอะ
SELECT
    query,
    calls,
    shared_blks_hit,
    shared_blks_read,
    ROUND(100.0 * shared_blks_hit / NULLIF(shared_blks_hit + shared_blks_read, 0), 1) as hit_ratio
FROM pg_stat_statements
WHERE shared_blks_hit + shared_blks_read > 1000
ORDER BY shared_blks_read DESC
LIMIT 5;


-- =====================================================
-- Multi-Database Cache Hit Ratio Analysis Script
-- =====================================================
-- Description: Analyze cache performance across all databases
-- Usage: Run this as a superuser or database owner
-- =====================================================

-- 1. SUMMARY: All Databases Cache Hit Ratio Overview
-- =====================================================
WITH all_databases AS (
    SELECT datname
    FROM pg_database
    WHERE datistemplate = false
      AND datallowconn = true
      AND datname NOT IN ('postgres', 'template0', 'template1')
),
     cache_stats AS (
         -- This query needs to be run per database, so we'll show current database stats
         SELECT
             current_database() as database_name,
             COALESCE(sum(heap_blks_hit), 0) as total_hits,
             COALESCE(sum(heap_blks_read), 0) as total_reads,
             COALESCE(sum(heap_blks_hit + heap_blks_read), 0) as total_blocks,
             CASE
                 WHEN sum(heap_blks_hit + heap_blks_read) > 0
                     THEN ROUND(100.0 * sum(heap_blks_hit) / sum(heap_blks_hit + heap_blks_read), 2)
                 ELSE 0
                 END as cache_hit_ratio,
             pg_size_pretty(sum(heap_blks_hit + heap_blks_read) * 8192) as buffer_used,
             count(DISTINCT schemaname || '.' || relname) as table_count
         FROM pg_statio_user_tables
     )
SELECT
    '🎯 CURRENT DATABASE ANALYSIS' as analysis_type,
    database_name,
    cache_hit_ratio || '%' as cache_hit_ratio,
    CASE
        WHEN cache_hit_ratio >= 98 THEN '🟢 Excellent'
        WHEN cache_hit_ratio >= 95 THEN '🟢 Good'
        WHEN cache_hit_ratio >= 90 THEN '🟡 Fair'
        WHEN cache_hit_ratio >= 85 THEN '🟡 Poor'
        ELSE '🔴 Critical'
        END as performance_grade,
    buffer_used,
    table_count || ' tables' as table_count,
    total_hits || ' hits' as cache_hits,
    total_reads || ' disk reads' as disk_reads
FROM cache_stats;

-- =====================================================
-- 2. DETAILED: Current Database Table-Level Analysis
-- =====================================================
SELECT
    '📊 TABLE-LEVEL CACHE ANALYSIS' as section,
    schemaname as schema_name,
    relname as table_name,
    heap_blks_hit as cache_hits,
    heap_blks_read as disk_reads,
    heap_blks_hit + heap_blks_read as total_blocks,
    CASE
        WHEN heap_blks_hit + heap_blks_read = 0 THEN 'No Activity'
        ELSE ROUND(100.0 * heap_blks_hit / (heap_blks_hit + heap_blks_read), 1) || '%'
        END as hit_ratio,
    CASE
        WHEN heap_blks_hit + heap_blks_read = 0 THEN '⚪ No Data'
        WHEN 100.0 * heap_blks_hit / NULLIF(heap_blks_hit + heap_blks_read, 0) >= 95 THEN '🟢 Excellent'
        WHEN 100.0 * heap_blks_hit / NULLIF(heap_blks_hit + heap_blks_read, 0) >= 90 THEN '🟡 Fair'
        ELSE '🔴 Poor'
        END as status,
    pg_size_pretty(pg_relation_size(relid)) as table_size,
    pg_size_pretty((heap_blks_hit + heap_blks_read) * 8192) as buffer_usage
FROM pg_statio_user_tables
WHERE heap_blks_hit + heap_blks_read > 0
ORDER BY heap_blks_hit + heap_blks_read DESC;

-- =====================================================
-- 3. ANALYSIS: Cache Performance Issues
-- =====================================================
SELECT '🔍 CACHE PERFORMANCE ISSUES' as section;

-- Tables with poor cache performance
SELECT
    '🔴 POOR CACHE PERFORMANCE TABLES' as issue_type,
    schemaname || '.' || relname as table_name,
    ROUND(100.0 * heap_blks_hit / NULLIF(heap_blks_hit + heap_blks_read, 0), 1) as hit_ratio,
    heap_blks_read as disk_reads,
    pg_size_pretty(pg_relation_size(relid)) as table_size,
    'Consider adding indexes or optimizing queries' as recommendation
FROM pg_statio_user_tables
WHERE heap_blks_hit + heap_blks_read > 100  -- Only tables with significant activity
  AND 100.0 * heap_blks_hit / NULLIF(heap_blks_hit + heap_blks_read, 0) < 90
ORDER BY heap_blks_read DESC
LIMIT 10;

-- High disk read tables
SELECT
    '💿 HIGH DISK READ TABLES' as issue_type,
    schemaname || '.' || relname as table_name,
    heap_blks_read as disk_reads,
    ROUND(100.0 * heap_blks_hit / NULLIF(heap_blks_hit + heap_blks_read, 0), 1) as hit_ratio,
    pg_size_pretty(pg_relation_size(relid)) as table_size,
    'Candidates for memory optimization' as recommendation
FROM pg_statio_user_tables
WHERE heap_blks_read > 1000  -- High disk reads
ORDER BY heap_blks_read DESC
LIMIT 10;

-- =====================================================
-- 4. RECOMMENDATIONS: Optimization Suggestions
-- =====================================================
SELECT '💡 OPTIMIZATION RECOMMENDATIONS' as section;

WITH db_summary AS (
    SELECT
        ROUND(100.0 * sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit + heap_blks_read), 0), 1) as overall_hit_ratio,
        sum(heap_blks_read) as total_disk_reads,
        pg_size_pretty(sum(heap_blks_hit + heap_blks_read) * 8192) as total_buffer_used
    FROM pg_statio_user_tables
)
SELECT
    CASE
        WHEN overall_hit_ratio >= 98 THEN '🟢 EXCELLENT PERFORMANCE'
        WHEN overall_hit_ratio >= 95 THEN '🟡 GOOD - MINOR OPTIMIZATION NEEDED'
        WHEN overall_hit_ratio >= 90 THEN '🟠 FAIR - OPTIMIZATION RECOMMENDED'
        WHEN overall_hit_ratio >= 85 THEN '🔴 POOR - OPTIMIZATION REQUIRED'
        ELSE '🚨 CRITICAL - IMMEDIATE ACTION NEEDED'
        END as performance_status,
    overall_hit_ratio || '%' as current_hit_ratio,
    total_disk_reads || ' disk reads' as disk_activity,
    total_buffer_used as buffer_consumption,
    CASE
        WHEN overall_hit_ratio < 95 THEN
            '1. Increase shared_buffers parameter
             2. Optimize slow queries
             3. Add missing indexes
             4. Consider table partitioning for large tables'
        ELSE
            '1. Monitor performance regularly
             2. Continue current optimization strategy
             3. Consider query-level optimizations'
        END as recommendations
FROM db_summary;

-- =====================================================
-- 5. SYSTEM INFO: Current Database Configuration
-- =====================================================
SELECT '⚙️ CURRENT SYSTEM CONFIGURATION' as section;

SELECT
    name as parameter,
    setting as current_value,
    unit,
    CASE name
        WHEN 'shared_buffers' THEN
            CASE
                WHEN setting::bigint * 8192 / (1024*1024) < 256 THEN '🔴 Too Low - Consider increasing'
                WHEN setting::bigint * 8192 / (1024*1024) < 512 THEN '🟡 Moderate - Could be higher'
                ELSE '🟢 Good'
                END
        WHEN 'effective_cache_size' THEN '📊 OS Cache Size Hint'
        WHEN 'work_mem' THEN '🔧 Per-Query Memory'
        ELSE '📋 Configuration'
        END as assessment
FROM pg_settings
WHERE name IN (
               'shared_buffers',
               'effective_cache_size',
               'work_mem',
               'maintenance_work_mem',
               'max_connections'
    )
ORDER BY name;

-- =====================================================
-- 6. QUERY PERFORMANCE: Top Cache-Missing Queries
-- =====================================================
SELECT '🐌 TOP CACHE-MISSING QUERIES' as section;

SELECT
    LEFT(query, 1000) as query_preview,
    calls,
    shared_blks_hit as cache_hits,
    shared_blks_read as disk_reads,
    CASE
        WHEN shared_blks_hit + shared_blks_read = 0 THEN 'No Block Access'
        ELSE ROUND(100.0 * shared_blks_hit / (shared_blks_hit + shared_blks_read), 1) || '%'
        END as query_hit_ratio,
    ROUND(mean_exec_time::numeric, 2) as avg_time_ms,
    'Consider adding indexes or rewriting query' as suggestion
FROM pg_stat_statements
WHERE shared_blks_read > 100  -- Queries with significant disk reads
  AND calls > 10  -- Executed multiple times
ORDER BY shared_blks_read DESC
LIMIT 10;

-- =====================================================
-- 7. SUMMARY REPORT
-- =====================================================
SELECT '📋 SUMMARY REPORT' as section;

WITH performance_summary AS (
    SELECT
        current_database() as database_name,
        ROUND(100.0 * sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit + heap_blks_read), 0), 1) as hit_ratio,
        sum(heap_blks_read) as total_disk_reads,
        count(*) as active_tables,
        pg_size_pretty(pg_database_size(current_database())) as db_size
    FROM pg_statio_user_tables
    WHERE heap_blks_hit + heap_blks_read > 0
),
     config_info AS (
         SELECT setting as shared_buffers_mb
         FROM pg_settings
         WHERE name = 'shared_buffers'
     )
SELECT
    '🎯 DATABASE: ' || database_name as summary,
    '📊 Cache Hit Ratio: ' || hit_ratio || '%' as cache_performance,
    '💿 Disk Reads: ' || total_disk_reads as disk_activity,
    '📈 Active Tables: ' || active_tables as table_activity,
    '💾 Database Size: ' || db_size as size_info,
    '⚙️ Shared Buffers: ' || shared_buffers_mb as memory_config,
    '⏰ Analysis Time: ' || current_timestamp as report_time
FROM performance_summary, config_info;

-- =====================================================
-- 8. ACTIONABLE NEXT STEPS
-- =====================================================
SELECT '🚀 NEXT STEPS' as section;

SELECT
    'IMMEDIATE ACTIONS' as priority,
    'Run this script on each database individually for complete analysis' as action_1,
    'Monitor cache hit ratio daily using: SELECT 100.0 * sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit + heap_blks_read), 0) FROM pg_statio_user_tables;' as action_2,
    'If cache hit ratio < 95%, consider increasing shared_buffers' as action_3,
    'Optimize queries with high disk reads shown above' as action_4,
    'Schedule regular performance reviews weekly' as action_5;

-- =====================================================
-- END OF SCRIPT
-- Note: To analyze ALL databases, this script needs to be
-- executed against each database individually, or use
-- the companion bash script provided below in comments.
-- =====================================================

/*
BASH SCRIPT TO RUN AGAINST ALL DATABASES:
==========================================

#!/bin/bash
# Save this as analyze_all_databases.sh

echo "🔍 PostgreSQL Multi-Database Cache Analysis"
echo "=========================================="

# Get list of databases
DATABASES=$(psql -t -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datallowconn = true AND datname NOT IN ('postgres', 'template0', 'template1');" | grep -v '^$')

echo "📊 Found databases: $DATABASES"
echo ""

# Loop through each database
for db in $DATABASES; do
    echo "🎯 Analyzing database: $db"
    echo "------------------------"

    psql -d $db -c "
    SELECT
        '$db' as database_name,
        ROUND(100.0 * sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit + heap_blks_read), 0), 1) as cache_hit_ratio,
        sum(heap_blks_read) as disk_reads,
        pg_size_pretty(pg_database_size('$db')) as database_size,
        CASE
            WHEN ROUND(100.0 * sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit + heap_blks_read), 0), 1) >= 95 THEN '🟢 Good'
            WHEN ROUND(100.0 * sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit + heap_blks_read), 0), 1) >= 90 THEN '🟡 Fair'
            ELSE '🔴 Poor'
        END as status
    FROM pg_statio_user_tables
    WHERE heap_blks_hit + heap_blks_read > 0;
    "
    echo ""
done

echo "✅ Analysis complete!"

# Usage:
# chmod +x analyze_all_databases.sh
# ./analyze_all_databases.sh
*/