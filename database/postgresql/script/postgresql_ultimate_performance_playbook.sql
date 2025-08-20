-- ================================================
-- PostgreSQL ULTIMATE Performance Tuning Playbook
-- Complete Simulation with Before/After Testing
-- Merged Best Practices from Multiple Sources
-- ================================================

-- ========================================
-- 1. SETUP: Extensions, Monitoring & Baseline
-- ========================================

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Performance baseline tracking table
DROP TABLE IF EXISTS performance_baseline CASCADE;
CREATE TABLE performance_baseline (
    test_id SERIAL PRIMARY KEY,
    test_name VARCHAR(100) NOT NULL,
    test_phase VARCHAR(20) NOT NULL, -- 'BEFORE' or 'AFTER'
    execution_time_ms NUMERIC,
    cache_hit_ratio NUMERIC,
    seq_scans INTEGER,
    index_scans INTEGER,
    rows_examined INTEGER,
    test_timestamp TIMESTAMP DEFAULT NOW(),
    notes TEXT
);

-- Reset statistics for clean baseline
SELECT pg_stat_statements_reset();
SELECT pg_stat_reset();

-- ========================================
-- 2. CREATE COMPREHENSIVE SAMPLE SCHEMA
-- ========================================

-- Customers table
DROP TABLE IF EXISTS customers CASCADE;
CREATE TABLE customers (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20),
    address TEXT,
    city VARCHAR(100),
    country VARCHAR(100),
    registration_date TIMESTAMP DEFAULT NOW(),
    is_active BOOLEAN DEFAULT true,
    last_login TIMESTAMP,
    total_orders INTEGER DEFAULT 0,
    customer_tier VARCHAR(20) DEFAULT 'bronze' -- Added for partial index demo
);

-- Products table  
DROP TABLE IF EXISTS products CASCADE;
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    category VARCHAR(100) NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    stock_quantity INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    manufacturer VARCHAR(100),
    weight DECIMAL(8,2),
    dimensions VARCHAR(50),
    tags TEXT[] -- Added for GIN index demo
);

-- Orders table (main performance testing table)
DROP TABLE IF EXISTS orders CASCADE;
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL REFERENCES customers(id),
    order_date TIMESTAMP DEFAULT NOW(),
    status VARCHAR(20) DEFAULT 'pending',
    total_amount DECIMAL(12,2) NOT NULL,
    shipping_address TEXT,
    shipping_method VARCHAR(50),
    payment_method VARCHAR(50),
    notes TEXT,
    processed_at TIMESTAMP,
    shipped_at TIMESTAMP,
    delivered_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Order items table
