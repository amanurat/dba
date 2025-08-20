-- ==========================================================================================================
-- PostgreSQL Performance Analysis & Tuning - Complete Step-by-Step Guide
-- ==========================================================================================================
-- 
-- PURPOSE: Comprehensive script for systematic PostgreSQL database performance analysis and optimization
-- VERSION: 1.0
-- AUTHOR: PostgreSQL DBA Team
-- DATE: 2024-08-13
-- 
-- USAGE:
--   psql "host=yourserver.postgres.database.azure.com user=youruser dbname=yourdb sslmode=require" -f step_tuning.sql
--   
-- SAFETY LEVELS:
--   🟢 SAFE     - Read-only analysis, safe for production
--   🟡 MEDIUM   - Safe optimizations, test recommended  
--   🔴 HIGH     - Major changes, backup required, maintenance window needed
-- 
-- PREREQUISITES:
--   - pg_stat_statements extension enabled
--   - Adequate permissions for analysis queries
--   - For implementation: DBA privileges and maintenance window
-- 
-- TIME ESTIMATE: 45-60 minutes for complete analysis and recommendations
-- 
-- ==========================================================================================================

\set ECHO all
\timing on

\echo ''
\echo '============================================================================================================'
\echo 'PostgreSQL Performance Tuning - Step-by-Step Analysis'
\echo '============================================================================================================'
\echo 'Database: ' :HOST ' / ' :DBNAME
\echo 'User: ' :USER  
\echo 'Date: ' `date`
\echo '============================================================================================================'
\echo ''

-- ==========================================================================================================
-- PHASE 1: INITIAL ANALYSIS (🟢 SAFE - READ-ONLY)
-- ==========================================================================================================

\echo ''
\echo '========================================='
\echo '🟢 PHASE 1: INITIAL ANALYSIS'
\echo '========================================='
\echo ''

-- ---------------------------------------------------------------------------------------------------------
-- STEP 1: DATABASE HEALTH OVERVIEW
-- ---------------------------------------------------------------------------------------------------------

\echo '>>> STEP 1: Database Health Overview'
\echo '------------------------------------'
\echo 'Analyzing: Server info, database size, connections, basic performance metrics'
\echo ''

-- Server and Database Information
SELECT 
    'Server Information' as metric_category,
    'PostgreSQL Version' as metric_name,
    version() as metric_value,
    'Info' as recommendation
UNION ALL
SELECT 
    'Server Information',
    'Server Uptime',
    EXTRACT(epoch FROM (now() - pg_postmaster_start_time()))::text || ' seconds (' || 
    EXTRACT(days FROM (now() - pg_postmaster_start_time())) || ' days)',
    CASE 
        WHEN EXTRACT(days FROM (now() - pg_postmaster_start_time())) < 1 THEN 'Recent restart - metrics may be incomplete'
        ELSE 'Good data collection period'
    END
UNION ALL
SELECT 
    'Database Size',
    'Current Database Size',
    pg_size_pretty(pg_database_size(current_database())),
    CASE 
        WHEN pg_database_size(current_database()) > 107374182400 THEN 'Large database (>100GB) - monitor performance closely'
        WHEN pg_database_size(current_database()) > 10737418240 THEN 'Medium database (>10GB) - consider partitioning large tables'
        ELSE 'Small database (<10GB) - basic optimization sufficient'
    END
UNION ALL
SELECT 
    'Connections',
    'Current Active Connections',
    (SELECT count(*)::text FROM pg_stat_activity WHERE state = 'active'),
    CASE 
        WHEN (SELECT count(*) FROM pg_stat_activity WHERE state = 'active') > 50 THEN 'High connection count - investigate connection pooling'
        WHEN (SELECT count(*) FROM pg_stat_activity WHERE state = 'active') > 20 THEN 'Moderate connection usage - monitor trends'
        ELSE 'Low connection usage - normal'
    END
UNION ALL
SELECT 
    'Cache Performance',
    'Buffer Cache Hit Ratio',
    ROUND(
        100.0 * sum(heap_blks_hit) / 
        NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0), 2
    )::text || '%',
    CASE 
        WHEN ROUND(100.0 * sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0), 2) < 90 
        THEN 'Low cache hit ratio - increase shared_buffers'
        WHEN ROUND(100.0 * sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0), 2) < 95 
        THEN 'Moderate cache performance - monitor and optimize'
        ELSE 'Good cache performance'
    END
FROM pg_statio_user_tables;

\echo ''
\echo '>>> STEP 1 ANALYSIS COMPLETE'
\echo 'Review the metrics above:'
\echo '- Database size indicates optimization complexity'
\echo '- Connection count affects resource planning'
\echo '- Cache hit ratio <95% suggests memory tuning needed'
\echo ''

-- ---------------------------------------------------------------------------------------------------------
-- STEP 2: QUERY PERFORMANCE ANALYSIS
-- ---------------------------------------------------------------------------------------------------------

