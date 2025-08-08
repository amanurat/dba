# 🧹 PostgreSQL Comprehensive VACUUM Management Guide

> **Professional DBA Reference**: Enterprise-grade vacuum management, bloat monitoring, and maintenance automation for PostgreSQL production environments

---

## 📋 **Executive Summary**

This guide provides comprehensive vacuum management strategies for PostgreSQL databases, covering:
- **Proactive bloat monitoring** and prevention
- **Automated vacuum scheduling** and optimization
- **Performance impact analysis** of vacuum operations
- **Emergency bloat remediation** procedures
- **Azure-specific considerations** and monitoring integration

---

## 🎯 **VACUUM Management Framework**

### **Critical Management Areas**

| **Category** | **Focus Area** | **Business Impact** | **Monitoring Frequency** |
|--------------|----------------|-------------------|-------------------------|
| 🔍 **Bloat Detection** | Table and index bloat percentage | Storage costs, query performance | Daily |
| ⚡ **Autovacuum Tuning** | Threshold optimization | Background maintenance efficiency | Weekly |
| 📊 **Performance Impact** | Vacuum operation duration and I/O | Application performance during maintenance | Real-time |
| 🚨 **Emergency Situations** | Critical bloat levels (>50%) | System stability, query timeouts | Immediate |
| 📈 **Capacity Planning** | Growth trends and space reclamation | Infrastructure scaling decisions | Monthly |
| 🔧 **Maintenance Windows** | Scheduled VACUUM FULL operations | Planned downtime optimization | As needed |

---

## 🔍 **Bloat Detection and Analysis**

### **1. Comprehensive Bloat Assessment**
```sql
-- Advanced table bloat analysis with actionable insights
WITH table_stats AS (
    SELECT 
        schemaname,
        tablename,
        n_live_tup,
        n_dead_tup,
        n_tup_ins,
        n_tup_upd,
        n_tup_del,
        last_vacuum,
        last_autovacuum,
        last_analyze,
        last_autoanalyze,
        vacuum_count,
        autovacuum_count
    FROM pg_stat_user_tables
),
table_sizes AS (
    SELECT 
        schemaname,
        tablename,
        pg_total_relation_size(schemaname||'.'||tablename) AS total_size_bytes,
        pg_relation_size(schemaname||'.'||tablename) AS table_size_bytes,
        pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename) AS index_size_bytes
    FROM pg_tables
    WHERE schemaname NOT IN ('information_schema', 'pg_catalog')
),
bloat_estimates AS (
    SELECT 
        ts.schemaname,
        ts.tablename,
        ts.n_live_tup,
        ts.n_dead_tup,
        CASE 
            WHEN ts.n_live_tup + ts.n_dead_tup > 0 THEN
                ROUND((ts.n_dead_tup::decimal / (ts.n_live_tup + ts.n_dead_tup)) * 100, 2)
            ELSE 0
        END AS dead_tuple_percent,
        sz.total_size_bytes,
        sz.table_size_bytes,
        sz.index_size_bytes,
        pg_size_pretty(sz.total_size_bytes) AS total_size,
        pg_size_pretty(sz.table_size_bytes) AS table_size,
        pg_size_pretty(sz.index_size_bytes) AS index_size,
        -- Estimate potential space savings
        CASE 
            WHEN ts.n_live_tup + ts.n_dead_tup > 0 THEN
                pg_size_pretty((sz.table_size_bytes * ts.n_dead_tup::decimal / (ts.n_live_tup + ts.n_dead_tup))::bigint)
            ELSE '0 bytes'
        END AS estimated_bloat_size,
        ts.last_vacuum,
        ts.last_autovacuum,
        ts.vacuum_count,
        ts.autovacuum_count,
        -- Calculate vacuum urgency score
        CASE 
            WHEN ts.n_dead_tup > 100000 AND 
                 (ts.n_dead_tup::decimal / NULLIF(ts.n_live_tup + ts.n_dead_tup, 0)) > 0.3 THEN 'CRITICAL'
            WHEN ts.n_dead_tup > 50000 AND 
                 (ts.n_dead_tup::decimal / NULLIF(ts.n_live_tup + ts.n_dead_tup, 0)) > 0.2 THEN 'HIGH'
            WHEN ts.n_dead_tup > 10000 AND 
                 (ts.n_dead_tup::decimal / NULLIF(ts.n_live_tup + ts.n_dead_tup, 0)) > 0.1 THEN 'MEDIUM'
            ELSE 'LOW'
        END AS vacuum_priority
    FROM table_stats ts
    JOIN table_sizes sz ON ts.schemaname = sz.schemaname AND ts.tablename = sz.tablename
)
SELECT 
    schemaname,
    tablename,
    n_live_tup AS live_tuples,
    n_dead_tup AS dead_tuples,
    dead_tuple_percent,
    total_size,
    table_size,
    estimated_bloat_size,
    vacuum_priority,
    COALESCE(last_vacuum, last_autovacuum) AS last_vacuum_time,
    vacuum_count + autovacuum_count AS total_vacuum_count,
    -- Recommendations
    CASE 
        WHEN vacuum_priority = 'CRITICAL' THEN 'IMMEDIATE VACUUM FULL required'
        WHEN vacuum_priority = 'HIGH' THEN 'Schedule VACUUM FULL in next maintenance window'
        WHEN vacuum_priority = 'MEDIUM' THEN 'Monitor closely, consider manual VACUUM'
        ELSE 'Normal autovacuum sufficient'
    END AS recommendation
FROM bloat_estimates
WHERE n_dead_tup > 1000  -- Filter out tables with minimal dead tuples
ORDER BY 
    CASE vacuum_priority 
        WHEN 'CRITICAL' THEN 1 
        WHEN 'HIGH' THEN 2 
        WHEN 'MEDIUM' THEN 3 
        ELSE 4 
    END,
    dead_tuple_percent DESC,
    total_size_bytes DESC;
```

