-- =============================================================================
-- URI Equivalence Test Data
-- =============================================================================
-- Each group_id groups URI variants for comparison.
-- The normalization_level column indicates what level of normalization (per
-- RFC 3986 Section 6) is required to recognise the equivalence:
--
--   syntax    – syntax-based normalization (case, percent-encoding, dot segments)
--   scheme    – scheme-based normalization  (default ports, empty paths)
--   protocol  – protocol-based / application-level normalization
--
-- Rows with is_canonical = TRUE represent the preferred normalized form.
-- Rows with is_equivalent = TRUE are positive tests (variants MUST normalize
-- to the same output). Rows with is_equivalent = FALSE are negative tests
-- (variants MUST NOT normalize to the same output).
-- =============================================================================

CREATE TABLE uri_equivalence_tests (
    group_id            INT NOT NULL,
    variant_id          INT NOT NULL,
    uri                 TEXT NOT NULL,
    description         TEXT NOT NULL,
    normalization_level TEXT NOT NULL,
    is_canonical        BOOLEAN NOT NULL DEFAULT FALSE,
    is_equivalent       BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (group_id, variant_id)
);

INSERT INTO uri_equivalence_tests
    (group_id, variant_id, uri, description, normalization_level, is_canonical, is_equivalent)
VALUES

-- =============================================================================
-- 1. CASE NORMALIZATION  (scheme + host are case-insensitive)
-- =============================================================================

-- Group 1: Scheme case
(1, 1, 'http://example.com',          'Lowercase scheme (canonical)',     'syntax', TRUE, TRUE),
(1, 2, 'HTTP://example.com',          'Uppercase scheme',                 'syntax', FALSE, TRUE),
(1, 3, 'Http://example.com',          'Mixed case scheme',               'syntax', FALSE, TRUE),
(1, 4, 'hTtP://example.com',          'Alternating case scheme',         'syntax', FALSE, TRUE),

-- Group 2: Host case
(2, 1, 'http://example.com/path',     'Lowercase host (canonical)',      'syntax', TRUE, TRUE),
(2, 2, 'http://EXAMPLE.COM/path',     'Uppercase host',                  'syntax', FALSE, TRUE),
(2, 3, 'http://Example.Com/path',     'Mixed case host',                 'syntax', FALSE, TRUE),
(2, 4, 'http://eXaMpLe.CoM/path',     'Alternating case host',          'syntax', FALSE, TRUE),

-- Group 3: Scheme + host case combined (path stays case-sensitive)
(3, 1, 'https://www.example.com/Path/To/Resource',   'Canonical form',         'syntax', TRUE, TRUE),
(3, 2, 'HTTPS://WWW.EXAMPLE.COM/Path/To/Resource',   'Uppercase scheme+host',  'syntax', FALSE, TRUE),
(3, 3, 'Https://Www.Example.Com/Path/To/Resource',   'Title case scheme+host', 'syntax', FALSE, TRUE),

-- Group 4: Scheme case with port and query
(4, 1, 'http://example.com:8080/path?key=VALUE',          'Canonical form',    'syntax', TRUE, TRUE),
(4, 2, 'HTTP://EXAMPLE.COM:8080/path?key=VALUE',          'Uppercase pre-path','syntax', FALSE, TRUE),
(4, 3, 'Http://Example.Com:8080/path?key=VALUE',          'Mixed case',        'syntax', FALSE, TRUE),

-- Group 5: Hex digit case in percent-encoding
(5, 1, 'http://example.com/%7E',      'Uppercase hex digits (canonical)', 'syntax', TRUE, TRUE),
(5, 2, 'http://example.com/%7e',      'Lowercase hex digits',             'syntax', FALSE, TRUE),

-- Group 6: Multi-byte percent-encoding hex case
(6, 1, 'http://example.com/%C3%A9',   'Uppercase hex (canonical)',        'syntax', TRUE, TRUE),
(6, 2, 'http://example.com/%c3%a9',   'Lowercase hex',                    'syntax', FALSE, TRUE),
(6, 3, 'http://example.com/%C3%a9',   'Mixed hex case',                   'syntax', FALSE, TRUE),
(6, 4, 'http://example.com/%c3%A9',   'Inverted mixed hex case',          'syntax', FALSE, TRUE),

-- =============================================================================
-- 2. PERCENT-ENCODING NORMALIZATION  (unreserved characters)
-- =============================================================================
-- RFC 3986 unreserved = ALPHA / DIGIT / "-" / "." / "_" / "~"
-- Percent-encoding unreserved chars is valid but should normalize to decoded.

-- Group 10: Tilde
(10, 1, 'http://example.com/~user',        'Literal tilde (canonical)',          'syntax', TRUE, TRUE),
(10, 2, 'http://example.com/%7Euser',      'Percent-encoded tilde (uppercase)', 'syntax', FALSE, TRUE),
(10, 3, 'http://example.com/%7euser',      'Percent-encoded tilde (lowercase)', 'syntax', FALSE, TRUE),

-- Group 11: Hyphen
(11, 1, 'http://example.com/a-b',          'Literal hyphen (canonical)',         'syntax', TRUE, TRUE),
(11, 2, 'http://example.com/a%2Db',        'Percent-encoded hyphen',             'syntax', FALSE, TRUE),

-- Group 12: Period
(12, 1, 'http://example.com/a.b',          'Literal period (canonical)',         'syntax', TRUE, TRUE),
(12, 2, 'http://example.com/a%2Eb',        'Percent-encoded period',             'syntax', FALSE, TRUE),

-- Group 13: Underscore
(13, 1, 'http://example.com/a_b',          'Literal underscore (canonical)',     'syntax', TRUE, TRUE),
(13, 2, 'http://example.com/a%5Fb',        'Percent-encoded underscore',         'syntax', FALSE, TRUE),

-- Group 14: Digits
(14, 1, 'http://example.com/123',          'Literal digits (canonical)',         'syntax', TRUE, TRUE),
(14, 2, 'http://example.com/%31%32%33',    'Percent-encoded digits',             'syntax', FALSE, TRUE),

-- Group 15: Letters
(15, 1, 'http://example.com/path',         'Literal letters (canonical)',        'syntax', TRUE, TRUE),
(15, 2, 'http://example.com/%70%61%74%68', 'All letters percent-encoded',        'syntax', FALSE, TRUE),
(15, 3, 'http://example.com/p%61th',       'Partially percent-encoded',          'syntax', FALSE, TRUE),
(15, 4, 'http://example.com/%70ath',       'First letter encoded',               'syntax', FALSE, TRUE),
(15, 5, 'http://example.com/pat%68',       'Last letter encoded',                'syntax', FALSE, TRUE),

-- Group 16: Uppercase letters
(16, 1, 'http://example.com/ABC',          'Literal uppercase (canonical)',      'syntax', TRUE, TRUE),
(16, 2, 'http://example.com/%41%42%43',    'Percent-encoded uppercase letters',  'syntax', FALSE, TRUE),

-- Group 17: All unreserved in one path
(17, 1, 'http://example.com/aZ09-._~',                             'All unreserved literal (canonical)', 'syntax', TRUE, TRUE),
(17, 2, 'http://example.com/%61%5A%30%39%2D%2E%5F%7E',             'All unreserved encoded',             'syntax', FALSE, TRUE),

-- Group 18: Unreserved in query value
(18, 1, 'http://example.com/path?key=hello_world',                 'Literal underscore in query (canonical)', 'syntax', TRUE, TRUE),
(18, 2, 'http://example.com/path?key=hello%5Fworld',               'Encoded underscore in query',              'syntax', FALSE, TRUE),

-- Group 19: Unreserved in fragment
(19, 1, 'http://example.com/path#section~1',                       'Literal tilde in fragment (canonical)',     'syntax', TRUE, TRUE),
(19, 2, 'http://example.com/path#section%7E1',                     'Encoded tilde in fragment',                 'syntax', FALSE, TRUE),