DROP TABLE IF EXISTS order_items CASCADE;
CREATE TABLE order_items (
    id SERIAL PRIMARY KEY,
    order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id INTEGER NOT NULL REFERENCES products(id),
    quantity INTEGER NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    total_price DECIMAL(12,2) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Reviews table
DROP TABLE IF EXISTS reviews CASCADE;
CREATE TABLE reviews (
    id SERIAL PRIMARY KEY,
    product_id INTEGER NOT NULL REFERENCES products(id),
    customer_id INTEGER NOT NULL REFERENCES customers(id),
    rating INTEGER CHECK (rating >= 1 AND rating <= 5),
    review_text TEXT,
    is_verified BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    helpful_votes INTEGER DEFAULT 0, -- Added for additional queries
    UNIQUE(product_id, customer_id)
);

-- ========================================
-- 3. GENERATE REALISTIC LARGE DATASET
-- ========================================

-- Insert customers (50,000 records)
INSERT INTO customers (email, first_name, last_name, phone, address, city, country, registration_date, is_active, last_login, total_orders, customer_tier)
SELECT 
    'user' || i || '@example.com',
    'FirstName' || i,
    'LastName' || i,
    '+66' || LPAD((random() * 999999999)::text, 9, '0'),
    i || ' Main Street',
    CASE (i % 10)
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
    NOW() - (random() * interval '2 years'),
    CASE WHEN random() > 0.1 THEN true ELSE false END,
    NOW() - (random() * interval '30 days'),
    (random() * 20)::integer,
    CASE (random() * 100)::integer
        WHEN 0 TO 70 THEN 'bronze'
        WHEN 71 TO 90 THEN 'silver'
        WHEN 91 TO 98 THEN 'gold'
        ELSE 'platinum'
    END
FROM generate_series(1, 50000) AS i;

-- Insert products (10,000 records) with tags
INSERT INTO products (name, description, category, price, stock_quantity, is_active, created_at, manufacturer, weight, dimensions, tags)
SELECT 
    'Product ' || i || ' - ' || 
    CASE (i % 6)
        WHEN 0 THEN 'Smartphone'
        WHEN 1 THEN 'Laptop'
        WHEN 2 THEN 'Tablet'
        WHEN 3 THEN 'Headphones'
        WHEN 4 THEN 'Camera'
        ELSE 'Watch'
    END,
    'High quality product with advanced features and excellent performance.',
    CASE (i % 6)
        WHEN 0 THEN 'electronics'
        WHEN 1 THEN 'computers'
        WHEN 2 THEN 'electronics'
        WHEN 3 THEN 'audio'
        WHEN 4 THEN 'photography'
        ELSE 'accessories'
    END,
    (random() * 2000 + 100)::DECIMAL(10,2),
    (random() * 1000)::integer,
    CASE WHEN random() > 0.15 THEN true ELSE false END,
    NOW() - (random() * interval '1 year'),
    CASE (i % 5)
        WHEN 0 THEN 'Apple'
        WHEN 1 THEN 'Samsung'
        WHEN 2 THEN 'Sony'
        WHEN 3 THEN 'LG'
        ELSE 'Huawei'
    END,
    (random() * 5 + 0.1)::DECIMAL(8,2),
    ROUND(random() * 30 + 5) || 'x' || ROUND(random() * 20 + 3) || 'x' || ROUND(random() * 10 + 1) || 'cm',
    ARRAY['tag' || (random() * 20 + 1)::text, 'feature' || (random() * 10 + 1)::text]
FROM generate_series(1, 10000) AS i;

-- Insert orders (200,000 records)
INSERT INTO orders (customer_id, order_date, status, total_amount, shipping_address, shipping_method, payment_method, notes, processed_at, shipped_at, delivered_at, created_at)
SELECT 
    (random() * 49999 + 1)::integer,
    NOW() - (random() * interval '18 months'),
    CASE (random() * 10)::integer
        WHEN 0 THEN 'pending'
        WHEN 1 THEN 'processing'
        WHEN 2 THEN 'shipped'
        WHEN 3 THEN 'delivered'
        WHEN 4 THEN 'cancelled'
        ELSE 'completed'
    END,
    (random() * 5000 + 50)::DECIMAL(12,2),
    'Shipping address for order ' || i,
    CASE (random() * 3)::integer
        WHEN 0 THEN 'standard'
        WHEN 1 THEN 'express'
        ELSE 'overnight'
    END,
    CASE (random() * 4)::integer
        WHEN 0 THEN 'credit_card'
        WHEN 1 THEN 'bank_transfer'
        WHEN 2 THEN 'paypal'
        ELSE 'cash_on_delivery'
    END,
    CASE WHEN random() > 0.7 THEN 'Special delivery instructions for order ' || i ELSE NULL END,
    CASE WHEN random() > 0.2 THEN NOW() - (random() * interval '18 months') ELSE NULL END,
    CASE WHEN random() > 0.3 THEN NOW() - (random() * interval '17 months') ELSE NULL END,
    CASE WHEN random() > 0.4 THEN NOW() - (random() * interval '16 months') ELSE NULL END,
    NOW() - (random() * interval '18 months')
FROM generate_series(1, 200000) AS i;

-- Insert order items (500,000+ records)
INSERT INTO order_items (order_id, product_id, quantity, unit_price, total_price)
SELECT 
    o.id,
    (random() * 9999 + 1)::integer,
    (random() * 5 + 1)::integer,
    (random() * 1000 + 10)::DECIMAL(10,2),
    ((random() * 5 + 1) * (random() * 1000 + 10))::DECIMAL(12,2)
FROM orders o
CROSS JOIN LATERAL (
    SELECT generate_series(1, (random() * 4 + 1)::integer)
) AS series;

-- Insert reviews with helpful_votes
WITH review_candidates AS (
    SELECT 
        p.id as product_id,
        c.id as customer_id,
        (random() * 5 + 1)::integer as rating,
        CASE WHEN random() > 0.3 THEN 
            'This is a review for ' || p.name || '. ' || 
            CASE (random() * 3)::integer
                WHEN 0 THEN 'Excellent quality and fast delivery!'
                WHEN 1 THEN 'Good value for money, recommended.'
                ELSE 'Average product, nothing special.'
            END
        ELSE NULL END as review_text,
        CASE WHEN random() > 0.4 THEN true ELSE false END as is_verified,
        NOW() - (random() * interval '12 months') as created_at,
        (random() * 50)::integer as helpful_votes,
        row_number() OVER (PARTITION BY p.id, c.id ORDER BY random()) as rn
    FROM products p 
    CROSS JOIN customers c
    WHERE p.is_active = true 
        AND c.is_active = true
        AND random() < 0.05
)
INSERT INTO reviews (product_id, customer_id, rating, review_text, is_verified, created_at, helpful_votes)
SELECT 
    product_id, customer_id, rating, review_text, is_verified, created_at, helpful_votes
FROM review_candidates 
WHERE rn = 1
LIMIT 100000
ON CONFLICT (product_id, customer_id) DO NOTHING;

-- Update initial statistics
ANALYZE customers, products, orders, order_items, reviews;

-- ========================================
-- 4. CREATE INTENTIONALLY BAD INDEXES
-- ========================================

-- Create inefficient indexes to demonstrate problems
CREATE INDEX idx_customers_unused1 ON customers (phone);    
CREATE INDEX idx_customers_unused2 ON customers (address);  
CREATE INDEX idx_products_unused ON products (weight);     
CREATE INDEX idx_orders_unused ON orders (notes);          
CREATE INDEX idx_orders_wrong_order ON orders (total_amount, status); -- Wrong order

-- ========================================
-- 5. PERFORMANCE TESTING FUNCTIONS
-- ========================================

-- Enhanced performance capture function
CREATE OR REPLACE FUNCTION capture_query_performance(
    test_name_param VARCHAR(100),
    test_phase_param VARCHAR(20),
    query_text TEXT
) RETURNS TABLE (
    execution_time_ms NUMERIC,
    rows_returned BIGINT
) AS $$
DECLARE
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    exec_time NUMERIC;
    rows_count BIGINT;
    seq_scans_before BIGINT;
    seq_scans_after BIGINT;
    idx_scans_before BIGINT;
    idx_scans_after BIGINT;
BEGIN
    -- Capture scan statistics before
    SELECT sum(seq_scan), sum(idx_scan) INTO seq_scans_before, idx_scans_before
    FROM pg_stat_user_tables;
    
    start_time := clock_timestamp();
    
    -- Execute query and count rows
    EXECUTE 'SELECT count(*) FROM (' || query_text || ') as subquery' INTO rows_count;
    
    end_time := clock_timestamp();
    
    -- Capture scan statistics after
    SELECT sum(seq_scan), sum(idx_scan) INTO seq_scans_after, idx_scans_after
    FROM pg_stat_user_tables;
    
    exec_time := ROUND(EXTRACT(EPOCH FROM (end_time - start_time)) * 1000, 2);
    
    -- Record performance data
    INSERT INTO performance_baseline (
        test_name, test_phase, execution_time_ms, rows_examined, 
        seq_scans, index_scans, test_timestamp
    )
    VALUES (
        test_name_param, test_phase_param, exec_time, rows_count,
        (seq_scans_after - seq_scans_before), (idx_scans_after - idx_scans_before), NOW()
    );
    
    execution_time_ms := exec_time;
    rows_returned := rows_count;
    RETURN NEXT;
END;
$$ LANGUAGE plpgsql;

-- Cache metrics capture function
CREATE OR REPLACE FUNCTION capture_cache_metrics(
    test_name_param VARCHAR(100), 
    test_phase_param VARCHAR(20)
) RETURNS NUMERIC AS $$
DECLARE
    cache_hit_ratio NUMERIC;
BEGIN
    SELECT ROUND(100.0 * sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0), 2)
    INTO cache_hit_ratio
    FROM pg_statio_user_tables;
    
    INSERT INTO performance_baseline (test_name, test_phase, cache_hit_ratio, test_timestamp)
    VALUES (test_name_param, test_phase_param, cache_hit_ratio, NOW());
    
    RETURN cache_hit_ratio;
