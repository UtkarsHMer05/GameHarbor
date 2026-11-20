#define DS3_FRAME_LIMIT_TEST 1
#import "ds3_frame_limit.m"
#include <assert.h>

static BOOL available = YES;
static id fakeDrawable(id layer, SEL selector) { return available ? layer : nil; }

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc == 2) {
            assert(!strcmp(argv[1], "40") || !strcmp(argv[1], "30"));
            targetFPS = atof(argv[1]);
        }
        originalNextDrawable = fakeDrawable;
        NSObject *layer = [NSObject new];
        CFTimeInterval started = CACurrentMediaTime();
        for (unsigned i = 0; i < 21; ++i)
            assert(pacedNextDrawable(layer, @selector(nextDrawable)) == layer);
        CFTimeInterval elapsed = CACurrentMediaTime() - started;
        fprintf(stderr, "21 paced frames: %.6f seconds\n", elapsed);
        assert(elapsed >= 20.0 / targetFPS - 0.001 && elapsed < 20.0 / targetFPS + 0.15);
        NPDS3FramePacer *first = objc_getAssociatedObject(layer, &pacerKey);
        first.nextFrame = CACurrentMediaTime() - 1.0;
        assert(pacedNextDrawable(layer, @selector(nextDrawable)) == layer);
        assert(first.nextFrame > CACurrentMediaTime());
        NSObject *second = [NSObject new];
        assert(pacedNextDrawable(second, @selector(nextDrawable)) == second);
        NPDS3FramePacer *pacer = objc_getAssociatedObject(second, &pacerKey);
        assert(pacer.frames == 1);
        CFTimeInterval deadline = pacer.nextFrame;
        available = NO;
        assert(pacedNextDrawable(second, @selector(nextDrawable)) == nil);
        assert(pacer.nextFrame == deadline && pacer.frames == 1);
        [layer release];
        [second release];
        printf("%.0f FPS pacing, independent layers, and unavailable drawables passed (%.3f s).\n", targetFPS, elapsed);
    }
}