-- Group 20: Unreserved in userinfo
(20, 1, 'http://us-er@example.com',                                'Literal hyphen in userinfo (canonical)',    'syntax', TRUE, TRUE),
(20, 2, 'http://us%2Der@example.com',                              'Encoded hyphen in userinfo',                'syntax', FALSE, TRUE),

-- =============================================================================
-- 3. PATH SEGMENT NORMALIZATION  (dot segment removal)
-- =============================================================================

-- Group 30: Single dot removal
(30, 1, 'http://example.com/a/b/c',            'Clean path (canonical)',               'syntax', TRUE, TRUE),
(30, 2, 'http://example.com/a/./b/./c',        'Single dots in path',                  'syntax', FALSE, TRUE),
-- NOTE: http://example.com/./a/./b/./c/. resolves to /a/b/c/ (trailing slash) per
-- remove_dot_segments, so it is NOT equivalent to /a/b/c. Moved to Group 33.

-- Group 31: Double dot removal
(31, 1, 'http://example.com/a/c',              'Clean path (canonical)',               'syntax', TRUE, TRUE),
(31, 2, 'http://example.com/a/b/../c',         'Parent ref removes b',                 'syntax', FALSE, TRUE),
(31, 3, 'http://example.com/a/b/d/../../../a/c','Multiple parent refs resolve to a/c', 'syntax', FALSE, TRUE),

-- Group 32: Mixed dot segments
(32, 1, 'http://example.com/a/g',              'Clean path (canonical)',               'syntax', TRUE, TRUE),
(32, 2, 'http://example.com/a/b/c/./../../g',  'Mixed . and .. segments',              'syntax', FALSE, TRUE),
(32, 3, 'http://example.com/a/./g',            'Dot then target',                      'syntax', FALSE, TRUE),
(32, 4, 'http://example.com/a/b/../g',         'Up one then target',                   'syntax', FALSE, TRUE),

-- Group 33: Root path dot normalization
(33, 1, 'http://example.com/',                 'Root path (canonical)',                'syntax', TRUE, TRUE),
(33, 2, 'http://example.com/.',               'Dot at root',                          'syntax', FALSE, TRUE),
(33, 3, 'http://example.com/./',              'Dot slash at root',                    'syntax', FALSE, TRUE),
(33, 4, 'http://example.com/a/..',            'Up from single segment',               'syntax', FALSE, TRUE),
(33, 5, 'http://example.com/a/b/../..',       'Up two from two segments',             'syntax', FALSE, TRUE),
(33, 6, 'http://example.com/./a/../',          'Dot then parent then root',            'syntax', FALSE, TRUE),

-- Group 34: Dot segments with query and fragment preserved
(34, 1, 'http://example.com/a/c?q=1#f',            'Clean (canonical)',               'syntax', TRUE, TRUE),
(34, 2, 'http://example.com/a/b/../c?q=1#f',       'Parent ref with query+fragment',  'syntax', FALSE, TRUE),
(34, 3, 'http://example.com/a/./c?q=1#f',          'Dot segment with query+fragment', 'syntax', FALSE, TRUE),

-- Group 35: Deeply nested dot segments
(35, 1, 'http://example.com/x',                                    'Clean path (canonical)',  'syntax', TRUE, TRUE),
(35, 2, 'http://example.com/a/b/c/d/../../../../x',                'Four levels up',          'syntax', FALSE, TRUE),
(35, 3, 'http://example.com/./a/../b/../c/../x',                   'Zigzag dot segments',     'syntax', FALSE, TRUE),

-- =============================================================================
-- 4. SCHEME-BASED NORMALIZATION  (default ports)
-- =============================================================================

-- Group 40: HTTP default port (80)
(40, 1, 'http://example.com/path',         'No port (canonical)',                'scheme', TRUE, TRUE),
(40, 2, 'http://example.com:80/path',      'Explicit default port 80',          'scheme', FALSE, TRUE),

-- Group 41: HTTPS default port (443)
(41, 1, 'https://example.com/path',        'No port (canonical)',                'scheme', TRUE, TRUE),
(41, 2, 'https://example.com:443/path',    'Explicit default port 443',         'scheme', FALSE, TRUE),

-- Group 42: FTP default port (21)
(42, 1, 'ftp://example.com/path',          'No port (canonical)',                'scheme', TRUE, TRUE),
(42, 2, 'ftp://example.com:21/path',       'Explicit default port 21',          'scheme', FALSE, TRUE),

-- Group 43: SSH default port (22)
(43, 1, 'ssh://example.com',              'No port (canonical)',                'scheme', TRUE, TRUE),
(43, 2, 'ssh://example.com:22',           'Explicit default port 22',          'scheme', FALSE, TRUE),

-- Group 44: WS default port (80)
(44, 1, 'ws://example.com/socket',         'No port (canonical)',               'scheme', TRUE, TRUE),
(44, 2, 'ws://example.com:80/socket',      'Explicit default port 80',         'scheme', FALSE, TRUE),

-- Group 45: WSS default port (443)
(45, 1, 'wss://example.com/socket',        'No port (canonical)',               'scheme', TRUE, TRUE),
(45, 2, 'wss://example.com:443/socket',    'Explicit default port 443',        'scheme', FALSE, TRUE),

-- Group 46: Default port with full URI (all components)
(46, 1, 'http://user:pass@example.com/path?q=1#f',       'No port (canonical)',         'scheme', TRUE, TRUE),
(46, 2, 'http://user:pass@example.com:80/path?q=1#f',    'Explicit default port 80',   'scheme', FALSE, TRUE),

-- =============================================================================
-- 5. SCHEME-BASED NORMALIZATION  (empty path)
-- =============================================================================

-- Group 50: Empty path vs root slash
(50, 1, 'http://example.com/',            'Trailing slash (canonical)',         'scheme', TRUE, TRUE),
(50, 2, 'http://example.com',             'No trailing slash',                 'scheme', FALSE, TRUE),

-- Group 51: Empty path vs root slash with query
(51, 1, 'http://example.com/?q=1',        'Root slash with query (canonical)', 'scheme', TRUE, TRUE),
(51, 2, 'http://example.com?q=1',         'No path with query',               'scheme', FALSE, TRUE),

-- Group 52: Empty path vs root slash with fragment
(52, 1, 'http://example.com/#frag',       'Root slash with fragment (canonical)', 'scheme', TRUE, TRUE),
(52, 2, 'http://example.com#frag',         'No path with fragment',               'scheme', FALSE, TRUE),

-- Group 53: Empty path with port
(53, 1, 'http://example.com:8080/',        'Port with slash (canonical)',       'scheme', TRUE, TRUE),
(53, 2, 'http://example.com:8080',         'Port without slash',               'scheme', FALSE, TRUE),

-- =============================================================================
-- 6. EMPTY PORT  (colon with no digits)
-- =============================================================================

-- Group 55: Trailing colon with no port number
(55, 1, 'http://example.com/path',         'No colon (canonical)',             'syntax', TRUE, TRUE),
(55, 2, 'http://example.com:/path',        'Trailing colon, no port digits',   'syntax', FALSE, TRUE),

-- Group 56: Empty port with userinfo
(56, 1, 'http://user@example.com/',        'No colon (canonical)',             'syntax', TRUE, TRUE),
(56, 2, 'http://user@example.com:/',       'Trailing colon, no port digits',   'syntax', FALSE, TRUE),

-- =============================================================================
-- 7. IPv6 ADDRESS NORMALIZATION
-- =============================================================================

-- Group 60: IPv6 case normalization
(60, 1, 'http://[2001:db8::1]/',                       'Lowercase hex (canonical)',     'syntax', TRUE, TRUE),
(60, 2, 'http://[2001:DB8::1]/',                       'Uppercase hex',                 'syntax', FALSE, TRUE),
(60, 3, 'http://[2001:Db8::1]/',                       'Mixed case hex',                'syntax', FALSE, TRUE),

-- Group 61: IPv6 leading zeros
(61, 1, 'http://[2001:db8:0:0:0:0:0:1]/',             'Expanded form',                 'scheme', FALSE, TRUE),
(61, 2, 'http://[2001:db8::1]/',                       'Compressed form (canonical)',    'scheme', TRUE, TRUE),