### **2. Index Bloat Analysis**
```sql
-- Index bloat detection and maintenance recommendations
WITH index_stats AS (
    SELECT 
        schemaname,
        tablename,
        indexname,
        idx_scan,
        idx_tup_read,
        idx_tup_fetch,
        pg_relation_size(indexname::regclass) AS index_size_bytes,
        pg_size_pretty(pg_relation_size(indexname::regclass)) AS index_size
    FROM pg_stat_user_indexes
    WHERE pg_relation_size(indexname::regclass) > 1024 * 1024  -- > 1MB
),
table_bloat AS (
    SELECT 
        schemaname,
        tablename,
        n_dead_tup,
        n_live_tup + n_dead_tup AS total_tuples,
        CASE 
            WHEN n_live_tup + n_dead_tup > 0 THEN
                (n_dead_tup::decimal / (n_live_tup + n_dead_tup)) * 100
            ELSE 0
        END AS table_bloat_percent
    FROM pg_stat_user_tables
)
SELECT 
    i.schemaname,
    i.tablename,
    i.indexname,
    i.index_size,
    i.idx_scan AS index_scans,
    CASE 
        WHEN i.idx_scan = 0 THEN 'UNUSED - Consider dropping'
        WHEN i.idx_scan < 100 THEN 'LOW USAGE - Review necessity'
        ELSE 'ACTIVE'
    END AS usage_status,
    t.table_bloat_percent,
    -- Index maintenance recommendation
    CASE 
        WHEN t.table_bloat_percent > 30 THEN 'REINDEX recommended due to table bloat'
        WHEN t.table_bloat_percent > 20 THEN 'Monitor for REINDEX need'
        WHEN i.idx_scan = 0 AND i.index_size_bytes > 100 * 1024 * 1024 THEN 'Consider dropping unused large index'
        ELSE 'No immediate action needed'
    END AS maintenance_recommendation,
    -- Estimated maintenance command
    CASE 
        WHEN t.table_bloat_percent > 30 THEN 'REINDEX INDEX CONCURRENTLY ' || i.indexname || ';'
        WHEN i.idx_scan = 0 THEN '-- DROP INDEX ' || i.indexname || '; -- Verify not needed first'
        ELSE '-- No action required'
    END AS suggested_command
FROM index_stats i
LEFT JOIN table_bloat t ON i.schemaname = t.schemaname AND i.tablename = t.tablename
ORDER BY 
    CASE 
        WHEN t.table_bloat_percent > 30 THEN 1
        WHEN i.idx_scan = 0 AND i.index_size_bytes > 100 * 1024 * 1024 THEN 2
        ELSE 3
    END,
    i.index_size_bytes DESC;
```

---

## ⚙️ **Autovacuum Optimization**

