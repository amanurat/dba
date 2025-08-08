# Database Alert Templates and Thresholds

## Table of Contents
1. [Alert Framework Overview](#alert-framework-overview)
2. [PostgreSQL Alert Templates](#postgresql-alert-templates)
3. [MySQL Alert Templates](#mysql-alert-templates)
4. [SQL Server Alert Templates](#sql-server-alert-templates)
5. [Azure-Specific Alerts](#azure-specific-alerts)
6. [Cross-Platform Alerts](#cross-platform-alerts)
7. [Alert Management Best Practices](#alert-management-best-practices)

## Alert Framework Overview

### Severity Levels
- **Critical (P1)**: Immediate action required, service impact
- **High (P2)**: Urgent attention needed, potential service impact
- **Medium (P3)**: Important but not urgent, monitor closely
- **Low (P4)**: Informational, trend monitoring

### Alert Categories
- **Performance**: Response time, throughput, resource utilization
- **Availability**: Connection failures, service outages
- **Capacity**: Storage, memory, connection limits
- **Security**: Failed logins, suspicious activity
- **Maintenance**: Backup failures, maintenance tasks

### Notification Channels
- **Critical**: SMS, Phone, Email, Teams/Slack
- **High**: Email, Teams/Slack, Ticket creation
- **Medium**: Email, Dashboard notification
- **Low**: Dashboard notification, Daily digest

## PostgreSQL Alert Templates

### 1. Performance Alerts

#### High CPU Usage
```json
{
  "alert_name": "PostgreSQL_High_CPU_Usage",
  "description": "PostgreSQL server CPU usage is above threshold",
  "severity": "High",
  "metric": "cpu_percent",
  "thresholds": {
    "warning": 70,
    "critical": 85
  },
  "evaluation_window": "5m",
  "evaluation_frequency": "1m",
  "query": "AzureMetrics | where ResourceProvider == 'MICROSOFT.DBFORPOSTGRESQL' | where MetricName == 'cpu_percent' | summarize avg(Average) by bin(TimeGenerated, 5m)",
  "action_groups": ["dba-team", "on-call-engineer"],
  "auto_resolve": true,
  "suppress_duration": "15m"
}
```

#### Memory Pressure
```json
{
  "alert_name": "PostgreSQL_Memory_Pressure",
  "description": "PostgreSQL server memory usage is high",
  "severity": "Medium",
  "metric": "memory_percent",
  "thresholds": {
    "warning": 80,
    "critical": 90
  },
  "evaluation_window": "10m",
  "evaluation_frequency": "5m",
  "query": "AzureMetrics | where ResourceProvider == 'MICROSOFT.DBFORPOSTGRESQL' | where MetricName == 'memory_percent' | summarize avg(Average) by bin(TimeGenerated, 10m)",
  "action_groups": ["dba-team"],
  "auto_resolve": true
}
```

#### Connection Limit Approaching
```json
{
  "alert_name": "PostgreSQL_Connection_Limit",
  "description": "PostgreSQL active connections approaching limit",
  "severity": "High",
  "metric": "active_connections",
  "thresholds": {
    "warning": 80,
    "critical": 95
  },
  "evaluation_window": "5m",
  "evaluation_frequency": "1m",
  "query": "AzureMetrics | where ResourceProvider == 'MICROSOFT.DBFORPOSTGRESQL' | where MetricName == 'active_connections' | summarize avg(Average) by bin(TimeGenerated, 5m)",
  "action_groups": ["dba-team", "on-call-engineer"],
  "auto_resolve": true
}
```

#### Slow Query Detection
```kusto
// Log-based alert for slow queries
let SlowQueryThreshold = 5000; // 5 seconds in milliseconds
AzureDiagnostics
| where TimeGenerated > ago(5m)
| where ResourceProvider == "MICROSOFT.DBFORPOSTGRESQL"
| where Category == "PostgreSQLLogs"
| where Message contains "duration:"
| extend Duration = extract(@"duration: ([0-9.]+) ms", 1, Message)
| where toint(Duration) > SlowQueryThreshold
| summarize SlowQueryCount = count() by bin(TimeGenerated, 1m)
| where SlowQueryCount > 5
```

### 2. Availability Alerts

#### Connection Failures
```json
{
  "alert_name": "PostgreSQL_Connection_Failures",
  "description": "High number of PostgreSQL connection failures",
  "severity": "Critical",
  "metric": "connections_failed",
  "thresholds": {
    "warning": 10,
    "critical": 25
  },
  "evaluation_window": "5m",
  "evaluation_frequency": "1m",
  "query": "AzureMetrics | where ResourceProvider == 'MICROSOFT.DBFORPOSTGRESQL' | where MetricName == 'connections_failed' | summarize sum(Total) by bin(TimeGenerated, 5m)",
  "action_groups": ["dba-team", "on-call-engineer", "incident-response"],
  "auto_resolve": false
}
```

#### Database Locks
```kusto
// Custom log query for lock detection
AzureDiagnostics
| where TimeGenerated > ago(5m)
| where ResourceProvider == "MICROSOFT.DBFORPOSTGRESQL"
| where Category == "PostgreSQLLogs"
| where Message contains "deadlock detected" or Message contains "lock timeout"
| summarize LockIssues = count() by bin(TimeGenerated, 1m)
| where LockIssues > 0
```

### 3. Capacity Alerts

#### Storage Usage
```json
{
  "alert_name": "PostgreSQL_Storage_Usage",
  "description": "PostgreSQL storage usage is high",
  "severity": "Medium",
  "metric": "storage_percent",
  "thresholds": {
    "warning": 80,
    "critical": 90
  },
  "evaluation_window": "15m",
  "evaluation_frequency": "5m",
  "query": "AzureMetrics | where ResourceProvider == 'MICROSOFT.DBFORPOSTGRESQL' | where MetricName == 'storage_percent' | summarize avg(Average) by bin(TimeGenerated, 15m)",
  "action_groups": ["dba-team"],
  "auto_resolve": true
}
```

## MySQL Alert Templates

### 1. Performance Alerts

#### High CPU Usage
```json
{
  "alert_name": "MySQL_High_CPU_Usage",
  "description": "MySQL server CPU usage is above threshold",
  "severity": "High",
  "metric": "cpu_percent",
  "thresholds": {
    "warning": 70,
    "critical": 85
  },
  "evaluation_window": "5m",
  "evaluation_frequency": "1m",
  "query": "AzureMetrics | where ResourceProvider == 'MICROSOFT.DBFORMYSQL' | where MetricName == 'cpu_percent' | summarize avg(Average) by bin(TimeGenerated, 5m)",
  "action_groups": ["dba-team", "on-call-engineer"],
  "auto_resolve": true
}
```

#### Buffer Pool Hit Ratio Low
```kusto
// Custom query for MySQL buffer pool efficiency
let BufferPoolThreshold = 95.0;
AzureMetrics
| where TimeGenerated > ago(10m)
| where ResourceProvider == "MICROSOFT.DBFORMYSQL"
| where MetricName in ("innodb_buffer_pool_reads", "innodb_buffer_pool_read_requests")
| summarize 
    PhysicalReads = max(Average) by MetricName, bin(TimeGenerated, 5m)
| pivot(MetricName, max_Average)
| extend HitRatio = (1 - (innodb_buffer_pool_reads / innodb_buffer_pool_read_requests)) * 100
| where HitRatio < BufferPoolThreshold
```

#### Replication Lag
```json
{
  "alert_name": "MySQL_Replication_Lag",
  "description": "MySQL replication lag is high",
  "severity": "High",
  "metric": "seconds_behind_master",
  "thresholds": {
    "warning": 30,
    "critical": 60
  },
  "evaluation_window": "5m",
  "evaluation_frequency": "1m",
  "query": "AzureMetrics | where ResourceProvider == 'MICROSOFT.DBFORMYSQL' | where MetricName == 'seconds_behind_master' | summarize avg(Average) by bin(TimeGenerated, 5m)",
  "action_groups": ["dba-team", "on-call-engineer"],
  "auto_resolve": true
}
```

### 2. Availability Alerts

#### Connection Failures
```json
{
  "alert_name": "MySQL_Connection_Failures",
  "description": "High number of MySQL connection failures",
  "severity": "Critical",
  "metric": "connections_failed",
  "thresholds": {
    "warning": 10,
    "critical": 25
  },
  "evaluation_window": "5m",
  "evaluation_frequency": "1m",
  "query": "AzureMetrics | where ResourceProvider == 'MICROSOFT.DBFORMYSQL' | where MetricName == 'connections_failed' | summarize sum(Total) by bin(TimeGenerated, 5m)",
  "action_groups": ["dba-team", "on-call-engineer", "incident-response"],
  "auto_resolve": false
}
```

#### Slow Query Volume
```kusto
// MySQL slow query volume alert
AzureDiagnostics
| where TimeGenerated > ago(5m)
| where ResourceProvider == "MICROSOFT.DBFORMYSQL"
| where Category == "MySqlSlowLogs"
| summarize SlowQueryCount = count() by bin(TimeGenerated, 1m)
| where SlowQueryCount > 20
```

## SQL Server Alert Templates

### 1. Performance Alerts

#### High DTU Usage (Azure SQL Database)
```json
{
  "alert_name": "SQL_High_DTU_Usage",
  "description": "SQL Database DTU consumption is high",
  "severity": "High",
  "metric": "dtu_consumption_percent",
  "thresholds": {
    "warning": 75,
    "critical": 90
  },
  "evaluation_window": "5m",
  "evaluation_frequency": "1m",
  "query": "AzureMetrics | where ResourceProvider == 'MICROSOFT.SQL' | where MetricName == 'dtu_consumption_percent' | summarize avg(Average) by bin(TimeGenerated, 5m)",
  "action_groups": ["dba-team", "on-call-engineer"],
  "auto_resolve": true
}
```

#### High CPU Usage
```json
{
  "alert_name": "SQL_High_CPU_Usage",
  "description": "SQL Server CPU usage is above threshold",
  "severity": "High",
  "metric": "cpu_percent",
  "thresholds": {
    "warning": 70,
    "critical": 85
  },
  "evaluation_window": "5m",
  "evaluation_frequency": "1m",
  "query": "AzureMetrics | where ResourceProvider == 'MICROSOFT.SQL' | where MetricName == 'cpu_percent' | summarize avg(Average) by bin(TimeGenerated, 5m)",
  "action_groups": ["dba-team", "on-call-engineer"],
  "auto_resolve": true
}
```

#### Blocking Sessions
```kusto
// SQL Server blocking detection
AzureDiagnostics
| where TimeGenerated > ago(5m)
| where ResourceProvider == "MICROSOFT.SQL"
| where Category == "Blocks"
| where duration_d > 30000  // 30 seconds
| summarize BlockingCount = count() by bin(TimeGenerated, 1m)
| where BlockingCount > 0
```

#### Deadlocks
```kusto
// SQL Server deadlock detection
AzureDiagnostics
| where TimeGenerated > ago(5m)
| where ResourceProvider == "MICROSOFT.SQL"
| where Category == "Deadlocks"
| summarize DeadlockCount = count() by bin(TimeGenerated, 1m)
| where DeadlockCount > 0
```

### 2. Availability Alerts

#### Connection Failures
```json
{
  "alert_name": "SQL_Connection_Failures",
  "description": "High number of SQL Server connection failures",
  "severity": "Critical",
  "metric": "connection_failed",
  "thresholds": {
    "warning": 10,
    "critical": 25
  },
  "evaluation_window": "5m",
  "evaluation_frequency": "1m",
  "query": "AzureMetrics | where ResourceProvider == 'MICROSOFT.SQL' | where MetricName == 'connection_failed' | summarize sum(Total) by bin(TimeGenerated, 5m)",
  "action_groups": ["dba-team", "on-call-engineer", "incident-response"],
  "auto_resolve": false
}
```

### 3. Capacity Alerts

#### Storage Usage
```json
{
  "alert_name": "SQL_Storage_Usage",
  "description": "SQL Database storage usage is high",
  "severity": "Medium",
  "metric": "storage_percent",
  "thresholds": {
    "warning": 80,
    "critical": 90
  },
  "evaluation_window": "15m",
  "evaluation_frequency": "5m",
  "query": "AzureMetrics | where ResourceProvider == 'MICROSOFT.SQL' | where MetricName == 'storage_percent' | summarize avg(Average) by bin(TimeGenerated, 15m)",
  "action_groups": ["dba-team"],
  "auto_resolve": true
}
```

## Azure-Specific Alerts

### 1. Resource Governance Alerts

#### Resource Limit Approaching
```json
{
  "alert_name": "Azure_Resource_Limit_Approaching",
  "description": "Azure database resource consumption approaching limits",
  "severity": "High",
  "metric": "resource_consumption_percent",
  "thresholds": {
    "warning": 80,
    "critical": 95
  },
  "evaluation_window": "10m",
  "evaluation_frequency": "5m",
  "action_groups": ["dba-team", "azure-admin"],
  "auto_resolve": true
}
```

### 2. Service Health Alerts

#### Service Degradation
```json
{
  "alert_name": "Azure_Service_Health_Alert",
  "description": "Azure database service health issue detected",
  "severity": "Critical",
  "source": "Azure Service Health",
  "action_groups": ["dba-team", "on-call-engineer", "management"],
  "auto_resolve": false
}
```

### 3. Cost Management Alerts

#### Unexpected Cost Increase
```json
{
  "alert_name": "Azure_Database_Cost_Alert",
  "description": "Database costs have increased significantly",
  "severity": "Medium",
  "metric": "cost_usd",
  "threshold_type": "percentage_increase",
  "threshold_value": 25,
  "evaluation_window": "24h",
  "action_groups": ["dba-team", "finance-team"],
  "auto_resolve": false
}
```

## Cross-Platform Alerts

### 1. Backup Alerts

#### Backup Failure
```json
{
  "alert_name": "Database_Backup_Failure",
  "description": "Database backup has failed",
  "severity": "Critical",
  "source": "backup_logs",
  "evaluation_frequency": "15m",
  "query": "Custom log query to detect backup failures",
  "action_groups": ["dba-team", "on-call-engineer"],
  "auto_resolve": false,
  "escalation": {
    "after": "30m",
    "to": ["management", "incident-response"]
  }
}
```

#### Backup Duration Excessive
```json
{
  "alert_name": "Database_Backup_Duration_Long",
  "description": "Database backup taking longer than expected",
  "severity": "Medium",
  "metric": "backup_duration_minutes",
  "thresholds": {
    "warning": 120,
    "critical": 240
  },
  "evaluation_window": "5m",
  "action_groups": ["dba-team"],
  "auto_resolve": true
}
```

### 2. Security Alerts

#### Failed Login Attempts
```kusto
// Cross-platform failed login detection
AzureDiagnostics
| where TimeGenerated > ago(5m)
| where ResourceProvider in ("MICROSOFT.DBFORPOSTGRESQL", "MICROSOFT.DBFORMYSQL", "MICROSOFT.SQL")
| where Message contains "authentication failed" or Message contains "login failed" or Message contains "access denied"
| summarize FailedLogins = count() by ResourceProvider, bin(TimeGenerated, 1m)
| where FailedLogins > 10
```

#### Suspicious Activity
```json
{
  "alert_name": "Database_Suspicious_Activity",
  "description": "Suspicious database activity detected",
  "severity": "High",
  "source": "security_logs",
  "patterns": [
    "Multiple failed logins from same IP",
    "Login from unusual location",
    "Privilege escalation attempts",
    "Unusual query patterns"
  ],
  "action_groups": ["security-team", "dba-team"],
  "auto_resolve": false
}
```

## Alert Management Best Practices

### 1. Alert Configuration Templates

#### PowerShell Script for Azure Alert Creation
```powershell
# Create Azure Monitor Alert Rule
param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$AlertName,
    
    [Parameter(Mandatory=$true)]
    [string]$MetricName,
    
    [Parameter(Mandatory=$true)]
    [double]$Threshold,
    
    [Parameter(Mandatory=$true)]
    [string]$ActionGroupId
)

$criteria = New-AzMetricAlertRuleV2Criteria -MetricName $MetricName -TimeAggregation Average -Operator GreaterThan -Threshold $Threshold

Add-AzMetricAlertRuleV2 -Name $AlertName -ResourceGroupName $ResourceGroupName -WindowSize 00:05:00 -Frequency 00:01:00 -TargetResourceScope "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName" -Condition $criteria -ActionGroupId $ActionGroupId -Severity 2
```

#### Terraform Template for Alert Rules
```hcl
resource "azurerm_monitor_metric_alert" "database_cpu_alert" {
  name                = "database-cpu-high"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_postgresql_server.main.id]
  description         = "Database CPU usage is high"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  
  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/servers"
    metric_name      = "cpu_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.dba_team.id
  }
}
```

### 2. Alert Suppression and Grouping

#### Intelligent Alert Grouping
```json
{
  "alert_grouping": {
    "enabled": true,
    "group_by": ["ResourceId", "AlertType"],
    "group_window": "15m",
    "max_alerts_per_group": 5
  },
  "suppression": {
    "enabled": true,
    "suppress_duration": "30m",
    "conditions": [
      "Same resource and metric",
      "During maintenance window"
    ]
  }
}
```

### 3. Escalation Policies

#### Multi-Level Escalation
```json
{
  "escalation_policy": {
    "name": "Database Critical Alert Escalation",
    "levels": [
      {
        "level": 1,
        "delay": "0m",
        "targets": ["on-call-dba"],
        "methods": ["sms", "phone", "email"]
      },
      {
        "level": 2,
        "delay": "15m",
        "targets": ["dba-manager", "on-call-dba"],
        "methods": ["phone", "email"],
        "condition": "not_acknowledged"
      },
      {
        "level": 3,
        "delay": "30m",
        "targets": ["incident-commander", "management"],
        "methods": ["phone", "email"],
        "condition": "not_resolved"
      }
    ]
  }
}
```

### 4. Alert Testing and Validation

#### Alert Testing Script
```bash
#!/bin/bash
# Alert testing script
# Tests alert functionality by simulating conditions

RESOURCE_GROUP="test-rg"
SERVER_NAME="test-db-server"

echo "Testing database alerts..."

# Test CPU alert by running CPU-intensive query
echo "1. Testing CPU alert..."
psql -h $SERVER_NAME -c "SELECT COUNT(*) FROM generate_series(1, 10000000);"

# Test connection alert by opening many connections
echo "2. Testing connection alert..."
for i in {1..50}; do
    psql -h $SERVER_NAME -c "SELECT pg_sleep(60);" &
done

# Test storage alert by creating large temporary data
echo "3. Testing storage alert..."
psql -h $SERVER_NAME -c "CREATE TEMP TABLE test_storage AS SELECT generate_series(1, 1000000), md5(random()::text);"

echo "Alert testing completed. Check monitoring dashboard for triggered alerts."
```

### 5. Alert Documentation Template

#### Alert Runbook Template
```markdown
# Alert: [Alert Name]

## Description
Brief description of what this alert indicates

## Severity: [Critical/High/Medium/Low]

## Trigger Conditions
- Metric: [metric_name]
- Threshold: [threshold_value]
- Duration: [evaluation_window]

## Impact
Description of business impact when this alert fires

## Investigation Steps
1. Check [specific dashboard/query]
2. Verify [specific conditions]
3. Review [relevant logs]

## Resolution Steps
1. Immediate actions to take
2. Short-term fixes
3. Long-term solutions

## Escalation
- Level 1: [contact/team]
- Level 2: [contact/team]
- Level 3: [contact/team]

## Related Alerts
List of related alerts that might fire together

## Historical Data
- Frequency: How often this alert typically fires
- Common causes: Most frequent root causes
- Resolution time: Average time to resolve
```

## Alert Threshold Summary

### Performance Thresholds
| Metric | Warning | Critical | Database Types |
|--------|---------|----------|----------------|
| CPU Usage | 70% | 85% | All |
| Memory Usage | 80% | 90% | All |
| Storage Usage | 80% | 90% | All |
| Connection Usage | 80% | 95% | All |
| Query Response Time | 2s | 5s | All |
| Buffer Cache Hit Ratio | <95% | <90% | All |

### Availability Thresholds
| Metric | Warning | Critical | Database Types |
|--------|---------|----------|----------------|
| Connection Failures | 10/5min | 25/5min | All |
| Service Downtime | 1min | 5min | All |
| Backup Failures | 1 | 2 consecutive | All |
| Replication Lag | 30s | 60s | MySQL, PostgreSQL |

### Capacity Thresholds
| Metric | Warning | Critical | Database Types |
|--------|---------|----------|----------------|
| Disk Space | 80% | 90% | All |
| Log File Growth | 1GB/hour | 5GB/hour | All |
| Connection Pool | 80% | 95% | All |
| Transaction Log | 80% | 90% | SQL Server |

These thresholds should be adjusted based on your specific environment, baseline performance, and business requirements.