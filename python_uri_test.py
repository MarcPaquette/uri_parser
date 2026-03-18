#!/usr/bin/env python3
"""URI test validator using Python's urllib.parse as a canonical parser.

Implements RFC 3986 Section 6 normalization at three levels:
  - syntax   (§6.2.2): case, percent-encoding, dot-segment removal
  - scheme   (§6.2.3): default ports, empty path, empty userinfo, file://
  - protocol (§6.2.4): query sort, +→%20, trailing dot, sub-delims, NFC, IDN
"""

import ipaddress
import re
import sys
import unicodedata
from urllib.parse import urlsplit, quote, unquote

UNRESERVED = frozenset(
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~'
)
SUBDELIMS_PCHAR = frozenset("!$&'()*+,;=:@")
HEX = frozenset('0123456789ABCDEFabcdef')

DEFAULT_PORTS = {
    'http': 80, 'https': 443, 'ftp': 21, 'ftps': 990,
    'ssh': 22, 'telnet': 23, 'ws': 80, 'wss': 443,
    'ldap': 389, 'ldaps': 636, 'mysql': 3306, 'postgres': 5432,
    'redis': 6379, 'mongodb': 27017, 'kafka': 9092, 'postgresql': 5432,
}

# ── Helpers ──────────────────────────────────────────────────────────

def remove_dot_segments(path):
    """RFC 3986 §5.2.4 — input/output buffer algorithm."""
    inp = path
    out = []
    while inp:
        if inp.startswith('../'):     inp = inp[3:]
        elif inp.startswith('./'):    inp = inp[2:]
        elif inp.startswith('/./'):   inp = '/' + inp[3:]
        elif inp == '/.':            inp = '/'
        elif inp.startswith('/../'):
            inp = '/' + inp[4:]
            if out: out.pop()
        elif inp == '/..':
            inp = '/'
            if out: out.pop()
        elif inp in ('.', '..'):     inp = ''
        else:
            if inp[0] == '/':
                idx = inp.find('/', 1)
                if idx == -1: out.append(inp); inp = ''
                else:         out.append(inp[:idx]); inp = inp[idx:]
            else:
                idx = inp.find('/')
                if idx == -1: out.append(inp); inp = ''
                else:         out.append(inp[:idx]); inp = inp[idx:]
    return ''.join(out)


def pct_normalize(s):
    """RFC 3986 §6.2.2.2 — uppercase hex digits, decode unreserved."""
    if not s:
        return s
    result = []
    i = 0
    while i < len(s):
        if s[i] == '%' and i + 2 < len(s) and s[i+1] in HEX and s[i+2] in HEX:
            val = int(s[i+1:i+3], 16)
            ch = chr(val)
            if ch in UNRESERVED:
                result.append(ch)
            else:
                result.append(f'%{val:02X}')
            i += 3
        else:
            result.append(s[i])
            i += 1
    return ''.join(result)


def _split_netloc(netloc):
    """Split netloc into (userinfo, host, port_str) where port_str includes ':'."""
    if not netloc:
        return '', '', ''
    if '@' in netloc:
        userinfo, _, rest = netloc.rpartition('@')
    else:
        userinfo, rest = '', netloc
    if rest.startswith('['):
        bracket = rest.find(']')
        if bracket != -1:
            return userinfo, rest[:bracket+1], rest[bracket+1:]
        return userinfo, rest, ''
    if ':' in rest:
        host, _, p = rest.rpartition(':')
        return userinfo, host, ':' + p
    return userinfo, rest, ''


def _detect_markers(uri):
    """Detect has_query (? present) and has_fragment (# present)."""
    h = uri.find('#')
    q = uri.find('?')
    return (q != -1 and (h == -1 or q < h)), (h != -1)


def _has_authority(uri, scheme_len):
    """Check if URI has authority (// after scheme:)."""
    return uri[scheme_len+1:scheme_len+3] == '//'


def _reconstruct(scheme, has_auth, userinfo, host, port_str, path,
                 query, fragment, has_query, has_frag):
    r = scheme + ':'
    if has_auth:
        r += '//'
        if userinfo:
            r += userinfo + '@'
        r += host + port_str
    r += path
    if has_query:
        r += '?' + (query or '')
    if has_frag:
        r += '#' + (fragment or '')
    return r


# ── §6.2.2: Syntax-Based Normalization ──────────────────────────────