\echo '>>> STEP 2: Query Performance Analysis'
\echo '-------------------------------------'
\echo 'Analyzing: Top slow queries, execution patterns, resource consumption'
\echo ''

-- Check if pg_stat_statements is available
DO $$
DECLARE
    ext_exists boolean;
BEGIN
    SELECT EXISTS(
        SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements'
    ) INTO ext_exists;
    
    IF NOT ext_exists THEN
        RAISE NOTICE 'WARNING: pg_stat_statements extension is not installed!';
        RAISE NOTICE 'Install with: CREATE EXTENSION pg_stat_statements;';
        RAISE NOTICE 'Some analysis steps will be skipped.';
    END IF;
END $$;

-- Top 10 Slowest Queries by Total Time
\echo 'Top 10 Slowest Queries by Total Execution Time:'
SELECT 
    ROW_NUMBER() OVER (ORDER BY total_exec_time DESC) as rank,
    LEFT(query, 80) as query_preview,
    calls,
    ROUND(total_exec_time::numeric, 2) as total_time_ms,
    ROUND(mean_exec_time::numeric, 2) as avg_time_ms,
    ROUND(max_exec_time::numeric, 2) as max_time_ms,
    rows as total_rows,
    CASE 
        WHEN mean_exec_time > 1000 THEN '🔴 SLOW'
        WHEN mean_exec_time > 100 THEN '🟡 MODERATE'  
        ELSE '🟢 FAST'
    END as performance_status
FROM pg_stat_statements 
WHERE query NOT LIKE '%pg_stat_statements%'
    AND query NOT LIKE '%COMMIT%'
    AND query NOT LIKE '%BEGIN%'
    AND query NOT LIKE '%ANALYZE%'
    AND query NOT LIKE '%CREATE INDEX%'
    AND query NOT LIKE '%SELECT query_store%'
    AND total_exec_time > 0
ORDER BY total_exec_time DESC 
LIMIT 10;

\echo ''

-- Top 10 Most Called Queries
\echo 'Top 10 Most Frequently Called Queries:'
SELECT 
    ROW_NUMBER() OVER (ORDER BY calls DESC) as rank,
    LEFT(query, 80) as query_preview,
    calls,
    ROUND(total_exec_time::numeric, 2) as total_time_ms,
    ROUND(mean_exec_time::numeric, 2) as avg_time_ms,
    CASE 
        WHEN calls > 10000 THEN '🔴 VERY HIGH'
        WHEN calls > 1000 THEN '🟡 HIGH'
        ELSE '🟢 NORMAL'
    END as frequency_status
FROM pg_stat_statements 
WHERE query NOT LIKE '%pg_stat_statements%'
    AND query NOT LIKE '%COMMIT%'
    AND query NOT LIKE '%commit%'
    AND query NOT LIKE '%BEGIN%'
    AND query NOT LIKE '%begin%'
    AND query NOT LIKE '%CLOSE ALL%'
    AND query NOT LIKE '%RESET ALL%'
    AND query NOT LIKE '%DISCARD%'
    AND query NOT LIKE '%UNLISTEN%'
ORDER BY calls DESC
LIMIT 10;

\echo ''
\echo '>>> STEP 2 ANALYSIS COMPLETE'
\echo 'Review the query analysis:'
\echo '- 🔴 SLOW queries (>1000ms) need immediate optimization'  
\echo '- 🟡 MODERATE queries (>100ms) should be investigated'
\echo '- High frequency queries should be optimized even if individually fast'
\echo ''

-- ---------------------------------------------------------------------------------------------------------
-- STEP 3: INDEX USAGE ANALYSIS
-- ---------------------------------------------------------------------------------------------------------

\echo '>>> STEP 3: Index Usage Analysis'
\echo '--------------------------------'
\echo 'Analyzing: Index efficiency, unused indexes, sequential scan patterns'
\echo ''

-- Index Usage Statistics
\echo 'Index Usage Statistics (Top 15 by scans):'
SELECT 
    schemaname,
    relname as table_name,
    indexrelname as index_name,
    idx_scan as scans,
    idx_tup_read as tuples_read,
    idx_tup_fetch as tuples_fetched,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size,
    CASE 
        WHEN idx_scan = 0 THEN '🔴 UNUSED'
        WHEN idx_scan < 100 THEN '🟡 LOW USAGE'
        WHEN idx_scan < 1000 THEN '🟢 MODERATE'
        ELSE '🟢 HIGH USAGE'
    END as usage_status
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC, pg_relation_size(indexrelid) DESC
LIMIT 15;

\echo ''

-- Unused Indexes (Candidates for Removal)
\echo 'Unused Indexes (Candidates for Removal):'
SELECT 
    schemaname,
    relname as table_name,
    indexrelname as index_name,
    pg_size_pretty(pg_relation_size(pi.indexrelid)) as wasted_space,
    'DROP INDEX ' || schemaname || '.' || indexrelname || ';' as drop_statement
FROM pg_stat_user_indexes psi
JOIN pg_index pi ON psi.indexrelid = pi.indexrelid
WHERE idx_scan = 0
    AND NOT pi.indisunique  -- Keep unique indexes
    AND NOT pi.indisprimary -- Keep primary key indexes