END;
$$ LANGUAGE plpgsql;

-- ========================================
-- 6. COMPREHENSIVE SYSTEM HEALTH CHECK
-- ========================================

-- Database overview
SELECT 
    '🏥 DATABASE HEALTH CHECK' as title,
    '═══════════════════════════════════════════════════════════════════' as separator;

-- 6.1 Database size and connections
SELECT 
    'Database Size: ' || pg_size_pretty(pg_database_size(current_database())) as metric,
    'Total Size: ' || ROUND(pg_database_size(current_database()) / 1024.0 / 1024.0 / 1024.0, 2) || ' GB' as detail;

SELECT 
    'Total Connections: ' || count(*) as connections,
    'Active: ' || count(*) FILTER (WHERE state = 'active') as active,
    'Idle: ' || count(*) FILTER (WHERE state = 'idle') as idle
FROM pg_stat_activity 
WHERE pid <> pg_backend_pid();

-- 6.2 Initial cache hit ratio
SELECT 
    'Initial Cache Hit Ratio: ' || 
    ROUND(100.0 * sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0), 2) || '%' as cache_performance,
    sum(heap_blks_hit) as cache_hits,
    sum(heap_blks_read) as disk_reads
FROM pg_statio_user_tables;

-- ========================================
-- 7. BEFORE OPTIMIZATION - COMPREHENSIVE TESTING
-- ========================================

SELECT pg_stat_statements_reset();
SELECT pg_stat_reset();

SELECT '🧪 STARTING BEFORE OPTIMIZATION TESTING...' as status;

-- Test Suite 1: Basic Queries
SELECT * FROM capture_query_performance(
    'Basic Status Query',
    'BEFORE',
    'SELECT count(*) FROM orders WHERE status = ''pending'''
);

SELECT * FROM capture_query_performance(
    'Date Range Query',
    'BEFORE', 
    'SELECT count(*) FROM orders WHERE order_date >= ''2024-01-01'''
);

SELECT * FROM capture_query_performance(
    'Complex WHERE Multiple',
    'BEFORE',
    'SELECT count(*) FROM orders WHERE status = ''completed'' AND total_amount > 1000 AND order_date >= ''2023-06-01'''
);

-- Test Suite 2: JOIN Performance
SELECT * FROM capture_query_performance(
    'Simple JOIN Query',
    'BEFORE',
    'SELECT count(*) FROM orders o JOIN customers c ON o.customer_id = c.id WHERE c.city = ''Bangkok'''
);

