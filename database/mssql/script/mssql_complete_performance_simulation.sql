-- ================================================
-- SQL Server COMPLETE Performance Tuning Simulation
-- Complete Before & After Comparison
-- ================================================

-- ========================================
-- 1. SETUP: Enable Query Store & Monitoring
-- ========================================

-- Create table to store test results
DROP TABLE IF EXISTS performance_baseline;
CREATE TABLE performance_baseline (
    test_id INT IDENTITY(1,1) PRIMARY KEY,
    test_name VARCHAR(100) NOT NULL,
    test_phase VARCHAR(20) NOT NULL, -- 'BEFORE' or 'AFTER'
    execution_time_ms DECIMAL(10,3),
    cpu_time_ms DECIMAL(10,3),
    logical_reads BIGINT,
    physical_reads BIGINT,
    cache_hit_ratio DECIMAL(5,2),
    test_timestamp DATETIME2 DEFAULT GETDATE(),
    notes NVARCHAR(MAX)
);

-- Enable Query Store if not already enabled
ALTER DATABASE CURRENT SET QUERY_STORE = ON 
(
    OPERATION_MODE = READ_WRITE,
    CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30),
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    INTERVAL_LENGTH_MINUTES = 60,
    MAX_STORAGE_SIZE_MB = 1000,
    QUERY_CAPTURE_MODE = AUTO,
    SIZE_BASED_CLEANUP_MODE = AUTO
);

-- Clear Query Store for clean baseline
ALTER DATABASE CURRENT SET QUERY_STORE CLEAR;

-- ========================================
-- 2. CREATE SAMPLE TABLES (E-COMMERCE SCENARIO)
-- ========================================

-- Customers table
DROP TABLE IF EXISTS dbo.order_items;
DROP TABLE IF EXISTS dbo.orders;
DROP TABLE IF EXISTS dbo.reviews;
DROP TABLE IF EXISTS dbo.customers;
DROP TABLE IF EXISTS dbo.products;

CREATE TABLE dbo.customers (
    id INT IDENTITY(1,1) PRIMARY KEY,
    email NVARCHAR(255) UNIQUE NOT NULL,
    first_name NVARCHAR(100) NOT NULL,
    last_name NVARCHAR(100) NOT NULL,
    phone NVARCHAR(20),
    address NVARCHAR(MAX),
    city NVARCHAR(100),
    country NVARCHAR(100),
    registration_date DATETIME2 DEFAULT GETDATE(),
    is_active BIT DEFAULT 1,
    last_login DATETIME2 NULL,
    total_orders INT DEFAULT 0
);

-- Products table
CREATE TABLE dbo.products (
    id INT IDENTITY(1,1) PRIMARY KEY,
    name NVARCHAR(255) NOT NULL,
    description NVARCHAR(MAX),
    category NVARCHAR(100) NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    stock_quantity INT DEFAULT 0,
    is_active BIT DEFAULT 1,
    created_at DATETIME2 DEFAULT GETDATE(),
    updated_at DATETIME2 DEFAULT GETDATE(),
    manufacturer NVARCHAR(100),
    weight DECIMAL(8,2),
    dimensions NVARCHAR(50)
);

-- Orders table (main performance testing table)
CREATE TABLE dbo.orders (
    id INT IDENTITY(1,1) PRIMARY KEY,
    customer_id INT NOT NULL,
    order_date DATETIME2 DEFAULT GETDATE(),
    status NVARCHAR(20) DEFAULT 'pending',
    total_amount DECIMAL(12,2) NOT NULL,
    shipping_address NVARCHAR(MAX),
    shipping_method NVARCHAR(50),
    payment_method NVARCHAR(50),
    notes NVARCHAR(MAX),
    processed_at DATETIME2 NULL,
    shipped_at DATETIME2 NULL,
    delivered_at DATETIME2 NULL,
    created_at DATETIME2 DEFAULT GETDATE(),
    updated_at DATETIME2 DEFAULT GETDATE()
);

-- Order items table
CREATE TABLE dbo.order_items (
    id INT IDENTITY(1,1) PRIMARY KEY,
    order_id INT NOT NULL,
    product_id INT NOT NULL,
    quantity INT NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    total_price DECIMAL(12,2) NOT NULL,
    created_at DATETIME2 DEFAULT GETDATE()
);

-- Reviews table
CREATE TABLE dbo.reviews (
    id INT IDENTITY(1,1) PRIMARY KEY,
    product_id INT NOT NULL,
    customer_id INT NOT NULL,
    rating INT CHECK (rating >= 1 AND rating <= 5),
    review_text NVARCHAR(MAX),
    is_verified BIT DEFAULT 0,
    created_at DATETIME2 DEFAULT GETDATE(),
    updated_at DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT UK_reviews_product_customer UNIQUE (product_id, customer_id)
);

-- ========================================
-- 3. GENERATE LARGE SAMPLE DATA
-- ========================================

-- Create a numbers CTE for data generation
WITH numbers AS (
    SELECT 1 as n
    UNION ALL
    SELECT n + 1
    FROM numbers
    WHERE n < 50000
)
-- Insert customers (50,000 records)
INSERT INTO dbo.customers (email, first_name, last_name, phone, address, city, country, registration_date, is_active, last_login, total_orders)
SELECT 
    CONCAT('user', n, '@example.com'),
    CONCAT('FirstName', n),
    CONCAT('LastName', n),
    CONCAT('+66', FORMAT(ABS(CHECKSUM(NEWID()) % 999999999), 'D9')),
    CONCAT(n, ' Main Street'),
    CASE (n % 10)
        WHEN 0 THEN 'Bangkok'
        WHEN 1 THEN 'Chiang Mai' 
        WHEN 2 THEN 'Phuket'
        WHEN 3 THEN 'Pattaya'
        WHEN 4 THEN 'Khon Kaen'
        WHEN 5 THEN 'Hat Yai'
        WHEN 6 THEN 'Nakhon Ratchasima'
        WHEN 7 THEN 'Udon Thani'
        WHEN 8 THEN 'Chon Buri'
        ELSE 'Rayong'
    END,
    'Thailand',
    DATEADD(DAY, -ABS(CHECKSUM(NEWID()) % 730), GETDATE()),
    CASE WHEN ABS(CHECKSUM(NEWID()) % 10) > 1 THEN 1 ELSE 0 END,
    DATEADD(DAY, -ABS(CHECKSUM(NEWID()) % 30), GETDATE()),
    ABS(CHECKSUM(NEWID()) % 20)
