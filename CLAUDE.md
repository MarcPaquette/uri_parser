# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RFC 3986 URI parser and normalizer implemented as a pure SQL UDF (`parse_uri()`) for CockroachDB. Test data is cross-validated by three canonical parsers: C/uriparser, Python/urllib.parse, and Go/net/url.

## Key Commands

### Run UDF tests (primary test flow)
```bash
# Starts ephemeral CockroachDB, loads data + UDFs, runs ~40 validation checks, shuts down
./test_parse_uri.sh

# Keep DB running after tests for interactive SQL
./test_parse_uri.sh --keep

# Also export parse_uri() output snapshots for before/after diffing
./test_parse_uri.sh --snapshot
```
Requires: `cockroach` CLI in PATH.

### Run canonical parser validation
```bash
# Build C + Go validators, run all three parsers, produce comparison report
make test
```
Requires: `uriparser` (`brew install uriparser`), Python 3, Go 1.21+.

### Build validators only
```bash
make          # builds uriparser_test and go_uri_validator
```

### Load UDFs into an existing CockroachDB
```bash
cockroach sql --insecure --host=<host>:<port> --database=<db> < parse_uri.sql
```

## Architecture

### SQL functions (`parse_uri.sql`)
All three functions are pure `LANGUAGE SQL` (not PL/pgSQL) to avoid CockroachDB's ~300-500ms per-function compilation overhead:
- **`parse_uri(TEXT)`** — Main entry point. Returns JSONB with: `scheme`, `userinfo`, `host`, `port`, `path`, `query`, `fragment`, `authority`, `normalized_uri`. Uses CockroachDB's `INET` type for RFC 5952 IPv6 compression.
- **`_uri_pct_norm(TEXT)`** — Helper: decode unreserved percent-encoding, uppercase hex digits. Recursive CTE jumping between `%` positions.
- **`_uri_dot_norm(TEXT)`** — Helper: remove `.` and `..` path segments per RFC 3986 §5.2.4.

### Test data (SQL tables)
- **`uri_test_data.sql`** — 378 URIs across 20+ categories covering the full RFC 3986 ABNF grammar
- **`uri_equivalence_tests.sql`** — 415 rows across 173 groups for normalization equivalence (positive and negative tests at syntax/scheme/protocol levels)
- **`uri_invalid_tests.sql`** — 36 URIs that both reference parsers reject

### Test harnesses
- **`test_parse_uri.sh`** — Full UDF validation + benchmarks (sections A-J). Manages CockroachDB lifecycle (ephemeral in-memory node on random ports). Supports `--snapshot` for output comparison and `--keep` for interactive use.
- **`run_uriparser_tests.sh`** — Runs all three canonical validators against test data and produces a comparison report.
- **`test_setup.sh`** — Simpler data-only validation (13 checks, no UDF).

### Canonical validators
- **`uriparser_test.c`** — C wrapper around liburiparser for syntax-level validation
- **`python_uri_test.py`** — Python urllib.parse validator with all three RFC 3986 §6 normalization levels
- **`go_uri_validator.go`** — Go net/url validator with syntax + scheme + partial protocol normalization

## CI

GitHub Actions (`.github/workflows/pr-test.yml`) runs on PRs to `main`: spins up CockroachDB in a container, loads all three test data files, and runs 17 validation checks on data integrity (not UDF logic).

## CockroachDB-Specific Constraints

- `LANGUAGE SQL` functions are inlined with zero overhead; PL/pgSQL functions cost ~300-500ms compilation per statement. Never convert helpers to PL/pgSQL.
- CockroachDB treats regex functions as `STABLE`, so functions using them cannot be `IMMUTABLE`.
- Large PL/pgSQL function bodies (>200 lines) can hang during `CREATE FUNCTION`.
- `host(val::INET)` provides RFC 5952 IPv6 normalization for free — prefer it over manual PL/pgSQL.