-- Group 62: IPv6 zero compression variants
(62, 1, 'http://[::1]/',                               'Loopback compressed (canonical)', 'scheme', TRUE, TRUE),
(62, 2, 'http://[0:0:0:0:0:0:0:1]/',                  'Loopback expanded',               'scheme', FALSE, TRUE),
(62, 3, 'http://[0000:0000:0000:0000:0000:0000:0000:0001]/', 'Loopback fully expanded',  'scheme', FALSE, TRUE),

-- Group 63: IPv6 all-zeros
(63, 1, 'http://[::]/',                                'All-zeros compressed (canonical)', 'scheme', TRUE, TRUE),
(63, 2, 'http://[0:0:0:0:0:0:0:0]/',                  'All-zeros expanded',               'scheme', FALSE, TRUE),
(63, 3, 'http://[0000:0000:0000:0000:0000:0000:0000:0000]/', 'All-zeros fully expanded',  'scheme', FALSE, TRUE),

-- Group 64: IPv6 with port – address normalization
(64, 1, 'http://[2001:db8::1]:8080/path',             'Compressed with port (canonical)', 'scheme', TRUE, TRUE),
(64, 2, 'http://[2001:0db8:0:0:0:0:0:1]:8080/path',   'Expanded with port',               'scheme', FALSE, TRUE),

-- =============================================================================
-- 8. COMBINED NORMALIZATIONS  (multiple rules applied at once)
-- =============================================================================

-- Group 100: Case + default port
(100, 1, 'http://example.com/path',                            'Canonical',                          'scheme', TRUE, TRUE),
(100, 2, 'HTTP://EXAMPLE.COM:80/path',                         'Uppercase + default port',           'scheme', FALSE, TRUE),
(100, 3, 'Http://Example.Com:80/path',                         'Mixed case + default port',          'scheme', FALSE, TRUE),

-- Group 101: Case + percent-encoding + dots
(101, 1, 'http://example.com/~user/file',                      'Canonical',                          'syntax', TRUE, TRUE),
(101, 2, 'HTTP://EXAMPLE.COM/%7euser/./file',                  'Uppercase + encoded tilde + dot',    'syntax', FALSE, TRUE),
(101, 3, 'Http://Example.Com/%7Euser/a/../file',               'Mixed case + encoded tilde + ..',    'syntax', FALSE, TRUE),

-- Group 102: Default port + empty path + case
(102, 1, 'https://example.com/',                               'Canonical',                          'scheme', TRUE, TRUE),
(102, 2, 'HTTPS://EXAMPLE.COM:443',                            'Uppercase + port + no slash',        'scheme', FALSE, TRUE),
(102, 3, 'Https://Example.Com:443/',                           'Mixed case + explicit port + slash', 'scheme', FALSE, TRUE),

-- Group 103: Everything combined – full URI
(103, 1, 'http://example.com/~user/doc?q=hello#top',           'Canonical',                          'scheme', TRUE, TRUE),
(103, 2, 'HTTP://EXAMPLE.COM:80/%7Euser/./doc?q=hello#top',    'All normalizations applied',        'scheme', FALSE, TRUE),
(103, 3, 'Http://Example.Com:80/%7euser/a/../doc?q=hello#top', 'All normalizations mixed case',     'scheme', FALSE, TRUE),

-- Group 104: Percent-encoded unreserved in all components
(104, 1, 'http://us.er@example.com/a-b?c_d=1#e~f',             'All literal (canonical)',           'syntax', TRUE, TRUE),
(104, 2, 'http://us%2Eer@example.com/a%2Db?c%5Fd=1#e%7Ef',     'All unreserved encoded',           'syntax', FALSE, TRUE),

-- Group 105: Multiple encoded letters in path with dots
(105, 1, 'http://example.com/hello/world',                      'Canonical',                        'syntax', TRUE, TRUE),
(105, 2, 'http://example.com/%68%65%6C%6C%6F/%77%6F%72%6C%64', 'Fully encoded path',               'syntax', FALSE, TRUE),
(105, 3, 'http://example.com/./hello/x/../world',               'Dot segments resolve to same',     'syntax', FALSE, TRUE),
(105, 4, 'http://example.com/%68ello/./world',                  'Partial encoding + dot segment',   'syntax', FALSE, TRUE),

-- =============================================================================
-- 9. RESERVED CHARACTER ENCODING  (must stay encoded – NOT equivalent if decoded)
-- =============================================================================
-- These groups test that reserved chars are NOT treated as equivalent when
-- encoded vs literal, because decoding them changes semantics.

-- Group 200: Encoded slash vs path separator  (NOT equivalent)
(200, 1, 'http://example.com/a%2Fb',          'Encoded slash – single segment "a/b"',  'syntax', TRUE, FALSE),
(200, 2, 'http://example.com/a/b',            'Literal slash – two segments "a" "b"',  'syntax', FALSE, FALSE),

-- Group 201: Encoded question mark vs query delimiter  (NOT equivalent)
(201, 1, 'http://example.com/path%3Fq=1',     'Encoded ? in path, no query',          'syntax', TRUE, FALSE),
(201, 2, 'http://example.com/path?q=1',       'Literal ? starts query',               'syntax', FALSE, FALSE),

-- Group 202: Encoded hash vs fragment delimiter  (NOT equivalent)
(202, 1, 'http://example.com/path%23frag',     'Encoded # in path, no fragment',       'syntax', TRUE, FALSE),
(202, 2, 'http://example.com/path#frag',       'Literal # starts fragment',            'syntax', FALSE, FALSE),

-- Group 203: Encoded ampersand vs query separator  (NOT equivalent)
(203, 1, 'http://example.com/path?a=1%26b=2', 'Encoded & – single param "a=1&b=2"',  'syntax', TRUE, FALSE),
(203, 2, 'http://example.com/path?a=1&b=2',   'Literal & – two params "a=1" "b=2"',  'syntax', FALSE, FALSE),

-- Group 204: Encoded equals vs key-value separator  (NOT equivalent)
(204, 1, 'http://example.com/path?a%3D1=x',   'Encoded = – key is "a=1"',            'syntax', TRUE, FALSE),
(204, 2, 'http://example.com/path?a=1=x',     'Literal = – key "a" value "1=x"',     'syntax', FALSE, FALSE),

-- Group 205: Encoded @ vs userinfo delimiter  (NOT equivalent)
(205, 1, 'http://user%40name@example.com',     'Encoded @ in userinfo, host is example.com', 'syntax', TRUE, FALSE),
(205, 2, 'http://user@name@example.com',       'Ambiguous – two literal @ signs',            'syntax', FALSE, FALSE),

-- Group 206: Encoded colon vs port/password separator  (NOT equivalent)
(206, 1, 'http://user%3Aname@example.com',     'Encoded colon in username',            'syntax', TRUE, FALSE),
(206, 2, 'http://user:name@example.com',       'Literal colon – username:password',    'syntax', FALSE, FALSE),

-- =============================================================================
-- 10. QUERY STRING ENCODING EQUIVALENCES
-- =============================================================================

-- Group 210: Plus vs %20 in query (application-level equivalence)
(210, 1, 'http://example.com/search?q=hello%20world',  'Percent-encoded space (canonical)',   'protocol', TRUE, TRUE),
(210, 2, 'http://example.com/search?q=hello+world',    'Plus-as-space (form encoding)',       'protocol', FALSE, TRUE),

-- Group 211: Unreserved chars in query key
(211, 1, 'http://example.com/path?my-key=value',       'Literal hyphen in key (canonical)',    'syntax', TRUE, TRUE),
(211, 2, 'http://example.com/path?my%2Dkey=value',     'Encoded hyphen in key',                'syntax', FALSE, TRUE),

-- Group 212: Unreserved chars in query value
(212, 1, 'http://example.com/path?key=val_ue',         'Literal underscore in value (canonical)', 'syntax', TRUE, TRUE),
(212, 2, 'http://example.com/path?key=val%5Fue',       'Encoded underscore in value',              'syntax', FALSE, TRUE),

