#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# ── Build ────────────────────────────────────────────────────────────
echo "=== Building uriparser_test ==="
make -s

# ── Extract URIs from uri_test_data.sql ──────────────────────────────
echo ""
echo "=== Extracting test data ==="

extract_parse_data() {
    local sql_file="$SCRIPT_DIR/uri_test_data.sql"
    local count=0

    while IFS= read -r line; do
        # Skip REPEAT lines (handled separately below).
        if echo "$line" | grep -q 'REPEAT'; then
            continue
        fi

        if echo "$line" | grep -qE '^\([0-9]+,'; then
            local id uri
            id=$(echo "$line" | sed -E "s/^\(([0-9]+),.*/\1/")

            # Handle empty string: (800, '', ...)
            if echo "$line" | grep -qE "^\\($id, *''," ; then
                uri=""
            else
                uri=$(echo "$line" | sed -E "s/^\\($id, *'//; s/', *'[^']*'\\).*//")
                # Un-escape SQL escaped quotes: '' -> '
                uri=$(echo "$uri" | sed "s/''/'/g")
            fi

            printf '%s\t%s\n' "$id" "$uri"
            ((count++))
        fi
    done < "$sql_file"

    # Handle REPEAT expressions.
    printf '%s\t%s\n' "1200" "http://example.com/$(printf 'a%.0s' $(seq 1 2000))"
    ((count++))
    printf '%s\t%s\n' "1201" "http://example.com/path?$(printf 'key=value&%.0s' $(seq 1 200) | sed 's/&$//')"
    ((count++))
    printf '%s\t%s\n' "1202" "http://$(printf 'sub.%.0s' $(seq 1 50))example.com"
    ((count++))
    printf '%s\t%s\n' "1203" "http://example.com/path#$(printf 'f%.0s' $(seq 1 1000))"
    ((count++))
    printf '%s\t%s\n' "1204" "http://example.com/$(printf 'a/%.0s' $(seq 1 100) | sed 's|/$||')"
    ((count++))

    echo "  Extracted $count URIs" >&2
}

extract_equiv_data() {
    local sql_file="$SCRIPT_DIR/uri_equivalence_tests.sql"
    local count=0

    while IFS= read -r line; do
        if echo "$line" | grep -qE '^\([0-9]+, *[0-9]+,'; then
            local group_id variant_id uri norm_level is_canonical is_equivalent

            group_id=$(echo "$line" | sed -E "s/^\(([0-9]+),.*/\1/")
            variant_id=$(echo "$line" | sed -E "s/^\([0-9]+, *([0-9]+),.*/\1/")

            uri=$(echo "$line" | sed -E "s/^\([0-9]+, *[0-9]+, *'//; s/', *'[^']*', *'[^']*',.*//" )

            norm_level=$(echo "$line" | sed -E "s/.*', *'([^']+)', *(TRUE|FALSE), *(TRUE|FALSE)\).*/\1/")

            is_canonical=$(echo "$line" | sed -E "s/.*', *(TRUE|FALSE), *(TRUE|FALSE)\).*/\1/")
            is_equivalent=$(echo "$line" | sed -E "s/.*', *(TRUE|FALSE), *(TRUE|FALSE)\).*/\2/")

            [[ "$is_canonical" == "TRUE" ]] && is_canonical=1 || is_canonical=0
            [[ "$is_equivalent" == "TRUE" ]] && is_equivalent=1 || is_equivalent=0

            printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
                "$group_id" "$variant_id" "$uri" "$norm_level" "$is_canonical" "$is_equivalent"
            ((count++))
        fi
    done < "$sql_file"

    echo "  Extracted $count equivalence rows" >&2
}

extract_invalid_data() {
    local sql_file="$SCRIPT_DIR/uri_invalid_tests.sql"
    local count=0

    while IFS= read -r line; do
        if echo "$line" | grep -qE '^\([0-9]+,'; then
            local id uri
            id=$(echo "$line" | sed -E "s/^\(([0-9]+),.*/\1/")
            uri=$(echo "$line" | sed -E "s/^\\($id, *'//; s/', *'[^']*', *'[^']*', *'[^']*'\\).*//")
            uri=$(echo "$uri" | sed "s/''/'/g")
            printf '%s\t%s\n' "$id" "$uri"
            ((count++))
        fi
    done < "$sql_file"

    echo "  Extracted $count invalid URIs" >&2
}

PARSE_DATA=$(extract_parse_data)
EQUIV_DATA=$(extract_equiv_data)
INVALID_DATA=$(extract_invalid_data)

# ── Run both parsers on parse data ───────────────────────────────────
echo ""
echo "=== uriparser: Parse ==="
C_PARSE=$(echo "$PARSE_DATA" | ./uriparser_test --parse || true)
echo "$C_PARSE"

echo ""
echo "=== Python urllib.parse: Parse ==="
PY_PARSE=$(echo "$PARSE_DATA" | python3 python_uri_test.py --parse || true)
echo "$PY_PARSE"