SELECT * FROM capture_query_performance(
    'Complex Multi-JOIN',
    'BEFORE',
    'SELECT count(*) FROM orders o 
     JOIN customers c ON o.customer_id = c.id 
     JOIN order_items oi ON o.id = oi.order_id
     JOIN products p ON oi.product_id = p.id
     WHERE c.city = ''Bangkok'' AND o.status = ''completed'' AND p.category = ''electronics'''
);

-- Test Suite 3: Aggregation Queries
SELECT * FROM capture_query_performance(
    'GROUP BY Aggregation',
    'BEFORE',
    'SELECT category, count(*), avg(price), max(price) FROM products WHERE is_active = true GROUP BY category'
);

SELECT * FROM capture_query_performance(
    'Complex Aggregation JOIN',
    'BEFORE',
    'SELECT c.city, c.customer_tier, count(o.id) as order_count, sum(o.total_amount) as revenue
     FROM customers c 
     LEFT JOIN orders o ON c.id = o.customer_id 
     WHERE c.is_active = true
     GROUP BY c.city, c.customer_tier
     HAVING count(o.id) > 5'
);

-- Test Suite 4: Text and Array Searches
SELECT * FROM capture_query_performance(
    'Text Search ILIKE',
    'BEFORE',
    'SELECT count(*) FROM products WHERE name ILIKE ''%phone%'' OR description ILIKE ''%smartphone%'''
);

SELECT * FROM capture_query_performance(
    'Array Search',
    'BEFORE',
    'SELECT count(*) FROM products WHERE tags && ARRAY[''tag1'', ''tag5'']'
);

-- Test Suite 5: Subquery Performance
SELECT * FROM capture_query_performance(
    'Correlated Subquery',
    'BEFORE',
    'SELECT count(*) FROM customers c 
     WHERE (SELECT count(*) FROM orders WHERE customer_id = c.id AND status = ''completed'') > 5
     AND c.customer_tier IN (''gold'', ''platinum'')'
);

-- Capture baseline cache performance
SELECT capture_cache_metrics('Overall Cache Performance', 'BEFORE');

-- ========================================
-- 8. DISPLAY BEFORE RESULTS
-- ========================================

SELECT 
    '📊 BEFORE OPTIMIZATION RESULTS' as title,
    '════════════════════════════════════════════════════════════════════' as separator;

SELECT 
    test_name as "Test Case",
    execution_time_ms || ' ms' as "Execution Time",
    CASE 
        WHEN execution_time_ms < 50 THEN '🟢 Fast'
        WHEN execution_time_ms < 200 THEN '🟡 OK'
        WHEN execution_time_ms < 1000 THEN '🟠 Slow'
        ELSE '🔴 Very Slow'
    END as "Performance Status",
    rows_examined as "Rows Found",
    COALESCE(seq_scans, 0) as "Table Scans",
    COALESCE(index_scans, 0) as "Index Scans"
FROM performance_baseline 
WHERE test_phase = 'BEFORE' 
    AND execution_time_ms IS NOT NULL
ORDER BY execution_time_ms DESC;

-- Show cache performance
SELECT 
    'Cache Hit Ratio (BEFORE): ' || cache_hit_ratio || '%' as cache_performance,
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

-- Show slow queries from pg_stat_statements
SELECT
    '💔 SLOWEST QUERIES DETECTED:' as title,
    '─────────────────────────────────────────────────────────────────' as separator;

SELECT
    LEFT(query, 80) AS query_preview,
    calls AS execution_count,
    ROUND(total_exec_time::numeric, 2) AS total_time_ms,
    ROUND(mean_exec_time::numeric, 2) AS avg_time_ms,
    ROUND((100.0 * total_exec_time / SUM(total_exec_time) OVER())::numeric, 2) AS time_percentage
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
  AND query NOT LIKE '%pg_stat_activity%'
  AND query NOT LIKE '%performance_baseline%'
  AND (total_exec_time / NULLIF(calls, 0)) > 10
ORDER BY total_exec_time DESC
LIMIT 10;

-- ========================================
-- 9. ADVANCED OPTIMIZATION IMPLEMENTATION
-- ========================================

SELECT '⚡ IMPLEMENTING COMPREHENSIVE OPTIMIZATIONS...' as status;

-- Remove bad indexes first
DROP INDEX IF EXISTS idx_customers_unused1;
DROP INDEX IF EXISTS idx_customers_unused2;
DROP INDEX IF EXISTS idx_products_unused;
DROP INDEX IF EXISTS idx_orders_unused;
DROP INDEX IF EXISTS idx_orders_wrong_order;

-- Phase 1: Essential single-column indexes
CREATE INDEX CONCURRENTLY idx_orders_status_opt ON orders (status);
CREATE INDEX CONCURRENTLY idx_orders_date_opt ON orders (order_date);
CREATE INDEX CONCURRENTLY idx_customers_city_opt ON customers (city);
CREATE INDEX CONCURRENTLY idx_products_category_opt ON products (category);

-- Phase 2: Composite indexes for complex queries
CREATE INDEX CONCURRENTLY idx_orders_status_amount_opt ON orders (status, total_amount);
CREATE INDEX CONCURRENTLY idx_orders_status_date_opt ON orders (status, order_date);
CREATE INDEX CONCURRENTLY idx_orders_status_date_amount_opt ON orders (status, order_date, total_amount);

