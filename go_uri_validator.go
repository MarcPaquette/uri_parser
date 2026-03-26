package main

import (
	"bufio"
	"fmt"
	"net/netip"
	"net/url"
	"os"
	"sort"
	"strconv"
	"strings"
)

const unreserved = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
const hexDigits = "0123456789ABCDEFabcdef"
const subdelimsPchar = "!$&'()*+,;=:@"

var defaultPorts = map[string]int{
	"http": 80, "https": 443, "ftp": 21, "ftps": 990,
	"ssh": 22, "telnet": 23, "ws": 80, "wss": 443,
	"ldap": 389, "ldaps": 636, "mysql": 3306, "postgres": 5432,
	"redis": 6379, "mongodb": 27017, "kafka": 9092, "postgresql": 5432,
}

// ── Helpers ──────────────────────────────────────────────────────────

func isHexDigit(c byte) bool {
	return strings.IndexByte(hexDigits, c) >= 0
}

func isUnreserved(c byte) bool {
	return strings.IndexByte(unreserved, c) >= 0
}

func isSchemeChar(c byte) bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
		(c >= '0' && c <= '9') || c == '+' || c == '-' || c == '.'
}

// pctNormalize decodes unreserved percent-encoded chars and uppercases hex digits.
func pctNormalize(s string) string {
	var b strings.Builder
	b.Grow(len(s))
	for i := 0; i < len(s); i++ {
		if s[i] == '%' && i+2 < len(s) && isHexDigit(s[i+1]) && isHexDigit(s[i+2]) {
			val, _ := strconv.ParseUint(s[i+1:i+3], 16, 8)
			ch := byte(val)
			if isUnreserved(ch) {
				b.WriteByte(ch)
			} else {
				fmt.Fprintf(&b, "%%%02X", val)
			}
			i += 2
		} else {
			b.WriteByte(s[i])
		}
	}
	return b.String()
}

// removeDotSegments implements RFC 3986 §5.2.4.
func removeDotSegments(path string) string {
	inp := path
	var out []string
	for len(inp) > 0 {
		if strings.HasPrefix(inp, "../") {
			inp = inp[3:]
		} else if strings.HasPrefix(inp, "./") {
			inp = inp[2:]
		} else if strings.HasPrefix(inp, "/./") {
			inp = "/" + inp[3:]
		} else if inp == "/." {
			inp = "/"
		} else if strings.HasPrefix(inp, "/../") {
			inp = "/" + inp[4:]
			if len(out) > 0 {
				out = out[:len(out)-1]
			}
		} else if inp == "/.." {
			inp = "/"
			if len(out) > 0 {
				out = out[:len(out)-1]
			}
		} else if inp == "." || inp == ".." {
			inp = ""
		} else {
			if inp[0] == '/' {
				idx := strings.Index(inp[1:], "/")
				if idx == -1 {
					out = append(out, inp)
					inp = ""
				} else {
					out = append(out, inp[:idx+1])
					inp = inp[idx+1:]
				}
			} else {
				idx := strings.Index(inp, "/")
				if idx == -1 {
					out = append(out, inp)
					inp = ""
				} else {
					out = append(out, inp[:idx])
					inp = inp[idx:]
				}
			}
		}
	}
	return strings.Join(out, "")
}

// splitNetloc splits netloc into (userinfo, host, portStr).
func splitNetloc(netloc string) (string, string, string) {
	if netloc == "" {
		return "", "", ""
	}
	userinfo := ""
	rest := netloc
	if at := strings.LastIndex(netloc, "@"); at >= 0 {
		userinfo = netloc[:at]
		rest = netloc[at+1:]
	}
	if strings.HasPrefix(rest, "[") {
		bracket := strings.Index(rest, "]")
		if bracket >= 0 {
			return userinfo, rest[:bracket+1], rest[bracket+1:]
		}
		return userinfo, rest, ""
	}
	if colon := strings.LastIndex(rest, ":"); colon >= 0 {
		return userinfo, rest[:colon], rest[colon:]
	}
	return userinfo, rest, ""
}

// detectMarkers finds whether ? and # are present in the URI.
func detectMarkers(uri string) (hasQuery, hasFragment bool) {
	h := strings.Index(uri, "#")
	q := strings.Index(uri, "?")
	hasQuery = q >= 0 && (h < 0 || q < h)
	hasFragment = h >= 0
	return
}

// hasAuthority checks if URI has // after scheme:.
func hasAuthority(uri string, schemeLen int) bool {
	pos := schemeLen + 1
	return pos+1 < len(uri) && uri[pos:pos+2] == "//"
}

