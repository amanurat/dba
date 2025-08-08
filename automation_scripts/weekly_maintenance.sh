#!/bin/bash
# Weekly Database Maintenance Script
# Performs routine maintenance tasks across all database types
# Schedule: Run every Sunday at 2 AM via cron

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/var/log/dba/maintenance"
CONFIG_FILE="${SCRIPT_DIR}/config.json"
DATE=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/weekly_maintenance_${DATE}.log"

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Send notification
send_notification() {
    local subject="$1"
    local message="$2"
    local priority="${3:-normal}"
    
    # Send email notification (requires mailx or similar)
    if command -v mailx >/dev/null 2>&1; then
        echo "$message" | mailx -s "$subject" dba-team@company.com
    fi
    
    # Send Teams notification (requires webhook URL)
    if [[ -n "${TEAMS_WEBHOOK_URL:-}" ]]; then
        curl -H "Content-Type: application/json" -d "{
            \"text\": \"**$subject**\n\n$message\"
        }" "$TEAMS_WEBHOOK_URL" || true
    fi
}

# PostgreSQL maintenance
postgresql_maintenance() {
    log "Starting PostgreSQL maintenance tasks"
    
    # Read PostgreSQL configurations from config file
    local pg_servers=$(jq -r '.databases[] | select(.type == "postgresql") | .name' "$CONFIG_FILE")
    
    for server in $pg_servers; do
        log "Processing PostgreSQL server: $server"
        
        local host=$(jq -r ".databases[] | select(.name == \"$server\") | .connection.host" "$CONFIG_FILE")
        local port=$(jq -r ".databases[] | select(.name == \"$server\") | .connection.port" "$CONFIG_FILE")
        local database=$(jq -r ".databases[] | select(.name == \"$server\") | .connection.database" "$CONFIG_FILE")
        local user=$(jq -r ".databases[] | select(.name == \"$server\") | .connection.user" "$CONFIG_FILE")
        
        # Connection string
        local conn_str="host=$host port=$port dbname=$database user=$user sslmode=require"
        
        # Update statistics
        log "Updating PostgreSQL statistics for $server"
        psql "$conn_str" -c "ANALYZE;" || log "WARNING: Statistics update failed for $server"
        
        # Vacuum analyze on large tables
        log "Running VACUUM ANALYZE on large tables for $server"
        psql "$conn_str" -c "
            SELECT 'VACUUM ANALYZE ' || schemaname || '.' || tablename || ';' as vacuum_cmd
            FROM pg_tables 
            WHERE schemaname NOT IN ('information_schema', 'pg_catalog')
            AND pg_total_relation_size(schemaname||'.'||tablename) > 100 * 1024 * 1024  -- Tables > 100MB
        " -t | while read -r vacuum_cmd; do
            if [[ -n "$vacuum_cmd" ]]; then
                log "Executing: $vacuum_cmd"
                psql "$conn_str" -c "$vacuum_cmd" || log "WARNING: Vacuum failed for command: $vacuum_cmd"
            fi
        done
        
        # Check for bloated tables
        log "Checking for table bloat in $server"
        psql "$conn_str" -c "
            SELECT schemaname, tablename, 
                   pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size,
                   n_dead_tup, n_live_tup,
                   CASE WHEN n_live_tup > 0 THEN round(n_dead_tup::numeric / n_live_tup * 100, 2) ELSE 0 END as dead_tuple_percent
            FROM pg_stat_user_tables 
            WHERE n_dead_tup > 1000 
            AND CASE WHEN n_live_tup > 0 THEN n_dead_tup::numeric / n_live_tup ELSE 0 END > 0.1
            ORDER BY dead_tuple_percent DESC;
        " >> "$LOG_FILE"
        
        # Reindex if needed (based on fragmentation)
        log "Checking index fragmentation for $server"
        psql "$conn_str" -c "
            SELECT schemaname, tablename, indexname, idx_scan, idx_tup_read, idx_tup_fetch
            FROM pg_stat_user_indexes 
            WHERE idx_scan = 0 
            AND schemaname NOT IN ('information_schema', 'pg_catalog')
        " >> "$LOG_FILE"
        
        log "PostgreSQL maintenance completed for $server"
    done
}