FROM numbers
OPTION (MAXRECURSION 50000);

-- Reset and create products data
WITH numbers AS (
    SELECT 1 as n
    UNION ALL
    SELECT n + 1
    FROM numbers
    WHERE n < 10000
)
-- Insert products (10,000 records)
INSERT INTO dbo.products (name, description, category, price, stock_quantity, is_active, created_at, manufacturer, weight, dimensions)
SELECT 
    CONCAT('Product ', n, ' - ', 
    CASE (n % 6)
        WHEN 0 THEN 'Smartphone'
        WHEN 1 THEN 'Laptop'
        WHEN 2 THEN 'Tablet'
        WHEN 3 THEN 'Headphones'
        WHEN 4 THEN 'Camera'
        ELSE 'Watch'
    END),
    'High quality product with advanced features and excellent performance.',
    CASE (n % 6)
        WHEN 0 THEN 'electronics'
        WHEN 1 THEN 'computers'
        WHEN 2 THEN 'electronics'
        WHEN 3 THEN 'audio'
        WHEN 4 THEN 'photography'
        ELSE 'accessories'
    END,
    ROUND(RAND(CHECKSUM(NEWID())) * 2000 + 100, 2),
    ABS(CHECKSUM(NEWID()) % 1000),
    CASE WHEN ABS(CHECKSUM(NEWID()) % 100) > 15 THEN 1 ELSE 0 END,
    DATEADD(DAY, -ABS(CHECKSUM(NEWID()) % 365), GETDATE()),
    CASE (n % 5)
        WHEN 0 THEN 'Apple'
        WHEN 1 THEN 'Samsung'
        WHEN 2 THEN 'Sony'
        WHEN 3 THEN 'LG'
        ELSE 'Huawei'
    END,
    ROUND(RAND(CHECKSUM(NEWID())) * 5 + 0.1, 2),
    CONCAT(ROUND(RAND(CHECKSUM(NEWID())) * 30 + 5, 0), 'x', 
           ROUND(RAND(CHECKSUM(NEWID())) * 20 + 3, 0), 'x', 
           ROUND(RAND(CHECKSUM(NEWID())) * 10 + 1, 0), 'cm')
FROM numbers
OPTION (MAXRECURSION 10000);

-- Reset and create orders data
WITH numbers AS (
    SELECT 1 as n
    UNION ALL
    SELECT n + 1
    FROM numbers
    WHERE n < 200000
)
-- Insert orders (200,000 records)
INSERT INTO dbo.orders (customer_id, order_date, status, total_amount, shipping_address, shipping_method, payment_method, notes, processed_at, shipped_at, delivered_at, created_at)
SELECT 
    (ABS(CHECKSUM(NEWID())) % 49999) + 1,
    DATEADD(DAY, -ABS(CHECKSUM(NEWID()) % 545), GETDATE()),
    CASE (ABS(CHECKSUM(NEWID())) % 10)
        WHEN 0 THEN 'pending'
        WHEN 1 THEN 'processing'
        WHEN 2 THEN 'shipped'
        WHEN 3 THEN 'delivered'
        WHEN 4 THEN 'cancelled'
        ELSE 'completed'
    END,
    ROUND(RAND(CHECKSUM(NEWID())) * 5000 + 50, 2),
    CONCAT('Shipping address for order ', n),
    CASE (ABS(CHECKSUM(NEWID())) % 3)
        WHEN 0 THEN 'standard'
        WHEN 1 THEN 'express'
        ELSE 'overnight'
    END,
    CASE (ABS(CHECKSUM(NEWID())) % 4)
        WHEN 0 THEN 'credit_card'
        WHEN 1 THEN 'bank_transfer'
        WHEN 2 THEN 'paypal'
        ELSE 'cash_on_delivery'
    END,
    CASE WHEN ABS(CHECKSUM(NEWID()) % 10) > 7 THEN CONCAT('Special delivery instructions for order ', n) ELSE NULL END,
    CASE WHEN ABS(CHECKSUM(NEWID()) % 10) > 2 THEN DATEADD(DAY, -ABS(CHECKSUM(NEWID()) % 545), GETDATE()) ELSE NULL END,
    CASE WHEN ABS(CHECKSUM(NEWID()) % 10) > 3 THEN DATEADD(DAY, -ABS(CHECKSUM(NEWID()) % 515), GETDATE()) ELSE NULL END,
    CASE WHEN ABS(CHECKSUM(NEWID()) % 10) > 4 THEN DATEADD(DAY, -ABS(CHECKSUM(NEWID()) % 485), GETDATE()) ELSE NULL END,
    DATEADD(DAY, -ABS(CHECKSUM(NEWID()) % 545), GETDATE())
FROM numbers
OPTION (MAXRECURSION 200000);

-- Insert order items (limited batch for performance)
INSERT INTO dbo.order_items (order_id, product_id, quantity, unit_price, total_price)
SELECT 
    o.id,
    (ABS(CHECKSUM(NEWID())) % 9999) + 1,
    (ABS(CHECKSUM(NEWID())) % 5) + 1,
    ROUND(RAND(CHECKSUM(NEWID())) * 1000 + 10, 2),
    ROUND(((ABS(CHECKSUM(NEWID())) % 5) + 1) * (RAND(CHECKSUM(NEWID())) * 1000 + 10), 2)