-- Phase 3: JOIN optimization indexes
CREATE INDEX CONCURRENTLY idx_orders_customer_id_opt ON orders (customer_id);
CREATE INDEX CONCURRENTLY idx_order_items_order_id_opt ON order_items (order_id);
CREATE INDEX CONCURRENTLY idx_order_items_product_id_opt ON order_items (product_id);
CREATE INDEX CONCURRENTLY idx_reviews_product_id_opt ON reviews (product_id);
CREATE INDEX CONCURRENTLY idx_reviews_customer_id_opt ON reviews (customer_id);

-- Phase 4: Covering indexes (INCLUDE frequently selected columns)
CREATE INDEX CONCURRENTLY idx_orders_status_covering_opt ON orders (status) 
    INCLUDE (id, customer_id, order_date, total_amount);

CREATE INDEX CONCURRENTLY idx_customers_city_covering_opt ON customers (city)
    INCLUDE (id, first_name, last_name, customer_tier, registration_date);

CREATE INDEX CONCURRENTLY idx_products_category_covering_opt ON products (category)
    INCLUDE (id, name, price, is_active);

-- Phase 5: Partial indexes for active/frequent data
CREATE INDEX CONCURRENTLY idx_products_category_active_opt ON products (category) 
    WHERE is_active = true;

CREATE INDEX CONCURRENTLY idx_customers_premium_opt ON customers (city, registration_date)
    WHERE customer_tier IN ('gold', 'platinum') AND is_active = true;

CREATE INDEX CONCURRENTLY idx_orders_completed_opt ON orders (order_date, total_amount)
    WHERE status = 'completed';

-- Phase 6: Specialized indexes
-- GIN index for full-text search
CREATE INDEX CONCURRENTLY idx_products_fulltext_opt ON products 
    USING gin (to_tsvector('english', name || ' ' || COALESCE(description, '')));

-- GIN index for array searches
CREATE INDEX CONCURRENTLY idx_products_tags_opt ON products USING gin (tags);

-- Functional index for case-insensitive searches
CREATE INDEX CONCURRENTLY idx_customers_email_lower_opt ON customers (lower(email));

-- Update statistics after index creation
ANALYZE customers, products, orders, order_items, reviews;

-- ========================================
-- 10. AFTER OPTIMIZATION - COMPREHENSIVE TESTING
-- ========================================

SELECT pg_stat_statements_reset();
SELECT pg_stat_reset();

SELECT '🧪 STARTING AFTER OPTIMIZATION TESTING...' as status;

-- Re-run all the same tests
-- Test Suite 1: Basic Queries (should be much faster now)
SELECT * FROM capture_query_performance(
    'Basic Status Query',
    'AFTER',
    'SELECT count(*) FROM orders WHERE status = ''pending'''
);

SELECT * FROM capture_query_performance(
    'Date Range Query',
    'AFTER', 
    'SELECT count(*) FROM orders WHERE order_date >= ''2024-01-01'''
);

SELECT * FROM capture_query_performance(
    'Complex WHERE Multiple',
    'AFTER',
    'SELECT count(*) FROM orders WHERE status = ''completed'' AND total_amount > 1000 AND order_date >= ''2023-06-01'''
);

-- Test Suite 2: JOIN Performance (should be dramatically faster)
SELECT * FROM capture_query_performance(
    'Simple JOIN Query',
    'AFTER',
    'SELECT count(*) FROM orders o JOIN customers c ON o.customer_id = c.id WHERE c.city = ''Bangkok'''
);

SELECT * FROM capture_query_performance(
    'Complex Multi-JOIN',
    'AFTER',
    'SELECT count(*) FROM orders o 
     JOIN customers c ON o.customer_id = c.id 
     JOIN order_items oi ON o.id = oi.order_id
     JOIN products p ON oi.product_id = p.id
     WHERE c.city = ''Bangkok'' AND o.status = ''completed'' AND p.category = ''electronics'''
);

-- Test Suite 3: Aggregation Queries (using partial indexes)
SELECT * FROM capture_query_performance(
    'GROUP BY Aggregation',
    'AFTER',
    'SELECT category, count(*), avg(price), max(price) FROM products WHERE is_active = true GROUP BY category'
);

SELECT * FROM capture_query_performance(
    'Complex Aggregation JOIN',
    'AFTER',
    'SELECT c.city, c.customer_tier, count(o.id) as order_count, sum(o.total_amount) as revenue
     FROM customers c 
     LEFT JOIN orders o ON c.id = o.customer_id 
     WHERE c.is_active = true
     GROUP BY c.city, c.customer_tier
     HAVING count(o.id) > 5'
);

-- Test Suite 4: Optimized Text and Array Searches
SELECT * FROM capture_query_performance(
    'Text Search ILIKE',
    'AFTER',
    'SELECT count(*) FROM products 
     WHERE to_tsvector(''english'', name || '' '' || COALESCE(description, '''')) 
           @@ to_tsquery(''english'', ''phone | smartphone'')'
);

SELECT * FROM capture_query_performance(
    'Array Search',
    'AFTER',
    'SELECT count(*) FROM products WHERE tags && ARRAY[''tag1'', ''tag5'']'
);