### **3. Autovacuum Performance Analysis**
```sql
-- Comprehensive autovacuum performance monitoring
SELECT 
    schemaname,
    tablename,
    n_live_tup,
    n_dead_tup,
    CASE 
        WHEN n_live_tup + n_dead_tup > 0 THEN
            ROUND((n_dead_tup::decimal / (n_live_tup + n_dead_tup)) * 100, 2)
        ELSE 0
    END AS dead_tuple_percent,
    last_vacuum,
    last_autovacuum,
    vacuum_count,
    autovacuum_count,
    -- Calculate time since last vacuum
    CASE 
        WHEN last_autovacuum IS NOT NULL THEN
            EXTRACT(EPOCH FROM (now() - last_autovacuum))/3600
        WHEN last_vacuum IS NOT NULL THEN
            EXTRACT(EPOCH FROM (now() - last_vacuum))/3600
        ELSE NULL
    END AS hours_since_last_vacuum,
    -- Autovacuum threshold calculation
    CASE 
        WHEN n_live_tup > 0 THEN
            50 + (0.2 * n_live_tup)  -- Default autovacuum_vacuum_threshold + autovacuum_vacuum_scale_factor
        ELSE 50
    END AS autovacuum_threshold,
    -- Check if table needs vacuum based on thresholds
    CASE 
        WHEN n_dead_tup > (50 + (0.2 * n_live_tup)) THEN 'OVERDUE'
        WHEN n_dead_tup > (40 + (0.15 * n_live_tup)) THEN 'DUE_SOON'
        ELSE 'OK'
    END AS vacuum_status,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY 
    CASE 
        WHEN n_dead_tup > (50 + (0.2 * n_live_tup)) THEN 1
        WHEN n_dead_tup > (40 + (0.15 * n_live_tup)) THEN 2
        ELSE 3
    END,
    n_dead_tup DESC;
```

### **4. Autovacuum Configuration Recommendations**
```sql
-- Generate table-specific autovacuum tuning recommendations
WITH table_analysis AS (
    SELECT 
        schemaname,
        tablename,
        n_live_tup,
        n_dead_tup,
        n_tup_ins + n_tup_upd + n_tup_del AS total_modifications,
        pg_total_relation_size(schemaname||'.'||tablename) AS table_size_bytes,
        CASE 
            WHEN last_autovacuum IS NOT NULL THEN
                EXTRACT(EPOCH FROM (now() - last_autovacuum))/3600
            ELSE NULL
        END AS hours_since_autovacuum,
        autovacuum_count,
        -- Calculate modification rate (modifications per hour)
        CASE 
            WHEN last_autovacuum IS NOT NULL AND 
                 EXTRACT(EPOCH FROM (now() - last_autovacuum)) > 0 THEN
                (n_tup_ins + n_tup_upd + n_tup_del) / 
                (EXTRACT(EPOCH FROM (now() - last_autovacuum))/3600)
            ELSE 0
        END AS modifications_per_hour
    FROM pg_stat_user_tables
    WHERE n_live_tup > 1000  -- Focus on substantial tables
)
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(table_size_bytes) AS table_size,
    n_live_tup,
    n_dead_tup,
    modifications_per_hour,
    -- Current autovacuum settings recommendations
    CASE 
        WHEN modifications_per_hour > 10000 THEN
            'ALTER TABLE ' || schemaname || '.' || tablename || 
            ' SET (autovacuum_vacuum_scale_factor = 0.1, autovacuum_vacuum_threshold = 100);'
        WHEN modifications_per_hour > 1000 THEN
            'ALTER TABLE ' || schemaname || '.' || tablename || 
            ' SET (autovacuum_vacuum_scale_factor = 0.15, autovacuum_vacuum_threshold = 75);'
        WHEN table_size_bytes > 1024*1024*1024 THEN  -- > 1GB
            'ALTER TABLE ' || schemaname || '.' || tablename || 
            ' SET (autovacuum_vacuum_scale_factor = 0.05, autovacuum_vacuum_threshold = 200);'
        ELSE
            '-- Default settings appropriate'
    END AS recommended_autovacuum_settings,
    -- Analyze threshold recommendations
    CASE 
        WHEN modifications_per_hour > 5000 THEN
            'ALTER TABLE ' || schemaname || '.' || tablename || 
            ' SET (autovacuum_analyze_scale_factor = 0.05, autovacuum_analyze_threshold = 100);'
        WHEN table_size_bytes > 1024*1024*1024 THEN
            'ALTER TABLE ' || schemaname || '.' || tablename || 
            ' SET (autovacuum_analyze_scale_factor = 0.02, autovacuum_analyze_threshold = 200);'
        ELSE
            '-- Default analyze settings appropriate'
    END AS recommended_analyze_settings,
    -- Priority classification
    CASE 
        WHEN modifications_per_hour > 10000 OR table_size_bytes > 5*1024*1024*1024 THEN 'HIGH'
        WHEN modifications_per_hour > 1000 OR table_size_bytes > 1024*1024*1024 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS tuning_priority
FROM table_analysis
WHERE modifications_per_hour > 100 OR table_size_bytes > 100*1024*1024  -- Focus on active or large tables
ORDER BY 
    CASE 
        WHEN modifications_per_hour > 10000 OR table_size_bytes > 5*1024*1024*1024 THEN 1
        WHEN modifications_per_hour > 1000 OR table_size_bytes > 1024*1024*1024 THEN 2
        ELSE 3
    END,
    modifications_per_hour DESC,
    table_size_bytes DESC;
```