FROM dbo.orders o
WHERE o.id <= 50000;

-- Continue with more order items
INSERT INTO dbo.order_items (order_id, product_id, quantity, unit_price, total_price)
SELECT 
    o.id,
    (ABS(CHECKSUM(NEWID())) % 9999) + 1,
    (ABS(CHECKSUM(NEWID())) % 5) + 1,
    ROUND(RAND(CHECKSUM(NEWID())) * 1000 + 10, 2),
    ROUND(((ABS(CHECKSUM(NEWID())) % 5) + 1) * (RAND(CHECKSUM(NEWID())) * 1000 + 10), 2)
FROM dbo.orders o
WHERE o.id > 50000 AND o.id <= 100000;

-- Insert reviews with duplicate handling
WITH review_data AS (
    SELECT TOP 100000
        (ABS(CHECKSUM(NEWID())) % 9999) + 1 AS product_id,
        (ABS(CHECKSUM(NEWID())) % 49999) + 1 AS customer_id,
        (ABS(CHECKSUM(NEWID())) % 5) + 1 AS rating,
        CASE WHEN ABS(CHECKSUM(NEWID()) % 10) > 3 THEN 
            CONCAT('This is a great product! ', 
            CASE (ABS(CHECKSUM(NEWID())) % 3)
                WHEN 0 THEN 'Excellent quality and fast delivery!'
                WHEN 1 THEN 'Good value for money, recommended.'
                ELSE 'Average product, nothing special.'
            END)
        ELSE NULL END AS review_text,
        CASE WHEN ABS(CHECKSUM(NEWID()) % 10) > 4 THEN 1 ELSE 0 END AS is_verified,
        DATEADD(DAY, -ABS(CHECKSUM(NEWID()) % 365), GETDATE()) AS created_at,
        ROW_NUMBER() OVER (PARTITION BY 
            (ABS(CHECKSUM(NEWID())) % 9999) + 1,
            (ABS(CHECKSUM(NEWID())) % 49999) + 1 
            ORDER BY NEWID()) as rn
    FROM dbo.orders  -- Use existing table for row generation
)
INSERT INTO dbo.reviews (product_id, customer_id, rating, review_text, is_verified, created_at)
SELECT product_id, customer_id, rating, review_text, is_verified, created_at
FROM review_data
WHERE rn = 1;  -- Only take first occurrence to avoid duplicates

-- Update statistics
UPDATE STATISTICS dbo.customers;
UPDATE STATISTICS dbo.products;
UPDATE STATISTICS dbo.orders;
UPDATE STATISTICS dbo.order_items;
UPDATE STATISTICS dbo.reviews;

-- ========================================
-- 4. CREATE BAD INDEXES (Simulate Problems)
-- ========================================

-- Create bad indexes to simulate problems
CREATE NONCLUSTERED INDEX IX_customers_unused1 ON dbo.customers (phone);    -- Rarely queried
CREATE NONCLUSTERED INDEX IX_customers_unused2 ON dbo.customers (address);  -- Text field, inefficient
CREATE NONCLUSTERED INDEX IX_products_unused ON dbo.products (weight);  -- Rarely queried
CREATE NONCLUSTERED INDEX IX_orders_unused ON dbo.orders (notes);   -- Text field, rarely queried
CREATE NONCLUSTERED INDEX IX_orders_wrong_order ON dbo.orders (total_amount, status); -- Wrong order for typical queries

-- ========================================
-- 5. BASELINE PERFORMANCE CAPTURE PROCEDURES
-- ========================================

-- Procedure to capture query performance using SQL Server methods
GO
CREATE OR ALTER PROCEDURE capture_query_performance
    @test_name_param VARCHAR(100),
    @test_phase_param VARCHAR(20),
    @query_text NVARCHAR(MAX),
    @execution_time_ms DECIMAL(10,3) OUTPUT,
    @cpu_time_ms DECIMAL(10,3) OUTPUT,
    @logical_reads BIGINT OUTPUT
AS
BEGIN
    DECLARE @start_time DATETIME2(7);
    DECLARE @end_time DATETIME2(7);
    DECLARE @exec_time DECIMAL(10,3);
    DECLARE @cpu_start BIGINT, @cpu_end BIGINT;
    DECLARE @reads_start BIGINT, @reads_end BIGINT;
    DECLARE @row_count BIGINT = 0;
    
    -- Capture initial metrics
    SELECT @cpu_start = cpu_time, @reads_start = logical_reads 
    FROM sys.dm_exec_sessions WHERE session_id = @@SPID;
    
    SET @start_time = SYSDATETIME();
    
    -- Execute dynamic SQL and count rows
    DECLARE @count_query NVARCHAR(MAX) = N'SELECT @row_count = COUNT(*) FROM (' + @query_text + N') as subquery';
    EXEC sp_executesql @count_query, N'@row_count BIGINT OUTPUT', @row_count OUTPUT;
    
    SET @end_time = SYSDATETIME();
    
    -- Capture final metrics
    SELECT @cpu_end = cpu_time, @reads_end = logical_reads 
    FROM sys.dm_exec_sessions WHERE session_id = @@SPID;
    
    -- Calculate execution time
    SET @exec_time = DATEDIFF_BIG(microsecond, @start_time, @end_time) / 1000.0;
    
    -- Insert into baseline table
    INSERT INTO performance_baseline (test_name, test_phase, execution_time_ms, cpu_time_ms, logical_reads, test_timestamp)
    VALUES (@test_name_param, @test_phase_param, @exec_time, (@cpu_end - @cpu_start), (@reads_end - @reads_start), GETDATE());
    
    -- Return values
    SET @execution_time_ms = @exec_time;
    SET @cpu_time_ms = (@cpu_end - @cpu_start);
    SET @logical_reads = (@reads_end - @reads_start);
