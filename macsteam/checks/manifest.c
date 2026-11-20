#include "../src/hooks/hook_manifest.c"
#include <assert.h>
#include <string.h>

static int calls;
static uint32_t original(void *self, uint32_t app, uint32_t depot, uint64_t manifest,
                         const char *branch, uint64_t *out) {
    (void)self; (void)app; (void)depot; (void)manifest; (void)branch;
    calls++;
    if (out) *out = 9876;
    return out ? 1 : 0;
}

int main(int argc, char **argv) {
    int app = 42; sx_config_t cfg = {0};
    cfg.app_ids = &app; cfg.app_count = 1; sx_config_current = &cfg;
    orig_GetManifestRequestCode = (void *)original;
    uint64_t value = 0;
    assert(hook_GetManifestRequestCode(NULL, 42, 1, 2, "public", &value) == 1);
    assert(value == 9876 && calls == 1);
    assert(hook_GetManifestRequestCode(NULL, 42, 1, 2, "public", NULL) == 0);
    assert(calls == 2);
    if (argc == 3) {
        int rc = fetch_manifest_code_url(argv[1], 0.3, &value);
        if (strcmp(argv[2], "ok") == 0) { assert(rc == 0 && value == 123456); }
        else { assert(rc != 0); }
    }
    return 0;
}
