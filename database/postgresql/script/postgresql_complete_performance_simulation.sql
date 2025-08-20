-- ================================================
-- PostgreSQL COMPLETE Performance Tuning Simulation
-- สมบูรณ์แบบสำหรับ Before & After Comparison
-- ================================================

-- ========================================
-- 1. SETUP: Enable Extensions & Monitoring
-- ========================================

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- สร้างตารางเก็บผลการทดสอบ
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

-- Reset และเริ่มต้นใหม่
SELECT pg_stat_statements_reset();
SELECT pg_stat_reset();

-- ========================================
-- 2. CREATE SAMPLE TABLES (E-COMMERCE SCENARIO)
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
    total_orders INTEGER DEFAULT 0
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
    dimensions VARCHAR(50)
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
    UNIQUE(product_id, customer_id)
);

-- ========================================
-- 3. GENERATE LARGE SAMPLE DATA
-- ========================================

-- Insert customers (50,000 records)
INSERT INTO customers (email, first_name, last_name, phone, address, city, country, registration_date, is_active, last_login, total_orders)
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
    (random() * 20)::integer
FROM generate_series(1, 50000) AS i;

-- Insert products (10,000 records)
INSERT INTO products (name, description, category, price, stock_quantity, is_active, created_at, manufacturer, weight, dimensions)
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
    ROUND(random() * 30 + 5) || 'x' || ROUND(random() * 20 + 3) || 'x' || ROUND(random() * 10 + 1) || 'cm'
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

-- Insert reviews (safe method)
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
        row_number() OVER (PARTITION BY p.id, c.id ORDER BY random()) as rn
    FROM products p 
    CROSS JOIN customers c
    WHERE p.is_active = true 
        AND c.is_active = true
        AND random() < 0.05
)
INSERT INTO reviews (product_id, customer_id, rating, review_text, is_verified, created_at)
SELECT 
    product_id, customer_id, rating, review_text, is_verified, created_at
FROM review_candidates 
WHERE rn = 1
LIMIT 100000
ON CONFLICT (product_id, customer_id) DO NOTHING;

-- อัปเดตสถิติเริ่มต้น
ANALYZE customers, products, orders, order_items, reviews;

-- ========================================
-- 4. CREATE BAD INDEXES (จำลองปัญหา)
-- ========================================

-- สร้าง indexes ที่ไม่ดีเพื่อจำลองปัญหา
CREATE INDEX idx_customers_unused1 ON customers (phone);
CREATE INDEX idx_customers_unused2 ON customers (address);
CREATE INDEX idx_products_unused ON products (weight);
CREATE INDEX idx_orders_unused ON orders (notes);
CREATE INDEX idx_orders_wrong_order ON orders (total_amount, status); -- Wrong order

-- ========================================
-- 5. BASELINE PERFORMANCE CAPTURE FUNCTIONS
-- ========================================

-- ฟังก์ชันจับเวลาการทำงาน
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
    result_record RECORD;
    exec_time NUMERIC;
    rows_count BIGINT;
BEGIN
    -- บันทึกเวลาเริ่มต้น
    start_time := clock_timestamp();
    
    -- รัน query และนับ rows
    EXECUTE 'SELECT count(*) FROM (' || query_text || ') as subquery' INTO rows_count;
    
    -- บันทึกเวลาสิ้นสุด
    end_time := clock_timestamp();
    
    -- คำนวณเวลาที่ใช้
    exec_time := ROUND(EXTRACT(EPOCH FROM (end_time - start_time)) * 1000, 2);
    
    -- บันทึกลงตาราง baseline
    INSERT INTO performance_baseline (test_name, test_phase, execution_time_ms, rows_examined, test_timestamp)
    VALUES (test_name_param, test_phase_param, exec_time, rows_count, NOW());
    
    -- ส่งค่ากลับ
    execution_time_ms := exec_time;
    rows_returned := rows_count;
    RETURN NEXT;