-- =============================================================================
-- 11. FRAGMENT ENCODING EQUIVALENCES
-- =============================================================================

-- Group 220: Unreserved in fragment
(220, 1, 'http://example.com/path#section-1',          'Literal hyphen (canonical)',            'syntax', TRUE, TRUE),
(220, 2, 'http://example.com/path#section%2D1',        'Encoded hyphen in fragment',            'syntax', FALSE, TRUE),

-- Group 221: Encoded vs literal tilde in fragment
(221, 1, 'http://example.com/path#~intro',             'Literal tilde (canonical)',             'syntax', TRUE, TRUE),
(221, 2, 'http://example.com/path#%7Eintro',           'Encoded tilde in fragment',             'syntax', FALSE, TRUE),

-- =============================================================================
-- 12. USERINFO ENCODING EQUIVALENCES
-- =============================================================================

-- Group 230: Unreserved in username
(230, 1, 'http://my.user@example.com',                 'Literal period in username (canonical)', 'syntax', TRUE, TRUE),
(230, 2, 'http://my%2Euser@example.com',               'Encoded period in username',              'syntax', FALSE, TRUE),

-- Group 231: Unreserved in password
(231, 1, 'http://user:p~ss@example.com',               'Literal tilde in password (canonical)',   'syntax', TRUE, TRUE),
(231, 2, 'http://user:p%7Ess@example.com',             'Encoded tilde in password',                'syntax', FALSE, TRUE),

-- =============================================================================
-- 13. PROTOCOL-LEVEL EQUIVALENCES  (application / query-order)
-- =============================================================================

-- Group 240: Query parameter order (protocol-level, not RFC-mandated)
(240, 1, 'http://example.com/path?a=1&b=2',            'Original order',                       'protocol', TRUE, TRUE),
(240, 2, 'http://example.com/path?b=2&a=1',            'Reversed order',                       'protocol', FALSE, TRUE),

-- Group 241: Query parameter order – more params
(241, 1, 'http://example.com/search?page=1&q=test&sort=asc',  'Original order',               'protocol', TRUE, TRUE),
(241, 2, 'http://example.com/search?q=test&page=1&sort=asc',  'Reordered',                    'protocol', FALSE, TRUE),
(241, 3, 'http://example.com/search?sort=asc&q=test&page=1',  'Reverse order',                'protocol', FALSE, TRUE),

-- Group 242: Trailing ampersand / empty params (protocol-level)
(242, 1, 'http://example.com/path?a=1&b=2',            'Clean query (canonical)',               'protocol', TRUE, TRUE),
(242, 2, 'http://example.com/path?a=1&b=2&',           'Trailing ampersand',                    'protocol', FALSE, TRUE),
(242, 3, 'http://example.com/path?&a=1&b=2',           'Leading ampersand',                     'protocol', FALSE, TRUE),
(242, 4, 'http://example.com/path?a=1&&b=2',           'Double ampersand',                      'protocol', FALSE, TRUE),

-- =============================================================================
-- 14. NEGATIVE TESTS  (look similar but are NOT equivalent)
-- =============================================================================
-- These verify the parser does NOT incorrectly treat these as equivalent.
-- Each row is its own group – none should match any other.

-- Group 300: Path case sensitivity
(300, 1, 'http://example.com/Path',                    'Uppercase P – distinct',                'syntax', TRUE, FALSE),
(300, 2, 'http://example.com/path',                    'Lowercase p – distinct',                'syntax', FALSE, FALSE),

-- Group 301: Query case sensitivity
(301, 1, 'http://example.com/?Key=Value',              'Mixed case query – distinct',           'syntax', TRUE, FALSE),
(301, 2, 'http://example.com/?key=value',              'Lowercase query – distinct',            'syntax', FALSE, FALSE),

-- Group 302: Fragment case sensitivity
(302, 1, 'http://example.com/#Section',                'Uppercase fragment – distinct',         'syntax', TRUE, FALSE),
(302, 2, 'http://example.com/#section',                'Lowercase fragment – distinct',         'syntax', FALSE, FALSE),

-- Group 303: Non-default port must not be stripped
(303, 1, 'http://example.com:8080/path',               'Port 8080 present – distinct',          'scheme', TRUE, FALSE),
(303, 2, 'http://example.com/path',                    'No port – distinct',                    'scheme', FALSE, FALSE),

-- Group 304: Encoded reserved vs literal (slash)
(304, 1, 'http://example.com/a/b',                     'Two segments – distinct',               'syntax', TRUE, FALSE),
(304, 2, 'http://example.com/a%2Fb',                   'One segment with encoded / – distinct', 'syntax', FALSE, FALSE),

-- Group 305: Trailing slash significance
(305, 1, 'http://example.com/path',                    'No trailing slash – distinct',          'syntax', TRUE, FALSE),
(305, 2, 'http://example.com/path/',                   'Trailing slash – distinct',             'syntax', FALSE, FALSE),

-- Group 306: Different schemes
(306, 1, 'http://example.com/path',                    'HTTP scheme – distinct',                'syntax', TRUE, FALSE),
(306, 2, 'https://example.com/path',                   'HTTPS scheme – distinct',               'syntax', FALSE, FALSE),

-- Group 307: Userinfo presence
(307, 1, 'http://example.com/path',                    'No userinfo – distinct',                'syntax', TRUE, FALSE),
(307, 2, 'http://user@example.com/path',               'Has userinfo – distinct',               'syntax', FALSE, FALSE),

-- Group 308: Query presence
(308, 1, 'http://example.com/path',                    'No query – distinct',                   'syntax', TRUE, FALSE),
(308, 2, 'http://example.com/path?',                   'Empty query – distinct',                'syntax', FALSE, FALSE),

-- Group 309: Fragment presence
(309, 1, 'http://example.com/path',                    'No fragment – distinct',                'syntax', TRUE, FALSE),
(309, 2, 'http://example.com/path#',                   'Empty fragment – distinct',             'syntax', FALSE, FALSE),

-- Group 310: Duplicate query keys – order matters
(310, 1, 'http://example.com/path?a=1&a=2',           'a=1 first – distinct',                  'syntax', TRUE, FALSE),
(310, 2, 'http://example.com/path?a=2&a=1',           'a=2 first – distinct',                  'syntax', FALSE, FALSE),

-- =============================================================================
-- 15. REAL-WORLD EQUIVALENCE SCENARIOS
-- =============================================================================

-- Group 400: Google search URL normalization
(400, 1, 'https://www.google.com/search?q=uri+parser',                                     'Canonical form',            'scheme', TRUE, TRUE),
(400, 2, 'HTTPS://WWW.GOOGLE.COM:443/search?q=uri+parser',                                 'Uppercase + default port',  'scheme', FALSE, TRUE),
(400, 3, 'https://www.google.com:443/./search?q=uri+parser',                               'Port + dot segment',        'scheme', FALSE, TRUE),

-- Group 401: GitHub URL normalization
(401, 1, 'https://github.com/user/repo',                                                    'Canonical form',            'scheme', TRUE, TRUE),
(401, 2, 'HTTPS://GITHUB.COM:443/user/repo',                                                'Uppercase + default port',  'scheme', FALSE, TRUE),
(401, 3, 'https://GitHub.Com/user/repo',                                                     'Mixed case host',           'scheme', FALSE, TRUE),

-- Group 402: API endpoint normalization
(402, 1, 'https://api.example.com/v1/users/42',                                              'Canonical form',           'scheme', TRUE, TRUE),
(402, 2, 'HTTPS://API.EXAMPLE.COM:443/./v1/./users/./42',                                   'All normalizations',       'scheme', FALSE, TRUE),
(402, 3, 'https://api.example.com:443/v1/users/42',                                          'Just default port',        'scheme', FALSE, TRUE),

-- Group 403: Database connection string normalization
(403, 1, 'postgres://user:pass@db.example.com:5432/mydb',                                   'Canonical form',            'syntax', TRUE, TRUE),
(403, 2, 'POSTGRES://user:pass@DB.EXAMPLE.COM:5432/mydb',                                   'Uppercase scheme+host',     'syntax', FALSE, TRUE),
(403, 3, 'postgres://user:pass@Db.Example.Com:5432/mydb',                                   'Mixed case host',           'syntax', FALSE, TRUE),