# ── Run both parsers on invalid URI data ─────────────────────────────
echo ""
echo "=== uriparser: Invalid URIs ==="
C_INVALID=$(echo "$INVALID_DATA" | ./uriparser_test --parse || true)
echo "$C_INVALID"

echo ""
echo "=== Python urllib.parse: Invalid URIs ==="
PY_INVALID=$(echo "$INVALID_DATA" | python3 python_uri_test.py --parse || true)
echo "$PY_INVALID"

# ── Run both parsers on equivalence data ─────────────────────────────
echo ""
echo "=== uriparser: Equivalence ==="
C_EQUIV=$(echo "$EQUIV_DATA" | ./uriparser_test --equiv || true)
echo "$C_EQUIV"

echo ""
echo "=== Python urllib.parse: Equivalence ==="
PY_EQUIV=$(echo "$EQUIV_DATA" | python3 python_uri_test.py --equiv || true)
echo "$PY_EQUIV"

# ── Comparison Report ────────────────────────────────────────────────
echo ""
echo "============================================================="
echo "                    COMPARISON REPORT"
echo "============================================================="

# ── Parse comparison ─────────────────────────────────────────────────
echo ""
echo "=== Parse Comparison ==="

# Extract "ID STATUS" from each parser (sort -k1,1 for join compatibility)
echo "$C_PARSE"  | grep '^PARSE' | awk '{gsub(/\t.*/, "", $3); print $3, $2}' | sort -k1,1 > "$TMPDIR/c_parse.txt"
echo "$PY_PARSE" | grep '^PARSE' | awk '{gsub(/\t.*/, "", $3); print $3, $2}' | sort -k1,1 > "$TMPDIR/py_parse.txt"

join "$TMPDIR/c_parse.txt" "$TMPDIR/py_parse.txt" 2>/dev/null | awk '
{
    if ($2 == $3) agree++
    else {
        disagree++
        print "  DISAGREE id=" $1 "  uriparser=" $2 "  python=" $3
    }
}
END {
    print ""
    print "Parse agreement: " agree+0 " URIs agree, " disagree+0 " disagree"
}'

# ── Equivalence comparison ───────────────────────────────────────────
# ── Invalid URI comparison ────────────────────────────────────────────
echo ""
echo "=== Invalid URI Comparison ==="

echo "$C_INVALID"  | grep '^PARSE' | awk '{gsub(/\t.*/, "", $3); print $3, $2}' | sort -k1,1 > "$TMPDIR/c_invalid.txt"
echo "$PY_INVALID" | grep '^PARSE' | awk '{gsub(/\t.*/, "", $3); print $3, $2}' | sort -k1,1 > "$TMPDIR/py_invalid.txt"

join "$TMPDIR/c_invalid.txt" "$TMPDIR/py_invalid.txt" 2>/dev/null | awk '
{
    if ($2 == "FAIL" && $3 == "FAIL") both_fail++
    else {
        problem++
        print "  PROBLEM id=" $1 "  uriparser=" $2 "  python=" $3 "  (expected both FAIL)"
    }
}
END {
    print ""
    print "Invalid URIs: " both_fail+0 " both reject, " problem+0 " unexpected accepts"
}'

echo ""
echo "=== Equivalence Comparison ==="

# Extract "group_id PASS|FAIL" from each parser
echo "$C_EQUIV"  | grep '^EQUIV' | sed -E 's/^EQUIV (PASS|FAIL)  group=([0-9]+).*/\2 \1/' | sort -k1,1 > "$TMPDIR/c_equiv.txt"
echo "$PY_EQUIV" | grep '^EQUIV' | sed -E 's/^EQUIV (PASS|FAIL)  group=([0-9]+).*/\2 \1/' | sort -k1,1 > "$TMPDIR/py_equiv.txt"

join "$TMPDIR/c_equiv.txt" "$TMPDIR/py_equiv.txt" 2>/dev/null | awk '
{
    if ($2 == "PASS" && $3 == "PASS") { both_pass++; bp[both_pass] = $1 }
    else if ($2 == "FAIL" && $3 == "PASS") { py_only++; po[py_only] = $1 }
    else if ($2 == "FAIL" && $3 == "FAIL") { both_fail++; bf[both_fail] = $1 }
    else if ($2 == "PASS" && $3 == "FAIL") {
        disagree++
        print "  DISAGREE group=" $1 "  uriparser=PASS  python=FAIL"
    }
}
END {
    print ""
    print "Both PASS:        " both_pass+0 " groups  (test data confirmed by both canonical parsers)"
    print "Python-only PASS: " py_only+0 " groups  (Python covers scheme/protocol; uriparser only does syntax)"
    print "Both FAIL:        " both_fail+0 " groups  (limitations — investigate test data)"
    print "Disagree:         " disagree+0 " groups  (investigate — one parser says test data is wrong)"

    if (both_fail > 0) {
        printf "\n  Both-FAIL groups: "
        for (i = 1; i <= both_fail; i++) printf "%s ", bf[i]
        print ""
    }
    if (disagree > 0) {
        print "\n  *** Groups where parsers disagree need investigation ***"
    }
}'

echo ""
echo "=== Done ==="
