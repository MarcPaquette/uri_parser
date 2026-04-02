-- =============================================================================
-- parse_uri.sql -- RFC 3986 URI Parser and Normalizer for CockroachDB
-- =============================================================================
--
-- Single entry point returning JSONB with: scheme, userinfo, host, port,
-- path, query, fragment, authority, normalized_uri
--
--   parse_uri(TEXT)  Pure SQL, sub-millisecond per call.
--                    Full RFC 3986 normalization: case normalization,
--                    percent-encoding decode/uppercase, dot-segment removal,
--                    default port removal, empty path, IPv6 RFC 5952 via INET,
--                    file scheme drive letter and localhost normalization.
--
-- Pure SQL (LANGUAGE SQL) functions are inlined by CockroachDB's optimizer
-- with zero compilation overhead, unlike PL/pgSQL which incurs ~2s per
-- statement for function chain compilation.
-- =============================================================================

-- helper: normalize percent-encoding in a URI component (pure SQL)
-- 1) decode unreserved characters  (%7E -> ~)
-- 2) uppercase hex digits          (%c3%a9 -> %C3%A9)
-- Jumps between '%' positions via recursive CTE.
CREATE OR REPLACE FUNCTION _uri_pct_norm(input TEXT) RETURNS TEXT AS $$
  SELECT CASE
    WHEN input IS NULL THEN NULL
    WHEN position('%' IN input) = 0 THEN input
    ELSE (
      WITH RECURSIVE pct(remainder, result) AS (
        SELECT input, ''::TEXT
        UNION ALL
        SELECT
          -- advance remainder past this percent triplet
          CASE
            -- no more '%' → consume all remaining
            WHEN position('%' IN remainder) = 0 THEN ''
            -- '%' at end or with <2 chars after → skip the '%', keep rest
            WHEN position('%' IN remainder) + 2 > length(remainder) THEN
              substring(remainder FROM position('%' IN remainder) + 1)
            ELSE
              -- We have a '%XX' triplet starting at pos
              (SELECT
                CASE
                  -- valid hex pair → skip all 3 chars (%XX)
                  WHEN (
                    (substring(remainder FROM position('%' IN remainder) + 1 FOR 1) BETWEEN '0' AND '9'
                     OR substring(remainder FROM position('%' IN remainder) + 1 FOR 1) BETWEEN 'a' AND 'f'
                     OR substring(remainder FROM position('%' IN remainder) + 1 FOR 1) BETWEEN 'A' AND 'F')
                    AND
                    (substring(remainder FROM position('%' IN remainder) + 2 FOR 1) BETWEEN '0' AND '9'
                     OR substring(remainder FROM position('%' IN remainder) + 2 FOR 1) BETWEEN 'a' AND 'f'
                     OR substring(remainder FROM position('%' IN remainder) + 2 FOR 1) BETWEEN 'A' AND 'F')
                  ) THEN substring(remainder FROM position('%' IN remainder) + 3)
                  -- invalid hex → skip just the '%'
                  ELSE substring(remainder FROM position('%' IN remainder) + 1)
                END
              )
          END,
          -- accumulate result
          result ||
          CASE
            WHEN position('%' IN remainder) = 0 THEN remainder
            ELSE
              -- text before the '%'
              CASE WHEN position('%' IN remainder) > 1
                   THEN substring(remainder FROM 1 FOR position('%' IN remainder) - 1)
                   ELSE '' END
              ||
              -- the '%XX' triplet (or just '%')
              CASE
                WHEN position('%' IN remainder) + 2 > length(remainder) THEN '%'
                WHEN (
                  (substring(remainder FROM position('%' IN remainder) + 1 FOR 1) BETWEEN '0' AND '9'
                   OR substring(remainder FROM position('%' IN remainder) + 1 FOR 1) BETWEEN 'a' AND 'f'
                   OR substring(remainder FROM position('%' IN remainder) + 1 FOR 1) BETWEEN 'A' AND 'F')
                  AND
                  (substring(remainder FROM position('%' IN remainder) + 2 FOR 1) BETWEEN '0' AND '9'
                   OR substring(remainder FROM position('%' IN remainder) + 2 FOR 1) BETWEEN 'a' AND 'f'
                   OR substring(remainder FROM position('%' IN remainder) + 2 FOR 1) BETWEEN 'A' AND 'F')
                ) THEN
                  -- valid hex pair: compute the byte value
                  (SELECT
                    CASE
                      -- unreserved char → decode to literal
                      WHEN v1 * 16 + v2 BETWEEN 65 AND 90   -- A-Z
                        OR v1 * 16 + v2 BETWEEN 97 AND 122  -- a-z
                        OR v1 * 16 + v2 BETWEEN 48 AND 57   -- 0-9
                        OR v1 * 16 + v2 IN (45, 46, 95, 126) -- - . _ ~
                      THEN chr(v1 * 16 + v2)
                      -- reserved → uppercase the hex
                      ELSE '%' || upper(substring(remainder FROM position('%' IN remainder) + 1 FOR 2))
                    END
                   FROM (SELECT
                     CASE
                       WHEN substring(remainder FROM position('%' IN remainder) + 1 FOR 1) BETWEEN '0' AND '9'
                       THEN ascii(substring(remainder FROM position('%' IN remainder) + 1 FOR 1)) - 48
                       WHEN substring(remainder FROM position('%' IN remainder) + 1 FOR 1) BETWEEN 'a' AND 'f'
                       THEN ascii(substring(remainder FROM position('%' IN remainder) + 1 FOR 1)) - 87
                       ELSE ascii(substring(remainder FROM position('%' IN remainder) + 1 FOR 1)) - 55
                     END AS v1,
                     CASE
                       WHEN substring(remainder FROM position('%' IN remainder) + 2 FOR 1) BETWEEN '0' AND '9'
                       THEN ascii(substring(remainder FROM position('%' IN remainder) + 2 FOR 1)) - 48
                       WHEN substring(remainder FROM position('%' IN remainder) + 2 FOR 1) BETWEEN 'a' AND 'f'
                       THEN ascii(substring(remainder FROM position('%' IN remainder) + 2 FOR 1)) - 87
                       ELSE ascii(substring(remainder FROM position('%' IN remainder) + 2 FOR 1)) - 55
                     END AS v2
                   ) hex_vals)
                ELSE '%'
              END
          END
        FROM pct
        WHERE length(remainder) > 0
      )
      SELECT result FROM pct WHERE length(remainder) = 0 ORDER BY length(remainder) LIMIT 1
    )
  END;
