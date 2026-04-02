# uri_parser

RFC 3986 URI parser and normalizer for CockroachDB, with comprehensive test data cross-checked by three canonical parsers (C/uriparser, Python/urllib.parse, and Go/net/url).

## Install

```bash
# Prerequisites: cockroach CLI (https://www.cockroachlabs.com/docs/releases)

# Load into an existing CockroachDB database
cockroach sql --insecure --host=<host>:<port> --database=<db> < parse_uri.sql
```

This creates a single function:

**`parse_uri(TEXT)`** — Pure SQL, sub-millisecond per call. Full RFC 3986 normalization including percent-encoding decode/uppercase, dot-segment removal, IPv6 RFC 5952 compression (via INET built-in), default port removal, file-scheme handling.

Returns JSONB with keys: `scheme`, `userinfo`, `host`, `port`, `path`, `query`, `fragment`, `authority`, `normalized_uri`.

## Usage

```sql
-- Sub-millisecond per call, full RFC 3986 normalization
SELECT parse_uri('http://EXAMPLE.COM/%7Euser/a/../b?q=%31');
-- {"normalized_uri": "http://example.com/~user/b?q=1", ...}

-- Extract individual components
SELECT (parse_uri(uri))->>'host' FROM uri_test_data WHERE id = 1;

-- Bulk processing
SELECT id, uri, (parse_uri(uri))->>'normalized_uri'
FROM uri_test_data
WHERE id IN (1, 7, 14, 110, 300, 1303);
```

### Equivalence testing

```sql
-- Test positive equivalence: these MUST normalize to the same output
SELECT a.group_id, a.uri, b.uri
FROM uri_equivalence_tests a
JOIN uri_equivalence_tests b USING (group_id)
WHERE a.variant_id < b.variant_id
  AND a.is_equivalent = TRUE
  AND (parse_uri(a.uri))->>'normalized_uri' != (parse_uri(b.uri))->>'normalized_uri';
-- Expected: 0 rows

-- Test negative equivalence: these MUST NOT normalize to the same output
SELECT a.group_id, a.uri, b.uri
FROM uri_equivalence_tests a
JOIN uri_equivalence_tests b USING (group_id)
WHERE a.variant_id < b.variant_id
  AND a.is_equivalent = FALSE
  AND (parse_uri(a.uri))->>'normalized_uri' = (parse_uri(b.uri))->>'normalized_uri';
-- Expected: 0 rows

-- Filter by normalization level
SELECT a.group_id, a.uri, b.uri
FROM uri_equivalence_tests a
JOIN uri_equivalence_tests b USING (group_id)
WHERE a.variant_id < b.variant_id
  AND a.is_equivalent = TRUE
  AND a.normalization_level = 'syntax'
  AND (parse_uri(a.uri))->>'normalized_uri' != (parse_uri(b.uri))->>'normalized_uri';
-- Expected: 0 rows (syntax-level normalization only)
```

## Running tests

### UDF validation + benchmarks

```bash
# Starts CockroachDB, loads test data + UDFs, runs 40 checks, shuts down
./test_parse_uri.sh

# Keep DB running for interactive use
./test_parse_uri.sh --keep
```

### Test data validation against canonical parsers

```bash
# Prerequisites: uriparser (brew install uriparser), Python 3, Go 1.21+
make test
```

This builds the C and Go programs, runs all three validators, and produces a comparison report:

```
Both PASS:        103 groups  (test data confirmed by both canonical parsers)
Python-only PASS:  70 groups  (Python covers scheme/protocol; uriparser only does syntax)
Both FAIL:          0 groups
Disagree:           0 groups
```

## Test data

### `uri_test_data.sql`

**378 test URIs** across 20+ categories designed to exercise every production in the RFC 3986 ABNF grammar:

