#include "../src/hooks/hook_stats.c"
#include <assert.h>
#include <string.h>

int main(void) {
    unsigned char job[0x200] = {0};
    uint64_t game = 881100, owner = 123456;
    sx_hooks_stats_set_build(1794536281ULL);
    assert(job_steamid_off == 0x190 && job_gameid_off == 0x198);
    memcpy(job + job_steamid_off, &owner, sizeof(owner));
    memcpy(job + job_gameid_off, &game, sizeof(game));
    assert(worker_appid((uintptr_t)job) == 881100);
    sx_hooks_stats_set_build(1794266161ULL);
    assert(worker_appid((uintptr_t)job) == 881100);
    return 0;
}
