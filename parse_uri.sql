-- =============================================================================
-- parse_uri.sql -- RFC 3986 URI Parser and Normalizer for CockroachDB
-- =============================================================================
--
-- Creates parse_uri(TEXT) -> JSONB that parses a URI and returns:
--   scheme, userinfo, host, port, path, query, fragment,
--   authority, normalized_uri
--
-- Normalization applied:
--   Syntax-based  (RFC 3986 6.2.2): case, percent-encoding, dot segments
--   Scheme-based  (RFC 3986 6.2.3): default port removal, empty path -> "/"
--
-- Architecture: two small PL/pgSQL functions (_uri_parse_raw, _uri_normalize)
-- composed by a SQL function (parse_uri) to avoid CockroachDB PL/pgSQL
-- overhead with large function bodies.
-- =============================================================================

-- helper: normalize percent-encoding in a URI component
-- 1) decode unreserved characters  (%7E -> ~)
-- 2) uppercase hex digits          (%c3%a9 -> %C3%A9)
-- Jumps between '%' positions for efficiency.
CREATE OR REPLACE FUNCTION _uri_normalize_pct(input TEXT) RETURNS TEXT AS $$
DECLARE
  result TEXT := '';
  remainder TEXT;
  pos INT;
  hex_str TEXT;
  code INT;
  c1 CHAR;
  c2 CHAR;
  v1 INT;
  v2 INT;
BEGIN
  IF input IS NULL THEN RETURN NULL; END IF;
  IF position('%' IN input) = 0 THEN RETURN input; END IF;

  remainder := input;
  LOOP
    pos := position('%' IN remainder);
    IF pos = 0 THEN
      result := result || remainder;
      EXIT;
    END IF;
    IF pos > 1 THEN
      result := result || substring(remainder FROM 1 FOR pos - 1);
    END IF;
    IF pos + 2 <= length(remainder) THEN
      hex_str := substring(remainder FROM pos + 1 FOR 2);
      c1 := left(hex_str, 1);
      c2 := right(hex_str, 1);
      -- validate hex chars and convert in one step
      IF (c1 >= '0' AND c1 <= '9') THEN v1 := ascii(c1) - 48;
      ELSIF (c1 >= 'a' AND c1 <= 'f') THEN v1 := ascii(c1) - 87;
      ELSIF (c1 >= 'A' AND c1 <= 'F') THEN v1 := ascii(c1) - 55;
      ELSE v1 := -1;
      END IF;
      IF (c2 >= '0' AND c2 <= '9') THEN v2 := ascii(c2) - 48;
      ELSIF (c2 >= 'a' AND c2 <= 'f') THEN v2 := ascii(c2) - 87;
      ELSIF (c2 >= 'A' AND c2 <= 'F') THEN v2 := ascii(c2) - 55;
      ELSE v2 := -1;
      END IF;
      IF v1 >= 0 AND v2 >= 0 THEN
        code := v1 * 16 + v2;
        IF code BETWEEN 65 AND 90
            OR code BETWEEN 97 AND 122
            OR code BETWEEN 48 AND 57
            OR code IN (45, 46, 95, 126)
        THEN
          result := result || chr(code);
        ELSE
          result := result || '%' || upper(hex_str);
        END IF;
        remainder := substring(remainder FROM pos + 3);
        CONTINUE;
      END IF;
    END IF;
    result := result || '%';
    remainder := substring(remainder FROM pos + 1);
  END LOOP;
  RETURN result;
END;
$$ LANGUAGE PLpgSQL IMMUTABLE;

-- helper: remove dot segments from a path per RFC 3986 Section 5.2.4
CREATE OR REPLACE FUNCTION _uri_remove_dot_segments(input TEXT) RETURNS TEXT AS $$
DECLARE
  buf TEXT;
  output TEXT := '';
  pos INT;