---

## 🚨 **Emergency Bloat Remediation**

### **5. Critical Bloat Response Procedures**
```sql
-- Emergency bloat assessment and remediation planning
WITH critical_bloat AS (
    SELECT 
        schemaname,
        tablename,
        n_live_tup,
        n_dead_tup,
        CASE 
            WHEN n_live_tup + n_dead_tup > 0 THEN
                (n_dead_tup::decimal / (n_live_tup + n_dead_tup)) * 100
            ELSE 0
        END AS bloat_percent,
        pg_total_relation_size(schemaname||'.'||tablename) AS total_size_bytes,
        pg_relation_size(schemaname||'.'||tablename) AS table_size_bytes,
        -- Estimate VACUUM FULL duration (rough estimate: 1GB per 10 minutes)
        CASE 
            WHEN pg_relation_size(schemaname||'.'||tablename) > 0 THEN
                ROUND((pg_relation_size(schemaname||'.'||tablename) / (1024*1024*1024.0)) * 10)
            ELSE 1
        END AS estimated_vacuum_full_minutes,
        -- Check for foreign key constraints (affects VACUUM FULL strategy)
        (SELECT COUNT(*) 
         FROM information_schema.table_constraints tc
         WHERE tc.table_schema = schemaname 
           AND tc.table_name = tablename 
           AND tc.constraint_type = 'FOREIGN KEY') AS fk_constraints,
        -- Check for dependent views
        (SELECT COUNT(*)
         FROM information_schema.view_table_usage vtu
         WHERE vtu.table_schema = schemaname 
           AND vtu.table_name = tablename) AS dependent_views
    FROM pg_stat_user_tables
    WHERE n_dead_tup > 10000  -- Significant dead tuple count
)
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(total_size_bytes) AS total_size,
    pg_size_pretty(table_size_bytes) AS table_size,
    n_live_tup AS live_tuples,
    n_dead_tup AS dead_tuples,
    ROUND(bloat_percent, 2) AS bloat_percent,
    estimated_vacuum_full_minutes AS est_vacuum_duration_min,
    -- Risk assessment
    CASE 
        WHEN bloat_percent > 70 THEN 'CRITICAL - Immediate action required'
        WHEN bloat_percent > 50 THEN 'HIGH - Schedule emergency maintenance'
        WHEN bloat_percent > 30 THEN 'MEDIUM - Plan maintenance window'
        ELSE 'LOW - Monitor'
    END AS risk_level,
    -- Remediation strategy
    CASE 
        WHEN bloat_percent > 70 AND total_size_bytes > 10*1024*1024*1024 THEN 
            'EMERGENCY: Consider pg_repack or staged VACUUM FULL'
        WHEN bloat_percent > 50 AND fk_constraints > 0 THEN
            'CAUTION: VACUUM FULL will require constraint recreation'
        WHEN bloat_percent > 50 THEN
            'VACUUM FULL recommended in maintenance window'
        WHEN bloat_percent > 30 THEN
            'Regular VACUUM may be sufficient, monitor closely'
        ELSE
            'Continue normal autovacuum'
    END AS remediation_strategy,
    -- Specific commands
    CASE 
        WHEN bloat_percent > 50 THEN
            'VACUUM (FULL, ANALYZE) ' || schemaname || '.' || tablename || ';'
        WHEN bloat_percent > 30 THEN
            'VACUUM (ANALYZE) ' || schemaname || '.' || tablename || ';'
        ELSE
            '-- No immediate action needed'
    END AS recommended_command,
    fk_constraints,
    dependent_views
FROM critical_bloat
WHERE bloat_percent > 20  -- Focus on tables with significant bloat
ORDER BY 
    CASE 
        WHEN bloat_percent > 70 THEN 1
        WHEN bloat_percent > 50 THEN 2
        WHEN bloat_percent > 30 THEN 3
        ELSE 4
    END,
    total_size_bytes DESC;
```

