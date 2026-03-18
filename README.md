# uri_parser

Test data for validating URI parsing and normalization against [RFC 3986](https://www.rfc-editor.org/rfc/rfc3986).

## Files

### `uri_test_data.sql`

**345 test URIs** across 20+ categories designed to exercise every production in the RFC 3986 ABNF grammar:

| Category | IDs | Examples |
|---|---|---|
| Basic structure | 1–23 | HTTP, HTTPS, FTP, SSH, mailto, tel, URN, file, data, WebSocket |
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

Descriptions note RFC 3986 validity — URIs that are invalid per the ABNF (e.g., brackets in query, `#` in fragment) are explicitly marked.

### `uri_equivalence_tests.sql`

**377 test rows across 157 groups** for validating URI normalization. Each group contains URI variants that should (or should not) normalize to the same output.

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
| `protocol` | Query param ordering, plus-as-space, FQDN trailing dot, IDN/punycode, IPv4-mapped IPv6 | `http://example.com.` → `http://example.com` |

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
| Protocol-level equivalences | 240–242, 410–412, 430–431, 440–441, 480–481, 491–492 | Positive |
| Sub-delimiter encoding in path | 620–628 | Positive |
| Multiple unreserved decodings | 630–632 | Positive |
| Structural non-equivalence | 300–310, 490, 530–541, 550–558 | Negative |
| Encoding traps | 700–704 | Negative |
| RFC 3986 explicit examples | 610–611 | Positive |
| Real-world scenarios | 400–404, 600–603 | Mixed |

### `test_setup.sh`

CockroachDB test harness that:

- Starts a **single-node CockroachDB** with an in-memory store (no disk artifacts)
- Picks **random ports** (30000–39999) to avoid collisions
- Runs in **insecure mode** (no TLS)
- Creates an **isolated test database** with timestamp+PID name
- Loads both SQL files and runs **13 validation checks**
- Cleans up on exit (kills CockroachDB, removes PID file)

## Quick start

```bash
# Prerequisites: cockroach CLI (https://www.cockroachlabs.com/docs/releases)

# Run validation (starts DB, loads data, checks, shuts down)
./test_setup.sh

# Start DB and keep it running for interactive use
./test_setup.sh --keep
```

In `--keep` mode, the script prints a connection string:

```
cockroach sql --insecure --host=127.0.0.1:<port> --database=<db>
```

## Usage with a `parse_uri` function

Once you have a `parse_uri()` UDF registered in CockroachDB, you can validate it against the test data:

```sql
-- Test component extraction
SELECT id, uri, parse_uri(uri)
FROM uri_test_data
WHERE id IN (1, 7, 14, 110, 300, 1303);

-- Test positive equivalence: these MUST normalize to the same output
SELECT a.group_id, a.uri, b.uri
FROM uri_equivalence_tests a
JOIN uri_equivalence_tests b USING (group_id)
WHERE a.variant_id < b.variant_id
  AND a.is_equivalent = TRUE
  AND normalize_uri(a.uri) != normalize_uri(b.uri);
-- Expected: 0 rows

-- Test negative equivalence: these MUST NOT normalize to the same output
SELECT a.group_id, a.uri, b.uri
FROM uri_equivalence_tests a
JOIN uri_equivalence_tests b USING (group_id)
WHERE a.variant_id < b.variant_id
  AND a.is_equivalent = FALSE
  AND normalize_uri(a.uri) = normalize_uri(b.uri);
-- Expected: 0 rows

-- Filter by normalization level
SELECT a.group_id, a.uri, b.uri
FROM uri_equivalence_tests a
JOIN uri_equivalence_tests b USING (group_id)
WHERE a.variant_id < b.variant_id
  AND a.is_equivalent = TRUE
  AND a.normalization_level = 'syntax'
  AND normalize_uri(a.uri) != normalize_uri(b.uri);
-- Expected: 0 rows (syntax-level normalization only)
```

## References

- [RFC 3986 — Uniform Resource Identifier (URI): Generic Syntax](https://www.rfc-editor.org/rfc/rfc3986)
- [RFC 5952 — A Recommendation for IPv6 Address Text Representation](https://www.rfc-editor.org/rfc/rfc5952)
- [RFC 8089 — The "file" URI Scheme](https://www.rfc-editor.org/rfc/rfc8089)

## License

This project is released into the public domain under [The Unlicense](https://unlicense.org/).