// extractNetloc extracts the netloc from a URI that has authority.
func extractNetloc(uri string, schemeLen int) string {
	start := schemeLen + 3 // skip "://"
	rest := uri[start:]
	// netloc ends at /, ?, or #
	end := len(rest)
	for i, c := range rest {
		if c == '/' || c == '?' || c == '#' {
			end = i
			break
		}
	}
	return rest[:end]
}

// extractPath extracts the path from a URI that has authority.
func extractPath(uri string, schemeLen int, netloc string) string {
	start := schemeLen + 3 + len(netloc) // skip "://" + netloc
	rest := uri[start:]
	end := len(rest)
	for i, c := range rest {
		if c == '?' || c == '#' {
			end = i
			break
		}
	}
	return rest[:end]
}

// extractQuery extracts the query string (without ?) from URI.
func extractQuery(uri string) string {
	h := strings.Index(uri, "#")
	q := strings.Index(uri, "?")
	if q < 0 || (h >= 0 && q > h) {
		return ""
	}
	after := uri[q+1:]
	if h2 := strings.Index(after, "#"); h2 >= 0 {
		return after[:h2]
	}
	return after
}

// extractFragment extracts the fragment (without #) from URI.
func extractFragment(uri string) string {
	h := strings.Index(uri, "#")
	if h < 0 {
		return ""
	}
	return uri[h+1:]
}

func reconstruct(scheme string, hasAuth bool, userinfo, host, portStr, path, query, fragment string, hasQuery, hasFrag bool) string {
	var b strings.Builder
	b.WriteString(scheme)
	b.WriteByte(':')
	if hasAuth {
		b.WriteString("//")
		if userinfo != "" {
			b.WriteString(userinfo)
			b.WriteByte('@')
		}
		b.WriteString(host)
		b.WriteString(portStr)
	}
	b.WriteString(path)
	if hasQuery {
		b.WriteByte('?')
		b.WriteString(query)
	}
	if hasFrag {
		b.WriteByte('#')
		b.WriteString(fragment)
	}
	return b.String()
}

// ── Normalization ────────────────────────────────────────────────────

// normalizeSyntax implements RFC 3986 §6.2.2.
func normalizeSyntax(uri string) string {
	colon := strings.Index(uri, ":")
	if colon < 1 {
		return uri
	}
	scheme := strings.ToLower(uri[:colon])
	hasQ, hasF := detectMarkers(uri)
	hasAuth := hasAuthority(uri, colon)

	var userinfo, host, portStr, path string

	if hasAuth {
		netloc := extractNetloc(uri, colon)
		userinfo, host, portStr = splitNetloc(netloc)
		userinfo = pctNormalize(userinfo)
		host = strings.ToLower(pctNormalize(host))
		if portStr == ":" {
			portStr = ""
		}
		path = extractPath(uri, colon, netloc)
	} else {
		// For opaque URIs, everything after scheme: up to ? or # is the path.
		rest := uri[colon+1:]
		end := len(rest)
		for i, c := range rest {
			if c == '?' || c == '#' {
				end = i
				break
			}
		}
		path = rest[:end]
	}

	path = removeDotSegments(pctNormalize(path))

	query := ""
	if hasQ {
		query = pctNormalize(extractQuery(uri))
	}
	fragment := ""
	if hasF {
		fragment = pctNormalize(extractFragment(uri))
	}

	return reconstruct(scheme, hasAuth, userinfo, host, portStr, path, query, fragment, hasQ, hasF)
}

// normalizeIPv6 compresses an IPv6 address in bracket notation.
func normalizeIPv6(host string) string {
	if !strings.HasPrefix(host, "[") || !strings.HasSuffix(host, "]") {
		return host
	}
	addrStr := host[1 : len(host)-1]
	addr, err := netip.ParseAddr(addrStr)
	if err != nil {
		return host
	}
	return "[" + addr.String() + "]"
}

// normalizeScheme implements RFC 3986 §6.2.3.
func normalizeScheme(uri string) string {
	uri = normalizeSyntax(uri)
	colon := strings.Index(uri, ":")
	if colon < 1 {
		return uri
	}
	scheme := uri[:colon]
	hasQ, hasF := detectMarkers(uri)
	hasAuth := hasAuthority(uri, colon)

	if !hasAuth {
		return uri
	}

	netloc := extractNetloc(uri, colon)
	userinfo, host, portStr := splitNetloc(netloc)

	// IPv6 compression
	if strings.HasPrefix(host, "[") {
		host = normalizeIPv6(host)
	}

	// Normalize port: remove leading zeros, remove default port
	if strings.HasPrefix(portStr, ":") && len(portStr) > 1 {
		portNum, err := strconv.Atoi(portStr[1:])
		if err == nil {
			if dp, ok := defaultPorts[scheme]; ok && dp == portNum {
				portStr = ""
			} else {
				portStr = ":" + strconv.Itoa(portNum)
			}
		}
	}

	// Remove empty port
	if portStr == ":" {
		portStr = ""
	}

	// Remove empty userinfo
	if userinfo == "" || userinfo == ":" {
		userinfo = ""
	}

	// Empty path → "/"
	path := extractPath(uri, colon, netloc)
	if path == "" {
		path = "/"
	}

	// File scheme normalization
	if scheme == "file" {
		if host == "localhost" {
			host = ""
		}
		if len(path) >= 3 && path[0] == '/' && (path[2] == ':' || path[2] == '|') {
			path = "/" + strings.ToUpper(string(path[1])) + ":" + path[3:]
		}
	}

	query := ""
	if hasQ {
		query = extractQuery(uri)
	}
	fragment := ""
	if hasF {
		fragment = extractFragment(uri)
	}

	return reconstruct(scheme, true, userinfo, host, portStr, path, query, fragment, hasQ, hasF)
}