### **6. Safe VACUUM FULL Execution Framework**
```sql
-- Function to safely execute VACUUM FULL with pre-checks
CREATE OR REPLACE FUNCTION safe_vacuum_full(
    p_schema_name TEXT,
    p_table_name TEXT,
    p_max_size_gb INTEGER DEFAULT 100,
    p_check_constraints BOOLEAN DEFAULT TRUE
) RETURNS TEXT AS $$
DECLARE
    v_table_size_bytes BIGINT;
    v_table_size_gb NUMERIC;
    v_fk_count INTEGER;
    v_view_count INTEGER;
    v_lock_count INTEGER;
    v_result TEXT;
BEGIN
    -- Get table size
    SELECT pg_total_relation_size(p_schema_name||'.'||p_table_name) 
    INTO v_table_size_bytes;
    
    v_table_size_gb := v_table_size_bytes / (1024*1024*1024.0);
    
    -- Safety checks
    IF v_table_size_gb > p_max_size_gb THEN
        RETURN 'ABORT: Table size (' || ROUND(v_table_size_gb, 2) || 'GB) exceeds safety limit (' || p_max_size_gb || 'GB)';
    END IF;
    
    -- Check for foreign key constraints
    IF p_check_constraints THEN
        SELECT COUNT(*) INTO v_fk_count
        FROM information_schema.table_constraints
        WHERE table_schema = p_schema_name 
          AND table_name = p_table_name 
          AND constraint_type = 'FOREIGN KEY';
          
        IF v_fk_count > 0 THEN
            RETURN 'WARNING: Table has ' || v_fk_count || ' foreign key constraints. VACUUM FULL will require exclusive lock.';
        END IF;
    END IF;
    
    -- Check for current locks
    SELECT COUNT(*) INTO v_lock_count
    FROM pg_locks l
    JOIN pg_class c ON l.relation = c.oid
    WHERE c.relname = p_table_name
      AND c.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = p_schema_name);
      
    IF v_lock_count > 1 THEN  -- More than just our connection
        RETURN 'ABORT: Table currently has ' || v_lock_count || ' active locks. Wait for operations to complete.';
    END IF;
    
    -- Execute VACUUM FULL
    EXECUTE 'VACUUM (FULL, ANALYZE) ' || p_schema_name || '.' || p_table_name;
    
    RETURN 'SUCCESS: VACUUM FULL completed for ' || p_schema_name || '.' || p_table_name || 
           ' (original size: ' || ROUND(v_table_size_gb, 2) || 'GB)';
           
EXCEPTION
    WHEN OTHERS THEN
        RETURN 'ERROR: ' || SQLERRM;
END;
$$ LANGUAGE plpgsql;
```

---

## 📊 **Performance Monitoring and Impact Analysis**

### **7. VACUUM Operation Performance Tracking**
```sql
-- Monitor ongoing VACUUM operations and their impact
SELECT 
    pid,
    usename,
    application_name,
    state,
    query_start,
    EXTRACT(EPOCH FROM (now() - query_start))::int AS duration_seconds,
    CASE 
        WHEN query ILIKE '%VACUUM%FULL%' THEN 'VACUUM FULL'
        WHEN query ILIKE '%VACUUM%' THEN 'VACUUM'
        WHEN query ILIKE '%REINDEX%' THEN 'REINDEX'
        ELSE 'OTHER'
    END AS operation_type,
    LEFT(query, 100) AS query_preview,
    -- Estimate progress for VACUUM FULL (rough approximation)
    CASE 
        WHEN query ILIKE '%VACUUM%FULL%' THEN
            CASE 
                WHEN EXTRACT(EPOCH FROM (now() - query_start)) < 300 THEN 'Starting (0-10%)'
                WHEN EXTRACT(EPOCH FROM (now() - query_start)) < 900 THEN 'In Progress (10-50%)'
                WHEN EXTRACT(EPOCH FROM (now() - query_start)) < 1800 THEN 'Advanced (50-80%)'
                ELSE 'Finalizing (80-100%)'
            END
        ELSE 'N/A'
    END AS estimated_progress
FROM pg_stat_activity
WHERE query ILIKE '%VACUUM%' 
   OR query ILIKE '%REINDEX%'
   AND state = 'active'
ORDER BY query_start;

-- System impact during VACUUM operations
SELECT 
    'VACUUM_IMPACT_METRICS' AS metric_type,
    COUNT(*) FILTER (WHERE query ILIKE '%VACUUM%') AS active_vacuum_operations,
    COUNT(*) FILTER (WHERE state = 'active' AND query NOT ILIKE '%VACUUM%') AS other_active_queries,
    COUNT(*) FILTER (WHERE wait_event_type = 'Lock') AS queries_waiting_for_locks,
    ROUND(AVG(EXTRACT(EPOCH FROM (now() - query_start))) FILTER (WHERE state = 'active'), 2) AS avg_query_duration_seconds
FROM pg_stat_activity
WHERE state != 'idle';
```

