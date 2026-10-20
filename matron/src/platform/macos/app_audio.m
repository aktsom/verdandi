/*
 * app_audio.m: see app_audio.h. manual retain/release (not ARC), like mac_menu.m.
 */

#import <Cocoa/Cocoa.h>
#include <CoreAudio/CoreAudio.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#include "app_audio.h"
#include "product.h"

extern char **environ;

static pid_t helper = 0;
static char current[256] = "";

static NSString *helper_path(void) {
    const char *tool = getenv("NORNS_AUDIO_TOOL");
    if (tool == NULL || tool[0] == '\0') {
        return nil;
    }
    NSString *dir = [[NSString stringWithUTF8String:tool] stringByDeletingLastPathComponent];
    return [dir stringByAppendingPathComponent:@"app_input"];
}

int app_audio_available(void) {
    if (@available(macOS 14.2, *)) {
        NSString *p = helper_path();
        return p != nil && [[NSFileManager defaultManager] isExecutableFileAtPath:p];
    }
    return 0;
}

// the bundle ids of the processes making sound now (an app's helpers too)
static NSArray<NSString *> *playing_bundles(void) {
    NSMutableArray *out = [NSMutableArray array];
    if (@available(macOS 14.2, *)) {
        AudioObjectPropertyAddress list = {kAudioHardwarePropertyProcessObjectList, kAudioObjectPropertyScopeGlobal,
                                           kAudioObjectPropertyElementMain};
        UInt32 size = 0;
        if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &list, 0, NULL, &size) != noErr || size == 0) {
            return out;
        }
        AudioObjectID *ids = malloc(size);
        if (ids == NULL ||
            AudioObjectGetPropertyData(kAudioObjectSystemObject, &list, 0, NULL, &size, ids) != noErr) {
            free(ids);
            return out;
        }
        for (UInt32 i = 0; i < size / sizeof(AudioObjectID); i++) {
            AudioObjectPropertyAddress running = {kAudioProcessPropertyIsRunningOutput,
                                                  kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
            UInt32 on = 0, n = sizeof on;
            if (AudioObjectGetPropertyData(ids[i], &running, 0, NULL, &n, &on) != noErr || !on) {
                continue;
            }
            AudioObjectPropertyAddress bid = {kAudioProcessPropertyBundleID, kAudioObjectPropertyScopeGlobal,
                                              kAudioObjectPropertyElementMain};
            CFStringRef s = NULL;
            n = sizeof s;
            if (AudioObjectGetPropertyData(ids[i], &bid, 0, NULL, &n, &s) == noErr && s != NULL) {
                [out addObject:(NSString *)s];
                CFRelease(s);
            }
        }
        free(ids);
    }
    return out;
}

// the app or one of its helpers (com.google.Chrome.helper for com.google.Chrome)
static int belongs(NSString *process, NSString *app) {
    return [process isEqualToString:app] || [process hasPrefix:[app stringByAppendingString:@"."]];
}

int app_audio_list(app_audio_app_t *out, int max) {
    NSArray<NSString *> *playing = playing_bundles();
    NSRunningApplication *me = [NSRunningApplication currentApplication];
    NSMutableArray *apps = [NSMutableArray array];
    for (NSRunningApplication *a in [[NSWorkspace sharedWorkspace] runningApplications]) {
        if (a.activationPolicy != NSApplicationActivationPolicyRegular || a.bundleIdentifier == nil ||
            a.localizedName == nil || a.processIdentifier == me.processIdentifier ||
            [a.bundleIdentifier isEqualToString:@"com.apple.finder"]) {
            continue;
        }
        // the app runs this binary through a launcher (and so under either name)
        if ([a.localizedName isEqualToString:@"norns"] || [a.localizedName isEqualToString:@MACOS_PRODUCT]) {
            continue;
        }
        [apps addObject:a];
    }
    int n = 0;
    for (int pass = 0; pass < 2 && n < max; pass++) {
        NSMutableArray *group = [NSMutableArray array];
        for (NSRunningApplication *a in apps) {
            int on = 0;
            for (NSString *p in playing) {
                on = on || belongs(p, a.bundleIdentifier);
            }
            if (on == (pass == 0)) {
                [group addObject:a];
            }
        }
        [group sortUsingComparator:^NSComparisonResult(NSRunningApplication *x, NSRunningApplication *y) {
          return [x.localizedName localizedCaseInsensitiveCompare:y.localizedName];
        }];
        for (NSRunningApplication *a in group) {
            if (n >= max) {
                break;
            }
            snprintf(out[n].name, sizeof out[n].name, "%s", a.localizedName.UTF8String);
            snprintf(out[n].bundle, sizeof out[n].bundle, "%s", a.bundleIdentifier.UTF8String);
            out[n].playing = pass == 0;
            n++;
        }
    }
    return n;
}

static int helper_alive(void) {
    if (helper <= 0) {
        return 0;
    }
    int st = 0;
    pid_t r = waitpid(helper, &st, WNOHANG);
    // reaped elsewhere (SIGCHLD ignored): only kill(0) knows
    if (r == helper || (r < 0 && errno == ECHILD && kill(helper, 0) != 0)) {
        if (r == helper) {
            fprintf(stderr, "app_audio: app input ended (%s %d)\n", WIFEXITED(st) ? "exit" : "signal",
                    WIFEXITED(st) ? WEXITSTATUS(st) : WTERMSIG(st));
        }
        helper = 0;
        current[0] = '\0';
        return 0;
    }
    return 1;
}

static void stop_helper(void) {
    if (!helper_alive()) {
        return;
    }
    kill(helper, SIGTERM);
    // it gives the app its sound back and leaves jack: quick
    for (int i = 0; i < 100; i++) {
        pid_t r = waitpid(helper, NULL, WNOHANG);
        if (r == helper || (r < 0 && kill(helper, 0) != 0)) {
            helper = 0;
            break;
        }
        usleep(10000);
    }
    if (helper > 0) {
        kill(helper, SIGKILL);
        waitpid(helper, NULL, WNOHANG);
        helper = 0;
    }
    current[0] = '\0';
}

static void stop_at_exit(void) {
    stop_helper();
}

int app_audio_select(const char *bundle) {
    static int registered = 0;
    if (!registered) {
        atexit(stop_at_exit);
        registered = 1;
    }
    stop_helper();
    if (bundle == NULL || bundle[0] == '\0') {
        return 1;
    }
    NSString *path = helper_path();
    if (path == nil || !app_audio_available()) {
        return 0;
    }
    const char *exe = path.fileSystemRepresentation;
    // "system": every app but norns
    const char *what = strcmp(bundle, APP_AUDIO_SYSTEM) == 0 ? "--system" : bundle;
    char *argv[] = {(char *)exe, (char *)what, NULL};
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    // not matron's REPL input
    posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_addinherit_np(&fa, 1);
    posix_spawn_file_actions_addinherit_np(&fa, 2);
    // nothing else of norns: with crone's jack sockets the helper would keep the old crone
    // alive in jackd after norns ends (SYSTEM > RESTART), and the new one could not connect
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_CLOEXEC_DEFAULT);
    pid_t pid;
    int err = posix_spawn(&pid, exe, &fa, &attr, argv, environ);
    posix_spawnattr_destroy(&attr);
    posix_spawn_file_actions_destroy(&fa);
    if (err != 0) {
        fprintf(stderr, "app_audio: cannot start %s: %s\n", exe, strerror(err));
        return 0;
    }
    helper = pid;
    snprintf(current, sizeof current, "%s", bundle);
    return 1;
}

const char *app_audio_current(void) {
    return helper_alive() && current[0] != '\0' ? current : NULL;
}
