CREATE TABLE uri_test_data (
    id          INT PRIMARY KEY,
    uri         TEXT NOT NULL,
    description TEXT NOT NULL
);

INSERT INTO uri_test_data (id, uri, description) VALUES

-- =============================================================================
-- BASIC STRUCTURE VARIATIONS
-- =============================================================================

-- Scheme variations
(1,   'http://example.com',                          'HTTP scheme'),
(2,   'https://example.com',                         'HTTPS scheme'),
(3,   'ftp://example.com',                           'FTP scheme'),
(4,   'ftps://example.com',                          'FTPS scheme'),
(5,   'ssh://example.com',                           'SSH scheme'),
(6,   'telnet://example.com',                        'Telnet scheme'),
(7,   'mailto:user@example.com',                     'Mailto scheme (no authority)'),
(8,   'tel:+1-800-555-1234',                         'Tel scheme'),
(9,   'urn:isbn:0451450523',                         'URN scheme'),
(10,  'file:///home/user/file.txt',                  'File scheme with empty authority'),
(11,  'file:///C:/Users/file.txt',                   'File scheme Windows path'),
(12,  'data:text/plain;base64,SGVsbG8=',             'Data URI scheme'),
(13,  'javascript:void(0)',                          'JavaScript scheme'),
(14,  'ldap://[2001:db8::7]/c=GB',                  'LDAP scheme with IPv6'),
(15,  'news:comp.lang.sql',                          'News scheme'),
(16,  'custom-scheme://example.com',                 'Custom scheme with hyphen'),
(17,  'HTTPS://EXAMPLE.COM',                         'Uppercase scheme and host'),
(18,  'hTtPs://Example.Com',                         'Mixed case scheme and host'),
(19,  'postgres://localhost/mydb',                    'Postgres scheme'),
(20,  'mongodb://localhost:27017/mydb',               'MongoDB scheme'),
(21,  's3://my-bucket/my-key',                       'S3 scheme'),
(22,  'ws://example.com/socket',                     'WebSocket scheme'),
(23,  'wss://example.com/socket',                    'Secure WebSocket scheme'),
(24,  'kafka://broker.example.com:9092',             'Kafka scheme'),
(25,  'kafka+ssl://broker.example.com:9093',         'Kafka with SSL (compound scheme)'),
(26,  'postgresql://root@localhost:26257/defaultdb', 'CockroachDB connection (postgresql scheme)'),

-- =============================================================================
-- AUTHORITY / HOST VARIATIONS
-- =============================================================================

-- Hostnames
(100, 'http://localhost',                             'Localhost'),
(101, 'http://localhost:8080',                        'Localhost with port'),
(102, 'http://example.com',                           'Simple domain'),
(103, 'http://www.example.com',                       'Domain with www subdomain'),
(104, 'http://sub.domain.example.com',                'Multi-level subdomain'),
(105, 'http://a.b.c.d.e.f.example.com',              'Deeply nested subdomain'),
(106, 'http://example.co.uk',                         'Country code TLD'),
(107, 'http://example.com.',                          'Trailing dot (FQDN)'),
(108, 'http://xn--nxasmq6b.example.com',             'Punycode / internationalized domain'),
(109, 'http://example',                               'Single-label hostname (no TLD)'),
(110, 'http://192.168.1.1',                           'IPv4 address'),
(111, 'http://10.0.0.1:8080',                         'IPv4 with port'),
(112, 'http://0.0.0.0',                               'All-zeros IPv4'),
(113, 'http://255.255.255.255',                        'Max IPv4'),
(114, 'http://127.0.0.1',                             'Loopback IPv4'),
(115, 'http://[::1]',                                 'IPv6 loopback'),
(116, 'http://[::1]:8080',                            'IPv6 loopback with port'),
(117, 'http://[2001:db8:85a3::8a2e:370:7334]',       'Full IPv6 address'),
(118, 'http://[2001:db8:85a3::8a2e:370:7334]:443',   'IPv6 with port'),
(119, 'http://[::ffff:192.168.1.1]',                  'IPv4-mapped IPv6'),
(120, 'http://[v1.fe80::a+en1]',                      'IPvFuture address'),
(121, 'http://[::1%25eth0]',                          'IPv6 with zone ID (RFC 6874, not valid per RFC 3986 ABNF)'),
(122, 'http://0x7f.0x00.0x00.0x01',                   'Hex IPv4 octets (parsed as reg-name, not IPv4address per RFC 3986)'),
(123, 'http://2130706433',                             'Decimal IPv4 (parsed as reg-name, not IPv4address per RFC 3986)'),
(124, 'http://my-host.example.com',                   'Hostname with hyphens'),
(125, 'http://123numeric.example.com',                'Hostname starting with digits'),
(126, 'http://host_with_underscore.example.com',      'Hostname with underscore (non-standard)'),

