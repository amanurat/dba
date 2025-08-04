
-- ==================================================================
-- Azure MySQL Sample Dataset Generator
-- Tables: tribal_customers, tribal_orders
-- Records: 100,000 customers, ~40,000–50,000 orders
-- Purpose: Performance testing, benchmarking, tuning on Azure MySQL
-- ==================================================================

-- -----------------------------------------------
-- Step 1: Create Tables
-- -----------------------------------------------
DROP TABLE IF EXISTS tribal_orders;
DROP TABLE IF EXISTS tribal_customers;

CREATE TABLE tribal_customers (
    id INT PRIMARY KEY,
    name VARCHAR(100),
    email VARCHAR(100),
    age INT,
    country VARCHAR(50),
    created_at DATETIME
);

CREATE TABLE tribal_orders (
    order_id INT PRIMARY KEY AUTO_INCREMENT,
    id INT,
    order_date DATETIME,
    amount DECIMAL(10,2),
    status ENUM('PENDING', 'COMPLETED', 'CANCELLED'),
    FOREIGN KEY (id) REFERENCES tribal_customers(id)
);

-- -----------------------------------------------
-- Step 2: Insert Sample Customers using Recursive CTE
-- -----------------------------------------------
-- Note: Azure MySQL may require adjusting recursion limit
SET SESSION cte_max_recursion_depth = 100000;

WITH RECURSIVE seq AS (
  SELECT 1 AS n
  UNION ALL
  SELECT n + 1 FROM seq WHERE n < 100000
)
INSERT INTO tribal_customers (id, name, email, age, country, created_at)
SELECT 
  n,
  CONCAT('First', n, ' Last', n),
  CONCAT('user', n, '@tribal.io'),
  FLOOR(18 + (RAND() * 42)), -- age between 18 and 60
  ELT(FLOOR(1 + (RAND() * 5)), 'USA', 'India', 'Thailand', 'Germany', 'Brazil'),
  NOW() - INTERVAL FLOOR(RAND() * 365) DAY
FROM seq;

-- -----------------------------------------------
-- Step 3: Insert Orders Randomly
-- -----------------------------------------------
-- Adds multiple orders per customer with varied status/amount
INSERT INTO tribal_orders (id, order_date, amount, status)
SELECT 
  id,
  NOW() - INTERVAL FLOOR(RAND() * 90) DAY,
  ROUND(10 + (RAND() * 990), 2),
  ELT(FLOOR(1 + (RAND() * 3)), 'PENDING', 'COMPLETED', 'CANCELLED')
FROM tribal_customers
WHERE id % 2 = 0
UNION
SELECT 
  id,
  NOW() - INTERVAL FLOOR(RAND() * 90) DAY,
  ROUND(10 + (RAND() * 990), 2),
  ELT(FLOOR(1 + (RAND() * 3)), 'PENDING', 'COMPLETED', 'CANCELLED')
FROM tribal_customers
WHERE id % 5 = 0;

-- -----------------------------------------------
-- Step 4: Add Indexes for Performance
-- -----------------------------------------------
CREATE INDEX idx_customer_order_date ON tribal_orders(id, order_date);
CREATE INDEX idx_amount_status ON tribal_orders(amount, status);

-- -----------------------------------------------
-- Step 5: Example Queries for Tuning and Testing
-- -----------------------------------------------
-- Slow query simulation (no index used)
-- SELECT * FROM tribal_orders WHERE amount > 500 ORDER BY order_date DESC;

-- Optimized query using index
-- SELECT * FROM tribal_orders WHERE id = 1234 ORDER BY order_date DESC;

-- Query Performance Summary
-- SELECT DIGEST_TEXT, COUNT_STAR, ROUND(SUM_TIMER_WAIT/COUNT_STAR/1000000,2) AS avg_ms
-- FROM performance_schema.events_statements_summary_by_digest
-- ORDER BY avg_ms DESC LIMIT 10;