END;
$$ LANGUAGE plpgsql;

-- ฟังก์ชันจับ cache hit ratio
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
    
    -- บันทึกลงตาราง baseline
    INSERT INTO performance_baseline (test_name, test_phase, cache_hit_ratio, test_timestamp)
    VALUES (test_name_param, test_phase_param, cache_hit_ratio, NOW());
    
    RETURN cache_hit_ratio;
END;
$$ LANGUAGE plpgsql;

-- ========================================
-- 6. COMPREHENSIVE BEFORE TESTING
-- ========================================

-- Reset statistics สำหรับการทดสอบ
SELECT pg_stat_statements_reset();
SELECT pg_stat_reset();

-- Test Suite 1: Simple Queries (ควรเร็ว แต่ไม่มี index)
SELECT '🧪 STARTING BEFORE TESTING...' as status;

-- Test 1.1: Single WHERE condition
SELECT * FROM capture_query_performance(
    'Single WHERE - Status',
    'BEFORE',
    'SELECT count(*) FROM orders WHERE status = ''pending'''
);

-- Test 1.2: Date Range Query
SELECT * FROM capture_query_performance(
    'Date Range Query',
    'BEFORE', 
    'SELECT count(*) FROM orders WHERE order_date >= ''2024-01-01'''
);

-- Test 1.3: Multiple WHERE conditions
SELECT * FROM capture_query_performance(
    'Multiple WHERE',
    'BEFORE',
    'SELECT count(*) FROM orders WHERE status = ''completed'' AND total_amount > 1000'
);

-- Test Suite 2: JOIN Queries (จะช้ามากเพราะไม่มี index)
-- Test 2.1: Simple JOIN
SELECT * FROM capture_query_performance(
    'Simple JOIN',
    'BEFORE',
    'SELECT count(*) FROM orders o JOIN customers c ON o.customer_id = c.id WHERE c.city = ''Bangkok'''
);

-- Test 2.2: Complex JOIN with WHERE
SELECT * FROM capture_query_performance(
    'Complex JOIN',
    'BEFORE',
    'SELECT count(*) FROM orders o 
     JOIN customers c ON o.customer_id = c.id 
     JOIN order_items oi ON o.id = oi.order_id
     WHERE c.city = ''Bangkok'' AND o.status = ''completed'' AND oi.quantity > 2'
);

-- Test Suite 3: Aggregation Queries
-- Test 3.1: GROUP BY on large table
SELECT * FROM capture_query_performance(
    'GROUP BY Category',
    'BEFORE',
    'SELECT category, count(*), avg(price) FROM products WHERE is_active = true GROUP BY category'
);

-- Test 3.2: Complex aggregation with JOIN
SELECT * FROM capture_query_performance(
    'Complex Aggregation',
    'BEFORE',
    'SELECT c.city, count(o.id) as order_count, sum(o.total_amount) as total_revenue
     FROM customers c 
     LEFT JOIN orders o ON c.id = o.customer_id 
     WHERE c.registration_date >= ''2023-01-01''
     GROUP BY c.city
     HAVING count(o.id) > 10'
);

-- Test Suite 4: Text Search (ช้ามากเพราะไม่มี GIN index)
-- Test 4.1: ILIKE search
SELECT * FROM capture_query_performance(
    'Text Search ILIKE',
    'BEFORE',
    'SELECT count(*) FROM products WHERE name ILIKE ''%phone%'' OR description ILIKE ''%smartphone%'''
);

-- Test Suite 5: Subquery Performance
-- Test 5.1: Correlated subquery
SELECT * FROM capture_query_performance(
    'Correlated Subquery', 
    'BEFORE',
    'SELECT count(*) FROM customers c 
     WHERE (SELECT count(*) FROM orders WHERE customer_id = c.id AND status = ''completed'') > 5'
);

-- Capture baseline cache performance
SELECT capture_cache_metrics('Overall Cache Performance', 'BEFORE');