-- =============================================================================
-- PORT VARIATIONS
-- =============================================================================
(200, 'http://example.com:80',                        'Default HTTP port explicit'),
(201, 'https://example.com:443',                      'Default HTTPS port explicit'),
(202, 'http://example.com:8080',                      'Non-standard port'),
(203, 'http://example.com:0',                         'Port zero'),
(204, 'http://example.com:65535',                      'Max valid port'),
(205, 'http://example.com:',                          'Empty port (colon, no digits)'),
(206, 'http://example.com:3000',                      'Common dev port'),
(207, 'ftp://example.com:21',                         'FTP default port'),
(208, 'ssh://example.com:22',                         'SSH default port'),

-- =============================================================================
-- USERINFO (CREDENTIALS) VARIATIONS
-- =============================================================================
(300, 'http://user@example.com',                       'Username only'),
(301, 'http://user:password@example.com',              'Username and password'),
(302, 'http://user:@example.com',                      'Username with empty password'),
(303, 'http://:password@example.com',                  'Empty username with password'),
(304, 'http://:@example.com',                          'Empty username and password'),
(305, 'http://user%40name:p%40ss@example.com',         'Percent-encoded @ in credentials'),
(306, 'http://user:p%3Ass@example.com',                'Percent-encoded colon in password'),
(307, 'http://user:pass:word@example.com',             'Multiple colons in userinfo'),
(308, 'http://user%20name:pass%20word@example.com',    'Spaces encoded in credentials'),
(309, 'http://admin:admin@192.168.1.1:8080/path',     'Full userinfo with IPv4 and port'),
(310, 'ftp://anonymous:user@example.com@ftp.example.com', 'Email-like password (bare @ invalid in userinfo per RFC 3986)'),

-- =============================================================================
-- PATH VARIATIONS
-- =============================================================================
(400, 'http://example.com/',                           'Root path (trailing slash)'),
(401, 'http://example.com/path',                       'Simple path'),
(402, 'http://example.com/path/',                      'Path with trailing slash'),
(403, 'http://example.com/path/to/resource',           'Multi-segment path'),
(404, 'http://example.com/path/to/resource/',          'Multi-segment path trailing slash'),
(405, 'http://example.com/path/to/resource.html',      'Path with file extension'),
(406, 'http://example.com/path/to/resource.tar.gz',    'Path with double extension'),
(407, 'http://example.com/path//double//slash',         'Double slashes in path'),
(408, 'http://example.com/.',                           'Dot segment'),
(409, 'http://example.com/..',                          'Double-dot segment'),
(410, 'http://example.com/a/./b/../c',                  'Dot segments requiring normalization'),
(411, 'http://example.com/path%20with%20spaces',        'Percent-encoded spaces in path'),
(412, 'http://example.com/path+with+plus',              'Plus signs in path'),
(413, 'http://example.com/%2F',                         'Percent-encoded slash'),
(414, 'http://example.com/p%61th',                      'Percent-encoded unreserved char (a)'),
(415, 'http://example.com/path;params',                 'Semicolon path parameter'),
(416, 'http://example.com/a;x=1/b;y=2',                'Multiple path segment params'),
(417, 'http://example.com/~user',                       'Tilde in path'),
(418, 'http://example.com/path/with-dashes',            'Dashes in path'),
(419, 'http://example.com/path/with_underscores',       'Underscores in path'),
(420, 'http://example.com/CaseSensitive/Path',          'Mixed case path'),
(421, 'http://example.com/path/with!special$chars&here','Special characters in path'),
(422, 'http://example.com/path/(parens)/[brackets]',    'Parens valid (sub-delims), brackets invalid (gen-delims) in path'),
(423, 'http://example.com/unicode/%E4%B8%AD%E6%96%87',  'Percent-encoded Unicode in path'),
(424, 'http://example.com/api/v1/users/123/posts',      'REST-style API path'),
(425, 'http://example.com/',                             'Single slash path'),
(426, 'http://example.com',                              'No path at all'),
(427, '/relative/path/only',                             'Relative URI (path only)'),
(428, 'relative/path',                                   'Relative URI no leading slash'),
(429, './relative/path',                                 'Relative URI with dot prefix'),
(430, '../parent/path',                                  'Relative URI with parent ref'),
(431, 'http://example.com/a/very/deeply/nested/path/to/some/resource/file.json', 'Very deep path'),
(432, 'http://example.com/%00',                          'Null byte percent-encoded'),
(433, 'http://example.com/path/with%23hash',             'Percent-encoded hash in path'),

