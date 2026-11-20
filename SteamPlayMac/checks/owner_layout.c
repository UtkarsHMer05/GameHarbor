#include "../src/hooks/hook_apps.c"
#include <assert.h>
#include <string.h>

int main(void) {
    unsigned char cuser[0x300] = {0};
    uint32_t expected = 123456;
    sx_hooks_apps_set_build(1794536281ULL);
    memcpy(cuser + 0x242, &expected, sizeof(expected));
    assert(read_cuser_account_id(cuser) == expected);
    sx_hooks_apps_set_build(1794266161ULL);
    assert(read_cuser_account_id(cuser) == expected);
    return 0;
}