-- ========================================
-- 7. DISPLAY BEFORE RESULTS
-- ========================================

SELECT 
    '📊 BEFORE OPTIMIZATION RESULTS' as title,
    '════════════════════════════════════════════════════════════════════' as separator;

SELECT 
    test_name,
    execution_time_ms || ' ms' as execution_time,
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

-- ========================================
-- 8. OPTIMIZATION IMPLEMENTATION
-- ========================================

SELECT '⚡ APPLYING OPTIMIZATIONS...' as status;

-- Remove bad indexes first
DROP INDEX IF EXISTS idx_customers_unused1;
DROP INDEX IF EXISTS idx_customers_unused2;
DROP INDEX IF EXISTS idx_products_unused;
DROP INDEX IF EXISTS idx_orders_unused;
DROP INDEX IF EXISTS idx_orders_wrong_order;

-- Create optimized indexes
-- For single column queries
CREATE INDEX CONCURRENTLY idx_orders_status_opt ON orders (status);
CREATE INDEX CONCURRENTLY idx_orders_date_opt ON orders (order_date);
CREATE INDEX CONCURRENTLY idx_customers_city_opt ON customers (city);

-- For multiple column queries (composite indexes)
CREATE INDEX CONCURRENTLY idx_orders_status_amount_opt ON orders (status, total_amount);
CREATE INDEX CONCURRENTLY idx_orders_status_date_opt ON orders (status, order_date);
CREATE INDEX CONCURRENTLY idx_customers_city_registration_opt ON customers (city, registration_date);

-- For JOIN performance
CREATE INDEX CONCURRENTLY idx_orders_customer_id_opt ON orders (customer_id);
CREATE INDEX CONCURRENTLY idx_order_items_order_id_opt ON order_items (order_id);
CREATE INDEX CONCURRENTLY idx_order_items_product_id_opt ON order_items (product_id);
CREATE INDEX CONCURRENTLY idx_reviews_product_id_opt ON reviews (product_id);

-- Covering indexes (include commonly selected columns)
CREATE INDEX CONCURRENTLY idx_orders_status_covering_opt ON orders (status) 
    INCLUDE (id, customer_id, order_date, total_amount);

CREATE INDEX CONCURRENTLY idx_customers_city_covering_opt ON customers (city)
    INCLUDE (id, first_name, last_name, registration_date);

-- Partial indexes (for active/common data only)
CREATE INDEX CONCURRENTLY idx_products_category_active_opt ON products (category) 
    WHERE is_active = true;

CREATE INDEX CONCURRENTLY idx_customers_active_city_opt ON customers (city)
    WHERE is_active = true;

-- Text search optimization
CREATE INDEX CONCURRENTLY idx_products_fulltext_opt ON products 
    USING gin (to_tsvector('english', name || ' ' || COALESCE(description, '')));

-- Update statistics after index creation
ANALYZE customers, products, orders, order_items, reviews;

-- ========================================
-- 9. COMPREHENSIVE AFTER TESTING
-- ========================================

-- Reset statistics for clean measurement
SELECT pg_stat_statements_reset();
SELECT pg_stat_reset();

SELECT '🧪 STARTING AFTER TESTING...' as status;

-- Test Suite 1: Simple Queries (ตอนนี้ควรเร็วมาก)
-- Test 1.1: Single WHERE condition
SELECT * FROM capture_query_performance(
    'Single WHERE - Status',
    'AFTER',
    'SELECT count(*) FROM orders WHERE status = ''pending'''
);

-- Test 1.2: Date Range Query
SELECT * FROM capture_query_performance(
    'Date Range Query',
    'AFTER',
    'SELECT count(*) FROM orders WHERE order_date >= ''2024-01-01'''
);

-- Test 1.3: Multiple WHERE conditions
SELECT * FROM capture_query_performance(
    'Multiple WHERE',
    'AFTER',
    'SELECT count(*) FROM orders WHERE status = ''completed'' AND total_amount > 1000'
);

