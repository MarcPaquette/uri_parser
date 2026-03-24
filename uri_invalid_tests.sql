-- =============================================================================
-- URI Invalid Test Data
-- =============================================================================
-- URIs that are structurally invalid per RFC 3986. Both reference parsers
-- (C/uriparser and Python/urllib.parse) agree these should fail parsing.
--
-- Some URIs also appear in uri_test_data.sql (noted in descriptions).
-- That table tests parse_uri() handles them without crashing;
-- this table asserts that reference parsers reject them.
-- =============================================================================

CREATE TABLE uri_invalid_tests (
    id              INT PRIMARY KEY,
    uri             TEXT NOT NULL,
    description     TEXT NOT NULL,
    category        TEXT NOT NULL,
    expected_reason TEXT NOT NULL
);

INSERT INTO uri_invalid_tests (id, uri, description, category, expected_reason) VALUES

-- =============================================================================
-- 1. INCOMPLETE PERCENT-ENCODING
-- =============================================================================
-- RFC 3986 §2.1: pct-encoded = "%" HEXDIG HEXDIG
-- A "%" not followed by exactly two hex digits is invalid.

(3000, 'http://example.com/path?key=value%',        'Lone % at end of query (uri_test_data 808)',           'incomplete-pct-encoding', 'bad pct-encoding'),
(3001, 'http://example.com/path?key=value%2',        'Single hex digit after % (uri_test_data 809)',         'incomplete-pct-encoding', 'bad pct-encoding'),
(3002, 'http://example.com/path?key=value%ZZ',       'Non-hex chars after % (uri_test_data 810)',            'incomplete-pct-encoding', 'bad pct-encoding'),
(3003, 'http://example.com/path%',                   'Lone % at end of path (uri_test_data 1508)',           'incomplete-pct-encoding', 'bad pct-encoding'),
(3004, 'http://example.com/%G1/path',                'Non-hex uppercase G after % in path',                 'incomplete-pct-encoding', 'bad pct-encoding'),
(3005, 'http://example.com/path#frag%',              'Lone % at end of fragment',                            'incomplete-pct-encoding', 'bad pct-encoding'),
(3006, 'http://example.com/path#frag%0',             'Single hex digit in fragment',                         'incomplete-pct-encoding', 'bad pct-encoding'),
(3007, 'http://example.com/path%0Grest',             'Second hex digit invalid (G) in path',                 'incomplete-pct-encoding', 'bad pct-encoding'),
(3008, 'http://example.com/path?key=%ZZ&other=1',    'Non-hex after % mid-query (not at end)',               'incomplete-pct-encoding', 'bad pct-encoding'),

-- =============================================================================
-- 2. DISALLOWED CHARACTERS
-- =============================================================================
-- RFC 3986 does not allow: space, <, >, {, }, |, \, ^, `, "
-- in unencoded form anywhere in a URI.

-- Spaces
(3100, 'http://example.com/path with spaces',        'Space in path (uri_test_data 815)',                    'disallowed-char', 'disallowed char'),
(3101, 'http://example.com/path?key=val ue',         'Space in query value (uri_test_data 816)',             'disallowed-char', 'disallowed char'),
(3102, 'http://example.com/path#frag ment',          'Space in fragment',                                    'disallowed-char', 'disallowed char'),
(3103, 'http://exam ple.com/path',                   'Space in hostname',                                    'disallowed-char', 'disallowed char'),
(3104, 'http://user name@example.com/path',          'Space in userinfo',                                    'disallowed-char', 'disallowed char'),

-- Angle brackets
(3105, 'http://example.com/path?key=<tag>',          'Angle brackets in query (uri_test_data 818)',          'disallowed-char', 'disallowed char'),
(3106, 'http://example.com/<path>',                  'Angle brackets in path',                               'disallowed-char', 'disallowed char'),
(3107, 'data:text/html,<script>alert(1)</script>',   'Angle brackets in data URI (uri_test_data 1108)',      'disallowed-char', 'disallowed char'),

-- Curly braces
(3108, 'http://example.com/path?key={value}',        'Curly braces in query (uri_test_data 819)',            'disallowed-char', 'disallowed char'),
(3109, 'http://example.com/{path}',                  'Curly braces in path',                                 'disallowed-char', 'disallowed char'),

-- Pipe
(3110, 'http://example.com/path?key=|pipe',          'Pipe in query (uri_test_data 820)',                    'disallowed-char', 'disallowed char'),
(3111, 'http://example.com/path|rest',               'Pipe in path',                                         'disallowed-char', 'disallowed char'),

-- Backslash
(3112, 'http://example.com\@evil.com',               'Backslash in authority (uri_test_data 1106)',           'disallowed-char', 'disallowed char'),
(3113, 'http://example.com/path\..\..\etc\passwd',   'Backslash path traversal (uri_test_data 1802)',        'disallowed-char', 'disallowed char'),

-- XSS patterns with disallowed chars
(3114, 'http://example.com/path?q=<script>alert(1)</script>', 'XSS attempt with angle brackets (uri_test_data 1100)', 'disallowed-char', 'disallowed char'),

-- =============================================================================
-- 3. INVALID SCHEME
-- =============================================================================
-- RFC 3986 §3.1: scheme = ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )
-- Scheme must start with a letter and contain only letters, digits, +, -, .

(3200, '3com://example.com',                         'Scheme starts with digit (uri_test_data 2300)',         'invalid-scheme', 'invalid scheme'),
(3201, '+scheme://example.com',                      'Scheme starts with + (uri_test_data 2301)',             'invalid-scheme', 'invalid scheme'),
(3202, '.scheme://example.com',                      'Scheme starts with . (uri_test_data 2302)',             'invalid-scheme', 'invalid scheme'),
(3203, '-scheme://example.com',                      'Scheme starts with - (uri_test_data 2303)',             'invalid-scheme', 'invalid scheme'),
(3204, 'scheme_x://example.com',                     'Scheme with underscore (uri_test_data 2305)',           'invalid-scheme', 'invalid scheme'),
(3205, '0://example.com',                            'Single digit as scheme',                                'invalid-scheme', 'no scheme'),
(3206, ':not-a-scheme',                              'Colon with empty scheme (uri_test_data 825)',           'invalid-scheme', 'no scheme'),

-- =============================================================================
-- 4. NON-NUMERIC PORT
-- =============================================================================
-- RFC 3986 §3.2.3: port = *DIGIT

(3300, 'http://example.com:abc/path',                'All-letter port (uri_test_data 813)',                   'non-numeric-port', 'non-numeric port'),
(3301, 'http://example.com:8o80/path',               'Letter in middle of port',                              'non-numeric-port', 'non-numeric port'),
(3302, 'http://example.com:80ab/path',               'Trailing letters in port',                              'non-numeric-port', 'non-numeric port'),
(3303, 'http://example.com:ab80/path',               'Leading letters in port',                               'non-numeric-port', 'non-numeric port'),

-- =============================================================================
-- 5. UNBALANCED BRACKETS
-- =============================================================================
-- RFC 3986 §3.2.2: brackets are only allowed in IP-literal and must be balanced.

(3400, 'http://[::1/path',                           'Opening bracket without closing (uri_test_data 1401)',  'unbalanced-brackets', 'unbalanced brackets');
