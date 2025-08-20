-- 1) Workload Characterization
/*
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
*/


-- 2) Workload Characterization
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

-- 3) Configuration Documentation
/*
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
 */


-- ### PostgreSQL Baseline####
-- 1.Performance Metrics Collection
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

-- 2. Query Performance Baseline
-- Top queries baseline (requires pg_stat_statements)
CREATE TABLE IF NOT EXISTS baseline_pg_queries AS
SELECT
    now() as baseline_date,
    query,
    calls,
    total_exec_time,
    mean_exec_time,
    rows,
    100.0 * shared_blks_hit / nullif(shared_blks_hit + shared_blks_read, 0) as hit_percent
FROM pg_stat_statements
WHERE calls > 100  -- Only frequently executed queries
ORDER BY total_exec_time DESC
LIMIT 50;

-- Reset statistics after baseline period
-- SELECT pg_stat_statements_reset();

-- 3. System Resource Baseline
/*
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

*/

-- ### Baseline Analysis and Reporting ####
-- 1. PostgreSQL baseline analysis
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
    ROUND(avg_value::numeric, 2) as average,
    ROUND(min_value::numeric, 2) as minimum,
    ROUND(max_value::numeric, 2) as maximum,
    ROUND(std_dev::numeric, 2) as std_deviation,
    ROUND(p95_value::numeric, 2) as percentile_95,
    ROUND((avg_value + (2 * std_dev))::numeric, 2) as upper_threshold,
    ROUND((avg_value - (2 * std_dev))::numeric, 2) as lower_threshold
FROM baseline_stats;


-- 2. Baseline Report Generation
/*

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


 */


-- 3. Threshold Calculation
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
            AVG(value)::NUMERIC as avg_value,
            STDDEV(value)::NUMERIC as std_dev,
            (AVG(value) + (1.5 * STDDEV(value)))::NUMERIC as warning_threshold,
            (AVG(value) + (2.5 * STDDEV(value)))::NUMERIC as critical_threshold,
            PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY value)::NUMERIC as p95_threshold
        FROM (
                 SELECT active_connections::NUMERIC as value
                 FROM baseline_pg_metrics
                 WHERE sample_time >= NOW() - (baseline_days || ' days')::INTERVAL
                   AND metric_name = 'active_connections'

                 UNION ALL

                 SELECT cache_hit_ratio::NUMERIC as value
                 FROM baseline_pg_metrics
                 WHERE sample_time >= NOW() - (baseline_days || ' days')::INTERVAL
                   AND metric_name = 'cache_hit_ratio'
             ) baseline_data;
END;
$$ LANGUAGE plpgsql;


-- Example usage
SELECT * FROM calculate_thresholds('active_connections', 30);



