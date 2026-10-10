-- Запустить в третьем сеансе, пока операция в другом сеансе ждёт блокировку.

SELECT
    pid, usename, state, wait_event_type, wait_event,
    pg_blocking_pids(pid) AS blocking_pids,
    now() - query_start AS query_duration,
    query
FROM pg_stat_activity
WHERE datname = current_database()
  AND pid <> pg_backend_pid()
ORDER BY query_start;

SELECT
    pid, pg_blocking_pids(pid) AS blocking_pids,
    wait_event_type, wait_event, query
FROM pg_stat_activity
WHERE datname = current_database()
  AND wait_event_type = 'Lock';

SELECT
    waiting.pid AS waiting_pid,
    waiting_activity.query AS waiting_query,
    blocking.pid AS blocking_pid,
    blocking_activity.query AS blocking_query,
    waiting.locktype,
    waiting.mode AS waiting_mode,
    blocking.mode AS blocking_mode
FROM pg_locks waiting
JOIN pg_stat_activity waiting_activity ON waiting_activity.pid = waiting.pid
JOIN pg_locks blocking
  ON blocking.locktype = waiting.locktype
 AND blocking.database IS NOT DISTINCT FROM waiting.database
 AND blocking.relation IS NOT DISTINCT FROM waiting.relation
 AND blocking.page IS NOT DISTINCT FROM waiting.page
 AND blocking.tuple IS NOT DISTINCT FROM waiting.tuple
 AND blocking.virtualxid IS NOT DISTINCT FROM waiting.virtualxid
 AND blocking.transactionid IS NOT DISTINCT FROM waiting.transactionid
 AND blocking.classid IS NOT DISTINCT FROM waiting.classid
 AND blocking.objid IS NOT DISTINCT FROM waiting.objid
 AND blocking.objsubid IS NOT DISTINCT FROM waiting.objsubid
 AND blocking.pid <> waiting.pid
JOIN pg_stat_activity blocking_activity ON blocking_activity.pid = blocking.pid
WHERE NOT waiting.granted
  AND blocking.granted;