END;
GO

-- Procedure to capture buffer cache hit ratio
CREATE OR ALTER PROCEDURE capture_cache_metrics
    @test_name_param VARCHAR(100), 
    @test_phase_param VARCHAR(20),
    @cache_hit_ratio DECIMAL(5,2) OUTPUT
AS
BEGIN
    DECLARE @hit_ratio DECIMAL(5,2) = 0;
    
    -- Get Buffer Pool Hit Ratio from SQL Server
    SELECT @hit_ratio = 
        CASE 
            WHEN b.cntr_value = 0 THEN 0
            ELSE (a.cntr_value * 1.0 / b.cntr_value) * 100.0 
        END
    FROM sys.dm_os_performance_counters a
        INNER JOIN sys.dm_os_performance_counters b ON a.object_name = b.object_name
    WHERE a.counter_name = 'Buffer cache hit ratio'
        AND b.counter_name = 'Buffer cache hit ratio base'
        AND a.object_name LIKE '%Buffer Manager%';
    
    -- Insert into baseline table
    INSERT INTO performance_baseline (test_name, test_phase, cache_hit_ratio, test_timestamp)
    VALUES (@test_name_param, @test_phase_param, @hit_ratio, GETDATE());
    
    SET @cache_hit_ratio = @hit_ratio;
END;
GO

-- ========================================
-- 6. COMPREHENSIVE BEFORE TESTING
-- ========================================

-- Clear previous Query Store data for clean measurement
ALTER DATABASE CURRENT SET QUERY_STORE CLEAR;

PRINT '🧪 STARTING BEFORE TESTING...';

-- Test Suite 1: Simple Queries (should be slow without indexes)
DECLARE @exec_time DECIMAL(10,3), @cpu_time DECIMAL(10,3), @logical_reads BIGINT;

-- Test 1.1: Single WHERE condition
EXEC capture_query_performance 
    'Single WHERE - Status',
    'BEFORE',
    N'SELECT * FROM dbo.orders WHERE status = ''pending''',
    @exec_time OUTPUT, @cpu_time OUTPUT, @logical_reads OUTPUT;
PRINT CONCAT('Test completed: ', @exec_time, ' ms, CPU: ', @cpu_time, ' ms, Reads: ', @logical_reads);

-- Test 1.2: Date Range Query
EXEC capture_query_performance 
    'Date Range Query',
    'BEFORE', 
    N'SELECT * FROM dbo.orders WHERE order_date >= ''2024-01-01''',
    @exec_time OUTPUT, @cpu_time OUTPUT, @logical_reads OUTPUT;
PRINT CONCAT('Test completed: ', @exec_time, ' ms, CPU: ', @cpu_time, ' ms, Reads: ', @logical_reads);

-- Test 1.3: Multiple WHERE conditions
EXEC capture_query_performance 
    'Multiple WHERE',
    'BEFORE',
    N'SELECT * FROM dbo.orders WHERE status = ''completed'' AND total_amount > 1000',
    @exec_time OUTPUT, @cpu_time OUTPUT, @logical_reads OUTPUT;
PRINT CONCAT('Test completed: ', @exec_time, ' ms, CPU: ', @cpu_time, ' ms, Reads: ', @logical_reads);

-- Test Suite 2: JOIN Queries (will be very slow without indexes)
-- Test 2.1: Simple JOIN
EXEC capture_query_performance 
    'Simple JOIN',
    'BEFORE',
    N'SELECT o.*, c.first_name FROM dbo.orders o INNER JOIN dbo.customers c ON o.customer_id = c.id WHERE c.city = ''Bangkok''',
    @exec_time OUTPUT, @cpu_time OUTPUT, @logical_reads OUTPUT;
PRINT CONCAT('Test completed: ', @exec_time, ' ms, CPU: ', @cpu_time, ' ms, Reads: ', @logical_reads);

-- Test 2.2: Complex JOIN with WHERE
EXEC capture_query_performance 
    'Complex JOIN',
    'BEFORE',
    N'SELECT o.id, c.first_name, oi.quantity FROM dbo.orders o INNER JOIN dbo.customers c ON o.customer_id = c.id INNER JOIN dbo.order_items oi ON o.id = oi.order_id WHERE c.city = ''Bangkok'' AND o.status = ''completed'' AND oi.quantity > 2',
    @exec_time OUTPUT, @cpu_time OUTPUT, @logical_reads OUTPUT;
PRINT CONCAT('Test completed: ', @exec_time, ' ms, CPU: ', @cpu_time, ' ms, Reads: ', @logical_reads);

-- Test Suite 3: Aggregation Queries
-- Test 3.1: GROUP BY on large table
EXEC capture_query_performance 
    'GROUP BY Category',
    'BEFORE',
    N'SELECT category, COUNT(*), AVG(price) FROM dbo.products WHERE is_active = 1 GROUP BY category',
    @exec_time OUTPUT, @cpu_time OUTPUT, @logical_reads OUTPUT;
PRINT CONCAT('Test completed: ', @exec_time, ' ms, CPU: ', @cpu_time, ' ms, Reads: ', @logical_reads);

-- Test 3.2: Complex aggregation with JOIN
EXEC capture_query_performance 
    'Complex Aggregation',
    'BEFORE',
    N'SELECT c.city, COUNT(o.id) as order_count, SUM(o.total_amount) as total_revenue FROM dbo.customers c LEFT JOIN dbo.orders o ON c.id = o.customer_id WHERE c.registration_date >= ''2023-01-01'' GROUP BY c.city HAVING COUNT(o.id) > 10',
    @exec_time OUTPUT, @cpu_time OUTPUT, @logical_reads OUTPUT;