-- Group 404: CDN asset URL with tilde
(404, 1, 'https://cdn.example.com/~assets/app.js',                                          'Literal tilde (canonical)', 'scheme', TRUE, TRUE),
(404, 2, 'HTTPS://CDN.EXAMPLE.COM:443/%7Eassets/app.js',                                    'All normalizations',        'scheme', FALSE, TRUE),
(404, 3, 'https://cdn.example.com/%7eassets/app.js',                                         'Encoded tilde lowercase',   'scheme', FALSE, TRUE),

-- =============================================================================
-- 16. FQDN TRAILING DOT  (DNS-level host equivalence)
-- =============================================================================

-- Group 410: Trailing dot is the fully qualified form of the same host
(410, 1, 'http://example.com/path',                'No trailing dot (canonical)',          'protocol', TRUE, TRUE),
(410, 2, 'http://example.com./path',               'Trailing dot (FQDN)',                 'protocol', FALSE, TRUE),

-- Group 411: Trailing dot with subdomain
(411, 1, 'https://www.example.com/',               'No trailing dot (canonical)',          'protocol', TRUE, TRUE),
(411, 2, 'https://www.example.com./',              'Trailing dot (FQDN)',                 'protocol', FALSE, TRUE),

-- Group 412: Trailing dot with port
(412, 1, 'http://example.com:8080/path',           'No trailing dot (canonical)',          'protocol', TRUE, TRUE),
(412, 2, 'http://example.com.:8080/path',          'Trailing dot with port',              'protocol', FALSE, TRUE),

-- =============================================================================
-- 17. PERCENT-ENCODED HOST  (unreserved chars in reg-name)
-- =============================================================================

-- Group 420: Encoded unreserved letters in host
(420, 1, 'http://example.com/path',                'Literal host (canonical)',             'syntax', TRUE, TRUE),
(420, 2, 'http://exam%70le.com/path',              'Encoded p in host',                   'syntax', FALSE, TRUE),
(420, 3, 'http://%65%78%61%6D%70%6C%65.com/path',  'Fully encoded host label',            'syntax', FALSE, TRUE),

-- Group 421: Encoded hyphen in host
(421, 1, 'http://my-host.example.com/',            'Literal hyphen (canonical)',           'syntax', TRUE, TRUE),
(421, 2, 'http://my%2Dhost.example.com/',          'Encoded hyphen in host',              'syntax', FALSE, TRUE),

-- =============================================================================
-- 18. PUNYCODE / IDN EQUIVALENCE
-- =============================================================================

-- Group 430: Punycode vs Unicode domain (protocol-level, IRI-to-URI mapping)
(430, 1, 'http://xn--bcher-kva.example.com/',      'Punycode form (canonical URI)',       'protocol', TRUE, TRUE),
(430, 2, 'http://bücher.example.com/',              'Unicode form (IRI)',                  'protocol', FALSE, TRUE),

-- Group 431: Punycode vs Unicode – Japanese
(431, 1, 'http://xn--r8jz45g.jp/',                 'Punycode form (canonical URI)',       'protocol', TRUE, TRUE),
(431, 2, 'http://亀.jp/',                            'Unicode form (IRI)',                  'protocol', FALSE, TRUE),

-- =============================================================================
-- 19. IPv4-MAPPED IPv6 vs PLAIN IPv4
-- =============================================================================

-- Group 440: IPv4-mapped IPv6 address
(440, 1, 'http://192.168.1.1/path',                'Plain IPv4 (canonical)',               'protocol', TRUE, TRUE),
(440, 2, 'http://[::ffff:192.168.1.1]/path',       'IPv4-mapped IPv6',                    'protocol', FALSE, TRUE),

-- Group 441: Loopback forms
(441, 1, 'http://127.0.0.1/',                      'IPv4 loopback (canonical)',            'protocol', TRUE, TRUE),
(441, 2, 'http://[::ffff:127.0.0.1]/',             'IPv4-mapped IPv6 loopback',           'protocol', FALSE, TRUE),
(441, 3, 'http://[::1]/',                           'IPv6 loopback',                       'protocol', FALSE, TRUE),
(441, 4, 'http://localhost/',                        'Hostname loopback',                   'protocol', FALSE, TRUE),

-- =============================================================================
-- 20. PORT NORMALIZATION EDGE CASES
-- =============================================================================

-- Group 450: Leading zeros in port (non-default port)
(450, 1, 'http://example.com:8080/path',           'Port 8080 (canonical)',                'scheme', TRUE, TRUE),
(450, 2, 'http://example.com:08080/path',          'Leading zero port 08080',             'scheme', FALSE, TRUE),

-- Group 451: Leading zeros on default port (also tests default port removal)
(451, 1, 'http://example.com/path',                'No port (canonical)',                  'scheme', TRUE, TRUE),
(451, 2, 'http://example.com:80/path',             'Default port 80',                     'scheme', FALSE, TRUE),
(451, 3, 'http://example.com:080/path',            'Leading zero + default port 080',     'scheme', FALSE, TRUE),
(451, 4, 'http://example.com:0080/path',           'Two leading zeros + default port',    'scheme', FALSE, TRUE),

-- =============================================================================
-- 21. FILE URI EQUIVALENCES
-- =============================================================================

-- Group 460: Drive letter case (Windows file URIs)
(460, 1, 'file:///C:/Users/file.txt',              'Uppercase drive (canonical)',           'scheme', TRUE, TRUE),
(460, 2, 'file:///c:/Users/file.txt',              'Lowercase drive letter',               'scheme', FALSE, TRUE),

-- Group 461: Pipe vs colon for drive letter (legacy)
(461, 1, 'file:///C:/path/file.txt',               'Colon form (canonical)',                'protocol', TRUE, TRUE),
(461, 2, 'file:///C|/path/file.txt',               'Pipe form (legacy)',                    'protocol', FALSE, TRUE),

-- Group 462: File URI localhost vs empty authority (RFC 8089)
(462, 1, 'file:///path/to/file',                   'Empty authority (canonical)',            'scheme', TRUE, TRUE),
(462, 2, 'file://localhost/path/to/file',          'Explicit localhost authority',           'scheme', FALSE, TRUE),

-- =============================================================================
-- 22. EMPTY / ABSENT USERINFO
-- =============================================================================

-- Group 470: Empty userinfo (@) vs no userinfo
-- RFC 3986 §6.2.3: don't remove delimiters unless the scheme licenses it
(470, 1, 'http://example.com/path',               'No userinfo (canonical)',                'scheme', TRUE, TRUE),
(470, 2, 'http://@example.com/path',              'Empty userinfo (bare @)',               'scheme', FALSE, TRUE),

-- Group 471: Empty userinfo with empty password
(471, 1, 'http://example.com/',                   'No userinfo (canonical)',                'scheme', TRUE, TRUE),
(471, 2, 'http://:@example.com/',                 'Empty user and empty pass',             'scheme', FALSE, TRUE),

-- =============================================================================
-- 23. UNICODE NORMALIZATION  (NFC vs NFD)
-- =============================================================================

-- Group 480: Precomposed vs decomposed é  (protocol-level / IRI)
(480, 1, 'http://example.com/caf%C3%A9',          'Precomposed é NFC (canonical)',          'protocol', TRUE, TRUE),
(480, 2, 'http://example.com/caf%65%CC%81',       'Decomposed e + combining acute NFD',    'protocol', FALSE, TRUE),

-- Group 481: Precomposed vs decomposed ñ
(481, 1, 'http://example.com/%C3%B1',             'Precomposed ñ NFC (canonical)',          'protocol', TRUE, TRUE),
(481, 2, 'http://example.com/%6E%CC%83',          'Decomposed n + combining tilde NFD',    'protocol', FALSE, TRUE),

-- =============================================================================
-- 24. PLUS IN PATH vs QUERY  (plus is NOT a space in path)
-- =============================================================================

