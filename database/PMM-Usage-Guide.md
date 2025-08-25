# PMM (Percona Monitoring and Management) Usage Guide

## ✅ Current Status - Everything is Working!

Your PMM setup is **ACTIVE** and monitoring your Azure MySQL database:

- **PMM Server**: ✅ Running (https://localhost:443)
- **Azure MySQL Service**: ✅ Connected (`my-azure-mysql`)
- **MySQL Exporter**: ✅ Running (collecting metrics)
- **Query Analytics**: ✅ Running (monitoring queries)
- **Table Statistics**: ✅ Enabled (342 tables monitored)

---

## 🚀 **QUICK START: Access PMM Dashboard**

### Step 1: Open PMM in Your Browser
```
URL: https://localhost:443
Username: admin
Password: admin
```

**⚠️ Important**: Your browser will show a security warning because of the self-signed certificate. Click **"Advanced" → "Proceed to localhost (unsafe)"** or type `thisisunsafe` in Chrome.

### Step 2: First Login
1. You'll be prompted to change the default password
2. Set a strong password for security
3. You'll then access the main dashboard

---

## 📊 **KEY DASHBOARDS TO EXPLORE**

### 1. **Home Dashboard Overview**
- Shows overall system health
- Quick metrics snapshot
- Service status overview

### 2. **MySQL Instance Summary** 
**Path**: Home → MySQL → MySQL Instance Summary
- **Database connections** and connection pool status
- **Query performance** metrics
- **InnoDB buffer pool** efficiency
- **Slow queries** count and performance

### 3. **MySQL Overview**
**Path**: Home → MySQL → MySQL Overview  
- **QPS** (Queries Per Second)
- **Database operations** (SELECT, INSERT, UPDATE, DELETE)
- **MySQL connections** and threads
- **InnoDB metrics** and locks

### 4. **Query Analytics (QAN)**
**Path**: Query Analytics → MySQL
- **Slowest queries** analysis
- **Query execution time** trends
- **Query frequency** statistics
- **Performance Schema** insights

### 5. **MySQL Table Statistics**
**Path**: Home → MySQL → MySQL Table Statistics
- **Table sizes** and row counts  
- **Index usage** efficiency
- **Table fragmentation** analysis

---

## 🎯 **WHAT TO MONITOR FIRST**

### Immediate Health Checks:
1. **Connection Status**: Check MySQL connections aren't maxed out
2. **Query Performance**: Look for slow queries > 1 second
3. **Buffer Pool Hit Ratio**: Should be > 95%
4. **Disk I/O**: Check for high read/write operations

### Key Metrics to Watch:
- **QPS (Queries Per Second)**: Database load indicator
- **Response Time**: Query execution speed
- **Connections**: Active vs max connections
- **InnoDB Buffer Pool**: Memory efficiency
- **Slow Queries**: Performance bottlenecks

---

## 🔍 **HOW TO USE SPECIFIC FEATURES**

### MySQL Monitoring:
1. **Dashboard Navigation**: Use the left sidebar
2. **Time Range**: Change time period (top-right corner)
3. **Auto-refresh**: Enable real-time monitoring
4. **Drill-down**: Click on charts for detailed views

### Query Analytics:
1. **Query List**: Shows all queries with performance data
2. **Query Details**: Click any query for execution plan
3. **Time-based Analysis**: Filter by time periods
4. **Database Filtering**: Focus on specific databases

### Alerting (Advanced):
1. **Alert Rules**: Set up notifications for critical metrics
2. **Thresholds**: Define warning/critical levels
3. **Channels**: Configure email/Slack notifications

---

## 🛠 **COMMON TASKS**

### Check Database Performance:
1. Go to **MySQL Instance Summary**
2. Look for **red alerts** or **high values**
3. Check **Query Response Time** trends
4. Review **Connection Usage** percentage

### Identify Slow Queries:
1. Open **Query Analytics**
2. Sort by **Query Time** or **Load**
3. Click on slow queries for details
4. Analyze **Execution Count** vs **Time**

### Monitor Resource Usage:
1. Check **MySQL Overview** dashboard
2. Monitor **InnoDB Buffer Pool** usage
3. Watch **Disk I/O** patterns
4. Review **Memory Usage** trends

### Table Analysis:
1. Go to **MySQL Table Statistics**
2. Sort by **Table Size** or **Row Count**
3. Look for **fragmented tables**
4. Identify **unused indexes**

---

## ⚡ **PERFORMANCE OPTIMIZATION TIPS**

### Based on PMM Data:
1. **Slow Queries**: Use Query Analytics to optimize SQL
2. **Buffer Pool**: Increase `innodb_buffer_pool_size` if hit ratio < 95%
3. **Connections**: Monitor and adjust `max_connections`
4. **Indexing**: Check table statistics for missing indexes

### Monitoring Best Practices:
1. **Set Baselines**: Know your normal performance levels
2. **Regular Reviews**: Check dashboards daily/weekly
3. **Alert Setup**: Configure notifications for critical metrics
4. **Historical Analysis**: Use longer time ranges for trends

---

## 🚨 **TROUBLESHOOTING**

### If Dashboards Show No Data:
1. Check service status: `docker exec pmm-server pmm-admin list`
2. Verify MySQL connection: Test from PMM server
3. Check time ranges: Might need to wait for data collection
4. Review error logs: `docker logs pmm-server`

### If Connection Issues:
1. **Browser Certificate**: Accept self-signed certificate
2. **Firewall**: Ensure port 443 is accessible
3. **PMM Server**: Restart if needed: `docker restart pmm-server`

### Performance Issues:
1. **Resource Limits**: Check Docker container resources
2. **Data Retention**: Configure appropriate data retention
3. **Metrics Resolution**: Adjust collection intervals

---

## 📈 **ADVANCED FEATURES**

### Custom Dashboards:
1. **Grafana Access**: Use built-in Grafana for custom panels
2. **Query Builder**: Create custom metric queries
3. **Dashboard Import**: Use community dashboards
4. **Annotations**: Add notes for incidents/changes

### API Usage:
1. **PMM API**: Programmatic access to metrics
2. **Integration**: Connect with other monitoring tools
3. **Automation**: Automated reporting and alerts

---

## 🔐 **SECURITY RECOMMENDATIONS**

### Production Setup:
1. **Change Default Password**: Use strong authentication
2. **SSL Certificates**: Install proper certificates
3. **Network Security**: Use firewalls and VPNs
4. **Access Control**: Limit dashboard access
5. **Regular Updates**: Keep PMM updated

### Data Protection:
1. **Backup Configuration**: Save PMM settings
2. **Metric Retention**: Configure appropriate retention
3. **Database Security**: Secure monitoring user privileges

---

## 📚 **LEARNING RESOURCES**

### Documentation:
- [PMM Official Documentation](https://docs.percona.com/percona-monitoring-and-management/)
- [MySQL Performance Tuning Guide](https://dev.mysql.com/doc/refman/8.0/en/optimization.html)
- [Grafana Dashboard Creation](https://grafana.com/docs/grafana/latest/dashboards/)

### Community:
- [Percona Community Forums](https://forums.percona.com/)
- [PMM GitHub Repository](https://github.com/percona/pmm)
- [MySQL Performance Blog](https://www.percona.com/blog/)

---

## 🎯 **YOUR NEXT STEPS**

1. **✅ Access Dashboard**: Open https://localhost:443 now!
2. **🔍 Explore**: Look at MySQL Instance Summary first
3. **📊 Analyze**: Check Query Analytics for slow queries  
4. **⚙️ Optimize**: Use findings to tune your database
5. **🚨 Alert**: Set up notifications for critical metrics

**Your Azure MySQL database monitoring is ready to use!** 🚀

---

## 📋 **Quick Commands Reference**

```bash
# Check PMM Status
docker ps --filter name=pmm-server
docker exec pmm-server pmm-admin list

# View Logs
docker logs pmm-server
docker logs -f pmm-server  # Real-time

# Restart PMM Server
docker restart pmm-server

# Remove MySQL Service (if needed)
docker exec pmm-server pmm-admin remove mysql my-azure-mysql

# Add Additional MySQL Services
docker exec pmm-server pmm-admin add mysql \
  --username=USER --password=PASS \
  --service-name=SERVICE_NAME \
  --host=HOSTNAME --port=3306 --tls
```

**Start exploring your database performance now!** 📈