-- =============================================================================
-- QUERY STRING VARIATIONS
-- =============================================================================
(500, 'http://example.com?key=value',                    'Query without path'),
(501, 'http://example.com/?key=value',                   'Query with root path'),
(502, 'http://example.com/path?key=value',               'Query with path'),
(503, 'http://example.com/path?',                        'Empty query string'),
(504, 'http://example.com/path?key',                     'Query key with no value'),
(505, 'http://example.com/path?key=',                    'Query key with empty value'),
(506, 'http://example.com/path?key=value&key2=value2',   'Multiple query params'),
(507, 'http://example.com/path?key=value&key=value2',    'Duplicate query keys'),
(508, 'http://example.com/path?key=value&&key2=value2',  'Double ampersand in query'),
(509, 'http://example.com/path?key=val%20ue',            'Percent-encoded space in query value'),
(510, 'http://example.com/path?key=val+ue',              'Plus as space in query value'),
(511, 'http://example.com/path?key=val%26ue',            'Percent-encoded ampersand in value'),
(512, 'http://example.com/path?key=val%3Due',             'Percent-encoded equals in value'),
(513, 'http://example.com/path?a=1&b=2&c=3&d=4&e=5',     'Many query params'),
(514, 'http://example.com/path?key[0]=a&key[1]=b',        'Array-style query params (brackets invalid per RFC 3986)'),
(515, 'http://example.com/path?obj[name]=foo&obj[age]=30','Object-style query params (brackets invalid per RFC 3986)'),
(516, 'http://example.com/path?q=hello+world&lang=en',    'Search-style query'),
(517, 'http://example.com/path?url=http%3A%2F%2Fother.com','URL as query value'),
(518, 'http://example.com/path?json=%7B%22a%22%3A1%7D',   'JSON as query value'),
(519, 'http://example.com/path?key;semi=value',            'Semicolon in query string'),
(520, 'http://example.com/path?a=1;b=2',                   'Semicolons as param separators'),
(521, 'http://example.com/path?query=SELECT%20*%20FROM%20t','SQL in query value'),
(522, 'http://example.com/path?emoji=%F0%9F%98%80',         'Encoded emoji in query'),
(523, 'http://example.com/path?key=value&utm_source=test&utm_medium=email', 'UTM tracking params'),
(524, 'http://example.com/search?q=a%20b%20c&page=1&limit=10&sort=desc&filter=active', 'Complex search query'),

-- =============================================================================
-- FRAGMENT VARIATIONS
-- =============================================================================
(600, 'http://example.com#fragment',                     'Fragment without path'),
(601, 'http://example.com/#fragment',                    'Fragment with root path'),
(602, 'http://example.com/path#fragment',                'Fragment with path'),
(603, 'http://example.com/path#',                        'Empty fragment'),
(604, 'http://example.com/path#section-1',               'Fragment with hyphen'),
(605, 'http://example.com/path#/json/pointer',           'JSON Pointer fragment'),
(606, 'http://example.com/path#name=value',              'Key=value fragment'),
(607, 'http://example.com/path?q=1#frag',                'Query and fragment'),
(608, 'http://example.com/path#frag%20ment',             'Percent-encoded space in fragment'),
(609, 'http://example.com/path#frag#ment',               'Multiple hash signs (# invalid in fragment per RFC 3986)'),
(610, 'http://example.com/path#top',                     'Common anchor fragment'),
(611, 'http://example.com/path#/a/b/c',                  'Path-like fragment'),
(612, 'http://example.com/path?q=1&r=2#section',         'Query + fragment combined'),

-- =============================================================================
-- COMBINED COMPLEX URIs
-- =============================================================================
(700, 'http://user:pass@example.com:8080/path/to/resource?key=value&foo=bar#section', 'Full URI with all components'),
(701, 'https://admin:s3cret%21@api.example.com:9443/v2/users?status=active&role=admin#results', 'Complex API URI'),
(702, 'ftp://anonymous:guest@files.example.com:2121/pub/docs/readme.txt', 'FTP with credentials and path'),
(703, 'http://example.com/path?a=1&a=2&a=3&b=x#top',    'Repeated params plus fragment'),
(704, 'https://example.com/api/v1/users/42/posts/7/comments?page=2&per_page=25&sort=created_at&order=desc#comment-15', 'Full REST API URI'),