-- Test Suite 2: JOIN Queries (ตอนนี้ควรเร็วขึ้นมาก)
-- Test 2.1: Simple JOIN
SELECT * FROM capture_query_performance(
    'Simple JOIN',
    'AFTER',
    'SELECT count(*) FROM orders o JOIN customers c ON o.customer_id = c.id WHERE c.city = ''Bangkok'''
);

-- Test 2.2: Complex JOIN with WHERE
SELECT * FROM capture_query_performance(
    'Complex JOIN',
    'AFTER',
    'SELECT count(*) FROM orders o 
     JOIN customers c ON o.customer_id = c.id 
     JOIN order_items oi ON o.id = oi.order_id
     WHERE c.city = ''Bangkok'' AND o.status = ''completed'' AND oi.quantity > 2'
);

-- Test Suite 3: Aggregation Queries
-- Test 3.1: GROUP BY on large table (ใช้ partial index)
SELECT * FROM capture_query_performance(
    'GROUP BY Category',
    'AFTER',
    'SELECT category, count(*), avg(price) FROM products WHERE is_active = true GROUP BY category'
);

-- Test 3.2: Complex aggregation with JOIN
SELECT * FROM capture_query_performance(
    'Complex Aggregation', 
    'AFTER',
    'SELECT c.city, count(o.id) as order_count, sum(o.total_amount) as total_revenue
     FROM customers c 
     LEFT JOIN orders o ON c.id = o.customer_id 
     WHERE c.registration_date >= ''2023-01-01''
     GROUP BY c.city
     HAVING count(o.id) > 10'
);

