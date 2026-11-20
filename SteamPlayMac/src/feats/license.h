// License injection
#ifndef STEAMPLAYMAC_FEATS_LICENSE_H
#define STEAMPLAYMAC_FEATS_LICENSE_H

#include "../steam_types.h"

void sx_license_inject_from_packet(CProtoBufMsg_t *msg);

void sx_license_handle_list(void *body);

#endif // STEAMPLAYMAC_FEATS_LICENSE_H
