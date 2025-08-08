Purpose:
-- query is used to analyze index usage and size in a PostgreSQL database
SELECT schemaname, relname, indexrelname, idx_scan,
       pg_size_pretty(pg_relation_size(indexrelid)) AS idx_size
FROM
    pg_stat_user_indexes;


-- query is used to analyze the performance and execution plan of a query in PostgreSQL.
EXPLAIN (ANALYZE, VERBOSE, COSTS, TIMING, BUFFERS)
SELECT * FROM test_estimates ORDER BY random();

-- query is used to estimate the cost of sequential scans and tuple processing on the pgbench_tellers table
SELECT relpages,
       current_setting('seq_page_cost') AS seq_page_cost,
       relpages * current_setting('seq_page_cost')::decimal AS page_cost,
        reltuples,
       current_setting('cpu_tuple_cost') AS cpu_tuple_cost,
       reltuples * current_setting('cpu_tuple_cost')::decimal AS tuple_cost
FROM pg_class
WHERE relname = 'pgbench_tellers';


--
-- Create a table with 10,000 rows (IDs from 1 to 10,000)
create table test_estimates2 as select * from generate_series(1,10000) as id;
-- Output: SELECT 10000

-- Update planner statistics for the new table
analyze test_estimates2;
-- Output: ANALYZE

-- Run an execution plan and analyze performance of a function-based filter
explain analyze select * from test_estimates2 where cos(id) < 4;

explain analyze select * from test_estimates2 where cos(id) > 4;



--## Spotting Query Problems
create table test_estimates2 as select * from generate_series(1,10000) as id;





    