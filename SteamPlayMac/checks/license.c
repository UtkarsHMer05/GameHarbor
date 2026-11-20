#include "../src/feats/license.c"
#include <assert.h>

int main(void) {
    int packages[] = {20200, 333, 333};
    sx_config_t cfg = {0}; cfg.package_ids = packages; cfg.pkg_count = 1;
    sx_config_current = &cfg;
    uint8_t body[0x40] = {0};
    uint8_t license[LIC_OBJ_SIZE_FALLBACK] = {0};
    ((License_t *)license)->packageId = 20200;
    void *rep = calloc(1, REP_ELEMENTS_OFF + sizeof(void *));
    assert(rep);
    *(void **)((uint8_t *)rep + REP_ELEMENTS_OFF) = license;
    *(int32_t *)(body + BODY_RPF_CURSIZE) = 1;
    *(int32_t *)(body + BODY_RPF_TOTSIZE) = 1;
    *(void **)(body + BODY_RPF_REP) = rep;
    inject_licenses_into_body(body);
    assert(*(int32_t *)(body + BODY_RPF_CURSIZE) == 1);
    assert(*(void **)(body + BODY_RPF_REP) == rep);
    cfg.pkg_count = 3;
    inject_licenses_into_body(body);
    assert(*(int32_t *)(body + BODY_RPF_CURSIZE) == 2);
    void *new_rep = *(void **)(body + BODY_RPF_REP);
    License_t **items = (License_t **)((uint8_t *)new_rep + REP_ELEMENTS_OFF);
    assert(items[0] == (License_t *)license && items[1]->packageId == 333);
    free(items[1]); free(new_rep); free(rep);
    return 0;
}
