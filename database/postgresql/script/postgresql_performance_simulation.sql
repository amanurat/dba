-- ================================================
-- PostgreSQL Performance Tuning Simulation
-- Based on postgresql_performance_guide-update.md
-- ================================================

-- ========================================
-- 1. SETUP: Enable Extensions & Monitoring
-- ========================================

-- Enable pg_stat_statements for query monitoring
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pg_trgm;  -- For text search optimization

-- Reset statistics to start fresh
SELECT pg_stat_statements_reset();

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

-- Reviews table (for JOIN performance testing)
DROP TABLE IF EXISTS reviews CASCADE;
CREATE TABLE reviews (
    id SERIAL PRIMARY KEY,
    product_id INTEGER NOT NULL REFERENCES products(id),
    customer_id INTEGER NOT NULL REFERENCES customers(id),
    rating INTEGER CHECK (rating >= 1 AND rating <= 5),
    review_text TEXT,
    is_verified BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
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

-- Insert orders (200,000 records - this will create performance challenges)
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

-- Insert order items (500,000 records)
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

-- Insert reviews (100,000 records)
INSERT INTO reviews (product_id, customer_id, rating, review_text, is_verified, created_at)
SELECT 
    (random() * 9999 + 1)::integer,
    (random() * 49999 + 1)::integer,
    (random() * 5 + 1)::integer,
    CASE WHEN random() > 0.3 THEN 
        'This is a review for product. ' || 
        CASE (random() * 3)::integer
            WHEN 0 THEN 'Excellent quality and fast delivery!'
            WHEN 1 THEN 'Good value for money, recommended.'
            ELSE 'Average product, nothing special.'
        END
    ELSE NULL END,
    CASE WHEN random() > 0.4 THEN true ELSE false END,
    NOW() - (random() * interval '12 months')
FROM generate_series(1, 100000) AS i;

-- Update table statistics
ANALYZE customers, products, orders, order_items, reviews;

-- ========================================
-- 4. CREATE INTENTIONALLY BAD INDEXES (for optimization demo)
-- ========================================

-- Create some unnecessary indexes that waste space
CREATE INDEX idx_customers_unused1 ON customers (phone);  -- Rarely queried
CREATE INDEX idx_customers_unused2 ON customers (address); -- Text field, inefficient
CREATE INDEX idx_products_unused ON products (weight);     -- Rarely queried
CREATE INDEX idx_orders_unused ON orders (notes);          -- Text field, rarely queried

-- Create a composite index in wrong order
CREATE INDEX idx_orders_wrong_order ON orders (total_amount, status); -- Wrong order for typical queries

-- ========================================
-- 5. STEP 1 QUERIES: SYSTEM HEALTH CHECK
-- ========================================

-- 5.1 Database size check
SELECT 
    pg_size_pretty(pg_database_size(current_database())) as database_size,
    pg_database_size(current_database()) / 1024 / 1024 as size_mb;

-- 5.2 Connection usage check
SELECT 
    count(*) as total_connections,
    count(*) FILTER (WHERE state = 'active') as active_connections,
    count(*) FILTER (WHERE state = 'idle') as idle_connections
FROM pg_stat_activity 
WHERE pid <> pg_backend_pid();

-- 5.3 Cache hit ratio check
SELECT 
    ROUND(100.0 * sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0), 2) as cache_hit_ratio,
    sum(heap_blks_hit) as cache_hits,
    sum(heap_blks_read) as disk_reads
FROM pg_statio_user_tables;

-- ========================================
-- 6. STEP 2 QUERIES: SLOW QUERY ANALYSIS
-- ========================================

-- Generate some slow queries first to populate pg_stat_statements

-- Slow Query 1: Full table scan on large table
SELECT count(*) FROM orders WHERE status = 'pending' AND total_amount > 1000;

-- Slow Query 2: Complex JOIN without proper indexes
SELECT 
    c.first_name, c.last_name, o.order_date, o.total_amount