// decodeSubdelimsPath decodes percent-encoded sub-delimiters in path.
func decodeSubdelimsPath(path string) string {
	var b strings.Builder
	b.Grow(len(path))
	for i := 0; i < len(path); i++ {
		if path[i] == '%' && i+2 < len(path) && isHexDigit(path[i+1]) && isHexDigit(path[i+2]) {
			val, _ := strconv.ParseUint(path[i+1:i+3], 16, 8)
			ch := byte(val)
			if ch < 128 && strings.IndexByte(subdelimsPchar, ch) >= 0 {
				b.WriteByte(ch)
				i += 2
				continue
			}
		}
		b.WriteByte(path[i])
	}
	return b.String()
}

// normalizeProtocol implements RFC 3986 §6.2.4 (partial: no IDN, no NFC).
func normalizeProtocol(uri string) string {
	uri = normalizeScheme(uri)
	colon := strings.Index(uri, ":")
	if colon < 1 {
		return uri
	}
	scheme := uri[:colon]
	hasQ, hasF := detectMarkers(uri)
	hasAuth := hasAuthority(uri, colon)

	var userinfo, host, portStr, path string

	if hasAuth {
		netloc := extractNetloc(uri, colon)
		userinfo, host, portStr = splitNetloc(netloc)

		// Remove trailing dot from host
		if host != "" && !strings.HasPrefix(host, "[") && strings.HasSuffix(host, ".") {
			host = host[:len(host)-1]
		}

		path = extractPath(uri, colon, netloc)
	} else {
		userinfo, host, portStr = "", "", ""
		rest := uri[colon+1:]
		end := len(rest)
		for i, c := range rest {
			if c == '?' || c == '#' {
				end = i
				break
			}
		}
		path = rest[:end]
	}

	// Decode sub-delimiters in path
	path = decodeSubdelimsPath(path)

	query := ""
	if hasQ {
		query = extractQuery(uri)
		// + → %20 in query
		query = strings.ReplaceAll(query, "+", "%20")
		// Sort query params, remove empty segments
		params := strings.Split(query, "&")
		var filtered []string
		for _, p := range params {
			if p != "" {
				filtered = append(filtered, p)
			}
		}
		sort.Strings(filtered)
		query = strings.Join(filtered, "&")
	}

	fragment := ""
	if hasF {
		fragment = extractFragment(uri)
	}

	return reconstruct(scheme, hasAuth, userinfo, host, portStr, path, query, fragment, hasQ, hasF)
}

func normalize(uri, level string) string {
	switch level {
	case "protocol":
		return normalizeProtocol(uri)
	case "scheme":
		return normalizeScheme(uri)
	default:
		return normalizeSyntax(uri)
	}
}

// ── Validation ───────────────────────────────────────────────────────

func validateURI(uri string) (bool, string) {
	// 1. Disallowed characters
	for i := 0; i < len(uri); i++ {
		c := uri[i]
		if c == ' ' || c == '<' || c == '>' || c == '{' || c == '}' || c == '|' || c == '\\' {
			return false, fmt.Sprintf("disallowed char at %d", i)
		}
	}

	// 2. Valid percent-encoding
	for i := 0; i < len(uri); i++ {
		if uri[i] == '%' {
			if i+2 >= len(uri) || !isHexDigit(uri[i+1]) || !isHexDigit(uri[i+2]) {
				return false, fmt.Sprintf("bad pct-encoding at %d", i)
			}
			i += 2
		}
	}

	// 3. Scheme required
	colon := strings.Index(uri, ":")
	if colon < 1 {
		return false, "no scheme"
	}
	scheme := uri[:colon]
	if !((scheme[0] >= 'a' && scheme[0] <= 'z') || (scheme[0] >= 'A' && scheme[0] <= 'Z')) {
		return false, "invalid scheme"
	}
	for i := 1; i < len(scheme); i++ {
		if !isSchemeChar(scheme[i]) {
			return false, "invalid scheme"
		}
	}

	// 4. Port must be numeric
	// url.Parse detects non-numeric ports as errors, use that as a signal.
	_, err := url.Parse(uri)
	if err != nil && strings.Contains(err.Error(), "invalid port") {
		return false, "non-numeric port"
	}
	// Also check manually for URIs that url.Parse parses differently.
	if hasAuthority(uri, colon) {
		netloc := extractNetloc(uri, colon)
		_, _, portStr := splitNetloc(netloc)
		if strings.HasPrefix(portStr, ":") && len(portStr) > 1 {
			port := portStr[1:]
			for j := 0; j < len(port); j++ {
				if port[j] < '0' || port[j] > '9' {
					return false, "non-numeric port"
				}
			}
		}
	}

	// 5. Balanced brackets
	if strings.Count(uri, "[") != strings.Count(uri, "]") {
		return false, "unbalanced brackets"
	}

	return true, ""
}