-- Test Suite 5: Optimized Subquery Performance
SELECT * FROM capture_query_performance(
    'Correlated Subquery',
    'AFTER',
    'SELECT count(*) FROM customers c 
     WHERE (SELECT count(*) FROM orders WHERE customer_id = c.id AND status = ''completed'') > 5
     AND c.customer_tier IN (''gold'', ''platinum'')'
);

-- Capture optimized cache performance
SELECT capture_cache_metrics('Overall Cache Performance', 'AFTER');

-- ========================================
-- 11. COMPREHENSIVE PERFORMANCE COMPARISON
-- ========================================

SELECT 
    '🏆 ULTIMATE PERFORMANCE IMPROVEMENT REPORT' as title,
    '════════════════════════════════════════════════════════════════════════════════' as separator;

-- Detailed before/after comparison with improvements
WITH performance_comparison AS (
    SELECT 
        test_name,
        MAX(CASE WHEN test_phase = 'BEFORE' THEN execution_time_ms END) as before_ms,
        MAX(CASE WHEN test_phase = 'AFTER' THEN execution_time_ms END) as after_ms,
        MAX(CASE WHEN test_phase = 'BEFORE' THEN seq_scans END) as before_seq_scans,
        MAX(CASE WHEN test_phase = 'AFTER' THEN seq_scans END) as after_seq_scans,
        MAX(CASE WHEN test_phase = 'BEFORE' THEN index_scans END) as before_idx_scans,
        MAX(CASE WHEN test_phase = 'AFTER' THEN index_scans END) as after_idx_scans,
        MAX(CASE WHEN test_phase = 'BEFORE' THEN cache_hit_ratio END) as cache_before,
        MAX(CASE WHEN test_phase = 'AFTER' THEN cache_hit_ratio END) as cache_after
    FROM performance_baseline
    GROUP BY test_name
)
SELECT 
    test_name as "Test Case",
    COALESCE(before_ms, 0) || ' ms' as "Before",
    COALESCE(after_ms, 0) || ' ms' as "After", 
    CASE 
        WHEN before_ms > 0 AND after_ms > 0 THEN 
            ROUND(before_ms / after_ms, 1) || 'x'
        ELSE 'N/A'
    END as "Speed Gain",
    CASE 
        WHEN before_ms > 0 AND after_ms > 0 THEN
            ROUND(((before_ms - after_ms) / before_ms) * 100, 1) || '%'
        ELSE 'N/A'
    END as "% Faster",
    COALESCE(before_seq_scans, 0) || ' → ' || COALESCE(after_seq_scans, 0) as "Table Scans",
    COALESCE(before_idx_scans, 0) || ' → ' || COALESCE(after_idx_scans, 0) as "Index Scans",
    CASE 
        WHEN COALESCE(after_ms, 0) < 50 THEN '🟢 Excellent'
        WHEN COALESCE(after_ms, 0) < 200 THEN '🟢 Good'
        WHEN COALESCE(after_ms, 0) < 1000 THEN '🟡 OK'
        ELSE '🔴 Needs Work'
    END as "Final Status"
FROM performance_comparison
WHERE before_ms IS NOT NULL AND after_ms IS NOT NULL
ORDER BY 
    CASE WHEN before_ms > 0 AND after_ms > 0 THEN before_ms / after_ms ELSE 0 END DESC;

-- Cache performance comparison
SELECT 
    '💾 CACHE PERFORMANCE COMPARISON' as metric_type,
    '─────────────────────────────────────────────────────────────────' as separator
UNION ALL
SELECT 
    'Cache Hit Ratio Improvement' as metric_type,
    'Before: ' || COALESCE(cache_before, 0) || '%  →  After: ' || COALESCE(cache_after, 0) || '%  (' ||
    CASE 
        WHEN cache_before > 0 AND cache_after > 0 THEN 
            '+' || ROUND(cache_after - cache_before, 1) || '% improvement)'
        ELSE 'N/A)'
    END as comparison
FROM (
    SELECT 
        MAX(CASE WHEN test_phase = 'BEFORE' THEN cache_hit_ratio END) as cache_before,
        MAX(CASE WHEN test_phase = 'AFTER' THEN cache_hit_ratio END) as cache_after
    FROM performance_baseline
    WHERE test_name = 'Overall Cache Performance'
) cache_comparison;

-- ========================================
-- 12. INDEX USAGE ANALYSIS
-- ========================================

SELECT 
    '📊 OPTIMIZED INDEX USAGE ANALYSIS' as title,
    '═══════════════════════════════════════════════════════════════════' as separator;

SELECT 
    schemaname as schema,
    relname as table_name,
    indexrelname as index_name,
    idx_scan as times_used,
    idx_tup_read as rows_read,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size,
    CASE 
        WHEN idx_scan = 0 THEN '🔴 Not Used'
        WHEN idx_scan < 10 THEN '🟡 Low Usage'
        WHEN idx_scan < 100 THEN '🟢 Good Usage'
        ELSE '🟢 High Usage'
    END as usage_status
FROM pg_stat_user_indexes
WHERE indexrelname LIKE '%_opt'
ORDER BY idx_scan DESC;