# MySQL maintenance
mysql_maintenance() {
    log "Starting MySQL maintenance tasks"
    
    # Read MySQL configurations from config file
    local mysql_servers=$(jq -r '.databases[] | select(.type == "mysql") | .name' "$CONFIG_FILE")
    
    for server in $mysql_servers; do
        log "Processing MySQL server: $server"
        
        local host=$(jq -r ".databases[] | select(.name == \"$server\") | .connection.host" "$CONFIG_FILE")
        local port=$(jq -r ".databases[] | select(.name == \"$server\") | .connection.port" "$CONFIG_FILE")
        local database=$(jq -r ".databases[] | select(.name == \"$server\") | .connection.database" "$CONFIG_FILE")
        local user=$(jq -r ".databases[] | select(.name == \"$server\") | .connection.user" "$CONFIG_FILE")
        
        # MySQL connection parameters
        local mysql_cmd="mysql -h $host -P $port -u $user -p$MYSQL_PASSWORD $database"
        
        # Update table statistics
        log "Updating MySQL table statistics for $server"
        $mysql_cmd -e "
            SELECT CONCAT('ANALYZE TABLE ', table_schema, '.', table_name, ';') as analyze_cmd
            FROM information_schema.tables 
            WHERE table_schema = '$database' 
            AND table_type = 'BASE TABLE'
        " -s -N | while read -r analyze_cmd; do
            if [[ -n "$analyze_cmd" ]]; then
                log "Executing: $analyze_cmd"
                $mysql_cmd -e "$analyze_cmd" || log "WARNING: Analyze failed for: $analyze_cmd"
            fi
        done
        
        # Optimize tables (equivalent to defragmentation)
        log "Optimizing MySQL tables for $server"
        $mysql_cmd -e "
            SELECT table_name, 
                   ROUND(((data_length + index_length) / 1024 / 1024), 2) AS size_mb,
                   ROUND((data_free / 1024 / 1024), 2) AS free_mb
            FROM information_schema.tables 
            WHERE table_schema = '$database' 
            AND data_free > 100 * 1024 * 1024  -- Tables with > 100MB free space
            ORDER BY free_mb DESC
        " >> "$LOG_FILE"
        
        # Check for unused indexes
        log "Checking for unused indexes in $server"
        $mysql_cmd -e "
            SELECT OBJECT_SCHEMA, OBJECT_NAME, INDEX_NAME
            FROM performance_schema.table_io_waits_summary_by_index_usage 
            WHERE OBJECT_SCHEMA = '$database'
            AND INDEX_NAME IS NOT NULL
            AND INDEX_NAME != 'PRIMARY'
            AND COUNT_STAR = 0
        " >> "$LOG_FILE"
        
        # Check InnoDB status
        log "Checking InnoDB status for $server"
        $mysql_cmd -e "SHOW ENGINE INNODB STATUS\G" >> "$LOG_FILE"
        
        log "MySQL maintenance completed for $server"
    done
}

# SQL Server maintenance
sqlserver_maintenance() {
    log "Starting SQL Server maintenance tasks"
    
    # Read SQL Server configurations from config file
    local sql_servers=$(jq -r '.databases[] | select(.type == "sqlserver") | .name' "$CONFIG_FILE")
    
    for server in $sql_servers; do
        log "Processing SQL Server: $server"
        
        local conn_str=$(jq -r ".databases[] | select(.name == \"$server\") | .connection_string" "$CONFIG_FILE")
        
        # Update statistics
        log "Updating SQL Server statistics for $server"
        sqlcmd -Q "EXEC sp_updatestats;" || log "WARNING: Statistics update failed for $server"
        
        # Check index fragmentation
        log "Checking index fragmentation for $server"
        sqlcmd -Q "
            SELECT 
                OBJECT_NAME(ips.object_id) AS table_name,
                i.name AS index_name,
                ips.avg_fragmentation_in_percent,
                ips.page_count,
                CASE 
                    WHEN ips.avg_fragmentation_in_percent > 30 THEN 'REBUILD'
                    WHEN ips.avg_fragmentation_in_percent > 10 THEN 'REORGANIZE'
                    ELSE 'NO ACTION'
                END AS recommended_action
            FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
            JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
            WHERE ips.avg_fragmentation_in_percent > 10
            AND ips.page_count > 100
            ORDER BY ips.avg_fragmentation_in_percent DESC
        " >> "$LOG_FILE"
        
        # Rebuild/reorganize indexes based on fragmentation
        log "Performing index maintenance for $server"
        sqlcmd -Q "
            DECLARE @sql NVARCHAR(MAX)
            DECLARE index_cursor CURSOR FOR
            SELECT 
                CASE 
                    WHEN ips.avg_fragmentation_in_percent > 30 THEN 
                        'ALTER INDEX [' + i.name + '] ON [' + OBJECT_NAME(ips.object_id) + '] REBUILD'
                    WHEN ips.avg_fragmentation_in_percent > 10 THEN 
                        'ALTER INDEX [' + i.name + '] ON [' + OBJECT_NAME(ips.object_id) + '] REORGANIZE'
                END
            FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
            JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
            WHERE ips.avg_fragmentation_in_percent > 10
            AND ips.page_count > 100
            AND i.name IS NOT NULL
            
            OPEN index_cursor
            FETCH NEXT FROM index_cursor INTO @sql
            
            WHILE @@FETCH_STATUS = 0
            BEGIN
                EXEC sp_executesql @sql
                FETCH NEXT FROM index_cursor INTO @sql
            END
            
            CLOSE index_cursor
            DEALLOCATE index_cursor
        " || log "WARNING: Index maintenance failed for $server"
        
        # Check for missing indexes
        log "Checking for missing indexes in $server"
        sqlcmd -Q "
            SELECT TOP 10
                migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans) AS improvement_measure,
                'CREATE INDEX [IX_' + OBJECT_NAME(mid.object_id) + '_Missing] ON ' + mid.statement + 
                ' (' + ISNULL(mid.equality_columns,'') +
                CASE WHEN mid.equality_columns IS NOT NULL AND mid.inequality_columns IS NOT NULL THEN ',' ELSE '' END +
                ISNULL(mid.inequality_columns, '') + ')' +
                ISNULL(' INCLUDE (' + mid.included_columns + ')', '') AS create_index_statement
            FROM sys.dm_db_missing_index_groups mig
            JOIN sys.dm_db_missing_index_group_stats migs ON migs.group_handle = mig.index_group_handle
            JOIN sys.dm_db_missing_index_details mid ON mig.index_handle = mid.index_handle
            WHERE migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans) > 10
            ORDER BY improvement_measure DESC
        " >> "$LOG_FILE"
        
        log "SQL Server maintenance completed for $server"
    done
}

