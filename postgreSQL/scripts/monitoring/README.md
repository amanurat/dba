# 📊 Monitoring Scripts

Database monitoring and health check SQL scripts for PostgreSQL.

## 📋 Available Scripts

| Script | Purpose | Risk Level |
|--------|---------|------------|
| `postgresql_lock_monitoring_queries.sql` | Comprehensive lock monitoring and analysis | 🟢 Read-only |
| `check_postgresql_connections_before_restart.sql` | Pre-restart connection health check | 🟢 Read-only |

## 🔍 Script Details

### **postgresql_lock_monitoring_queries.sql**
- **Purpose**: Monitor database locks, blocking queries, and lock contention
- **Use Case**: Troubleshooting performance issues, identifying blocking sessions
- **Safety**: Read-only queries, safe for production
- **Related Docs**: [PostgreSQL Comprehensive Lock Monitoring Guide](../../docs/postgresql_comprehensive_lock_monitoring_guide.md)

### **check_postgresql_connections_before_restart.sql**
- **Purpose**: Check active connections and running queries before server restart
- **Use Case**: Pre-maintenance checks, ensuring safe restart conditions
- **Safety**: Read-only queries, safe for production
- **Output**: Connection summary and active query analysis

## 🚀 Usage Examples

```bash
# Run lock monitoring (Azure PostgreSQL)
psql "host=myserver.postgres.database.azure.com user=myuser dbname=mydb sslmode=require" \
  -f postgresql_lock_monitoring_queries.sql

# Check connections before restart
psql "host=myserver.postgres.database.azure.com user=myuser dbname=mydb sslmode=require" \
  -f check_postgresql_connections_before_restart.sql
```

## 📈 Integration

These scripts work well with:
- **Azure Query Performance Insight** - For long-term trend analysis
- **Azure Monitor** - For alerting and dashboards  
- **Grafana** - For custom visualization
- **pgAdmin** - For ad-hoc monitoring

## ⚠️ Best Practices

- Run during business hours for accurate activity monitoring
- Use with monitoring tools for automated alerting
- Schedule regular execution for proactive monitoring
- Combine with application performance monitoring

---

*These scripts are designed for PostgreSQL on Azure Flexible Server*