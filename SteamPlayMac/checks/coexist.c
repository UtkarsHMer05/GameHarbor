#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 3)
        return 2;

    char buf[8192];
    if (strncmp(argv[1], "fopen", 5) == 0) {
        FILE *f = fopen(argv[2], strcmp(argv[1], "fopen+") == 0 ? "r+" : "r");
        if (!f)
            return 3;
        size_t n;
        while ((n = fread(buf, 1, sizeof(buf), f)) != 0)
            if (write(STDOUT_FILENO, buf, n) != (ssize_t)n)
                return 4;
        int failed = ferror(f);
        fclose(f);
        return failed ? 5 : 0;
    }

    int flags = strcmp(argv[1], "open+") == 0 ? O_RDWR : O_RDONLY;
    int fd = strcmp(argv[1], "openat") == 0 ? openat(AT_FDCWD, argv[2], flags)
                                            : open(argv[2], flags);
    if (fd < 0)
        return 3;
    ssize_t n;
    while ((n = read(fd, buf, sizeof(buf))) > 0)
        if (write(STDOUT_FILENO, buf, (size_t)n) != n)
            return 4;
    close(fd);
    return n < 0 ? 5 : 0;
}
