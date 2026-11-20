#include "../src/core/macho.h"
#include "../src/resolver/resolver.h"
#include "../src/resolver/sigdb.h"
#include "../src/util/file.h"
#include "../src/util/log.h"
#include "../vendor/cJSON.h"
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int is_function_start(const struct mach_header_64 *mh, intptr_t slide, uintptr_t addr) {
    const uint8_t *cursor = (const uint8_t *)(mh + 1);
    const struct linkedit_data_command *fs = NULL;
    uint64_t vm = 0, fileoff = 0, filesize = 0;
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)cursor;
        if (lc->cmdsize < sizeof(*lc)) return 0;
        if (lc->cmd == LC_FUNCTION_STARTS) fs = (const struct linkedit_data_command *)lc;
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
            if (strncmp(seg->segname, SEG_LINKEDIT, sizeof(seg->segname)) == 0) {
                vm = seg->vmaddr; fileoff = seg->fileoff; filesize = seg->filesize;
            }
        }
        cursor += lc->cmdsize;
    }
    if (!fs || fs->dataoff < fileoff || fs->dataoff - fileoff > filesize ||
        fs->datasize > filesize - (fs->dataoff - fileoff)) return 0;
    const uint8_t *p = (const uint8_t *)(vm + slide + fs->dataoff - fileoff);
    const uint8_t *end = p + fs->datasize;
    uintptr_t current = (uintptr_t)mh;
    while (p < end) {
        uint64_t delta = 0; unsigned shift = 0; uint8_t byte;
        do {
            if (p >= end || shift >= 64) return 0;
            byte = *p++; delta |= (uint64_t)(byte & 0x7f) << shift; shift += 7;
        } while (byte & 0x80);
        if (!delta) break;
        current += (uintptr_t)delta;
        if (current == addr) return 1;
        if (current > addr) break;
    }
    return 0;
}

int main(int argc, char **argv) {
    if (argc != 3) return 2;
    sx_log_level = SX_LVL_ERR;
    if (!dlopen(argv[1], RTLD_LAZY | RTLD_LOCAL)) {
        fprintf(stderr, "dlopen failed: %s\n", dlerror()); return 1;
    }
    const struct mach_header_64 *mh = NULL;
    intptr_t slide = 0; char path[2048];
    if (sx_wait_for_image_ex("steamclient.dylib", 1000, &mh, &slide, path, sizeof(path))) return 1;
    sx_sigdb_t db = {0}; sx_resolve_result_t result = {0};
    if (sx_sigdb_load(argv[2], &db)) return 1;
    if (db.steamclient_sha256_arm64[0]) {
        char hash[65];
        if (sx_hash_arm64_slice(path, hash, sizeof(hash)) || strcmp(hash, db.steamclient_sha256_arm64)) return 1;
    }
    if (sx_resolve_all_ex(mh, slide, path, &db, &result) != db.sig_count) return 1;
    size_t length = 0; uint8_t *raw = sx_slurp_file(argv[2], &length);
    if (!raw) return 1;
    char *json = realloc(raw, length + 1);
    if (!json) { free(raw); return 1; }
    json[length] = 0;
    cJSON *root = cJSON_Parse(json); free(json);
    if (!root) return 1;
    cJSON *entries = cJSON_GetObjectItem(root, "signatures"), *entry;
    int checked = 0;
    cJSON_ArrayForEach(entry, entries) {
        cJSON *name = cJSON_GetObjectItem(entry, "name"), *expected = cJSON_GetObjectItem(entry, "func_addr_this_build");
        if (!cJSON_IsString(name) || !cJSON_IsString(expected)) return 1;
        uintptr_t addr = sx_resolve_find(&result, name->valuestring);
        if (!addr || addr - (uintptr_t)slide != strtoull(expected->valuestring, NULL, 0)) {
            fprintf(stderr, "Wrong location: %s\n", name->valuestring); return 1;
        }
        if (!strstr(name->valuestring, ".transport_ret") && !is_function_start(mh, slide, addr)) {
            fprintf(stderr, "Not a function start: %s\n", name->valuestring); return 1;
        }
        checked++;
    }
    printf("Verified %d profile locations and arm64 client hash\n", checked);
    cJSON_Delete(root); sx_resolve_result_free(&result); sx_sigdb_free(&db);
    return 0;
}