BEGIN
  IF input IS NULL THEN RETURN NULL; END IF;
  buf := input;
  WHILE length(buf) > 0 LOOP
    IF left(buf, 3) = '../' THEN  buf := substring(buf FROM 4); CONTINUE; END IF;
    IF left(buf, 2) = './'  THEN  buf := substring(buf FROM 3); CONTINUE; END IF;
    IF left(buf, 3) = '/./' THEN  buf := '/' || substring(buf FROM 4); CONTINUE; END IF;
    IF buf = '/.'             THEN  buf := '/'; CONTINUE; END IF;
    IF left(buf, 4) = '/../' OR buf = '/..' THEN
      IF buf = '/..' THEN buf := '/'; ELSE buf := '/' || substring(buf FROM 5); END IF;
      IF position('/' IN output) > 0 THEN
        output := left(output, length(output) - position('/' IN reverse(output)));
      ELSE
        output := '';
      END IF;
      CONTINUE;
    END IF;
    IF buf = '.' OR buf = '..' THEN buf := ''; CONTINUE; END IF;
    IF left(buf, 1) = '/' THEN
      pos := position('/' IN substring(buf FROM 2));
      IF pos > 0 THEN
        output := output || substring(buf FROM 1 FOR pos);
        buf    := substring(buf FROM pos + 1);
      ELSE
        output := output || buf;
        buf    := '';
      END IF;
    ELSE
      pos := position('/' IN buf);
      IF pos > 0 THEN
        output := output || substring(buf FROM 1 FOR pos - 1);
        buf    := substring(buf FROM pos);
      ELSE
        output := output || buf;
        buf    := '';
      END IF;
    END IF;
  END LOOP;
  RETURN output;
END;
$$ LANGUAGE PLpgSQL IMMUTABLE;

-- helper: well-known default ports per scheme
CREATE OR REPLACE FUNCTION _uri_default_port(scheme TEXT) RETURNS INT AS $$
  SELECT CASE scheme
    WHEN 'http'       THEN 80    WHEN 'https'      THEN 443
    WHEN 'ftp'        THEN 21    WHEN 'ssh'        THEN 22
    WHEN 'ws'         THEN 80    WHEN 'wss'        THEN 443
    WHEN 'telnet'     THEN 23    WHEN 'ldap'       THEN 389
    WHEN 'mysql'      THEN 3306  WHEN 'postgres'   THEN 5432
    WHEN 'postgresql' THEN 5432  WHEN 'redis'      THEN 6379
    WHEN 'kafka'      THEN 9092
    ELSE NULL
  END;
$$ LANGUAGE SQL IMMUTABLE;

-- helper: normalize IPv6 address to RFC 5952 canonical form
-- Input: content between [ and ], already lowercased. Output: compressed canonical form.
CREATE OR REPLACE FUNCTION _uri_normalize_ipv6(addr TEXT) RETURNS TEXT AS $$
DECLARE
  ipv4_tail TEXT := '';
  prefix TEXT;
  expanded TEXT;
  groups TEXT[];
  left_part TEXT;
  right_part TEXT;
  left_count INT;
  right_count INT;
  fill_count INT;
  total_groups INT := 8;
  best_start INT := 0;
  best_len INT := 0;
  cur_start INT := 0;
  cur_len INT := 0;
  sep_pos INT;
  grp TEXT;
  hi INT;
  lo INT;
  c CHAR;
  i INT;
  result TEXT;
