-- ==========================================================================================================
-- MySQL Performance Analysis & Tuning - Complete Step-by-Step Guide
-- ==========================================================================================================
-- 
-- PURPOSE: Comprehensive script for systematic MySQL database performance analysis and optimization
-- VERSION: 1.0
-- AUTHOR: MySQL DBA Team
-- DATE: 2024-08-13
-- 
-- USAGE:
--   mysql -h yourserver.mysql.database.azure.com -u youruser -p yourdb < step_tuning.sql
--   
-- SAFETY LEVELS:
--   🟢 SAFE     - Read-only analysis, safe for production
--   🟡 MEDIUM   - Safe optimizations, test recommended  
--   🔴 HIGH     - Major changes, backup required, maintenance window needed
-- 
-- PREREQUISITES:
--   - Performance Schema enabled (performance_schema = ON)
--   - Adequate permissions for analysis queries
--   - For implementation: DBA privileges and maintenance window
-- 
-- TIME ESTIMATE: 45-60 minutes for complete analysis and recommendations
-- 
-- ==========================================================================================================

SET SESSION sql_mode = 'TRADITIONAL,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION';
SET SESSION autocommit = 1;

SELECT '============================================================================================================' as '';
SELECT 'MySQL Performance Tuning - Step-by-Step Analysis' as '';
SELECT '============================================================================================================' as '';
SELECT CONCAT('Database: ', DATABASE()) as '';
SELECT CONCAT('User: ', USER()) as '';
SELECT CONCAT('Date: ', NOW()) as '';
SELECT '============================================================================================================' as '';
SELECT '' as '';

-- ==========================================================================================================
-- PHASE 1: INITIAL ANALYSIS (🟢 SAFE - READ-ONLY)
-- ==========================================================================================================

SELECT '' as '';
SELECT '=========================================' as '';
SELECT '🟢 PHASE 1: INITIAL ANALYSIS' as '';
SELECT '=========================================' as '';
SELECT '' as '';

-- ---------------------------------------------------------------------------------------------------------
-- STEP 1: DATABASE HEALTH OVERVIEW
-- ---------------------------------------------------------------------------------------------------------

SELECT '>>> STEP 1: Database Health Overview' as '';
SELECT '------------------------------------' as '';
SELECT 'Analyzing: Server info, database size, connections, basic performance metrics' as '';
SELECT '' as '';

-- Server and Database Information
SELECT 
    'Server Information' as metric_category,
    'MySQL Version' as metric_name,
    VERSION() as metric_value,
    'Info' as recommendation
UNION ALL
SELECT 
    'Server Information',
    'Server Uptime',
    CONCAT(
        ROUND(VARIABLE_VALUE / 86400, 0), ' days, ',
        ROUND((VARIABLE_VALUE % 86400) / 3600, 0), ' hours'
    ),
    CASE 
        WHEN VARIABLE_VALUE < 86400 THEN 'Recent restart - metrics may be incomplete'
        ELSE 'Good data collection period'
    END