ORDER BY pg_relation_size(pi.indexrelid) DESC;

\echo ''

-- Tables with High Sequential Scan Ratio
\echo 'Tables with High Sequential Scan Ratio (May Need Indexes):'
SELECT 
    schemaname,
    pc.relname as table_name,
    seq_scan,
    idx_scan,
    CASE WHEN (seq_scan + idx_scan) > 0 
         THEN ROUND(100.0 * seq_scan / (seq_scan + idx_scan), 2)
         ELSE 0 
    END as seq_scan_ratio,
    pg_size_pretty(pg_relation_size(oid)) as table_size,
    CASE 
        WHEN seq_scan > idx_scan AND seq_scan > 1000 THEN '🔴 HIGH SEQ SCAN'
        WHEN seq_scan > idx_scan AND seq_scan > 100 THEN '🟡 MODERATE SEQ SCAN'
        ELSE '🟢 GOOD INDEX USAGE'
    END as scan_status
FROM pg_stat_user_tables ps
JOIN pg_class pc ON ps.relname = pc.relname
WHERE (seq_scan + idx_scan) > 0
ORDER BY seq_scan_ratio DESC, seq_scan DESC
LIMIT 10;

\echo ''
\echo '>>> STEP 3 ANALYSIS COMPLETE'
\echo 'Review index analysis:'
\echo '- 🔴 UNUSED indexes consume space and slow down writes'
\echo '- Tables with high sequential scan ratios may need indexes'
\echo '- Large tables with frequent seq scans are priority for indexing'
\echo ''

-- ---------------------------------------------------------------------------------------------------------
-- STEP 4: TABLE STATISTICS AND MAINTENANCE
-- ---------------------------------------------------------------------------------------------------------

\echo '>>> STEP 4: Table Statistics and Maintenance Analysis'
\echo '----------------------------------------------------'
\echo 'Analyzing: Table bloat, VACUUM status, UPDATE/DELETE patterns'
\echo ''

-- Table Size and Bloat Estimation
\echo 'Table Size and Maintenance Statistics:'
SELECT 
    schemaname,
    relname as table_name,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||relname)) as total_size,
    n_tup_ins as inserts,
    n_tup_upd as updates,
    n_tup_del as deletes,
    n_tup_upd + n_tup_del as modifications,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze,
    CASE 
        WHEN last_autovacuum IS NULL AND last_vacuum IS NULL THEN '🔴 NEVER VACUUMED'
        WHEN COALESCE(last_autovacuum, last_vacuum) < NOW() - INTERVAL '7 days' THEN '🟡 VACUUM OVERDUE'
        ELSE '🟢 RECENT VACUUM'
    END as vacuum_status,
    CASE 
        WHEN last_autoanalyze IS NULL AND last_analyze IS NULL THEN '🔴 NEVER ANALYZED'
        WHEN COALESCE(last_autoanalyze, last_analyze) < NOW() - INTERVAL '1 day' THEN '🟡 ANALYZE OVERDUE'
        ELSE '🟢 RECENT ANALYZE'
    END as analyze_status
FROM pg_stat_user_tables
WHERE n_tup_ins + n_tup_upd + n_tup_del > 0
ORDER BY pg_total_relation_size(schemaname||'.'||relname) DESC
LIMIT 15;

\echo ''

-- Lock Analysis
\echo 'Current Lock Analysis:'
SELECT 
    pl.locktype,
    pl.mode,
    pl.granted,
    pa.usename,
    pa.query_start,
    pa.state,
    LEFT(pa.query, 60) as query_preview
FROM pg_locks pl
JOIN pg_stat_activity pa ON pl.pid = pa.pid
WHERE NOT pl.granted OR pl.mode LIKE '%ExclusiveLock%'
ORDER BY pa.query_start;

\echo ''
\echo '>>> STEP 4 ANALYSIS COMPLETE'
\echo 'Review table maintenance:'
\echo '- Tables that have never been vacuumed/analyzed need immediate attention'
\echo '- High modification counts may indicate bloat issues'
\echo '- Current locks may indicate contention issues'
\echo ''

-- ==========================================================================================================
-- PHASE 2: PROBLEM IDENTIFICATION (🟢 SAFE - ANALYSIS ONLY)
-- ==========================================================================================================

\echo ''
\echo '========================================='
\echo '🟢 PHASE 2: PROBLEM IDENTIFICATION'
\echo '========================================='
\echo ''

-- ---------------------------------------------------------------------------------------------------------
-- STEP 5: PERFORMANCE BOTTLENECK DETECTION
-- ---------------------------------------------------------------------------------------------------------
\echo '>>> STEP 5: Performance Bottleneck Detection'
\echo '-------------------------------------------'
\echo 'Analyzing: Critical performance issues and resource bottlenecks'
\echo ''

