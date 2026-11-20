// Package record injection
#ifndef STEAMPLAYMAC_FEATS_PACKAGE_H
#define STEAMPLAYMAC_FEATS_PACKAGE_H

#include <stdint.h>
#include "../steam_types.h"

void sx_pkg_set_helpers(uintptr_t pkg_parse);

void sx_pkg_inject(CPackageInfo_t *pkg);

#endif // STEAMPLAYMAC_FEATS_PACKAGE_H
