# 📜 PostgreSQL DBA Scripts

This directory contains organized SQL scripts for PostgreSQL database administration, monitoring, and performance tuning.

## 📁 Directory Structure

```
scripts/
├── monitoring/     # Database monitoring and health check scripts
├── performance/    # Performance tuning and analysis scripts  
├── maintenance/    # Database maintenance and admin scripts
├── sample-data/    # Sample data and test scripts
└── README.md       # This file
```

## 🎯 Usage Guidelines

### **Before Running Any Script:**
1. **Always test in development environment first**
2. **Review script contents carefully**
3. **Backup your database if making changes**
4. **Understand the impact of each query**
5. **Check permissions and security implications**

### **Script Categories:**

| Directory | Purpose | Risk Level |
|-----------|---------|------------|
| **monitoring/** | Read-only monitoring queries | 🟢 Low |
| **performance/** | Analysis and optimization | 🟡 Medium |
| **maintenance/** | Database maintenance tasks | 🔴 High |
| **sample-data/** | Test data generation | 🟢 Low |

## 🔗 Related Documentation

For detailed guides and explanations, see the [`docs/`](../docs/) directory:
- [PostgreSQL Monitoring Complete Setup Guide](../docs/01_postgresql_monitoring_complete_setup_guide.md)
- [PostgreSQL Performance Query Templates](../docs/04%20postgresql_performance_query_templates.md)
- [PostgreSQL Comprehensive Lock Monitoring Guide](../docs/postgresql_comprehensive_lock_monitoring_guide.md)

## ⚠️ Important Notes

- **Production Use**: Always test scripts in development first
- **Security**: Review scripts for sensitive information before version control
- **Performance**: Monitor resource usage when running analysis scripts
- **Compatibility**: Scripts are designed for PostgreSQL on Azure Flexible Server

---

*Last Updated: $(date +%Y-%m-%d)*