-- Group 490: Plus in path is literal, not a space  (NOT equivalent)
(490, 1, 'http://example.com/a+b',                'Plus in path – literal +',              'syntax', TRUE, FALSE),
(490, 2, 'http://example.com/a%20b',              'Encoded space in path – literal space', 'syntax', FALSE, FALSE),

-- Group 491: Encoded sub-delimiter vs literal  (+ is a sub-delimiter, not unreserved)
-- Per §6.2.2.2, only unreserved chars are decoded during syntax normalization.
-- %2B → + decoding is protocol-level since + is reserved (sub-delims).
(491, 1, 'http://example.com/a+b',                'Literal + in path (canonical)',         'protocol', TRUE, TRUE),
(491, 2, 'http://example.com/a%2Bb',              'Encoded + in path',                     'protocol', FALSE, TRUE),

-- Group 492: Plus in query IS space (protocol-level, application/x-www-form-urlencoded)
(492, 1, 'http://example.com/?q=a%20b',           'Percent-encoded space in query',        'protocol', TRUE, TRUE),
(492, 2, 'http://example.com/?q=a+b',             'Plus-as-space in query (form encoded)','protocol', FALSE, TRUE),

-- =============================================================================
-- 25. DOT SEGMENTS ABOVE ROOT  (RFC 3986 Section 5.4)
-- =============================================================================

-- Group 500: Dot segments that try to go above root
(500, 1, 'http://example.com/',                    'Root (canonical)',                      'syntax', TRUE, TRUE),
(500, 2, 'http://example.com/../',                 'Parent of root resolves to root',      'syntax', FALSE, TRUE),
(500, 3, 'http://example.com/../../',              'Double parent of root resolves to root','syntax', FALSE, TRUE),

-- Group 501: Above root then descend
(501, 1, 'http://example.com/a',                   'Simple path (canonical)',              'syntax', TRUE, TRUE),
(501, 2, 'http://example.com/../../a',             'Above root + descend',                'syntax', FALSE, TRUE),
(501, 3, 'http://example.com/../a',                'Parent of root + descend',            'syntax', FALSE, TRUE),

-- =============================================================================
-- 26. IPv6 COMPRESSION AMBIGUITY
-- =============================================================================

-- Group 510: Address with multiple compressible runs – leftmost wins (RFC 5952)
(510, 1, 'http://[2001:db8::1:0:0:1]/',            'Compress leftmost run (canonical)',   'scheme', TRUE, TRUE),
(510, 2, 'http://[2001:db8:0:0:1:0:0:1]/',         'Fully expanded',                     'scheme', FALSE, TRUE),
(510, 3, 'http://[2001:0db8:0000:0000:0001:0000:0000:0001]/',  'Fully padded',           'scheme', FALSE, TRUE),

-- Group 511: Prefer compressing the longest run (RFC 5952)
(511, 1, 'http://[2001:db8:1::1]/',                 'Compress longest run (canonical)',    'scheme', TRUE, TRUE),
(511, 2, 'http://[2001:db8:1:0:0:0:0:1]/',          'Expanded form',                     'scheme', FALSE, TRUE),
(511, 3, 'http://[2001:0db8:0001:0000:0000:0000:0000:0001]/', 'Fully padded',            'scheme', FALSE, TRUE),

-- =============================================================================
-- 27. ADDITIONAL DEFAULT PORTS  (scheme-based)
-- =============================================================================

-- Group 520: Telnet default port (23)
(520, 1, 'telnet://example.com',                    'No port (canonical)',                 'scheme', TRUE, TRUE),
(520, 2, 'telnet://example.com:23',                 'Explicit default port 23',            'scheme', FALSE, TRUE),

-- Group 521: LDAP default port (389)
(521, 1, 'ldap://example.com/dc=example,dc=com',   'No port (canonical)',                 'scheme', TRUE, TRUE),
(521, 2, 'ldap://example.com:389/dc=example,dc=com','Explicit default port 389',          'scheme', FALSE, TRUE),

-- Group 522: MySQL default port (3306)
(522, 1, 'mysql://root@localhost/mydb',             'No port (canonical)',                 'scheme', TRUE, TRUE),
(522, 2, 'mysql://root@localhost:3306/mydb',        'Explicit default port 3306',          'scheme', FALSE, TRUE),

-- Group 523: PostgreSQL default port (5432)
(523, 1, 'postgres://user@localhost/mydb',          'No port (canonical)',                 'scheme', TRUE, TRUE),
(523, 2, 'postgres://user@localhost:5432/mydb',     'Explicit default port 5432',          'scheme', FALSE, TRUE),

-- Group 524: Redis default port (6379)
(524, 1, 'redis://localhost/0',                     'No port (canonical)',                 'scheme', TRUE, TRUE),
(524, 2, 'redis://localhost:6379/0',                'Explicit default port 6379',          'scheme', FALSE, TRUE),

-- =============================================================================
-- 28. DOUBLE / TRIPLE ENCODING  (negative – must NOT normalize)
-- =============================================================================

-- Group 530: Double encoding is NOT equivalent to single encoding
(530, 1, 'http://example.com/a%20b',               'Single-encoded space',                 'syntax', TRUE, FALSE),
(530, 2, 'http://example.com/a%2520b',             'Double-encoded – literal %20 in path', 'syntax', FALSE, FALSE),

-- Group 531: Double-encoded slash
(531, 1, 'http://example.com/a%2Fb',               'Single-encoded slash – one segment',   'syntax', TRUE, FALSE),
(531, 2, 'http://example.com/a%252Fb',             'Double-encoded – literal %2F in path', 'syntax', FALSE, FALSE),

-- Group 532: Triple-encoded percent
(532, 1, 'http://example.com/a%25b',               'Single-encoded % – literal %b',        'syntax', TRUE, FALSE),
(532, 2, 'http://example.com/a%2525b',             'Double-encoded % – literal %25b',      'syntax', FALSE, FALSE),

-- =============================================================================
-- 29. MULTIPLE SLASHES IN PATH  (NOT equivalent per RFC)
-- =============================================================================
-- Some servers treat //a as /a, but per RFC 3986 these are distinct segments.

-- Group 540: Single vs double slash  (NOT equivalent)
(540, 1, 'http://example.com/a/b',                 'Single slash – two segments',          'syntax', TRUE, FALSE),
(540, 2, 'http://example.com/a//b',                'Double slash – empty segment between', 'syntax', FALSE, FALSE),

-- Group 541: Triple slash vs single  (NOT equivalent)
(541, 1, 'http://example.com/a/b/c',               'Normal path',                         'syntax', TRUE, FALSE),
(541, 2, 'http://example.com///a///b///c',          'Triple slashes throughout',            'syntax', FALSE, FALSE),

-- =============================================================================
-- 30. ADDITIONAL NEGATIVE TESTS
-- =============================================================================

-- Group 550: Empty query vs absent query vs empty fragment
(550, 1, 'http://example.com/path',                'No query, no fragment',                'syntax', TRUE, FALSE),
(550, 2, 'http://example.com/path?',               'Empty query present',                  'syntax', FALSE, FALSE),
(550, 3, 'http://example.com/path#',               'Empty fragment present',               'syntax', FALSE, FALSE),
(550, 4, 'http://example.com/path?#',              'Both empty query and fragment',        'syntax', FALSE, FALSE),

-- Group 551: Different ports (none should match)
(551, 1, 'http://example.com:80/path',             'Port 80',                              'syntax', TRUE, FALSE),
(551, 2, 'http://example.com:8080/path',           'Port 8080',                            'syntax', FALSE, FALSE),
(551, 3, 'http://example.com:443/path',            'Port 443',                             'syntax', FALSE, FALSE),

-- Group 552: Userinfo differences (none should match)
(552, 1, 'http://user@example.com/',               'User only',                            'syntax', TRUE, FALSE),
(552, 2, 'http://user:pass@example.com/',          'User with password',                   'syntax', FALSE, FALSE),
(552, 3, 'http://user:@example.com/',              'User with empty password',             'syntax', FALSE, FALSE),
(552, 4, 'http://other@example.com/',              'Different username',                   'syntax', FALSE, FALSE),

