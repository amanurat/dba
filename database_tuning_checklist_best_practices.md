# Database Tuning Checklist and Best Practices

## Table of Contents
1. [Pre-Tuning Assessment](#pre-tuning-assessment)
2. [PostgreSQL Tuning Checklist](#postgresql-tuning-checklist)
3. [MySQL Tuning Checklist](#mysql-tuning-checklist)
4. [SQL Server Tuning Checklist](#sql-server-tuning-checklist)
5. [Cross-Platform Best Practices](#cross-platform-best-practices)
6. [Performance Testing and Validation](#performance-testing-and-validation)
7. [Maintenance and Monitoring](#maintenance-and-monitoring)

## Pre-Tuning Assessment

### 1. Environment Documentation Checklist
- [ ] **Hardware Specifications**
  - [ ] CPU cores and architecture
  - [ ] Total RAM and available memory
  - [ ] Storage type (SSD/HDD) and IOPS capacity
  - [ ] Network bandwidth and latency
  
- [ ] **Current Performance Baseline**
  - [ ] CPU utilization patterns (peak/average)
  - [ ] Memory usage patterns
  - [ ] I/O patterns and bottlenecks
  - [ ] Query response time distribution
  - [ ] Connection patterns and concurrency levels

- [ ] **Workload Characterization**
  - [ ] OLTP vs OLAP workload ratio
  - [ ] Read vs Write operation ratio
  - [ ] Peak usage hours and patterns
  - [ ] Seasonal variations
  - [ ] Business-critical queries identified

### 2. Risk Assessment
- [ ] **Change Management**
  - [ ] Backup and rollback plan prepared
  - [ ] Maintenance window scheduled
  - [ ] Stakeholder notification completed
  - [ ] Testing environment validated

- [ ] **Impact Analysis**
  - [ ] Application dependencies mapped
  - [ ] SLA requirements documented
  - [ ] Performance degradation tolerance defined
  - [ ] Rollback criteria established

## PostgreSQL Tuning Checklist

### 1. Memory Configuration
- [ ] **shared_buffers**
  - [ ] Set to 25% of total RAM (max 8GB for dedicated server)
  - [ ] Current value: `SHOW shared_buffers;`
  - [ ] Recommended: `shared_buffers = '2GB'` (adjust based on RAM)

- [ ] **effective_cache_size**
  - [ ] Set to 75% of total RAM
  - [ ] Current value: `SHOW effective_cache_size;`
  - [ ] Recommended: `effective_cache_size = '6GB'` (adjust based on RAM)

- [ ] **work_mem**
  - [ ] Set based on concurrent connections and available RAM
  - [ ] Formula: (Total RAM * 0.25) / max_connections
  - [ ] Current value: `SHOW work_mem;`
  - [ ] Recommended: `work_mem = '64MB'` (adjust based on workload)

- [ ] **maintenance_work_mem**
  - [ ] Set to 5-10% of total RAM (max 2GB)
  - [ ] Current value: `SHOW maintenance_work_mem;`
  - [ ] Recommended: `maintenance_work_mem = '512MB'`

### 2. Connection and Concurrency
- [ ] **max_connections**
  - [ ] Set based on application requirements and available resources
  - [ ] Monitor current usage: `SELECT count(*) FROM pg_stat_activity;`
  - [ ] Recommended: Start with 100-200, adjust based on monitoring

- [ ] **Connection Pooling**
  - [ ] Implement PgBouncer or similar connection pooler
  - [ ] Configure pool size based on actual concurrent queries
  - [ ] Monitor pool efficiency and adjust as needed

### 3. WAL and Checkpoints
- [ ] **wal_buffers**
  - [ ] Set to 16MB or 3% of shared_buffers (whichever is smaller)
  - [ ] Current value: `SHOW wal_buffers;`
  - [ ] Recommended: `wal_buffers = '16MB'`

- [ ] **checkpoint_completion_target**
  - [ ] Set to 0.9 to spread checkpoint I/O
  - [ ] Current value: `SHOW checkpoint_completion_target;`
  - [ ] Recommended: `checkpoint_completion_target = 0.9`

- [ ] **max_wal_size**
  - [ ] Set based on checkpoint frequency requirements
  - [ ] Current value: `SHOW max_wal_size;`
  - [ ] Recommended: `max_wal_size = '2GB'` (adjust based on write volume)

### 4. Query Optimization
- [ ] **random_page_cost**
  - [ ] Set to 1.1 for SSD, 4.0 for HDD
  - [ ] Current value: `SHOW random_page_cost;`
  - [ ] Recommended: `random_page_cost = 1.1` (for SSD)

- [ ] **effective_io_concurrency**
  - [ ] Set to number of concurrent I/O operations storage can handle
  - [ ] Current value: `SHOW effective_io_concurrency;`
  - [ ] Recommended: `effective_io_concurrency = 200` (for SSD)

### 5. Statistics and Autovacuum
- [ ] **default_statistics_target**
  - [ ] Increase for better query plans on large tables
  - [ ] Current value: `SHOW default_statistics_target;`
  - [ ] Recommended: `default_statistics_target = 100`

- [ ] **autovacuum_max_workers**
  - [ ] Set based on number of CPU cores
  - [ ] Current value: `SHOW autovacuum_max_workers;`
  - [ ] Recommended: `autovacuum_max_workers = 4`

### 6. Monitoring and Logging
- [ ] **log_min_duration_statement**
  - [ ] Set to log slow queries (e.g., 1000ms)
  - [ ] Current value: `SHOW log_min_duration_statement;`
  - [ ] Recommended: `log_min_duration_statement = 1000`

- [ ] **pg_stat_statements Extension**
  - [ ] Enable for query performance monitoring
  - [ ] Verify: `SELECT * FROM pg_extension WHERE extname = 'pg_stat_statements';`
  - [ ] Install: `CREATE EXTENSION pg_stat_statements;`

## MySQL Tuning Checklist

### 1. InnoDB Configuration
- [ ] **innodb_buffer_pool_size**
  - [ ] Set to 70-80% of total RAM for dedicated MySQL server
  - [ ] Current value: `SHOW VARIABLES LIKE 'innodb_buffer_pool_size';`
  - [ ] Recommended: `innodb_buffer_pool_size = 6G` (adjust based on RAM)

- [ ] **innodb_log_file_size**
  - [ ] Set to 25% of innodb_buffer_pool_size
  - [ ] Current value: `SHOW VARIABLES LIKE 'innodb_log_file_size';`
  - [ ] Recommended: `innodb_log_file_size = 1G`

- [ ] **innodb_flush_method**
  - [ ] Set to O_DIRECT on Linux for better I/O performance
  - [ ] Current value: `SHOW VARIABLES LIKE 'innodb_flush_method';`
  - [ ] Recommended: `innodb_flush_method = O_DIRECT`

- [ ] **innodb_io_capacity**
  - [ ] Set based on storage IOPS capability
  - [ ] Current value: `SHOW VARIABLES LIKE 'innodb_io_capacity';`
  - [ ] Recommended: `innodb_io_capacity = 2000` (for SSD)

### 2. Connection Management
- [ ] **max_connections**
  - [ ] Set based on application requirements
  - [ ] Monitor current usage: `SHOW STATUS LIKE 'Threads_connected';`
  - [ ] Recommended: Start with 200, adjust based on monitoring

- [ ] **thread_cache_size**
  - [ ] Set to handle connection spikes efficiently
  - [ ] Current value: `SHOW VARIABLES LIKE 'thread_cache_size';`
  - [ ] Recommended: `thread_cache_size = 50`

### 3. Query Cache (MySQL 5.7 and earlier)
- [ ] **query_cache_size**
  - [ ] Set to 64-256MB for read-heavy workloads
  - [ ] Current value: `SHOW VARIABLES LIKE 'query_cache_size';`
  - [ ] Recommended: `query_cache_size = 128M`

- [ ] **query_cache_type**
  - [ ] Enable for appropriate workloads
  - [ ] Current value: `SHOW VARIABLES LIKE 'query_cache_type';`
  - [ ] Recommended: `query_cache_type = ON`

### 4. Performance Schema
- [ ] **performance_schema**
  - [ ] Enable for detailed performance monitoring
  - [ ] Current value: `SHOW VARIABLES LIKE 'performance_schema';`
  - [ ] Recommended: `performance_schema = ON`

### 5. Slow Query Logging
- [ ] **slow_query_log**
  - [ ] Enable to identify performance issues
  - [ ] Current value: `SHOW VARIABLES LIKE 'slow_query_log';`
  - [ ] Recommended: `slow_query_log = ON`

- [ ] **long_query_time**
  - [ ] Set threshold for slow query logging
  - [ ] Current value: `SHOW VARIABLES LIKE 'long_query_time';`
  - [ ] Recommended: `long_query_time = 2`

## SQL Server Tuning Checklist

### 1. Memory Configuration
- [ ] **max server memory (MB)**
  - [ ] Set to leave 2-4GB for OS (80% of total RAM)
  - [ ] Current value: `SELECT value FROM sys.configurations WHERE name = 'max server memory (MB)';`
  - [ ] Recommended: Set via `sp_configure 'max server memory (MB)', 6144;`

- [ ] **min server memory (MB)**
  - [ ] Set to ensure minimum memory allocation
  - [ ] Current value: `SELECT value FROM sys.configurations WHERE name = 'min server memory (MB)';`
  - [ ] Recommended: Set to 25% of max server memory

### 2. Parallelism Configuration
- [ ] **max degree of parallelism (MAXDOP)**
  - [ ] Set based on CPU cores (typically 8 or number of cores, whichever is smaller)
  - [ ] Current value: `SELECT value FROM sys.configurations WHERE name = 'max degree of parallelism';`
  - [ ] Recommended: `sp_configure 'max degree of parallelism', 8;`

- [ ] **cost threshold for parallelism**
  - [ ] Increase from default 5 to reduce unnecessary parallelism
  - [ ] Current value: `SELECT value FROM sys.configurations WHERE name = 'cost threshold for parallelism';`
  - [ ] Recommended: `sp_configure 'cost threshold for parallelism', 50;`

### 3. Database Configuration
- [ ] **Auto Growth Settings**
  - [ ] Set fixed MB growth instead of percentage
  - [ ] Check current settings: `SELECT name, growth FROM sys.database_files;`
  - [ ] Recommended: Set growth in MB (e.g., 100MB increments)

- [ ] **Initial File Sizes**
  - [ ] Set appropriate initial sizes to avoid frequent auto-growth
  - [ ] Monitor file growth patterns
  - [ ] Pre-size files based on expected growth

### 4. Query Store (SQL Server 2016+)
- [ ] **Enable Query Store**
  - [ ] Enable for performance monitoring and plan regression detection
  - [ ] Check status: `SELECT actual_state_desc FROM sys.database_query_store_options;`
  - [ ] Enable: `ALTER DATABASE [YourDB] SET QUERY_STORE = ON;`

### 5. Index Optimization
- [ ] **Fill Factor**
  - [ ] Set appropriate fill factor for indexes (85-90% for OLTP)
  - [ ] Check current: `SELECT fill_factor FROM sys.indexes WHERE fill_factor > 0;`
  - [ ] Adjust during index rebuilds

- [ ] **Statistics Auto Update**
  - [ ] Ensure auto update statistics is enabled
  - [ ] Check: `SELECT is_auto_update_stats_on FROM sys.databases;`
  - [ ] Enable: `ALTER DATABASE [YourDB] SET AUTO_UPDATE_STATISTICS ON;`

## Cross-Platform Best Practices

### 1. Index Management
- [ ] **Regular Index Analysis**
  - [ ] Identify missing indexes using database-specific tools
  - [ ] Remove unused indexes to reduce maintenance overhead
  - [ ] Monitor index fragmentation levels
  - [ ] Schedule regular index maintenance

- [ ] **Index Design Principles**
  - [ ] Create indexes on frequently queried columns
  - [ ] Use composite indexes for multi-column queries
  - [ ] Consider covering indexes for read-heavy workloads
  - [ ] Avoid over-indexing write-heavy tables

### 2. Query Optimization
- [ ] **Query Analysis**
  - [ ] Identify top resource-consuming queries
  - [ ] Analyze execution plans for inefficiencies
  - [ ] Look for table scans on large tables
  - [ ] Identify queries with high logical reads

- [ ] **Query Rewriting**
  - [ ] Eliminate unnecessary JOINs and subqueries
  - [ ] Use appropriate WHERE clause filtering
  - [ ] Consider query hints when necessary
  - [ ] Optimize ORDER BY and GROUP BY operations

### 3. Storage Optimization
- [ ] **File Placement**
  - [ ] Separate data and log files on different drives
  - [ ] Use fast storage (SSD) for frequently accessed data
  - [ ] Consider storage tiering for large databases
  - [ ] Monitor I/O patterns and bottlenecks

- [ ] **Partitioning Strategy**
  - [ ] Implement table partitioning for large tables
  - [ ] Use date-based partitioning for time-series data
  - [ ] Consider horizontal partitioning for scalability
  - [ ] Monitor partition pruning effectiveness

### 4. Maintenance Tasks
- [ ] **Statistics Updates**
  - [ ] Schedule regular statistics updates
  - [ ] Monitor statistics freshness
  - [ ] Use sampling for large tables
  - [ ] Automate statistics maintenance

- [ ] **Backup and Recovery**
  - [ ] Implement regular backup schedules
  - [ ] Test backup restoration procedures
  - [ ] Monitor backup performance impact
  - [ ] Consider backup compression

## Performance Testing and Validation

### 1. Pre-Tuning Metrics Collection
- [ ] **Baseline Performance Metrics**
  - [ ] CPU utilization patterns
  - [ ] Memory usage and cache hit ratios
  - [ ] I/O throughput and latency
  - [ ] Query response times
  - [ ] Connection and concurrency levels

### 2. Tuning Implementation
- [ ] **Change Management Process**
  - [ ] Implement changes incrementally
  - [ ] Test each change in isolation
  - [ ] Document all configuration changes
  - [ ] Maintain rollback procedures

### 3. Post-Tuning Validation
- [ ] **Performance Comparison**
  - [ ] Compare before/after metrics
  - [ ] Validate improvement in target areas
  - [ ] Check for any performance regressions
  - [ ] Document performance gains

- [ ] **Load Testing**
  - [ ] Run representative workload tests
  - [ ] Test under peak load conditions
  - [ ] Validate scalability improvements
  - [ ] Monitor resource utilization

### 4. Success Criteria
- [ ] **Performance Targets Met**
  - [ ] Query response time improvements: Target 20-30% reduction
  - [ ] Throughput improvements: Target 15-25% increase
  - [ ] Resource utilization optimization: Target 10-20% reduction
  - [ ] Cache hit ratio improvements: Target >95%

## Maintenance and Monitoring

### 1. Ongoing Monitoring
- [ ] **Performance Metrics Dashboard**
  - [ ] Real-time performance indicators
  - [ ] Historical trend analysis
  - [ ] Alert thresholds configured
  - [ ] Regular review schedule established

- [ ] **Automated Monitoring**
  - [ ] Performance degradation alerts
  - [ ] Resource utilization warnings
  - [ ] Query performance regression detection
  - [ ] Index fragmentation monitoring

### 2. Regular Maintenance Tasks
- [ ] **Weekly Tasks**
  - [ ] Review slow query logs
  - [ ] Check index fragmentation levels
  - [ ] Monitor storage growth
  - [ ] Validate backup completion

- [ ] **Monthly Tasks**
  - [ ] Update database statistics
  - [ ] Review and optimize indexes
  - [ ] Analyze query performance trends
  - [ ] Review configuration parameters

- [ ] **Quarterly Tasks**
  - [ ] Comprehensive performance review
  - [ ] Capacity planning assessment
  - [ ] Configuration optimization review
  - [ ] Disaster recovery testing

### 3. Documentation and Knowledge Management
- [ ] **Configuration Documentation**
  - [ ] Current configuration parameters
  - [ ] Change history and rationale
  - [ ] Performance impact analysis
  - [ ] Rollback procedures

- [ ] **Performance Baselines**
  - [ ] Regular baseline updates
  - [ ] Seasonal adjustment factors
  - [ ] Growth trend analysis
  - [ ] Capacity planning projections

## Tuning Success Metrics

### 1. Performance Improvements
- **Query Performance**: 20-30% reduction in average query response time
- **Throughput**: 15-25% increase in transactions per second
- **Resource Efficiency**: 10-20% reduction in CPU and memory usage
- **Cache Efficiency**: >95% buffer cache hit ratio
- **I/O Performance**: 20-40% reduction in physical I/O operations

### 2. Operational Improvements
- **Availability**: >99.9% uptime during business hours
- **Scalability**: Support 25-50% more concurrent users
- **Maintenance**: 30-50% reduction in maintenance window duration
- **Monitoring**: <5 minute alert response time for critical issues

### 3. Business Impact
- **User Experience**: Improved application response times
- **Cost Optimization**: Reduced infrastructure requirements
- **Scalability**: Support for business growth without hardware upgrades
- **Reliability**: Reduced performance-related incidents

## Risk Mitigation

### 1. Change Management
- **Testing**: All changes tested in non-production environment
- **Rollback Plan**: Documented rollback procedures for each change
- **Monitoring**: Enhanced monitoring during and after changes
- **Communication**: Stakeholder notification for all changes

### 2. Performance Regression Prevention
- **Baseline Monitoring**: Continuous comparison against performance baselines
- **Automated Alerts**: Immediate notification of performance degradation
- **Regular Reviews**: Weekly performance trend analysis
- **Proactive Optimization**: Address issues before they impact users