BEGIN
  prefix := addr;

  -- Step 1: Detect and extract dotted IPv4 tail
  IF prefix ~ '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' THEN
    ipv4_tail := regexp_extract(prefix, '([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)$');
    prefix := regexp_replace(prefix, '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$', '');
    IF right(prefix, 1) = ':' AND right(prefix, 2) != '::' THEN
      prefix := substring(prefix FROM 1 FOR length(prefix) - 1);
    END IF;
    total_groups := 6;
  END IF;

  -- Step 2: Expand :: to fill missing groups
  IF position('::' IN prefix) > 0 THEN
    sep_pos := position('::' IN prefix);
    left_part := substring(prefix FROM 1 FOR sep_pos - 1);
    right_part := substring(prefix FROM sep_pos + 2);

    IF left_part = '' THEN left_count := 0;
    ELSE left_count := length(left_part) - length(replace(left_part, ':', '')) + 1;
    END IF;

    IF right_part = '' THEN right_count := 0;
    ELSE right_count := length(right_part) - length(replace(right_part, ':', '')) + 1;
    END IF;

    fill_count := total_groups - left_count - right_count;

    expanded := '';
    IF left_part != '' THEN expanded := left_part; END IF;
    i := 1;
    WHILE i <= fill_count LOOP
      IF expanded != '' THEN expanded := expanded || ':'; END IF;
      expanded := expanded || '0';
      i := i + 1;
    END LOOP;
    IF right_part != '' THEN
      IF expanded != '' THEN expanded := expanded || ':'; END IF;
      expanded := expanded || right_part;
    END IF;
  ELSE
    expanded := prefix;
  END IF;

  -- Step 3: Strip leading zeros from each group (build new string directly)
  result := '';
  i := 1;
  WHILE i <= total_groups LOOP
    IF i > 1 THEN result := result || ':'; END IF;
    grp := split_part(expanded, ':', i);
    WHILE length(grp) > 1 AND left(grp, 1) = '0' LOOP
      grp := substring(grp FROM 2);
    END LOOP;
    IF grp = '' THEN grp := '0'; END IF;
    result := result || grp;
    i := i + 1;
  END LOOP;
  expanded := result;

  -- Convert to array for O(1) read access (replaces repeated split_part calls below)
  groups := string_to_array(expanded, ':');

  -- Step 6: IPv4-mapped conversion (::ffff:hex:hex -> ::ffff:d.d.d.d)
  IF total_groups = 8 AND ipv4_tail = '' THEN
    IF groups[1] = '0'
       AND groups[2] = '0'
       AND groups[3] = '0'
       AND groups[4] = '0'
       AND groups[5] = '0'
       AND groups[6] = 'ffff'
    THEN
      grp := lpad(groups[7], 4, '0');
      c := substring(grp FROM 1 FOR 1);
      IF c >= '0' AND c <= '9' THEN hi := ascii(c) - 48;
      ELSE hi := ascii(c) - 87; END IF;
      hi := hi * 16;
      c := substring(grp FROM 2 FOR 1);
      IF c >= '0' AND c <= '9' THEN hi := hi + ascii(c) - 48;
      ELSE hi := hi + ascii(c) - 87; END IF;
      c := substring(grp FROM 3 FOR 1);
      IF c >= '0' AND c <= '9' THEN lo := ascii(c) - 48;
      ELSE lo := ascii(c) - 87; END IF;
      lo := lo * 16;
      c := substring(grp FROM 4 FOR 1);
      IF c >= '0' AND c <= '9' THEN lo := lo + ascii(c) - 48;
      ELSE lo := lo + ascii(c) - 87; END IF;
      ipv4_tail := hi::TEXT || '.' || lo::TEXT;

      grp := lpad(groups[8], 4, '0');
      c := substring(grp FROM 1 FOR 1);
      IF c >= '0' AND c <= '9' THEN hi := ascii(c) - 48;
      ELSE hi := ascii(c) - 87; END IF;
      hi := hi * 16;
      c := substring(grp FROM 2 FOR 1);
      IF c >= '0' AND c <= '9' THEN hi := hi + ascii(c) - 48;
      ELSE hi := hi + ascii(c) - 87; END IF;
      c := substring(grp FROM 3 FOR 1);
      IF c >= '0' AND c <= '9' THEN lo := ascii(c) - 48;
      ELSE lo := ascii(c) - 87; END IF;
      lo := lo * 16;
      c := substring(grp FROM 4 FOR 1);
      IF c >= '0' AND c <= '9' THEN lo := lo + ascii(c) - 48;
      ELSE lo := lo + ascii(c) - 87; END IF;
      ipv4_tail := ipv4_tail || '.' || hi::TEXT || '.' || lo::TEXT;

      total_groups := 6;
      expanded := groups[1] || ':' || groups[2] || ':'
               || groups[3] || ':' || groups[4] || ':'
               || groups[5] || ':' || groups[6];
      groups := string_to_array(expanded, ':');
    END IF;
  END IF;

  -- Step 4: Find longest consecutive run of '0' groups (leftmost wins per RFC 5952)
  best_start := 0; best_len := 0;
  cur_start := 0; cur_len := 0;
  i := 1;
  WHILE i <= total_groups LOOP
    IF groups[i] = '0' THEN
      IF cur_len = 0 THEN cur_start := i; END IF;
      cur_len := cur_len + 1;
    ELSE
      IF cur_len > best_len THEN best_start := cur_start; best_len := cur_len; END IF;
      cur_len := 0;
    END IF;
    i := i + 1;
  END LOOP;
  IF cur_len > best_len THEN best_start := cur_start; best_len := cur_len; END IF;

  -- Step 5: Replace longest run with :: (only if run length >= 2)
  IF best_len >= 2 THEN
    left_part := '';
    i := 1;
    WHILE i <= best_start - 1 LOOP
      IF i > 1 THEN left_part := left_part || ':'; END IF;
      left_part := left_part || groups[i];
      i := i + 1;
    END LOOP;

    right_part := '';
    i := best_start + best_len;
    WHILE i <= total_groups LOOP
      IF i > best_start + best_len THEN right_part := right_part || ':'; END IF;
      right_part := right_part || groups[i];
      i := i + 1;
    END LOOP;

    result := left_part || '::' || right_part;
  ELSE
    result := expanded;
  END IF;

  -- Append IPv4 tail
  IF ipv4_tail != '' THEN
    IF right(result, 1) = ':' THEN
      result := result || ipv4_tail;
    ELSE
      result := result || ':' || ipv4_tail;
    END IF;
  END IF;

  RETURN result;