-- Group 553: Encoded reserved char in query vs literal  (NOT equivalent)
(553, 1, 'http://example.com/?key=a%23b',          'Encoded # in query value',             'syntax', TRUE, FALSE),
(553, 2, 'http://example.com/?key=a#b',            'Literal # starts fragment',            'syntax', FALSE, FALSE),

-- Group 554: Same path, different query values
(554, 1, 'http://example.com/path?a=1',            'Query a=1',                            'syntax', TRUE, FALSE),
(554, 2, 'http://example.com/path?a=2',            'Query a=2',                            'syntax', FALSE, FALSE),

-- Group 555: Same path, different fragments
(555, 1, 'http://example.com/path#one',            'Fragment one',                         'syntax', TRUE, FALSE),
(555, 2, 'http://example.com/path#two',            'Fragment two',                         'syntax', FALSE, FALSE),

-- Group 556: Scheme can NOT be percent-encoded  (NOT equivalent)
(556, 1, 'http://example.com/',                    'Normal scheme',                        'syntax', TRUE, FALSE),
(556, 2, '%68ttp://example.com/',                  'Percent-encoded scheme – not a URI',   'syntax', FALSE, FALSE),

-- Group 557: Windows backslash vs forward slash  (NOT equivalent per RFC)
(557, 1, 'file:///C:/path/file.txt',               'Forward slashes',                      'syntax', TRUE, FALSE),
(557, 2, 'file:///C:\path\file.txt',               'Backslashes (not valid URI separators)','syntax', FALSE, FALSE),

-- Group 558: Port 0 is NOT equivalent to absent port
(558, 1, 'http://example.com/path',                'No port',                              'syntax', TRUE, FALSE),
(558, 2, 'http://example.com:0/path',              'Port zero',                            'syntax', FALSE, FALSE),

-- =============================================================================
-- 31. ADDITIONAL REAL-WORLD EQUIVALENCES
-- =============================================================================

-- Group 600: S3 URI normalization
(600, 1, 'https://my-bucket.s3.amazonaws.com/key',                        'Virtual-hosted style (canonical)',  'protocol', TRUE, TRUE),
(600, 2, 'https://s3.amazonaws.com/my-bucket/key',                        'Path style',                        'protocol', FALSE, TRUE),
(600, 3, 's3://my-bucket/key',                                            'S3 scheme shorthand',               'protocol', FALSE, TRUE),

-- Group 601: Docker registry tag vs digest (NOT equivalent)
(601, 1, 'docker://registry.example.com/image:latest',                    'Tag latest',                        'syntax', TRUE, FALSE),
(601, 2, 'docker://registry.example.com/image:v1.0',                      'Tag v1.0 – distinct',               'syntax', FALSE, FALSE),

-- Group 602: Kubernetes API normalization
(602, 1, 'https://k8s.example.com/api/v1/pods',                           'Canonical',                        'scheme', TRUE, TRUE),
(602, 2, 'HTTPS://K8S.EXAMPLE.COM:443/api/v1/pods',                       'Uppercase + default port',         'scheme', FALSE, TRUE),
(602, 3, 'https://K8S.Example.Com:443/./api/./v1/./pods',                 'All normalizations',               'scheme', FALSE, TRUE),

-- Group 603: Database connection – full normalization
(603, 1, 'mysql://root:pass@db.example.com/mydb?charset=utf8mb4',         'Canonical',                        'scheme', TRUE, TRUE),
(603, 2, 'MYSQL://root:pass@DB.EXAMPLE.COM:3306/mydb?charset=utf8mb4',    'Uppercase + default port',         'scheme', FALSE, TRUE),
(603, 3, 'mysql://root:pass@db.example.com:3306/./mydb?charset=utf8mb4',  'Default port + dot segment',       'scheme', FALSE, TRUE),

-- =============================================================================
-- 32. RFC 3986 EXPLICIT EXAMPLES
-- =============================================================================