PRINT CONCAT('Test completed: ', @exec_time, ' ms, CPU: ', @cpu_time, ' ms, Reads: ', @logical_reads);

-- Test Suite 4: Text Search (slow without proper indexing)
-- Test 4.1: LIKE search
EXEC capture_query_performance 
    'Text Search LIKE',
    'BEFORE',
    N'SELECT * FROM dbo.products WHERE name LIKE ''%phone%'' OR description LIKE ''%smartphone%''',
    @exec_time OUTPUT, @cpu_time OUTPUT, @logical_reads OUTPUT;
PRINT CONCAT('Test completed: ', @exec_time, ' ms, CPU: ', @cpu_time, ' ms, Reads: ', @logical_reads);

-- Test Suite 5: Subquery Performance
-- Test 5.1: Correlated subquery
EXEC capture_query_performance 
    'Correlated Subquery', 
    'BEFORE',
    N'SELECT * FROM dbo.customers c WHERE (SELECT COUNT(*) FROM dbo.orders WHERE customer_id = c.id AND status = ''completed'') > 5',
    @exec_time OUTPUT, @cpu_time OUTPUT, @logical_reads OUTPUT;
PRINT CONCAT('Test completed: ', @exec_time, ' ms, CPU: ', @cpu_time, ' ms, Reads: ', @logical_reads);

-- Capture baseline cache performance
DECLARE @cache_ratio DECIMAL(5,2);
EXEC capture_cache_metrics 'Overall Cache Performance', 'BEFORE', @cache_ratio OUTPUT;
PRINT CONCAT('Cache hit ratio: ', @cache_ratio, '%');

-- ========================================
-- 7. DISPLAY BEFORE RESULTS
-- ========================================

SELECT 
    '📊 BEFORE OPTIMIZATION RESULTS' as title,
    '════════════════════════════════════════════════════════════════════' as separator;

-- BEFORE OPTIMIZATION RESULTS
SELECT 
    test_name,
    CONCAT(execution_time_ms, ' ms') as execution_time,
    CONCAT(cpu_time_ms, ' ms') as cpu_time,
    CONCAT(logical_reads, ' pages') as logical_reads,
    CASE 
        WHEN execution_time_ms < 50 THEN '🟢 Fast'
        WHEN execution_time_ms < 200 THEN '🟡 OK'
        WHEN execution_time_ms < 1000 THEN '🟠 Slow'
        ELSE '🔴 Very Slow'
    END as performance_status
FROM performance_baseline 
WHERE test_phase = 'BEFORE' 
    AND execution_time_ms IS NOT NULL
ORDER BY execution_time_ms DESC;

-- Cache performance before
SELECT 
    CONCAT('Cache Hit Ratio (BEFORE): ', cache_hit_ratio, '%') as cache_performance,
    CASE 
        WHEN cache_hit_ratio > 98 THEN '🟢 Excellent'
        WHEN cache_hit_ratio > 95 THEN '🟢 Good'
        WHEN cache_hit_ratio > 90 THEN '🟡 OK'
        ELSE '🔴 Poor'
    END as cache_status
FROM performance_baseline 
WHERE test_phase = 'BEFORE' 
    AND cache_hit_ratio IS NOT NULL
ORDER BY test_timestamp DESC;

-- ========================================
-- 8. OPTIMIZATION IMPLEMENTATION
-- ========================================

PRINT '⚡ APPLYING OPTIMIZATIONS...';

-- Remove bad indexes first
DROP INDEX IF EXISTS IX_customers_unused1 ON dbo.customers;
DROP INDEX IF EXISTS IX_customers_unused2 ON dbo.customers;
DROP INDEX IF EXISTS IX_products_unused ON dbo.products;
DROP INDEX IF EXISTS IX_orders_unused ON dbo.orders;
DROP INDEX IF EXISTS IX_orders_wrong_order ON dbo.orders;

-- Create optimized indexes
-- For single column queries
CREATE NONCLUSTERED INDEX IX_orders_status_opt ON dbo.orders (status);
CREATE NONCLUSTERED INDEX IX_orders_date_opt ON dbo.orders (order_date);
CREATE NONCLUSTERED INDEX IX_customers_city_opt ON dbo.customers (city);

-- For multiple column queries (composite indexes)
CREATE NONCLUSTERED INDEX IX_orders_status_amount_opt ON dbo.orders (status, total_amount);
CREATE NONCLUSTERED INDEX IX_orders_status_date_opt ON dbo.orders (status, order_date);
CREATE NONCLUSTERED INDEX IX_customers_city_registration_opt ON dbo.customers (city, registration_date);

-- For JOIN performance
CREATE NONCLUSTERED INDEX IX_orders_customer_id_opt ON dbo.orders (customer_id);
CREATE NONCLUSTERED INDEX IX_order_items_order_id_opt ON dbo.order_items (order_id);
CREATE NONCLUSTERED INDEX IX_order_items_product_id_opt ON dbo.order_items (product_id);
CREATE NONCLUSTERED INDEX IX_reviews_product_id_opt ON dbo.reviews (product_id);

-- Covering indexes (include commonly selected columns)
CREATE NONCLUSTERED INDEX IX_orders_status_covering_opt ON dbo.orders (status) 
    INCLUDE (id, customer_id, order_date, total_amount);
CREATE NONCLUSTERED INDEX IX_customers_city_covering_opt ON dbo.customers (city) 
    INCLUDE (id, first_name, last_name, registration_date);

-- Filtered indexes for active records
CREATE NONCLUSTERED INDEX IX_products_category_active_opt ON dbo.products (category) 
    WHERE is_active = 1;
CREATE NONCLUSTERED INDEX IX_customers_active_city_opt ON dbo.customers (city) 
    WHERE is_active = 1;

