// Steam can discard depotcache files; refill only configured depots it asks for.
#include "manifest_watch.h"
#include "../util/file.h"
#include "../util/log.h"

#include <errno.h>
#include <limits.h>
#include <pthread.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#ifndef WATCH_HELPER
#define WATCH_HELPER "/Applications/SteamPlayMac Config.app/Contents/MacOS/SteamPlayMacApp"
#endif
#ifndef WATCH_MARKER
#define WATCH_MARKER "/Applications/SteamPlayMac Config.app/Contents/Resources/manifest-watcher.version"
#endif
#define WATCH_SLOTS 256
#define WATCH_RUNNING 4
#define WATCH_RETRY_SECONDS 60

typedef struct { uint32_t depot; uint64_t gid; time_t attempted; pid_t pid; } watch_attempt_t;

static int number(const char **at, uint64_t *value, const char *after) {
    if (**at < '0' || **at > '9') return 0;
    errno = 0;
    char *end = NULL;
    unsigned long long parsed = strtoull(*at, &end, 10);
    size_t n = strlen(after);
    if (errno == ERANGE || end == *at || strncmp(end, after, n) != 0) return 0;
    *at = end + n;
    *value = (uint64_t)parsed;
    return 1;
}

int sx_manifest_parse_failure(const char *line, uint32_t *app_id, uint32_t *depot, uint64_t *gid) {
    const char *prefix = "CDepotDownloadMgr::BYldRequestDepotManifest(App: ";
    if (!line || !app_id || !depot || !gid) return 0;
    const char *at = strstr(line, prefix);
    if (!at || !strstr(at, "Failed to get manifest request code")) return 0;
    at += strlen(prefix);
    uint64_t app, dep, manifest;
    if (!number(&at, &app, ", Depot: ") || !number(&at, &dep, ", Manifest: ") ||
        !number(&at, &manifest, ", branch: ") || !app || app > INT_MAX || !dep || dep > INT_MAX || !manifest)
        return 0;
    *app_id = (uint32_t)app;
    *depot = (uint32_t)dep;
    *gid = manifest;
    return 1;
}

static int configured(const sx_config_t *cfg, uint32_t app, uint32_t depot) {
    char key[65];
    return sx_config_has_app((sx_config_t *)cfg, (int)app) ||
           sx_config_get_depot_key_any((sx_config_t *)cfg, (int)depot, key, sizeof(key)) == 0;
}

static void reap(watch_attempt_t *attempts, int *running) {
    for (int i = 0; i < WATCH_SLOTS; i++) {
        if (attempts[i].pid <= 0) continue;
        int status = 0;
        pid_t result = waitpid(attempts[i].pid, &status, WNOHANG);
        if (result == attempts[i].pid || (result < 0 && errno == ECHILD)) {
            attempts[i].pid = 0;
            if (*running > 0) (*running)--;
        }
    }
}

static void request(const sx_config_t *cfg, const char *home, const char *cache,
                    const char *line, watch_attempt_t *attempts, int *running) {
    uint32_t app, depot;
    uint64_t gid;
    if (!sx_manifest_parse_failure(line, &app, &depot, &gid) || !configured(cfg, app, depot)) return;
    char path[1400];
    if (snprintf(path, sizeof(path), "%s/%u_%llu.manifest", cache, depot,
                 (unsigned long long)gid) >= (int)sizeof(path) || access(path, F_OK) == 0) return;
    time_t now = time(NULL);
    int slot = -1;
    for (int i = 0; i < WATCH_SLOTS; i++) {
        if (attempts[i].depot == depot && attempts[i].gid == gid) { slot = i; break; }
        if (attempts[i].pid == 0 && (slot < 0 || attempts[i].attempted < attempts[slot].attempted)) slot = i;
    }
    if (slot < 0 || *running >= WATCH_RUNNING || attempts[slot].pid > 0 ||
        (attempts[slot].depot == depot && attempts[slot].gid == gid &&
         now - attempts[slot].attempted < WATCH_RETRY_SECONDS)) return;

    char depot_arg[16], gid_arg[32], home_env[1100];
    snprintf(depot_arg, sizeof(depot_arg), "%u", depot);
    snprintf(gid_arg, sizeof(gid_arg), "%llu", (unsigned long long)gid);
    if (snprintf(home_env, sizeof(home_env), "HOME=%s", home) >= (int)sizeof(home_env)) return;
    char *argv[] = { WATCH_HELPER, "--cache-manifest", depot_arg, gid_arg, NULL };
    char *env[] = { home_env, "PATH=/usr/bin:/bin:/usr/sbin:/sbin", NULL };
    pid_t pid = 0;
    int rc = posix_spawn(&pid, WATCH_HELPER, NULL, NULL, argv, env);
    attempts[slot] = (watch_attempt_t){depot, gid, now, rc == 0 ? pid : 0};
    if (rc == 0) {
        (*running)++;
        SX_LOG("manifest cache: checking depot %u, manifest %llu", depot, (unsigned long long)gid);
    } else {
        SX_WARN("manifest cache: could not start helper (error %d)", rc);
    }
}

static void *watch_log(void *arg) {
    const sx_config_t *cfg = arg;
    const char *home = sx_resolve_home();
    if (!home) return NULL;
    char path[1200], cache[1200];
    if (snprintf(path, sizeof(path), "%s/Library/Application Support/Steam/logs/content_log.txt", home) >= (int)sizeof(path) ||
        snprintf(cache, sizeof(cache), "%s/Library/Application Support/Steam/depotcache", home) >= (int)sizeof(cache)) return NULL;
    watch_attempt_t attempts[WATCH_SLOTS] = {{0}};
    int running = 0, first = 1;
    FILE *log = NULL;
    for (;;) {
        reap(attempts, &running);
        struct stat active, disk;
        if (log && (fstat(fileno(log), &active) != 0 || stat(path, &disk) != 0 ||
                    active.st_ino != disk.st_ino || active.st_dev != disk.st_dev ||
                    ftello(log) > disk.st_size)) {
            fclose(log); log = NULL;
        }
        if (!log) {
            log = fopen(path, "r");
            if (log && first) { fseeko(log, 0, SEEK_END); first = 0; }
        }
        if (log) {
            char line[2048];
            for (;;) {
                off_t start = ftello(log);
                if (!fgets(line, sizeof(line), log)) { clearerr(log); break; }
                if (!strchr(line, '\n') && feof(log)) {
                    clearerr(log); fseeko(log, start, SEEK_SET); break;
                }
                request(cfg, home, cache, line, attempts, &running);
            }
        }
        sleep(1);
    }
}

void sx_manifest_watch_start(const sx_config_t *cfg) {
    if (!cfg || access(WATCH_HELPER, X_OK) != 0 || access(WATCH_MARKER, R_OK) != 0) {
        SX_WARN("manifest cache: local helper is unavailable");
        return;
    }
    pthread_t thread;
    if (pthread_create(&thread, NULL, watch_log, (void *)cfg) == 0) {
        pthread_detach(thread);
        SX_LOG("manifest cache: watching Steam download requests");
    } else {
        SX_WARN("manifest cache: could not start watcher");
    }
}