-- Group 610: RFC 3986 §6.2.3 – Four equivalent HTTP URIs (the RFC's canonical example)
(610, 1, 'http://example.com/',                    'Normalized form (canonical)',           'scheme', TRUE, TRUE),
(610, 2, 'http://example.com',                     'No trailing slash',                    'scheme', FALSE, TRUE),
(610, 3, 'http://example.com:/',                   'Empty port with trailing slash',       'scheme', FALSE, TRUE),
(610, 4, 'http://example.com:80/',                 'Default port with trailing slash',     'scheme', FALSE, TRUE),

-- Group 611: RFC 3986 §6.2.2 – Syntax-based normalization example
-- Combines: scheme case, dot-segment removal, unreserved decoding (%63→c),
-- hex case normalization (%7b→%7B), reserved chars stay encoded (%7B, %7D)
(611, 1, 'example://a/b/c/%7Bfoo%7D',                       'Canonical form',               'syntax', TRUE, TRUE),
(611, 2, 'eXAMPLE://a/./b/../b/%63/%7bfoo%7d',              'RFC example (all normalizations)', 'syntax', FALSE, TRUE),

-- =============================================================================
-- 33. SUB-DELIMITER / PCHAR ENCODING IN PATH  (protocol-level)
-- =============================================================================
-- Sub-delimiters (reserved) and ":" / "@" are allowed literally in pchar.
-- Encoding them does not change structure in path context, but per §6.2.2.2
-- only unreserved chars are decoded during syntax normalization. Decoding
-- reserved chars in path is protocol-level.

-- Group 620: Exclamation mark (sub-delim)
(620, 1, 'http://example.com/a!b',                'Literal ! in path (canonical)',         'protocol', TRUE, TRUE),
(620, 2, 'http://example.com/a%21b',              'Encoded ! in path',                     'protocol', FALSE, TRUE),

-- Group 621: Comma (sub-delim)
(621, 1, 'http://example.com/a,b',                'Literal , in path (canonical)',         'protocol', TRUE, TRUE),
(621, 2, 'http://example.com/a%2Cb',              'Encoded , in path',                     'protocol', FALSE, TRUE),

-- Group 622: Semicolon (sub-delim)
(622, 1, 'http://example.com/a;b',                'Literal ; in path (canonical)',         'protocol', TRUE, TRUE),
(622, 2, 'http://example.com/a%3Bb',              'Encoded ; in path',                     'protocol', FALSE, TRUE),

-- Group 623: Colon (allowed in pchar)
(623, 1, 'http://example.com/a:b',                'Literal : in path (canonical)',         'protocol', TRUE, TRUE),
(623, 2, 'http://example.com/a%3Ab',              'Encoded : in path',                     'protocol', FALSE, TRUE),

-- Group 624: At-sign (allowed in pchar)
(624, 1, 'http://example.com/user@host',           'Literal @ in path (canonical)',        'protocol', TRUE, TRUE),
(624, 2, 'http://example.com/user%40host',         'Encoded @ in path',                    'protocol', FALSE, TRUE),

-- Group 625: Equals (sub-delim)
(625, 1, 'http://example.com/a=b',                'Literal = in path (canonical)',         'protocol', TRUE, TRUE),
(625, 2, 'http://example.com/a%3Db',              'Encoded = in path',                     'protocol', FALSE, TRUE),

-- Group 626: Dollar sign (sub-delim)
(626, 1, 'http://example.com/a$b',                'Literal $ in path (canonical)',         'protocol', TRUE, TRUE),
(626, 2, 'http://example.com/a%24b',              'Encoded $ in path',                     'protocol', FALSE, TRUE),

-- Group 627: Parentheses (sub-delims)
(627, 1, 'http://example.com/f(x)',               'Literal parens in path (canonical)',    'protocol', TRUE, TRUE),
(627, 2, 'http://example.com/f%28x%29',           'Encoded parens in path',                'protocol', FALSE, TRUE),

-- Group 628: Asterisk (sub-delim)
(628, 1, 'http://example.com/a*b',                'Literal * in path (canonical)',         'protocol', TRUE, TRUE),
(628, 2, 'http://example.com/a%2Ab',              'Encoded * in path',                     'protocol', FALSE, TRUE),

-- =============================================================================
-- 34. MULTIPLE UNRESERVED DECODINGS IN SAME SEGMENT
-- =============================================================================

-- Group 630: All encoded unreserved in one segment
(630, 1, 'http://example.com/abc',                                  'All literal (canonical)',          'syntax', TRUE, TRUE),
(630, 2, 'http://example.com/%61%62%63',                            'All three letters encoded',        'syntax', FALSE, TRUE),
(630, 3, 'http://example.com/%61b%63',                              'First and last encoded',           'syntax', FALSE, TRUE),

-- Group 631: Multiple unreserved types decoded together
(631, 1, 'http://example.com/a-b_c',                                'All literal (canonical)',          'syntax', TRUE, TRUE),
(631, 2, 'http://example.com/a%2Db%5Fc',                            'Hyphen and underscore encoded',   'syntax', FALSE, TRUE),
(631, 3, 'http://example.com/%61%2D%62%5F%63',                      'All chars encoded',               'syntax', FALSE, TRUE),

-- Group 632: Unreserved decoding in query key AND value simultaneously
(632, 1, 'http://example.com/path?a-b=c_d',                         'All literal (canonical)',         'syntax', TRUE, TRUE),
(632, 2, 'http://example.com/path?a%2Db=c%5Fd',                     'Key and value both encoded',     'syntax', FALSE, TRUE),

-- =============================================================================
-- 35. COMBINED NORMALIZATIONS NOT YET PAIRED
-- =============================================================================

-- Group 640: IPv6 case + compression combined
(640, 1, 'http://[2001:db8::1]/',                                    'Lowercase compressed (canonical)', 'scheme', TRUE, TRUE),
(640, 2, 'http://[2001:DB8:0:0:0:0:0:1]/',                          'Uppercase expanded',               'scheme', FALSE, TRUE),
(640, 3, 'http://[2001:0DB8:0000:0000:0000:0000:0000:0001]/',       'Uppercase fully padded',           'scheme', FALSE, TRUE),

-- Group 641: Host percent-encoding + host case
(641, 1, 'http://example.com/path',                                  'Canonical',                       'syntax', TRUE, TRUE),
(641, 2, 'http://EXAM%70LE.COM/path',                                'Uppercase + encoded p in host',   'syntax', FALSE, TRUE),
(641, 3, 'HTTP://%45xample.%43om/path',                              'Scheme case + encoded E and C',   'syntax', FALSE, TRUE),

-- Group 642: FQDN trailing dot + default port + case (all three combined)
(642, 1, 'http://example.com/',                                      'Canonical',                       'protocol', TRUE, TRUE),
(642, 2, 'HTTP://EXAMPLE.COM.:80/',                                  'FQDN + default port + uppercase', 'protocol', FALSE, TRUE),
(642, 3, 'Http://Example.Com.:80',                                   'FQDN + port + mixed case + no slash', 'protocol', FALSE, TRUE),

-- Group 643: Unreserved decoding + dot segments + case (in one URI)
(643, 1, 'http://example.com/a/b',                                   'Canonical',                       'syntax', TRUE, TRUE),
(643, 2, 'HTTP://EXAMPLE.COM/%61/./b',                               'Case + encoded a + dot segment',  'syntax', FALSE, TRUE),
(643, 3, 'Http://Example.Com/a/c/../%62',                            'Case + parent ref + encoded b',   'syntax', FALSE, TRUE),

-- =============================================================================
-- 36. IPv4-IN-IPv6 HEX vs DOTTED NOTATION
-- =============================================================================

-- Group 650: Pure hex vs dotted dual-form for IPv4-mapped address
(650, 1, 'http://[::ffff:192.168.1.1]/',                             'IPv4-dotted form (canonical)',    'scheme', TRUE, TRUE),
(650, 2, 'http://[::ffff:c0a8:0101]/',                               'Pure hex form',                   'scheme', FALSE, TRUE),

-- Group 651: Loopback in hex vs dotted
(651, 1, 'http://[::ffff:127.0.0.1]/',                               'Dotted loopback (canonical)',     'scheme', TRUE, TRUE),
(651, 2, 'http://[::ffff:7f00:0001]/',                                'Hex loopback',                    'scheme', FALSE, TRUE),

-- =============================================================================
-- 37. EMPTY PATH NORMALIZATION FOR NON-HTTP SCHEMES
-- =============================================================================

-- Group 660: FTP empty path vs root slash
(660, 1, 'ftp://example.com/',                     'Trailing slash (canonical)',            'scheme', TRUE, TRUE),
(660, 2, 'ftp://example.com',                      'No trailing slash',                     'scheme', FALSE, TRUE),

-- Group 661: WebSocket empty path vs root slash
(661, 1, 'ws://example.com/',                      'Trailing slash (canonical)',             'scheme', TRUE, TRUE),
(661, 2, 'ws://example.com',                       'No trailing slash',                      'scheme', FALSE, TRUE),

-- Group 662: HTTPS empty path vs root slash (supplements Group 50 for HTTP)
(662, 1, 'https://example.com/',                   'Trailing slash (canonical)',             'scheme', TRUE, TRUE),
(662, 2, 'https://example.com',                    'No trailing slash',                      'scheme', FALSE, TRUE),

-- =============================================================================
-- 38. ENCODED GEN-DELIMS HARMLESS IN PATH CONTEXT
-- =============================================================================
-- ":" and "@" are gen-delims but also allowed literally in pchar.
-- In path context, encoding them doesn't change structure. This is distinct
-- from Groups 200-206 where the encoded char WOULD change structure if decoded.
-- These are covered individually in Groups 623-624, but here we test them
-- in combination and in multi-segment paths.

-- Group 670: Mixed encoded pchar-safe gen-delims in path
(670, 1, 'http://example.com/user@host:8080/resource',               'All literal (canonical)',          'protocol', TRUE, TRUE),
(670, 2, 'http://example.com/user%40host%3A8080/resource',           'Both @ and : encoded',             'protocol', FALSE, TRUE),

-- =============================================================================
-- 39. ADDITIONAL NEGATIVE TESTS — ENCODING TRAPS
-- =============================================================================

-- Group 700: Encoded dots are NOT dot segments
(700, 1, 'http://example.com/a/%2E%2E/b',         'Encoded .. — literal segment "%2E%2E"', 'syntax', TRUE, FALSE),
(700, 2, 'http://example.com/a/../b',              'Literal .. — parent traversal to /b',   'syntax', FALSE, FALSE),

-- Group 701: Single encoded dot is NOT a dot segment
(701, 1, 'http://example.com/a/%2E/b',             'Encoded . — literal segment "%2E"',     'syntax', TRUE, FALSE),
(701, 2, 'http://example.com/a/./b',               'Literal . — removed by normalization',  'syntax', FALSE, FALSE),

-- Group 702: Different non-ASCII characters that differ only in case of encoded byte
-- é (U+00E9) = %C3%A9, É (U+00C9) = %C3%89 — different characters
(702, 1, 'http://example.com/caf%C3%A9',           'Lowercase é (U+00E9)',                  'syntax', TRUE, FALSE),
(702, 2, 'http://example.com/caf%C3%89',           'Uppercase É (U+00C9) – different char', 'syntax', FALSE, FALSE),

-- Group 703: Non-breaking space is NOT regular space
(703, 1, 'http://example.com/a%C2%A0b',            'Non-breaking space (U+00A0)',            'syntax', TRUE, FALSE),
(703, 2, 'http://example.com/a%20b',               'Regular space (U+0020) – different',     'syntax', FALSE, FALSE),

-- Group 704: Encoded slash in path vs encoded slash in query (different components)
(704, 1, 'http://example.com/a%2Fb?c/d',           'Encoded / in path, literal / in query',  'syntax', TRUE, FALSE),
(704, 2, 'http://example.com/a/b?c%2Fd',           'Literal / in path, encoded / in query',  'syntax', FALSE, FALSE);