$$ LANGUAGE SQL IMMUTABLE;

-- helper: remove dot segments from a path per RFC 3986 Section 5.2.4 (pure SQL)
CREATE OR REPLACE FUNCTION _uri_dot_norm(input TEXT) RETURNS TEXT AS $$
  SELECT CASE
    WHEN input IS NULL THEN NULL
    WHEN position('.' IN input) = 0 THEN input
    ELSE (
      WITH RECURSIVE dot(buf, output) AS (
        SELECT input, ''::TEXT
        UNION ALL
        SELECT
          CASE
            WHEN left(buf, 3) = '../' THEN substring(buf FROM 4)
            WHEN left(buf, 2) = './'  THEN substring(buf FROM 3)
            WHEN left(buf, 3) = '/./' THEN '/' || substring(buf FROM 4)
            WHEN buf = '/.'           THEN '/'
            WHEN left(buf, 4) = '/../' THEN '/' || substring(buf FROM 5)
            WHEN buf = '/..'          THEN '/'
            WHEN buf = '.' OR buf = '..' THEN ''
            WHEN left(buf, 1) = '/' THEN
              CASE WHEN position('/' IN substring(buf FROM 2)) > 0
                   THEN substring(buf FROM position('/' IN substring(buf FROM 2)) + 1)
                   ELSE '' END
            ELSE
              CASE WHEN position('/' IN buf) > 0
                   THEN substring(buf FROM position('/' IN buf))
                   ELSE '' END
          END,
          CASE
            WHEN left(buf, 3) = '../' THEN output
            WHEN left(buf, 2) = './'  THEN output
            WHEN left(buf, 3) = '/./' THEN output
            WHEN buf = '/.'           THEN output
            WHEN left(buf, 4) = '/../' OR buf = '/..' THEN
              CASE WHEN position('/' IN output) > 0
                   THEN left(output, length(output) - position('/' IN reverse(output)))
                   ELSE '' END
            WHEN buf = '.' OR buf = '..' THEN output
            WHEN left(buf, 1) = '/' THEN
              output || CASE WHEN position('/' IN substring(buf FROM 2)) > 0
                             THEN substring(buf FROM 1 FOR position('/' IN substring(buf FROM 2)))
                             ELSE buf END
            ELSE
              output || CASE WHEN position('/' IN buf) > 0
                             THEN substring(buf FROM 1 FOR position('/' IN buf) - 1)
                             ELSE buf END
          END
        FROM dot
        WHERE length(buf) > 0
      )
      SELECT output FROM dot WHERE length(buf) = 0 LIMIT 1
    )
  END;