-- Text search optimization using Full-Text Search (if available)
-- This would require Full-Text Search to be installed and configured
-- CREATE FULLTEXT CATALOG ProductCatalog;
-- CREATE FULLTEXT INDEX ON dbo.products (name, description) KEY INDEX PK__products__3213E83F...;

-- Additional performance indexes
CREATE NONCLUSTERED INDEX IX_order_items_quantity_opt ON dbo.order_items (quantity);
CREATE NONCLUSTERED INDEX IX_customers_registration_opt ON dbo.customers (registration_date);
CREATE NONCLUSTERED INDEX IX_orders_total_amount_opt ON dbo.orders (total_amount);

-- Add proper foreign key constraints
ALTER TABLE dbo.orders ADD CONSTRAINT FK_orders_customer_id 
    FOREIGN KEY (customer_id) REFERENCES dbo.customers(id);

ALTER TABLE dbo.order_items ADD CONSTRAINT FK_order_items_order_id 
    FOREIGN KEY (order_id) REFERENCES dbo.orders(id);

ALTER TABLE dbo.order_items ADD CONSTRAINT FK_order_items_product_id 
    FOREIGN KEY (product_id) REFERENCES dbo.products(id);

ALTER TABLE dbo.reviews ADD CONSTRAINT FK_reviews_product_id 
    FOREIGN KEY (product_id) REFERENCES dbo.products(id);

ALTER TABLE dbo.reviews ADD CONSTRAINT FK_reviews_customer_id 
    FOREIGN KEY (customer_id) REFERENCES dbo.customers(id);

-- Update statistics after index creation
UPDATE STATISTICS dbo.customers;
UPDATE STATISTICS dbo.products;
UPDATE STATISTICS dbo.orders;
UPDATE STATISTICS dbo.order_items;
UPDATE STATISTICS dbo.reviews;

-- ========================================
-- 9. COMPREHENSIVE AFTER TESTING
-- ========================================

-- Clear Query Store for clean measurement of optimized performance
ALTER DATABASE CURRENT SET QUERY_STORE CLEAR;

PRINT '🧪 STARTING AFTER TESTING...';

-- Test Suite 1: Simple Queries (should be much faster now)
-- Test 1.1: Single WHERE condition
EXEC capture_query_performance 
    'Single WHERE - Status',
    'AFTER',
    N'SELECT * FROM dbo.orders WHERE status = ''pending''',
    @exec_time OUTPUT, @cpu_time OUTPUT, @logical_reads OUTPUT;
PRINT CONCAT('Test completed: ', @exec_time, ' ms, CPU: ', @cpu_time, ' ms, Reads: ', @logical_reads);

-- Test 1.2: Date Range Query
EXEC capture_query_performance 
    'Date Range Query',
    'AFTER',
    N'SELECT * FROM dbo.orders WHERE order_date >= ''2024-01-01''',
    @exec_time OUTPUT, @cpu_time OUTPUT, @logical_reads OUTPUT;
PRINT CONCAT('Test completed: ', @exec_time, ' ms, CPU: ', @cpu_time, ' ms, Reads: ', @logical_reads);

-- Test 1.3: Multiple WHERE conditions
EXEC capture_query_performance 
    'Multiple WHERE',
    'AFTER',
    N'SELECT * FROM dbo.orders WHERE status = ''completed'' AND total_amount > 1000',
    @exec_time OUTPUT, @cpu_time OUTPUT, @logical_reads OUTPUT;
PRINT CONCAT('Test completed: ', @exec_time, ' ms, CPU: ', @cpu_time, ' ms, Reads: ', @logical_reads);

-- Test Suite 2: JOIN Queries (should be much faster now)
-- Test 2.1: Simple JOIN
EXEC capture_query_performance 
    'Simple JOIN',
    'AFTER',
    N'SELECT o.*, c.first_name FROM dbo.orders o INNER JOIN dbo.customers c ON o.customer_id = c.id WHERE c.city = ''Bangkok''',
    @exec_time OUTPUT, @cpu_time OUTPUT, @logical_reads OUTPUT;
PRINT CONCAT('Test completed: ', @exec_time, ' ms, CPU: ', @cpu_time, ' ms, Reads: ', @logical_reads);

-- Test 2.2: Complex JOIN with WHERE
EXEC capture_query_performance 
    'Complex JOIN',
    'AFTER',
    N'SELECT o.id, c.first_name, oi.quantity FROM dbo.orders o INNER JOIN dbo.customers c ON o.customer_id = c.id INNER JOIN dbo.order_items oi ON o.id = oi.order_id WHERE c.city = ''Bangkok'' AND o.status = ''completed'' AND oi.quantity > 2',
    @exec_time OUTPUT, @cpu_time OUTPUT, @logical_reads OUTPUT;
PRINT CONCAT('Test completed: ', @exec_time, ' ms, CPU: ', @cpu_time, ' ms, Reads: ', @logical_reads);

-- Test Suite 3: Aggregation Queries
-- Test 3.1: GROUP BY on large table (using optimized indexes)
EXEC capture_query_performance 
    'GROUP BY Category',
    'AFTER',
    N'SELECT category, COUNT(*), AVG(price) FROM dbo.products WHERE is_active = 1 GROUP BY category',
    @exec_time OUTPUT, @cpu_time OUTPUT, @logical_reads OUTPUT;
PRINT CONCAT('Test completed: ', @exec_time, ' ms, CPU: ', @cpu_time, ' ms, Reads: ', @logical_reads);

-- Test 3.2: Complex aggregation with JOIN
EXEC capture_query_performance 
    'Complex Aggregation',
    'AFTER',
    N'SELECT c.city, COUNT(o.id) as order_count, SUM(o.total_amount) as total_revenue FROM dbo.customers c LEFT JOIN dbo.orders o ON c.id = o.customer_id WHERE c.registration_date >= ''2023-01-01'' GROUP BY c.city HAVING COUNT(o.id) > 10',
    @exec_time OUTPUT, @cpu_time OUTPUT, @logical_reads OUTPUT;