END;
$$ LANGUAGE PLpgSQL STABLE;

-- =============================================================================
-- PHASE 1: Parse URI into raw components (small PL/pgSQL function)
-- =============================================================================
CREATE OR REPLACE FUNCTION _uri_parse_raw(input TEXT) RETURNS JSONB AS $$
DECLARE
  remainder TEXT;
  raw_scheme TEXT; raw_authority TEXT; raw_path TEXT;
  raw_query TEXT; raw_fragment TEXT; raw_userinfo TEXT;
  raw_host TEXT; raw_port TEXT;
  host_port TEXT; pos INT; bracket_end INT;
  has_authority BOOLEAN := FALSE;
BEGIN
  IF input IS NULL THEN RETURN NULL; END IF;
  remainder := input;

  -- fragment
  pos := position('#' IN remainder);
  IF pos > 0 THEN
    raw_fragment := substring(remainder FROM pos + 1);
    remainder := substring(remainder FROM 1 FOR pos - 1);
  END IF;

  -- query
  pos := position('?' IN remainder);
  IF pos > 0 THEN
    raw_query := substring(remainder FROM pos + 1);
    remainder := substring(remainder FROM 1 FOR pos - 1);
  END IF;

  -- scheme
  IF remainder ~ '^[a-zA-Z][a-zA-Z0-9+.-]*:' THEN
    pos := position(':' IN remainder);
    raw_scheme := substring(remainder FROM 1 FOR pos - 1);
    remainder := substring(remainder FROM pos + 1);
  END IF;

  -- authority
  IF left(remainder, 2) = '//' THEN
    has_authority := TRUE;
    remainder := substring(remainder FROM 3);
    pos := position('/' IN remainder);
    IF pos > 0 THEN
      raw_authority := substring(remainder FROM 1 FOR pos - 1);
      raw_path := substring(remainder FROM pos);
    ELSE
      raw_authority := remainder;
      raw_path := '';
    END IF;
  ELSE
    raw_path := remainder;
  END IF;

  -- decompose authority
  IF raw_authority IS NOT NULL THEN
    host_port := raw_authority;
    IF raw_authority ~ '@' THEN
      raw_userinfo := regexp_extract(raw_authority, '^(.*)@');
      host_port := regexp_extract(raw_authority, '@([^@]*)$');
    END IF;
    IF left(host_port, 1) = '[' THEN
      bracket_end := position(']' IN host_port);
      IF bracket_end > 0 THEN
        raw_host := substring(host_port FROM 1 FOR bracket_end);
        IF length(host_port) > bracket_end
           AND substring(host_port FROM bracket_end + 1 FOR 1) = ':' THEN
          raw_port := substring(host_port FROM bracket_end + 2);
        END IF;
      ELSE
        raw_host := host_port;
      END IF;
    ELSE
      IF host_port ~ ':' THEN
        raw_host := regexp_extract(host_port, '^(.*):');
        raw_port := regexp_extract(host_port, ':([^:]*)$');
      ELSE
        raw_host := host_port;
      END IF;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'scheme', raw_scheme, 'userinfo', raw_userinfo,
    'host', raw_host, 'port', raw_port,
    'path', raw_path, 'query', raw_query,
    'fragment', raw_fragment,
    'has_authority', has_authority
  );
END;
$$ LANGUAGE PLpgSQL STABLE;

-- =============================================================================
-- PHASE 2: Normalize parsed components (small PL/pgSQL function)
-- =============================================================================
CREATE OR REPLACE FUNCTION _uri_normalize(raw JSONB) RETURNS JSONB AS $$
DECLARE
  norm_scheme TEXT; norm_userinfo TEXT; norm_host TEXT; norm_port TEXT;
  norm_path TEXT; norm_query TEXT; norm_fragment TEXT;
  norm_authority TEXT; norm_uri TEXT;
  raw_host TEXT; raw_port TEXT; raw_query TEXT; raw_fragment TEXT;
  has_authority BOOLEAN;
  default_port INT; cleaned_port TEXT;