FROM customers c 
JOIN orders o ON c.id = o.customer_id 
WHERE c.city = 'Bangkok' 
    AND o.order_date >= '2024-01-01'
    AND o.status = 'completed'
ORDER BY o.total_amount DESC;

-- Slow Query 3: Text search without GIN index
SELECT * FROM products WHERE name ILIKE '%phone%' OR description ILIKE '%smartphone%';

-- Slow Query 4: Aggregation on large dataset
SELECT 
    category,
    COUNT(*) as product_count,
    AVG(price) as avg_price,
    MAX(price) as max_price
FROM products 
WHERE is_active = true
GROUP BY category
ORDER BY avg_price DESC;

-- Slow Query 5: Complex subquery
SELECT c.*, 
    (SELECT COUNT(*) FROM orders WHERE customer_id = c.id AND status = 'completed') as completed_orders,
    (SELECT AVG(total_amount) FROM orders WHERE customer_id = c.id) as avg_order_value
FROM customers c
WHERE c.registration_date >= '2023-01-01'
    AND c.is_active = true
ORDER BY completed_orders DESC;

-- Now check for slow queries
SELECT 
    LEFT(query, 100) as query_preview,
    calls as จำนวนครั้ง,
    ROUND(total_exec_time::numeric, 2) as รวมเวลา_ms,
    ROUND(mean_exec_time::numeric, 2) as เฉลี่ย_ms,
    ROUND((100.0 * total_exec_time / sum(total_exec_time) OVER()), 2) as เปอร์เซ็นต์
FROM pg_stat_statements 
WHERE query NOT LIKE '%pg_stat_statements%'
    AND query NOT LIKE '%pg_stat_activity%'
    AND mean_exec_time > 10  -- Only queries > 10ms
ORDER BY total_exec_time DESC 
LIMIT 10;

-- ========================================
-- 7. STEP 3 QUERIES: INDEX ANALYSIS  
-- ========================================

-- 7.1 Find unused indexes (wasting space)
SELECT 
    schemaname,
    relname as table_name,
    indexrelname as index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) as wasted_space,
    idx_scan as usage_count
FROM pg_stat_user_indexes
WHERE idx_scan = 0  
    AND indexrelname NOT LIKE '%_pkey'  -- Keep primary keys
ORDER BY pg_relation_size(indexrelid) DESC;

-- 7.2 Find tables needing indexes (too many full table scans)
SELECT 
    schemaname,
    relname as table_name,
    seq_scan as full_table_scans,
    idx_scan as index_scans,
    ROUND(100.0 * seq_scan / NULLIF(seq_scan + idx_scan, 0), 1) as scan_ratio,
    pg_size_pretty(pg_relation_size(oid)) as table_size
FROM pg_stat_user_tables ps
JOIN pg_class pc ON ps.relname = pc.relname
WHERE seq_scan > 10  
    AND pg_relation_size(oid) > 1024*1024  -- Tables > 1MB
ORDER BY seq_scan DESC;

-- 7.3 Find most used indexes (good ones to keep)
SELECT 
    schemaname,
    relname as table_name,
    indexrelname as index_name,
    idx_scan as times_used,
    idx_tup_read as rows_read,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes
WHERE idx_scan > 0
ORDER BY idx_scan DESC
LIMIT 10;

-- ========================================
-- 8. PERFORMANCE OPTIMIZATION EXAMPLES
-- ========================================

-- BEFORE: Test slow queries with timing
\timing on

-- Test 1: Query that needs index on status and order_date
SELECT count(*) FROM orders WHERE status = 'pending' AND order_date >= '2024-01-01';

-- Test 2: JOIN query that needs composite index
SELECT o.id, o.total_amount, c.first_name 
FROM orders o 
JOIN customers c ON o.customer_id = c.id 
WHERE o.status = 'completed' AND c.city = 'Bangkok'
LIMIT 100;

\timing off

-- OPTIMIZATION 1: Create proper indexes
CREATE INDEX CONCURRENTLY idx_orders_status_date_optimized ON orders (status, order_date);
CREATE INDEX CONCURRENTLY idx_customers_city_optimized ON customers (city);
CREATE INDEX CONCURRENTLY idx_orders_status_customer ON orders (status, customer_id);

