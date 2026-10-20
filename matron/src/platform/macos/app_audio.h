/*
 * app_audio.h
 *
 * another app's sound as norns' input (MIC button SYS, Devices > Audio Input): runs the helper
 * macos/app_input.m (build/macos/app_input, next to NORNS_AUDIO_TOOL), which taps the app
 * (macOS 14.2+) and plays it into crone:input_1/2 alongside the audio interface. the app is
 * muted while it is tapped: its sound comes out of norns. one app at a time; main thread.
 */

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char name[128];
    char bundle[256];
    int playing; // making sound right now
} app_audio_app_t;

// macOS can tap apps (14.2 and later) and the helper is there
extern int app_audio_available(void);

// the running apps (with a dock icon, not norns), the ones playing first, then by name
extern int app_audio_list(app_audio_app_t *out, int max);

// every app but norns' own processes (the Mac's whole sound, YouTube in a browser ...)
#define APP_AUDIO_SYSTEM "system"

// tap this app (bundle id) or APP_AUDIO_SYSTEM instead of the current one; NULL stops.
// false if the helper could not be started
extern int app_audio_select(const char *bundle);

// the bundle id of the tapped app (or APP_AUDIO_SYSTEM), or NULL; a helper that ended on
// its own (it cannot tap on this Mac, jack went away) no longer counts
extern const char *app_audio_current(void);

#ifdef __cplusplus
}
#endif