-- =============================================================================
-- EDGE CASES AND UNUSUAL INPUTS
-- =============================================================================
(800, '',                                                'Empty string'),
(801, '/',                                               'Just a slash'),
(802, '//',                                              'Double slash only'),
(803, '//example.com',                                   'Protocol-relative URI'),
(804, '//example.com/path?q=1#f',                        'Protocol-relative with all parts'),
(805, '?query=only',                                     'Query only (no scheme/path)'),
(806, '#fragment-only',                                  'Fragment only'),
(807, '?query=1#fragment',                               'Query and fragment, no path'),
(808, 'http://example.com/path?key=value%',              'Incomplete percent encoding'),
(809, 'http://example.com/path?key=value%2',             'Partial percent encoding (one hex digit)'),
(810, 'http://example.com/path?key=value%ZZ',            'Invalid percent encoding'),
(811, 'http://',                                          'Scheme with empty authority'),
(812, 'http:///path',                                    'Scheme with empty authority and path'),
(813, 'http://example.com:abc/path',                     'Non-numeric port'),
(814, 'http://example.com:99999/path',                   'Port out of range (syntactically valid per ABNF, semantically invalid)'),
(815, 'http://example.com/path with spaces',             'Unencoded spaces in path'),
(816, 'http://example.com/path?key=val ue',              'Unencoded space in query'),
(817, 'http://example.com/path?key="quoted"',            'Quotes in query value'),
(818, 'http://example.com/path?key=<tag>',               'Angle brackets in query'),
(819, 'http://example.com/path?key={value}',             'Curly braces in query'),
(820, 'http://example.com/path?key=|pipe',               'Pipe in query'),
(821, 'http://example.com/résumé',                       'Raw Unicode in path'),
(822, 'http://例え.jp/パス',                               'International domain and path'),
(823, 'http://example.com/path\nwith\nnewlines',         'Newlines in path'),
(824, 'http://example.com/path\twith\ttabs',             'Tabs in path'),
(825, ':not-a-scheme',                                    'Colon with no scheme name'),
(826, 'http:path:with:colons',                           'Colons in path (no authority)'),
(827, 'http://example.com?',                             'Question mark, no query content'),
(828, 'http://example.com#',                             'Hash, no fragment content'),
(829, 'http://example.com?#',                            'Empty query and empty fragment'),
(830, 'http://example.com/path???multiple',              'Multiple question marks'),
(831, 'http://example.com/path###multiple',              'Multiple hash marks (# invalid in fragment per RFC 3986)'),
(832, 'http://example.com/@user/repo',                   'At sign in path (GitHub-style)'),
(833, 'http://example.com/path?callback=http://other.com/cb', 'Unencoded URL in query'),
(834, 'http://example.com/a?b=c?d=e',                   'Question mark in query value'),
(835, 'http://user@example.com:8080',                    'Userinfo with port, no path'),
(836, 'http://example.com/path#frag?not-query',          'Question mark inside fragment'),

-- =============================================================================
-- NORMALIZATION TESTS
-- =============================================================================
(900, 'HTTP://Example.COM/Path',                          'Mixed case scheme and host'),
(901, 'http://example.com/%7Euser',                       'Percent-encoded tilde (unreserved)'),
(902, 'http://example.com/%41%42%43',                     'Percent-encoded uppercase letters ABC'),
(903, 'http://example.com:80/path',                       'Default port should normalize away'),
(904, 'http://example.com/a/b/c/../d',                    'Dot segment for normalization'),
(905, 'http://example.com/a/b/c/./d',                     'Single dot segment normalization'),
(906, 'http://example.com/',                               'Trailing slash root'),
(907, 'http://example.com',                                'No trailing slash root'),
(908, 'http://example.com/a%2Fb',                          'Encoded slash vs path separator'),
(909, 'http://EXAMPLE.com/Path?KEY=VALUE',                 'Host case-insensitive, path case-sensitive'),

-- =============================================================================
-- REAL-WORLD PATTERNS
-- =============================================================================
(1000, 'https://www.google.com/search?q=uri+parser&oq=uri+parser&sourceid=chrome&ie=UTF-8', 'Google search URL'),
(1001, 'https://github.com/user/repo/blob/main/src/file.go#L42-L50',                       'GitHub file link with line range'),
(1002, 'https://stackoverflow.com/questions/12345/some-question?answertab=votes#tab-top',    'StackOverflow URL'),
(1003, 'https://maps.google.com/?q=40.7128,-74.0060&z=15',                                  'Google Maps coordinates'),
(1004, 'https://example.com/oauth/callback?code=abc123&state=xyz789',                        'OAuth callback'),
(1005, 'https://cdn.example.com/assets/js/app.min.js?v=1.2.3',                              'CDN asset with version'),
(1006, 'postgres://user:pass@db.example.com:5432/mydb?sslmode=require&connect_timeout=10',   'PostgreSQL connection string'),
(1007, 'mongodb+srv://admin:pass@cluster0.abc.mongodb.net/mydb?retryWrites=true&w=majority', 'MongoDB SRV connection'),
(1008, 'redis://default:password@redis.example.com:6379/0',                                  'Redis connection string'),
(1009, 'amqp://user:pass@rabbit.example.com:5672/vhost',                                     'AMQP connection string'),
(1010, 'mysql://root:password@127.0.0.1:3306/testdb?charset=utf8mb4',                        'MySQL connection string'),
(1011, 'https://example.com/api/v1/users?fields=id,name,email&filter[status]=active&page[number]=1&page[size]=20', 'JSON:API style query (brackets invalid per RFC 3986)'),
(1012, 'magnet:?xt=urn:btih:abc123&dn=example&tr=http%3A%2F%2Ftracker.example.com',          'Magnet URI'),
(1013, 'geo:37.7749,-122.4194',                                                              'Geo URI'),
(1014, 'sip:user@example.com:5060;transport=tcp',                                            'SIP URI'),
(1015, 'xmpp:user@example.com/resource',                                                     'XMPP URI'),
(1016, 'spotify:track:6rqhFgbbKwnb9MLmUQDhG6',                                              'Spotify URI'),
(1017, 'market://details?id=com.example.app',                                                'Android Market URI'),
(1018, 'itms-apps://itunes.apple.com/app/id123456789',                                       'iOS App Store URI'),
(1019, 'slack://channel?team=T123&id=C456',                                                  'Slack deep link'),
(1020, 'vscode://file/Users/user/project/main.go:42:10',                                     'VS Code file URI'),