-- OPTIMIZATION 2: Create covering index
CREATE INDEX CONCURRENTLY idx_orders_covering ON orders (status) INCLUDE (id, total_amount, customer_id, order_date);

-- OPTIMIZATION 3: Create partial index for active products
CREATE INDEX CONCURRENTLY idx_products_category_active ON products (category) WHERE is_active = true;

-- OPTIMIZATION 4: Create GIN index for text search
CREATE INDEX CONCURRENTLY idx_products_text_search ON products USING gin (to_tsvector('english', name || ' ' || description));

-- AFTER: Test optimized queries
\timing on

-- Test 1 (should be much faster now)
SELECT count(*) FROM orders WHERE status = 'pending' AND order_date >= '2024-01-01';

-- Test 2 (should be much faster now)  
SELECT o.id, o.total_amount, c.first_name 
FROM orders o 
JOIN customers c ON o.customer_id = c.id 
WHERE o.status = 'completed' AND c.city = 'Bangkok'
LIMIT 100;

-- Test 3: Text search with GIN index
SELECT id, name, price FROM products 
WHERE to_tsvector('english', name || ' ' || description) @@ to_tsquery('english', 'phone | smartphone');

\timing off

-- ========================================
-- 9. CLEAN UP UNUSED INDEXES
-- ========================================

-- Remove the intentionally bad indexes
DROP INDEX IF EXISTS idx_customers_unused1;
DROP INDEX IF EXISTS idx_customers_unused2; 
DROP INDEX IF EXISTS idx_products_unused;
DROP INDEX IF EXISTS idx_orders_unused;
DROP INDEX IF EXISTS idx_orders_wrong_order;

-- ========================================
-- 10. STEP 6: VALIDATION QUERIES
-- ========================================

-- Check cache hit ratio improvement
SELECT 
    ROUND(100.0 * sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0), 2) as cache_hit_ratio_after
FROM pg_statio_user_tables;

-- Check index usage for new indexes
SELECT 
    schemaname,
    relname as table_name,
    indexrelname as index_name,
    idx_scan as times_used,
    idx_tup_read as rows_read
FROM pg_stat_user_indexes 
WHERE indexrelname LIKE '%_optimized' OR indexrelname LIKE '%_covering' OR indexrelname LIKE '%_active'
ORDER BY idx_scan DESC;

-- Performance comparison query
WITH slow_queries AS (
    SELECT 
        query,
        calls,
        mean_exec_time,
        total_exec_time
    FROM pg_stat_statements 
    WHERE query NOT LIKE '%pg_stat%'
    ORDER BY mean_exec_time DESC
    LIMIT 10
)
SELECT 
    LEFT(query, 80) as query_preview,
    calls,
    ROUND(mean_exec_time::numeric, 2) as avg_time_ms,
    CASE 
        WHEN mean_exec_time < 50 THEN '🟢 Fast'
        WHEN mean_exec_time < 200 THEN '🟡 OK'
        WHEN mean_exec_time < 1000 THEN '🟠 Slow'
        ELSE '🔴 Very Slow'
    END as performance_status
FROM slow_queries;

-- ========================================
-- 11. STABILITY & MAINTENANCE EXAMPLES
-- ========================================

-- Health check query
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
)
SELECT 
    CASE 
        WHEN cache_hit_ratio < 90 THEN 'CRITICAL: Cache Hit Ratio = ' || cache_hit_ratio || '%'
        WHEN cache_hit_ratio < 95 THEN 'WARNING: Cache Hit Ratio = ' || cache_hit_ratio || '%'  
        ELSE 'OK: Cache Hit Ratio = ' || cache_hit_ratio || '%'
    END as memory_status,
    CASE 
        WHEN slow_count > 10 THEN 'CRITICAL: ' || slow_count || ' slow queries detected'
        WHEN slow_count > 5 THEN 'WARNING: ' || slow_count || ' slow queries detected'
        ELSE 'OK: ' || slow_count || ' slow queries'
    END as query_status,
    CASE 
        WHEN long_tx_count > 5 THEN 'CRITICAL: ' || long_tx_count || ' long running transactions'
        WHEN long_tx_count > 2 THEN 'WARNING: ' || long_tx_count || ' long running transactions'  
        ELSE 'OK: ' || long_tx_count || ' long running transactions'
    END as transaction_status