### **8. Historical VACUUM Performance Analysis**
```sql
-- Analyze VACUUM performance trends (requires log analysis or custom tracking)
WITH vacuum_history AS (
    SELECT 
        schemaname,
        tablename,
        last_vacuum,
        last_autovacuum,
        vacuum_count,
        autovacuum_count,
        n_tup_ins + n_tup_upd + n_tup_del AS total_modifications,
        pg_total_relation_size(schemaname||'.'||tablename) AS current_size_bytes,
        -- Calculate vacuum frequency
        CASE 
            WHEN vacuum_count + autovacuum_count > 0 AND last_autovacuum IS NOT NULL THEN
                EXTRACT(EPOCH FROM (now() - last_autovacuum)) / (vacuum_count + autovacuum_count)
            ELSE NULL
        END AS avg_seconds_between_vacuums
    FROM pg_stat_user_tables
    WHERE vacuum_count + autovacuum_count > 0
)
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(current_size_bytes) AS current_size,
    vacuum_count + autovacuum_count AS total_vacuum_operations,
    CASE 
        WHEN avg_seconds_between_vacuums IS NOT NULL THEN
            ROUND(avg_seconds_between_vacuums / 3600, 2) || ' hours'
        ELSE 'N/A'
    END AS avg_time_between_vacuums,
    total_modifications,
    -- Vacuum efficiency score
    CASE 
        WHEN avg_seconds_between_vacuums IS NOT NULL AND avg_seconds_between_vacuums < 86400 THEN 'EFFICIENT'
        WHEN avg_seconds_between_vacuums IS NOT NULL AND avg_seconds_between_vacuums < 259200 THEN 'MODERATE'
        WHEN avg_seconds_between_vacuums IS NOT NULL THEN 'INEFFICIENT'
        ELSE 'INSUFFICIENT_DATA'
    END AS vacuum_efficiency,
    last_vacuum,
    last_autovacuum
FROM vacuum_history
ORDER BY 
    CASE 
        WHEN avg_seconds_between_vacuums IS NOT NULL AND avg_seconds_between_vacuums > 259200 THEN 1
        WHEN avg_seconds_between_vacuums IS NULL THEN 2
        ELSE 3
    END,
    current_size_bytes DESC;
```

---

## 🔧 **Automated Maintenance Procedures**

### **9. Automated VACUUM Scheduling Script**
```sql
-- Function for intelligent VACUUM scheduling
CREATE OR REPLACE FUNCTION intelligent_vacuum_scheduler()
RETURNS TABLE(
    schema_name TEXT,
    table_name TEXT,
    vacuum_type TEXT,
    priority INTEGER,
    estimated_duration_minutes INTEGER,
    recommended_command TEXT
) AS $$
BEGIN
    RETURN QUERY
    WITH table_analysis AS (
        SELECT 
            schemaname,
            tablename,
            n_live_tup,
            n_dead_tup,
            CASE 
                WHEN n_live_tup + n_dead_tup > 0 THEN
                    (n_dead_tup::decimal / (n_live_tup + n_dead_tup)) * 100
                ELSE 0
            END AS bloat_percent,
            pg_total_relation_size(schemaname||'.'||tablename) AS table_size_bytes,
            COALESCE(last_vacuum, last_autovacuum) AS last_vacuum_time,
            -- Calculate urgency score
            CASE 
                WHEN n_dead_tup > 100000 AND 
                     (n_dead_tup::decimal / NULLIF(n_live_tup + n_dead_tup, 0)) > 0.5 THEN 1
                WHEN n_dead_tup > 50000 AND 
                     (n_dead_tup::decimal / NULLIF(n_live_tup + n_dead_tup, 0)) > 0.3 THEN 2
                WHEN n_dead_tup > 10000 AND 
                     (n_dead_tup::decimal / NULLIF(n_live_tup + n_dead_tup, 0)) > 0.2 THEN 3
                ELSE 4
            END AS priority_score
        FROM pg_stat_user_tables
        WHERE n_dead_tup > 1000
    )
    SELECT 
        ta.schemaname::TEXT,
        ta.tablename::TEXT,
        CASE 
            WHEN ta.bloat_percent > 50 THEN 'VACUUM FULL'
            WHEN ta.bloat_percent > 20 THEN 'VACUUM'
            ELSE 'ANALYZE'
        END::TEXT AS vacuum_type,
        ta.priority_score::INTEGER,
        -- Estimate duration based on table size and operation type
        CASE 
            WHEN ta.bloat_percent > 50 THEN
                GREATEST(5, (ta.table_size_bytes / (1024*1024*1024.0) * 10)::INTEGER)
            WHEN ta.bloat_percent > 20 THEN
                GREATEST(2, (ta.table_size_bytes / (1024*1024*1024.0) * 3)::INTEGER)
            ELSE 1
        END::INTEGER AS estimated_duration_minutes,
        CASE 
            WHEN ta.bloat_percent > 50 THEN
                'VACUUM (FULL, ANALYZE) ' || ta.schemaname || '.' || ta.tablename || ';'
            WHEN ta.bloat_percent > 20 THEN
                'VACUUM (ANALYZE) ' || ta.schemaname || '.' || ta.tablename || ';'
            ELSE
                'ANALYZE ' || ta.schemaname || '.' || ta.tablename || ';'
        END::TEXT AS recommended_command
    FROM table_analysis ta
    ORDER BY ta.priority_score, ta.table_size_bytes DESC;
END;
$$ LANGUAGE plpgsql;

-- Execute the scheduler
SELECT * FROM intelligent_vacuum_scheduler();
```