-- =============================================================================
-- SECURITY-RELATED TEST CASES
-- =============================================================================
(1100, 'http://example.com/path?q=<script>alert(1)</script>',            'XSS in query'),
(1101, 'http://example.com/path?q=%3Cscript%3Ealert(1)%3C/script%3E',   'Encoded XSS in query'),
(1102, 'http://example.com/path?q=1%27%20OR%201%3D1--',                  'SQL injection in query'),
(1103, 'http://example.com/..%2F..%2Fetc/passwd',                        'Path traversal (encoded)'),
(1104, 'http://example.com/%2e%2e/%2e%2e/etc/passwd',                    'Double-encoded path traversal'),
(1105, 'http://evil.com@example.com',                                    'Authority confusion attack'),
(1106, 'http://example.com\@evil.com',                                   'Backslash in authority'),
(1107, 'javascript:alert(document.cookie)',                               'JavaScript injection URI'),
(1108, 'data:text/html,<script>alert(1)</script>',                       'Data URI with script (angle brackets invalid per RFC 3986)'),
(1109, 'http://127.0.0.1:11211/memcache',                                'SSRF localhost attempt'),
(1110, 'http://0177.0.0.1',                                              'Octal IPv4 (parsed as reg-name, not IPv4address per RFC 3986)'),
(1111, 'http://2130706433',                                              'Decimal IPv4 as integer (parsed as reg-name per RFC 3986)'),
(1112, 'http://example.com/path?redirect=http://evil.com',               'Open redirect in query'),
(1113, 'http://example.com/%00/path',                                    'Null byte injection'),

-- =============================================================================
-- EXTREMELY LONG AND STRESS TEST URIs
-- =============================================================================
(1200, 'http://example.com/' || REPEAT('a', 2000),                       'Very long path segment'),
(1201, 'http://example.com/path?' || REPEAT('key=value&', 200),          'Many repeated query params'),
(1202, 'http://' || REPEAT('sub.', 50) || 'example.com',                 'Many subdomains'),
(1203, 'http://example.com/path#' || REPEAT('f', 1000),                  'Very long fragment'),
(1204, 'http://example.com/' || REPEAT('a/', 100),                       'Deeply nested path segments'),

-- =============================================================================
-- ADDITIONAL SCHEME PATTERNS
-- =============================================================================
(1300, 'coap+tcp://example.com',                                                     'Compound scheme with plus'),
(1301, 'x://example.com',                                                            'Single-letter scheme'),
(1302, 'h323://example.com',                                                         'Scheme with digits'),
(1303, 'http:',                                                                      'Scheme only (no authority or path)'),
(1304, 'http:example.com/path',                                                      'Scheme without double slash (no authority)'),
(1305, 'blob:https://example.com/550e8400-e29b-41d4-a716-446655440000',              'Blob URL'),
(1306, 'cid:part1@example.com',                                                      'Content-ID scheme'),
(1307, 'git+ssh://git@github.com/user/repo.git',                                     'Git+SSH compound scheme'),
(1308, 'bitcoin:1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa?amount=0.1',                     'Bitcoin URI'),
(1309, 'urn:uuid:550e8400-e29b-41d4-a716-446655440000',                              'URN UUID'),

-- =============================================================================
-- ADDITIONAL AUTHORITY EDGE CASES
-- =============================================================================
(1400, 'http://:8080/path',                                                          'Empty host with port'),
(1401, 'http://[::1/path',                                                           'Incomplete IPv6 bracket (malformed)'),
(1402, 'http://::1/path',                                                            'IPv6 missing brackets (malformed)'),
(1403, 'http://exаmple.com',                                                         'Homograph domain (Cyrillic а U+0430)'),
(1404, 'http://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.com',   'Max DNS label length (63 chars)'),
(1405, '//user:pass@example.com/path',                                               'Protocol-relative with userinfo'),

-- =============================================================================
-- ADDITIONAL PATH EDGE CASES
-- =============================================================================
(1500, 'path:with:colons',                                                           'Colon in first relative path segment (ambiguous with scheme)'),
(1501, 'http://example.com/a,b,c',                                                   'Comma-delimited path'),
(1502, 'http://example.com/users(''123'')',                                           'OData-style path with parentheses'),
(1503, 'http://example.com/%70%61%74%68',                                            'Fully percent-encoded path (decodes to /path)'),
(1504, 'http://example.com/path%C2%A0here',                                          'Non-breaking space (U+00A0) in path'),
(1505, '.',                                                                           'Dot-only relative reference'),
(1506, '..',                                                                          'Double-dot-only relative reference'),
(1507, 'http://example.com/////',                                                     'Multiple consecutive empty path segments'),
(1508, 'http://example.com/path%',                                                   'Lone percent at end of path'),

