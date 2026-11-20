#include <CoreGraphics/CoreGraphics.h>

static bool test_input_access(void) { return true; }
__attribute__((used)) static const struct {
    const void *replacement;
    const void *original;
} input_access __attribute__((section("__DATA,__interpose"))) = {
    (const void *)test_input_access, (const void *)CGPreflightPostEventAccess
};