FROM cache_stats, slow_queries, long_transactions;

-- Auto vacuum status
SELECT 
    schemaname,
    tablename,
    last_vacuum,
    last_autovacuum,
    n_dead_tup,
    n_live_tup,
    ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) as dead_tuple_ratio
FROM pg_stat_user_tables 
WHERE n_dead_tup > 100
ORDER BY dead_tuple_ratio DESC;

-- ========================================
-- 12. FINAL PERFORMANCE SCORECARD
-- ========================================

-- Calculate performance score
WITH metrics AS (
    SELECT 
        -- Memory Performance (30 points)
        CASE 
            WHEN cache_hit_ratio > 98 THEN 30
            WHEN cache_hit_ratio > 95 THEN 25
            WHEN cache_hit_ratio > 90 THEN 20
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
        
        -- Database Size (15 points)
        CASE 
            WHEN db_size_gb < 1 THEN 15
            WHEN db_size_gb < 5 THEN 12
            WHEN db_size_gb < 20 THEN 10
            ELSE 8
        END as size_score,
        db_size_gb
        
    FROM (
        SELECT 
            ROUND(100.0 * sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0), 2) as cache_hit_ratio,
            (SELECT count(*) FROM pg_stat_statements WHERE mean_exec_time > 200) as slow_queries,
            (SELECT count(*) FROM pg_stat_user_indexes WHERE idx_scan = 0 AND indexrelname NOT LIKE '%_pkey') as unused_indexes,
            ROUND(pg_database_size(current_database()) / 1024.0 / 1024.0 / 1024.0, 2) as db_size_gb
        FROM pg_statio_user_tables
    ) base
)
SELECT 
    '🎯 PERFORMANCE SCORECARD' as title,
    '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' as separator,
    '' as blank1,
    'Memory Performance:     ' || memory_score || '/30  (Cache Hit: ' || cache_hit_ratio || '%)' as memory_result,
    'Query Performance:      ' || query_score || '/30  (Slow Queries: ' || slow_queries || ')' as query_result,
    'Index Efficiency:       ' || index_score || '/25  (Unused Indexes: ' || unused_indexes || ')' as index_result,
    'Database Size:          ' || size_score || '/15  (Size: ' || db_size_gb || ' GB)' as size_result,
    '                        ──────' as separator2,
    'TOTAL SCORE:            ' || (memory_score + query_score + index_score + size_score) || '/100' as total_score,
    '' as blank2,
    'PERFORMANCE GRADE: ' || 
    CASE 
        WHEN (memory_score + query_score + index_score + size_score) >= 90 THEN '🟢 A (ยอดเยี่ยม)'
        WHEN (memory_score + query_score + index_score + size_score) >= 80 THEN '🟢 B (ดีมาก)'
        WHEN (memory_score + query_score + index_score + size_score) >= 70 THEN '🟡 C (ดี)'
        WHEN (memory_score + query_score + index_score + size_score) >= 60 THEN '🟠 D (พอใช้)'
        ELSE '🔴 F (แย่)'
    END as grade
FROM metrics;

-- ========================================
-- USEFUL MAINTENANCE COMMANDS
-- ========================================

-- Update statistics after major changes
-- ANALYZE;

-- Clean up old statistics
-- SELECT pg_stat_statements_reset();

-- Manual vacuum if needed
-- VACUUM ANALYZE orders;

-- Check current configuration
-- SHOW shared_buffers;
-- SHOW work_mem;
-- SHOW effective_cache_size;

-- ========================================
-- END OF SIMULATION SCRIPT
-- ========================================