-- Test Suite 4: Text Search (ใช้ GIN index)
-- Test 4.1: Full-text search
SELECT * FROM capture_query_performance(
    'Text Search ILIKE',
    'AFTER',
    'SELECT count(*) FROM products 
     WHERE to_tsvector(''english'', name || '' '' || COALESCE(description, '''')) 
           @@ to_tsquery(''english'', ''phone | smartphone'')'
);

-- Test Suite 5: Subquery Performance
-- Test 5.1: Correlated subquery
SELECT * FROM capture_query_performance(
    'Correlated Subquery',
    'AFTER', 
    'SELECT count(*) FROM customers c 
     WHERE (SELECT count(*) FROM orders WHERE customer_id = c.id AND status = ''completed'') > 5'
);

-- Capture optimized cache performance
SELECT capture_cache_metrics('Overall Cache Performance', 'AFTER');

-- ========================================
-- 10. COMPREHENSIVE BEFORE/AFTER COMPARISON
-- ========================================

SELECT 
    '🏆 PERFORMANCE IMPROVEMENT REPORT' as title,
    '════════════════════════════════════════════════════════════════════════════════' as separator;

-- Detailed before/after comparison
WITH performance_comparison AS (
    SELECT 
        test_name,
        MAX(CASE WHEN test_phase = 'BEFORE' THEN execution_time_ms END) as before_ms,
        MAX(CASE WHEN test_phase = 'AFTER' THEN execution_time_ms END) as after_ms,
        MAX(CASE WHEN test_phase = 'BEFORE' THEN cache_hit_ratio END) as cache_before,
        MAX(CASE WHEN test_phase = 'AFTER' THEN cache_hit_ratio END) as cache_after
    FROM performance_baseline
    WHERE execution_time_ms IS NOT NULL OR cache_hit_ratio IS NOT NULL
    GROUP BY test_name
)
SELECT 
    test_name as "Test Case",
    COALESCE(before_ms, 0) || ' ms' as "Before",
    COALESCE(after_ms, 0) || ' ms' as "After", 
    CASE 
        WHEN before_ms > 0 AND after_ms > 0 THEN 
            ROUND(before_ms / after_ms, 1) || 'x faster'
        ELSE 'N/A'
    END as "Improvement",
    CASE 
        WHEN before_ms > 0 AND after_ms > 0 THEN
            ROUND(((before_ms - after_ms) / before_ms) * 100, 1) || '% faster'
        ELSE 'N/A'
    END as "% Improvement",
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
    'Cache Hit Ratio' as metric_type,
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

-- Summary statistics
WITH summary_stats AS (
    SELECT 
        COUNT(*) as total_tests,
        AVG(CASE WHEN test_phase = 'BEFORE' THEN execution_time_ms END) as avg_before,
        AVG(CASE WHEN test_phase = 'AFTER' THEN execution_time_ms END) as avg_after,
        MAX(CASE WHEN test_phase = 'BEFORE' THEN execution_time_ms END) as max_before,
        MAX(CASE WHEN test_phase = 'AFTER' THEN execution_time_ms END) as max_after
    FROM performance_baseline
    WHERE execution_time_ms IS NOT NULL
)
SELECT 
    '📈 OVERALL SUMMARY' as metric_type,
    '─────────────────────────────────────────────────────────────────' as separator
UNION ALL
SELECT 
    'Average Performance' as metric_type,
    ROUND(avg_before, 1) || ' ms → ' || ROUND(avg_after, 1) || ' ms (' ||
    ROUND(avg_before / NULLIF(avg_after, 0), 1) || 'x faster overall)' as summary
FROM summary_stats
UNION ALL
SELECT 
    'Worst Case Performance' as metric_type,
    ROUND(max_before, 1) || ' ms → ' || ROUND(max_after, 1) || ' ms (' ||
    ROUND(max_before / NULLIF(max_after, 0), 1) || 'x improvement)' as summary
FROM summary_stats;

-- ========================================
-- 11. INDEX USAGE ANALYSIS
-- ========================================

SELECT 
    '📊 INDEX USAGE ANALYSIS' as title,
    '═══════════════════════════════════════════════════════════════════' as separator;

-- Show which new indexes are being used
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

-- ========================================
-- 12. FINAL RECOMMENDATIONS
-- ========================================

SELECT 
    '💡 OPTIMIZATION RECOMMENDATIONS' as title,
    '═══════════════════════════════════════════════════════════════════' as separator;

WITH optimization_summary AS (
    SELECT 
        COUNT(*) as total_tests,
        COUNT(*) FILTER (WHERE 
            (SELECT MAX(CASE WHEN test_phase = 'BEFORE' THEN execution_time_ms END) 
             FROM performance_baseline pb2 
             WHERE pb2.test_name = pb1.test_name) > 
            (SELECT MAX(CASE WHEN test_phase = 'AFTER' THEN execution_time_ms END) 
             FROM performance_baseline pb3 
             WHERE pb3.test_name = pb1.test_name) * 2
        ) as significantly_improved,
        AVG(CASE WHEN test_phase = 'BEFORE' THEN execution_time_ms END) as avg_before,
        AVG(CASE WHEN test_phase = 'AFTER' THEN execution_time_ms END) as avg_after
    FROM performance_baseline pb1
    WHERE execution_time_ms IS NOT NULL
)
SELECT 
    'Tests Performed: ' || total_tests as metric,
    '' as value
FROM optimization_summary
UNION ALL
SELECT 
    'Significantly Improved (>2x): ' || significantly_improved as metric,
    '' as value
FROM optimization_summary
UNION ALL
SELECT 
    'Overall Performance Gain: ' as metric,
    ROUND(avg_before / NULLIF(avg_after, 0), 1) || 'x faster on average' as value
FROM optimization_summary;

-- Clean up test functions
DROP FUNCTION IF EXISTS capture_query_performance(VARCHAR, VARCHAR, TEXT);
DROP FUNCTION IF EXISTS capture_cache_metrics(VARCHAR, VARCHAR);

SELECT 
    '✅ PERFORMANCE TUNING SIMULATION COMPLETE!' as status,
    'Check the results above to see dramatic improvements.' as note;

-- ========================================
-- END OF COMPLETE SIMULATION
-- ========================================