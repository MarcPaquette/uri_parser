#!/usr/bin/env bash
#
# test_setup.sh — Start a temporary CockroachDB instance, load URI test data,
#                 validate it, and clean up on exit.
#
# Usage:
#   ./test_setup.sh          # run validation then shut down
#   ./test_setup.sh --keep   # start DB, load data, print connection info, wait
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---------------------------------------------------------------------------
# Pick ports that avoid collisions with default CockroachDB (26257/8080)
# and other common services. Use a hash of PID + timestamp for determinism
# within a run but variance across runs.
# ---------------------------------------------------------------------------
pick_port() {
  # Find a free port in the 30000-39999 range
  local port
  for _ in $(seq 1 20); do
    port=$((30000 + RANDOM % 10000))
    if ! lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
      echo "$port"
      return 0
    fi
  done
  echo "ERROR: could not find a free port" >&2
  return 1
}

SQL_PORT=$(pick_port)
HTTP_PORT=$(pick_port)
while [ "$HTTP_PORT" = "$SQL_PORT" ]; do
  HTTP_PORT=$(pick_port)
done

PID_FILE=$(mktemp "${TMPDIR:-/tmp}/crdb-uri-test.pid.XXXXXX")
TEST_DB="uri_test_$(date +%s)_$$"
CRDB_PID=""
KEEP_RUNNING=false

if [[ "${1:-}" == "--keep" ]]; then
  KEEP_RUNNING=true
fi

