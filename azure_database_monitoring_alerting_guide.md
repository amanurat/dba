# Azure Database Monitoring and Alerting Guide

## Table of Contents
1. [Azure Monitor Overview](#azure-monitor-overview)
2. [Database-Specific Monitoring](#database-specific-monitoring)
3. [Alert Configuration](#alert-configuration)
4. [Dashboard Setup](#dashboard-setup)
5. [Log Analytics Integration](#log-analytics-integration)
6. [Automation and Runbooks](#automation-and-runbooks)
7. [Cost Optimization](#cost-optimization)

## Azure Monitor Overview

### 1. Enable Diagnostic Settings
```bash
# Enable diagnostic settings for PostgreSQL
az postgres server configuration set \
  --resource-group myResourceGroup \
  --server-name myPostgreSQLServer \
  --name log_statement \
  --value all

# Enable diagnostic settings for MySQL
az mysql server configuration set \
  --resource-group myResourceGroup \
  --server-name myMySQLServer \
  --name slow_query_log \
  --value ON

# Enable diagnostic settings for SQL Database
az sql db audit-policy update \
  --resource-group myResourceGroup \
  --server myServer \
  --name myDatabase \
  --state Enabled \
  --storage-account myStorageAccount
```

### 2. Configure Log Analytics Workspace
```json
{
  "type": "Microsoft.OperationalInsights/workspaces",
  "apiVersion": "2020-08-01",
  "name": "dba-monitoring-workspace",
  "location": "[resourceGroup().location]",
  "properties": {
    "sku": {
      "name": "PerGB2018"
    },
    "retentionInDays": 90,
    "features": {
      "searchVersion": 1,
      "legacy": 0,
      "enableLogAccessUsingOnlyResourcePermissions": true
    }
  }
}
```

## Database-Specific Monitoring

### PostgreSQL on Azure

#### 1. Key Metrics to Monitor
```kusto
// PostgreSQL Connection Metrics
AzureMetrics
| where ResourceProvider == "MICROSOFT.DBFORPOSTGRESQL"
| where MetricName in ("active_connections", "connections_failed", "connections_succeeded")
| summarize avg(Average) by MetricName, bin(TimeGenerated, 5m)
| render timechart

// PostgreSQL Performance Metrics
AzureMetrics
| where ResourceProvider == "MICROSOFT.DBFORPOSTGRESQL"
| where MetricName in ("cpu_percent", "memory_percent", "io_consumption_percent")
| summarize avg(Average) by MetricName, bin(TimeGenerated, 5m)
| render timechart

// PostgreSQL Storage Metrics
AzureMetrics
| where ResourceProvider == "MICROSOFT.DBFORPOSTGRESQL"
| where MetricName in ("storage_percent", "storage_used", "storage_limit")
| summarize avg(Average) by MetricName, bin(TimeGenerated, 15m)
| render timechart
```

#### 2. PostgreSQL Diagnostic Logs
```kusto
// Slow Query Analysis
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.DBFORPOSTGRESQL"
| where Category == "PostgreSQLLogs"
| where Message contains "duration:"
| extend Duration = extract(@"duration: ([0-9.]+) ms", 1, Message)
| where toint(Duration) > 1000
| project TimeGenerated, Duration, Message
| order by TimeGenerated desc

// Connection Errors
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.DBFORPOSTGRESQL"
| where Category == "PostgreSQLLogs"
| where Message contains "FATAL" or Message contains "ERROR"
| project TimeGenerated, Level = "ERROR", Message
| order by TimeGenerated desc
```

### MySQL on Azure

#### 1. Key Metrics to Monitor
```kusto
// MySQL Connection and Performance Metrics
AzureMetrics
| where ResourceProvider == "MICROSOFT.DBFORMYSQL"
| where MetricName in ("active_connections", "cpu_percent", "memory_percent", "io_consumption_percent")
| summarize avg(Average) by MetricName, bin(TimeGenerated, 5m)
| render timechart

// MySQL Replication Lag (if applicable)
AzureMetrics
| where ResourceProvider == "MICROSOFT.DBFORMYSQL"
| where MetricName == "seconds_behind_master"
| summarize avg(Average) by bin(TimeGenerated, 5m)
| render timechart
```

#### 2. MySQL Diagnostic Logs
```kusto
// MySQL Slow Query Log Analysis
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.DBFORMYSQL"
| where Category == "MySqlSlowLogs"
| extend QueryTime = extract(@"Query_time: ([0-9.]+)", 1, Message)
| where toint(QueryTime) > 2
| project TimeGenerated, QueryTime, Message
| order by TimeGenerated desc

// MySQL Error Log Analysis
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.DBFORMYSQL"
| where Category == "MySqlAuditLogs"
| where Message contains "ERROR"
| project TimeGenerated, Message
| order by TimeGenerated desc
```

### SQL Server on Azure

#### 1. Key Metrics to Monitor
```kusto
// SQL Database Performance Metrics
AzureMetrics
| where ResourceProvider == "MICROSOFT.SQL"
| where MetricName in ("cpu_percent", "dtu_consumption_percent", "storage_percent", "connection_successful", "connection_failed")
| summarize avg(Average) by MetricName, bin(TimeGenerated, 5m)
| render timechart

// SQL Database Wait Statistics
AzureMetrics
| where ResourceProvider == "MICROSOFT.SQL"
| where MetricName contains "wait"
| summarize avg(Average) by MetricName, bin(TimeGenerated, 15m)
| render timechart
```

#### 2. SQL Database Diagnostic Logs
```kusto
// SQL Database Query Performance
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.SQL"
| where Category == "QueryStoreRuntimeStatistics"
| where avg_duration_d > 5000  // Queries taking more than 5 seconds
| project TimeGenerated, avg_duration_d, query_hash_s, query_plan_hash_s
| order by avg_duration_d desc

// SQL Database Blocking
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.SQL"
| where Category == "Blocks"
| project TimeGenerated, duration_d, blocked_process_report_s
| order by TimeGenerated desc
```

## Alert Configuration

### 1. Critical Performance Alerts

#### PostgreSQL Alerts
```json
{
  "name": "PostgreSQL-High-CPU",
  "description": "PostgreSQL CPU usage is above 80%",
  "severity": 2,
  "criteria": {
    "allOf": [
      {
        "metricName": "cpu_percent",
        "operator": "GreaterThan",
        "threshold": 80,
        "timeAggregation": "Average"
      }
    ]
  },
  "windowSize": "PT5M",
  "evaluationFrequency": "PT1M",
  "actions": [
    {
      "actionGroupId": "/subscriptions/{subscription-id}/resourceGroups/{resource-group}/providers/Microsoft.Insights/actionGroups/dba-alerts"
    }
  ]
}
```

#### MySQL Alerts
```json
{
  "name": "MySQL-Connection-Limit",
  "description": "MySQL active connections approaching limit",
  "severity": 1,
  "criteria": {
    "allOf": [
      {
        "metricName": "active_connections",
        "operator": "GreaterThan",
        "threshold": 80,
        "timeAggregation": "Average"
      }
    ]
  },
  "windowSize": "PT5M",
  "evaluationFrequency": "PT1M"
}
```

#### SQL Server Alerts
```json
{
  "name": "SQL-DTU-High",
  "description": "SQL Database DTU consumption is high",
  "severity": 2,
  "criteria": {
    "allOf": [
      {
        "metricName": "dtu_consumption_percent",
        "operator": "GreaterThan",
        "threshold": 85,
        "timeAggregation": "Average"
      }
    ]
  },
  "windowSize": "PT5M",
  "evaluationFrequency": "PT1M"
}
```

### 2. Log-Based Alerts

#### Slow Query Alert
```kusto
// Alert query for slow queries across all database types
let SlowQueryThreshold = 5000; // 5 seconds
AzureDiagnostics
| where TimeGenerated > ago(5m)
| where (
    (ResourceProvider == "MICROSOFT.DBFORPOSTGRESQL" and Message contains "duration:" and extract(@"duration: ([0-9.]+) ms", 1, Message) > SlowQueryThreshold) or
    (ResourceProvider == "MICROSOFT.DBFORMYSQL" and Category == "MySqlSlowLogs") or
    (ResourceProvider == "MICROSOFT.SQL" and Category == "QueryStoreRuntimeStatistics" and avg_duration_d > SlowQueryThreshold)
)
| summarize count() by ResourceProvider
| where count_ > 5
```

#### Connection Failure Alert
```kusto
// Alert query for connection failures
AzureDiagnostics
| where TimeGenerated > ago(5m)
| where (
    (ResourceProvider == "MICROSOFT.DBFORPOSTGRESQL" and Message contains "FATAL") or
    (ResourceProvider == "MICROSOFT.DBFORMYSQL" and Message contains "Access denied") or
    (ResourceProvider == "MICROSOFT.SQL" and Category == "Errors")
)
| summarize count() by ResourceProvider, bin(TimeGenerated, 1m)
| where count_ > 10
```

### 3. Action Groups Configuration
```json
{
  "name": "dba-alerts",
  "shortName": "dba-alerts",
  "enabled": true,
  "emailReceivers": [
    {
      "name": "DBA Team",
      "emailAddress": "dba-team@company.com",
      "useCommonAlertSchema": true
    }
  ],
  "smsReceivers": [
    {
      "name": "DBA On-Call",
      "countryCode": "1",
      "phoneNumber": "1234567890"
    }
  ],
  "webhookReceivers": [
    {
      "name": "Teams Webhook",
      "serviceUri": "https://outlook.office.com/webhook/...",
      "useCommonAlertSchema": true
    }
  ]
}
```

## Dashboard Setup

### 1. Azure Dashboard JSON Template
```json
{
  "properties": {
    "lenses": {
      "0": {
        "order": 0,
        "parts": {
          "0": {
            "position": {"x": 0, "y": 0, "rowSpan": 4, "colSpan": 6},
            "metadata": {
              "inputs": [
                {
                  "name": "resourceType",
                  "value": "microsoft.dbforpostgresql/servers"
                },
                {
                  "name": "metricName",
                  "value": "cpu_percent"
                }
              ],
              "type": "Extension/Microsoft_Azure_Monitoring/PartType/MetricsChartPart"
            }
          },
          "1": {
            "position": {"x": 6, "y": 0, "rowSpan": 4, "colSpan": 6},
            "metadata": {
              "inputs": [
                {
                  "name": "resourceType",
                  "value": "microsoft.dbformysql/servers"
                },
                {
                  "name": "metricName",
                  "value": "active_connections"
                }
              ],
              "type": "Extension/Microsoft_Azure_Monitoring/PartType/MetricsChartPart"
            }
          }
        }
      }
    },
    "metadata": {
      "model": {
        "timeRange": {
          "value": {
            "relative": {
              "duration": 24,
              "timeUnit": 1
            }
          },
          "type": "MsPortalFx.Composition.Configuration.ValueTypes.TimeRange"
        }
      }
    }
  }
}
```

### 2. Grafana Dashboard Configuration
```json
{
  "dashboard": {
    "title": "Azure Database Monitoring",
    "panels": [
      {
        "title": "Database CPU Usage",
        "type": "graph",
        "targets": [
          {
            "datasource": "Azure Monitor",
            "subscription": "$subscription",
            "resourceGroup": "$resourceGroup",
            "metricDefinition": "Microsoft.DBforPostgreSQL/servers",
            "metricName": "cpu_percent",
            "aggregation": "Average"
          }
        ]
      },
      {
        "title": "Active Connections",
        "type": "stat",
        "targets": [
          {
            "datasource": "Azure Monitor",
            "subscription": "$subscription",
            "resourceGroup": "$resourceGroup",
            "metricDefinition": "Microsoft.DBforMySQL/servers",
            "metricName": "active_connections",
            "aggregation": "Average"
          }
        ]
      }
    ]
  }
}
```

## Log Analytics Integration

### 1. Custom Log Analytics Queries

#### Database Health Summary
```kusto
// Database Health Dashboard Query
let TimeRange = ago(1h);
let PostgreSQLHealth = AzureMetrics
| where TimeGenerated > TimeRange
| where ResourceProvider == "MICROSOFT.DBFORPOSTGRESQL"
| where MetricName in ("cpu_percent", "memory_percent", "active_connections")
| summarize avg(Average) by MetricName, Resource
| extend DatabaseType = "PostgreSQL";

let MySQLHealth = AzureMetrics
| where TimeGenerated > TimeRange
| where ResourceProvider == "MICROSOFT.DBFORMYSQL"
| where MetricName in ("cpu_percent", "memory_percent", "active_connections")
| summarize avg(Average) by MetricName, Resource
| extend DatabaseType = "MySQL";

let SQLHealth = AzureMetrics
| where TimeGenerated > TimeRange
| where ResourceProvider == "MICROSOFT.SQL"
| where MetricName in ("cpu_percent", "dtu_consumption_percent", "connection_successful")
| summarize avg(Average) by MetricName, Resource
| extend DatabaseType = "SQL";

union PostgreSQLHealth, MySQLHealth, SQLHealth
| project DatabaseType, Resource, MetricName, HealthScore = avg_Average
| order by DatabaseType, Resource
```

#### Performance Trending
```kusto
// 7-day performance trend analysis
AzureMetrics
| where TimeGenerated > ago(7d)
| where ResourceProvider in ("MICROSOFT.DBFORPOSTGRESQL", "MICROSOFT.DBFORMYSQL", "MICROSOFT.SQL")
| where MetricName in ("cpu_percent", "memory_percent", "storage_percent")
| summarize 
    avg(Average) as AvgValue,
    max(Maximum) as MaxValue,
    min(Minimum) as MinValue
    by ResourceProvider, MetricName, bin(TimeGenerated, 1h)
| render timechart
```

### 2. Workbook Templates

#### Database Performance Workbook
```json
{
  "version": "Notebook/1.0",
  "items": [
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "AzureMetrics\n| where ResourceProvider in (\"MICROSOFT.DBFORPOSTGRESQL\", \"MICROSOFT.DBFORMYSQL\", \"MICROSOFT.SQL\")\n| where MetricName == \"cpu_percent\"\n| summarize avg(Average) by Resource, bin(TimeGenerated, 5m)\n| render timechart",
        "size": 0,
        "title": "Database CPU Usage Trend",
        "timeContext": {
          "durationMs": 3600000
        }
      }
    }
  ]
}
```

## Automation and Runbooks

### 1. PowerShell Runbook for Automated Response
```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$ServerName,
    
    [Parameter(Mandatory=$true)]
    [string]$DatabaseType
)

# Connect to Azure
Connect-AzAccount -Identity

# Function to scale up database
function Scale-Database {
    param($ResourceGroup, $Server, $Type)
    
    switch ($Type) {
        "PostgreSQL" {
            # Scale PostgreSQL server
            Set-AzPostgreSqlServer -ResourceGroupName $ResourceGroup -Name $Server -Sku GP_Gen5_4
        }
        "MySQL" {
            # Scale MySQL server
            Set-AzMySqlServer -ResourceGroupName $ResourceGroup -Name $Server -Sku GP_Gen5_4
        }
        "SQL" {
            # Scale SQL Database
            Set-AzSqlDatabase -ResourceGroupName $ResourceGroup -ServerName $Server -DatabaseName "mydb" -RequestedServiceObjectiveName "S2"
        }
    }
}

# Check current metrics and decide on action
$metrics = Get-AzMetric -ResourceId "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.DBfor$DatabaseType/servers/$ServerName" -MetricName "cpu_percent" -TimeGrain 00:05:00

$avgCPU = ($metrics.Data | Measure-Object -Property Average -Average).Average

if ($avgCPU -gt 80) {
    Write-Output "High CPU detected: $avgCPU%. Scaling up database."
    Scale-Database -ResourceGroup $ResourceGroupName -Server $ServerName -Type $DatabaseType
    
    # Send notification
    Send-AzActionGroupNotification -ActionGroupName "dba-alerts" -Subject "Database Auto-Scaled" -Body "Database $ServerName was automatically scaled due to high CPU usage: $avgCPU%"
}
```

### 2. Logic App for Alert Processing
```json
{
  "definition": {
    "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
    "triggers": {
      "When_an_Azure_Monitor_alert_is_fired": {
        "type": "ApiConnectionWebhook",
        "inputs": {
          "host": {
            "connection": {
              "name": "@parameters('$connections')['azuremonitorlogs']['connectionId']"
            }
          },
          "body": {
            "callback_url": "@{listCallbackUrl()}"
          },
          "path": "/subscriptions/@{encodeURIComponent('subscription-id')}/providers/Microsoft.Insights/alertRules/@{encodeURIComponent('alert-rule-name')}/actions/microsoft.insights/logicapps"
        }
      }
    },
    "actions": {
      "Parse_Alert_Data": {
        "type": "ParseJson",
        "inputs": {
          "content": "@triggerBody()",
          "schema": {
            "type": "object",
            "properties": {
              "alertType": {"type": "string"},
              "resourceId": {"type": "string"},
              "severity": {"type": "string"}
            }
          }
        }
      },
      "Send_Teams_Notification": {
        "type": "Http",
        "inputs": {
          "method": "POST",
          "uri": "https://outlook.office.com/webhook/...",
          "body": {
            "text": "Database Alert: @{body('Parse_Alert_Data')['alertType']} on @{body('Parse_Alert_Data')['resourceId']}"
          }
        }
      }
    }
  }
}
```

## Cost Optimization

### 1. Resource Usage Analysis
```kusto
// Identify underutilized databases
AzureMetrics
| where TimeGenerated > ago(7d)
| where ResourceProvider in ("MICROSOFT.DBFORPOSTGRESQL", "MICROSOFT.DBFORMYSQL", "MICROSOFT.SQL")
| where MetricName in ("cpu_percent", "memory_percent")
| summarize 
    AvgCPU = avg(Average),
    MaxCPU = max(Maximum),
    AvgMemory = avg(Average)
    by Resource
| where AvgCPU < 20 and MaxCPU < 50
| project Resource, AvgCPU, MaxCPU, Recommendation = "Consider downsizing"
```

### 2. Storage Optimization
```kusto
// Storage growth analysis
AzureMetrics
| where TimeGenerated > ago(30d)
| where MetricName == "storage_used"
| summarize 
    StartStorage = min(Average),
    EndStorage = max(Average),
    GrowthMB = max(Average) - min(Average)
    by Resource
| extend GrowthRate = GrowthMB / 30 // MB per day
| project Resource, StartStorage, EndStorage, GrowthMB, GrowthRate
| order by GrowthRate desc
```

### 3. Automated Cost Recommendations
```powershell
# PowerShell script for cost optimization recommendations
$subscriptionId = "your-subscription-id"
$resourceGroups = Get-AzResourceGroup

foreach ($rg in $resourceGroups) {
    # Get all database resources
    $databases = Get-AzResource -ResourceGroupName $rg.ResourceGroupName | Where-Object {
        $_.ResourceType -match "Microsoft.DBfor|Microsoft.Sql"
    }
    
    foreach ($db in $databases) {
        # Get CPU metrics for the last 7 days
        $metrics = Get-AzMetric -ResourceId $db.ResourceId -MetricName "cpu_percent" -TimeGrain 01:00:00 -StartTime (Get-Date).AddDays(-7)
        
        $avgCPU = ($metrics.Data | Measure-Object -Property Average -Average).Average
        $maxCPU = ($metrics.Data | Measure-Object -Property Maximum -Maximum).Maximum
        
        if ($avgCPU -lt 20 -and $maxCPU -lt 50) {
            Write-Output "RECOMMENDATION: $($db.Name) in $($rg.ResourceGroupName) is underutilized (Avg CPU: $avgCPU%, Max CPU: $maxCPU%). Consider downsizing."
        }
    }
}
```

## Best Practices Summary

### 1. Monitoring Strategy
- **Real-time Monitoring**: Set up alerts for critical metrics with 1-5 minute evaluation frequency
- **Historical Analysis**: Retain 90+ days of metrics for trend analysis
- **Cross-Database Correlation**: Monitor all database types with consistent thresholds
- **Proactive Alerting**: Set warning thresholds at 60-70% and critical at 80-90%

### 2. Alert Management
- **Severity Levels**: Use appropriate severity (0=Critical, 1=Error, 2=Warning, 3=Informational)
- **Action Groups**: Configure multiple notification channels (email, SMS, Teams, PagerDuty)
- **Alert Suppression**: Implement intelligent grouping to avoid alert storms
- **Escalation**: Set up escalation paths for unacknowledged critical alerts

### 3. Dashboard Design
- **Executive Summary**: High-level health indicators for management
- **Operational Dashboard**: Detailed metrics for DBA team
- **Troubleshooting Views**: Drill-down capabilities for incident response
- **Mobile Friendly**: Ensure dashboards work on mobile devices for on-call scenarios

### 4. Automation Guidelines
- **Graduated Response**: Start with notifications, then automated diagnostics, finally automated remediation
- **Safety Checks**: Always include safeguards in automated remediation scripts
- **Audit Trail**: Log all automated actions for compliance and troubleshooting
- **Testing**: Thoroughly test automation in non-production environments first