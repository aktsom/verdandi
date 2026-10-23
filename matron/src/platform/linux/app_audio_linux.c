/*
 * app_audio_linux.c: see platform/macos/app_audio.h
 *
 * another app's sound as norns' input is phase 3 on Linux (JACK / PipeWire ports). until then
 * nothing can be tapped; lua is not given _norns.app_input (weaver.cc), so the MIC button only
 * has MIC and OFF.
 */

#include <stddef.h>

#include "../macos/app_audio.h"

int app_audio_available(void) {
    return 0;
}

int app_audio_list(app_audio_app_t *out, int max) {
    (void)out;
    (void)max;
    return 0;
}

int app_audio_select(const char *bundle) {
    return bundle == NULL; // stopping is fine, starting is not
}

const char *app_audio_current(void) {
    return NULL;
}
