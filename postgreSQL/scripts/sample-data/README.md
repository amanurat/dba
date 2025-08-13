# 🧪 Sample Data Scripts

SQL scripts for generating test data and sample datasets for PostgreSQL performance testing and development.

## 📋 Available Scripts

| Script | Purpose | Risk Level |
|--------|---------|------------|
| `sample_data_for_pg_performance_tuning.sql` | Generate sample datasets for performance testing | 🟢 Test Data |

## 🔍 Script Details

### **sample_data_for_pg_performance_tuning.sql**
- **Purpose**: Create realistic sample data for performance testing and tuning exercises
- **Use Case**: Development testing, performance benchmarking, query optimization practice
- **Safety**: Creates test tables and data only - safe for development environments
- **Output**: Sample tables with realistic data patterns for testing
- **Data Volume**: Configurable amount of test data
- **Related Docs**: [PostgreSQL Monitoring Complete Setup Guide](../../docs/01_postgresql_monitoring_complete_setup_guide.md)

## 🚀 Usage Examples

```bash
# Generate sample data in development database
psql "host=dev-server.postgres.database.azure.com user=dev_user dbname=test_db sslmode=require" \
  -f sample_data_for_pg_performance_tuning.sql

# Generate sample data with custom parameters (if script supports it)
psql "host=dev-server.postgres.database.azure.com user=dev_user dbname=test_db sslmode=require" \
  -v rows=100000 \
  -f sample_data_for_pg_performance_tuning.sql
```

## 📊 Integration with Testing

Use sample data for:
- **Performance Testing**: Benchmark query performance with realistic data volumes
- **Index Testing**: Test index effectiveness with various data patterns
- **Monitoring Validation**: Verify monitoring systems with controlled workloads
- **Development**: Provide consistent test data for application development

## 🎯 Test Scenarios

The sample data enables testing of:
- **Query Performance**: Various SELECT patterns and complexity
- **Index Optimization**: Different index strategies and effectiveness
- **Monitoring Systems**: pg_stat_statements and monitoring tool validation
- **Capacity Planning**: Estimate resource requirements with known data volumes

## ⚠️ Important Notes

### **Environment Guidelines:**
- **Development Only**: Use only in development and testing environments
- **Never in Production**: Do not run in production databases
- **Resource Consideration**: Large datasets may require significant storage and time
- **Cleanup**: Remove test data when no longer needed

### **Data Characteristics:**
- Realistic data patterns and distributions
- Configurable data volumes
- Representative of common application workloads
- Designed to trigger various PostgreSQL optimization scenarios

## 🧹 Cleanup

```sql
-- Example cleanup (verify table names in script)
DROP TABLE IF EXISTS test_customers CASCADE;
DROP TABLE IF EXISTS test_orders CASCADE;
DROP TABLE IF EXISTS test_products CASCADE;
-- Add other tables created by the script
```

## 🔗 Related Scripts

Combine with other script categories:
- **Performance Scripts**: Use sample data for performance analysis
- **Monitoring Scripts**: Monitor test workloads generated from sample data
- **Load Testing**: Generate realistic query patterns against sample datasets

---

*Sample data scripts for PostgreSQL development and testing environments*