-- Critical Performance Issues Summary
\echo 'CRITICAL PERFORMANCE ISSUES DETECTED:'
WITH performance_issues AS (
    -- Slow queries issue
    SELECT 
        'Slow Queries' as issue_type,
        COUNT(*) as issue_count,
        '🔴 HIGH' as priority,
        'Queries averaging >1000ms execution time' as description,
        'Optimize queries, add indexes, rewrite inefficient statements' as recommendation
    FROM pg_stat_statements 
    WHERE mean_exec_time > 1000
    
    UNION ALL
    
    -- Unused indexes issue  
    SELECT 
        'Unused Indexes',
        COUNT(*),
        '🟡 MEDIUM',
        'Indexes that are never used but consume space',
        'Consider dropping unused indexes to improve write performance'
    FROM pg_stat_user_indexes psi
    JOIN pg_index pi ON psi.indexrelid = pi.indexrelid
    WHERE idx_scan = 0 AND NOT pi.indisunique AND NOT pi.indisprimary
    
    UNION ALL
    
    -- High sequential scan tables
    SELECT 
        'Missing Indexes',
        COUNT(*),
        '🔴 HIGH', 
        'Large tables with high sequential scan ratios',
        'Add appropriate indexes to frequently queried columns'
    FROM pg_stat_user_tables ps
    JOIN pg_class pc ON ps.relname = pc.relname
    WHERE seq_scan > idx_scan 
        AND seq_scan > 1000
        AND pg_relation_size(oid) > 10485760 -- >10MB
    
    UNION ALL
    
    -- Cache hit ratio issue
    SELECT 
        'Low Cache Hit Ratio',
        1,
        '🟡 MEDIUM',
        'Buffer cache hit ratio below 95%',
        'Increase shared_buffers parameter'
    WHERE (
        SELECT ROUND(100.0 * sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0), 2)
        FROM pg_statio_user_tables
    ) < 95
)
SELECT * FROM performance_issues WHERE issue_count > 0
ORDER BY 
    CASE priority 
        WHEN '🔴 HIGH' THEN 1 
        WHEN '🟡 MEDIUM' THEN 2 
        ELSE 3 
    END;

\echo ''
\echo '>>> STEP 5 ANALYSIS COMPLETE'
\echo 'Critical issues identified above should be addressed first'
\echo 'Focus on 🔴 HIGH priority issues for maximum impact'
\echo ''

-- ---------------------------------------------------------------------------------------------------------
-- STEP 6: CONFIGURATION ANALYSIS
-- ---------------------------------------------------------------------------------------------------------

\echo '>>> STEP 6: Configuration Analysis'
\echo '---------------------------------'
\echo 'Analyzing: Server configuration and parameter optimization opportunities'
\echo ''

-- Key Configuration Parameters Analysis
\echo 'Current Configuration vs Recommendations:'
SELECT 
    name as parameter,
    setting as current_value,
    unit,
    CASE 
        -- Memory parameters
        WHEN name = 'shared_buffers' THEN
            CASE 
                WHEN setting::bigint * 
                    CASE unit 
                        WHEN 'kB' THEN 1024 
                        WHEN 'MB' THEN 1024*1024 
                        WHEN 'GB' THEN 1024*1024*1024 
                        ELSE 1 
                    END < 134217728 THEN '🔴 Consider increasing to 128MB+ (25% of RAM)'
                ELSE '🟢 Adequate'
            END
        WHEN name = 'effective_cache_size' THEN '🟢 Usually auto-managed by Azure'
        WHEN name = 'work_mem' THEN
            CASE 
                WHEN setting::int < 4096 THEN '🟡 Consider increasing to 4MB+ for complex queries'
                ELSE '🟢 Adequate'
            END
        WHEN name = 'maintenance_work_mem' THEN
            CASE 
                WHEN setting::int < 65536 THEN '🟡 Consider increasing to 64MB+ for maintenance'
                ELSE '🟢 Adequate'
            END
        -- Connection parameters  
        WHEN name = 'max_connections' THEN
            CASE 
                WHEN setting::int > 200 THEN '🟡 High connection limit - consider connection pooling'
                ELSE '🟢 Reasonable'
            END
        -- Query planner parameters
        WHEN name = 'random_page_cost' THEN
            CASE 
                WHEN setting::numeric > 2.0 THEN '🟡 Consider lowering to 1.1 for SSD storage'
                ELSE '🟢 Optimized for SSD'
            END
        WHEN name = 'effective_io_concurrency' THEN
            CASE 
                WHEN setting::int < 100 THEN '🟡 Consider increasing to 200 for SSD storage'  
                ELSE '🟢 Optimized for SSD'
            END
        ELSE '🟢 Standard'
    END as recommendation
FROM pg_settings 
WHERE name IN (
    'shared_buffers', 
    'effective_cache_size',
    'work_mem', 
    'maintenance_work_mem',
    'max_connections',
    'random_page_cost',
    'effective_io_concurrency',
    'checkpoint_completion_target',
    'wal_buffers'
)
ORDER BY name;

