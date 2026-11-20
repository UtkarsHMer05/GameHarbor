#include "../src/feats/apps.h"
#include "../src/config/config.h"
#include <assert.h>
#include <string.h>

int main(void) {
    int id = 881100;
    sx_config_t cfg = {0};
    cfg.app_ids = &id;
    cfg.app_count = 1;
    sx_config_current = &cfg;
    sx_apps_force_ready();
    AppOwnershipInfo_t before = {0};
    before.owner = 42;
    before.purchaseTime = 100;
    AppOwnershipInfo_t after = before;
    assert(sx_apps_own(id, 1, &after, 1000) == 1);
    assert(memcmp(&before, &after, sizeof(before)) == 0);
    return 0;
}