---

## 📈 **Azure-Specific Monitoring Integration**

### **10. Azure Monitor Integration Queries**
```kusto
// Azure Log Analytics query for VACUUM operation monitoring
AzureDiagnostics
| where Category == "PostgreSQLLogs"
| where Message contains "VACUUM" or Message contains "autovacuum"
| extend VacuumType = case(
    Message contains "VACUUM FULL", "VACUUM_FULL",
    Message contains "autovacuum", "AUTOVACUUM",
    Message contains "VACUUM", "MANUAL_VACUUM",
    "OTHER"
)
| extend Duration = extract(@"duration: ([\d.]+) ms", 1, Message)
| extend TableName = extract(@"table ""([^""]+)""", 1, Message)
| summarize 
    Count = count(),
    AvgDuration = avg(todouble(Duration)),
    MaxDuration = max(todouble(Duration))
    by VacuumType, TableName, bin(TimeGenerated, 1h)
| order by TimeGenerated desc
```

### **11. Performance Baseline and Alerting**
```sql
-- Create performance baseline for VACUUM operations
CREATE OR REPLACE VIEW vacuum_performance_baseline AS
WITH baseline_metrics AS (
    SELECT 
        schemaname,
        tablename,
        pg_total_relation_size(schemaname||'.'||tablename) AS table_size_bytes,
        n_live_tup,
        n_dead_tup,
        vacuum_count + autovacuum_count AS total_vacuum_count,
        CASE 
            WHEN n_live_tup + n_dead_tup > 0 THEN
                (n_dead_tup::decimal / (n_live_tup + n_dead_tup)) * 100
            ELSE 0
        END AS current_bloat_percent,
        -- Expected vacuum frequency based on table size and activity
        CASE 
            WHEN pg_total_relation_size(schemaname||'.'||tablename) > 10*1024*1024*1024 THEN 24  -- Large tables: daily
            WHEN pg_total_relation_size(schemaname||'.'||tablename) > 1024*1024*1024 THEN 12   -- Medium tables: twice daily
            ELSE 6  -- Small tables: every 6 hours
        END AS expected_vacuum_frequency_hours,
        COALESCE(last_vacuum, last_autovacuum) AS last_vacuum_time
    FROM pg_stat_user_tables
    WHERE n_live_tup > 1000
)
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(table_size_bytes) AS table_size,
    current_bloat_percent,
    expected_vacuum_frequency_hours,
    CASE 
        WHEN last_vacuum_time IS NOT NULL THEN
            EXTRACT(EPOCH FROM (now() - last_vacuum_time))/3600
        ELSE NULL
    END AS hours_since_last_vacuum,
    -- Alert conditions
    CASE 
        WHEN current_bloat_percent > 50 THEN 'CRITICAL_BLOAT'
        WHEN current_bloat_percent > 30 THEN 'HIGH_BLOAT'
        WHEN last_vacuum_time IS NOT NULL AND 
             EXTRACT(EPOCH FROM (now() - last_vacuum_time))/3600 > (expected_vacuum_frequency_hours * 2) THEN 'OVERDUE_VACUUM'
        ELSE 'NORMAL'
    END AS alert_status,
    total_vacuum_count
FROM baseline_metrics
ORDER BY 
    CASE 
        WHEN current_bloat_percent > 50 THEN 1
        WHEN current_bloat_percent > 30 THEN 2
        WHEN last_vacuum_time IS NOT NULL AND 
             EXTRACT(EPOCH FROM (now() - last_vacuum_time))/3600 > (expected_vacuum_frequency_hours * 2) THEN 3
        ELSE 4
    END,
    table_size_bytes DESC;
```

