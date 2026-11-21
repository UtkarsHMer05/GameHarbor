#include <stdio.h>
#include <sys/time.h>
#include <unistd.h>
#include <objc/runtime.h>
#include <objc/message.h>

int   np_log_level = -1;
FILE *np_log_file  = NULL;

int np_hooks_env_lists_label(const char *var, const char *label) {
    (void)var; (void)label;
    return 0;
}

#include "../hooks/hook_activate.c"

static int failures;
static int handoffs;
static id fake_owner;
static int fake_pid;
static id fake_apps;
static id game_app;
static id other_app;
static id msg(id obj, const char *sel);

static id running_apps(id self, SEL cmd) { return fake_apps; }
static id game_bundle_url(id self, SEL cmd) {
    CFURLRef url = CFURLCreateWithFileSystemPath(NULL,
        self == game_app ? CFSTR("/tmp/Game A.app") : CFSTR("/tmp/Game B.app"), kCFURLPOSIXPathStyle, true);
    return msg((id)url, "autorelease");
}
static bool app_alive(id self, SEL cmd) { return false; }
static long app_policy(id self, SEL cmd) { return 1; }
static void *direct_app(void *self, void *cmd, pid_t pid) {
    return pid == 12345 ? other_app : NULL;
}

static void check(int ok, const char *what) {
    if (!ok) {
        printf("FAIL %s\n", what);
        failures++;
    }
}

static void fake_did_become_active(id self, SEL cmd, id note) {
    handoffs++;
}

static id fake_menu_bar_owner(id self, SEL cmd) { return fake_owner; }
static int fake_process_identifier(id self, SEL cmd) { return fake_pid; }

static id msg(id obj, const char *sel) {
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel_registerName(sel));
}

static Class make_class(const char *name, const char *sel, IMP imp, const char *types) {
    Class cls = objc_allocateClassPair(objc_getClass("NSObject"), name, 0);
    class_addMethod(cls, sel_registerName(sel), imp, types);
    objc_registerClassPair(cls);
    return cls;
}

static void become_active(id delegate) {
    ((void (*)(id, SEL, id))objc_msgSend)(delegate, sel_registerName("applicationDidBecomeActive:"), nil);
}

static void menu_bar_owner(id workspace, id owner, int pid) {
    fake_owner = owner;
    fake_pid = pid;
    ((void (*)(id, SEL, id, id, id, void *))objc_msgSend)(
        (id)np_watcher, sel_registerName("observeValueForKeyPath:ofObject:change:context:"),
        (id)CFSTR("menuBarOwningApplication"), workspace, nil, NULL);
}

static void check_resume(id workspace) {
    Class app = make_class("FocusGame", "bundleURL", (IMP)game_bundle_url, "@@:");
    class_addMethod(app, sel_registerName("isTerminated"), (IMP)app_alive, "B@:");
    class_addMethod(app, sel_registerName("activationPolicy"), (IMP)app_policy, "q@:");
    class_addMethod(object_getClass(workspace), sel_registerName("runningApplications"), (IMP)running_apps, "@@:");
    game_app = msg(msg((id)app, "alloc"), "init");
    other_app = msg(msg((id)app, "alloc"), "init");
    id games[] = { other_app, game_app };
    fake_apps = ((id (*)(id, SEL, id *, unsigned long))objc_msgSend)(
        (id)objc_getClass("NSArray"), sel_registerName("arrayWithObjects:count:"), games, 2);
    check(np_game_application(workspace, "/tmp/Game A.app") == game_app, "resume matches the exact game bundle");
    check(np_game_application(workspace, "/tmp/Gone.app") == nil, "resume does not pick an unrelated game");

    orig_running_app = direct_app;
    check(np_hook_running_app(NULL, NULL, 12345) == other_app, "native apps retain their lookup result");

    char scratch[] = "/tmp/gameharbor-focus.XXXXXX";
    if (!mkdtemp(scratch)) {
        check(0, "create temporary focus directory");
        return;
    }
    setenv("HOME", scratch, 1);
    char directory[PATH_MAX], record[PATH_MAX], target[PATH_MAX];
    snprintf(directory, sizeof(directory), "%s/Library", scratch);
    mkdir(directory, 0700);
    strcat(directory, "/Application Support"); mkdir(directory, 0700);
    strcat(directory, "/notproton"); mkdir(directory, 0700);
    strcat(directory, "/focus"); mkdir(directory, 0700);
    np_focus_path(getpid(), record);
    FILE *file = fopen(record, "w");
    check(file != NULL, "create live focus record");
    if (file) {
        fputs("/tmp/Game A.app\n", file);
        fclose(file);
        check(np_focus_target(getpid(), target) && strcmp(target, "/tmp/Game A.app") == 0,
              "a record for the running launcher is accepted");
        const struct timeval old[2] = {{1, 0}, {1, 0}};
        utimes(record, old);
        check(!np_focus_target(getpid(), target), "a record older than the launcher is rejected");
        unlink(record);
    }
    for (int depth = 0; depth < 4; depth++) {
        rmdir(directory);
        *strrchr(directory, '/') = '\0';
    }
    rmdir(scratch);
}

int main(void) {
    Class delegate_cls = make_class("VGUIApplicationDelegate", "applicationDidBecomeActive:",
                                    (IMP)fake_did_become_active, "v@:@");
    Class app_cls = make_class("FakeRunningApplication", "processIdentifier",
                               (IMP)fake_process_identifier, "i@:");
    Class ws_cls = make_class("FakeWorkspace", "menuBarOwningApplication",
                              (IMP)fake_menu_bar_owner, "@@:");

    id delegate = msg(msg((id)delegate_cls, "alloc"), "init");
    id app = msg(msg((id)app_cls, "alloc"), "init");
    id workspace = msg(msg((id)ws_cls, "alloc"), "init");

    np_hooks_activate_install();
    np_activate_install_main(NULL);
    check(orig_did_become_active != NULL && np_watcher != NULL,
          "the hook installs on VGUIApplicationDelegate");

    fake_owner = app;
    fake_pid = getpid();
    np_menu_bar_sync(workspace);
    become_active(delegate);
    check(handoffs == 0, "a menu bar click is skipped when Steam already owned the menu bar at install");

    fake_pid = getpid() + 1;
    np_menu_bar_sync(workspace);
    become_active(delegate);
    check(handoffs == 1, "the first activation hands off when another app owned the menu bar at install");

    become_active(delegate);
    check(handoffs == 1, "an activation while Steam kept the menu bar is skipped");

    menu_bar_owner(workspace, app, getpid());
    become_active(delegate);
    check(handoffs == 1, "Steam owning the menu bar again does not count");

    menu_bar_owner(workspace, app, getpid() + 1);
    become_active(delegate);
    check(handoffs == 2, "an activation after another app took the menu bar hands off");

    become_active(delegate);
    check(handoffs == 2, "the next menu bar click is skipped again");

    menu_bar_owner(workspace, nil, 0);
    become_active(delegate);
    check(handoffs == 3, "an activation after nobody owned the menu bar hands off");
    check_resume(workspace);

    if (failures) {
        printf("==> activatecheck: %d check(s) failed\n", failures);
        return 1;
    }
    printf("==> activatecheck: Steam hands off focus and resolves the exact game on resume\n");
    return 0;
}
