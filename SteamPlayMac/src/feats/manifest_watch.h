#ifndef STEAMPLAYMAC_MANIFEST_WATCH_H
#define STEAMPLAYMAC_MANIFEST_WATCH_H

#include "../config/config.h"
#include <stdint.h>

int sx_manifest_parse_failure(const char *line, uint32_t *app, uint32_t *depot, uint64_t *gid);
void sx_manifest_watch_start(const sx_config_t *cfg);

#endif
