// Hex encoding helpers
#ifndef STEAMPLAYMAC_UTIL_HEX_H
#define STEAMPLAYMAC_UTIL_HEX_H

#include <stdint.h>

int sx_hex_nibble(int c);
int sx_hex_decode(const char *hex, uint8_t *out, int max_out);

#endif // STEAMPLAYMAC_UTIL_HEX_H
