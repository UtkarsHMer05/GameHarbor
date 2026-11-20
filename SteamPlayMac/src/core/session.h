// Live login state shared across hooks
#ifndef STEAMPLAYMAC_CORE_SESSION_H
#define STEAMPLAYMAC_CORE_SESSION_H

#include <stdint.h>

uint32_t sx_session_account_id(void);
void     sx_session_set_account_id(uint32_t account_id);

#endif // STEAMPLAYMAC_CORE_SESSION_H
