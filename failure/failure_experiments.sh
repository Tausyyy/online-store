set -uo pipefail

MODE="${MODE:-docker}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="$ROOT_DIR/failure/results"
LOG_FILE="${LOG_FILE:-$RESULTS_DIR/failure_experiments_raw.txt}"
COMPOSE=(docker compose -f "$ROOT_DIR/replication/compose.yaml")
PGBIN="${PGBIN:-/usr/lib/postgresql/16/bin}"
PGROOT="${PGROOT:-/tmp/pgl}"
DB=online_store
TABLES=(categories customers products sku carts cart_items orders order_items)

mkdir -p "$RESULTS_DIR"
exec > >(tee "$LOG_FILE") 2>&1

ts()  { date '+%H:%M:%S'; }
now() { date +%s.%N; }
say() { printf '\n[%s] %s\n' "$(ts)" "$*"; }


psql_node() {   
  local node="$1" sql="$2" port=5433
  [[ "$node" == replica ]] && port=5434
  if [[ "$MODE" == docker ]]; then
    timeout 10 "${COMPOSE[@]}" exec -T "$node" psql -U postgres -d "$DB" -Atq -F '|' -c "$sql" 2>&1
  else
    timeout 10 su postgres -c "PATH=$PGBIN:\$PATH psql -h $PGROOT -p $port -U postgres -d $DB -Atq -F '|' -c \"$sql\"" 2>&1
  fi
}
P() { psql_node primary "$1"; }
R() { psql_node replica "$1"; }

node_stop() {
  if [[ "$MODE" == docker ]]; then "${COMPOSE[@]}" stop "$1" >/dev/null 2>&1
  else su postgres -c "PATH=$PGBIN:\$PATH pg_ctl -D $PGROOT/$1 -m fast -w stop" >/dev/null 2>&1; fi
}
node_start() {
  if [[ "$MODE" == docker ]]; then "${COMPOSE[@]}" start "$1" >/dev/null 2>&1
  else su postgres -c "PATH=$PGBIN:\$PATH pg_ctl -D $PGROOT/$1 -l $PGROOT/$1.log -w start" >/dev/null 2>&1; fi
}
node_log() {    
  if [[ "$MODE" == docker ]]; then "${COMPOSE[@]}" logs --no-log-prefix --tail="$2" "$1" 2>&1
  else tail -n "$2" "$PGROOT/$1.log"; fi
}


probe_write() {
  local out rc
  out=$(P "INSERT INTO failure_probe(note) VALUES ('$1') RETURNING id")
  rc=$?
  if [[ $rc -eq 0 && "$out" =~ ^[0-9]+$ ]]; then echo "[$(ts)] APP WRITE(primary) OK   id=$out  ($1)"
  else echo "[$(ts)] APP WRITE(primary) FAIL ($1): $(echo "$out" | head -1)"; fi
}
probe_read() {
  local out rc
  out=$(R "SELECT count(*), coalesce(max(id),0) FROM failure_probe")
  rc=$?
  if [[ $rc -eq 0 && "$out" =~ ^[0-9]+\|[0-9]+$ ]]; then echo "[$(ts)] APP READ (replica) OK   rows|max_id=$out"
  else echo "[$(ts)] APP READ (replica) FAIL: $(echo "$out" | head -1)"; fi
}
probe_write_on_replica() {
  local out
  out=$(R "INSERT INTO failure_probe(note) VALUES ('write-to-replica')")
  echo "[$(ts)] APP WRITE(replica) -> $(echo "$out" | head -1)"
}


repl_state() { P "SELECT coalesce(string_agg(state||'/'||sync_state, ','), 'нет подключённых реплик') FROM pg_stat_replication"; }
recv_state() { R "SELECT coalesce((SELECT status FROM pg_stat_wal_receiver), 'нет walreceiver')"; }

wait_caught_up() {   
  local t0 t1 a b
  t0=$(now)
  for _ in $(seq 1 60); do
    a=$(P "SELECT count(*) FROM failure_probe"); b=$(R "SELECT count(*) FROM failure_probe")
    if [[ "$a" =~ ^[0-9]+$ && "$a" == "$b" ]]; then
      t1=$(now); printf 'догнала за %.1f с (failure_probe: primary=%s replica=%s)\n' "$(awk "BEGIN{print $t1 - $t0}")" "$a" "$b"; return 0
    fi
    sleep 0.5
  done
  echo "НЕ догнала за 30 с (primary=$a replica=$b)"; return 1
}