-- =============================================================================
-- ADDITIONAL ENCODING EDGE CASES
-- =============================================================================
(1600, 'http://example.com/path%2520value',                                          'Double percent-encoding (%2520 decodes to %20)'),
(1601, 'http://example.com/100%25done',                                              'Percent-encoded percent sign'),
(1602, 'http://example.com/%C0%AF',                                                  'Overlong UTF-8 encoding of /'),
(1603, 'http://example.com/%FF%FE',                                                  'Invalid UTF-8 sequence'),
(1604, 'http://example.com/path?token=SGVsbG8gV29ybGQ=',                             'Base64 with trailing = in query value'),

-- =============================================================================
-- ADDITIONAL QUERY PATTERNS
-- =============================================================================
(1700, 'http://example.com/path?a&b&c',                                              'Flag-style query params (no values)'),
(1701, 'http://example.com?a[b][c][d]=1',                                            'Deeply nested bracket query params (brackets invalid per RFC 3986)'),
(1702, 'http://example.com?file=../../etc/passwd',                                   'Path traversal in query value'),
(1703, '#',                                                                           'Bare hash only (empty fragment, no other component)'),

-- =============================================================================
-- ADDITIONAL SECURITY CASES
-- =============================================================================
(1800, 'http://example.com/path%0d%0aX-Injected:%20header',                          'CRLF injection in path'),
(1801, 'http://example.com/%E2%80%AEgro.live',                                       'Right-to-left override character in path'),
(1802, 'http://example.com/path\..\..\etc\passwd',                                   'Backslash path traversal'),
(1803, 'http://google.com%40evil.com',                                               'Percent-encoded @ in hostname (authority confusion)'),
(1804, 'http://example.com/%25252e%25252e/etc/passwd',                               'Triple-encoded path traversal'),
(1805, 'jar:http://example.com/archive.jar!/file.txt',                               'Jar nested URI scheme'),
(1806, 'http://example.com/page#javascript:alert(1)',                                'JavaScript scheme in fragment'),

-- =============================================================================
-- ADDITIONAL STRUCTURAL / RELATIVE REFERENCE CASES
-- =============================================================================
(1900, 'http://example.com/path?key=value#fragment?not-query',                       'Question mark after fragment (not a query)'),
(1901, 'http://example.com/path#one#two#three',                                      'Multiple hash signs (# invalid in fragment per RFC 3986)'),
(1902, 'http:///path/to/resource',                                                   'Scheme with empty authority and multi-segment path'),
(1903, '//example.com:8080/path?q=1#frag',                                           'Protocol-relative with port, query, and fragment'),
(1904, 'http://example.com/path?&=&=value&key=&=',                                  'Degenerate query param separators and empty keys/values'),
(1905, 'http://example.com?key=value#fragment',                                      'Query and fragment with no path'),

-- =============================================================================
-- ADDITIONAL REAL-WORLD PATTERNS
-- =============================================================================
(2000, 'docker://registry.example.com/org/image:tag',                                'Docker registry image URI'),
(2001, 'smb://server/share/folder/file.txt',                                         'SMB file share URI'),
(2002, 'vnc://192.168.1.1:5900',                                                     'VNC remote desktop URI'),
(2003, 'https://k8s.example.com/api/v1/namespaces/default/pods?labelSelector=app%3Dwebserver', 'Kubernetes API URI'),
(2004, 'chrome-extension://abcdefghijklmnop/popup.html',                              'Chrome extension URI'),
(2005, 'intent://scan/#Intent;scheme=zxing;package=com.google.zxing.client.android;end', 'Android intent URI'),
(2006, 'matrix:r/room:example.com',                                                  'Matrix URI'),
(2007, 'https://example.com/path?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIA1234%2F20240101%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Signature=abcdef1234567890', 'AWS pre-signed S3 URL'),
(2008, 'did:example:123456789abcdefghi',                                              'Decentralized Identifier (DID)'),
(2009, 'tag:example.com,2024:blog/post/1',                                            'Tag URI (RFC 4151)'),
(2010, 'ms-windows-store://pdp?productid=9WZDNCRFJ3TJ',                              'Windows Store URI'),
(2011, 'coap://sensor.example.com:5683/.well-known/core',                             'CoAP IoT URI'),
(2012, 'payto://iban/DE89370400440532013000?amount=EUR:25.50&message=Invoice%2042',   'Payment URI (payto)'),

-- =============================================================================
-- RFC 3986 SECTION 1.1.2 CANONICAL EXAMPLES
-- =============================================================================
(2100, 'ftp://ftp.is.co.za/rfc/rfc1808.txt',                                        'RFC 3986 §1.1.2 example – FTP'),
(2101, 'http://www.ietf.org/rfc/rfc2396.txt',                                       'RFC 3986 §1.1.2 example – HTTP'),
(2102, 'ldap://[2001:db8::7]/c=GB?objectClass?one',                                 'RFC 3986 §1.1.2 example – LDAP (? in query)'),
(2103, 'mailto:John.Doe@example.com',                                                'RFC 3986 §1.1.2 example – mailto'),
(2104, 'news:comp.infosystems.www.servers.unix',                                     'RFC 3986 §1.1.2 example – news'),
(2105, 'tel:+1-816-555-1212',                                                        'RFC 3986 §1.1.2 example – tel'),
(2106, 'telnet://192.0.2.16:80/',                                                    'RFC 3986 §1.1.2 example – telnet'),
(2107, 'urn:oasis:names:specification:docbook:dtd:xml:4.1.2',                        'RFC 3986 §1.1.2 example – URN with many colons'),

