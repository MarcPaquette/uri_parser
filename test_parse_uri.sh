#!/usr/bin/env bash
#
# test_parse_uri.sh -- Start CockroachDB, load test data & parse_uri() UDF,
#                      and validate the parser against uri_equivalence_tests
#                      and uri_test_data.
#
# Usage:
#   ./test_parse_uri.sh          # run all validation then shut down
#   ./test_parse_uri.sh --keep   # start DB, load data, run tests, keep DB running
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---------------------------------------------------------------------------
# Pick free ports
# ---------------------------------------------------------------------------
pick_port() {
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

PID_FILE=$(mktemp "${TMPDIR:-/tmp}/crdb-parse-uri.pid.XXXXXX")
TEST_DB="uri_parse_test_$(date +%s)_$$"
CRDB_PID=""
KEEP_RUNNING=false
[ "${1:-}" = "--keep" ] && KEEP_RUNNING=true

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
cleanup() {
  local exit_code=$?
  echo ""
  if [ -n "$CRDB_PID" ] && kill -0 "$CRDB_PID" 2>/dev/null; then
    echo "Stopping CockroachDB (PID $CRDB_PID)..."
    kill "$CRDB_PID" 2>/dev/null || true
    wait "$CRDB_PID" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
  if [ $exit_code -eq 0 ]; then echo "Done."; else echo "Exited with code $exit_code."; fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Start CockroachDB
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

sql() {
  cockroach sql --insecure --host="127.0.0.1:${SQL_PORT}" --format=tsv "$@" 2>/dev/null
}

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
# Create test database and load everything
# ---------------------------------------------------------------------------
echo ""
echo "Creating test database: $TEST_DB"
sql -e "CREATE DATABASE ${TEST_DB};"

test_sql() {
  sql --database="$TEST_DB" "$@"
}

echo ""
echo "Loading uri_test_data.sql..."
test_sql <"$SCRIPT_DIR/uri_test_data.sql"
TD_COUNT=$(test_sql -e "SELECT count(*) FROM uri_test_data;" | tail -1)
echo "  Loaded $TD_COUNT rows into uri_test_data."

echo ""
echo "Loading uri_equivalence_tests.sql..."
test_sql <"$SCRIPT_DIR/uri_equivalence_tests.sql"
EQ_COUNT=$(test_sql -e "SELECT count(*) FROM uri_equivalence_tests;" | tail -1)
echo "  Loaded $EQ_COUNT rows into uri_equivalence_tests."

echo ""
echo "Loading uri_invalid_tests.sql..."
test_sql <"$SCRIPT_DIR/uri_invalid_tests.sql"
INV_COUNT=$(test_sql -e "SELECT count(*) FROM uri_invalid_tests;" | tail -1)
echo "  Loaded $INV_COUNT rows into uri_invalid_tests."

echo ""
echo "Loading parse_uri.sql (UDF + helpers)..."
test_sql <"$SCRIPT_DIR/parse_uri.sql"
echo "  Functions created."

# ---------------------------------------------------------------------------
# Validation checks
# ---------------------------------------------------------------------------
echo ""
echo "========================================================================"
echo "  VALIDATION"
echo "========================================================================"

PASS=0
FAIL=0

check() {
  local description="$1" query="$2" expected="$3"
  local actual
  actual=$(test_sql -e "$query" 2>&1 | tail -1) || true
  if [ "$actual" = "$expected" ]; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    echo "        expected: $expected"
    echo "        got:      $actual"
    FAIL=$((FAIL + 1))
  fi
}

# -- A. Basic parsing completeness ------------------------------------------
echo ""
echo "-- A. Parse completeness ------------------------------------------------"

check "parse_uri returns JSONB for every uri_test_data row" \
  "SELECT count(*) FROM uri_test_data WHERE parse_uri(uri) IS NOT NULL OR uri = '';" \
  "$TD_COUNT"

check "parse_uri returns JSONB for every uri_equivalence_tests row" \
  "SELECT count(*) FROM uri_equivalence_tests WHERE parse_uri(uri) IS NOT NULL;" \
  "$EQ_COUNT"

# -- B. Component extraction spot-checks ------------------------------------
echo ""
echo "-- B. Component extraction -----------------------------------------------"

check "scheme extracted from http://example.com" \
  "SELECT (parse_uri('http://example.com'))->>'scheme';" \
  "http"

check "host extracted from http://user:pass@example.com:8080/path" \
  "SELECT (parse_uri('http://user:pass@example.com:8080/path'))->>'host';" \
  "example.com"

check "port extracted from http://example.com:8080/path" \
  "SELECT (parse_uri('http://example.com:8080/path'))->>'port';" \
  "8080"

check "path extracted from http://example.com/path/to/resource" \
  "SELECT (parse_uri('http://example.com/path/to/resource'))->>'path';" \
  "/path/to/resource"

check "query extracted from http://example.com/path?key=value" \
  "SELECT (parse_uri('http://example.com/path?key=value'))->>'query';" \
  "key=value"

check "fragment extracted from http://example.com/path#frag" \
  "SELECT (parse_uri('http://example.com/path#frag'))->>'fragment';" \
  "frag"

check "userinfo extracted from http://user:pass@example.com" \
  "SELECT (parse_uri('http://user:pass@example.com'))->>'userinfo';" \
  "user:pass"

check "authority assembled correctly" \
  "SELECT (parse_uri('http://user:pass@example.com:9090/p'))->>'authority';" \
  "user:pass@example.com:9090"

check "IPv6 host parsed correctly" \
  "SELECT (parse_uri('http://[::1]:8080/path'))->>'host';" \
  "[::1]"

check "mailto scheme parsed (no authority)" \
  "SELECT ((parse_uri('mailto:user@example.com'))->>'scheme') || ':' || ((parse_uri('mailto:user@example.com'))->>'path');" \
  "mailto:user@example.com"

# -- C. Syntax normalization -------------------------------------------------
echo ""
echo "-- C. Syntax normalization ------------------------------------------------"

check "scheme lowercased" \
  "SELECT (parse_uri('HTTP://EXAMPLE.COM'))->>'scheme';" \
  "http"

check "host lowercased" \
  "SELECT (parse_uri('http://EXAMPLE.COM/path'))->>'host';" \
  "example.com"

check "unreserved %7E decoded to ~" \
  "SELECT (parse_uri('http://example.com/%7Euser'))->>'path';" \
  "/~user"

check "unreserved %2D decoded to -" \
  "SELECT (parse_uri('http://example.com/a%2Db'))->>'path';" \
  "/a-b"

check "unreserved %2E decoded to ." \
  "SELECT (parse_uri('http://example.com/a%2Eb'))->>'path';" \
  "/a.b"

check "unreserved %5F decoded to _" \
  "SELECT (parse_uri('http://example.com/a%5Fb'))->>'path';" \
  "/a_b"

check "hex digits uppercased (%c3%a9 -> %C3%A9)" \
  "SELECT (parse_uri('http://example.com/%c3%a9'))->>'path';" \
  "/%C3%A9"

check "reserved %2F stays encoded" \
  "SELECT (parse_uri('http://example.com/a%2Fb'))->>'path';" \
  "/a%2Fb"

check "dot segment /a/b/../c -> /a/c" \
  "SELECT (parse_uri('http://example.com/a/b/../c'))->>'path';" \
  "/a/c"

check "dot segment /a/./b -> /a/b" \
  "SELECT (parse_uri('http://example.com/a/./b'))->>'path';" \
  "/a/b"

check "dot segment /. -> /" \
  "SELECT (parse_uri('http://example.com/.'))->>'path';" \
  "/"

check "dot segment /.. -> /" \
  "SELECT (parse_uri('http://example.com/..'))->>'path';" \
  "/"

check "encoded dot %2E%2E decoded then removed as dot segment" \
  "SELECT (parse_uri('http://example.com/a/%2E%2E/b'))->>'path';" \
  "/b"

check "empty port (colon, no digits) removed" \
  "SELECT (parse_uri('http://example.com:/path'))->>'normalized_uri';" \
  "http://example.com/path"

# -- D. Scheme-based normalization -------------------------------------------
echo ""
echo "-- D. Scheme-based normalization ------------------------------------------"

check "HTTP default port 80 removed" \
  "SELECT (parse_uri('http://example.com:80/path'))->>'port' IS NULL;" \
  "t"

check "HTTPS default port 443 removed" \
  "SELECT (parse_uri('https://example.com:443/path'))->>'port' IS NULL;" \
  "t"

check "FTP default port 21 removed" \
  "SELECT (parse_uri('ftp://example.com:21/path'))->>'port' IS NULL;" \
  "t"

check "Kafka default port 9092 removed" \
  "SELECT (parse_uri('kafka://broker.example.com:9092/topic'))->>'port' IS NULL;" \
  "t"

check "PostgreSQL default port 5432 removed" \
  "SELECT (parse_uri('postgresql://root@localhost:5432/db'))->>'port' IS NULL;" \
  "t"

check "non-default port 8080 preserved" \
  "SELECT (parse_uri('http://example.com:8080/path'))->>'port';" \
  "8080"

check "leading-zero port 08080 normalized to 8080" \
  "SELECT (parse_uri('http://example.com:08080/path'))->>'port';" \
  "8080"

check "leading-zero default port 080 removed" \
  "SELECT (parse_uri('http://example.com:080/path'))->>'port' IS NULL;" \
  "t"

check "empty path -> / for authority URI" \
  "SELECT (parse_uri('http://example.com'))->>'path';" \
  "/"

check "RFC 3986 6.2.3 four equivalent HTTP URIs" \
  "SELECT count(DISTINCT (parse_uri(uri))->>'normalized_uri') FROM (VALUES ('http://example.com'), ('http://example.com/'), ('http://example.com:/'), ('http://example.com:80/')) AS t(uri);" \
  "1"

# -- E. Equivalence tests (syntax level) ------------------------------------
echo ""
echo "-- E. Equivalence tests (syntax level) -----------------------------------"

SYNTAX_TOTAL=$(test_sql -e "SELECT count(DISTINCT group_id) FROM uri_equivalence_tests WHERE normalization_level = 'syntax' AND is_equivalent = TRUE;" | tail -1)

check "Syntax-level positive groups: all variants normalize to same URI (0 failures)" \
  "SELECT count(*) FROM (SELECT group_id FROM uri_equivalence_tests WHERE normalization_level = 'syntax' AND is_equivalent = TRUE GROUP BY group_id HAVING count(DISTINCT (parse_uri(uri))->>'normalized_uri') > 1) sub;" \
  "0"

echo "        ($SYNTAX_TOTAL syntax-level positive groups tested)"

# -- F. Equivalence tests (scheme level) ------------------------------------
echo ""
echo "-- F. Equivalence tests (scheme level) -----------------------------------"

SCHEME_TOTAL=$(test_sql -e "SELECT count(DISTINCT group_id) FROM uri_equivalence_tests WHERE normalization_level = 'scheme' AND is_equivalent = TRUE;" | tail -1)

check "Scheme-level positive groups: all variants normalize to same URI (0 failures)" \
  "SELECT count(*) FROM (SELECT group_id FROM uri_equivalence_tests WHERE normalization_level = 'scheme' AND is_equivalent = TRUE GROUP BY group_id HAVING count(DISTINCT (parse_uri(uri))->>'normalized_uri') > 1) sub;" \
  "0"

echo "        ($SCHEME_TOTAL scheme-level positive groups tested)"

# -- G. Negative equivalence tests ------------------------------------------
echo ""
echo "-- G. Negative equivalence tests (syntax + scheme) -----------------------"

NEG_TOTAL=$(test_sql -e "SELECT count(DISTINCT group_id) FROM uri_equivalence_tests WHERE is_equivalent = FALSE AND normalization_level IN ('syntax','scheme');" | tail -1)

check "Negative groups: non-equivalent URIs stay different (0 false matches)" \
  "SELECT count(*) FROM (SELECT group_id FROM uri_equivalence_tests WHERE is_equivalent = FALSE AND normalization_level IN ('syntax','scheme') GROUP BY group_id HAVING count(DISTINCT (parse_uri(uri))->>'normalized_uri') = 1) sub;" \
  "0"

echo "        ($NEG_TOTAL negative groups tested)"

# -- H2. Invalid URI handling ------------------------------------------------
echo ""
echo "-- H2. Invalid URI handling -----------------------------------------------"

check "parse_uri handles every uri_invalid_tests row without crashing" \
  "SELECT count(*) FROM uri_invalid_tests WHERE parse_uri(uri) IS NOT NULL OR uri = '';" \
  "$INV_COUNT"

echo "        ($INV_COUNT invalid URIs tested for crash protection)"

# -- H. Protocol-level info (not implemented) --------------------------------
echo ""
echo "-- H. Protocol-level tests (informational) -------------------------------"

PROTO_TOTAL=$(test_sql -e "SELECT count(DISTINCT group_id) FROM uri_equivalence_tests WHERE normalization_level = 'protocol';" | tail -1)
PROTO_PASS=$(test_sql -e "SELECT count(*) FROM (SELECT group_id FROM uri_equivalence_tests WHERE normalization_level = 'protocol' AND is_equivalent = TRUE GROUP BY group_id HAVING count(DISTINCT (parse_uri(uri))->>'normalized_uri') = 1) sub;" | tail -1)
echo "  INFO: $PROTO_PASS / $PROTO_TOTAL protocol-level groups happen to pass"
echo "        (protocol-level normalization is not implemented)"

# -- I. Performance benchmarks -----------------------------------------------
echo ""
echo "-- I. Performance benchmarks ----------------------------------------------"

BENCH_ITERS=100

# Batch benchmark: parse_uri() across all uri_test_data rows
echo ""
echo "  parse_uri() x $TD_COUNT URIs x $BENCH_ITERS iterations:"
BENCH_RESULT=$(test_sql -e "
  SELECT count(*) AS calls,
         round(extract(epoch FROM (clock_timestamp() - statement_timestamp())) * 1000)::INT AS ms
  FROM generate_series(1, $BENCH_ITERS) g, uri_test_data t
  WHERE parse_uri(t.uri) IS NOT NULL;" | tail -1)
BENCH_CALLS=$(echo "$BENCH_RESULT" | cut -f1)
BENCH_MS=$(echo "$BENCH_RESULT" | cut -f2)
PER_CALL=$(echo "$BENCH_CALLS $BENCH_MS" | awk '{if($1>0) printf "%.1f", $2/$1*1000; else print "N/A"}')
echo "    ${BENCH_CALLS} calls in ${BENCH_MS}ms (${PER_CALL} µs/call)"

# Batch benchmark: parse_uri() across all uri_equivalence_tests rows
echo ""
echo "  parse_uri() x $EQ_COUNT equivalence URIs x $BENCH_ITERS iterations:"
BENCH_RESULT2=$(test_sql -e "
  SELECT count(*) AS calls,
         round(extract(epoch FROM (clock_timestamp() - statement_timestamp())) * 1000)::INT AS ms
  FROM generate_series(1, $BENCH_ITERS) g, uri_equivalence_tests t
  WHERE parse_uri(t.uri) IS NOT NULL;" | tail -1)
BENCH_CALLS2=$(echo "$BENCH_RESULT2" | cut -f1)
BENCH_MS2=$(echo "$BENCH_RESULT2" | cut -f2)
PER_CALL2=$(echo "$BENCH_CALLS2 $BENCH_MS2" | awk '{if($1>0) printf "%.1f", $2/$1*1000; else print "N/A"}')
echo "    ${BENCH_CALLS2} calls in ${BENCH_MS2}ms (${PER_CALL2} µs/call)"

# Per-URI-type latency
BENCH_SINGLE=1000
echo ""
echo "  Per-URI-type latency ($BENCH_SINGLE iterations each):"
for BENCH_PAIR in \
  "simple_http|http://example.com/path?q=1#frag" \
  "complex_auth|http://user:pass@example.com:8080/a/b/c?x=1&y=2#s" \
  "ipv6|http://[2001:db8::1]:8080/path" \
  "pct_encoded|http://example.com/%7Euser/%C3%A9?q=%20" \
  "dot_segments|http://example.com/a/b/../c/./d" \
  "mailto|mailto:user@example.com" \
; do
  BENCH_LABEL="${BENCH_PAIR%%|*}"
  BENCH_URI="${BENCH_PAIR#*|}"
  BENCH_URI_ESC=$(echo "$BENCH_URI" | sed "s/'/''/g")
  BENCH_US=$(test_sql -e "
    WITH inputs AS (
      SELECT '${BENCH_URI_ESC}'::TEXT AS uri FROM generate_series(1, $BENCH_SINGLE)
    )
    SELECT round(extract(epoch FROM (clock_timestamp() - statement_timestamp())) * 1000000 / $BENCH_SINGLE)::INT
    FROM inputs WHERE parse_uri(uri) IS NOT NULL HAVING count(*) > 0;" | tail -1)
  printf "    %-16s %6s µs/call\n" "$BENCH_LABEL" "$BENCH_US"
done

# ---------------------------------------------------------------------------
# Show details for any failures
# ---------------------------------------------------------------------------
if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "========================================================================"
  echo "  FAILURE DETAILS"
  echo "========================================================================"

  echo ""
  echo "-- Syntax-level failures -----------------------------------------------"
  test_sql -e "
    SELECT e.group_id, e.variant_id, e.uri,
           (parse_uri(e.uri))->>'normalized_uri' AS normalized
    FROM uri_equivalence_tests e
    JOIN (
      SELECT group_id
      FROM uri_equivalence_tests
      WHERE normalization_level = 'syntax' AND is_equivalent = TRUE
      GROUP BY group_id
      HAVING count(DISTINCT (parse_uri(uri))->>'normalized_uri') > 1
    ) f ON e.group_id = f.group_id
    ORDER BY e.group_id, e.variant_id;" 2>/dev/null || true

  echo ""
  echo "-- Scheme-level failures -----------------------------------------------"
  test_sql -e "
    SELECT e.group_id, e.variant_id, e.uri,
           (parse_uri(e.uri))->>'normalized_uri' AS normalized
    FROM uri_equivalence_tests e
    JOIN (
      SELECT group_id
      FROM uri_equivalence_tests
      WHERE normalization_level = 'scheme' AND is_equivalent = TRUE
      GROUP BY group_id
      HAVING count(DISTINCT (parse_uri(uri))->>'normalized_uri') > 1
    ) f ON e.group_id = f.group_id
    ORDER BY e.group_id, e.variant_id;" 2>/dev/null || true

  echo ""
  echo "-- Negative test failures (false equivalences) -------------------------"
  test_sql -e "
    SELECT e.group_id, e.variant_id, e.uri,
           (parse_uri(e.uri))->>'normalized_uri' AS normalized
    FROM uri_equivalence_tests e
    JOIN (
      SELECT group_id
      FROM uri_equivalence_tests
      WHERE is_equivalent = FALSE AND normalization_level IN ('syntax','scheme')
      GROUP BY group_id
      HAVING count(DISTINCT (parse_uri(uri))->>'normalized_uri') = 1
    ) f ON e.group_id = f.group_id
    ORDER BY e.group_id, e.variant_id;" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "========================================================================"
echo "  RESULTS: $PASS passed, $FAIL failed out of $((PASS + FAIL)) checks"
echo "========================================================================"

# ---------------------------------------------------------------------------
# --keep mode
# ---------------------------------------------------------------------------
if [ "$KEEP_RUNNING" = true ]; then
  echo ""
  echo "CockroachDB is running. Connect with:"
  echo ""
  echo "  cockroach sql --insecure --host=127.0.0.1:${SQL_PORT} --database=${TEST_DB}"
  echo ""
  echo "  # Or with a connection string:"
  echo "  postgresql://root@127.0.0.1:${SQL_PORT}/${TEST_DB}?sslmode=disable"
  echo ""
  echo "  # Try: SELECT * FROM parse_uri('http://example.com/path?q=1#frag');"
  echo ""
  echo "Press Ctrl+C to stop and clean up."
  while true; do sleep 60; done
fi

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
echo ""
echo "Dropping test database: $TEST_DB"
sql -e "DROP DATABASE ${TEST_DB} CASCADE;" 2>/dev/null || true

exit $FAIL
