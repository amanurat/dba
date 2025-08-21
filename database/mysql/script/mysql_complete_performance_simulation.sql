-- ================================================
-- MySQL COMPLETE Performance Tuning Simulation
-- Complete Before & After Comparison
-- ================================================

-- ========================================
-- 1. SETUP: Enable Performance Schema & Monitoring
-- ========================================

-- Enable Performance Schema components
UPDATE performance_schema.setup_instruments 
SET ENABLED = 'YES', TIMED = 'YES' 
WHERE NAME LIKE '%statement/%' OR NAME LIKE '%table/%';

UPDATE performance_schema.setup_consumers 
SET ENABLED = 'YES' 
WHERE NAME LIKE '%events_statements_%' OR NAME LIKE '%table_io%';

-- Create table to store test results
DROP TABLE IF EXISTS performance_baseline;
CREATE TABLE performance_baseline (
    test_id INT AUTO_INCREMENT PRIMARY KEY,
    test_name VARCHAR(100) NOT NULL,
    test_phase VARCHAR(20) NOT NULL, -- 'BEFORE' or 'AFTER'
    execution_time_ms DECIMAL(10,3),
    cache_hit_ratio DECIMAL(5,2),
    seq_scans INTEGER,
    index_scans INTEGER,
    rows_examined INTEGER,
    test_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    notes TEXT
);

-- Reset Performance Schema statistics
CALL sys.ps_truncate_all_tables(FALSE);

-- ========================================
-- 2. CREATE SAMPLE TABLES (E-COMMERCE SCENARIO)
-- ========================================

-- Set session variables for better performance during data loading
SET SESSION foreign_key_checks = 0;
SET SESSION unique_checks = 0;
SET SESSION sql_log_bin = 0;

-- Customers table
DROP TABLE IF EXISTS customers;
CREATE TABLE customers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20),
    address TEXT,
    city VARCHAR(100),
    country VARCHAR(100),
    registration_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    last_login TIMESTAMP NULL,
    total_orders INTEGER DEFAULT 0
) ENGINE=InnoDB;

-- Products table
DROP TABLE IF EXISTS products;
CREATE TABLE products (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    category VARCHAR(100) NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    stock_quantity INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    manufacturer VARCHAR(100),
    weight DECIMAL(8,2),
    dimensions VARCHAR(50)
) ENGINE=InnoDB;

-- Orders table (main performance testing table)
DROP TABLE IF EXISTS orders;
CREATE TABLE orders (
    id INT AUTO_INCREMENT PRIMARY KEY,
    customer_id INTEGER NOT NULL,
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) DEFAULT 'pending',
    total_amount DECIMAL(12,2) NOT NULL,
    shipping_address TEXT,
    shipping_method VARCHAR(50),
    payment_method VARCHAR(50),
    notes TEXT,
    processed_at TIMESTAMP NULL,
    shipped_at TIMESTAMP NULL,
    delivered_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX fk_customer_temp (customer_id)
) ENGINE=InnoDB;

-- Order items table
DROP TABLE IF EXISTS order_items;
CREATE TABLE order_items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    order_id INTEGER NOT NULL,
    product_id INTEGER NOT NULL,
    quantity INTEGER NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    total_price DECIMAL(12,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX fk_order_temp (order_id),
    INDEX fk_product_temp (product_id)
) ENGINE=InnoDB;

-- Reviews table
DROP TABLE IF EXISTS reviews;
CREATE TABLE reviews (
    id INT AUTO_INCREMENT PRIMARY KEY,
    product_id INTEGER NOT NULL,
    customer_id INTEGER NOT NULL,
    rating INTEGER CHECK (rating >= 1 AND rating <= 5),
    review_text TEXT,
    is_verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY unique_review (product_id, customer_id),
    INDEX fk_product_review_temp (product_id),
    INDEX fk_customer_review_temp (customer_id)
) ENGINE=InnoDB;

-- ========================================
-- 3. GENERATE LARGE SAMPLE DATA
-- ========================================

-- Create a numbers table for data generation
DROP TABLE IF EXISTS numbers;
CREATE TABLE numbers (n INT PRIMARY KEY);

