#include "../src/util/file.h"
#include <stdio.h>

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    printf("%llu\n", (unsigned long long)sx_steam_build(argv[1]));
    return 0;
}