\echo ''
\echo '>>> STEP 6 ANALYSIS COMPLETE'
\echo 'Configuration recommendations above focus on memory and I/O optimization'  
\echo '🔴 RED items need immediate attention'
\echo '🟡 YELLOW items provide moderate performance improvements'
\echo ''

-- ==========================================================================================================
-- PHASE 3: RECOMMENDATIONS (🟢 SAFE - SUGGESTIONS ONLY)
-- ==========================================================================================================

\echo ''
\echo '========================================='
\echo '🟢 PHASE 3: RECOMMENDATIONS'
\echo '========================================='
\echo ''

-- ---------------------------------------------------------------------------------------------------------
-- STEP 7: INDEX RECOMMENDATIONS  
-- ---------------------------------------------------------------------------------------------------------

\echo '>>> STEP 7: Index Recommendations'
\echo '---------------------------------'
\echo 'Generating: Specific index creation and removal recommendations'
\echo ''

-- Recommended Indexes Based on Query Analysis
\echo 'RECOMMENDED INDEX CREATIONS:'
\echo '(Based on high sequential scan ratios and query patterns)'
\echo ''

-- Tables that would benefit from indexes
WITH index_candidates AS (
    SELECT 
        ps.schemaname,
        ps.relname as table_name,
        ps.seq_scan,
        ps.idx_scan,
        pg_size_pretty(pg_relation_size(pc.oid)) as table_size,
        pg_relation_size(pc.oid) as table_size_bytes
    FROM pg_stat_user_tables ps
    JOIN pg_class pc ON ps.relname = pc.relname
    WHERE ps.seq_scan > ps.idx_scan 
        AND ps.seq_scan > 100
        AND pg_relation_size(pc.oid) > 1048576 -- >1MB
)
SELECT 
    '-- High Priority: ' || table_name || ' (SeqScans: ' || seq_scan || ', Size: ' || table_size || ')' as recommendation,
    '-- Suggested: CREATE INDEX idx_' || table_name || '_commonly_queried_column ON ' || 
    schemaname || '.' || table_name || ' (commonly_queried_column);' as suggested_sql,
    '-- Impact: HIGH - Will significantly reduce query times' as impact
FROM index_candidates
WHERE table_size_bytes > 10485760 -- >10MB
ORDER BY seq_scan DESC, table_size_bytes DESC
LIMIT 5;

\echo ''

-- Indexes Recommended for Removal
\echo 'RECOMMENDED INDEX REMOVALS:'
\echo '(Unused indexes that consume space and slow writes)'
\echo ''

SELECT 
    '-- DROP INDEX ' || schemaname || '.' || indexrelname || ';' as drop_statement,
    '-- Space savings: ' || pg_size_pretty(pg_relation_size(pi.indexrelid)) as space_savings,
    '-- Impact: MEDIUM - Improves write performance, frees disk space' as impact
FROM pg_stat_user_indexes psi
JOIN pg_index pi ON psi.indexrelid = pi.indexrelid
WHERE idx_scan = 0
    AND NOT pi.indisunique  
    AND NOT pi.indisprimary
    AND pg_relation_size(pi.indexrelid) > 1048576 -- >1MB
ORDER BY pg_relation_size(pi.indexrelid) DESC
LIMIT 10;

\echo ''
\echo '>>> STEP 7 RECOMMENDATIONS COMPLETE'
\echo 'Index recommendations above are based on usage patterns'
\echo 'CREATE indexes during low-traffic periods'
\echo 'DROP unused indexes after confirming they are not needed'
\echo ''

-- ---------------------------------------------------------------------------------------------------------
-- STEP 8: QUERY OPTIMIZATION RECOMMENDATIONS
-- ---------------------------------------------------------------------------------------------------------

\echo '>>> STEP 8: Query Optimization Recommendations' 
\echo '---------------------------------------------'
\echo 'Analyzing: Specific query optimization opportunities'
\echo ''

-- Top Queries Needing Optimization
\echo 'TOP QUERIES REQUIRING OPTIMIZATION:'
SELECT 
    ROW_NUMBER() OVER (ORDER BY total_exec_time DESC) as priority,
    LEFT(query, 100) as query_preview,
    calls,
    ROUND(mean_exec_time::numeric, 2) as avg_time_ms,
    ROUND(total_exec_time::numeric, 2) as total_time_ms,
    CASE 
        WHEN query LIKE '%SELECT%FROM%WHERE%' AND query LIKE '%ORDER BY%' 
        THEN 'Add index on ORDER BY columns'
        WHEN query LIKE '%SELECT%FROM%WHERE%' AND query LIKE '%GROUP BY%'
        THEN 'Add index on GROUP BY columns' 
        WHEN query LIKE '%SELECT%FROM%WHERE%' AND NOT query LIKE '%LIMIT%'
        THEN 'Add LIMIT clause if appropriate + index on WHERE columns'
        WHEN query LIKE '%UPDATE%WHERE%' OR query LIKE '%DELETE%WHERE%'
        THEN 'Add index on WHERE clause columns'
        ELSE 'Review execution plan with EXPLAIN ANALYZE'
    END as optimization_suggestion