-- Show unused indexes that can be dropped
SELECT 
    '🗑️  UNUSED INDEXES TO CONSIDER DROPPING' as title,
    '─────────────────────────────────────────────────────────────────' as separator;

SELECT 
    schemaname,
    relname as table_name,
    indexrelname as index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) as wasted_space,
    idx_scan as usage_count
FROM pg_stat_user_indexes
WHERE idx_scan = 0  
    AND indexrelname NOT LIKE '%_pkey'
    AND indexrelname NOT LIKE '%_opt' -- Don't suggest dropping our optimized indexes immediately
ORDER BY pg_relation_size(indexrelid) DESC;

-- ========================================
-- 13. ADVANCED HEALTH CHECK & MONITORING
-- ========================================

-- Comprehensive health check
WITH cache_stats AS (
    SELECT 
        ROUND(100.0 * sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0), 2) as cache_hit_ratio
    FROM pg_statio_user_tables
),
slow_queries AS (
    SELECT count(*) as slow_count
    FROM pg_stat_statements 
    WHERE mean_exec_time > 1000
),
long_transactions AS (
    SELECT count(*) as long_tx_count
    FROM pg_stat_activity 
    WHERE state = 'active' 
        AND NOW() - query_start > interval '5 minutes'
),
table_bloat AS (
    SELECT count(*) as bloated_tables
    FROM pg_stat_user_tables 
    WHERE n_dead_tup > n_live_tup * 0.1
    AND n_dead_tup > 1000
)
SELECT 
    '🏥 COMPREHENSIVE DATABASE HEALTH STATUS' as title,
    '═══════════════════════════════════════════════════════════════════' as separator
UNION ALL
SELECT 
    'Memory Performance' as component,
    CASE 
        WHEN cache_hit_ratio < 90 THEN '🔴 CRITICAL: Cache Hit Ratio = ' || cache_hit_ratio || '%'
        WHEN cache_hit_ratio < 95 THEN '🟡 WARNING: Cache Hit Ratio = ' || cache_hit_ratio || '%'  
        ELSE '🟢 HEALTHY: Cache Hit Ratio = ' || cache_hit_ratio || '%'
    END as status
FROM cache_stats
UNION ALL
SELECT 
    'Query Performance' as component,
    CASE 
        WHEN slow_count > 10 THEN '🔴 CRITICAL: ' || slow_count || ' slow queries detected'
        WHEN slow_count > 5 THEN '🟡 WARNING: ' || slow_count || ' slow queries detected'
        ELSE '🟢 HEALTHY: ' || slow_count || ' slow queries'
    END as status
FROM slow_queries
UNION ALL
SELECT 
    'Transaction Health' as component,
    CASE 
        WHEN long_tx_count > 5 THEN '🔴 CRITICAL: ' || long_tx_count || ' long running transactions'
        WHEN long_tx_count > 2 THEN '🟡 WARNING: ' || long_tx_count || ' long running transactions'  
        ELSE '🟢 HEALTHY: ' || long_tx_count || ' long running transactions'
    END as status
FROM long_transactions
UNION ALL
SELECT
    'Table Maintenance' as component,
    CASE 
        WHEN bloated_tables > 5 THEN '🔴 CRITICAL: ' || bloated_tables || ' tables need VACUUM'
        WHEN bloated_tables > 2 THEN '🟡 WARNING: ' || bloated_tables || ' tables need VACUUM'
        ELSE '🟢 HEALTHY: ' || bloated_tables || ' tables need attention'
    END as status
FROM table_bloat;

-- ========================================
-- 14. ULTIMATE PERFORMANCE SCORECARD
-- ========================================

WITH performance_metrics AS (
    SELECT 
        -- Memory Performance (25 points)
        CASE 
            WHEN cache_hit_ratio > 98 THEN 25
            WHEN cache_hit_ratio > 95 THEN 22
            WHEN cache_hit_ratio > 90 THEN 18
            WHEN cache_hit_ratio > 85 THEN 15
            ELSE 10
        END as memory_score,
        cache_hit_ratio,
        
        -- Query Performance (30 points)  
        CASE 
            WHEN slow_queries = 0 THEN 30
            WHEN slow_queries <= 2 THEN 25
            WHEN slow_queries <= 5 THEN 20
            WHEN slow_queries <= 10 THEN 15
            ELSE 10
        END as query_score,
        slow_queries,
        
        -- Index Efficiency (25 points)
        CASE 
            WHEN unused_indexes <= 1 THEN 25
            WHEN unused_indexes <= 3 THEN 20
            WHEN unused_indexes <= 5 THEN 15
            ELSE 10
        END as index_score,
        unused_indexes,
        
        -- Improvement Factor (20 points) - NEW!
        CASE 
            WHEN avg_improvement >= 10 THEN 20
            WHEN avg_improvement >= 5 THEN 18
            WHEN avg_improvement >= 3 THEN 15
            WHEN avg_improvement >= 2 THEN 12
            ELSE 8
        END as improvement_score,
        avg_improvement
        
    FROM (
        SELECT 
            ROUND(100.0 * sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0), 2) as cache_hit_ratio,
            (SELECT count(*) FROM pg_stat_statements WHERE mean_exec_time > 200) as slow_queries,
            (SELECT count(*) FROM pg_stat_user_indexes WHERE idx_scan = 0 AND indexrelname NOT LIKE '%_pkey') as unused_indexes,
            (SELECT AVG(before_ms / NULLIF(after_ms, 0)) 
             FROM (
                SELECT 
                    MAX(CASE WHEN test_phase = 'BEFORE' THEN execution_time_ms END) as before_ms,
                    MAX(CASE WHEN test_phase = 'AFTER' THEN execution_time_ms END) as after_ms
                FROM performance_baseline
                WHERE execution_time_ms IS NOT NULL
                GROUP BY test_name
                HAVING MAX(CASE WHEN test_phase = 'BEFORE' THEN execution_time_ms END) IS NOT NULL
                   AND MAX(CASE WHEN test_phase = 'AFTER' THEN execution_time_ms END) IS NOT NULL
             ) improvements
            ) as avg_improvement
        FROM pg_statio_user_tables
    ) base
)
SELECT 
    '🎯 ULTIMATE PERFORMANCE SCORECARD' as title,
    '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' as separator
