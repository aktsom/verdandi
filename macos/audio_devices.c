/*
 * audio_devices: the CoreAudio devices, for SYSTEM > AUDIO (lua/core/menu/audio.lua).
 * one line per device:
 *
 *   <uid> TAB <name> TAB <input channels> TAB <output channels> TAB <rates>
 *
 * uid is what jackd takes as -C / -P; rates are those of 44100 48000 88200 96000 the
 * device supports, comma separated. tabs and newlines in names become spaces.
 *
 * audio_devices --default-input / --default-output: only the uid of the macOS default.
 */

#include <CoreAudio/CoreAudio.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void print_cfstring(CFStringRef s) {
    char buf[512];
    if (s == NULL || !CFStringGetCString(s, buf, sizeof buf, kCFStringEncodingUTF8)) {
        return;
    }
    for (char *c = buf; *c; c++) {
        if (*c == '\t' || *c == '\n' || *c == '\r') {
            *c = ' ';
        }
    }
    fputs(buf, stdout);
}

static CFStringRef string_property(AudioObjectID dev, AudioObjectPropertySelector sel) {
    AudioObjectPropertyAddress a = {sel, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    CFStringRef s = NULL;
    UInt32 size = sizeof s;
    if (AudioObjectGetPropertyData(dev, &a, 0, NULL, &size, &s) != noErr) {
        return NULL;
    }
    return s;
}

static int channels(AudioObjectID dev, AudioObjectPropertyScope scope) {
    AudioObjectPropertyAddress a = {kAudioDevicePropertyStreamConfiguration, scope, kAudioObjectPropertyElementMain};
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(dev, &a, 0, NULL, &size) != noErr || size == 0) {
        return 0;
    }
    AudioBufferList *list = (AudioBufferList *)malloc(size);
    int n = 0;
    if (list != NULL && AudioObjectGetPropertyData(dev, &a, 0, NULL, &size, list) == noErr) {
        for (UInt32 i = 0; i < list->mNumberBuffers; i++) {
            n += (int)list->mBuffers[i].mNumberChannels;
        }
    }
    free(list);
    return n;
}

static void print_rates(AudioObjectID dev) {
    static const double common[] = {44100, 48000, 88200, 96000};
    AudioObjectPropertyAddress a = {kAudioDevicePropertyAvailableNominalSampleRates, kAudioObjectPropertyScopeGlobal,
                                    kAudioObjectPropertyElementMain};
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(dev, &a, 0, NULL, &size) != noErr || size == 0) {
        return;
    }
    AudioValueRange *r = (AudioValueRange *)malloc(size);
    if (r == NULL || AudioObjectGetPropertyData(dev, &a, 0, NULL, &size, r) != noErr) {
        free(r);
        return;
    }
    int first = 1;
    for (int k = 0; k < 4; k++) {
        for (UInt32 i = 0; i < size / sizeof *r; i++) {
            if (common[k] >= r[i].mMinimum && common[k] <= r[i].mMaximum) {
                printf("%s%d", first ? "" : ",", (int)common[k]);
                first = 0;
                break;
            }
        }
    }
    free(r);
}

static int print_default(AudioObjectPropertySelector sel) {
    AudioObjectPropertyAddress a = {sel, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    AudioObjectID dev = kAudioObjectUnknown;
    UInt32 size = sizeof dev;
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &size, &dev) != noErr ||
        dev == kAudioObjectUnknown) {
        return 1;
    }
    CFStringRef uid = string_property(dev, kAudioDevicePropertyDeviceUID);
    if (uid == NULL) {
        return 1;
    }
    print_cfstring(uid);
    putchar('\n');
    CFRelease(uid);
    return 0;
}

int main(int argc, char **argv) {
    if (argc > 1 && strcmp(argv[1], "--default-input") == 0) {
        return print_default(kAudioHardwarePropertyDefaultInputDevice);
    }
    if (argc > 1 && strcmp(argv[1], "--default-output") == 0) {
        return print_default(kAudioHardwarePropertyDefaultOutputDevice);
    }
    AudioObjectPropertyAddress a = {kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal,
                                    kAudioObjectPropertyElementMain};
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &a, 0, NULL, &size) != noErr) {
        return 1;
    }
    AudioObjectID *devs = (AudioObjectID *)malloc(size);
    if (devs == NULL || AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &size, devs) != noErr) {
        return 1;
    }
    for (UInt32 i = 0; i < size / sizeof *devs; i++) {
        int in = channels(devs[i], kAudioObjectPropertyScopeInput);
        int out = channels(devs[i], kAudioObjectPropertyScopeOutput);
        CFStringRef uid = string_property(devs[i], kAudioDevicePropertyDeviceUID);
        CFStringRef name = string_property(devs[i], kAudioObjectPropertyName);
        if (uid != NULL && (in > 0 || out > 0)) {
            print_cfstring(uid);
            putchar('\t');
            print_cfstring(name);
            printf("\t%d\t%d\t", in, out);
            print_rates(devs[i]);
            putchar('\n');
        }
        if (uid != NULL) {
            CFRelease(uid);
        }
        if (name != NULL) {
            CFRelease(name);
        }
    }
    free(devs);
    return 0;
}