FROM pg_stat_statements
WHERE mean_exec_time > 100
    AND query NOT LIKE '%pg_stat_statements%'
    AND calls > 10
ORDER BY total_exec_time DESC
LIMIT 10;

\echo ''

-- Query Pattern Analysis
\echo 'QUERY PATTERN OPTIMIZATION OPPORTUNITIES:'
WITH query_patterns AS (
    SELECT 
        CASE 
            WHEN query LIKE '%SELECT%COUNT(*)%' THEN 'COUNT(*) Queries'
            WHEN query LIKE '%ORDER BY%LIMIT%' THEN 'Paginated Queries'
            WHEN query LIKE '%SELECT%FROM%JOIN%JOIN%' THEN 'Multi-Join Queries'
            WHEN query LIKE '%WHERE%LIKE%' THEN 'LIKE Pattern Queries'
            WHEN query LIKE '%WHERE%IN (%' THEN 'IN Clause Queries'
            ELSE 'Other'
        END as pattern_type,
        COUNT(*) as query_count,
        AVG(mean_exec_time) as avg_execution_time,
        SUM(total_exec_time) as total_time_spent
    FROM pg_stat_statements
    WHERE calls > 5
    GROUP BY 1
)
SELECT 
    pattern_type,
    query_count,
    ROUND(avg_execution_time::numeric, 2) as avg_time_ms,
    ROUND(total_time_spent::numeric, 2) as total_time_ms,
    CASE pattern_type
        WHEN 'COUNT(*) Queries' THEN 'Consider materialized views or approximations'
        WHEN 'Paginated Queries' THEN 'Ensure indexes on ORDER BY columns'  
        WHEN 'Multi-Join Queries' THEN 'Review join order and add indexes'
        WHEN 'LIKE Pattern Queries' THEN 'Consider full-text search or trigram indexes'
        WHEN 'IN Clause Queries' THEN 'Consider JOINs instead of large IN clauses'
        ELSE 'Review individual queries'
    END as optimization_strategy
FROM query_patterns
WHERE pattern_type != 'Other'
ORDER BY total_time_spent DESC;

\echo ''
\echo '>>> STEP 8 RECOMMENDATIONS COMPLETE'
\echo 'Query optimization strategies above target common performance patterns'
\echo 'Use EXPLAIN ANALYZE to verify optimization effectiveness'
\echo ''

-- ==========================================================================================================
-- PHASE 4: IMPLEMENTATION SCRIPTS (🟡🔴 CAUTION - MAKES CHANGES)
-- ==========================================================================================================

\echo ''
\echo '========================================='
\echo '⚠️  PHASE 4: IMPLEMENTATION SCRIPTS'
\echo '========================================='
\echo ''
\echo '🚨 WARNING: The following steps make actual changes to your database!'
\echo '🚨 ALWAYS test in development environment first'
\echo '🚨 Take backups before running production changes'
\echo '🚨 Run during maintenance windows for major changes'
\echo ''

-- ---------------------------------------------------------------------------------------------------------
-- STEP 9: SAFE OPTIMIZATIONS (🟡 MEDIUM RISK)
-- ---------------------------------------------------------------------------------------------------------

\echo '>>> STEP 9: Safe Optimizations (🟡 MEDIUM RISK)'
\echo '----------------------------------------------'
\echo 'These changes are relatively safe but should be tested first'
\echo ''

-- Update table statistics (safe operation)
\echo '-- SAFE OPERATION: Update Table Statistics'
\echo '-- This improves query planning accuracy'
\echo ''

\echo 'Updating statistics for tables with outdated analysis...'
DO $$
DECLARE
    table_record RECORD;
    analyze_sql TEXT;
BEGIN
    FOR table_record IN 
        SELECT schemaname, relname 
        FROM pg_stat_user_tables 
        WHERE (last_analyze IS NULL OR last_analyze < NOW() - INTERVAL '1 day')
           OR (last_autoanalyze IS NULL OR last_autoanalyze < NOW() - INTERVAL '1 day')
        ORDER BY n_tup_ins + n_tup_upd + n_tup_del DESC
        LIMIT 10
    LOOP
        analyze_sql := 'ANALYZE ' || quote_ident(table_record.schemaname) || '.' || quote_ident(table_record.relname);
        RAISE NOTICE 'Executing: %', analyze_sql;
        EXECUTE analyze_sql;
    END LOOP;
END $$;

\echo ''
\echo '>>> STEP 9 COMPLETE'
\echo 'Statistics updated for tables with stale analysis'
\echo 'This should improve query planning immediately'
\echo ''

-- ---------------------------------------------------------------------------------------------------------
-- STEP 10: INDEX IMPLEMENTATION (🟡 MEDIUM RISK)
-- ---------------------------------------------------------------------------------------------------------

\echo '>>> STEP 10: Index Implementation (🟡 MEDIUM RISK)'
\echo '------------------------------------------------'
\echo 'CAUTION: Index creation can be resource intensive'
\echo 'Run during low-traffic periods'
\echo ''

