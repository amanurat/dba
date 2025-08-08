
-- 1. SELECT with index usage
SELECT * FROM orders WHERE customer_id = 12345;

-- 2. SELECT full scan
SELECT * FROM orders WHERE amount > 0;

-- 3. JOIN query for business logic simulation
SELECT o.id, o.amount, c.name
FROM orders o
JOIN customers c ON o.customer_id = c.id
WHERE o.status = 'completed'
ORDER BY o.ordered_at DESC
LIMIT 500;

-- 4. Aggregation query
SELECT country, COUNT(*), AVG(amount)
FROM orders
JOIN customers ON orders.customer_id = customers.id
GROUP BY country;

-- 5. Update status (simulate write load)
UPDATE orders SET status = 'completed'
WHERE status = 'pending' AND ordered_at < now() - INTERVAL '180 days';

-- 6. Insert simulated new orders
INSERT INTO orders (customer_id, amount, status, ordered_at)
SELECT (random() * 100000 + 1)::int,
       round((random() * 1000 + 20)::numeric, 2),
       'pending',
       now() - (random() * INTERVAL '365 days')
FROM generate_series(1, 1000);

-- 7. Simulate repeated SELECTs (loop)
DO $$
BEGIN
    FOR i IN 1..50 LOOP
        PERFORM * FROM orders WHERE customer_id = (random() * 100000 + 1)::int;
    END LOOP;
END $$;

-- 8. Deliberately slow query (no index)
SELECT * FROM orders WHERE amount::text LIKE '%12.3%';