-- =============================================================================
-- IPv4 ADDRESS BOUNDARY TESTS (dec-octet grammar coverage)
-- =============================================================================
-- dec-octet = DIGIT / %x31-39 DIGIT / "1" 2DIGIT / "2" %x30-34 DIGIT / "25" %x30-35
(2200, 'http://0.0.0.0',                                                              'IPv4 all-zeros (each octet single DIGIT)'),
(2201, 'http://9.9.9.9',                                                              'IPv4 single-digit max'),
(2202, 'http://10.99.10.99',                                                          'IPv4 two-digit octets (%x31-39 DIGIT)'),
(2203, 'http://100.199.100.199',                                                      'IPv4 three-digit octets (1xx range)'),
(2204, 'http://200.249.200.249',                                                      'IPv4 three-digit octets (2x0-2x4 range)'),
(2205, 'http://250.255.250.255',                                                      'IPv4 three-digit octets (25x range, max)'),
(2206, 'http://256.1.1.1',                                                            'IPv4 octet > 255 (invalid dec-octet, parsed as reg-name)'),
(2207, 'http://1.2.3.4.5',                                                            'IPv4 too many octets (invalid, parsed as reg-name)'),
(2208, 'http://1.2.3',                                                                'IPv4 too few octets (invalid, parsed as reg-name)'),
(2209, 'http://01.02.03.04',                                                          'IPv4 leading zeros (invalid dec-octet, parsed as reg-name)'),
(2210, 'http://1.2.3.04',                                                             'IPv4 partial leading zero (invalid dec-octet, parsed as reg-name)'),

-- =============================================================================
-- SCHEME EDGE CASES (ABNF grammar coverage)
-- =============================================================================
-- scheme = ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )
(2300, '3com://example.com',                                                          'Scheme starts with digit (invalid – scheme must start with ALPHA)'),
(2301, '+scheme://example.com',                                                       'Scheme starts with + (invalid – must start with ALPHA)'),
(2302, '.scheme://example.com',                                                       'Scheme starts with . (invalid – must start with ALPHA)'),
(2303, '-scheme://example.com',                                                       'Scheme starts with - (invalid – must start with ALPHA)'),
(2304, 'a.1-2+3://example.com',                                                      'Scheme with all allowed non-ALPHA chars after initial letter'),
(2305, 'scheme_x://example.com',                                                     'Scheme with underscore (invalid – _ not in scheme production)'),

-- =============================================================================
-- MINIMAL / EMPTY COMPONENT COMBINATIONS
-- =============================================================================
(2400, 'x:?#',                                                                        'Scheme + empty path + empty query + empty fragment'),
(2401, 'x:#',                                                                         'Scheme + empty path + empty fragment'),
(2402, 'x:?',                                                                         'Scheme + empty path + empty query'),
(2403, 'x:',                                                                          'Scheme + empty path only'),
(2404, 'x:/',                                                                         'Scheme + path-absolute (root)'),
(2405, 'x://',                                                                        'Scheme + empty authority + empty path'),
(2406, 'x://h',                                                                       'Scheme + minimal authority + empty path'),
(2407, 'x://h/',                                                                      'Scheme + minimal authority + root path'),
(2408, 'x://h?q',                                                                     'Scheme + authority + query, no path'),
(2409, 'x://h#f',                                                                     'Scheme + authority + fragment, no path'),
(2410, 'x://h?q#f',                                                                   'Scheme + authority + query + fragment, no path'),

-- =============================================================================
-- GEN-DELIMS AS DATA (must be percent-encoded in path/query/fragment)
-- =============================================================================
(2500, 'http://example.com/path%5B0%5D',                                              'Percent-encoded brackets in path (valid)'),
(2501, 'http://example.com/path?key%5B0%5D=val',                                     'Percent-encoded brackets in query (valid)'),
(2502, 'http://example.com/path#section%5B1%5D',                                     'Percent-encoded brackets in fragment (valid)'),
(2503, 'http://example.com/path%23hash',                                              'Percent-encoded # in path (valid, not a fragment delimiter)'),
(2504, 'http://example.com/path%3Fquery',                                             'Percent-encoded ? in path (valid, not a query delimiter)'),

-- =============================================================================
-- SUB-DELIMITERS IN USERINFO (all valid per RFC 3986)
-- =============================================================================
(2600, 'http://!$&''()*+,;=@example.com/path',                                       'All sub-delims in userinfo (valid per RFC 3986)'),