FROM performance_schema.global_status 
WHERE VARIABLE_NAME = 'Uptime'
UNION ALL
SELECT 
    'Database Size',
    'Current Database Size',
    CONCAT(
        ROUND(SUM(DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024 / 1024, 2), ' GB'
    ),
    CASE 
        WHEN SUM(DATA_LENGTH + INDEX_LENGTH) > 107374182400 THEN 'Large database (>100GB) - monitor performance closely'
        WHEN SUM(DATA_LENGTH + INDEX_LENGTH) > 10737418240 THEN 'Medium database (>10GB) - consider partitioning large tables'
        ELSE 'Small database (<10GB) - basic optimization sufficient'
    END
FROM information_schema.TABLES 
WHERE TABLE_SCHEMA = DATABASE()
UNION ALL
SELECT 
    'Connections',
    'Current Active Connections',
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Threads_connected'),
    CASE 
        WHEN (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Threads_connected') > 50 THEN 'High connection count - investigate connection pooling'
        WHEN (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Threads_connected') > 20 THEN 'Moderate connection usage - monitor trends'
        ELSE 'Low connection usage - normal'
    END
UNION ALL
SELECT 
    'Cache Performance',
    'InnoDB Buffer Pool Hit Ratio',
    CONCAT(
        ROUND(
            100 * (1 - (
                (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads') /
                (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests')
            )), 2
        ), '%'
    ),
    CASE 
        WHEN (
            100 * (1 - (
                (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads') /
                (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests')
            ))
        ) < 90 THEN 'Low cache hit ratio - increase innodb_buffer_pool_size'
        WHEN (
            100 * (1 - (
                (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads') /
                (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests')
            ))
        ) < 95 THEN 'Moderate cache performance - monitor and optimize'
        ELSE 'Good cache performance'
    END;

SELECT '' as '';
SELECT '>>> STEP 1 ANALYSIS COMPLETE' as '';
SELECT 'Review the metrics above:' as '';
SELECT '- Database size indicates optimization complexity' as '';
SELECT '- Connection count affects resource planning' as '';
SELECT '- Cache hit ratio <95% suggests memory tuning needed' as '';
SELECT '' as '';

-- ---------------------------------------------------------------------------------------------------------
-- STEP 2: QUERY PERFORMANCE ANALYSIS
-- ---------------------------------------------------------------------------------------------------------

SELECT '>>> STEP 2: Query Performance Analysis' as '';
SELECT '-------------------------------------' as '';
SELECT 'Analyzing: Top slow queries, execution patterns, resource consumption' as '';
SELECT '' as '';

-- Check if Performance Schema is enabled
SELECT 
    CASE 
        WHEN @@performance_schema = 1 THEN 'Performance Schema is enabled - proceeding with analysis'
        ELSE 'WARNING: Performance Schema is disabled! Enable with performance_schema = ON in my.cnf'
    END as status;

-- Top 10 Slowest Queries by Total Time
SELECT 'Top 10 Slowest Queries by Total Execution Time:' as '';
SELECT 
    ROW_NUMBER() OVER (ORDER BY SUM_TIMER_WAIT DESC) as `rank`,
    LEFT(DIGEST_TEXT, 80) as query_preview,
    COUNT_STAR as calls,
    ROUND(SUM_TIMER_WAIT / 1000000000000, 2) as total_time_sec,
    ROUND(AVG_TIMER_WAIT / 1000000000000, 2) as avg_time_sec,
    ROUND(MAX_TIMER_WAIT / 1000000000000, 2) as max_time_sec,
    SUM_ROWS_EXAMINED as total_rows_examined,
    CASE 
        WHEN AVG_TIMER_WAIT / 1000000000000 > 1 THEN '🔴 SLOW'
        WHEN AVG_TIMER_WAIT / 1000000000000 > 0.1 THEN '🟡 MODERATE'  
        ELSE '🟢 FAST'
    END as performance_status
FROM performance_schema.events_statements_summary_by_digest 
WHERE DIGEST_TEXT IS NOT NULL
    AND DIGEST_TEXT NOT LIKE '%performance_schema%'
    AND DIGEST_TEXT NOT LIKE '%COMMIT%'
    AND DIGEST_TEXT NOT LIKE '%BEGIN%'
    AND DIGEST_TEXT NOT LIKE '%ANALYZE%'
    AND DIGEST_TEXT NOT LIKE '%CREATE INDEX%'
    AND SUM_TIMER_WAIT > 0
ORDER BY SUM_TIMER_WAIT DESC 
LIMIT 10;

SELECT '' as '';

-- Top 10 Most Called Queries
SELECT 'Top 10 Most Frequently Called Queries:' as '';
SELECT 
    ROW_NUMBER() OVER (ORDER BY COUNT_STAR DESC) as `rank`,
    LEFT(DIGEST_TEXT, 80) as query_preview,
    COUNT_STAR as calls,
    ROUND(SUM_TIMER_WAIT / 1000000000000, 2) as total_time_sec,
    ROUND(AVG_TIMER_WAIT / 1000000000000, 2) as avg_time_sec,
    CASE 
        WHEN COUNT_STAR > 10000 THEN '🔴 VERY HIGH'
        WHEN COUNT_STAR > 1000 THEN '🟡 HIGH'
        ELSE '🟢 NORMAL'
    END as frequency_status
FROM performance_schema.events_statements_summary_by_digest 
WHERE DIGEST_TEXT IS NOT NULL
    AND DIGEST_TEXT NOT LIKE '%performance_schema%'
    AND DIGEST_TEXT NOT LIKE '%COMMIT%'
    AND DIGEST_TEXT NOT LIKE '%commit%'
    AND DIGEST_TEXT NOT LIKE '%BEGIN%'
    AND DIGEST_TEXT NOT LIKE '%begin%'
ORDER BY COUNT_STAR DESC
LIMIT 10;

SELECT '' as '';

SELECT '>>> STEP 2 ANALYSIS COMPLETE' as '';
SELECT 'Review the query analysis:' as '';
SELECT '- 🔴 SLOW queries (>1sec) need immediate optimization' as '';
SELECT '- 🟡 MODERATE queries (>0.1sec) should be investigated' as '';
SELECT '- High frequency queries should be optimized even if individually fast' as '';
SELECT '' as '';

-- ---------------------------------------------------------------------------------------------------------
-- STEP 3: INDEX USAGE ANALYSIS
-- ---------------------------------------------------------------------------------------------------------

SELECT '>>> STEP 3: Index Usage Analysis' as '';
SELECT '--------------------------------' as '';
SELECT 'Analyzing: Index efficiency, unused indexes, table scan patterns' as '';
SELECT '' as '';

-- Index Usage Statistics
SELECT 'Index Usage Statistics (Top 15 by usage):' as '';
SELECT 
    TABLE_SCHEMA as schema_name,
    TABLE_NAME as table_name,
    INDEX_NAME as index_name,
    CARDINALITY as estimated_cardinality,
    ROUND(
        (SELECT DATA_LENGTH + INDEX_LENGTH 
         FROM information_schema.TABLES t 
         WHERE t.TABLE_SCHEMA = s.TABLE_SCHEMA 
           AND t.TABLE_NAME = s.TABLE_NAME) / 1024 / 1024, 2
    ) as table_size_mb,
    CASE 
        WHEN CARDINALITY IS NULL OR CARDINALITY = 0 THEN '🔴 NO CARDINALITY'
        WHEN CARDINALITY < 10 THEN '🟡 LOW SELECTIVITY'
        WHEN CARDINALITY < 100 THEN '🟢 MODERATE SELECTIVITY'
        ELSE '🟢 HIGH SELECTIVITY'
    END as selectivity_status
FROM information_schema.STATISTICS s
WHERE TABLE_SCHEMA = DATABASE()
    AND INDEX_NAME != 'PRIMARY'
ORDER BY CARDINALITY DESC, TABLE_NAME
LIMIT 15;

SELECT '' as '';

-- Tables with High Full Table Scan Activity
SELECT 'Tables with High Full Table Scan Activity (May Need Indexes):' as '';
SELECT 
    OBJECT_SCHEMA as schema_name,
    OBJECT_NAME as table_name,
    COUNT_READ as total_reads,
    SUM_TIMER_WAIT / 1000000000000 as total_read_time_sec,
    ROUND(
        (SELECT DATA_LENGTH + INDEX_LENGTH 
         FROM information_schema.TABLES t 
         WHERE t.TABLE_SCHEMA = tio.OBJECT_SCHEMA 
           AND t.TABLE_NAME = tio.OBJECT_NAME) / 1024 / 1024, 2
    ) as table_size_mb,
    CASE 
        WHEN COUNT_READ > 10000 THEN '🔴 HIGH TABLE SCANS'
        WHEN COUNT_READ > 1000 THEN '🟡 MODERATE TABLE SCANS'
        ELSE '🟢 LOW TABLE SCANS'
    END as scan_status
FROM performance_schema.table_io_waits_summary_by_table tio
WHERE OBJECT_SCHEMA = DATABASE()
    AND COUNT_READ > 0
ORDER BY COUNT_READ DESC, SUM_TIMER_WAIT DESC
LIMIT 10;

SELECT '' as '';
SELECT '>>> STEP 3 ANALYSIS COMPLETE' as '';
SELECT 'Review index analysis:' as '';
SELECT '- Low cardinality indexes may not be selective enough' as '';
SELECT '- Tables with high scan counts may need additional indexes' as '';
SELECT '- Large tables with frequent scans are priority for indexing' as '';
SELECT '' as '';

-- ---------------------------------------------------------------------------------------------------------
-- STEP 4: TABLE STATISTICS AND MAINTENANCE
-- ---------------------------------------------------------------------------------------------------------

SELECT '>>> STEP 4: Table Statistics and Maintenance Analysis' as '';
SELECT '----------------------------------------------------' as '';
SELECT 'Analyzing: Table size, engine type, fragmentation' as '';
SELECT '' as '';

-- Table Size and Engine Information
SELECT 'Table Size and Engine Information:' as '';
SELECT 
    TABLE_SCHEMA as schema_name,
    TABLE_NAME as table_name,
    ENGINE as storage_engine,
    ROUND((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024, 2) as total_size_mb,
    ROUND(DATA_LENGTH / 1024 / 1024, 2) as data_size_mb,
    ROUND(INDEX_LENGTH / 1024 / 1024, 2) as index_size_mb,
    TABLE_ROWS as estimated_rows,
    ROUND(DATA_FREE / 1024 / 1024, 2) as data_free_mb,
    UPDATE_TIME as last_update,
    CASE 
        WHEN DATA_FREE / (DATA_LENGTH + INDEX_LENGTH) > 0.1 THEN '🟡 HIGH FRAGMENTATION'
        WHEN DATA_FREE / (DATA_LENGTH + INDEX_LENGTH) > 0.05 THEN '🟡 MODERATE FRAGMENTATION'
        ELSE '🟢 LOW FRAGMENTATION'
    END as fragmentation_status,
    CASE 
        WHEN ENGINE != 'InnoDB' THEN '🔴 NON-INNODB ENGINE'
        ELSE '🟢 INNODB'
    END as engine_status
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_TYPE = 'BASE TABLE'
ORDER BY (DATA_LENGTH + INDEX_LENGTH) DESC
LIMIT 15;

SELECT '' as '';

-- InnoDB Status Information
SELECT 'InnoDB Buffer Pool Status:' as '';
SELECT 
    'Buffer Pool Size' as metric,
    CONCAT(
        ROUND(VARIABLE_VALUE / 1024 / 1024 / 1024, 2), ' GB'
    ) as value,
    'Current buffer pool allocation' as description
FROM performance_schema.global_status 
WHERE VARIABLE_NAME = 'Innodb_buffer_pool_size'
UNION ALL
SELECT 
    'Buffer Pool Utilization',
    CONCAT(
        ROUND(
            100 * (
                (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_pages_data') /
                (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_pages_total')
            ), 2
        ), '%'
    ),
    'Percentage of buffer pool in use'
UNION ALL
SELECT 
    'Dirty Pages Ratio',
    CONCAT(
        ROUND(
            100 * (
                (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_pages_dirty') /
                (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_pages_total')
            ), 2
        ), '%'
    ),
    'Percentage of dirty pages in buffer pool';

SELECT '' as '';
SELECT '>>> STEP 4 ANALYSIS COMPLETE' as '';
SELECT 'Review table maintenance:' as '';
SELECT '- High fragmentation indicates need for OPTIMIZE TABLE' as '';
SELECT '- Non-InnoDB engines should be migrated to InnoDB' as '';
SELECT '- Monitor buffer pool utilization and dirty page ratio' as '';
SELECT '' as '';

-- ==========================================================================================================
-- PHASE 2: PROBLEM IDENTIFICATION (🟢 SAFE - ANALYSIS ONLY)
-- ==========================================================================================================

SELECT '' as '';
SELECT '=========================================' as '';
SELECT '🟢 PHASE 2: PROBLEM IDENTIFICATION' as '';
SELECT '=========================================' as '';
SELECT '' as '';

-- ---------------------------------------------------------------------------------------------------------
-- STEP 5: PERFORMANCE BOTTLENECK DETECTION
-- ---------------------------------------------------------------------------------------------------------

SELECT '>>> STEP 5: Performance Bottleneck Detection' as '';
SELECT '-------------------------------------------' as '';
SELECT 'Analyzing: Critical performance issues and resource bottlenecks' as '';
SELECT '' as '';

-- Critical Performance Issues Summary
SELECT 'CRITICAL PERFORMANCE ISSUES DETECTED:' as '';

-- Create a temporary table for performance issues
DROP TEMPORARY TABLE IF EXISTS performance_issues;
CREATE TEMPORARY TABLE performance_issues (
    issue_type VARCHAR(100),
    issue_count INT,
    priority VARCHAR(20),
    description TEXT,
    recommendation TEXT
);

-- Insert slow queries issue
INSERT INTO performance_issues
SELECT 
    'Slow Queries' as issue_type,
    COUNT(*) as issue_count,
    '🔴 HIGH' as priority,
    'Queries averaging >1sec execution time' as description,
    'Optimize queries, add indexes, rewrite inefficient statements' as recommendation
FROM performance_schema.events_statements_summary_by_digest 
WHERE AVG_TIMER_WAIT / 1000000000000 > 1;

-- Insert fragmented tables issue
INSERT INTO performance_issues
SELECT 
    'Fragmented Tables',
    COUNT(*),
    '🟡 MEDIUM',
    'Tables with >10% fragmentation',
    'Run OPTIMIZE TABLE on fragmented tables during maintenance window'
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
    AND DATA_FREE / (DATA_LENGTH + INDEX_LENGTH) > 0.1;

-- Insert non-InnoDB tables issue
INSERT INTO performance_issues
SELECT 
    'Non-InnoDB Tables',
    COUNT(*),
    '🟡 MEDIUM',
    'Tables using non-InnoDB storage engines',
    'Migrate tables to InnoDB for better performance and ACID compliance'
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
    AND ENGINE != 'InnoDB'
    AND TABLE_TYPE = 'BASE TABLE';

-- Insert buffer pool issues
INSERT INTO performance_issues
SELECT 
    'Low Buffer Pool Hit Ratio',
    1,
    '🟡 MEDIUM',
    'InnoDB buffer pool hit ratio below 95%',
    'Increase innodb_buffer_pool_size parameter'
WHERE (
    100 * (1 - (
        (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads') /
        (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests')
    ))
) < 95;

SELECT * FROM performance_issues WHERE issue_count > 0
ORDER BY 
    CASE priority 
        WHEN '🔴 HIGH' THEN 1 
        WHEN '🟡 MEDIUM' THEN 2 
        ELSE 3 
    END;

SELECT '' as '';
SELECT '>>> STEP 5 ANALYSIS COMPLETE' as '';
SELECT 'Critical issues identified above should be addressed first' as '';
SELECT 'Focus on 🔴 HIGH priority issues for maximum impact' as '';
SELECT '' as '';

-- ---------------------------------------------------------------------------------------------------------
-- STEP 6: CONFIGURATION ANALYSIS
-- ---------------------------------------------------------------------------------------------------------

SELECT '>>> STEP 6: Configuration Analysis' as '';
SELECT '---------------------------------' as '';
SELECT 'Analyzing: Server configuration and parameter optimization opportunities' as '';
SELECT '' as '';

-- Key Configuration Parameters Analysis
SELECT 'Current Configuration vs Recommendations:' as '';
SELECT
    VARIABLE_NAME as parameter,
    VARIABLE_VALUE as current_value,
    CASE
        -- Memory parameters
        WHEN VARIABLE_NAME = 'innodb_buffer_pool_size' THEN
            CASE
                WHEN VARIABLE_VALUE < 134217728 THEN '🔴 Consider increasing to 128MB+ (70-80% of RAM)'
                ELSE '🟢 Adequate'
            END
        WHEN VARIABLE_NAME = 'query_cache_size' THEN
            CASE
                WHEN VARIABLE_VALUE = 0 THEN '🟡 Query cache disabled - consider enabling for read-heavy workloads'
                ELSE '🟢 Enabled'
            END
        WHEN VARIABLE_NAME = 'sort_buffer_size' THEN
            CASE
                WHEN VARIABLE_VALUE < 262144 THEN '🟡 Consider increasing to 256KB+ for complex sorts'
                ELSE '🟢 Adequate'
            END
        WHEN VARIABLE_NAME = 'join_buffer_size' THEN
            CASE
                WHEN VARIABLE_VALUE < 262144 THEN '🟡 Consider increasing to 256KB+ for join operations'
                ELSE '🟢 Adequate'
            END
        -- Connection parameters
        WHEN VARIABLE_NAME = 'max_connections' THEN
            CASE
                WHEN VARIABLE_VALUE > 500 THEN '🟡 High connection limit - consider connection pooling'
                ELSE '🟢 Reasonable'
            END
        -- InnoDB parameters
        WHEN VARIABLE_NAME = 'innodb_log_file_size' THEN
            CASE
                WHEN VARIABLE_VALUE < 50331648 THEN '🟡 Consider increasing to 48MB+ for write-heavy workloads'
                ELSE '🟢 Adequate'
            END
        WHEN VARIABLE_NAME = 'innodb_flush_log_at_trx_commit' THEN
            CASE
                WHEN VARIABLE_VALUE = 1 THEN '🟢 Full ACID compliance (safest)'
                WHEN VARIABLE_VALUE = 2 THEN '🟡 Good balance of performance and durability'
                ELSE '🔴 Potential data loss risk'
            END
        ELSE '🟢 Standard'
    END as recommendation
FROM performance_schema.global_variables
WHERE VARIABLE_NAME IN (
    'innodb_buffer_pool_size',
    'query_cache_size',
    'sort_buffer_size',
    'join_buffer_size',
    'max_connections',
    'innodb_log_file_size',
    'innodb_flush_log_at_trx_commit',
    'innodb_file_per_table'
)
ORDER BY VARIABLE_NAME;

SELECT '' as '';
SELECT '>>> STEP 6 ANALYSIS COMPLETE' as '';
SELECT 'Configuration recommendations above focus on memory and InnoDB optimization' as '';
SELECT '🔴 RED items need immediate attention' as '';
SELECT '🟡 YELLOW items provide moderate performance improvements' as '';
SELECT '' as '';

-- ==========================================================================================================
-- PHASE 3: RECOMMENDATIONS (🟢 SAFE - SUGGESTIONS ONLY)
-- ==========================================================================================================

SELECT '' as '';
SELECT '=========================================' as '';
SELECT '🟢 PHASE 3: RECOMMENDATIONS' as '';
SELECT '=========================================' as '';
SELECT '' as '';

-- ---------------------------------------------------------------------------------------------------------
-- STEP 7: INDEX RECOMMENDATIONS  
-- ---------------------------------------------------------------------------------------------------------

SELECT '>>> STEP 7: Index Recommendations' as '';
SELECT '---------------------------------' as '';
SELECT 'Generating: Specific index creation and optimization recommendations' as '';
SELECT '' as '';

-- Tables that would benefit from indexes based on scan activity
SELECT 'RECOMMENDED INDEX INVESTIGATIONS:' as '';
SELECT '(Based on high table scan activity and size)' as '';
SELECT '' as '';

SELECT 
    CONCAT('-- High Priority: ', OBJECT_NAME, ' (Reads: ', COUNT_READ, ', Size: ', 
           ROUND((SELECT DATA_LENGTH + INDEX_LENGTH FROM information_schema.TABLES t 
                  WHERE t.TABLE_SCHEMA = tio.OBJECT_SCHEMA AND t.TABLE_NAME = tio.OBJECT_NAME) / 1024 / 1024, 2), 'MB)') as recommendation,
    CONCAT('-- Investigate frequent query patterns on this table') as analysis_needed,
    CONCAT('-- Consider: CREATE INDEX idx_', OBJECT_NAME, '_frequently_queried_column ON ', OBJECT_SCHEMA, '.', OBJECT_NAME, ' (frequently_queried_column);') as suggested_approach,
    CONCAT('-- Impact: HIGH - Will significantly reduce query times') as impact
FROM performance_schema.table_io_waits_summary_by_table tio
WHERE OBJECT_SCHEMA = DATABASE()
    AND COUNT_READ > 1000
    AND (SELECT DATA_LENGTH + INDEX_LENGTH FROM information_schema.TABLES t 
         WHERE t.TABLE_SCHEMA = tio.OBJECT_SCHEMA AND t.TABLE_NAME = tio.OBJECT_NAME) > 10485760 -- >10MB
ORDER BY COUNT_READ DESC, 
         (SELECT DATA_LENGTH + INDEX_LENGTH FROM information_schema.TABLES t 
          WHERE t.TABLE_SCHEMA = tio.OBJECT_SCHEMA AND t.TABLE_NAME = tio.OBJECT_NAME) DESC
LIMIT 5;

SELECT '' as '';

-- Index optimization recommendations
SELECT 'INDEX OPTIMIZATION RECOMMENDATIONS:' as '';
SELECT 'Check for duplicate or redundant indexes:' as '';
SELECT '' as '';

SELECT 
    CONCAT('-- Review indexes on table: ', TABLE_NAME) as table_analysis,
    CONCAT('-- Current indexes: ', GROUP_CONCAT(DISTINCT INDEX_NAME ORDER BY INDEX_NAME)) as current_indexes,
    CONCAT('-- Check for redundant or duplicate indexes') as recommendation
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = DATABASE()
    AND INDEX_NAME != 'PRIMARY'
GROUP BY TABLE_NAME
HAVING COUNT(DISTINCT INDEX_NAME) > 5
ORDER BY COUNT(DISTINCT INDEX_NAME) DESC
LIMIT 5;

SELECT '' as '';
SELECT '>>> STEP 7 RECOMMENDATIONS COMPLETE' as '';
SELECT 'Index recommendations above are based on usage patterns' as '';
SELECT 'CREATE indexes during low-traffic periods' as '';
SELECT 'Always analyze query patterns before creating indexes' as '';
SELECT '' as '';

-- ---------------------------------------------------------------------------------------------------------
-- STEP 8: QUERY OPTIMIZATION RECOMMENDATIONS
-- ---------------------------------------------------------------------------------------------------------

SELECT '>>> STEP 8: Query Optimization Recommendations' as '';
SELECT '---------------------------------------------' as '';
SELECT 'Analyzing: Specific query optimization opportunities' as '';
SELECT '' as '';

-- Top Queries Needing Optimization
SELECT 'TOP QUERIES REQUIRING OPTIMIZATION:' as '';
SELECT 
    ROW_NUMBER() OVER (ORDER BY SUM_TIMER_WAIT DESC) as priority,
    LEFT(DIGEST_TEXT, 100) as query_preview,
    COUNT_STAR as calls,
    ROUND(AVG_TIMER_WAIT / 1000000000000, 2) as avg_time_sec,
    ROUND(SUM_TIMER_WAIT / 1000000000000, 2) as total_time_sec,
    CASE 
        WHEN DIGEST_TEXT LIKE '%SELECT%FROM%WHERE%' AND DIGEST_TEXT LIKE '%ORDER BY%' 
        THEN 'Add index on ORDER BY columns'
        WHEN DIGEST_TEXT LIKE '%SELECT%FROM%WHERE%' AND DIGEST_TEXT LIKE '%GROUP BY%'
        THEN 'Add index on GROUP BY columns' 
        WHEN DIGEST_TEXT LIKE '%SELECT%FROM%WHERE%' AND DIGEST_TEXT NOT LIKE '%LIMIT%'
        THEN 'Add LIMIT clause if appropriate + index on WHERE columns'
        WHEN DIGEST_TEXT LIKE '%UPDATE%WHERE%' OR DIGEST_TEXT LIKE '%DELETE%WHERE%'
        THEN 'Add index on WHERE clause columns'
        ELSE 'Review execution plan with EXPLAIN'
    END as optimization_suggestion
FROM performance_schema.events_statements_summary_by_digest
WHERE AVG_TIMER_WAIT / 1000000000000 > 0.1
    AND DIGEST_TEXT NOT LIKE '%performance_schema%'
    AND COUNT_STAR > 10
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 10;

SELECT '' as '';

-- Query Pattern Analysis
SELECT 'QUERY PATTERN OPTIMIZATION OPPORTUNITIES:' as '';

-- Create temporary table for query patterns
DROP TEMPORARY TABLE IF EXISTS query_patterns;
CREATE TEMPORARY TABLE query_patterns (
    pattern_type VARCHAR(100),
    query_count INT,
    avg_execution_time DECIMAL(10,2),
    total_time_spent DECIMAL(10,2),
    optimization_strategy TEXT
);

INSERT INTO query_patterns
SELECT 
    CASE 
        WHEN DIGEST_TEXT LIKE '%SELECT%COUNT(*)%' THEN 'COUNT(*) Queries'
        WHEN DIGEST_TEXT LIKE '%ORDER BY%LIMIT%' THEN 'Paginated Queries'
        WHEN DIGEST_TEXT LIKE '%SELECT%FROM%JOIN%JOIN%' THEN 'Multi-Join Queries'
        WHEN DIGEST_TEXT LIKE '%WHERE%LIKE%' THEN 'LIKE Pattern Queries'
        WHEN DIGEST_TEXT LIKE '%WHERE%IN (%' THEN 'IN Clause Queries'
        ELSE 'Other'
    END as pattern_type,
    COUNT(*) as query_count,
    ROUND(AVG(AVG_TIMER_WAIT / 1000000000000), 2) as avg_execution_time,
    ROUND(SUM(SUM_TIMER_WAIT / 1000000000000), 2) as total_time_spent,
    CASE 
        WHEN DIGEST_TEXT LIKE '%SELECT%COUNT(*)%' THEN 'Consider summary tables or approximations'
        WHEN DIGEST_TEXT LIKE '%ORDER BY%LIMIT%' THEN 'Ensure indexes on ORDER BY columns'  
        WHEN DIGEST_TEXT LIKE '%SELECT%FROM%JOIN%JOIN%' THEN 'Review join order and add indexes'
        WHEN DIGEST_TEXT LIKE '%WHERE%LIKE%' THEN 'Consider FULLTEXT indexes for text search'
        WHEN DIGEST_TEXT LIKE '%WHERE%IN (%' THEN 'Consider JOINs instead of large IN clauses'
        ELSE 'Review individual queries'
    END as optimization_strategy
FROM performance_schema.events_statements_summary_by_digest
WHERE COUNT_STAR > 5
GROUP BY pattern_type, optimization_strategy
HAVING pattern_type != 'Other';

SELECT * FROM query_patterns
ORDER BY total_time_spent DESC;

SELECT '' as '';
SELECT '>>> STEP 8 RECOMMENDATIONS COMPLETE' as '';
SELECT 'Query optimization strategies above target common performance patterns' as '';
SELECT 'Use EXPLAIN to verify optimization effectiveness' as '';
SELECT '' as '';

-- ==========================================================================================================
-- PHASE 4: IMPLEMENTATION SCRIPTS (🟡🔴 CAUTION - MAKES CHANGES)
-- ==========================================================================================================

SELECT '' as '';
SELECT '=========================================' as '';
SELECT '⚠️  PHASE 4: IMPLEMENTATION SCRIPTS' as '';
SELECT '=========================================' as '';
SELECT '' as '';
SELECT '🚨 WARNING: The following steps make actual changes to your database!' as '';
SELECT '🚨 ALWAYS test in development environment first' as '';
SELECT '🚨 Take backups before running production changes' as '';
SELECT '🚨 Run during maintenance windows for major changes' as '';
SELECT '' as '';

-- ---------------------------------------------------------------------------------------------------------
-- STEP 9: SAFE OPTIMIZATIONS (🟡 MEDIUM RISK)
-- ---------------------------------------------------------------------------------------------------------

SELECT '>>> STEP 9: Safe Optimizations (🟡 MEDIUM RISK)' as '';
SELECT '----------------------------------------------' as '';
SELECT 'These changes are relatively safe but should be tested first' as '';
SELECT '' as '';

-- Update table statistics (safe operation)
SELECT '-- SAFE OPERATION: Update Table Statistics' as '';
SELECT '-- This improves query planning accuracy' as '';
SELECT '' as '';

SELECT 'Updating statistics for tables...' as '';

-- Generate ANALYZE TABLE statements for tables in current database
SELECT CONCAT('ANALYZE TABLE ', TABLE_SCHEMA, '.', TABLE_NAME, ';') as analyze_statements
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_TYPE = 'BASE TABLE'
    AND ENGINE = 'InnoDB'
ORDER BY (DATA_LENGTH + INDEX_LENGTH) DESC
LIMIT 10;

SELECT '' as '';
SELECT '>>> STEP 9 COMPLETE' as '';
SELECT 'Statistics update statements generated above' as '';
SELECT 'Execute these during maintenance window for improved query planning' as '';
SELECT '' as '';

-- ---------------------------------------------------------------------------------------------------------
-- STEP 10: INDEX IMPLEMENTATION (🟡 MEDIUM RISK)
-- ---------------------------------------------------------------------------------------------------------

SELECT '>>> STEP 10: Index Implementation (🟡 MEDIUM RISK)' as '';
SELECT '------------------------------------------------' as '';
SELECT 'CAUTION: Index creation can be resource intensive' as '';
SELECT 'Run during low-traffic periods' as '';
SELECT '' as '';

SELECT '-- INDEX OPTIMIZATION SCRIPTS (Review before executing):' as '';
SELECT '-- The following are SUGGESTIONS based on analysis' as '';
SELECT '-- Customize column names based on your actual schema and query patterns' as '';
SELECT '' as '';

-- Generate sample index creation suggestions
SELECT 
    CONCAT('-- High impact potential for table: ', OBJECT_NAME) as comment,
    CONCAT('-- CREATE INDEX idx_', OBJECT_NAME, '_your_column ON ', OBJECT_SCHEMA, '.', OBJECT_NAME, ' (your_frequently_queried_column);') as suggested_index,
    CONCAT('-- Table activity: ', COUNT_READ, ' reads, Size: ', 
           ROUND((SELECT DATA_LENGTH + INDEX_LENGTH FROM information_schema.TABLES t 
                  WHERE t.TABLE_SCHEMA = tio.OBJECT_SCHEMA AND t.TABLE_NAME = tio.OBJECT_NAME) / 1024 / 1024, 2), 'MB') as impact_info
FROM performance_schema.table_io_waits_summary_by_table tio
WHERE OBJECT_SCHEMA = DATABASE()
    AND COUNT_READ > 1000
    AND (SELECT DATA_LENGTH + INDEX_LENGTH FROM information_schema.TABLES t 
         WHERE t.TABLE_SCHEMA = tio.OBJECT_SCHEMA AND t.TABLE_NAME = tio.OBJECT_NAME) > 10485760 -- >10MB
ORDER BY COUNT_READ DESC
LIMIT 5;

SELECT '' as '';
SELECT '-- TABLE OPTIMIZATION (For fragmented tables):' as '';

-- Generate OPTIMIZE TABLE statements for fragmented tables
SELECT 
    CONCAT('-- OPTIMIZE TABLE ', TABLE_SCHEMA, '.', TABLE_NAME, ';') as optimize_statements,
    CONCAT('-- Fragmentation: ', ROUND(DATA_FREE / (DATA_LENGTH + INDEX_LENGTH) * 100, 2), '%') as fragmentation_info,
    CONCAT('-- Size: ', ROUND((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024, 2), 'MB') as table_size
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_TYPE = 'BASE TABLE'
    AND DATA_FREE / (DATA_LENGTH + INDEX_LENGTH) > 0.1
ORDER BY DATA_FREE DESC
LIMIT 5;

SELECT '' as '';
SELECT '>>> STEP 10 RECOMMENDATIONS GENERATED' as '';
SELECT 'Review the suggested INDEX and OPTIMIZE statements above' as '';
SELECT 'Customize column names based on your query patterns' as '';
SELECT 'Monitor index effectiveness after creation' as '';
SELECT '' as '';

-- ---------------------------------------------------------------------------------------------------------
-- STEP 11: VERIFICATION AND MONITORING
-- ---------------------------------------------------------------------------------------------------------

SELECT '>>> STEP 11: Verification and Monitoring Setup' as '';
SELECT '---------------------------------------------' as '';
SELECT 'Setting up ongoing performance monitoring' as '';
SELECT '' as '';

-- Create a performance monitoring view (if permissions allow)
SELECT 'Creating performance monitoring view...' as '';

-- Since we can't create views in this context, provide the SQL
SELECT '-- CREATE VIEW performance_summary AS' as view_creation;
SELECT 'SELECT' as '';
SELECT '    "Query Performance" as metric_category,' as '';
SELECT '    COUNT(*) as slow_queries,' as '';
SELECT '    (SELECT COUNT(*) FROM performance_schema.events_statements_summary_by_digest WHERE COUNT_STAR > 1000) as frequent_queries,' as '';
SELECT '    COUNT(*) as total_tracked_queries,' as '';
SELECT '    ROUND(AVG(AVG_TIMER_WAIT / 1000000000000), 2) as avg_query_time_sec' as '';
SELECT 'FROM performance_schema.events_statements_summary_by_digest' as '';
SELECT 'WHERE AVG_TIMER_WAIT / 1000000000000 > 1' as '';
SELECT 'UNION ALL' as '';
SELECT 'SELECT' as '';
SELECT '    "Buffer Pool Performance",' as '';
SELECT '    NULL,' as '';
SELECT '    NULL,' as '';
SELECT '    NULL,' as '';
SELECT '    ROUND(100 * (1 - (' as '';
SELECT '        (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = "Innodb_buffer_pool_reads") /' as '';
SELECT '        (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = "Innodb_buffer_pool_read_requests")' as '';
SELECT '    )), 2) as hit_ratio_percent;' as '';

SELECT '' as '';

-- Final Performance Score Calculation
SELECT '>>> FINAL PERFORMANCE ASSESSMENT' as '';
SELECT '===============================' as '';

-- Create a simplified performance score
SELECT 
    'MYSQL PERFORMANCE ASSESSMENT' as assessment,
    CASE 
        WHEN (
            -- Buffer pool hit ratio score
            (SELECT 100 * (1 - (
                (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads') /
                (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests')
            ))) > 95
            AND 
            -- Low slow query ratio
            (SELECT COUNT(*) FROM performance_schema.events_statements_summary_by_digest 
             WHERE AVG_TIMER_WAIT / 1000000000000 > 1) < 5
        ) THEN '🟢 GOOD PERFORMANCE'
        WHEN (
            (SELECT 100 * (1 - (
                (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads') /
                (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests')
            ))) > 90
        ) THEN '🟡 MODERATE PERFORMANCE - OPTIMIZATION RECOMMENDED'
        ELSE '🔴 POOR PERFORMANCE - IMMEDIATE ACTION REQUIRED'
    END as grade,
    CONCAT(
        'Buffer Pool Hit Ratio: ',
        ROUND(100 * (1 - (
            (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads') /
            (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests')
        )), 2),
        '%'
    ) as key_metrics;

SELECT '' as '';
SELECT '=========================================' as '';
SELECT '📊 PERFORMANCE TUNING ANALYSIS COMPLETE' as '';
SELECT '=========================================' as '';
SELECT '' as '';
SELECT '📋 SUMMARY OF COMPLETED STEPS:' as '';
SELECT '✅ Step 1: Database Health Overview' as '';
SELECT '✅ Step 2: Query Performance Analysis' as '';
SELECT '✅ Step 3: Index Usage Analysis' as '';
SELECT '✅ Step 4: Table Statistics Analysis' as '';
SELECT '✅ Step 5: Performance Bottleneck Detection' as '';
SELECT '✅ Step 6: Configuration Analysis' as '';
SELECT '✅ Step 7: Index Recommendations' as '';
SELECT '✅ Step 8: Query Optimization Recommendations' as '';
SELECT '✅ Step 9: Safe Optimizations (Statistics Update)' as '';
SELECT '✅ Step 10: Index Implementation Suggestions' as '';
SELECT '✅ Step 11: Verification & Monitoring Setup' as '';
SELECT '' as '';
SELECT '📈 NEXT STEPS:' as '';
SELECT '1. Review all 🔴 HIGH priority issues identified' as '';
SELECT '2. Implement suggested optimizations during maintenance windows' as '';
SELECT '3. Monitor performance using Performance Schema queries' as '';
SELECT '4. Re-run this analysis monthly for ongoing optimization' as '';
SELECT '' as '';
SELECT '🔗 RELATED DOCUMENTATION:' as '';
SELECT '- Query Templates: ../mysql_performance_query_templates.md' as '';
SELECT '- EXPLAIN Guide: ../mysql_explain_analyze_guide.md' as '';
SELECT '- Setup Guide: ../mysql_monitoring_complete_setup_guide.md' as '';
SELECT '' as '';
SELECT '⚠️  IMPORTANT REMINDERS:' as '';
SELECT '- Always test changes in development first' as '';
SELECT '- Take backups before implementing major changes' as '';
SELECT '- Monitor performance after changes' as '';
SELECT '- Use maintenance windows for intensive operations' as '';
SELECT '' as '';
SELECT 'Performance analysis completed successfully! 🎉' as '';
SELECT '============================================================================================================' as '';

-- Clean up temporary tables
DROP TEMPORARY TABLE IF EXISTS performance_issues;
DROP TEMPORARY TABLE IF EXISTS query_patterns;
