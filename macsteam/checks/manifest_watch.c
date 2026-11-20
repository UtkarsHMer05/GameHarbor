#include "../src/feats/manifest_watch.c"
#include <assert.h>
#include <sys/stat.h>

int main(void) {
    const char *line = "[time] CDepotDownloadMgr::BYldRequestDepotManifest(App: 10, Depot: 20, Manifest: 18446744073709551615, branch: ): Failed to get manifest request code, 'Access Denied'";
    uint32_t app, depot;
    uint64_t gid;
    assert(sx_manifest_parse_failure(line, &app, &depot, &gid));
    assert(app == 10 && depot == 20 && gid == UINT64_MAX);
    assert(!sx_manifest_parse_failure("CDepotDownloadMgr::BYldRequestDepotManifest(App: 10, Depot: 20, Manifest: 30, branch: ): OK", &app, &depot, &gid));
    assert(!sx_manifest_parse_failure("CDepotDownloadMgr::BYldRequestDepotManifest(App: 10, Depot: -20, Manifest: 30, branch: ): Failed to get manifest request code", &app, &depot, &gid));
    assert(!sx_manifest_parse_failure("CDepotDownloadMgr::BYldRequestDepotManifest(App: 10, Depot: 20, Manifest: 18446744073709551616, branch: ): Failed to get manifest request code", &app, &depot, &gid));

    sx_config_t *cfg = calloc(1, sizeof(*cfg));
    assert(cfg);
    int app_id = 10;
    cfg->app_ids = &app_id;
    cfg->app_count = 1;
    cfg->dk_count = 1;
    cfg->depot_keys[0].depot_count = 1;
    cfg->depot_keys[0].depots[0].depot_id = 21;
    strcpy(cfg->depot_keys[0].depots[0].key, "test");
    assert(configured(cfg, 10, 20));
    assert(configured(cfg, 11, 21));
    assert(!configured(cfg, 11, 20));

    char home[] = "/tmp/macsteam-watch-test-XXXXXX";
    assert(mkdtemp(home));
    watch_attempt_t attempts[WATCH_SLOTS] = {{0}};
    int running = 0;
    request(cfg, home, home, line, attempts, &running);
    assert(running == 1);
    request(cfg, home, home, line, attempts, &running);
    assert(running == 1);
    for (int i = 0; i < 100 && running; i++) { usleep(10000); reap(attempts, &running); }
    assert(running == 0);
    char result[512];
    snprintf(result, sizeof(result), "%s/manifest-watch-called", home);
    FILE *f = fopen(result, "r");
    assert(f);
    char args[128];
    assert(fgets(args, sizeof(args), f));
    fclose(f);
    assert(strcmp(args, "--cache-manifest 20 18446744073709551615\n") == 0);
    request(cfg, home, home, line, attempts, &running);
    assert(running == 0);
    unlink(result);
    rmdir(home);
    free(cfg);
    puts("Manifest watcher checks passed: parsing, configured apps, helper launch and retry limits.");
    return 0;
}
