// File and path helpers
#include "file.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pwd.h>
#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <sys/stat.h>

uint8_t *sx_slurp_file(const char *path, size_t *out_len) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return NULL; }
    long sz = ftell(f);
    if (sz <= 0 || sz > (16 * 1024 * 1024)) { fclose(f); return NULL; }
    rewind(f);

    uint8_t *buf = (uint8_t *)malloc((size_t)sz);
    if (!buf) { fclose(f); return NULL; }
    size_t rd = fread(buf, 1, (size_t)sz, f);
    fclose(f);
    if (rd != (size_t)sz) { free(buf); return NULL; }

    *out_len = (size_t)sz;
    return buf;
}

int sx_file_patch_bytes(const char *path, const uint8_t *find, size_t find_len,
                        const uint8_t *replace, size_t write_len) {
    if (!path || !find || find_len == 0 || !replace || write_len == 0)
        return -1;

    size_t fsize = 0;
    uint8_t *buf = sx_slurp_file(path, &fsize);
    if (!buf) return -1;

    long match = -1;
    for (long i = 0; i <= (long)fsize - (long)find_len; i++) {
        if (memcmp(buf + i, find, find_len) == 0) {
            match = i;
            break;
        }
    }
    free(buf);
    if (match < 0) return 0;

    FILE *f = fopen(path, "r+b");
    if (!f) return -1;

    if (fseek(f, match, SEEK_SET) != 0) {
        fclose(f);
        return -1;
    }
    size_t wrote = fwrite(replace, 1, write_len, f);
    int close_rc = fclose(f);
    return (wrote == write_len && close_rc == 0) ? 1 : -1;
}

void sx_file_config_path(char *buf, size_t bufsz) {
    const char *env = sx_steamplaymac_getenv("CONFIG");
    if (env && env[0]) {
        snprintf(buf, bufsz, "%s", env);
        return;
    }
    const char *home = sx_resolve_home();
    if (!home) home = "/tmp";
    sx_steamplaymac_support_path(buf, bufsz, home, "config.yaml");
}

const char *sx_resolve_home(void) {
    const char *home = getenv("HOME");
    if (home && home[0]) return home;
    struct passwd *pw = getpwuid(getuid());
    return (pw && pw->pw_dir) ? pw->pw_dir : NULL;
}

uint64_t sx_steam_build(const char *home) {
    if (!home) return 0;
    char dir[1024], path[1200], beta[64] = "";
    if (snprintf(dir, sizeof(dir), "%s/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/package", home) >= (int)sizeof(dir)) return 0;
    snprintf(path, sizeof(path), "%s/beta", dir);
    FILE *f = fopen(path, "r");
    if (f) {
        if (!fgets(beta, sizeof(beta), f) && ferror(f)) { fclose(f); return 0; }
        fclose(f);
        beta[strcspn(beta, "\r\n")] = '\0';
        for (size_t i = 0; beta[i]; i++)
            if (!isalnum((unsigned char)beta[i]) && beta[i] != '_' && beta[i] != '-') return 0;
    }
    const char *suffixes[] = {"_osx.manifest", "_signed-2_osx.manifest", "_signed_osx.manifest"};
    int installed = -1;
    struct timespec newest = {0};
    // Steam leaves older signing-channel manifests behind after an update.
    for (size_t i = 0; i < sizeof(suffixes) / sizeof(suffixes[0]); i++) {
        snprintf(path, sizeof(path), "%s/steam_client%s%s%.*s.installed", dir, beta[0] ? "_" : "", beta,
                 (int)(strlen(suffixes[i]) - strlen(".manifest")), suffixes[i]);
        struct stat st;
        if (stat(path, &st) == 0 && (installed < 0 || st.st_mtimespec.tv_sec > newest.tv_sec ||
            (st.st_mtimespec.tv_sec == newest.tv_sec && st.st_mtimespec.tv_nsec > newest.tv_nsec))) {
            newest = st.st_mtimespec;
            installed = (int)i;
        }
    }
    for (size_t i = 0; i < sizeof(suffixes) / sizeof(suffixes[0]); i++) {
        if (installed >= 0 && (int)i != installed) continue;
        snprintf(path, sizeof(path), "%s/steam_client%s%s%s", dir, beta[0] ? "_" : "", beta, suffixes[i]);
        f = fopen(path, "r");
        if (!f) continue;
        char line[1024], key[64], number[32];
        while (fgets(line, sizeof(line), f)) {
            int end = 0;
            if (sscanf(line, " \"%63[^\"]\" \"%31[0-9]\" %n", key, number, &end) == 2 && end && strcmp(key, "version") == 0) {
                errno = 0;
                uint64_t value = strtoull(number, NULL, 10);
                fclose(f);
                return errno == 0 ? value : 0;
            }
        }
        fclose(f);
        return 0;
    }
    return 0;
}

void sx_steam_appcache_path(char *buf, size_t bufsz, const char *home, const char *rel) {
    snprintf(buf, bufsz, "%s/Library/Application Support/Steam/appcache/%s", home, rel);
}

const char *sx_steamplaymac_getenv(const char *key) {
    char name[64];
    snprintf(name, sizeof(name), "STEAMPLAYMAC_%s", key);
    const char *value = getenv(name);
    if (value) return value;
    // Accept overrides from existing launch scripts during the rename.
    snprintf(name, sizeof(name), "MACSTEAM_%s", key);
    return getenv(name);
}

void sx_steamplaymac_support_path(char *buf, size_t bufsz, const char *home, const char *rel) {
    char current[PATH_MAX], legacy[PATH_MAX];
    snprintf(current, sizeof(current), "%s/Library/Application Support/SteamPlayMac", home);
    snprintf(legacy, sizeof(legacy), "%s/Library/Application Support/macsteam", home);
    const char *root = current;
    // Never replace an existing settings directory or hide old settings after a failed move.
    if (access(current, F_OK) != 0 && access(legacy, F_OK) == 0 &&
        renamex_np(legacy, current, RENAME_EXCL) != 0 && access(current, F_OK) != 0)
        root = legacy;
    if (rel && rel[0])
        snprintf(buf, bufsz, "%s/%s", root, rel);
    else
        snprintf(buf, bufsz, "%s", root);
}