UNION ALL
SELECT '', ''
UNION ALL
SELECT 
    'Memory Performance:     ' || memory_score || '/25  (Cache Hit: ' || cache_hit_ratio || '%)',
    ''
FROM performance_metrics
UNION ALL
SELECT 
    'Query Performance:      ' || query_score || '/30  (Slow Queries: ' || slow_queries || ')', 
    ''
FROM performance_metrics
UNION ALL
SELECT 
    'Index Efficiency:       ' || index_score || '/25  (Unused Indexes: ' || unused_indexes || ')', 
    ''
FROM performance_metrics
UNION ALL
SELECT 
    'Performance Gain:       ' || improvement_score || '/20  (Avg Improvement: ' || ROUND(avg_improvement, 1) || 'x)',
    ''
FROM performance_metrics
UNION ALL
SELECT 
    '                        ──────────',
    ''
UNION ALL
SELECT 
    'TOTAL SCORE:            ' || (memory_score + query_score + index_score + improvement_score) || '/100',
    ''
FROM performance_metrics
UNION ALL
SELECT '', ''
UNION ALL
SELECT 
    'PERFORMANCE GRADE: ' || 
    CASE 
        WHEN (memory_score + query_score + index_score + improvement_score) >= 90 THEN '🟢 A+ (Outstanding!)'
        WHEN (memory_score + query_score + index_score + improvement_score) >= 80 THEN '🟢 A (Excellent)'
        WHEN (memory_score + query_score + index_score + improvement_score) >= 70 THEN '🟢 B (Very Good)'
        WHEN (memory_score + query_score + index_score + improvement_score) >= 60 THEN '🟡 C (Good)'
        ELSE '🔴 D (Needs Improvement)'
    END,
    ''
FROM performance_metrics;

-- ========================================
-- 15. MAINTENANCE RECOMMENDATIONS
-- ========================================

SELECT 
    '🔧 ONGOING MAINTENANCE RECOMMENDATIONS' as title,
    '═══════════════════════════════════════════════════════════════════' as separator;

-- Show tables that need VACUUM
SELECT 
    '🧹 Tables Needing VACUUM:' as category,
    schemaname || '.' || relname || 
    ' (Dead tuples: ' || n_dead_tup || ', Live: ' || n_live_tup || 
    ', Ratio: ' || ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 1) || '%)' as recommendation
FROM pg_stat_user_tables 
WHERE n_dead_tup > n_live_tup * 0.1
    AND n_dead_tup > 1000
ORDER BY n_dead_tup DESC
LIMIT 5;

-- Show configuration recommendations
SELECT '⚙️ Configuration Tuning:' as category, 
       'Consider adjusting shared_buffers, work_mem, effective_cache_size based on system resources' as recommendation
UNION ALL
SELECT '📊 Regular Monitoring:', 
       'Run this performance analysis weekly to track trends and catch regressions early'
UNION ALL
SELECT '🗂️ Index Maintenance:',
       'Monitor index usage monthly and drop unused indexes to save space'
UNION ALL
SELECT '📈 Query Analysis:',
       'Review pg_stat_statements regularly for new slow queries'
UNION ALL
SELECT '🔄 Statistics Updates:',
       'Run ANALYZE after major data changes to keep query planner informed';

-- Clean up functions
DROP FUNCTION IF EXISTS capture_query_performance(VARCHAR, VARCHAR, TEXT);
DROP FUNCTION IF EXISTS capture_cache_metrics(VARCHAR, VARCHAR);

-- Final status
SELECT 
    '✅ ULTIMATE PERFORMANCE TUNING PLAYBOOK COMPLETE!' as status,
    'Your database is now optimized for maximum performance.' as message;

-- ========================================
-- OPTIONAL: KEEP PERFORMANCE_BASELINE TABLE
-- ========================================
-- Uncomment to keep the baseline table for historical tracking:
-- SELECT 'Performance baseline data saved in performance_baseline table for future reference.' as note;

-- Or uncomment to clean up:
-- DROP TABLE IF EXISTS performance_baseline;

-- ========================================
-- END OF ULTIMATE PERFORMANCE PLAYBOOK
-- ========================================