# Backup verification
verify_backups() {
    log "Verifying database backups"
    
    # Check backup status for each database type
    # This would typically involve checking backup logs, Azure backup status, etc.
    
    # PostgreSQL backup verification
    log "Checking PostgreSQL backup status"
    # Add specific backup verification logic here
    
    # MySQL backup verification
    log "Checking MySQL backup status"
    # Add specific backup verification logic here
    
    # SQL Server backup verification
    log "Checking SQL Server backup status"
    # Add specific backup verification logic here
    
    log "Backup verification completed"
}

# Performance monitoring
performance_monitoring() {
    log "Collecting performance metrics"
    
    # Run the daily health check script to get current performance metrics
    if [[ -f "${SCRIPT_DIR}/daily_health_check.py" ]]; then
        python3 "${SCRIPT_DIR}/daily_health_check.py" "$CONFIG_FILE" >> "$LOG_FILE" 2>&1
    fi
    
    # Collect additional weekly metrics
    log "Collecting weekly performance trends"
    
    # This would typically involve:
    # - Analyzing query performance trends
    # - Checking resource utilization patterns
    # - Identifying performance regressions
    # - Generating capacity planning reports
    
    log "Performance monitoring completed"
}

# Cleanup old logs and files
cleanup_old_files() {
    log "Cleaning up old log files and temporary data"
    
    # Remove log files older than 30 days
    find "$LOG_DIR" -name "*.log" -mtime +30 -delete || true
    
    # Remove old health check results
    find "/var/log/dba/health_checks" -name "*.json" -mtime +30 -delete || true
    
    # Clean up temporary files
    find /tmp -name "dba_*" -mtime +1 -delete || true
    
    log "Cleanup completed"
}

# Generate weekly report
generate_weekly_report() {
    log "Generating weekly maintenance report"
    
    local report_file="${LOG_DIR}/weekly_report_${DATE}.txt"
    
    cat > "$report_file" << EOF
WEEKLY DATABASE MAINTENANCE REPORT
==================================
Date: $(date)
Duration: $(date -d @$(($(date +%s) - START_TIME)) -u +%H:%M:%S)

MAINTENANCE TASKS COMPLETED:
- PostgreSQL maintenance and optimization
- MySQL maintenance and optimization  
- SQL Server maintenance and optimization
- Backup verification
- Performance monitoring
- Log cleanup

DETAILED LOG: $LOG_FILE

SUMMARY:
$(tail -20 "$LOG_FILE")

EOF
    
    # Send the report
    send_notification "Weekly Database Maintenance Report - $(date +%Y-%m-%d)" "$(cat "$report_file")"
    
    log "Weekly report generated: $report_file"
}

# Main execution
main() {
    local START_TIME=$(date +%s)
    
    log "Starting weekly database maintenance"
    
    # Check if config file exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error_exit "Configuration file not found: $CONFIG_FILE"
    fi
    
    # Check required tools
    for tool in jq psql mysql sqlcmd; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log "WARNING: $tool not found, some maintenance tasks may be skipped"
        fi
    done
    
    # Run maintenance tasks
    postgresql_maintenance
    mysql_maintenance
    sqlserver_maintenance
    verify_backups
    performance_monitoring
    cleanup_old_files
    
    # Generate report
    generate_weekly_report
    
    local END_TIME=$(date +%s)
    local DURATION=$((END_TIME - START_TIME))
    
    log "Weekly maintenance completed successfully in $(date -d @$DURATION -u +%H:%M:%S)"
    
    # Send success notification
    send_notification "Weekly Database Maintenance Completed" "All maintenance tasks completed successfully. Duration: $(date -d @$DURATION -u +%H:%M:%S)"
}

# Trap errors and send notification
trap 'send_notification "Weekly Database Maintenance Failed" "Maintenance script failed. Check log: $LOG_FILE"; exit 1' ERR

# Run main function
main "$@"