PRINT CONCAT('Test completed: ', @exec_time, ' ms, CPU: ', @cpu_time, ' ms, Reads: ', @logical_reads);

-- Test Suite 4: Text Search (using optimized approach)
-- Test 4.1: Text search (optimized)
EXEC capture_query_performance 
    'Text Search LIKE',
    'AFTER',
    N'SELECT * FROM dbo.products WHERE name LIKE ''%phone%'' OR description LIKE ''%smartphone%''',
    @exec_time OUTPUT, @cpu_time OUTPUT, @logical_reads OUTPUT;
PRINT CONCAT('Test completed: ', @exec_time, ' ms, CPU: ', @cpu_time, ' ms, Reads: ', @logical_reads);

-- Test Suite 5: Subquery Performance
-- Test 5.1: Correlated subquery
EXEC capture_query_performance 
    'Correlated Subquery',
    'AFTER',
    N'SELECT * FROM dbo.customers c WHERE (SELECT COUNT(*) FROM dbo.orders WHERE customer_id = c.id AND status = ''completed'') > 5',
    @exec_time OUTPUT, @cpu_time OUTPUT, @logical_reads OUTPUT;
PRINT CONCAT('Test completed: ', @exec_time, ' ms, CPU: ', @cpu_time, ' ms, Reads: ', @logical_reads);

-- Capture optimized cache performance
EXEC capture_cache_metrics 'Overall Cache Performance', 'AFTER', @cache_ratio OUTPUT;
PRINT CONCAT('Cache hit ratio: ', @cache_ratio, '%');

-- ========================================
-- 10. COMPREHENSIVE BEFORE/AFTER COMPARISON
-- ========================================

SELECT 
    '🏆 PERFORMANCE IMPROVEMENT REPORT' as title,
    '════════════════════════════════════════════════════════════════════════════════' as separator;

-- Detailed before/after comparison
SELECT
    pb1.test_name as "Test Case",
    CONCAT(ISNULL(pb1.before_ms, 0), ' ms') as "Before",
    CONCAT(ISNULL(pb1.after_ms, 0), ' ms') as "After",
    CONCAT(ISNULL(pb1.before_reads, 0), ' pages') as "Before Reads",
    CONCAT(ISNULL(pb1.after_reads, 0), ' pages') as "After Reads",

    -- Improvement (x faster / slower)
    CASE
        WHEN pb1.before_ms > 0 AND pb1.after_ms > 0 THEN
            CONCAT(
                ROUND(
                    CASE
                        WHEN pb1.after_ms < pb1.before_ms
                            THEN pb1.before_ms / pb1.after_ms
                        ELSE pb1.after_ms / pb1.before_ms
                        END,
                    1),
                CASE
                    WHEN pb1.after_ms < pb1.before_ms THEN 'x faster'
                    ELSE 'x slower'
                    END
            )
        ELSE 'N/A'
        END as "Improvement",

    -- % Improvement (positive number + faster/slower)
    CASE
        WHEN pb1.before_ms > 0 AND pb1.after_ms > 0 THEN
            CONCAT(
                ROUND(
                    ABS((pb1.before_ms - pb1.after_ms) / pb1.before_ms * 100),
                    1
                ),
                CASE
                    WHEN pb1.after_ms < pb1.before_ms THEN '% faster'
                    ELSE '% slower'
                    END
            )
        ELSE 'N/A'
        END as "% Improvement",

    -- Final Status (based on absolute time after optimization)
    CASE
        WHEN ISNULL(pb1.after_ms, 0) < 50 THEN '🟢 Excellent'
        WHEN ISNULL(pb1.after_ms, 0) < 200 THEN '🟢 Good'
        WHEN ISNULL(pb1.after_ms, 0) < 1000 THEN '🟡 OK'
        ELSE '🔴 Needs Work'
        END as "Final Status"

FROM (
    SELECT
        test_name,
        MAX(CASE WHEN test_phase = 'BEFORE' THEN execution_time_ms END) as before_ms,
        MAX(CASE WHEN test_phase = 'AFTER' THEN execution_time_ms END) as after_ms,
        MAX(CASE WHEN test_phase = 'BEFORE' THEN logical_reads END) as before_reads,
        MAX(CASE WHEN test_phase = 'AFTER' THEN logical_reads END) as after_reads,
        MAX(CASE WHEN test_phase = 'BEFORE' THEN cache_hit_ratio END) as cache_before,
        MAX(CASE WHEN test_phase = 'AFTER' THEN cache_hit_ratio END) as cache_after
    FROM performance_baseline
    WHERE execution_time_ms IS NOT NULL OR cache_hit_ratio IS NOT NULL
    GROUP BY test_name
) pb1
WHERE pb1.before_ms IS NOT NULL AND pb1.after_ms IS NOT NULL
ORDER BY
    CASE
        WHEN pb1.before_ms > 0 AND pb1.after_ms > 0
            THEN pb1.before_ms / pb1.after_ms
        ELSE 0
        END DESC;

-- Cache performance comparison
SELECT 
    '💾 CACHE PERFORMANCE COMPARISON' as metric_type,
    '─────────────────────────────────────────────────────────────────' as separator
UNION ALL
SELECT 
    'Cache Hit Ratio' as metric_type,
    CONCAT(
        'Before: ', ISNULL(cache_before, 0), '%  →  After: ', ISNULL(cache_after, 0), '%  (',
        CASE 
            WHEN cache_before > 0 AND cache_after > 0 THEN 
                CONCAT('+', ROUND(cache_after - cache_before, 1), '% improvement)')
            ELSE 'N/A)'
        END
    ) as comparison