integrity_check() {  
  local bad=0 sql t a b
  for t in "${TABLES[@]}" failure_probe; do
    sql="SELECT count(*)||'|'||coalesce(md5(string_agg(x::text,'' ORDER BY x::text)),'-') FROM public.$t x"
    a=$(P "$sql"); b=$(R "$sql")
    if [[ "$a" == "$b" && "$a" != *ERROR* ]]; then printf '  %-14s MATCH  %s\n' "$t" "${a%%|*} строк"
    else printf '  %-14s DIFF   primary=%s replica=%s\n' "$t" "$a" "$b"; bad=1; fi
  done
  sql="SELECT string_agg(contype::text||'='||n, ',' ORDER BY contype) FROM (SELECT contype, count(*) n FROM pg_constraint c JOIN pg_namespace s ON s.oid=c.connamespace WHERE s.nspname='public' GROUP BY 1) q"
  a=$(P "$sql"); b=$(R "$sql")
  if [[ "$a" == "$b" && "$a" != *ERROR* ]]; then echo "  constraints    MATCH  $a"; else echo "  constraints    DIFF   primary=$a replica=$b"; bad=1; fi
  sql="SELECT (SELECT count(*) FROM order_items oi LEFT JOIN orders o USING(order_id) WHERE o.order_id IS NULL)+(SELECT count(*) FROM orders o LEFT JOIN customers c USING(customer_id) WHERE c.customer_id IS NULL)"
  a=$(P "$sql"); b=$(R "$sql")
  echo "  FK-сироты      primary=$a replica=$b (ожидается 0 и 0)"
  [[ "$a" == 0 && "$b" == 0 ]] || bad=1
  [[ $bad -eq 0 ]] && echo "  ИТОГ: целостность подтверждена" || echo "  ИТОГ: ЕСТЬ РАСХОЖДЕНИЯ"
  return $bad
}


echo "=============================================================="
echo " Эксперименты с отказами   MODE=$MODE   $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "=============================================================="
P "SELECT version()" | head -1

say "Подготовка: таблица-пробник failure_probe (пересоздаётся на primary)"
P "DROP TABLE IF EXISTS failure_probe" >/dev/null
P "CREATE TABLE failure_probe (id serial PRIMARY KEY, note text, created_at timestamptz DEFAULT now())" >/dev/null
sleep 1

say "E0. Исходное состояние"
echo "primary: pg_stat_replication = $(repl_state)"
echo "replica: walreceiver         = $(recv_state), in_recovery = $(R 'SELECT pg_is_in_recovery()')"
probe_write "baseline"; sleep 1; probe_read
integrity_check


say "E1. ОСТАНОВКА REPLICA"
T_STOP=$(now); node_stop replica
echo "replica остановлена"
probe_write "while-replica-down-1"; probe_write "while-replica-down-2"; probe_write "while-replica-down-3"
echo "primary: pg_stat_replication = $(repl_state)"
probe_read
say "E1. Запуск replica и догоняние"
T_START=$(now); node_start replica
printf 'простой replica: %.1f с\n' "$(awk "BEGIN{print $(now) - $T_STOP}")"
wait_caught_up
echo "primary: pg_stat_replication = $(repl_state)"
echo "replica: walreceiver         = $(recv_state)"
echo "-- replica, лог (последние строки):"; node_log replica 6
integrity_check


say "E2. ОСТАНОВКА PRIMARY"
probe_write "before-primary-down"; sleep 1
T_STOP=$(now); node_stop primary
echo "primary остановлена"
probe_write "while-primary-down"
probe_read
probe_write_on_replica
echo "replica: in_recovery = $(R 'SELECT pg_is_in_recovery()'), walreceiver = $(recv_state)"
echo "replica: последний применённый WAL = $(R 'SELECT pg_last_wal_replay_lsn()'), задержка применения = $(R "SELECT coalesce(now()-pg_last_xact_replay_timestamp(),'0')")"
sleep 3
echo "-- replica, лог (последние строки):"; node_log replica 6
say "E2. Запуск primary и переподключение replica"
T_UP=$(now); node_start primary
printf 'простой primary: %.1f с\n' "$(awk "BEGIN{print $(now) - $T_STOP}")"
for _ in $(seq 1 60); do [[ "$(repl_state)" == streaming/* ]] && break; sleep 0.5; done
printf 'replica снова streaming через %.1f с после старта primary\n' "$(awk "BEGIN{print $(now) - $T_UP}")"
probe_write "after-primary-up-1"; probe_write "after-primary-up-2"
wait_caught_up
integrity_check


if [[ "${RUN_FAILOVER:-0}" == 1 ]]; then
  say "E3. АВАРИЙНОЕ ПЕРЕКЛЮЧЕНИЕ: primary упал, replica повышается до primary"
  node_stop primary
  probe_write "primary-dead"
  echo "replica: pg_is_in_recovery до promote = $(R 'SELECT pg_is_in_recovery()')"
  R "SELECT pg_promote(wait => true)" | sed 's/^/pg_promote: /'
  echo "replica: pg_is_in_recovery после promote = $(R 'SELECT pg_is_in_recovery()')"
  out=$(R "INSERT INTO failure_probe(note) VALUES ('written-on-promoted') RETURNING id")
  echo "[$(ts)] запись на повышенную replica: $out"
  echo "failure_probe на повышенной replica: $(R 'SELECT count(*) FROM failure_probe')"
  echo "FK-сироты на повышенной replica: $(R "SELECT count(*) FROM order_items oi LEFT JOIN orders o USING(order_id) WHERE o.order_id IS NULL")"
  echo "ВНИМАНИЕ: старую primary нельзя запускать как есть (split-brain) — см. runbook.md, сценарий C."
fi

say "Эксперименты завершены. Сырой лог: $LOG_FILE"