\echo '-- INDEX CREATION SCRIPTS (Review before executing):'
\echo '-- The following are SUGGESTIONS based on analysis'
\echo '-- Customize column names based on your actual schema'
\echo ''

-- Generate sample index creation scripts
WITH index_suggestions AS (
    SELECT 
        ps.schemaname,
        ps.relname as table_name,
        ps.seq_scan,
        pg_size_pretty(pg_relation_size(pc.oid)) as table_size
    FROM pg_stat_user_tables ps
    JOIN pg_class pc ON ps.relname = pc.relname
    WHERE ps.seq_scan > ps.idx_scan 
        AND ps.seq_scan > 100
        AND pg_relation_size(pc.oid) > 10485760 -- >10MB
    ORDER BY ps.seq_scan DESC
    LIMIT 5
)
SELECT 
    '-- High impact index for table: ' || table_name as comment,
    '-- CREATE INDEX CONCURRENTLY idx_' || table_name || '_your_column ON ' || 
    schemaname || '.' || table_name || ' (your_frequently_queried_column);' as suggested_index,
    '-- Table size: ' || table_size || ', Sequential scans: ' || seq_scan as impact_info
FROM index_suggestions;

\echo ''
\echo '-- UNUSED INDEX REMOVAL (Review carefully before executing):'

-- Generate index removal scripts for unused indexes
SELECT 
    '-- DROP INDEX ' || schemaname || '.' || indexrelname || ';' as drop_statement,
    '-- Saves: ' || pg_size_pretty(pg_relation_size(indexrelid)) || ' disk space' as space_savings
FROM pg_stat_user_indexes psi
JOIN pg_index pi ON psi.indexrelid = pi.indexrelid
WHERE idx_scan = 0
    AND NOT pi.indisunique  
    AND NOT pi.indisprimary
ORDER BY pg_relation_size(indexrelid) DESC
LIMIT 5;

\echo ''
\echo '>>> STEP 10 RECOMMENDATIONS GENERATED'
\echo 'Review the suggested INDEX statements above'
\echo 'Customize column names based on your query patterns'
\echo 'Use CREATE INDEX CONCURRENTLY to avoid blocking writes'
\echo ''

-- ---------------------------------------------------------------------------------------------------------
-- STEP 11: VERIFICATION AND MONITORING
-- ---------------------------------------------------------------------------------------------------------

\echo '>>> STEP 11: Verification and Monitoring Setup'
\echo '---------------------------------------------'
\echo 'Setting up ongoing performance monitoring'
\echo ''

-- Create a simple performance monitoring view (if it doesn't exist)
\echo 'Creating performance monitoring view...'

CREATE OR REPLACE VIEW performance_summary AS
SELECT 
    'Query Performance' as metric_category,
    COUNT(*) FILTER (WHERE mean_exec_time > 1000) as slow_queries,
    COUNT(*) FILTER (WHERE calls > 1000) as frequent_queries,
    COUNT(*) as total_tracked_queries,
    ROUND(AVG(mean_exec_time)::numeric, 2) as avg_query_time_ms
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'

UNION ALL

SELECT 
    'Index Efficiency',
    COUNT(*) FILTER (WHERE idx_scan = 0) as unused_indexes,
    COUNT(*) FILTER (WHERE idx_scan > 0) as used_indexes,
    COUNT(*) as total_indexes,
    NULL
FROM pg_stat_user_indexes psi
JOIN pg_index pi ON psi.indexrelid = pi.indexrelid
WHERE NOT pi.indisprimary

UNION ALL

SELECT 
    'Cache Performance',
    NULL,
    NULL,
    NULL,
    ROUND(100.0 * sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0), 2)
FROM pg_statio_user_tables;

\echo ''
\echo 'Performance monitoring view created!'
\echo 'Use: SELECT * FROM performance_summary; for ongoing monitoring'
\echo ''

-- Final Performance Score Calculation
\echo '>>> FINAL PERFORMANCE ASSESSMENT'
\echo '===============================';

