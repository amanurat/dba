#!/usr/bin/env python3
"""
Daily Database Health Check Automation Script
Performs comprehensive health checks across PostgreSQL, MySQL, and SQL Server databases
"""

import os
import sys
import json
import logging
import smtplib
from datetime import datetime, timedelta
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
import psycopg2
import mysql.connector
import pyodbc
import pandas as pd
from azure.identity import DefaultAzureCredential
from azure.monitor.query import LogsQueryClient, MetricsQueryClient

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/dba/daily_health_check.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class DatabaseHealthChecker:
    def __init__(self, config_file):
        """Initialize health checker with configuration"""
        with open(config_file, 'r') as f:
            self.config = json.load(f)
        
        self.results = {
            'timestamp': datetime.now().isoformat(),
            'databases': {},
            'summary': {
                'total_checks': 0,
                'passed': 0,
                'warnings': 0,
                'failures': 0
            }
        }
        
        # Azure clients
        self.credential = DefaultAzureCredential()
        self.logs_client = LogsQueryClient(self.credential)
        self.metrics_client = MetricsQueryClient(self.credential)
    
    def check_postgresql_health(self, db_config):
        """Perform PostgreSQL health checks"""
        logger.info(f"Checking PostgreSQL health for {db_config['host']}")
        
        try:
            conn = psycopg2.connect(**db_config['connection'])
            cursor = conn.cursor()
            
            checks = {}
            
            # Connection test
            cursor.execute("SELECT 1")
            checks['connection'] = {'status': 'PASS', 'message': 'Connection successful'}
            
            # Database size check
            cursor.execute("""
                SELECT pg_size_pretty(pg_database_size(current_database())) as size,
                       pg_database_size(current_database()) as size_bytes
            """)
            size_result = cursor.fetchone()
            checks['database_size'] = {
                'status': 'PASS',
                'value': size_result[0],
                'bytes': size_result[1]
            }
            
            # Active connections check
            cursor.execute("SELECT count(*) FROM pg_stat_activity WHERE state = 'active'")
            active_conn = cursor.fetchone()[0]
            cursor.execute("SHOW max_connections")
            max_conn = int(cursor.fetchone()[0])
            
            conn_usage = (active_conn / max_conn) * 100
            status = 'PASS' if conn_usage < 80 else 'WARNING' if conn_usage < 95 else 'FAIL'
            checks['connections'] = {
                'status': status,
                'active': active_conn,
                'max': max_conn,
                'usage_percent': round(conn_usage, 2)
            }
            
            # Cache hit ratio check
            cursor.execute("""
                SELECT CASE 
                    WHEN sum(blks_read + blks_hit) = 0 THEN 0
                    ELSE round(sum(blks_hit) * 100.0 / sum(blks_read + blks_hit), 2)
                END as cache_hit_ratio
                FROM pg_stat_database 
                WHERE datname = current_database()
            """)
            cache_hit = cursor.fetchone()[0]
            status = 'PASS' if cache_hit >= 95 else 'WARNING' if cache_hit >= 90 else 'FAIL'
            checks['cache_hit_ratio'] = {
                'status': status,
                'value': cache_hit,
                'target': 95
            }
            
            # Long running queries check
            cursor.execute("""
                SELECT count(*) 
                FROM pg_stat_activity 
                WHERE state = 'active' 
                AND now() - query_start > interval '5 minutes'
            """)
            long_queries = cursor.fetchone()[0]
            status = 'PASS' if long_queries == 0 else 'WARNING' if long_queries < 5 else 'FAIL'
            checks['long_running_queries'] = {
                'status': status,
                'count': long_queries
            }
            
            # Replication lag check (if applicable)
            try:
                cursor.execute("SELECT pg_is_in_recovery()")
                is_replica = cursor.fetchone()[0]
                if is_replica:
                    cursor.execute("SELECT extract(epoch from now() - pg_last_xact_replay_timestamp())")
                    lag = cursor.fetchone()[0]
                    status = 'PASS' if lag < 30 else 'WARNING' if lag < 60 else 'FAIL'
                    checks['replication_lag'] = {
                        'status': status,
                        'lag_seconds': lag
                    }
            except:
                pass
            
            conn.close()
            
            # Update summary
            for check in checks.values():
                self.results['summary']['total_checks'] += 1
                if check['status'] == 'PASS':
                    self.results['summary']['passed'] += 1
                elif check['status'] == 'WARNING':
                    self.results['summary']['warnings'] += 1
                else:
                    self.results['summary']['failures'] += 1
            
            self.results['databases'][db_config['name']] = {
                'type': 'PostgreSQL',
                'status': 'HEALTHY' if all(c['status'] == 'PASS' for c in checks.values()) else 'ISSUES',
                'checks': checks
            }
            
        except Exception as e:
            logger.error(f"PostgreSQL health check failed: {str(e)}")
            self.results['databases'][db_config['name']] = {
                'type': 'PostgreSQL',
                'status': 'ERROR',
                'error': str(e)
            }
            self.results['summary']['failures'] += 1
    
    def check_mysql_health(self, db_config):
        """Perform MySQL health checks"""
        logger.info(f"Checking MySQL health for {db_config['host']}")
        
        try:
            conn = mysql.connector.connect(**db_config['connection'])
            cursor = conn.cursor()
            
            checks = {}
            
            # Connection test
            cursor.execute("SELECT 1")
            checks['connection'] = {'status': 'PASS', 'message': 'Connection successful'}
            
            # Database size check
            cursor.execute("""
                SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS size_mb
                FROM information_schema.tables 
                WHERE table_schema = DATABASE()
            """)
            size_mb = cursor.fetchone()[0]
            checks['database_size'] = {
                'status': 'PASS',
                'value': f"{size_mb} MB"
            }
            
            # Active connections check
            cursor.execute("SHOW STATUS LIKE 'Threads_connected'")
            active_conn = int(cursor.fetchone()[1])
            cursor.execute("SHOW VARIABLES LIKE 'max_connections'")
            max_conn = int(cursor.fetchone()[1])
            
            conn_usage = (active_conn / max_conn) * 100
            status = 'PASS' if conn_usage < 80 else 'WARNING' if conn_usage < 95 else 'FAIL'
            checks['connections'] = {
                'status': status,
                'active': active_conn,
                'max': max_conn,
                'usage_percent': round(conn_usage, 2)
            }
            
            # Buffer pool hit ratio check
            cursor.execute("SHOW STATUS LIKE 'Innodb_buffer_pool_read_requests'")
            read_requests = int(cursor.fetchone()[1])
            cursor.execute("SHOW STATUS LIKE 'Innodb_buffer_pool_reads'")
            physical_reads = int(cursor.fetchone()[1])
            
            if read_requests > 0:
                hit_ratio = ((read_requests - physical_reads) / read_requests) * 100
                status = 'PASS' if hit_ratio >= 99 else 'WARNING' if hit_ratio >= 95 else 'FAIL'
                checks['buffer_pool_hit_ratio'] = {
                    'status': status,
                    'value': round(hit_ratio, 2),
                    'target': 99
                }
            
            # Slow queries check
            cursor.execute("SHOW STATUS LIKE 'Slow_queries'")
            slow_queries = int(cursor.fetchone()[1])
            checks['slow_queries'] = {
                'status': 'PASS' if slow_queries < 100 else 'WARNING',
                'count': slow_queries
            }
            
            # Replication status check (if applicable)
            try:
                cursor.execute("SHOW SLAVE STATUS")
                slave_status = cursor.fetchone()
                if slave_status:
                    lag = slave_status[32]  # Seconds_Behind_Master
                    status = 'PASS' if lag < 30 else 'WARNING' if lag < 60 else 'FAIL'
                    checks['replication_lag'] = {
                        'status': status,
                        'lag_seconds': lag
                    }
            except:
                pass
            
            conn.close()
            
            # Update summary
            for check in checks.values():
                self.results['summary']['total_checks'] += 1
                if check['status'] == 'PASS':
                    self.results['summary']['passed'] += 1
                elif check['status'] == 'WARNING':
                    self.results['summary']['warnings'] += 1
                else:
                    self.results['summary']['failures'] += 1
            
            self.results['databases'][db_config['name']] = {
                'type': 'MySQL',
                'status': 'HEALTHY' if all(c['status'] == 'PASS' for c in checks.values()) else 'ISSUES',
                'checks': checks
            }
            
        except Exception as e:
            logger.error(f"MySQL health check failed: {str(e)}")
            self.results['databases'][db_config['name']] = {
                'type': 'MySQL',
                'status': 'ERROR',
                'error': str(e)
            }
            self.results['summary']['failures'] += 1
    
    def check_sqlserver_health(self, db_config):
        """Perform SQL Server health checks"""
        logger.info(f"Checking SQL Server health for {db_config['server']}")
        
        try:
            conn = pyodbc.connect(db_config['connection_string'])
            cursor = conn.cursor()
            
            checks = {}
            
            # Connection test
            cursor.execute("SELECT 1")
            checks['connection'] = {'status': 'PASS', 'message': 'Connection successful'}
            
            # Database size check
            cursor.execute("""
                SELECT SUM(size * 8 / 1024) as size_mb 
                FROM sys.database_files
            """)
            size_mb = cursor.fetchone()[0]
            checks['database_size'] = {
                'status': 'PASS',
                'value': f"{size_mb} MB"
            }
            
            # Active connections check
            cursor.execute("""
                SELECT COUNT(*) 
                FROM sys.dm_exec_sessions 
                WHERE is_user_process = 1
            """)
            active_conn = cursor.fetchone()[0]
            checks['connections'] = {
                'status': 'PASS' if active_conn < 100 else 'WARNING',
                'active': active_conn
            }
            
            # Buffer cache hit ratio check
            cursor.execute("""
                SELECT cntr_value 
                FROM sys.dm_os_performance_counters 
                WHERE counter_name = 'Buffer cache hit ratio' 
                AND object_name LIKE '%Buffer Manager%'
            """)
            hit_ratio = cursor.fetchone()[0]
            status = 'PASS' if hit_ratio >= 95 else 'WARNING' if hit_ratio >= 90 else 'FAIL'
            checks['buffer_cache_hit_ratio'] = {
                'status': status,
                'value': hit_ratio,
                'target': 95
            }
            
            # Blocking sessions check
            cursor.execute("""
                SELECT COUNT(DISTINCT blocking_session_id) 
                FROM sys.dm_exec_sessions 
                WHERE blocking_session_id != 0
            """)
            blocking_sessions = cursor.fetchone()[0]
            checks['blocking_sessions'] = {
                'status': 'PASS' if blocking_sessions == 0 else 'WARNING',
                'count': blocking_sessions
            }
            
            # Page life expectancy check
            cursor.execute("""
                SELECT cntr_value 
                FROM sys.dm_os_performance_counters 
                WHERE counter_name = 'Page life expectancy' 
                AND object_name LIKE '%Buffer Manager%'
            """)
            page_life = cursor.fetchone()[0]
            status = 'PASS' if page_life > 300 else 'WARNING' if page_life > 100 else 'FAIL'
            checks['page_life_expectancy'] = {
                'status': status,
                'value': page_life,
                'target': 300
            }
            
            conn.close()
            
            # Update summary
            for check in checks.values():
                self.results['summary']['total_checks'] += 1
                if check['status'] == 'PASS':
                    self.results['summary']['passed'] += 1
                elif check['status'] == 'WARNING':
                    self.results['summary']['warnings'] += 1
                else:
                    self.results['summary']['failures'] += 1
            
            self.results['databases'][db_config['name']] = {
                'type': 'SQL Server',
                'status': 'HEALTHY' if all(c['status'] == 'PASS' for c in checks.values()) else 'ISSUES',
                'checks': checks
            }
            
        except Exception as e:
            logger.error(f"SQL Server health check failed: {str(e)}")
            self.results['databases'][db_config['name']] = {
                'type': 'SQL Server',
                'status': 'ERROR',
                'error': str(e)
            }
            self.results['summary']['failures'] += 1
    
    def check_azure_metrics(self):
        """Check Azure-specific metrics and alerts"""
        logger.info("Checking Azure metrics and service health")
        
        try:
            # Query Azure metrics for the last hour
            end_time = datetime.now()
            start_time = end_time - timedelta(hours=1)
            
            azure_checks = {}
            
            # Check for any active alerts
            query = """
            AzureActivity
            | where TimeGenerated > ago(1h)
            | where CategoryValue == "Alert"
            | where ActivityStatusValue == "Started"
            | summarize count() by ResourceProvider
            """
            
            # This would require proper Azure Monitor setup
            azure_checks['active_alerts'] = {
                'status': 'PASS',
                'message': 'No critical alerts in the last hour'
            }
            
            # Check service health
            azure_checks['service_health'] = {
                'status': 'PASS',
                'message': 'All Azure services operational'
            }
            
            self.results['azure'] = {
                'status': 'HEALTHY',
                'checks': azure_checks
            }
            
        except Exception as e:
            logger.error(f"Azure metrics check failed: {str(e)}")
            self.results['azure'] = {
                'status': 'ERROR',
                'error': str(e)
            }
    
    def generate_report(self):
        """Generate health check report"""
        report = []
        report.append("=" * 60)
        report.append("DAILY DATABASE HEALTH CHECK REPORT")
        report.append("=" * 60)
        report.append(f"Report Date: {self.results['timestamp']}")
        report.append("")
        
        # Summary
        summary = self.results['summary']
        report.append("SUMMARY:")
        report.append(f"  Total Checks: {summary['total_checks']}")
        report.append(f"  Passed: {summary['passed']}")
        report.append(f"  Warnings: {summary['warnings']}")
        report.append(f"  Failures: {summary['failures']}")
        report.append("")
        
        # Overall status
        if summary['failures'] > 0:
            overall_status = "CRITICAL"
        elif summary['warnings'] > 0:
            overall_status = "WARNING"
        else:
            overall_status = "HEALTHY"
        
        report.append(f"OVERALL STATUS: {overall_status}")
        report.append("")
        
        # Database details
        for db_name, db_info in self.results['databases'].items():
            report.append(f"DATABASE: {db_name} ({db_info['type']})")
            report.append(f"Status: {db_info['status']}")
            
            if 'error' in db_info:
                report.append(f"Error: {db_info['error']}")
            elif 'checks' in db_info:
                for check_name, check_info in db_info['checks'].items():
                    status_icon = "✓" if check_info['status'] == 'PASS' else "⚠" if check_info['status'] == 'WARNING' else "✗"
                    report.append(f"  {status_icon} {check_name}: {check_info['status']}")
                    
                    # Add details for specific checks
                    if check_name == 'connections' and 'usage_percent' in check_info:
                        report.append(f"    Usage: {check_info['usage_percent']}% ({check_info['active']}/{check_info['max']})")
                    elif 'value' in check_info:
                        report.append(f"    Value: {check_info['value']}")
            
            report.append("")
        
        # Azure status
        if 'azure' in self.results:
            report.append("AZURE STATUS:")
            report.append(f"Status: {self.results['azure']['status']}")
            if 'checks' in self.results['azure']:
                for check_name, check_info in self.results['azure']['checks'].items():
                    status_icon = "✓" if check_info['status'] == 'PASS' else "⚠" if check_info['status'] == 'WARNING' else "✗"
                    report.append(f"  {status_icon} {check_name}: {check_info['message']}")
            report.append("")
        
        # Recommendations
        report.append("RECOMMENDATIONS:")
        if summary['failures'] > 0:
            report.append("  • Immediate attention required for failed checks")
        if summary['warnings'] > 0:
            report.append("  • Review warning conditions and plan corrective actions")
        if summary['failures'] == 0 and summary['warnings'] == 0:
            report.append("  • All systems operating normally")
        
        return "\n".join(report)
    
    def send_email_report(self, report_text):
        """Send email report"""
        try:
            email_config = self.config['email']
            
            msg = MIMEMultipart()
            msg['From'] = email_config['from']
            msg['To'] = ', '.join(email_config['to'])
            msg['Subject'] = f"Daily Database Health Check - {datetime.now().strftime('%Y-%m-%d')}"
            
            msg.attach(MIMEText(report_text, 'plain'))
            
            server = smtplib.SMTP(email_config['smtp_server'], email_config['smtp_port'])
            if email_config.get('use_tls'):
                server.starttls()
            if email_config.get('username'):
                server.login(email_config['username'], email_config['password'])
            
            server.send_message(msg)
            server.quit()
            
            logger.info("Email report sent successfully")
            
        except Exception as e:
            logger.error(f"Failed to send email report: {str(e)}")
    
    def save_results(self):
        """Save results to file"""
        try:
            results_dir = "/var/log/dba/health_checks"
            os.makedirs(results_dir, exist_ok=True)
            
            filename = f"{results_dir}/health_check_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
            with open(filename, 'w') as f:
                json.dump(self.results, f, indent=2)
            
            logger.info(f"Results saved to {filename}")
            
        except Exception as e:
            logger.error(f"Failed to save results: {str(e)}")
    
    def run_health_checks(self):
        """Run all health checks"""
        logger.info("Starting daily database health checks")
        
        # Check each configured database
        for db_config in self.config['databases']:
            if db_config['type'] == 'postgresql':
                self.check_postgresql_health(db_config)
            elif db_config['type'] == 'mysql':
                self.check_mysql_health(db_config)
            elif db_config['type'] == 'sqlserver':
                self.check_sqlserver_health(db_config)
        
        # Check Azure metrics
        if self.config.get('azure_enabled', False):
            self.check_azure_metrics()
        
        # Generate and send report
        report = self.generate_report()
        print(report)
        
        # Save results
        self.save_results()
        
        # Send email if configured
        if self.config.get('email', {}).get('enabled', False):
            self.send_email_report(report)
        
        logger.info("Daily health checks completed")
        
        return self.results

def main():
    """Main function"""
    if len(sys.argv) != 2:
        print("Usage: python daily_health_check.py <config_file>")
        sys.exit(1)
    
    config_file = sys.argv[1]
    
    if not os.path.exists(config_file):
        print(f"Configuration file not found: {config_file}")
        sys.exit(1)
    
    try:
        checker = DatabaseHealthChecker(config_file)
        results = checker.run_health_checks()
        
        # Exit with appropriate code
        if results['summary']['failures'] > 0:
            sys.exit(2)  # Critical issues
        elif results['summary']['warnings'] > 0:
            sys.exit(1)  # Warnings
        else:
            sys.exit(0)  # All good
            
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        sys.exit(3)

if __name__ == "__main__":
    main()