INSERT INTO numbers (n)
SELECT a.N + b.N * 10 + c.N * 100 + d.N * 1000 + e.N * 10000
FROM
    (SELECT 0 N UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
     UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) a,
    (SELECT 0 N UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
     UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) b,
    (SELECT 0 N UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
     UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) c,
    (SELECT 0 N UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
     UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d,
    (SELECT 0 N UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
     UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) e
WHERE a.N + b.N*10 + c.N*100 + d.N*1000 + e.N*10000 BETWEEN 1 AND 100000;


-- Insert customers (50,000 records)
INSERT INTO customers (email, first_name, last_name, phone, address, city, country, registration_date, is_active, last_login, total_orders)
SELECT 
    CONCAT('user', n, '@example.com'),
    CONCAT('FirstName', n),
    CONCAT('LastName', n),
    CONCAT('+66', LPAD(FLOOR(RAND() * 999999999), 9, '0')),
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
    DATE_SUB(NOW(), INTERVAL FLOOR(RAND() * 730) DAY),
    CASE WHEN RAND() > 0.1 THEN TRUE ELSE FALSE END,
    DATE_SUB(NOW(), INTERVAL FLOOR(RAND() * 30) DAY),
    FLOOR(RAND() * 20)
FROM numbers
WHERE n <= 50000;

-- Insert products (10,000 records)
INSERT INTO products (name, description, category, price, stock_quantity, is_active, created_at, manufacturer, weight, dimensions)
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
    ROUND(RAND() * 2000 + 100, 2),
    FLOOR(RAND() * 1000),
    CASE WHEN RAND() > 0.15 THEN TRUE ELSE FALSE END,
    DATE_SUB(NOW(), INTERVAL FLOOR(RAND() * 365) DAY),
    CASE (n % 5)
        WHEN 0 THEN 'Apple'
        WHEN 1 THEN 'Samsung'
        WHEN 2 THEN 'Sony'
        WHEN 3 THEN 'LG'
        ELSE 'Huawei'
    END,
    ROUND(RAND() * 5 + 0.1, 2),
    CONCAT(ROUND(RAND() * 30 + 5), 'x', ROUND(RAND() * 20 + 3), 'x', ROUND(RAND() * 10 + 1), 'cm')
FROM numbers
WHERE n <= 10000;

-- Insert orders (200,000 records)
INSERT INTO orders (customer_id, order_date, status, total_amount, shipping_address, shipping_method, payment_method, notes, processed_at, shipped_at, delivered_at, created_at)
SELECT 
    FLOOR(RAND() * 49999) + 1,
    DATE_SUB(NOW(), INTERVAL FLOOR(RAND() * 545) DAY),
    CASE FLOOR(RAND() * 10)
        WHEN 0 THEN 'pending'
        WHEN 1 THEN 'processing'
        WHEN 2 THEN 'shipped'
        WHEN 3 THEN 'delivered'
        WHEN 4 THEN 'cancelled'
        ELSE 'completed'
    END,
    ROUND(RAND() * 5000 + 50, 2),
    CONCAT('Shipping address for order ', n),
    CASE FLOOR(RAND() * 3)
        WHEN 0 THEN 'standard'
        WHEN 1 THEN 'express'
        ELSE 'overnight'
    END,
    CASE FLOOR(RAND() * 4)
        WHEN 0 THEN 'credit_card'
        WHEN 1 THEN 'bank_transfer'
        WHEN 2 THEN 'paypal'
        ELSE 'cash_on_delivery'
    END,
    CASE WHEN RAND() > 0.7 THEN CONCAT('Special delivery instructions for order ', n) ELSE NULL END,
    CASE WHEN RAND() > 0.2 THEN DATE_SUB(NOW(), INTERVAL FLOOR(RAND() * 545) DAY) ELSE NULL END,
    CASE WHEN RAND() > 0.3 THEN DATE_SUB(NOW(), INTERVAL FLOOR(RAND() * 515) DAY) ELSE NULL END,
    CASE WHEN RAND() > 0.4 THEN DATE_SUB(NOW(), INTERVAL FLOOR(RAND() * 485) DAY) ELSE NULL END,
    DATE_SUB(NOW(), INTERVAL FLOOR(RAND() * 545) DAY)
FROM numbers
WHERE n <= 200000;

-- Insert order items (500,000+ records) - using a more efficient approach
INSERT INTO order_items (order_id, product_id, quantity, unit_price, total_price)
SELECT 
    o.id,
    FLOOR(RAND() * 9999) + 1,
    FLOOR(RAND() * 5) + 1,
    ROUND(RAND() * 1000 + 10, 2),
    ROUND((FLOOR(RAND() * 5) + 1) * (RAND() * 1000 + 10), 2)
FROM orders o
JOIN numbers n ON n.n <= FLOOR(RAND() * 4) + 1
WHERE o.id <= 50000; -- Limit to prevent excessive data

-- Continue with more order items in batches
INSERT INTO order_items (order_id, product_id, quantity, unit_price, total_price)
SELECT 
    o.id,
    FLOOR(RAND() * 9999) + 1,
    FLOOR(RAND() * 5) + 1,
    ROUND(RAND() * 1000 + 10, 2),
    ROUND((FLOOR(RAND() * 5) + 1) * (RAND() * 1000 + 10), 2)
FROM orders o
JOIN numbers n ON n.n <= 2
WHERE o.id > 50000 AND o.id <= 150000;

-- Insert reviews (100,000 records)
INSERT INTO reviews (product_id, customer_id, rating, review_text, is_verified, created_at)
SELECT 
    FLOOR(RAND() * 9999) + 1,
    FLOOR(RAND() * 49999) + 1,
    FLOOR(RAND() * 5) + 1,
    CASE WHEN RAND() > 0.3 THEN 
        CONCAT('This is a great product! ', 
        CASE FLOOR(RAND() * 3)
            WHEN 0 THEN 'Excellent quality and fast delivery!'
            WHEN 1 THEN 'Good value for money, recommended.'
            ELSE 'Average product, nothing special.'
        END)
    ELSE NULL END,
    CASE WHEN RAND() > 0.4 THEN TRUE ELSE FALSE END,
    DATE_SUB(NOW(), INTERVAL FLOOR(RAND() * 365) DAY)
FROM numbers n1
JOIN numbers n2 ON n2.n <= 5
WHERE n1.n <= 20000
ON DUPLICATE KEY UPDATE rating = VALUES(rating);

-- Re-enable constraints
SET SESSION foreign_key_checks = 1;
SET SESSION unique_checks = 1;

-- Update statistics
ANALYZE TABLE customers, products, orders, order_items, reviews;

-- Drop numbers table
DROP TABLE numbers;

-- ========================================
-- 4. CREATE BAD INDEXES (Simulate Problems)
-- ========================================

-- Create bad indexes to simulate problems
CREATE INDEX idx_customers_unused1 ON customers (phone);    -- Rarely queried
CREATE INDEX idx_customers_unused2 ON customers (address(50));  -- Text field, inefficient
CREATE INDEX idx_products_unused ON products (weight);  -- Rarely queried
CREATE INDEX idx_orders_unused ON orders (notes(50));   -- Text field, rarely queried
CREATE INDEX idx_orders_wrong_order ON orders (total_amount, status); -- Wrong order for typical queries

-- ========================================
-- 5. BASELINE PERFORMANCE CAPTURE PROCEDURES
-- ========================================

DELIMITER $$

-- Procedure to capture query performance
CREATE PROCEDURE capture_query_performance(
    IN test_name_param VARCHAR(100),
    IN test_phase_param VARCHAR(20),
    IN query_text TEXT,
    OUT execution_time_ms DECIMAL(10,3),
    OUT rows_returned BIGINT
)
BEGIN
    DECLARE start_time DECIMAL(20,6);
    DECLARE end_time DECIMAL(20,6);
    DECLARE exec_time DECIMAL(10,3);
    DECLARE rows_count BIGINT DEFAULT 0;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    
    -- Record start time
    SET start_time = UNIX_TIMESTAMP(NOW(6));
    
    -- Execute query and count rows
    SET @sql = CONCAT('SELECT COUNT(*) INTO @row_count FROM (', query_text, ') as subquery');
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
    
    SET rows_count = @row_count;
    
    -- Record end time
    SET end_time = UNIX_TIMESTAMP(NOW(6));
    
    -- Calculate execution time in milliseconds
    SET exec_time = ROUND((end_time - start_time) * 1000, 3);
    
    -- Insert into baseline table
    INSERT INTO performance_baseline (test_name, test_phase, execution_time_ms, rows_examined, test_timestamp)
    VALUES (test_name_param, test_phase_param, exec_time, rows_count, NOW());
    
    -- Return values
    SET execution_time_ms = exec_time;
    SET rows_returned = rows_count;
END$$

-- Procedure to capture cache metrics
CREATE PROCEDURE capture_cache_metrics(
    IN test_name_param VARCHAR(100), 
    IN test_phase_param VARCHAR(20),
    OUT cache_hit_ratio DECIMAL(5,2)
)
BEGIN
    DECLARE buffer_pool_reads BIGINT DEFAULT 0;
    DECLARE buffer_pool_read_requests BIGINT DEFAULT 0;
    DECLARE hit_ratio DECIMAL(5,2) DEFAULT 0;
    
    -- Get InnoDB buffer pool statistics
    SELECT VARIABLE_VALUE INTO buffer_pool_reads
    FROM performance_schema.global_status 
    WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads';
    
    SELECT VARIABLE_VALUE INTO buffer_pool_read_requests
    FROM performance_schema.global_status 
    WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests';
    
    -- Calculate cache hit ratio
    IF buffer_pool_read_requests > 0 THEN
        SET hit_ratio = ROUND(100.0 * (1 - (buffer_pool_reads / buffer_pool_read_requests)), 2);
    END IF;
    
    -- Insert into baseline table
    INSERT INTO performance_baseline (test_name, test_phase, cache_hit_ratio, test_timestamp)
    VALUES (test_name_param, test_phase_param, hit_ratio, NOW());
    
    SET cache_hit_ratio = hit_ratio;
END$$

DELIMITER ;

-- ========================================
-- 6. COMPREHENSIVE BEFORE TESTING
-- ========================================

-- Reset Performance Schema statistics
CALL sys.ps_truncate_all_tables(FALSE);

SELECT '🧪 STARTING BEFORE TESTING...' as status;

-- Test Suite 1: Simple Queries (should be slow without indexes)
-- Test 1.1: Single WHERE condition
CALL capture_query_performance(
    'Single WHERE - Status',
    'BEFORE',
    'SELECT * FROM orders WHERE status = ''pending''',
    @exec_time, @rows_count
);
SELECT CONCAT('Test completed: ', @exec_time, ' ms, ', @rows_count, ' rows') as result;

-- Test 1.2: Date Range Query
CALL capture_query_performance(
    'Date Range Query',
    'BEFORE', 
    'SELECT * FROM orders WHERE order_date >= ''2024-01-01''',
    @exec_time, @rows_count
);
SELECT CONCAT('Test completed: ', @exec_time, ' ms, ', @rows_count, ' rows') as result;

-- Test 1.3: Multiple WHERE conditions
CALL capture_query_performance(
    'Multiple WHERE',
    'BEFORE',
    'SELECT * FROM orders WHERE status = ''completed'' AND total_amount > 1000',
    @exec_time, @rows_count
);
SELECT CONCAT('Test completed: ', @exec_time, ' ms, ', @rows_count, ' rows') as result;

-- Test Suite 2: JOIN Queries (will be very slow without indexes)
-- Test 2.1: Simple JOIN
CALL capture_query_performance(
    'Simple JOIN',
    'BEFORE',
    'SELECT o.*, c.first_name FROM orders o JOIN customers c ON o.customer_id = c.id WHERE c.city = ''Bangkok''',
    @exec_time, @rows_count
);
SELECT CONCAT('Test completed: ', @exec_time, ' ms, ', @rows_count, ' rows') as result;

-- Test 2.2: Complex JOIN with WHERE
CALL capture_query_performance(
    'Complex JOIN',
    'BEFORE',
    'SELECT o.id, c.first_name, oi.quantity 
     FROM orders o 
     JOIN customers c ON o.customer_id = c.id 
     JOIN order_items oi ON o.id = oi.order_id
     WHERE c.city = ''Bangkok'' AND o.status = ''completed'' AND oi.quantity > 2',
    @exec_time, @rows_count
);
SELECT CONCAT('Test completed: ', @exec_time, ' ms, ', @rows_count, ' rows') as result;

-- Test Suite 3: Aggregation Queries
-- Test 3.1: GROUP BY on large table
CALL capture_query_performance(
    'GROUP BY Category',
    'BEFORE',
    'SELECT category, COUNT(*), AVG(price) FROM products WHERE is_active = TRUE GROUP BY category',
    @exec_time, @rows_count
);
SELECT CONCAT('Test completed: ', @exec_time, ' ms, ', @rows_count, ' rows') as result;

-- Test 3.2: Complex aggregation with JOIN
CALL capture_query_performance(
    'Complex Aggregation',
    'BEFORE',
    'SELECT c.city, COUNT(o.id) as order_count, SUM(o.total_amount) as total_revenue
     FROM customers c 
     LEFT JOIN orders o ON c.id = o.customer_id 
     WHERE c.registration_date >= ''2023-01-01''
     GROUP BY c.city
     HAVING COUNT(o.id) > 10',
    @exec_time, @rows_count
);
SELECT CONCAT('Test completed: ', @exec_time, ' ms, ', @rows_count, ' rows') as result;

-- Test Suite 4: Text Search (slow without FULLTEXT index)
-- Test 4.1: LIKE search
CALL capture_query_performance(
    'Text Search LIKE',
    'BEFORE',
    'SELECT * FROM products WHERE name LIKE ''%phone%'' OR description LIKE ''%smartphone%''',
    @exec_time, @rows_count
);
SELECT CONCAT('Test completed: ', @exec_time, ' ms, ', @rows_count, ' rows') as result;

-- Test Suite 5: Subquery Performance
-- Test 5.1: Correlated subquery
CALL capture_query_performance(
    'Correlated Subquery', 
    'BEFORE',
    'SELECT * FROM customers c 
     WHERE (SELECT COUNT(*) FROM orders WHERE customer_id = c.id AND status = ''completed'') > 5',
    @exec_time, @rows_count
);
SELECT CONCAT('Test completed: ', @exec_time, ' ms, ', @rows_count, ' rows') as result;

-- Capture baseline cache performance
CALL capture_cache_metrics('Overall Cache Performance', 'BEFORE', @cache_ratio);
SELECT CONCAT('Cache hit ratio: ', @cache_ratio, '%') as cache_result;

-- ========================================
-- 7. DISPLAY BEFORE RESULTS
-- ========================================

SELECT 
    '📊 BEFORE OPTIMIZATION RESULTS' as title,
    '════════════════════════════════════════════════════════════════════' as separator;

SELECT 
    test_name,
    CONCAT(execution_time_ms, ' ms') as execution_time,
    CASE 
        WHEN execution_time_ms < 50 THEN '🟢 Fast'
        WHEN execution_time_ms < 200 THEN '🟡 OK'
        WHEN execution_time_ms < 1000 THEN '🟠 Slow'
        ELSE '🔴 Very Slow'
    END as performance_status,
    rows_examined as rows_examined
FROM performance_baseline 
WHERE test_phase = 'BEFORE' 
    AND execution_time_ms IS NOT NULL
ORDER BY execution_time_ms DESC;

-- Cache performance before
SELECT 
    CONCAT('Cache Hit Ratio (BEFORE): ', cache_hit_ratio, '%') as cache_performance,
    CASE 
        WHEN cache_hit_ratio > 95 THEN '🟢 Excellent'
        WHEN cache_hit_ratio > 90 THEN '🟢 Good'
        WHEN cache_hit_ratio > 85 THEN '🟡 OK'
        ELSE '🔴 Poor'
    END as cache_status
FROM performance_baseline 
WHERE test_phase = 'BEFORE' 
    AND cache_hit_ratio IS NOT NULL
ORDER BY test_timestamp DESC 
LIMIT 1;

-- ========================================
-- 8. OPTIMIZATION IMPLEMENTATION
-- ========================================

SELECT '⚡ APPLYING OPTIMIZATIONS...' as status;

-- Remove bad indexes first
DROP INDEX IF EXISTS idx_customers_unused1 ON customers;
DROP INDEX IF EXISTS idx_customers_unused2 ON customers;
DROP INDEX IF EXISTS idx_products_unused ON products;
DROP INDEX IF EXISTS idx_orders_unused ON orders;
DROP INDEX IF EXISTS idx_orders_wrong_order ON orders;

-- Remove temporary foreign key indexes
DROP INDEX IF EXISTS fk_customer_temp ON orders;
DROP INDEX IF EXISTS fk_order_temp ON order_items;
DROP INDEX IF EXISTS fk_product_temp ON order_items;
DROP INDEX IF EXISTS fk_product_review_temp ON reviews;
DROP INDEX IF EXISTS fk_customer_review_temp ON reviews;

-- Create optimized indexes
-- For single column queries
CREATE INDEX idx_orders_status_opt ON orders (status);
CREATE INDEX idx_orders_date_opt ON orders (order_date);
CREATE INDEX idx_customers_city_opt ON customers (city);

-- For multiple column queries (composite indexes)
CREATE INDEX idx_orders_status_amount_opt ON orders (status, total_amount);
CREATE INDEX idx_orders_status_date_opt ON orders (status, order_date);
CREATE INDEX idx_customers_city_registration_opt ON customers (city, registration_date);

-- For JOIN performance
CREATE INDEX idx_orders_customer_id_opt ON orders (customer_id);
CREATE INDEX idx_order_items_order_id_opt ON order_items (order_id);
CREATE INDEX idx_order_items_product_id_opt ON order_items (product_id);
CREATE INDEX idx_reviews_product_id_opt ON reviews (product_id);

-- Covering indexes (include commonly selected columns) - MySQL doesn't have INCLUDE, so we use composite indexes
CREATE INDEX idx_orders_status_covering_opt ON orders (status, id, customer_id, order_date, total_amount);
CREATE INDEX idx_customers_city_covering_opt ON customers (city, id, first_name, last_name, registration_date);

-- Partial indexes simulation using WHERE clause (functional indexes)
-- MySQL doesn't support partial indexes directly, but we can optimize for active records
CREATE INDEX idx_products_category_active_opt ON products (category, is_active);
CREATE INDEX idx_customers_active_city_opt ON customers (is_active, city);

-- Text search optimization using FULLTEXT
CREATE FULLTEXT INDEX idx_products_fulltext_opt ON products (name, description);

-- Additional performance indexes
CREATE INDEX idx_order_items_quantity_opt ON order_items (quantity);
CREATE INDEX idx_customers_registration_opt ON customers (registration_date);
CREATE INDEX idx_orders_total_amount_opt ON orders (total_amount);

-- Add proper foreign key constraints now
ALTER TABLE orders ADD CONSTRAINT fk_orders_customer_id 
    FOREIGN KEY (customer_id) REFERENCES customers(id);

ALTER TABLE order_items ADD CONSTRAINT fk_order_items_order_id 
    FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE;

ALTER TABLE order_items ADD CONSTRAINT fk_order_items_product_id 
    FOREIGN KEY (product_id) REFERENCES products(id);

ALTER TABLE reviews ADD CONSTRAINT fk_reviews_product_id 
    FOREIGN KEY (product_id) REFERENCES products(id);

ALTER TABLE reviews ADD CONSTRAINT fk_reviews_customer_id 
    FOREIGN KEY (customer_id) REFERENCES customers(id);

-- Update statistics after index creation
ANALYZE TABLE customers, products, orders, order_items, reviews;

-- ========================================
-- 9. COMPREHENSIVE AFTER TESTING
-- ========================================

-- Reset Performance Schema statistics for clean measurement
CALL sys.ps_truncate_all_tables(FALSE);

SELECT '🧪 STARTING AFTER TESTING...' as status;

-- Test Suite 1: Simple Queries (should be much faster now)
-- Test 1.1: Single WHERE condition
CALL capture_query_performance(
    'Single WHERE - Status',
    'AFTER',
    'SELECT * FROM orders WHERE status = ''pending''',
    @exec_time, @rows_count
);
SELECT CONCAT('Test completed: ', @exec_time, ' ms, ', @rows_count, ' rows') as result;

-- Test 1.2: Date Range Query
CALL capture_query_performance(
    'Date Range Query',
    'AFTER',
    'SELECT * FROM orders WHERE order_date >= ''2024-01-01''',
    @exec_time, @rows_count
);
SELECT CONCAT('Test completed: ', @exec_time, ' ms, ', @rows_count, ' rows') as result;

-- Test 1.3: Multiple WHERE conditions
CALL capture_query_performance(
    'Multiple WHERE',
    'AFTER',
    'SELECT * FROM orders WHERE status = ''completed'' AND total_amount > 1000',
    @exec_time, @rows_count
);
SELECT CONCAT('Test completed: ', @exec_time, ' ms, ', @rows_count, ' rows') as result;

-- Test Suite 2: JOIN Queries (should be much faster now)
-- Test 2.1: Simple JOIN
CALL capture_query_performance(
    'Simple JOIN',
    'AFTER',
    'SELECT o.*, c.first_name FROM orders o JOIN customers c ON o.customer_id = c.id WHERE c.city = ''Bangkok''',
    @exec_time, @rows_count
);
SELECT CONCAT('Test completed: ', @exec_time, ' ms, ', @rows_count, ' rows') as result;

-- Test 2.2: Complex JOIN with WHERE
CALL capture_query_performance(
    'Complex JOIN',
    'AFTER',
    'SELECT o.id, c.first_name, oi.quantity 
     FROM orders o 
     JOIN customers c ON o.customer_id = c.id 
     JOIN order_items oi ON o.id = oi.order_id
     WHERE c.city = ''Bangkok'' AND o.status = ''completed'' AND oi.quantity > 2',
    @exec_time, @rows_count
);
SELECT CONCAT('Test completed: ', @exec_time, ' ms, ', @rows_count, ' rows') as result;

-- Test Suite 3: Aggregation Queries
-- Test 3.1: GROUP BY on large table (using optimized indexes)
CALL capture_query_performance(
    'GROUP BY Category',
    'AFTER',
    'SELECT category, COUNT(*), AVG(price) FROM products WHERE is_active = TRUE GROUP BY category',
    @exec_time, @rows_count
);
SELECT CONCAT('Test completed: ', @exec_time, ' ms, ', @rows_count, ' rows') as result;

-- Test 3.2: Complex aggregation with JOIN
CALL capture_query_performance(
    'Complex Aggregation',
    'AFTER',
    'SELECT c.city, COUNT(o.id) as order_count, SUM(o.total_amount) as total_revenue
     FROM customers c 
     LEFT JOIN orders o ON c.id = o.customer_id 
     WHERE c.registration_date >= ''2023-01-01''
     GROUP BY c.city
     HAVING COUNT(o.id) > 10',
    @exec_time, @rows_count
);
SELECT CONCAT('Test completed: ', @exec_time, ' ms, ', @rows_count, ' rows') as result;

-- Test Suite 4: Text Search (using FULLTEXT index)
-- Test 4.1: Full-text search
CALL capture_query_performance(
    'Text Search LIKE',
    'AFTER',
    'SELECT * FROM products WHERE MATCH(name, description) AGAINST(''phone smartphone'' IN NATURAL LANGUAGE MODE)',
    @exec_time, @rows_count
);
SELECT CONCAT('Test completed: ', @exec_time, ' ms, ', @rows_count, ' rows') as result;

-- Test Suite 5: Subquery Performance
-- Test 5.1: Correlated subquery
CALL capture_query_performance(
    'Correlated Subquery',
    'AFTER',
    'SELECT * FROM customers c 
     WHERE (SELECT COUNT(*) FROM orders WHERE customer_id = c.id AND status = ''completed'') > 5',
    @exec_time, @rows_count
);
SELECT CONCAT('Test completed: ', @exec_time, ' ms, ', @rows_count, ' rows') as result;

-- Capture optimized cache performance
CALL capture_cache_metrics('Overall Cache Performance', 'AFTER', @cache_ratio);
SELECT CONCAT('Cache hit ratio: ', @cache_ratio, '%') as cache_result;

-- ========================================
-- 10. COMPREHENSIVE BEFORE/AFTER COMPARISON
-- ========================================

SELECT 
    '🏆 PERFORMANCE IMPROVEMENT REPORT' as title,
    '════════════════════════════════════════════════════════════════════════════════' as separator;

-- Detailed before/after comparison
SELECT 
    pb1.test_name as "Test Case",
    CONCAT(COALESCE(pb1.before_ms, 0), ' ms') as "Before",
    CONCAT(COALESCE(pb1.after_ms, 0), ' ms') as "After", 
    CASE 
        WHEN pb1.before_ms > 0 AND pb1.after_ms > 0 THEN 
            CONCAT(ROUND(pb1.before_ms / pb1.after_ms, 1), 'x faster')
        ELSE 'N/A'
    END as "Improvement",
    CASE 
        WHEN pb1.before_ms > 0 AND pb1.after_ms > 0 THEN
            CONCAT(ROUND(((pb1.before_ms - pb1.after_ms) / pb1.before_ms) * 100, 1), '% faster')
        ELSE 'N/A'
    END as "% Improvement",
    CASE 
        WHEN COALESCE(pb1.after_ms, 0) < 50 THEN '🟢 Excellent'
        WHEN COALESCE(pb1.after_ms, 0) < 200 THEN '🟢 Good'
        WHEN COALESCE(pb1.after_ms, 0) < 1000 THEN '🟡 OK'
        ELSE '🔴 Needs Work'
    END as "Final Status"
FROM (
    SELECT 
        test_name,
        MAX(CASE WHEN test_phase = 'BEFORE' THEN execution_time_ms END) as before_ms,
        MAX(CASE WHEN test_phase = 'AFTER' THEN execution_time_ms END) as after_ms,
        MAX(CASE WHEN test_phase = 'BEFORE' THEN cache_hit_ratio END) as cache_before,
        MAX(CASE WHEN test_phase = 'AFTER' THEN cache_hit_ratio END) as cache_after
    FROM performance_baseline
    WHERE execution_time_ms IS NOT NULL OR cache_hit_ratio IS NOT NULL
    GROUP BY test_name
) pb1
WHERE pb1.before_ms IS NOT NULL AND pb1.after_ms IS NOT NULL
ORDER BY 
    CASE WHEN pb1.before_ms > 0 AND pb1.after_ms > 0 THEN pb1.before_ms / pb1.after_ms ELSE 0 END DESC;

-- Cache performance comparison
SELECT 
    '💾 CACHE PERFORMANCE COMPARISON' as metric_type,
    '─────────────────────────────────────────────────────────────────' as separator
UNION ALL
SELECT 
    'Cache Hit Ratio' as metric_type,
    CONCAT(
        'Before: ', COALESCE(cache_before, 0), '%  →  After: ', COALESCE(cache_after, 0), '%  (',
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
SELECT 
    '📈 OVERALL SUMMARY' as metric_type,
    '─────────────────────────────────────────────────────────────────' as separator
UNION ALL
SELECT 
    'Average Performance' as metric_type,
    CONCAT(
        ROUND(avg_before, 1), ' ms → ', ROUND(avg_after, 1), ' ms (',
        ROUND(avg_before / NULLIF(avg_after, 0), 1), 'x faster overall)'
    ) as summary
FROM (
    SELECT 
        AVG(CASE WHEN test_phase = 'BEFORE' THEN execution_time_ms END) as avg_before,
        AVG(CASE WHEN test_phase = 'AFTER' THEN execution_time_ms END) as avg_after,
        MAX(CASE WHEN test_phase = 'BEFORE' THEN execution_time_ms END) as max_before,
        MAX(CASE WHEN test_phase = 'AFTER' THEN execution_time_ms END) as max_after
    FROM performance_baseline
    WHERE execution_time_ms IS NOT NULL
) summary_stats
UNION ALL
SELECT 
    'Worst Case Performance' as metric_type,
    CONCAT(
        ROUND(max_before, 1), ' ms → ', ROUND(max_after, 1), ' ms (',
        ROUND(max_before / NULLIF(max_after, 0), 1), 'x improvement)'
    ) as summary
FROM (
    SELECT 
        AVG(CASE WHEN test_phase = 'BEFORE' THEN execution_time_ms END) as avg_before,
        AVG(CASE WHEN test_phase = 'AFTER' THEN execution_time_ms END) as avg_after,
        MAX(CASE WHEN test_phase = 'BEFORE' THEN execution_time_ms END) as max_before,
        MAX(CASE WHEN test_phase = 'AFTER' THEN execution_time_ms END) as max_after
    FROM performance_baseline
    WHERE execution_time_ms IS NOT NULL
) summary_stats;

-- ========================================
-- 11. INDEX USAGE ANALYSIS
-- ========================================

SELECT 
    '📊 INDEX USAGE ANALYSIS' as title,
    '═══════════════════════════════════════════════════════════════════' as separator;

-- Show which new indexes are being used (MySQL equivalent)
SELECT 
    OBJECT_SCHEMA as schema_name,
    OBJECT_NAME as table_name,
    INDEX_NAME as index_name,
    COUNT_FETCH as times_used,
    SUM_TIMER_FETCH / 1000000000000 as total_fetch_time_sec,
    ROUND(
        (SELECT ((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024) 
         FROM information_schema.TABLES t 
         WHERE t.TABLE_SCHEMA = tio.OBJECT_SCHEMA 
           AND t.TABLE_NAME = tio.OBJECT_NAME), 2
    ) as table_size_mb,
    CASE 
        WHEN COUNT_FETCH = 0 THEN '🔴 Not Used'
        WHEN COUNT_FETCH < 10 THEN '🟡 Low Usage'
        WHEN COUNT_FETCH < 100 THEN '🟢 Good Usage'
        ELSE '🟢 High Usage'
    END as usage_status
FROM performance_schema.table_io_waits_summary_by_index_usage tio
WHERE OBJECT_SCHEMA = DATABASE()
    AND INDEX_NAME LIKE '%_opt'
    AND INDEX_NAME IS NOT NULL
ORDER BY COUNT_FETCH DESC;

-- ========================================
-- 12. FINAL RECOMMENDATIONS
-- ========================================

SELECT 
    '💡 OPTIMIZATION RECOMMENDATIONS' as title,
    '═══════════════════════════════════════════════════════════════════' as separator;

SELECT 
    'Tests Performed: ' || COUNT(*) as metric,
    '' as value
FROM (
    SELECT DISTINCT test_name FROM performance_baseline WHERE execution_time_ms IS NOT NULL
) tests
UNION ALL
SELECT 
    CONCAT('Significantly Improved (>2x): ', COUNT(*)) as metric,
    '' as value
FROM (
    SELECT 
        test_name,
        MAX(CASE WHEN test_phase = 'BEFORE' THEN execution_time_ms END) as before_ms,
        MAX(CASE WHEN test_phase = 'AFTER' THEN execution_time_ms END) as after_ms
    FROM performance_baseline
    WHERE execution_time_ms IS NOT NULL
    GROUP BY test_name
    HAVING before_ms > after_ms * 2
) significantly_improved
UNION ALL
SELECT 
    CONCAT(
        'Overall Performance Gain: ',
        ROUND(
            (SELECT AVG(CASE WHEN test_phase = 'BEFORE' THEN execution_time_ms END) FROM performance_baseline WHERE execution_time_ms IS NOT NULL) /
            NULLIF((SELECT AVG(CASE WHEN test_phase = 'AFTER' THEN execution_time_ms END) FROM performance_baseline WHERE execution_time_ms IS NOT NULL), 0),
            1
        ), 'x faster on average'
    ) as metric,
    '' as value;

-- Clean up procedures
DROP PROCEDURE IF EXISTS capture_query_performance;
DROP PROCEDURE IF EXISTS capture_cache_metrics;

SELECT 
    '✅ MYSQL PERFORMANCE TUNING SIMULATION COMPLETE!' as status,
    'Check the results above to see dramatic improvements.' as note;

-- ========================================
-- END OF COMPLETE SIMULATION
-- ========================================
