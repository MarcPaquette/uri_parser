#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <uriparser/Uri.h>

#define MAX_URI_LEN 65536
#define MAX_LINE_LEN 131072

/* ── helpers ────────────────────────────────────────────────────────── */

static char *uri_to_string(UriUriA *uri) {
    int len;
    if (uriToStringCharsRequiredA(uri, &len) != URI_SUCCESS)
        return NULL;
    len++;
    char *buf = malloc(len);
    if (!buf) return NULL;
    if (uriToStringA(buf, uri, len, NULL) != URI_SUCCESS) {
        free(buf);
        return NULL;
    }
    return buf;
}

/* Pure uriparser: parse + uriNormalizeSyntaxA + recompose. Zero custom code. */
static char *normalize_pure(const char *input) {
    UriUriA uri;
    const char *errPos;
    if (uriParseSingleUriA(&uri, input, &errPos) != URI_SUCCESS) {
        uriFreeUriMembersA(&uri);
        return strdup(input);
    }
    uriNormalizeSyntaxA(&uri);
    char *result = uri_to_string(&uri);
    uriFreeUriMembersA(&uri);
    return result ? result : strdup(input);
}

/* ── --parse mode ───────────────────────────────────────────────────── */

static int mode_parse(void) {
    char line[MAX_LINE_LEN];
    int ok = 0, fail = 0, total = 0;

    while (fgets(line, sizeof(line), stdin)) {
        size_t len = strlen(line);
        while (len > 0 && (line[len-1] == '\n' || line[len-1] == '\r'))
            line[--len] = '\0';
        if (len == 0) continue;

        char *tab = strchr(line, '\t');
        if (!tab) continue;
        *tab = '\0';
        const char *id = line;
        const char *uri_str = tab + 1;

        total++;
        UriUriA uri;
        const char *errPos;
        int rc = uriParseSingleUriA(&uri, uri_str, &errPos);
        if (rc == URI_SUCCESS) {
            printf("PARSE OK   %s\t%s\n", id, uri_str);
            ok++;
        } else {
            int error_at = (int)(errPos - uri_str);
            printf("PARSE FAIL %s\t%s\terror_at=%d\n", id, uri_str, error_at);
            fail++;
        }
        uriFreeUriMembersA(&uri);
    }

    printf("\n--- Parse Summary ---\n");
    printf("Total: %d  OK: %d  FAIL: %d\n", total, ok, fail);
    return 0;
}

/* ── --equiv mode ───────────────────────────────────────────────────── */

struct equiv_row {
    int group_id;
    int variant_id;
    char uri[MAX_URI_LEN];
    char norm_level[32];
    int is_canonical;
    int is_equivalent;
};

static int mode_equiv(void) {
    int cap = 512, count = 0;
    struct equiv_row *rows = malloc(cap * sizeof(struct equiv_row));
    char line[MAX_LINE_LEN];

    while (fgets(line, sizeof(line), stdin)) {
        size_t len = strlen(line);
        while (len > 0 && (line[len-1] == '\n' || line[len-1] == '\r'))
            line[--len] = '\0';
        if (len == 0) continue;

        if (count >= cap) {
            cap *= 2;
            rows = realloc(rows, cap * sizeof(struct equiv_row));
        }

        struct equiv_row *r = &rows[count];
        char *fields[6];
        char *p = line;
        for (int i = 0; i < 6; i++) {
            fields[i] = p;
            if (i < 5) {
                char *t = strchr(p, '\t');
                if (!t) break;
                *t = '\0';
                p = t + 1;
            }
        }
        r->group_id = atoi(fields[0]);
        r->variant_id = atoi(fields[1]);
        strncpy(r->uri, fields[2], MAX_URI_LEN - 1);
        r->uri[MAX_URI_LEN - 1] = '\0';
        strncpy(r->norm_level, fields[3], sizeof(r->norm_level) - 1);
        r->norm_level[sizeof(r->norm_level) - 1] = '\0';
        r->is_canonical = atoi(fields[4]);
        r->is_equivalent = atoi(fields[5]);
        count++;
    }

    int groups_pass = 0, groups_fail = 0, groups_total = 0;

    int i = 0;
    while (i < count) {
        int gid = rows[i].group_id;
        int start = i;
        while (i < count && rows[i].group_id == gid)
            i++;
        int end = i;
        groups_total++;

        const char *level = rows[start].norm_level;
        int is_positive = rows[start].is_equivalent;

        char **normalized = malloc((end - start) * sizeof(char *));
        for (int j = start; j < end; j++)
            normalized[j - start] = normalize_pure(rows[j].uri);

        if (is_positive) {
            int pass = 1;
            for (int j = 1; j < end - start; j++) {
                if (strcmp(normalized[0], normalized[j]) != 0) {
                    pass = 0;
                    break;
                }
            }
            if (pass) {
                printf("EQUIV PASS  group=%d level=%s canonical=%s\n",
                       gid, level, normalized[0]);
                groups_pass++;
            } else {
                printf("EQUIV FAIL  group=%d level=%s (positive: normalized forms differ)\n",
                       gid, level);
                for (int j = 0; j < end - start; j++)
                    printf("  variant=%d  input=%-60s  normalized=%s\n",
                           rows[start + j].variant_id, rows[start + j].uri,
                           normalized[j]);
                groups_fail++;
            }
        } else {
            int all_same = 1;
            for (int j = 1; j < end - start; j++) {
                if (strcmp(normalized[0], normalized[j]) != 0) {
                    all_same = 0;
                    break;
                }
            }
            if (!all_same) {
                printf("EQUIV PASS  group=%d level=%s (negative: forms differ as expected)\n",
                       gid, level);
                groups_pass++;
            } else {
                printf("EQUIV FAIL  group=%d level=%s (negative: forms should differ but don't)\n",
                       gid, level);
                for (int j = 0; j < end - start; j++)
                    printf("  variant=%d  input=%-60s  normalized=%s\n",
                           rows[start + j].variant_id, rows[start + j].uri,
                           normalized[j]);
                groups_fail++;
            }
        }

        for (int j = 0; j < end - start; j++)
            free(normalized[j]);
        free(normalized);
    }

    printf("\n--- Equivalence Summary (pure uriparser) ---\n");
    printf("Groups: %d  Pass: %d  Fail: %d\n", groups_total, groups_pass, groups_fail);

    free(rows);
    return groups_fail > 0 ? 1 : 0;
}

/* ── main ───────────────────────────────────────────────────────────── */

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s --parse | --equiv\n", argv[0]);
        return 1;
    }

    if (strcmp(argv[1], "--parse") == 0)
        return mode_parse();
    if (strcmp(argv[1], "--equiv") == 0)
        return mode_equiv();

    fprintf(stderr, "Unknown mode: %s\n", argv[1]);
    return 1;
}
