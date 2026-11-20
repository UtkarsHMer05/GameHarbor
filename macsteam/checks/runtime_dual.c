#include <dlfcn.h>
#include <stdio.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    sleep(1);
    if (!dlopen(argv[1], RTLD_LAZY | RTLD_LOCAL)) {
        fprintf(stderr, "dlopen failed: %s\n", dlerror());
        return 1;
    }
    sleep(8);
    return 0;
}