---

## 🎯 **Best Practices and Recommendations**

### **Enterprise VACUUM Management Strategy**

1. **Proactive Monitoring**
   - **Daily**: Run bloat assessment queries
   - **Weekly**: Review autovacuum performance and tuning
   - **Monthly**: Analyze vacuum trends and capacity planning

2. **Automated Thresholds**
   - **Critical Alert**: >50% bloat or >72 hours without vacuum
   - **Warning Alert**: >30% bloat or >48 hours without vacuum
   - **Info Alert**: >20% bloat or unusual vacuum patterns

3. **Maintenance Windows**
   - **Emergency**: VACUUM FULL for >70% bloat
   - **Planned**: VACUUM FULL for >50% bloat during maintenance
   - **Routine**: Regular VACUUM for >20% bloat

4. **Performance Optimization**
   - **Large Tables**: Custom autovacuum settings
   - **High-Activity Tables**: Aggressive vacuum thresholds
   - **Read-Heavy Tables**: Focus on analyze frequency

### **Safety Procedures**

1. **Pre-VACUUM Checks**
   - Verify sufficient disk space (3x table size for VACUUM FULL)
   - Check for long-running transactions
   - Identify dependent applications and maintenance windows

2. **During VACUUM Operations**
   - Monitor system resources (CPU, I/O, locks)
   - Track operation progress and duration
   - Maintain communication with application teams

3. **Post-VACUUM Validation**
   - Verify space reclamation
   - Update table statistics
   - Monitor application performance impact

---

## 🔗 **Integration and Automation**

### **Grafana Dashboard Metrics**
```sql
-- Metrics for Grafana visualization
SELECT 
    EXTRACT(EPOCH FROM now()) AS time,
    'table_bloat_percent' AS metric,
    schemaname || '.' || tablename AS table_name,
    CASE 
        WHEN n_live_tup + n_dead_tup > 0 THEN
            (n_dead_tup::decimal / (n_live_tup + n_dead_tup)) * 100
        ELSE 0
    END AS value
FROM pg_stat_user_tables
WHERE n_live_tup > 1000
UNION ALL
SELECT 
    EXTRACT(EPOCH FROM now()) AS time,
    'vacuum_operations_active' AS metric,
    'system' AS table_name,
    COUNT(*)::decimal AS value
FROM pg_stat_activity
WHERE query ILIKE '%VACUUM%' AND state = 'active';
```

### **Nagios/Icinga Check Script**
```bash
#!/bin/bash
# PostgreSQL bloat monitoring check
CRITICAL_BLOAT=$(psql -t -c "
SELECT COUNT(*) FROM pg_stat_user_tables 
WHERE n_live_tup + n_dead_tup > 0 
  AND (n_dead_tup::decimal / (n_live_tup + n_dead_tup)) > 0.5;
")

HIGH_BLOAT=$(psql -t -c "
SELECT COUNT(*) FROM pg_stat_user_tables 
WHERE n_live_tup + n_dead_tup > 0 
  AND (n_dead_tup::decimal / (n_live_tup + n_dead_tup)) > 0.3;
")

if [ "$CRITICAL_BLOAT" -gt 0 ]; then
    echo "CRITICAL: $CRITICAL_BLOAT tables with >50% bloat"
    exit 2
elif [ "$HIGH_BLOAT" -gt 0 ]; then
    echo "WARNING: $HIGH_BLOAT tables with >30% bloat"
    exit 1
else
    echo "OK: No critical table bloat detected"
    exit 0
fi
```

---

## 📚 **Additional Resources**

- **PostgreSQL Documentation**: [VACUUM Command](https://www.postgresql.org/docs/current/sql-vacuum.html)
- **Azure PostgreSQL**: [Autovacuum Tuning](https://docs.microsoft.com/en-us/azure/postgresql/concepts-monitoring)
- **Related Tools**: [pg_repack](https://github.com/reorg/pg_repack) for online table reorganization

---

*This comprehensive guide provides enterprise-grade VACUUM management for PostgreSQL databases. Regular implementation of these procedures ensures optimal database performance and storage efficiency.*