| Category | IDs | Examples |
|---|---|---|
| Basic structure | 1–26 | HTTP, HTTPS, FTP, SSH, mailto, tel, URN, file, data, WebSocket, Kafka, CockroachDB |
| Authority / host | 100–126 | localhost, domains, FQDN, punycode, IPv4, IPv6, IPvFuture, zone ID |
| Port | 200–208 | Default, non-standard, zero, max, empty |
| Userinfo | 300–310 | Username, password, percent-encoded, multiple colons |
| Path | 400–433 | Dot segments, double slashes, percent-encoded, semicolons, relative refs |
| Query string | 500–524 | Key-value, empty, duplicates, percent-encoded, arrays, JSON |
| Fragment | 600–612 | JSON pointer, anchors, combined with query |
| Combined complex | 700–704 | Full URIs with all components |
| Edge cases | 800–836 | Empty string, incomplete encoding, non-numeric port, raw Unicode |
| Normalization | 900–909 | Case, percent-encoding, default ports, dot segments |
| Real-world | 1000–1020 | Google, GitHub, OAuth, CDN, database connection strings, magnet, geo |
| Security | 1100–1113 | XSS, SQL injection, path traversal, authority confusion, SSRF |
| Stress tests | 1200–1204 | Long paths, many params, many subdomains |
| Additional schemes | 1300–1309 | Compound schemes (`coap+tcp`, `git+ssh`), blob, bitcoin, URN UUID |
| Additional authority | 1400–1405 | Empty host, malformed IPv6, homograph, max DNS label |
| Additional paths | 1500–1508 | Colon in relative path, OData, non-breaking space, lone `%` |
| Additional encoding | 1600–1604 | Double encoding, overlong UTF-8, invalid UTF-8 |
| Additional query | 1700–1703 | Flag-style params, deeply nested brackets, bare `#` |
| Additional security | 1800–1806 | CRLF injection, RTL override, triple encoding, jar: URIs |
| Additional structural | 1900–1905 | `?` in fragment, empty authority, degenerate query separators |
| Additional real-world | 2000–2012 | Docker, SMB, VNC, Kubernetes, Chrome extension, Android intent |
| RFC 3986 §1.1.2 | 2100–2107 | All 8 canonical examples from the RFC |
| IPv4 boundaries | 2200–2210 | All 5 `dec-octet` rules, invalid cases (>255, leading zeros, too few/many octets) |
| Scheme edge cases | 2300–2305 | Invalid starts (digit, `+`, `.`, `-`), underscore, all-valid combo |
| Minimal components | 2400–2410 | Scheme + empty path/query/fragment combinations |
| Gen-delims as data | 2500–2504 | Properly percent-encoded `[]`, `#`, `?` in path/query/fragment |
| Sub-delims in userinfo | 2600 | All 11 sub-delimiters |
| segment-nz-nc | 2700–2702 | Relative refs with `@`, `!`, colon requiring `./` prefix |
| IPv6 full forms | 2800–2805 | Fully expanded, all-zeros, zone ID, mixed groups, dual-stack |
| Kafka | 2900–2914 | Broker, topic, SASL, kafka+ssl, multi-broker, consumer config |
| CockroachDB | 2920–2934 | postgresql://, SSL modes, Cloud URLs, encoded options, IPv4/IPv6 |

Descriptions note RFC 3986 validity — URIs that are invalid per the ABNF (e.g., brackets in query, `#` in fragment) are explicitly marked.

### `uri_invalid_tests.sql`

**36 invalid URIs** where both reference parsers (C/uriparser and Python/urllib) agree the input violates RFC 3986.

**Schema:**

```sql
CREATE TABLE uri_invalid_tests (
    id              INT PRIMARY KEY,
    uri             TEXT NOT NULL,
    description     TEXT NOT NULL,
    category        TEXT NOT NULL,
    expected_reason TEXT NOT NULL
);
```

**Categories:**