FROM (
    SELECT 
        MAX(CASE WHEN test_phase = 'BEFORE' THEN cache_hit_ratio END) as cache_before,
        MAX(CASE WHEN test_phase = 'AFTER' THEN cache_hit_ratio END) as cache_after
    FROM performance_baseline
    WHERE test_name = 'Overall Cache Performance'
) cache_comparison;

-- Summary statistics
WITH summary_stats AS (
    SELECT
        AVG(CASE WHEN test_phase = 'BEFORE' THEN execution_time_ms END) AS avg_before,
        AVG(CASE WHEN test_phase = 'AFTER'  THEN execution_time_ms END) AS avg_after,
        MAX(CASE WHEN test_phase = 'BEFORE' THEN execution_time_ms END) AS max_before,
        MAX(CASE WHEN test_phase = 'AFTER'  THEN execution_time_ms END) AS max_after
    FROM performance_baseline
    WHERE execution_time_ms IS NOT NULL
)
SELECT
    '📈 OVERALL SUMMARY' AS metric_type,
    '─────────────────────────────────────────────────────────────────' AS summary

UNION ALL

SELECT
    'Average Performance',
    CONCAT(
        ROUND(avg_before, 1), ' ms → ', ROUND(avg_after, 1), ' ms (',
        ROUND(
            CASE WHEN avg_after < avg_before
                     THEN avg_before / NULLIF(avg_after, 0)
                 ELSE avg_after / NULLIF(avg_before, 0)
                END, 1
        ),
        CASE WHEN avg_after < avg_before THEN 'x faster overall)' ELSE 'x slower overall)' END
    )
FROM summary_stats

UNION ALL

SELECT
    'Worst Case Performance',
    CONCAT(
        ROUND(max_before, 1), ' ms → ', ROUND(max_after, 1), ' ms (',
        ROUND(
            CASE WHEN max_after < max_before
                     THEN max_before / NULLIF(max_after, 0)
                 ELSE max_after / NULLIF(max_before, 0)
                END, 1
        ),
        CASE WHEN max_after < max_before THEN 'x faster)' ELSE 'x slower)' END
    )
FROM summary_stats;

-- ========================================
-- 11. INDEX USAGE ANALYSIS
-- ========================================
-- Show which new indexes are being used
SELECT
    OBJECT_SCHEMA_NAME(ius.object_id) AS schema_name,
    OBJECT_NAME(ius.object_id) AS table_name,
    i.name AS index_name,
    ius.user_seeks AS times_used_seeks,
    ius.user_scans AS times_used_scans,
    ius.user_lookups AS times_used_lookups,
    ius.user_seeks + ius.user_scans + ius.user_lookups AS total_usage,
    CAST((a.used_pages * 8.0) / 1024 AS decimal(15,2)) AS index_size_mb,
    CASE
        WHEN (ius.user_seeks + ius.user_scans + ius.user_lookups) = 0 THEN '🔴 Not Used'
        WHEN (ius.user_seeks + ius.user_scans + ius.user_lookups) < 10 THEN '🟡 Low Usage'
        WHEN (ius.user_seeks + ius.user_scans + ius.user_lookups) < 100 THEN '🟢 Good Usage'
        ELSE '🟢 High Usage'
        END AS usage_status
FROM sys.dm_db_index_usage_stats ius
    INNER JOIN sys.indexes i ON ius.object_id = i.object_id AND ius.index_id = i.index_id
    INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
    INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
WHERE ius.database_id = DB_ID()
    AND OBJECT_SCHEMA_NAME(ius.object_id) = 'dbo'
    AND i.name IS NOT NULL
    AND i.name LIKE '%_opt'  -- Only optimized indexes we created
GROUP BY ius.object_id, ius.index_id, i.name, ius.user_seeks, ius.user_scans, ius.user_lookups, a.used_pages
ORDER BY total_usage DESC;

-- ========================================
-- 12. FINAL RECOMMENDATIONS
-- ========================================
SELECT 
    'Tests Performed: ' + CAST(COUNT(*) AS VARCHAR(10)) as metric,
    '' as value
FROM (
    SELECT DISTINCT test_name FROM performance_baseline WHERE execution_time_ms IS NOT NULL
) tests
UNION ALL
SELECT 
    'Significantly Improved (>2x): ' + CAST(COUNT(*) AS VARCHAR(10)) as metric,
    '' as value
FROM (
    SELECT 
        test_name,
        MAX(CASE WHEN test_phase = 'BEFORE' THEN execution_time_ms END) as before_ms,
        MAX(CASE WHEN test_phase = 'AFTER' THEN execution_time_ms END) as after_ms
    FROM performance_baseline
    WHERE execution_time_ms IS NOT NULL
    GROUP BY test_name
    HAVING MAX(CASE WHEN test_phase = 'BEFORE' THEN execution_time_ms END) > 
           MAX(CASE WHEN test_phase = 'AFTER' THEN execution_time_ms END) * 2
) significantly_improved
UNION ALL
SELECT 
    'Overall Performance Gain: ' + 
    CAST(ROUND(
        (SELECT AVG(CASE WHEN test_phase = 'BEFORE' THEN execution_time_ms END) FROM performance_baseline WHERE execution_time_ms IS NOT NULL) /
        NULLIF((SELECT AVG(CASE WHEN test_phase = 'AFTER' THEN execution_time_ms END) FROM performance_baseline WHERE execution_time_ms IS NOT NULL), 0),
        1
    ) AS VARCHAR(10)) + 'x faster on average' as metric,
    '' as value;

-- Clean up procedures
DROP PROCEDURE IF EXISTS capture_query_performance;
DROP PROCEDURE IF EXISTS capture_cache_metrics;

SELECT 
    '✅ SQL SERVER PERFORMANCE TUNING SIMULATION COMPLETE!' as status,
    'Check the results above to see dramatic improvements.' as note;

-- ========================================
-- END OF COMPLETE SIMULATION
-- ========================================