def normalize_syntax(uri):
    try:
        parts = urlsplit(uri)
    except ValueError:
        return uri
    scheme = parts.scheme.lower()
    has_query, has_frag = _detect_markers(uri)
    has_auth = _has_authority(uri, len(parts.scheme))

    if has_auth:
        userinfo, host, port_str = _split_netloc(parts.netloc)
        userinfo = pct_normalize(userinfo)
        host = pct_normalize(host).lower()
        # Remove empty port (colon with no digits)
        if port_str == ':':
            port_str = ''
    else:
        userinfo, host, port_str = '', '', ''

    path = remove_dot_segments(pct_normalize(parts.path))
    query = pct_normalize(parts.query) if parts.query else parts.query
    fragment = pct_normalize(parts.fragment) if parts.fragment else parts.fragment

    return _reconstruct(scheme, has_auth, userinfo, host, port_str,
                        path, query, fragment, has_query, has_frag)


# ── IPv6 normalization helper ────────────────────────────────────────

def _normalize_ipv6(host):
    """Compress IPv6 address in bracket notation using ipaddress module."""
    if not host.startswith('[') or not host.endswith(']'):
        return host
    addr_str = host[1:-1]
    try:
        addr = ipaddress.IPv6Address(addr_str)
        return '[' + str(addr) + ']'
    except ValueError:
        return host


# ── §6.2.3: Scheme-Based Normalization ──────────────────────────────

def normalize_scheme(uri):
    uri = normalize_syntax(uri)
    parts = urlsplit(uri)
    scheme = parts.scheme
    has_query, has_frag = _detect_markers(uri)
    has_auth = _has_authority(uri, len(scheme))

    if not has_auth:
        return uri

    userinfo, host, port_str = _split_netloc(parts.netloc)

    # IPv6 normalization (compression, leading zeros)
    if host.startswith('['):
        host = _normalize_ipv6(host)

    # Normalize port (remove leading zeros) and remove default port
    if port_str.startswith(':') and port_str[1:]:
        try:
            port_num = int(port_str[1:])
            if DEFAULT_PORTS.get(scheme) == port_num:
                port_str = ''
            else:
                port_str = ':' + str(port_num)
        except ValueError:
            pass

    # Remove empty port
    if port_str == ':':
        port_str = ''

    # Remove empty userinfo
    if userinfo in ('', ':'):
        userinfo = ''

    # Empty path → '/'
    path = parts.path or '/'

    # File scheme normalization
    if scheme == 'file':
        if host == 'localhost':
            host = ''
        if len(path) >= 3 and path[0] == '/' and path[2] in (':', '|'):
            path = '/' + path[1].upper() + ':' + path[3:]

    return _reconstruct(scheme, True, userinfo, host, port_str,
                        path, parts.query, parts.fragment, has_query, has_frag)


# ── §6.2.4: Protocol-Based Normalization ────────────────────────────

def _decode_subdelims_path(path):
    """Decode percent-encoded sub-delimiters and pchar-safe chars in path."""
    result = []
    i = 0
    while i < len(path):
        if path[i] == '%' and i + 2 < len(path) and path[i+1] in HEX and path[i+2] in HEX:
            val = int(path[i+1:i+3], 16)
            if val < 128 and chr(val) in SUBDELIMS_PCHAR:
                result.append(chr(val))
                i += 3
                continue
        result.append(path[i])
        i += 1
    return ''.join(result)


def _nfc_path(path):
    """Apply NFC normalization to path segments (decode, NFC, re-encode)."""
    segs = path.split('/')
    out = []
    for seg in segs:
        if not seg:
            out.append('')
            continue
        try:
            decoded = unquote(seg, encoding='utf-8', errors='strict')
            normalized = unicodedata.normalize('NFC', decoded)
            out.append(quote(normalized, safe="-._~!$&'()*+,;=:@"))
        except (UnicodeDecodeError, UnicodeEncodeError):
            out.append(seg)
    return '/'.join(out)


def normalize_protocol(uri):
    uri = normalize_scheme(uri)
    parts = urlsplit(uri)
    scheme = parts.scheme
    has_query, has_frag = _detect_markers(uri)
    has_auth = _has_authority(uri, len(scheme))

    if has_auth:
        userinfo, host, port_str = _split_netloc(parts.netloc)
    else:
        userinfo, host, port_str = '', '', ''

    # Remove trailing dot from host
    if host and not host.startswith('[') and host.endswith('.'):
        host = host[:-1]

    # IDN normalization (Unicode → Punycode)
    if host and not host.startswith('['):
        try:
            host = host.encode('idna').decode('ascii')
        except (UnicodeError, UnicodeDecodeError):
            pass

    path = _decode_subdelims_path(parts.path)
    path = _nfc_path(path)
    query = parts.query
    fragment = parts.fragment

    # + → %20 in query
    if query:
        query = query.replace('+', '%20')

    # Sort query params, filter empty (trailing/leading/double &)
    if query is not None and has_query:
        params = [p for p in query.split('&') if p]
        params.sort()
        query = '&'.join(params)

    result = _reconstruct(scheme, has_auth, userinfo, host, port_str,
                          path, query, fragment, has_query, has_frag)
    return unicodedata.normalize('NFC', result)


