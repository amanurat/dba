
-- Drop tables if exist (safety reset)
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS orders;

-- Create customers table
CREATE TABLE customers (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    age INT,
    country TEXT,
    created_at TIMESTAMP DEFAULT now()
);

-- Create orders table
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    customer_id INT REFERENCES customers(id),
    amount NUMERIC(10, 2),
    status TEXT,
    ordered_at TIMESTAMP DEFAULT now()
);

-- Insert 100k sample customers
INSERT INTO customers (name, email, age, country)
SELECT 
    'Customer ' || i,
    'customer_' || i || '@test.com',
    20 + (random() * 40)::INT,
    CASE WHEN i % 5 = 0 THEN 'USA'
         WHEN i % 5 = 1 THEN 'UK'
         WHEN i % 5 = 2 THEN 'TH'
         WHEN i % 5 = 3 THEN 'JP'
         ELSE 'SG' END
FROM generate_series(1, 100000) AS i;

-- Insert 500k sample orders (แก้ไขการใช้ round)
INSERT INTO orders (customer_id, amount, status, ordered_at)
SELECT
    floor(random() * 100000 + 1)::int,  -- ได้ค่า 1 ถึง 100,000 เท่านั้น
        round((random() * 1000 + 20)::numeric, 2),
    CASE WHEN i % 3 = 0 THEN 'completed'
         WHEN i % 3 = 1 THEN 'pending'
         ELSE 'cancelled' END,
    now() - (random() * INTERVAL '365 days')
FROM generate_series(1, 500000) AS i;

-- Create indexes for tuning scenarios
CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_ordered_at ON orders(ordered_at);
