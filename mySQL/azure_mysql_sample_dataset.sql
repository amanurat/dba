
-- -----------------------------------------------
-- Create Tables
-- -----------------------------------------------
CREATE TABLE tribal_customers (
    customer_id INT PRIMARY KEY,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    email VARCHAR(100),
    created_at DATETIME
);

CREATE TABLE tribal_orders (
    order_id INT PRIMARY KEY AUTO_INCREMENT,
    customer_id INT,
    order_date DATETIME,
    amount DECIMAL(10,2),
    status ENUM('PENDING', 'COMPLETED', 'CANCELLED'),
    FOREIGN KEY (customer_id) REFERENCES tribal_customers(customer_id)
);

-- -----------------------------------------------
-- Insert Customers using Recursive CTE
-- -----------------------------------------------
SET SESSION cte_max_recursion_depth = 100000;

WITH RECURSIVE seq AS (
  SELECT 1 AS n
  UNION ALL
  SELECT n + 1 FROM seq WHERE n < 100000
)
INSERT INTO tribal_customers (customer_id, first_name, last_name, email, created_at)
SELECT 
  n,
  CONCAT('First', n),
  CONCAT('Last', n),
  CONCAT('user', n, '@tribal.io'),
  NOW() - INTERVAL FLOOR(RAND() * 365) DAY
FROM seq;

-- -----------------------------------------------
-- Insert Tribal Orders Randomly
-- -----------------------------------------------
INSERT INTO tribal_orders (customer_id, order_date, amount, status)
SELECT 
  customer_id,
  NOW() - INTERVAL FLOOR(RAND() * 90) DAY,
  ROUND(10 + (RAND() * 990), 2),
  ELT(FLOOR(1 + (RAND() * 3)), 'PENDING', 'COMPLETED', 'CANCELLED')
FROM tribal_customers
WHERE customer_id % 2 = 0
UNION
SELECT 
  customer_id,
  NOW() - INTERVAL FLOOR(RAND() * 90) DAY,
  ROUND(10 + (RAND() * 990), 2),
  ELT(FLOOR(1 + (RAND() * 3)), 'PENDING', 'COMPLETED', 'CANCELLED')
FROM tribal_customers
WHERE customer_id % 5 = 0;

-- -----------------------------------------------
-- Add Indexes
-- -----------------------------------------------
CREATE INDEX idx_customer_order_date ON tribal_orders(customer_id, order_date);
CREATE INDEX idx_amount_status ON tribal_orders(amount, status);