// ── --parse mode ─────────────────────────────────────────────────────

func modeParse() {
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 0, 131072), 131072)
	ok, fail := 0, 0

	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			continue
		}
		tab := strings.Index(line, "\t")
		if tab < 0 {
			continue
		}
		id := line[:tab]
		uriStr := line[tab+1:]

		valid, reason := validateURI(uriStr)
		if valid {
			fmt.Printf("PARSE OK   %s\t%s\n", id, uriStr)
			ok++
		} else {
			fmt.Printf("PARSE FAIL %s\t%s\t%s\n", id, uriStr, reason)
			fail++
		}
	}

	fmt.Printf("\n--- Parse Summary ---\n")
	fmt.Printf("Total: %d  OK: %d  FAIL: %d\n", ok+fail, ok, fail)
}

// ── --equiv mode ─────────────────────────────────────────────────────

type equivRow struct {
	groupID      int
	variantID    int
	uri          string
	normLevel    string
	isCanonical  int
	isEquivalent int
}

func modeEquiv() {
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 0, 131072), 131072)

	var rows []equivRow
	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			continue
		}
		fields := strings.SplitN(line, "\t", 6)
		if len(fields) < 6 {
			continue
		}
		gid, _ := strconv.Atoi(fields[0])
		vid, _ := strconv.Atoi(fields[1])
		isCan, _ := strconv.Atoi(fields[4])
		isEq, _ := strconv.Atoi(fields[5])
		rows = append(rows, equivRow{gid, vid, fields[2], fields[3], isCan, isEq})
	}

	gpass, gfail := 0, 0
	i := 0
	for i < len(rows) {
		gid := rows[i].groupID
		start := i
		for i < len(rows) && rows[i].groupID == gid {
			i++
		}
		group := rows[start:i]

		level := group[0].normLevel
		isPositive := group[0].isEquivalent == 1

		norms := make([]string, len(group))
		for j, r := range group {
			norms[j] = normalize(r.uri, level)
		}

		if isPositive {
			pass := true
			for j := 1; j < len(norms); j++ {
				if norms[j] != norms[0] {
					pass = false
					break
				}
			}
			if pass {
				fmt.Printf("EQUIV PASS  group=%d level=%s canonical=%s\n", gid, level, norms[0])
				gpass++
			} else {
				fmt.Printf("EQUIV FAIL  group=%d level=%s (positive: normalized forms differ)\n", gid, level)
				for j, r := range group {
					fmt.Printf("  variant=%d  input=%-60s  normalized=%s\n", r.variantID, r.uri, norms[j])
				}
				gfail++
			}
		} else {
			allSame := true
			for j := 1; j < len(norms); j++ {
				if norms[j] != norms[0] {
					allSame = false
					break
				}
			}
			if !allSame {
				fmt.Printf("EQUIV PASS  group=%d level=%s (negative: forms differ as expected)\n", gid, level)
				gpass++
			} else {
				fmt.Printf("EQUIV FAIL  group=%d level=%s (negative: forms should differ but don't)\n", gid, level)
				for j, r := range group {
					fmt.Printf("  variant=%d  input=%-60s  normalized=%s\n", r.variantID, r.uri, norms[j])
				}
				gfail++
			}
		}
	}

	fmt.Printf("\n--- Equivalence Summary (go net/url) ---\n")
	fmt.Printf("Groups: %d  Pass: %d  Fail: %d\n", gpass+gfail, gpass, gfail)
}

// ── main ─────────────────────────────────────────────────────────────

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintf(os.Stderr, "Usage: %s --parse | --equiv\n", os.Args[0])
		os.Exit(1)
	}
	switch os.Args[1] {
	case "--parse":
		modeParse()
	case "--equiv":
		modeEquiv()
	default:
		fmt.Fprintf(os.Stderr, "Unknown mode: %s\n", os.Args[1])
		os.Exit(1)
	}
}