$$ LANGUAGE SQL IMMUTABLE;

-- =============================================================================
-- MAIN FUNCTION: Full RFC 3986 parse + normalize, pure SQL, sub-millisecond.
-- =============================================================================
CREATE OR REPLACE FUNCTION parse_uri(input TEXT) RETURNS JSONB AS $$
  WITH frag_split AS (
    SELECT
      CASE WHEN position('#' IN input) > 0
           THEN left(input, position('#' IN input) - 1)
           ELSE input END AS no_frag,
      CASE WHEN position('#' IN input) > 0
           THEN substring(input FROM position('#' IN input) + 1)
           ELSE NULL END AS frag
  ),
  query_split AS (
    SELECT
      CASE WHEN position('?' IN no_frag) > 0
           THEN left(no_frag, position('?' IN no_frag) - 1)
           ELSE no_frag END AS no_query,
      CASE WHEN position('?' IN no_frag) > 0
           THEN substring(no_frag FROM position('?' IN no_frag) + 1)
           ELSE NULL END AS query,
      frag
    FROM frag_split
  ),
  scheme_split AS (
    SELECT
      CASE WHEN no_query ~ '^[a-zA-Z][a-zA-Z0-9+.-]*:'
           THEN lower(left(no_query, position(':' IN no_query) - 1))
           ELSE NULL END AS scheme,
      CASE WHEN no_query ~ '^[a-zA-Z][a-zA-Z0-9+.-]*:'
           THEN substring(no_query FROM position(':' IN no_query) + 1)
           ELSE no_query END AS after_scheme,
      query, frag
    FROM query_split
  ),
  auth_split AS (
    SELECT
      scheme,
      left(after_scheme, 2) = '//' AS has_auth,
      CASE WHEN left(after_scheme, 2) = '//' THEN
        CASE WHEN position('/' IN substring(after_scheme FROM 3)) > 0
             THEN left(substring(after_scheme FROM 3),
                       position('/' IN substring(after_scheme FROM 3)) - 1)
             ELSE substring(after_scheme FROM 3) END
      ELSE NULL END AS authority,
      CASE WHEN left(after_scheme, 2) = '//' THEN
        CASE WHEN position('/' IN substring(after_scheme FROM 3)) > 0
             THEN substring(substring(after_scheme FROM 3)
                            FROM position('/' IN substring(after_scheme FROM 3)))
             ELSE '' END
      ELSE after_scheme END AS path,
      query, frag
    FROM scheme_split
  ),
  host_split AS (
    SELECT
      scheme, has_auth, path, query, frag,
      CASE WHEN authority IS NOT NULL AND position('@' IN authority) > 0
           THEN left(authority,
                length(authority) - position('@' IN reverse(authority)))
           ELSE NULL END AS userinfo,
      CASE WHEN authority IS NOT NULL AND position('@' IN authority) > 0
           THEN substring(authority
                FROM length(authority) - position('@' IN reverse(authority)) + 2)
           ELSE authority END AS hostport
    FROM auth_split
  ),
  components AS (
    SELECT
      scheme, has_auth, path, query, frag,
      CASE WHEN userinfo IS NOT NULL AND userinfo != '' AND userinfo != ':'
           THEN userinfo ELSE NULL END AS userinfo,
      CASE
        -- IPv6 / IPvFuture: bracketed host
        WHEN hostport IS NOT NULL AND left(hostport, 1) = '[' THEN
          CASE
            WHEN position(']' IN hostport) > 0 THEN
              substring(hostport FROM 1 FOR position(']' IN hostport))
            ELSE hostport
          END
        -- Regular host with port
        WHEN hostport IS NOT NULL AND position(':' IN hostport) > 0
        THEN left(hostport,
                  length(hostport) - position(':' IN reverse(hostport)))
        WHEN hostport IS NOT NULL THEN hostport
        ELSE NULL
      END AS raw_host,
      CASE
        -- Bracketed host: port is after ']:'
        WHEN hostport IS NOT NULL AND left(hostport, 1) = '[' THEN
          CASE
            WHEN position(']' IN hostport) > 0
                 AND length(hostport) > position(']' IN hostport)
                 AND substring(hostport FROM position(']' IN hostport) + 1 FOR 1) = ':'
            THEN substring(hostport FROM position(']' IN hostport) + 2)
            ELSE NULL
          END
        -- Regular host: port after last ':'
        WHEN hostport IS NOT NULL AND position(':' IN hostport) > 0
        THEN substring(hostport
                       FROM length(hostport) - position(':' IN reverse(hostport)) + 2)
        ELSE NULL
      END AS raw_port
    FROM host_split
  ),
  host_normalized AS (
    SELECT
      scheme, has_auth, path, query, frag, userinfo, raw_port,
      CASE
        -- IPv6: normalize via INET host() for RFC 5952 compression
        WHEN raw_host IS NOT NULL AND left(raw_host, 1) = '['
             AND right(raw_host, 1) = ']'
             AND lower(substring(raw_host FROM 2 FOR 1)) != 'v' THEN
          CASE
            -- Zone ID: strip %25... before INET cast, re-append after
            WHEN position('%25' IN raw_host) > 0 THEN
              '[' || host(
                lower(substring(raw_host FROM 2 FOR position('%25' IN raw_host) - 2))::INET
              ) || '%25' || substring(raw_host FROM position('%25' IN raw_host) + 3
                                      FOR position(']' IN raw_host) - position('%25' IN raw_host) - 3)
              || ']'
            ELSE
              '[' || host(
                lower(substring(raw_host FROM 2 FOR length(raw_host) - 2))::INET
              ) || ']'
          END
        -- IPvFuture: just lowercase
        WHEN raw_host IS NOT NULL AND left(raw_host, 1) = '[' THEN
          lower(raw_host)
        -- Regular host: lowercase + pct-normalize
        WHEN raw_host IS NOT NULL THEN
          lower(_uri_pct_norm(raw_host))
        ELSE NULL
      END AS host
    FROM components
  ),
  pct_normalized AS (
    SELECT
      scheme, has_auth, host, raw_port,
      _uri_pct_norm(userinfo) AS userinfo,
      _uri_pct_norm(path) AS path,
      _uri_pct_norm(query) AS query,
      _uri_pct_norm(frag) AS frag
    FROM host_normalized
  ),
  dot_normalized AS (
    SELECT
      scheme, has_auth, host, raw_port, userinfo,
      _uri_dot_norm(path) AS path,
      query, frag
    FROM pct_normalized
  ),
  normalized AS (
    SELECT
      scheme, has_auth, host, userinfo,
      -- File scheme: drive letter uppercase
      CASE WHEN scheme = 'file' AND path ~ '^/[a-z]:'
           THEN '/' || upper(substring(path FROM 2 FOR 1)) || substring(path FROM 3)
           ELSE path END AS pre_path,
      -- File scheme: localhost removal (already in host_normalized via lower)
      CASE WHEN scheme = 'file' AND host = 'localhost' THEN '' ELSE host END AS norm_host,
      query, frag,
      -- Port normalization
      CASE
        WHEN raw_port IS NULL OR raw_port = '' THEN NULL
        WHEN raw_port ~ '^[0-9]+$' THEN
          CASE WHEN (CASE WHEN regexp_replace(raw_port, '^0+', '') = '' THEN '0'
                         ELSE regexp_replace(raw_port, '^0+', '') END) =
                    (CASE scheme
                       WHEN 'http' THEN '80' WHEN 'https' THEN '443'
                       WHEN 'ftp' THEN '21' WHEN 'ssh' THEN '22'
                       WHEN 'ws' THEN '80' WHEN 'wss' THEN '443'
                       WHEN 'telnet' THEN '23' WHEN 'ldap' THEN '389'
                       WHEN 'mysql' THEN '3306' WHEN 'postgres' THEN '5432'
                       WHEN 'postgresql' THEN '5432' WHEN 'redis' THEN '6379'
                       WHEN 'kafka' THEN '9092' ELSE NULL END)
               THEN NULL
               ELSE CASE WHEN regexp_replace(raw_port, '^0+', '') = '' THEN '0'
                         ELSE regexp_replace(raw_port, '^0+', '') END
          END
        ELSE raw_port
      END AS port
    FROM dot_normalized
  ),
  final AS (
    SELECT
      scheme, userinfo,
      norm_host AS host,
      port,
      -- Empty path -> "/" for authority URIs
      CASE WHEN has_auth AND (pre_path IS NULL OR pre_path = '') THEN '/'
           -- Relative reference: prefix with ./ to prevent scheme-like confusion
           WHEN scheme IS NULL AND NOT has_auth
                AND pre_path ~ '^[a-zA-Z][a-zA-Z0-9+.-]*:'
           THEN './' || pre_path
           ELSE pre_path END AS path,
      query, frag, has_auth
    FROM normalized
  ),
  assembled AS (
    SELECT
      scheme, userinfo, host, port, path, query, frag,
      CASE WHEN has_auth THEN
        coalesce(CASE WHEN userinfo IS NOT NULL THEN userinfo || '@' ELSE '' END, '')
        || coalesce(host, '')
        || coalesce(CASE WHEN port IS NOT NULL THEN ':' || port END, '')
      ELSE NULL END AS authority,
      coalesce(CASE WHEN scheme IS NOT NULL THEN scheme || ':' END, '')
      || CASE WHEN has_auth THEN '//'
              || coalesce(CASE WHEN userinfo IS NOT NULL THEN userinfo || '@' ELSE '' END, '')
              || coalesce(host, '')
              || coalesce(CASE WHEN port IS NOT NULL THEN ':' || port END, '')
         ELSE '' END
      || coalesce(path, '')
      || coalesce(CASE WHEN query IS NOT NULL THEN '?' || query END, '')
      || coalesce(CASE WHEN frag IS NOT NULL THEN '#' || frag END, '')
      AS normalized_uri
    FROM final
  )
  SELECT CASE WHEN input IS NULL THEN NULL
              ELSE jsonb_build_object(
                'scheme', scheme, 'userinfo', userinfo,
                'host', host, 'port', port,
                'path', path, 'query', query,
                'fragment', frag, 'authority', authority,
                'normalized_uri', normalized_uri
              ) END
  FROM assembled;
$$ LANGUAGE SQL STABLE;
