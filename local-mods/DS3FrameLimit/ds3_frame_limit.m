#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>
#import <objc/runtime.h>
#include <mach/mach_time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

@interface NPDS3FramePacer : NSObject
@property(nonatomic) CFTimeInterval nextFrame;
@property(nonatomic) CFTimeInterval sampleStart;
@property(nonatomic) unsigned frames;
@end
@implementation NPDS3FramePacer
@end

static char pacerKey;
static double targetFPS = 45.0;
static id (*originalNextDrawable)(id, SEL);

static id pacedNextDrawable(id layer, SEL selector)
{
    @synchronized (layer) {
        NPDS3FramePacer *pacer = objc_getAssociatedObject(layer, &pacerKey);
        if (!pacer) {
            pacer = [NPDS3FramePacer new];
            objc_setAssociatedObject(layer, &pacerKey, pacer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [pacer release];
            if ([layer respondsToSelector:@selector(drawableSize)]) {
                CGSize size = [layer drawableSize];
                fprintf(stderr, "ds3_frame_limit: drawable size %.0fx%.0f\n", size.width, size.height);
            }
        }
        mach_timebase_info_data_t timebase;
        mach_timebase_info(&timebase);
        CFTimeInterval remaining;
        while ((remaining = pacer.nextFrame - CACurrentMediaTime()) > 0)
            mach_wait_until(mach_absolute_time() +
                            (uint64_t)(remaining * 1e9 * timebase.denom / timebase.numer));
        id drawable = originalNextDrawable(layer, selector);
        if (drawable) {
            CFTimeInterval now = CACurrentMediaTime();
            // Keep timer oversleep from accumulating; resync after a whole missed frame.
            if (pacer.nextFrame == 0 || now - pacer.nextFrame >= 1.0 / targetFPS)
                pacer.nextFrame = now + 1.0 / targetFPS;
            else
                pacer.nextFrame += 1.0 / targetFPS;
            if (pacer.frames == 0) pacer.sampleStart = now;
            if (++pacer.frames == 201) {
                fprintf(stderr, "ds3_frame_limit: %.2f drawable frames/s (%.0f FPS cap)\n",
                        200.0 / (now - pacer.sampleStart), targetFPS);
                pacer.frames = 0;
            }
        }
        return drawable;
    }
}

#ifndef DS3_FRAME_LIMIT_TEST
__attribute__((constructor)) static void installFramePacer(void)
{
    const char *enabled = getenv("NOTPROTON_DS3_45FPS");
    const char *sekiro = getenv("NOTPROTON_SEKIRO_40FPS");
    const char *app = getenv("SteamAppId");
    const char *game;
    if (app && !strcmp(app, "814380") && sekiro && !strcmp(sekiro, "1")) {
        const char *requestedFPS = getenv("SEKIRO_FRAME_LIMIT_FPS");
        targetFPS = requestedFPS && !strcmp(requestedFPS, "30") ? 30.0 : 40.0;
        game = "Sekiro";
    } else if (app && !strcmp(app, "374320") && enabled && !strcmp(enabled, "1")) {
        const char *requestedFPS = getenv("DS3_FRAME_LIMIT_FPS");
        if (requestedFPS && !strcmp(requestedFPS, "40")) targetFPS = 40.0;
        game = "Dark Souls III";
    } else return;
    Method method = class_getInstanceMethod([CAMetalLayer class], @selector(nextDrawable));
    if (!method) {
        fprintf(stderr, "ds3_frame_limit: CAMetalLayer.nextDrawable unavailable; cap not installed\n");
        return;
    }
    // CPU pacing avoids Metal's display-divisor rounding on a 60 Hz display.
    originalNextDrawable = (void *)method_setImplementation(method, (IMP)pacedNextDrawable);
    fprintf(stderr, "ds3_frame_limit: enabled %.0f FPS pacing for %s\n", targetFPS, game);
}
#endif
