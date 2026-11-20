// Ticket trickery
#ifndef STEAMPLAYMAC_FEATS_TICKET_H
#define STEAMPLAYMAC_FEATS_TICKET_H

#include <stdint.h>

void sx_ticket_set_helpers(uintptr_t put_bytes, uintptr_t put_tag,
                           uintptr_t get_bytes);

int sx_ticket_serve_extended(void *server_this, void *reqReader, void *respWriter);

#endif // STEAMPLAYMAC_FEATS_TICKET_H