| Category | IDs | Count | Examples |
|---|---|---|---|
| `incomplete-pct-encoding` | 3000–3008 | 9 | `%`, `%2`, `%ZZ`, `%G1` in path/query/fragment |
| `disallowed-char` | 3100–3114 | 15 | Spaces, `<>`, `{}`, `\|`, `\` in various positions |
| `invalid-scheme` | 3200–3206 | 7 | Digit start, `+.-_` start, empty scheme |
| `non-numeric-port` | 3300–3303 | 4 | `abc`, `8o80`, `ab80`, `80ab` |
| `unbalanced-brackets` | 3400 | 1 | Missing closing `]` |

### `uri_equivalence_tests.sql`

**415 test rows across 173 groups** for validating URI normalization. Each group contains URI variants that should (or should not) normalize to the same output.

**Schema:**

```sql
CREATE TABLE uri_equivalence_tests (
    group_id            INT NOT NULL,
    variant_id          INT NOT NULL,
    uri                 TEXT NOT NULL,
    description         TEXT NOT NULL,
    normalization_level TEXT NOT NULL,    -- 'syntax', 'scheme', or 'protocol'
    is_canonical        BOOLEAN NOT NULL, -- TRUE = preferred normalized form
    is_equivalent       BOOLEAN NOT NULL, -- TRUE = positive test, FALSE = negative test
    PRIMARY KEY (group_id, variant_id)
);
```

**Normalization levels** (per RFC 3986 Section 6):

| Level | What it covers | Example |
|---|---|---|
| `syntax` | Case normalization, percent-encoding of unreserved chars, dot-segment removal, hex digit case | `HTTP://EXAMPLE.COM/%7euser/./file` → `http://example.com/~user/file` |
| `scheme` | Default port removal, empty path → `/`, IPv6 compression, empty port removal | `http://example.com:80` → `http://example.com/` |
| `protocol` | Query param ordering, plus-as-space, FQDN trailing dot, IDN/punycode, NFC normalization | `http://example.com.` → `http://example.com` |

**Coverage:**

| Section | Groups | Tests |
|---|---|---|
| Case normalization (scheme, host, hex digits) | 1–6 | Positive |
| Percent-encoding of unreserved chars | 10–20 | Positive |
| Dot-segment removal | 30–35 | Positive |
| Default port removal | 40–46, 520–524 | Positive |
| Empty path normalization | 50–53, 660–662 | Positive |
| Empty port removal | 55–56 | Positive |
| IPv6 normalization | 60–64, 510–511, 640, 650–651 | Positive |
| Combined normalizations | 100–105, 641–643 | Positive |
| Reserved char encoding boundaries | 200–206 | Negative |
| Query/fragment/userinfo encoding | 210–212, 220–221, 230–231 | Positive |
| Protocol-level equivalences | 240–242, 410–412, 430–431, 480–481, 491–492 | Positive |
| Sub-delimiter encoding in path | 620–628 | Positive |
| Multiple unreserved decodings | 630–632 | Positive |
| Structural non-equivalence | 300–310, 490, 530–541, 550–558 | Negative |
| Encoded dot segments (§6.2.2.2 + §6.2.2.3) | 700–701 | Positive |
| Encoding traps | 702–704 | Negative |
| RFC 3986 explicit examples | 610–611 | Positive |
| Real-world scenarios | 400–404, 601–603 | Mixed |
| Kafka URIs | 710–718 | Mixed |
| CockroachDB / PostgreSQL URIs | 720–729 | Mixed |

## Other files

| File | Description |
|---|---|
| `parse_uri.sql` | All UDF definitions (`parse_uri` and pure SQL helpers `_uri_pct_norm`, `_uri_dot_norm`) |
| `test_parse_uri.sh` | Full UDF validation + benchmarks (40 checks, sections A–J) |
| `test_setup.sh` | Simpler data-only validation harness (13 checks, no UDF) |
| `uriparser_test.c` | C wrapper around [uriparser](https://uriparser.github.io/) for validity and equivalence checks |
| `python_uri_test.py` | Python `urllib.parse` validator implementing all three RFC 3986 §6 normalization levels |
| `go_uri_validator.go` | Go `net/url` validator implementing syntax, scheme, and partial protocol normalization |
| `run_uriparser_tests.sh` | Runs all three canonical validators and produces a comparison report |

## References

- [RFC 3986 — Uniform Resource Identifier (URI): Generic Syntax](https://www.rfc-editor.org/rfc/rfc3986)
- [RFC 5952 — A Recommendation for IPv6 Address Text Representation](https://www.rfc-editor.org/rfc/rfc5952)
- [RFC 8089 — The "file" URI Scheme](https://www.rfc-editor.org/rfc/rfc8089)

## License

This project is released into the public domain under [The Unlicense](https://unlicense.org/).