# ── Normalization dispatch ──────────────────────────────────────────

def normalize(uri, level):
    if level == 'protocol':
        return normalize_protocol(uri)
    if level == 'scheme':
        return normalize_scheme(uri)
    return normalize_syntax(uri)


# ── URI Validation (RFC 3986 ABNF) ──────────────────────────────────

_DISALLOWED = frozenset(' <>{|}\\')
_SCHEME_RE = re.compile(r'^[a-zA-Z][a-zA-Z0-9+\-.]*$')

def validate_uri(uri):
    """Validate URI against RFC 3986 structural rules."""
    for i, ch in enumerate(uri):
        if ch in _DISALLOWED:
            return False, f"disallowed char at {i}"

    # Valid percent-encoding
    i = 0
    while i < len(uri):
        if uri[i] == '%':
            if i + 2 >= len(uri) or uri[i+1] not in HEX or uri[i+2] not in HEX:
                return False, f"bad pct-encoding at {i}"
            i += 3
        else:
            i += 1

    # Scheme required
    colon = uri.find(':')
    if colon < 1:
        return False, "no scheme"
    if not _SCHEME_RE.match(uri[:colon]):
        return False, "invalid scheme"

    # Port must be numeric
    try:
        parts = urlsplit(uri)
    except ValueError:
        return False, "invalid URL structure"
    if parts.netloc:
        _, _, port_str = _split_netloc(parts.netloc)
        if port_str.startswith(':') and port_str[1:] and not port_str[1:].isdigit():
            return False, "non-numeric port"

    # Balanced IPv6 brackets
    if uri.count('[') != uri.count(']'):
        return False, "unbalanced brackets"

    return True, None


# ── --parse mode ────────────────────────────────────────────────────

def mode_parse():
    ok = fail = 0
    for line in sys.stdin:
        line = line.rstrip('\n\r')
        if not line:
            continue
        tab = line.find('\t')
        if tab == -1:
            continue
        uid, uri_str = line[:tab], line[tab+1:]
        valid, reason = validate_uri(uri_str)
        if valid:
            print(f"PARSE OK   {uid}\t{uri_str}")
            ok += 1
        else:
            print(f"PARSE FAIL {uid}\t{uri_str}\t{reason}")
            fail += 1
    print(f"\n--- Parse Summary ---")
    print(f"Total: {ok + fail}  OK: {ok}  FAIL: {fail}")


# ── --equiv mode ────────────────────────────────────────────────────

def mode_equiv():
    rows = []
    for line in sys.stdin:
        line = line.rstrip('\n\r')
        if not line:
            continue
        f = line.split('\t')
        if len(f) < 6:
            continue
        rows.append((int(f[0]), int(f[1]), f[2], f[3], int(f[4]), int(f[5])))

    gpass = gfail = 0
    i = 0
    while i < len(rows):
        gid = rows[i][0]
        group = []
        while i < len(rows) and rows[i][0] == gid:
            group.append(rows[i])
            i += 1

        level = group[0][3]
        is_positive = group[0][5]
        norms = [normalize(r[2], level) for r in group]

        if is_positive:
            ok = all(n == norms[0] for n in norms[1:])
            if ok:
                print(f"EQUIV PASS  group={gid} level={level} canonical={norms[0]}")
                gpass += 1
            else:
                print(f"EQUIV FAIL  group={gid} level={level} (positive: normalized forms differ)")
                for j, r in enumerate(group):
                    print(f"  variant={r[1]}  input={r[2]:<60s}  normalized={norms[j]}")
                gfail += 1
        else:
            same = all(n == norms[0] for n in norms[1:])
            if not same:
                print(f"EQUIV PASS  group={gid} level={level} (negative: forms differ as expected)")
                gpass += 1
            else:
                print(f"EQUIV FAIL  group={gid} level={level} (negative: forms should differ but don't)")
                for j, r in enumerate(group):
                    print(f"  variant={r[1]}  input={r[2]:<60s}  normalized={norms[j]}")
                gfail += 1

    print(f"\n--- Equivalence Summary (python urllib.parse) ---")
    print(f"Groups: {gpass + gfail}  Pass: {gpass}  Fail: {gfail}")


# ── main ────────────────────────────────────────────────────────────

if __name__ == '__main__':
    if len(sys.argv) < 2 or sys.argv[1] not in ('--parse', '--equiv'):
        print(f"Usage: {sys.argv[0]} --parse | --equiv", file=sys.stderr)
        sys.exit(1)
    if sys.argv[1] == '--parse':
        mode_parse()
    else:
        mode_equiv()
