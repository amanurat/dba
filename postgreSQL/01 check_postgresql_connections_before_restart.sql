
-- 🔍 CHECK: Who is currently connected and active?
SELECT pid,
       usename AS user,
       application_name,
       client_addr AS ip,
       state,
       query,
       backend_start,
       xact_start,
       query_start
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY query_start DESC;

-- 🧑‍💻 CHECK: Who is connected to the database (all states)?
SELECT datname, usename, client_addr, application_name, state
FROM pg_stat_activity
WHERE datname = current_database();

-- 📊 CHECK: Number of sessions per state
SELECT state, COUNT(*) AS connection_count
FROM pg_stat_activity
GROUP BY state;

-- ⛔ CHECK: Transactions that are still open
SELECT pid, usename, state, xact_start, query
FROM pg_stat_activity
WHERE state != 'idle'
  AND xact_start IS NOT NULL
ORDER BY xact_start;

-- 🐌 OPTIONAL: Check long-running queries (running more than 1 minute)
SELECT pid, usename, now() - query_start AS runtime, query
FROM pg_stat_activity
WHERE state = 'active'
  AND now() - query_start > interval '1 minute'
ORDER BY runtime DESC;
