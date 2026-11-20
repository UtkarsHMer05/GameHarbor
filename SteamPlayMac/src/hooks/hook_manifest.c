// Manifest request code via opensteamtool API
#include "hooks.h"
#include "../config/config.h"
#include "../util/log.h"
#include <stdint.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CFNetwork/CFNetwork.h>
#include <ctype.h>
#include <errno.h>
#include <stdbool.h>

#define MANIFEST_API_FMT "http://gmrc.wudrm.com/manifest/%llu"
#define MANIFEST_UA      "OpenSteamTool/1.0"

static void *orig_GetManifestRequestCode = NULL;

typedef uint32_t (*fn_GetManifestRequestCode)(void *self, uint32_t app_id,
                                                uint32_t depot_id, uint64_t manifest_id,
                                                const char *branch, uint64_t *pRequestCode);

typedef struct {
    UInt8 bytes[64];
    CFIndex length;
    int done;
    int failed;
} manifest_response_t;

static void manifest_stream_event(CFReadStreamRef stream, CFStreamEventType event, void *info) {
    manifest_response_t *response = (manifest_response_t *)info;
    if (event == kCFStreamEventHasBytesAvailable) {
        CFIndex n = CFReadStreamRead(stream, response->bytes + response->length,
                                     (CFIndex)sizeof(response->bytes) - 1 - response->length);
        if (n > 0) response->length += n;
        else { response->done = 1; response->failed = n < 0; }
        if (response->length == (CFIndex)sizeof(response->bytes) - 1) response->done = 1;
    } else if (event == kCFStreamEventEndEncountered) {
        response->done = 1;
    } else if (event == kCFStreamEventErrorOccurred) {
        response->done = 1; response->failed = 1;
    }
    if (response->done) CFRunLoopStop(CFRunLoopGetCurrent());
}

static int fetch_manifest_code_url(const char *url_buf, double timeout, uint64_t *out_code) {
    CFURLRef url = CFURLCreateWithBytes(NULL, (const UInt8 *)url_buf,
                                        (CFIndex)strlen(url_buf),
                                        kCFStringEncodingUTF8, NULL);
    if (!url) return -1;

    CFHTTPMessageRef req = CFHTTPMessageCreateRequest(NULL, CFSTR("GET"), url, kCFHTTPVersion1_1);
    CFRelease(url);
    if (!req) return -1;

    CFHTTPMessageSetHeaderFieldValue(req, CFSTR("User-Agent"), CFSTR(MANIFEST_UA));
    CFHTTPMessageSetHeaderFieldValue(req, CFSTR("Connection"), CFSTR("close"));

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CFReadStreamRef stream = CFReadStreamCreateForHTTPRequest(NULL, req);
#pragma clang diagnostic pop
    CFRelease(req);
    if (!stream) return -1;

    manifest_response_t response = {0};
    CFStreamClientContext context = {0, &response, NULL, NULL, NULL};
    CFOptionFlags events = kCFStreamEventHasBytesAvailable | kCFStreamEventEndEncountered | kCFStreamEventErrorOccurred;
    if (!CFReadStreamSetClient(stream, events, manifest_stream_event, &context)) { CFRelease(stream); return -1; }
    CFRunLoopRef loop = CFRunLoopGetCurrent();
    CFReadStreamScheduleWithRunLoop(stream, loop, kCFRunLoopDefaultMode);
    int opened = CFReadStreamOpen(stream);
    CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + timeout;
    while (opened && !response.done) {
        double remaining = deadline - CFAbsoluteTimeGetCurrent();
        if (remaining <= 0 || CFRunLoopRunInMode(kCFRunLoopDefaultMode, remaining, true) == kCFRunLoopRunFinished) break;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CFHTTPMessageRef reply = (CFHTTPMessageRef)CFReadStreamCopyProperty(stream, kCFStreamPropertyHTTPResponseHeader);
#pragma clang diagnostic pop
    int status = reply ? (int)CFHTTPMessageGetResponseStatusCode(reply) : 0;
    if (reply) CFRelease(reply);
    CFReadStreamClose(stream);
    CFReadStreamUnscheduleFromRunLoop(stream, loop, kCFRunLoopDefaultMode);
    CFReadStreamSetClient(stream, 0, NULL, NULL);
    CFRelease(stream);
    if (!opened || !response.done || response.failed || status != 200 || response.length <= 0) return -1;
    response.bytes[response.length] = '\0';
    const char *number = (const char *)response.bytes;
    while (*number && isspace((unsigned char)*number)) number++;
    if (!isdigit((unsigned char)*number)) return -1;
    char *end = NULL;
    errno = 0;
    unsigned long long code = strtoull(number, &end, 10);
    while (*end && isspace((unsigned char)*end)) end++;
    if (end == number || *end || errno == ERANGE || code == 0) return -1;

    *out_code = (uint64_t)code;
    return 0;
}

// Fetch manifest request code from the remote API. Returns 0 on success.
static int fetch_manifest_code(uint64_t manifest_id, uint64_t *out_code) {
    char url[128];
    snprintf(url, sizeof(url), MANIFEST_API_FMT, (unsigned long long)manifest_id);
    return fetch_manifest_code_url(url, 3.0, out_code);
}

static uint32_t hook_GetManifestRequestCode(void *self, uint32_t app_id,
                                              uint32_t depot_id, uint64_t manifest_id,
                                              const char *branch, uint64_t *pRequestCode) {
    sx_config_t *g_cfg = sx_config_current;
    fn_GetManifestRequestCode orig =
        (fn_GetManifestRequestCode)orig_GetManifestRequestCode;
    uint32_t result = orig(self, app_id, depot_id, manifest_id, branch, pRequestCode);
    if (result || !pRequestCode) return result;

    if (g_cfg && sx_config_has_app(g_cfg, (int)app_id)) {
        uint64_t code = 0;
        if (fetch_manifest_code(manifest_id, &code) == 0 && pRequestCode) {
            *pRequestCode = code;
            SX_LOG_ONCE_KEY(depot_id,
                    "GetManifestRequestCode: app=%u depot=%u manifest=0x%llx -> opensteamtool code=0x%llx",
                    app_id, depot_id, (unsigned long long)manifest_id,
                    (unsigned long long)code);
            return 1;
        }
        // API failed, fall through to original
        SX_LOG_ONCE_KEY(depot_id,
                "GetManifestRequestCode: app=%u depot=%u manifest=0x%llx -> opensteamtool FAILED, passthrough",
                app_id, depot_id, (unsigned long long)manifest_id);
    }

    return result;
}


static sx_hook_def_t g_hooks[] = {
    {
        .name     = "GetManifestRequestCode",
        .sig_name = "CAppInfo::GetManifestRequestCode",
        .hook_fn  = (void *)hook_GetManifestRequestCode,
        .orig_fn  = &orig_GetManifestRequestCode,
        .optional = 1,
    },
};

int sx_hooks_manifest_count(void) {
    return (int)(sizeof(g_hooks) / sizeof(g_hooks[0]));
}

sx_hook_def_t *sx_hooks_manifest_defs(void) {
    return g_hooks;
}
