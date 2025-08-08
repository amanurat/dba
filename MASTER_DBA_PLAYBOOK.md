# Master DBA Playbook for Azure Multi-Database Environment

## Table of Contents
1. [Executive Summary](#executive-summary)
2. [Environment Overview](#environment-overview)
3. [Quick Reference Guide](#quick-reference-guide)
4. [Daily Operations](#daily-operations)
5. [Weekly Maintenance](#weekly-maintenance)
6. [Monthly Reviews](#monthly-reviews)
7. [Incident Response](#incident-response)
8. [Performance Tuning Workflow](#performance-tuning-workflow)
9. [Monitoring and Alerting](#monitoring-and-alerting)
10. [Automation Framework](#automation-framework)
11. [Best Practices Summary](#best-practices-summary)
12. [Documentation Index](#documentation-index)

## Executive Summary

This master playbook provides comprehensive guidance for managing PostgreSQL, MySQL, and SQL Server databases on Azure. It consolidates all operational procedures, performance tuning strategies, monitoring approaches, and automation frameworks into a single reference document.

### Key Objectives
- **Performance Excellence**: Achieve 25% improvement in database performance
- **Operational Efficiency**: Reduce manual tasks by 80% through automation
- **Proactive Monitoring**: Detect and resolve issues before they impact users
- **Cost Optimization**: Optimize resource utilization and reduce costs by 15-20%

### Success Metrics
- **Availability**: >99.9% uptime for production databases
- **Performance**: <2 second response time for 95% of queries
- **Alert Response**: <5 minutes for critical alerts
- **Automation Coverage**: 80% of routine tasks automated

## Environment Overview

### Database Inventory
| Database Type | Environment | Count | Primary Use Case |
|---------------|-------------|-------|------------------|
| PostgreSQL | Production | 3 | OLTP Applications |
| PostgreSQL | Development | 2 | Development/Testing |
| MySQL | Production | 2 | Web Applications |
| MySQL | Development | 1 | Development/Testing |
| SQL Server | Production | 4 | Enterprise Applications |
| SQL Server | Development | 2 | Development/Testing |

### Azure Services Used
- **Azure Database for PostgreSQL**: Flexible Server
- **Azure Database for MySQL**: Flexible Server  
- **Azure SQL Database**: Standard and Premium tiers
- **Azure Monitor**: Metrics and log analytics
- **Azure Backup**: Automated backup solutions
- **Azure Key Vault**: Credential management

## Quick Reference Guide

### Emergency Contacts
- **DBA Team**: dba-team@company.com
- **On-Call Engineer**: +1-555-0123
- **Azure Support**: Portal ticket system
- **Management Escalation**: management@company.com

### Critical Commands

#### PostgreSQL
```bash
# Check connections
psql -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';"

# Kill blocking query
psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE pid = <PID>;"

# Check replication lag
psql -c "SELECT extract(epoch from now() - pg_last_xact_replay_timestamp());"
```

#### MySQL
```bash
# Check connections
mysql -e "SHOW STATUS LIKE 'Threads_connected';"

# Kill blocking query
mysql -e "KILL <CONNECTION_ID>;"

# Check replication status
mysql -e "SHOW SLAVE STATUS\G"
```

#### SQL Server
```bash
# Check active connections
sqlcmd -Q "SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process = 1;"

# Kill blocking session
sqlcmd -Q "KILL <SESSION_ID>;"

# Check blocking chains
sqlcmd -Q "SELECT blocking_session_id, session_id FROM sys.dm_exec_sessions WHERE blocking_session_id != 0;"
```

### Performance Thresholds
| Metric | Warning | Critical | Action Required |
|--------|---------|----------|-----------------|
| CPU Usage | 70% | 85% | Scale up/optimize queries |
| Memory Usage | 80% | 90% | Increase memory/tune config |
| Storage Usage | 80% | 90% | Add storage/archive data |
| Connection Usage | 80% | 95% | Increase limits/optimize connections |
| Query Response Time | 2s | 5s | Optimize queries/add indexes |

## Daily Operations

### Morning Checklist (8:00 AM)
- [ ] **Run Daily Health Check Script**
  ```bash
  python3 /scripts/daily_health_check.py /config/production.json
  ```
- [ ] **Review Overnight Alerts**
  - Check Azure Monitor dashboard
  - Review email alerts from past 24 hours
  - Verify all critical alerts were addressed

- [ ] **Check Backup Status**
  - Verify all scheduled backups completed successfully
  - Review backup sizes and durations
  - Test restore capability (weekly rotation)

- [ ] **Performance Review**
  - Review slow query logs
  - Check resource utilization trends
  - Identify any performance regressions

### Midday Check (12:00 PM)
- [ ] **Monitor Peak Load Performance**
  - Check CPU and memory usage during peak hours
  - Monitor connection counts
  - Review query performance metrics

- [ ] **Capacity Planning Review**
  - Check storage growth rates
  - Monitor connection pool utilization
  - Review resource consumption trends

### Evening Wrap-up (6:00 PM)
- [ ] **Daily Report Generation**
  - Generate performance summary report
  - Document any issues encountered
  - Plan next day's activities

- [ ] **Prepare for Overnight Operations**
  - Schedule any maintenance tasks
  - Verify monitoring alerts are active
  - Confirm on-call coverage

## Weekly Maintenance

### Sunday Maintenance Window (2:00 AM - 6:00 AM)
- [ ] **Run Weekly Maintenance Script**
  ```bash
  /scripts/weekly_maintenance.sh
  ```

#### PostgreSQL Weekly Tasks
- [ ] **Statistics Update**
  ```sql
  ANALYZE;
  ```
- [ ] **Vacuum Large Tables**
  ```sql
  VACUUM ANALYZE table_name;
  ```
- [ ] **Index Maintenance**
  - Check for unused indexes
  - Identify missing indexes
  - Reindex fragmented indexes

- [ ] **Configuration Review**
  - Review postgresql.conf settings
  - Check for parameter drift
  - Validate memory settings

#### MySQL Weekly Tasks
- [ ] **Table Optimization**
  ```sql
  OPTIMIZE TABLE table_name;
  ```
- [ ] **Statistics Update**
  ```sql
  ANALYZE TABLE table_name;
  ```
- [ ] **InnoDB Status Check**
  ```sql
  SHOW ENGINE INNODB STATUS;
  ```

#### SQL Server Weekly Tasks
- [ ] **Index Maintenance**
  ```sql
  -- Check fragmentation
  SELECT * FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED');
  
  -- Rebuild/reorganize as needed
  ALTER INDEX ALL ON table_name REBUILD;
  ```
- [ ] **Statistics Update**
  ```sql
  EXEC sp_updatestats;
  ```
- [ ] **Query Store Cleanup**
  ```sql
  ALTER DATABASE [DB] SET QUERY_STORE CLEAR;
  ```

### Weekly Reporting
- [ ] **Performance Trend Analysis**
  - Generate weekly performance report
  - Identify performance trends
  - Document capacity planning recommendations

- [ ] **Security Review**
  - Review failed login attempts
  - Check for suspicious activity
  - Validate access permissions

## Monthly Reviews

### First Monday of Each Month
- [ ] **Comprehensive Performance Review**
  - Analyze monthly performance trends
  - Review and update performance baselines
  - Identify optimization opportunities

- [ ] **Capacity Planning Assessment**
  - Project resource needs for next quarter
  - Review storage growth patterns
  - Plan for seasonal variations

- [ ] **Configuration Audit**
  - Review all database configurations
  - Compare against best practices
  - Document any configuration changes

- [ ] **Security Audit**
  - Review user access and permissions
  - Check for compliance violations
  - Update security policies as needed

- [ ] **Disaster Recovery Testing**
  - Test backup restoration procedures
  - Validate failover processes
  - Update disaster recovery documentation

## Incident Response

### Severity Levels
- **P1 (Critical)**: Production down, data loss risk
- **P2 (High)**: Significant performance degradation
- **P3 (Medium)**: Minor issues, workaround available
- **P4 (Low)**: Cosmetic issues, no business impact

### P1 Incident Response (0-15 minutes)
1. **Immediate Assessment**
   - Identify affected systems and users
   - Determine root cause category
   - Engage incident commander

2. **Initial Response**
   - Implement immediate workarounds
   - Scale resources if needed
   - Notify stakeholders

3. **Escalation**
   - Engage Azure support if needed
   - Involve vendor support teams
   - Activate disaster recovery if required

### P2 Incident Response (0-30 minutes)
1. **Performance Analysis**
   - Run diagnostic queries
   - Check resource utilization
   - Identify bottlenecks

2. **Quick Fixes**
   - Kill blocking queries
   - Restart services if needed
   - Adjust configuration parameters

3. **Monitoring**
   - Increase monitoring frequency
   - Set up additional alerts
   - Track resolution progress

### Common Incident Scenarios

#### High CPU Usage
```bash
# PostgreSQL
psql -c "SELECT query, state, query_start FROM pg_stat_activity WHERE state = 'active' ORDER BY query_start;"

# MySQL  
mysql -e "SHOW PROCESSLIST;"

# SQL Server
sqlcmd -Q "SELECT session_id, status, command, cpu_time, total_elapsed_time FROM sys.dm_exec_requests WHERE status = 'running';"
```

#### Connection Limit Reached
```bash
# PostgreSQL
psql -c "SELECT count(*), state FROM pg_stat_activity GROUP BY state;"

# MySQL
mysql -e "SHOW STATUS LIKE 'Threads_connected'; SHOW VARIABLES LIKE 'max_connections';"

# SQL Server
sqlcmd -Q "SELECT COUNT(*) as active_connections FROM sys.dm_exec_sessions WHERE is_user_process = 1;"
```

#### Storage Full
```bash
# Check Azure storage metrics
az monitor metrics list --resource <resource-id> --metric storage_percent

# PostgreSQL disk usage
psql -c "SELECT pg_size_pretty(pg_database_size(current_database()));"

# MySQL disk usage
mysql -e "SELECT table_schema, ROUND(SUM(data_length + index_length) / 1024 / 1024, 1) AS 'DB Size in MB' FROM information_schema.tables GROUP BY table_schema;"
```

## Performance Tuning Workflow

### 1. Assessment Phase (Week 1)
- [ ] **Establish Baseline**
  - Run baseline establishment scripts
  - Document current performance metrics
  - Identify performance bottlenecks

- [ ] **Workload Analysis**
  - Characterize query patterns
  - Identify peak usage periods
  - Analyze resource consumption

### 2. Planning Phase (Week 2)
- [ ] **Tuning Strategy**
  - Prioritize optimization opportunities
  - Plan configuration changes
  - Schedule implementation windows

- [ ] **Risk Assessment**
  - Identify potential impacts
  - Prepare rollback procedures
  - Plan testing approach

### 3. Implementation Phase (Week 3)
- [ ] **Configuration Tuning**
  - Apply memory optimizations
  - Tune connection settings
  - Optimize storage parameters

- [ ] **Query Optimization**
  - Optimize slow queries
  - Add missing indexes
  - Remove unused indexes

### 4. Validation Phase (Week 4)
- [ ] **Performance Testing**
  - Run load tests
  - Measure performance improvements
  - Validate stability

- [ ] **Documentation**
  - Document all changes
  - Update configuration baselines
  - Create performance reports

## Monitoring and Alerting

### Alert Configuration Matrix
| Alert Type | PostgreSQL | MySQL | SQL Server | Severity |
|------------|------------|-------|------------|----------|
| High CPU | >85% | >85% | >85% | Critical |
| High Memory | >90% | >90% | >90% | Critical |
| Connection Limit | >95% | >95% | >95% | Critical |
| Storage Full | >90% | >90% | >90% | Critical |
| Slow Queries | >5s | >5s | >5s | Warning |
| Replication Lag | >60s | >60s | N/A | Critical |
| Backup Failure | Any | Any | Any | Critical |

### Dashboard Configuration
- **Executive Dashboard**: High-level health indicators
- **Operational Dashboard**: Detailed metrics for DBA team
- **Troubleshooting Dashboard**: Drill-down capabilities for incidents

### Alert Routing
- **Critical Alerts**: SMS + Email + Teams
- **Warning Alerts**: Email + Teams
- **Info Alerts**: Dashboard notification only

## Automation Framework

### Automated Tasks
- **Daily Health Checks**: 8:00 AM daily
- **Weekly Maintenance**: Sunday 2:00 AM
- **Monthly Reports**: First Monday of month
- **Backup Verification**: Daily after backup completion
- **Performance Monitoring**: Continuous

### Automation Scripts Location
```
/scripts/
├── daily_health_check.py
├── weekly_maintenance.sh
├── monthly_report.py
├── backup_verification.sh
├── performance_monitor.py
└── config/
    ├── production.json
    ├── development.json
    └── templates/
```

### Cron Schedule
```bash
# Daily health check
0 8 * * * /scripts/daily_health_check.py /config/production.json

# Weekly maintenance
0 2 * * 0 /scripts/weekly_maintenance.sh

# Monthly report
0 9 1 * * /scripts/monthly_report.py

# Backup verification
30 */6 * * * /scripts/backup_verification.sh
```

## Best Practices Summary

### Configuration Management
- **Version Control**: All configurations in Git
- **Change Management**: Documented approval process
- **Testing**: All changes tested in development first
- **Rollback**: Always have rollback procedures ready

### Performance Optimization
- **Baseline First**: Establish performance baselines before tuning
- **Incremental Changes**: Make one change at a time
- **Measure Impact**: Quantify performance improvements
- **Document Everything**: Maintain detailed change logs

### Monitoring Strategy
- **Proactive Alerts**: Set thresholds before problems occur
- **Trend Analysis**: Monitor long-term trends
- **Business Context**: Align monitoring with business requirements
- **Regular Reviews**: Monthly review of alert effectiveness

### Security Practices
- **Least Privilege**: Grant minimum required permissions
- **Regular Audits**: Monthly security reviews
- **Credential Management**: Use Azure Key Vault
- **Compliance**: Maintain audit trails

## Documentation Index

### Core Documentation
1. **[PostgreSQL Performance Guide](postgreSQL/docs/postgresql_performance_tuning_guide.md)**
2. **[MySQL Performance Guide](mySQL/docs/mysql_performance_tuning_guide.md)**
3. **[SQL Server Performance Guide](sqlServer/docs/sqlserver_performance_tuning_guide.md)**
4. **[Azure Monitoring Guide](azure_database_monitoring_alerting_guide.md)**
5. **[Performance Baseline Guide](performance_baseline_establishment_guide.md)**
6. **[Tuning Checklist](database_tuning_checklist_best_practices.md)**
7. **[Alert Templates](alert_templates_thresholds.md)**

### Monitoring Queries
1. **[PostgreSQL Monitoring](postgreSQL/postgresql_lock_monitoring_queries.sql)**
2. **[MySQL Monitoring](mySQL/mysql_monitoring_queries.sql)**
3. **[SQL Server Monitoring](sqlServer/sqlserver_monitoring_queries.sql)**

### Automation Scripts
1. **[Daily Health Check](automation_scripts/daily_health_check.py)**
2. **[Weekly Maintenance](automation_scripts/weekly_maintenance.sh)**
3. **[Configuration Example](automation_scripts/config_example.json)**

### Azure Resources
1. **[Feature Matrix](DB_Monitoring_Feature_Matrix__Azure_.csv)**
2. **[Task Analysis](dba_task_analysis.md)**

## Quick Start Guide for New Team Members

### Day 1: Environment Setup
1. **Access Setup**
   - Azure portal access
   - Database connection credentials
   - Monitoring dashboard access

2. **Tool Installation**
   - Database client tools (psql, mysql, sqlcmd)
   - Azure CLI
   - Monitoring tools

3. **Documentation Review**
   - Read this master playbook
   - Review database-specific guides
   - Understand alert procedures

### Week 1: Shadow Operations
1. **Daily Operations**
   - Shadow daily health checks
   - Observe incident response
   - Learn monitoring tools

2. **Weekly Maintenance**
   - Participate in weekly maintenance
   - Understand automation scripts
   - Practice troubleshooting

### Month 1: Independent Operations
1. **Take Ownership**
   - Lead daily operations
   - Handle routine incidents
   - Contribute to improvements

2. **Continuous Learning**
   - Azure certifications
   - Database-specific training
   - Performance tuning workshops

## Continuous Improvement

### Monthly Reviews
- **Performance Metrics**: Review against targets
- **Process Efficiency**: Identify automation opportunities
- **Documentation Updates**: Keep playbook current
- **Team Feedback**: Incorporate lessons learned

### Quarterly Planning
- **Technology Updates**: Plan for new Azure features
- **Capacity Planning**: Project future needs
- **Training Plans**: Skill development roadmap
- **Tool Evaluation**: Assess new monitoring tools

### Annual Assessment
- **Architecture Review**: Evaluate overall design
- **Cost Optimization**: Identify savings opportunities
- **Disaster Recovery**: Test and update procedures
- **Compliance Audit**: Ensure regulatory compliance

---

## Contact Information

**DBA Team Lead**: [Name] - [email] - [phone]
**Azure Architect**: [Name] - [email] - [phone]
**Operations Manager**: [Name] - [email] - [phone]

**Last Updated**: [Date]
**Version**: 1.0
**Next Review**: [Date + 3 months]

---

*This playbook is a living document and should be updated regularly to reflect changes in the environment, processes, and best practices.*