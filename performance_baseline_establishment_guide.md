# Database Performance Baseline Establishment Guide

## Table of Contents
1. [Baseline Overview](#baseline-overview)
2. [Pre-Baseline Preparation](#pre-baseline-preparation)
3. [PostgreSQL Baseline](#postgresql-baseline)
4. [MySQL Baseline](#mysql-baseline)
5. [SQL Server Baseline](#sql-server-baseline)
6. [Baseline Analysis and Reporting](#baseline-analysis-and-reporting)
7. [Ongoing Baseline Maintenance](#ongoing-baseline-maintenance)

## Baseline Overview

### Purpose
Performance baselines establish normal operating parameters for database systems, enabling:
- **Anomaly Detection**: Identify when performance deviates from normal patterns
- **Capacity Planning**: Predict future resource needs based on growth trends
- **Performance Optimization**: Measure improvement after tuning activities
- **SLA Compliance**: Ensure service levels meet business requirements

### Baseline Duration
- **Initial Baseline**: 14-30 days of continuous monitoring
- **Seasonal Baseline**: 3-6 months to capture business cycles
- **Refresh Frequency**: Quarterly or after major changes

### Key Metrics Categories
1. **Resource Utilization**: CPU, Memory, Storage, I/O
2. **Performance Metrics**: Query response time, throughput, concurrency
3. **Availability Metrics**: Uptime, connection success rate
4. **Business Metrics**: Transaction volume, user activity patterns

## Pre-Baseline Preparation

### 1. Environment Assessment
```bash
# Document current environment
echo "=== Environment Assessment ===" > baseline_prep.txt
echo "Date: $(date)" >> baseline_prep.txt
echo "Environment: $ENVIRONMENT" >> baseline_prep.txt
echo "Database Versions:" >> baseline_prep.txt

# PostgreSQL version
psql -c "SELECT version();" >> baseline_prep.txt

# MySQL version  
mysql -e "SELECT VERSION();" >> baseline_prep.txt

# SQL Server version (if applicable)
sqlcmd -Q "SELECT @@VERSION;" >> baseline_prep.txt
```

### 2. Workload Characterization
```sql
-- Identify peak usage patterns
-- Run this across all database types during different time periods

-- PostgreSQL workload analysis
SELECT 
    date_trunc('hour', now()) as hour_period,
    count(*) as connection_count,
    avg(extract(epoch from (now() - backend_start))) as avg_session_duration
FROM pg_stat_activity 
WHERE state = 'active'
GROUP BY hour_period
ORDER BY hour_period;

-- MySQL workload analysis  
SELECT 
    DATE_FORMAT(NOW(), '%Y-%m-%d %H:00:00') as hour_period,
    COUNT(*) as connection_count
FROM INFORMATION_SCHEMA.PROCESSLIST 
WHERE COMMAND != 'Sleep'
GROUP BY hour_period;

-- SQL Server workload analysis
SELECT 
    DATEPART(hour, GETDATE()) as hour_period,
    COUNT(*) as connection_count,
    AVG(DATEDIFF(second, login_time, GETDATE())) as avg_session_duration
FROM sys.dm_exec_sessions 
WHERE is_user_process = 1
GROUP BY DATEPART(hour, GETDATE());
```

### 3. Configuration Documentation
```bash
# Create configuration backup before baseline
mkdir -p baseline_configs/$(date +%Y%m%d)

# PostgreSQL configuration
pg_dump --schema-only your_database > baseline_configs/$(date +%Y%m%d)/postgresql_schema.sql
psql -c "SHOW ALL;" > baseline_configs/$(date +%Y%m%d)/postgresql_config.txt

# MySQL configuration
mysqldump --no-data --routines your_database > baseline_configs/$(date +%Y%m%d)/mysql_schema.sql
mysql -e "SHOW VARIABLES;" > baseline_configs/$(date +%Y%m%d)/mysql_config.txt

# Document Azure configuration
az postgres server configuration list --resource-group $RG --server-name $PG_SERVER > baseline_configs/$(date +%Y%m%d)/azure_pg_config.json
az mysql server configuration list --resource-group $RG --server-name $MYSQL_SERVER > baseline_configs/$(date +%Y%m%d)/azure_mysql_config.json
```

## PostgreSQL Baseline

### 1. Performance Metrics Collection
```sql
-- Create baseline monitoring views
CREATE OR REPLACE VIEW baseline_pg_performance AS
SELECT 
    now() as sample_time,
    -- Connection metrics
    (SELECT count(*) FROM pg_stat_activity WHERE state = 'active') as active_connections,
    (SELECT count(*) FROM pg_stat_activity WHERE state = 'idle') as idle_connections,
    
    -- Database statistics
    pg_database_size(current_database()) as database_size_bytes,
    
    -- Transaction statistics
    (SELECT sum(xact_commit) FROM pg_stat_database WHERE datname = current_database()) as total_commits,
    (SELECT sum(xact_rollback) FROM pg_stat_database WHERE datname = current_database()) as total_rollbacks,
    
    -- I/O statistics
    (SELECT sum(blks_read) FROM pg_stat_database WHERE datname = current_database()) as blocks_read,
    (SELECT sum(blks_hit) FROM pg_stat_database WHERE datname = current_database()) as blocks_hit,
    
    -- Cache hit ratio
    CASE 
        WHEN (SELECT sum(blks_read + blks_hit) FROM pg_stat_database WHERE datname = current_database()) > 0 
        THEN (SELECT sum(blks_hit) * 100.0 / sum(blks_read + blks_hit) FROM pg_stat_database WHERE datname = current_database())
        ELSE 0 
    END as cache_hit_ratio;

-- Baseline data collection script
CREATE TABLE IF NOT EXISTS baseline_pg_metrics (
    sample_time timestamp,
    active_connections int,
    idle_connections int,
    database_size_bytes bigint,
    total_commits bigint,
    total_rollbacks bigint,
    blocks_read bigint,
    blocks_hit bigint,
    cache_hit_ratio numeric(5,2)
);

-- Insert baseline sample (run every 5 minutes via cron)
INSERT INTO baseline_pg_metrics 
SELECT * FROM baseline_pg_performance;
```

### 2. Query Performance Baseline
```sql
-- Top queries baseline (requires pg_stat_statements)
CREATE TABLE IF NOT EXISTS baseline_pg_queries AS
SELECT 
    now() as baseline_date,
    query,
    calls,
    total_time,
    mean_time,
    rows,
    100.0 * shared_blks_hit / nullif(shared_blks_hit + shared_blks_read, 0) as hit_percent
FROM pg_stat_statements 
WHERE calls > 100  -- Only frequently executed queries
ORDER BY total_time DESC
LIMIT 50;

-- Reset statistics after baseline period
-- SELECT pg_stat_statements_reset();
```

### 3. System Resource Baseline
```bash
#!/bin/bash
# PostgreSQL system resource baseline collection
# Run every 5 minutes during baseline period

BASELINE_DIR="/var/log/postgresql/baseline"
mkdir -p $BASELINE_DIR

# CPU and Memory
echo "$(date),$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1),$(free | grep Mem | awk '{printf "%.2f", $3/$2 * 100.0}')" >> $BASELINE_DIR/system_metrics.csv

# Disk I/O
iostat -x 1 1 | grep -E "(Device|postgres)" >> $BASELINE_DIR/disk_io.log

# Network
ss -tuln | grep :5432 | wc -l >> $BASELINE_DIR/network_connections.log
```

## MySQL Baseline

### 1. Performance Metrics Collection
```sql
-- Create baseline monitoring view
CREATE OR REPLACE VIEW baseline_mysql_performance AS
SELECT 
    NOW() as sample_time,
    -- Connection metrics
    (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Threads_connected') as active_connections,
    (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Threads_running') as running_threads,
    
    -- Query statistics
    (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Questions') as total_questions,
    (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Slow_queries') as slow_queries,
    
    -- InnoDB metrics
    (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests') as buffer_pool_reads,
    (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads') as physical_reads,
    
    -- Buffer pool hit ratio
    ROUND(
        (1 - (
            (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads') /
            (SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests')
        )) * 100, 2
    ) as buffer_pool_hit_ratio;

-- Baseline metrics table
CREATE TABLE IF NOT EXISTS baseline_mysql_metrics (
    sample_time datetime,
    active_connections int,
    running_threads int,
    total_questions bigint,
    slow_queries bigint,
    buffer_pool_reads bigint,
    physical_reads bigint,
    buffer_pool_hit_ratio decimal(5,2)
);

-- Insert baseline sample
INSERT INTO baseline_mysql_metrics 
SELECT * FROM baseline_mysql_performance;
```

### 2. Query Performance Baseline
```sql
-- Performance Schema baseline (MySQL 5.7+)
CREATE TABLE IF NOT EXISTS baseline_mysql_queries AS
SELECT 
    NOW() as baseline_date,
    DIGEST_TEXT as query_text,
    COUNT_STAR as execution_count,
    AVG_TIMER_WAIT/1000000000000 as avg_time_seconds,
    SUM_TIMER_WAIT/1000000000000 as total_time_seconds,
    SUM_ROWS_EXAMINED as total_rows_examined,
    SUM_ROWS_SENT as total_rows_sent
FROM performance_schema.events_statements_summary_by_digest 
WHERE COUNT_STAR > 100
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 50;

-- Reset Performance Schema after baseline
-- CALL sys.ps_truncate_all_tables(FALSE);
```

## SQL Server Baseline

### 1. Performance Metrics Collection
```sql
-- Create baseline monitoring view
CREATE OR ALTER VIEW baseline_sqlserver_performance AS
SELECT 
    GETDATE() as sample_time,
    -- Connection metrics
    (SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process = 1) as active_connections,
    (SELECT COUNT(*) FROM sys.dm_exec_requests WHERE status = 'running') as running_requests,
    
    -- Database size
    (SELECT SUM(size * 8 / 1024) FROM sys.database_files) as database_size_mb,
    
    -- Buffer cache hit ratio
    (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Buffer cache hit ratio' AND object_name LIKE '%Buffer Manager%') as buffer_cache_hit_ratio,
    
    -- Page life expectancy
    (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Page life expectancy' AND object_name LIKE '%Buffer Manager%') as page_life_expectancy,
    
    -- Batch requests per second
    (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Batch Requests/sec' AND object_name LIKE '%SQL Statistics%') as batch_requests_sec;

-- Baseline metrics table
CREATE TABLE baseline_sqlserver_metrics (
    sample_time datetime2,
    active_connections int,
    running_requests int,
    database_size_mb bigint,
    buffer_cache_hit_ratio bigint,
    page_life_expectancy bigint,
    batch_requests_sec bigint
);

-- Insert baseline sample
INSERT INTO baseline_sqlserver_metrics 
SELECT * FROM baseline_sqlserver_performance;
```

### 2. Query Store Baseline
```sql
-- Enable Query Store for baseline
ALTER DATABASE [YourDatabase] SET QUERY_STORE = ON;
ALTER DATABASE [YourDatabase] SET QUERY_STORE (
    OPERATION_MODE = READ_WRITE,
    CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30),
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    INTERVAL_LENGTH_MINUTES = 60,
    MAX_STORAGE_SIZE_MB = 1000
);

-- Baseline query performance
CREATE TABLE baseline_sqlserver_queries AS
SELECT 
    GETDATE() as baseline_date,
    qsq.query_id,
    qsqt.query_sql_text,
    qsrs.count_executions,
    qsrs.avg_duration / 1000.0 as avg_duration_ms,
    qsrs.avg_cpu_time / 1000.0 as avg_cpu_time_ms,
    qsrs.avg_logical_io_reads,
    qsrs.avg_physical_io_reads
FROM sys.query_store_query qsq
JOIN sys.query_store_query_text qsqt ON qsq.query_text_id = qsqt.query_text_id
JOIN sys.query_store_runtime_stats qsrs ON qsq.query_id = qsrs.query_id
WHERE qsrs.count_executions > 100
ORDER BY qsrs.avg_duration DESC;
```

## Baseline Analysis and Reporting

### 1. Statistical Analysis
```sql
-- PostgreSQL baseline analysis
WITH baseline_stats AS (
    SELECT 
        'active_connections' as metric,
        AVG(active_connections) as avg_value,
        MIN(active_connections) as min_value,
        MAX(active_connections) as max_value,
        STDDEV(active_connections) as std_dev,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY active_connections) as p95_value
    FROM baseline_pg_metrics
    WHERE sample_time >= NOW() - INTERVAL '30 days'
    
    UNION ALL
    
    SELECT 
        'cache_hit_ratio',
        AVG(cache_hit_ratio),
        MIN(cache_hit_ratio),
        MAX(cache_hit_ratio),
        STDDEV(cache_hit_ratio),
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY cache_hit_ratio)
    FROM baseline_pg_metrics
    WHERE sample_time >= NOW() - INTERVAL '30 days'
)
SELECT 
    metric,
    ROUND(avg_value, 2) as average,
    ROUND(min_value, 2) as minimum,
    ROUND(max_value, 2) as maximum,
    ROUND(std_dev, 2) as std_deviation,
    ROUND(p95_value, 2) as percentile_95,
    ROUND(avg_value + (2 * std_dev), 2) as upper_threshold,
    ROUND(avg_value - (2 * std_dev), 2) as lower_threshold
FROM baseline_stats;
```

### 2. Baseline Report Generation
```python
#!/usr/bin/env python3
"""
Database Baseline Report Generator
Generates comprehensive baseline reports for all database types
"""

import psycopg2
import mysql.connector
import pyodbc
import pandas as pd
import matplotlib.pyplot as plt
from datetime import datetime, timedelta
import json

class BaselineReporter:
    def __init__(self, config_file):
        with open(config_file, 'r') as f:
            self.config = json.load(f)
    
    def generate_postgresql_report(self):
        """Generate PostgreSQL baseline report"""
        conn = psycopg2.connect(**self.config['postgresql'])
        
        # Get baseline metrics
        query = """
        SELECT 
            DATE_TRUNC('hour', sample_time) as hour,
            AVG(active_connections) as avg_connections,
            AVG(cache_hit_ratio) as avg_cache_hit_ratio,
            AVG(database_size_bytes / 1024 / 1024) as avg_size_mb
        FROM baseline_pg_metrics 
        WHERE sample_time >= NOW() - INTERVAL '30 days'
        GROUP BY DATE_TRUNC('hour', sample_time)
        ORDER BY hour
        """
        
        df = pd.read_sql(query, conn)
        
        # Generate charts
        fig, axes = plt.subplots(2, 2, figsize=(15, 10))
        
        # Connections over time
        axes[0,0].plot(df['hour'], df['avg_connections'])
        axes[0,0].set_title('Average Connections Over Time')
        axes[0,0].set_ylabel('Connections')
        
        # Cache hit ratio
        axes[0,1].plot(df['hour'], df['avg_cache_hit_ratio'])
        axes[0,1].set_title('Cache Hit Ratio Over Time')
        axes[0,1].set_ylabel('Hit Ratio %')
        
        # Database size growth
        axes[1,0].plot(df['hour'], df['avg_size_mb'])
        axes[1,0].set_title('Database Size Growth')
        axes[1,0].set_ylabel('Size (MB)')
        
        plt.tight_layout()
        plt.savefig(f'postgresql_baseline_{datetime.now().strftime("%Y%m%d")}.png')
        
        conn.close()
        return df
    
    def generate_summary_report(self):
        """Generate executive summary report"""
        report = {
            'baseline_period': '30 days',
            'report_date': datetime.now().isoformat(),
            'databases': {}
        }
        
        # Add PostgreSQL summary
        pg_df = self.generate_postgresql_report()
        report['databases']['postgresql'] = {
            'avg_connections': float(pg_df['avg_connections'].mean()),
            'avg_cache_hit_ratio': float(pg_df['avg_cache_hit_ratio'].mean()),
            'size_growth_mb': float(pg_df['avg_size_mb'].max() - pg_df['avg_size_mb'].min())
        }
        
        # Save report
        with open(f'baseline_summary_{datetime.now().strftime("%Y%m%d")}.json', 'w') as f:
            json.dump(report, f, indent=2)
        
        return report

# Usage
if __name__ == "__main__":
    reporter = BaselineReporter('database_config.json')
    summary = reporter.generate_summary_report()
    print("Baseline report generated successfully")
```

### 3. Threshold Calculation
```sql
-- Calculate dynamic thresholds based on baseline data
CREATE OR REPLACE FUNCTION calculate_thresholds(metric_name TEXT, baseline_days INTEGER DEFAULT 30)
RETURNS TABLE(
    metric TEXT,
    avg_value NUMERIC,
    std_dev NUMERIC,
    warning_threshold NUMERIC,
    critical_threshold NUMERIC,
    p95_threshold NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        metric_name,
        AVG(value) as avg_value,
        STDDEV(value) as std_dev,
        AVG(value) + (1.5 * STDDEV(value)) as warning_threshold,
        AVG(value) + (2.5 * STDDEV(value)) as critical_threshold,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY value) as p95_threshold
    FROM (
        SELECT active_connections::NUMERIC as value FROM baseline_pg_metrics 
        WHERE sample_time >= NOW() - (baseline_days || ' days')::INTERVAL
        AND metric_name = 'active_connections'
        
        UNION ALL
        
        SELECT cache_hit_ratio as value FROM baseline_pg_metrics 
        WHERE sample_time >= NOW() - (baseline_days || ' days')::INTERVAL
        AND metric_name = 'cache_hit_ratio'
    ) baseline_data;
END;
$$ LANGUAGE plpgsql;

-- Example usage
SELECT * FROM calculate_thresholds('active_connections', 30);
```

## Ongoing Baseline Maintenance

### 1. Baseline Refresh Schedule
```bash
#!/bin/bash
# Baseline maintenance script
# Run monthly via cron: 0 2 1 * * /path/to/baseline_maintenance.sh

BASELINE_DIR="/var/log/database_baselines"
ARCHIVE_DIR="$BASELINE_DIR/archive"
DATE=$(date +%Y%m%d)

# Archive old baselines
mkdir -p $ARCHIVE_DIR/$DATE
mv $BASELINE_DIR/current/* $ARCHIVE_DIR/$DATE/

# Start new baseline collection
echo "Starting new baseline collection on $DATE" > $BASELINE_DIR/current/baseline.log

# Reset statistics (uncomment as needed)
# psql -c "SELECT pg_stat_statements_reset();"
# mysql -e "CALL sys.ps_truncate_all_tables(FALSE);"

# Update monitoring thresholds based on new baseline
python3 /scripts/update_monitoring_thresholds.py --baseline-days 30
```

### 2. Seasonal Baseline Adjustments
```python
#!/usr/bin/env python3
"""
Seasonal Baseline Adjustment Script
Adjusts baselines for known seasonal patterns
"""

import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import calendar

class SeasonalBaseline:
    def __init__(self, database_type):
        self.database_type = database_type
        self.seasonal_factors = {
            'Q1': 0.85,  # Lower activity in Q1
            'Q2': 1.0,   # Normal activity
            'Q3': 0.9,   # Summer slowdown
            'Q4': 1.15   # Year-end peak
        }
    
    def get_seasonal_factor(self, date=None):
        """Get seasonal adjustment factor for given date"""
        if date is None:
            date = datetime.now()
        
        quarter = f"Q{(date.month - 1) // 3 + 1}"
        return self.seasonal_factors.get(quarter, 1.0)
    
    def adjust_thresholds(self, base_threshold, date=None):
        """Adjust threshold based on seasonal factor"""
        factor = self.get_seasonal_factor(date)
        return base_threshold * factor
    
    def generate_seasonal_report(self):
        """Generate seasonal baseline report"""
        current_quarter = f"Q{(datetime.now().month - 1) // 3 + 1}"
        factor = self.get_seasonal_factor()
        
        report = {
            'current_quarter': current_quarter,
            'seasonal_factor': factor,
            'adjustment_recommendation': 'increase' if factor > 1.0 else 'decrease',
            'threshold_multiplier': factor
        }
        
        return report

# Usage
seasonal = SeasonalBaseline('postgresql')
report = seasonal.generate_seasonal_report()
print(f"Seasonal adjustment: {report}")
```

### 3. Baseline Validation
```sql
-- Baseline validation queries
-- Run these to ensure baseline data quality

-- Check for data completeness
SELECT 
    'PostgreSQL' as database_type,
    COUNT(*) as sample_count,
    MIN(sample_time) as earliest_sample,
    MAX(sample_time) as latest_sample,
    EXTRACT(days FROM (MAX(sample_time) - MIN(sample_time))) as baseline_days
FROM baseline_pg_metrics;

-- Check for outliers (values beyond 3 standard deviations)
WITH stats AS (
    SELECT 
        AVG(active_connections) as avg_conn,
        STDDEV(active_connections) as std_conn
    FROM baseline_pg_metrics
)
SELECT 
    sample_time,
    active_connections,
    'OUTLIER' as flag
FROM baseline_pg_metrics, stats
WHERE active_connections > (avg_conn + 3 * std_conn)
   OR active_connections < (avg_conn - 3 * std_conn)
ORDER BY sample_time;

-- Validate baseline consistency
SELECT 
    DATE_TRUNC('day', sample_time) as day,
    COUNT(*) as samples_per_day,
    CASE 
        WHEN COUNT(*) < 288 THEN 'INCOMPLETE'  -- Less than 5-minute intervals
        ELSE 'COMPLETE'
    END as status
FROM baseline_pg_metrics
GROUP BY DATE_TRUNC('day', sample_time)
ORDER BY day;
```

## Best Practices Summary

### 1. Baseline Collection
- **Duration**: Minimum 14 days, preferably 30 days for initial baseline
- **Frequency**: Collect metrics every 1-5 minutes for detailed analysis
- **Coverage**: Include all environments (Dev, Test, Production)
- **Documentation**: Record all configuration changes during baseline period

### 2. Metric Selection
- **Resource Metrics**: CPU, Memory, Storage, Network I/O
- **Performance Metrics**: Query response time, throughput, concurrency
- **Application Metrics**: Business transaction volume, user sessions
- **Error Metrics**: Failed connections, query errors, timeouts

### 3. Threshold Setting
- **Warning Thresholds**: Mean + 1.5 * Standard Deviation
- **Critical Thresholds**: Mean + 2.5 * Standard Deviation  
- **Percentile-Based**: Use 95th percentile for capacity planning
- **Business Context**: Adjust thresholds based on business requirements

### 4. Maintenance
- **Regular Updates**: Refresh baselines quarterly or after major changes
- **Seasonal Adjustments**: Account for known business cycles
- **Validation**: Regularly check baseline data quality and completeness
- **Documentation**: Maintain change log for all baseline modifications