# ---------------------------------------------------------------------------
# Cleanup: kill CockroachDB and remove temp store on exit
# ---------------------------------------------------------------------------
cleanup() {
  local exit_code=$?
  echo ""
  if [ -n "$CRDB_PID" ] && kill -0 "$CRDB_PID" 2>/dev/null; then
    echo "Stopping CockroachDB (PID $CRDB_PID)..."
    kill "$CRDB_PID" 2>/dev/null || true
    wait "$CRDB_PID" 2>/dev/null || true
  fi
  if [ -f "$PID_FILE" ]; then
    rm "$PID_FILE"
  fi
  if [ $exit_code -eq 0 ]; then
    echo "Done."
  else
    echo "Exited with code $exit_code."
  fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Start CockroachDB single-node in the background
# ---------------------------------------------------------------------------
echo "Starting CockroachDB single-node (in-memory store)..."
echo "  SQL port:  $SQL_PORT"
echo "  HTTP port: $HTTP_PORT"

cockroach start-single-node \
  --insecure \
  --store=type=mem,size=640MiB \
  --listen-addr="127.0.0.1:${SQL_PORT}" \
  --http-addr="127.0.0.1:${HTTP_PORT}" \
  --background \
  --pid-file="$PID_FILE" \
  >/dev/null 2>&1

CRDB_PID=$(cat "$PID_FILE")
echo "  PID:       $CRDB_PID"

# Helper to run SQL against our instance
sql() {
  cockroach sql --insecure --host="127.0.0.1:${SQL_PORT}" --format=tsv "$@" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Wait for the node to be ready
# ---------------------------------------------------------------------------
echo ""
echo "Waiting for CockroachDB to be ready..."
for i in $(seq 1 30); do
  if sql -e "SELECT 1" >/dev/null 2>&1; then
    echo "  Ready after ${i}s."
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "ERROR: CockroachDB did not become ready in 30s" >&2
    exit 1
  fi
  sleep 1
done

# ---------------------------------------------------------------------------
# Create isolated test database
# ---------------------------------------------------------------------------
echo ""
echo "Creating test database: $TEST_DB"
sql -e "CREATE DATABASE ${TEST_DB};"

# Helper to run SQL in the test database
test_sql() {
  sql --database="$TEST_DB" "$@"
}

# ---------------------------------------------------------------------------
# Load test data files
# ---------------------------------------------------------------------------
echo ""
echo "Loading uri_test_data.sql..."
test_sql <"$SCRIPT_DIR/uri_test_data.sql"
TEST_DATA_COUNT=$(test_sql -e "SELECT count(*) FROM uri_test_data;" | tail -1)
echo "  Loaded $TEST_DATA_COUNT rows into uri_test_data."

echo ""
echo "Loading uri_equivalence_tests.sql..."
test_sql <"$SCRIPT_DIR/uri_equivalence_tests.sql"
EQUIV_COUNT=$(test_sql -e "SELECT count(*) FROM uri_equivalence_tests;" | tail -1)
echo "  Loaded $EQUIV_COUNT rows into uri_equivalence_tests."

# ---------------------------------------------------------------------------
# Validate: run basic integrity checks
# ---------------------------------------------------------------------------
echo ""
echo "Running validation checks..."
PASS=0
FAIL=0

check() {
  local description="$1"
  local query="$2"
  local expected="$3"

  local actual
  actual=$(test_sql -e "$query" | tail -1)
  if [ "$actual" = "$expected" ]; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description (expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

# -- uri_test_data checks --
check "uri_test_data has rows" \
  "SELECT count(*) > 0 FROM uri_test_data;" \
  "t"

check "uri_test_data IDs are unique" \
  "SELECT count(*) = count(DISTINCT id) FROM uri_test_data;" \
  "t"

check "uri_test_data has no NULL URIs" \
  "SELECT count(*) FROM uri_test_data WHERE uri IS NULL;" \
  "0"

check "uri_test_data has no NULL descriptions" \
  "SELECT count(*) FROM uri_test_data WHERE description IS NULL;" \
  "0"

# -- uri_equivalence_tests checks --
check "uri_equivalence_tests has rows" \
  "SELECT count(*) > 0 FROM uri_equivalence_tests;" \
  "t"

check "uri_equivalence_tests PKs are unique" \
  "SELECT count(*) = count(DISTINCT (group_id, variant_id)) FROM uri_equivalence_tests;" \
  "t"

check "Every equivalence group has at least 2 variants" \
  "SELECT count(*) FROM (SELECT group_id FROM uri_equivalence_tests GROUP BY group_id HAVING count(*) < 2);" \
  "0"

check "Every equivalence group has exactly one canonical variant" \
  "SELECT count(*) FROM (SELECT group_id FROM uri_equivalence_tests WHERE is_canonical = true GROUP BY group_id HAVING count(*) != 1);" \
  "0"

check "normalization_level values are valid" \
  "SELECT count(*) FROM uri_equivalence_tests WHERE normalization_level NOT IN ('syntax', 'scheme', 'protocol');" \
  "0"

check "Positive groups (is_equivalent=true) exist" \
  "SELECT count(DISTINCT group_id) > 0 FROM uri_equivalence_tests WHERE is_equivalent = true;" \
  "t"

check "Negative groups (is_equivalent=false) exist" \
  "SELECT count(DISTINCT group_id) > 0 FROM uri_equivalence_tests WHERE is_equivalent = false;" \
  "t"

check "No equivalence group mixes is_equivalent values" \
  "SELECT count(*) FROM (SELECT group_id FROM uri_equivalence_tests GROUP BY group_id HAVING count(DISTINCT is_equivalent) > 1);" \
  "0"

# -- Cross-file sanity --
check "Stress test URIs with REPEAT() loaded correctly" \
  "SELECT length(uri) > 100 FROM uri_test_data WHERE id = 1200;" \
  "t"

echo ""
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL)) checks."

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Some checks failed. See output above."
fi

# ---------------------------------------------------------------------------
# --keep mode: print connection info and wait
# ---------------------------------------------------------------------------
if [ "$KEEP_RUNNING" = true ]; then
  echo ""
  echo "================================================================"
  echo "CockroachDB is running. Connect with:"
  echo ""
  echo "  cockroach sql --insecure --host=127.0.0.1:${SQL_PORT} --database=${TEST_DB}"
  echo ""
  echo "  # Or with a connection string:"
  echo "  postgresql://root@127.0.0.1:${SQL_PORT}/${TEST_DB}?sslmode=disable"
  echo ""
  echo "Admin UI: http://127.0.0.1:${HTTP_PORT}"
  echo "================================================================"
  echo ""
  echo "Press Ctrl+C to stop and clean up."
  # Wait until interrupted
  while true; do sleep 60; done
fi

# ---------------------------------------------------------------------------
# Cleanup: drop test database (belt-and-suspenders before trap drops everything)
# ---------------------------------------------------------------------------
echo ""
echo "Dropping test database: $TEST_DB"
sql -e "DROP DATABASE ${TEST_DB} CASCADE;" 2>/dev/null || true

exit $FAIL
