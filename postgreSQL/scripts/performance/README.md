# ⚡ Performance Scripts

SQL scripts for PostgreSQL performance analysis, tuning, and optimization.

## 📋 Available Scripts

| Script | Purpose | Risk Level |
|--------|---------|------------|
| `script analyze index and cost.sql` | Comprehensive index analysis and cost estimation | 🟡 Analysis |
| `simulate_pg_query_load.sql` | Generate test workload for performance testing | 🟡 Test Load |

## 🔍 Script Details

### **script analyze index and cost.sql**
- **Purpose**: Analyze table indexes, identify missing indexes, and estimate query costs
- **Use Case**: Performance tuning, index optimization, query plan analysis
- **Safety**: Read-only analysis with some statistics updates
- **Output**: Index usage statistics, recommendations for new indexes
- **Related Docs**: [PostgreSQL Performance Query Templates](../../docs/04%20postgresql_performance_query_templates.md)

### **simulate_pg_query_load.sql**
- **Purpose**: Generate synthetic database workload for testing and benchmarking
- **Use Case**: Performance testing, load simulation, benchmark preparation
- **Safety**: Creates temporary test data and queries
- **Impact**: May affect system resources during execution
- **Related Docs**: [PostgreSQL Monitoring Complete Setup Guide](../../docs/01_postgresql_monitoring_complete_setup_guide.md)

## 🚀 Usage Examples

```bash
# Run index analysis (recommend running during low-traffic periods)
psql "host=myserver.postgres.database.azure.com user=myuser dbname=mydb sslmode=require" \
  -f "script analyze index and cost.sql"

# Generate test load for performance testing
psql "host=myserver.postgres.database.azure.com user=myuser dbname=test_db sslmode=require" \
  -f simulate_pg_query_load.sql
```

## 📊 Integration with Monitoring

Use these scripts alongside:
- **pg_stat_statements** - For query performance tracking
- **Azure Query Performance Insight** - For performance visualization
- **EXPLAIN ANALYZE** - For detailed query plan analysis
- **Monitoring scripts** - For before/after performance comparison

## ⚠️ Important Considerations

### **Before Running:**
- **Test Environment First**: Always test in development before production
- **Resource Impact**: These scripts may consume significant CPU/memory
- **Timing**: Run during maintenance windows or low-traffic periods
- **Monitoring**: Watch system resources during execution

### **Index Analysis Script:**
- Updates table statistics (ANALYZE command)
- May take time on large tables
- Provides actionable recommendations

### **Load Simulation Script:**
- Creates temporary tables and data
- Generates realistic query patterns
- Clean up temporary objects after testing

## 📈 Expected Outcomes

- **Index Analysis**: Identify unused indexes, missing indexes, performance bottlenecks
- **Load Simulation**: Baseline performance metrics, stress test capabilities
- **Optimization Insights**: Data-driven recommendations for performance improvements

---

*Scripts optimized for PostgreSQL on Azure Flexible Server*