-- =============================================================================
-- SEGMENT-NZ-NC (no colon in first segment of relative-ref)
-- =============================================================================
(2700, 'a@b/c',                                                                       'Relative-ref: @ in first segment (valid segment-nz-nc)'),
(2701, 'a!b/c',                                                                       'Relative-ref: ! in first segment (valid segment-nz-nc)'),
(2702, './a:b/c',                                                                     'Relative-ref: colon in first segment (requires ./ prefix)'),

-- =============================================================================
-- IPv6 FULL-FORM COVERAGE
-- =============================================================================
(2800, 'http://[2001:0db8:0000:0000:0000:0000:0000:0001]/',                          'IPv6 fully expanded (all 8 groups, leading zeros)'),
(2801, 'http://[::]/',                                                                'IPv6 all-zeros compressed'),
(2802, 'http://[0000:0000:0000:0000:0000:0000:0000:0000]/',                          'IPv6 all-zeros fully expanded'),
(2803, 'http://[fe80::1%25en0]',                                                     'IPv6 link-local with zone ID (RFC 6874, not RFC 3986)'),
(2804, 'http://[2001:db8:a::123]/',                                                  'IPv6 with mixed-length groups'),
(2805, 'http://[::ffff:192.0.2.1]/',                                                 'IPv4-mapped IPv6 (dual form)'),

-- =============================================================================
-- KAFKA URIs
-- =============================================================================

(2900, 'kafka://broker.example.com:9092',                                            'Kafka broker basic'),
(2901, 'kafka://broker.example.com:9092/my-topic',                                   'Kafka broker with topic'),
(2902, 'kafka://broker.example.com',                                                  'Kafka broker no port'),
(2903, 'kafka://broker.example.com:9092/my-topic?timeout=5000',                       'Kafka with query param'),
(2904, 'kafka://user:pass@broker.example.com:9092/my-topic',                          'Kafka with SASL credentials'),
(2905, 'kafka+ssl://broker.example.com:9093',                                         'Kafka SSL compound scheme'),
(2906, 'kafka+ssl://broker.example.com:9093/my-topic',                                'Kafka SSL with topic'),
(2907, 'kafka://broker1.example.com:9092,broker2.example.com:9092/my-topic',          'Kafka multi-broker (comma invalid per RFC 3986)'),
(2908, 'KAFKA://BROKER.EXAMPLE.COM:9092/my-topic',                                   'Kafka uppercase scheme and host'),
(2909, 'kafka://broker.example.com:9092/my-topic#partition-0',                        'Kafka with fragment (partition hint)'),
(2910, 'kafka://broker.example.com:9092/my.topic.name',                               'Kafka dotted topic name'),
(2911, 'kafka://broker.example.com:9092/topic?group.id=my-group&auto.offset.reset=earliest', 'Kafka consumer config query'),
(2912, 'kafka://10.0.0.1:9092/topic',                                                 'Kafka with IPv4 broker'),
(2913, 'kafka://[::1]:9092/topic',                                                    'Kafka with IPv6 broker'),
(2914, 'kafka://broker.example.com:9092/',                                            'Kafka with trailing slash, no topic'),

-- =============================================================================
-- COCKROACHDB URIs
-- =============================================================================

(2920, 'postgresql://root@localhost:26257/defaultdb',                                  'CockroachDB basic connection'),
(2921, 'postgresql://root@localhost:26257/defaultdb?sslmode=disable',                  'CockroachDB with SSL disabled'),
(2922, 'postgresql://root@localhost:26257/movr?sslmode=verify-full&sslrootcert=/certs/ca.crt', 'CockroachDB with SSL certs'),
(2923, 'postgresql://user:password@free-tier.gcp-us-central1.cockroachlabs.cloud:26257/defaultdb?sslmode=verify-full', 'CockroachDB Cloud connection'),
(2924, 'postgresql://root@localhost:26257/',                                           'CockroachDB with trailing slash, no db'),
(2925, 'postgresql://root@localhost:26257',                                            'CockroachDB no path'),
(2926, 'POSTGRESQL://ROOT@LOCALHOST:26257/defaultdb',                                  'CockroachDB uppercase scheme+userinfo+host'),
(2927, 'postgres://root@localhost:26257/defaultdb',                                    'CockroachDB with postgres:// alias'),
(2928, 'postgresql://root@localhost:26257/defaultdb?options=--cluster%3Dfree-tier-123', 'CockroachDB with encoded cluster option'),
(2929, 'postgresql://root@localhost:26257/db%2Dname',                                  'CockroachDB with percent-encoded db name'),
(2930, 'postgresql://root:pass%40word@localhost:26257/defaultdb',                       'CockroachDB with encoded @ in password'),
(2931, 'postgresql://root@127.0.0.1:26257/defaultdb',                                  'CockroachDB with IPv4 host'),
(2932, 'postgresql://root@[::1]:26257/defaultdb',                                      'CockroachDB with IPv6 host'),
(2933, 'postgresql://root@localhost:5432/defaultdb',                                    'PostgreSQL standard port (not CockroachDB)'),
(2934, 'postgresql://root@crdb-node1.example.com:26257/defaultdb?application_name=myapp&connect_timeout=10', 'CockroachDB with app config params');