WITH performance_metrics AS (
    SELECT 
        -- Cache hit ratio score (0-30 points)
        CASE 
            WHEN cache_hit_ratio >= 98 THEN 30
            WHEN cache_hit_ratio >= 95 THEN 25
            WHEN cache_hit_ratio >= 90 THEN 20
            WHEN cache_hit_ratio >= 85 THEN 15
            ELSE 10
        END as cache_score,
        
        -- Query performance score (0-30 points) 
        CASE 
            WHEN slow_query_ratio <= 0.01 THEN 30  -- <1% slow queries
            WHEN slow_query_ratio <= 0.05 THEN 25  -- <5% slow queries
            WHEN slow_query_ratio <= 0.10 THEN 20  -- <10% slow queries  
            WHEN slow_query_ratio <= 0.20 THEN 15  -- <20% slow queries
            ELSE 10
        END as query_score,
        
        -- Index efficiency score (0-25 points)
        CASE 
            WHEN unused_index_ratio <= 0.05 THEN 25  -- <5% unused
            WHEN unused_index_ratio <= 0.10 THEN 20  -- <10% unused
            WHEN unused_index_ratio <= 0.20 THEN 15  -- <20% unused
            ELSE 10
        END as index_score,
        
        -- Table maintenance score (0-15 points)
        CASE 
            WHEN tables_need_vacuum <= 2 THEN 15
            WHEN tables_need_vacuum <= 5 THEN 12
            WHEN tables_need_vacuum <= 10 THEN 8
            ELSE 5
        END as maintenance_score,
        
        cache_hit_ratio,
        slow_query_ratio,
        unused_index_ratio, 
        tables_need_vacuum
    FROM (
        SELECT 
            -- Cache hit ratio
            COALESCE(
                ROUND(100.0 * sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0), 2),
                0
            ) as cache_hit_ratio,
            
            -- Slow query ratio
            COALESCE(
                (SELECT COUNT(*)::numeric / NULLIF(COUNT(*), 0) 
                 FROM pg_stat_statements 
                 WHERE mean_exec_time > 1000 AND calls > 10),
                0
            ) as slow_query_ratio,

            -- Unused index ratio
            COALESCE(
                    (
                        SELECT
                                    COUNT(*) FILTER (WHERE idx_scan = 0)::numeric
                                / NULLIF(COUNT(*), 0)
                        FROM pg_stat_user_indexes psi
                                 JOIN pg_index pi ON psi.indexrelid = pi.indexrelid
                        WHERE NOT pi.indisprimary
                    ),
                    0
            ) AS unused_index_ratio,
            
            -- Tables needing vacuum
            COALESCE(
                (SELECT COUNT(*)
                 FROM pg_stat_user_tables 
                 WHERE last_vacuum IS NULL AND last_autovacuum IS NULL),
                0
            ) as tables_need_vacuum
            
        FROM pg_statio_user_tables
    ) base_metrics
)
SELECT 
    'POSTGRESQL PERFORMANCE SCORE' as assessment,
    (cache_score + query_score + index_score + maintenance_score) || '/100' as total_score,
    CASE 
        WHEN (cache_score + query_score + index_score + maintenance_score) >= 90 THEN '🟢 EXCELLENT'
        WHEN (cache_score + query_score + index_score + maintenance_score) >= 80 THEN '🟢 GOOD' 
        WHEN (cache_score + query_score + index_score + maintenance_score) >= 70 THEN '🟡 FAIR'
        WHEN (cache_score + query_score + index_score + maintenance_score) >= 60 THEN '🟡 NEEDS IMPROVEMENT'
        ELSE '🔴 POOR - IMMEDIATE ACTION REQUIRED'
    END as grade,
    
    'Cache: ' || cache_score || '/30, Queries: ' || query_score || '/30, Indexes: ' || 
    index_score || '/25, Maintenance: ' || maintenance_score || '/15' as breakdown

FROM performance_metrics;

\echo ''
\echo '========================================='
\echo '📊 PERFORMANCE TUNING ANALYSIS COMPLETE'
\echo '========================================='
\echo ''
\echo '📋 SUMMARY OF COMPLETED STEPS:'
\echo '✅ Step 1: Database Health Overview'
\echo '✅ Step 2: Query Performance Analysis' 
\echo '✅ Step 3: Index Usage Analysis'
\echo '✅ Step 4: Table Statistics Analysis'
\echo '✅ Step 5: Performance Bottleneck Detection'
\echo '✅ Step 6: Configuration Analysis'
\echo '✅ Step 7: Index Recommendations'
\echo '✅ Step 8: Query Optimization Recommendations'
\echo '✅ Step 9: Safe Optimizations (Statistics Update)'
\echo '✅ Step 10: Index Implementation Suggestions'
\echo '✅ Step 11: Verification & Monitoring Setup'
\echo ''
\echo '📈 NEXT STEPS:'
\echo '1. Review all 🔴 HIGH priority issues identified'
\echo '2. Implement suggested index changes during maintenance windows'
\echo '3. Monitor performance using the created performance_summary view'
\echo '4. Re-run this analysis monthly for ongoing optimization'
\echo ''
\echo '🔗 RELATED DOCUMENTATION:'
\echo '- Query Templates: ../docs/03_postgresql_performance_query_templates.md'
\echo '- EXPLAIN Guide: ../docs/05_postgresql_explain_analyze_guide.md'  
\echo '- Index Analysis: ../docs/postgresql_index_analysis_cost_estimation_guide.md'
\echo '- Setup Guide: ../docs/01_postgresql_monitoring_complete_setup_guide.md'
\echo ''
\echo '⚠️  IMPORTANT REMINDERS:'
\echo '- Always test changes in development first'
\echo '- Take backups before implementing major changes'
\echo '- Monitor performance after changes'
\echo '- Use maintenance windows for index operations'
\echo ''
\echo 'Performance analysis completed successfully! 🎉'
\echo '============================================================================================================'

\timing off