BEGIN
  IF raw IS NULL THEN RETURN NULL; END IF;

  has_authority := (raw->>'has_authority')::BOOLEAN;
  raw_host := raw->>'host';
  raw_port := raw->>'port';
  raw_query := raw->>'query';
  raw_fragment := raw->>'fragment';

  -- syntax normalization
  norm_scheme := lower(raw->>'scheme');

  IF raw_host IS NOT NULL THEN
    IF raw_host ~ '^\[.*\]$' THEN
      norm_host := '[' || _uri_normalize_ipv6(
        lower(substring(raw_host FROM 2 FOR length(raw_host) - 2))
      ) || ']';
    ELSE
      norm_host := lower(_uri_normalize_pct(raw_host));
    END IF;
  END IF;

  IF raw_port IS NOT NULL THEN
    IF raw_port = '' THEN norm_port := NULL;
    ELSE norm_port := raw_port;
    END IF;
  END IF;

  norm_userinfo := _uri_normalize_pct(raw->>'userinfo');
  IF norm_userinfo IS NOT NULL AND (norm_userinfo = '' OR norm_userinfo = ':') THEN
    norm_userinfo := NULL;
  END IF;
  norm_path := _uri_remove_dot_segments(_uri_normalize_pct(raw->>'path'));
  IF norm_scheme = 'file' AND norm_path ~ '^/[a-z]:' THEN
    norm_path := '/' || upper(substring(norm_path FROM 2 FOR 1)) || substring(norm_path FROM 3);
  END IF;
  IF norm_scheme = 'file' AND norm_host = 'localhost' THEN
    norm_host := '';
  END IF;
  norm_query := _uri_normalize_pct(raw_query);
  norm_fragment := _uri_normalize_pct(raw_fragment);

  -- scheme-based normalization: default port removal
  IF norm_port IS NOT NULL AND norm_port ~ '^[0-9]+$' THEN
    cleaned_port := regexp_replace(norm_port, '^0+', '');
    IF cleaned_port = '' THEN cleaned_port := '0'; END IF;
    default_port := _uri_default_port(norm_scheme);
    IF default_port IS NOT NULL AND cleaned_port = default_port::TEXT THEN
      norm_port := NULL;
    ELSE
      norm_port := cleaned_port;
    END IF;
  END IF;

  -- empty path -> "/"
  IF has_authority AND (norm_path IS NULL OR norm_path = '') THEN
    norm_path := '/';
  END IF;

  -- relative reference: prefix path with ./ to prevent scheme-like confusion
  IF norm_scheme IS NULL AND NOT has_authority
     AND norm_path ~ '^[a-zA-Z][a-zA-Z0-9+.-]*:' THEN
    norm_path := './' || norm_path;
  END IF;

  -- reassemble authority
  IF has_authority THEN
    norm_authority := '';
    IF norm_userinfo IS NOT NULL THEN norm_authority := norm_userinfo || '@'; END IF;
    norm_authority := norm_authority || coalesce(norm_host, '');
    IF norm_port IS NOT NULL THEN norm_authority := norm_authority || ':' || norm_port; END IF;
  END IF;

  -- reassemble URI
  norm_uri := '';
  IF norm_scheme IS NOT NULL THEN norm_uri := norm_scheme || ':'; END IF;
  IF has_authority THEN norm_uri := norm_uri || '//' || norm_authority; END IF;
  norm_uri := norm_uri || coalesce(norm_path, '');
  IF raw_query IS NOT NULL THEN norm_uri := norm_uri || '?' || coalesce(norm_query, ''); END IF;
  IF raw_fragment IS NOT NULL THEN norm_uri := norm_uri || '#' || coalesce(norm_fragment, ''); END IF;

  RETURN jsonb_build_object(
    'scheme', norm_scheme, 'userinfo', norm_userinfo,
    'host', norm_host, 'port', norm_port,
    'path', norm_path, 'query', norm_query,
    'fragment', norm_fragment, 'authority', norm_authority,
    'normalized_uri', norm_uri
  );
END;
$$ LANGUAGE PLpgSQL STABLE;

-- =============================================================================
-- MAIN FUNCTION: compose parse + normalize via SQL (minimal overhead)
-- =============================================================================
CREATE OR REPLACE FUNCTION parse_uri(input TEXT) RETURNS JSONB AS $$
  SELECT _uri_normalize(_uri_parse_raw(input));
$$ LANGUAGE SQL STABLE;
