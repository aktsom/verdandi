/*
 * app_input.m
 *
 * one app's sound as norns' input: a Core Audio process tap (macOS 14.2+) on the app's
 * processes (its bundle id and its helpers: com.google.Chrome.helper for com.google.Chrome)
 * as a stereo mixdown, in a private aggregate device clocked by the default output, resampled
 * (jack's adapter) into the jack client "app_input", whose outputs go to crone:input_1/2 next
 * to the audio interface. the app is muted while it is tapped: its sound comes out of norns,
 * like an instrument plugged into the device.
 *
 * usage: app_input <bundle id>
 * started and stopped by the norns window (Devices > Audio Input from App, see
 * matron/src/platform/macos/app_audio.m). ends on SIGTERM, with its parent or with jack;
 * the tap and the aggregate device go with it, and the app is heard again.
 *
 * the app does not have to play yet, or run: the tap follows its processes as they come
 * and go (checked every half second).
 */

#import <CoreAudio/AudioHardwareTapping.h>
#import <CoreAudio/CATapDescription.h>
#import <CoreAudio/CoreAudio.h>
#import <Foundation/Foundation.h>
#include <jack/jack.h>
#include <jack/net.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define CHANNELS 2
#define BLOCK 256 // frames per push into the adapter

static NSString *bundle;
static jack_client_t *client;
static jack_port_t *out_port[CHANNELS];
static _Atomic(jack_adapter_t *) adapter = NULL;
static double adapter_rate = 0;

static AudioObjectID tap = kAudioObjectUnknown;
static AudioObjectID aggregate = kAudioObjectUnknown;
static AudioDeviceIOProcID io_proc = NULL;
static NSArray<NSNumber *> *tapped = nil; // process objects in the tap

// the IO thread's block on its way into the adapter
static float block[CHANNELS][BLOCK];
static int filled = 0;
// blocks pushed so far: when it stops moving (no tap, the device stalls) the adapter would
// play what it still holds over and over
static atomic_uint pushed = 0;
#define STALE_MS 50

//--- jack side

static int process(jack_nframes_t nframes, void *arg) {
    (void)arg;
    float *to[CHANNELS], dummy_buf[CHANNELS][4096], *dummy[CHANNELS];
    for (int c = 0; c < CHANNELS; c++) {
        to[c] = (float *)jack_port_get_buffer(out_port[c], nframes);
        dummy[c] = dummy_buf[c];
    }
    static unsigned seen = 0;
    static jack_nframes_t idle = 0;
    unsigned now = atomic_load(&pushed);
    idle = now != seen ? 0 : idle + nframes;
    seen = now;
    jack_adapter_t *a = atomic_load(&adapter);
    if (a == NULL || nframes > 4096 || idle > jack_get_sample_rate(client) * STALE_MS / 1000) {
        for (int c = 0; c < CHANNELS; c++) {
            memset(to[c], 0, nframes * sizeof(float));
        }
        return 0;
    }
    memset(dummy_buf, 0, sizeof dummy_buf);
    jack_adapter_pull_and_push(a, to, dummy, nframes);
    return 0;
}

static void on_jack_gone(void *arg) {
    (void)arg;
    // the tap and the aggregate go with the process
    _exit(0);
}

static void connect_crone(void) {
    for (int c = 0; c < CHANNELS; c++) {
        char name[32];
        snprintf(name, sizeof name, "crone:input_%d", c + 1);
        jack_connect(client, jack_port_name(out_port[c]), name);
    }
}

//--- Core Audio side

static OSStatus io(AudioObjectID dev, const AudioTimeStamp *now, const AudioBufferList *in,
                   const AudioTimeStamp *in_time, AudioBufferList *out, const AudioTimeStamp *out_time, void *arg) {
    (void)dev, (void)now, (void)in_time, (void)out, (void)out_time, (void)arg;
    jack_adapter_t *a = atomic_load(&adapter);
    if (a == NULL || in == NULL || in->mNumberBuffers == 0) {
        return noErr;
    }
    // the tap's stream comes after the clock device's own inputs: the last one(s)
    const AudioBuffer *last = &in->mBuffers[in->mNumberBuffers - 1];
    const AudioBuffer *left = last, *right = last;
    UInt32 stride = last->mNumberChannels;
    if (stride == 1 && in->mNumberBuffers >= 2) {
        // non-interleaved: one buffer per channel
        left = &in->mBuffers[in->mNumberBuffers - 2];
    }
    if (stride == 0 || left->mData == NULL || right->mData == NULL) {
        return noErr;
    }
    UInt32 frames = last->mDataByteSize / (stride * sizeof(float));
    const float *l = left->mData, *r = right->mData;
    int r_off = stride >= 2 ? 1 : 0;
    float *inp[CHANNELS], dummy_buf[CHANNELS][BLOCK], *dummy[CHANNELS];
    for (int c = 0; c < CHANNELS; c++) {
        inp[c] = block[c];
        dummy[c] = dummy_buf[c];
    }
    for (UInt32 i = 0; i < frames; i++) {
        block[0][filled] = l[i * stride];
        block[1][filled] = r[i * stride + r_off];
        if (++filled == BLOCK) {
            jack_adapter_push_and_pull(a, inp, dummy, BLOCK);
            atomic_fetch_add(&pushed, 1);
            filled = 0;
        }
    }
    return noErr;
}

static NSString *string_prop(AudioObjectID obj, AudioObjectPropertySelector sel) {
    AudioObjectPropertyAddress addr = {sel, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    CFStringRef s = NULL;
    UInt32 n = sizeof s;
    if (AudioObjectGetPropertyData(obj, &addr, 0, NULL, &n, &s) != noErr || s == NULL) {
        return nil;
    }
    return (__bridge_transfer NSString *)s;
}

static AudioObjectID default_output(void) {
    AudioObjectPropertyAddress addr = {kAudioHardwarePropertyDefaultSystemOutputDevice,
                                       kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    AudioObjectID dev = kAudioObjectUnknown;
    UInt32 n = sizeof dev;
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, NULL, &n, &dev);
    return dev;
}

// the app's process objects (it and its helpers), sorted
static NSArray<NSNumber *> *app_processes(void) {
    AudioObjectPropertyAddress addr = {kAudioHardwarePropertyProcessObjectList, kAudioObjectPropertyScopeGlobal,
                                       kAudioObjectPropertyElementMain};
    UInt32 size = 0;
    NSMutableArray *found = [NSMutableArray array];
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &addr, 0, NULL, &size) != noErr || size == 0) {
        return found;
    }
    NSMutableData *buf = [NSMutableData dataWithLength:size];
    AudioObjectID *ids = buf.mutableBytes;
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, NULL, &size, ids) != noErr) {
        return found;
    }
    NSString *helpers = [bundle stringByAppendingString:@"."];
    for (UInt32 i = 0; i < size / sizeof(AudioObjectID); i++) {
        NSString *b = string_prop(ids[i], kAudioProcessPropertyBundleID);
        if (b != nil && ([b isEqualToString:bundle] || [b hasPrefix:helpers])) {
            [found addObject:@(ids[i])];
        }
    }
    [found sortUsingSelector:@selector(compare:)];
    return found;
}

// process taps: macOS 14.2
API_AVAILABLE(macos(14.2)) static void teardown(void) {
    if (io_proc != NULL) {
        AudioDeviceStop(aggregate, io_proc);
        AudioDeviceDestroyIOProcID(aggregate, io_proc);
        io_proc = NULL;
    }
    if (aggregate != kAudioObjectUnknown) {
        AudioHardwareDestroyAggregateDevice(aggregate);
        aggregate = kAudioObjectUnknown;
    }
    if (tap != kAudioObjectUnknown) {
        AudioHardwareDestroyProcessTap(tap);
        tap = kAudioObjectUnknown;
    }
    tapped = nil;
}

static void set_adapter(double rate) {
    if (atomic_load(&adapter) != NULL && rate == adapter_rate) {
        return;
    }
    jack_adapter_t *a = jack_create_adapter(CHANNELS, CHANNELS, BLOCK, (jack_nframes_t)rate,
                                            jack_get_buffer_size(client), jack_get_sample_rate(client));
    if (a == NULL) {
        fprintf(stderr, "app_input: no adapter for %.0f Hz\n", rate);
        return;
    }
    jack_adapter_t *old = atomic_exchange(&adapter, a);
    adapter_rate = rate;
    if (old != NULL) {
        // a running cycle finishes with the old one
        usleep(100000);
        jack_destroy_adapter(old);
    }
}

API_AVAILABLE(macos(14.2)) static BOOL build_tap(NSArray<NSNumber *> *procs) {
    CATapDescription *desc = [[CATapDescription alloc] initStereoMixdownOfProcesses:procs];
    desc.name = @"norns app input";
    desc.privateTap = YES;
    // heard through norns only
    desc.muteBehavior = CATapMutedWhenTapped;
    OSStatus e = AudioHardwareCreateProcessTap(desc, &tap);
    if (e != noErr) {
        fprintf(stderr, "app_input: cannot tap %s (%d)\n", bundle.UTF8String, (int)e);
        tap = kAudioObjectUnknown;
        return NO;
    }
    NSString *clock = string_prop(default_output(), kAudioDevicePropertyDeviceUID);
    NSMutableDictionary *agg = [@{
        @kAudioAggregateDeviceNameKey : @"norns app input",
        @kAudioAggregateDeviceUIDKey : [NSUUID UUID].UUIDString,
        @kAudioAggregateDeviceIsPrivateKey : @YES,
        @kAudioAggregateDeviceIsStackedKey : @NO,
        @kAudioAggregateDeviceTapAutoStartKey : @YES,
        @kAudioAggregateDeviceTapListKey : @[ @{
            @kAudioSubTapDriftCompensationKey : @YES,
            @kAudioSubTapUIDKey : desc.UUID.UUIDString,
        } ],
    } mutableCopy];
    if (clock != nil) {
        agg[@kAudioAggregateDeviceMainSubDeviceKey] = clock;
        agg[@kAudioAggregateDeviceSubDeviceListKey] = @[ @{@kAudioSubDeviceUIDKey : clock} ];
    }
    e = AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)agg, &aggregate);
    if (e != noErr) {
        fprintf(stderr, "app_input: no aggregate device (%d)\n", (int)e);
        aggregate = kAudioObjectUnknown;
        teardown();
        return NO;
    }
    AudioObjectPropertyAddress rate_addr = {kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal,
                                            kAudioObjectPropertyElementMain};
    Float64 rate = 48000;
    UInt32 n = sizeof rate;
    AudioObjectGetPropertyData(aggregate, &rate_addr, 0, NULL, &n, &rate);
    set_adapter(rate);
    filled = 0;
    if (AudioDeviceCreateIOProcID(aggregate, io, NULL, &io_proc) != noErr || AudioDeviceStart(aggregate, io_proc) != noErr) {
        fprintf(stderr, "app_input: the aggregate device does not start\n");
        teardown();
        return NO;
    }
    tapped = procs;
    fprintf(stderr, "app_input: tapping %s (%lu processes, %.0f Hz)\n", bundle.UTF8String,
            (unsigned long)procs.count, rate);
    return YES;
}

// the app's processes changed (it started playing, quit, opened a helper): a new tap
API_AVAILABLE(macos(14.2)) static void follow(void) {
    NSArray<NSNumber *> *procs = app_processes();
    if ([procs isEqualToArray:tapped ?: @[]]) {
        return;
    }
    teardown();
    if (procs.count > 0) {
        build_tap(procs);
    } else {
        fprintf(stderr, "app_input: %s has no audio yet, waiting\n", bundle.UTF8String);
    }
}

API_AVAILABLE(macos(14.2)) static int run(const char *app) {
    @autoreleasepool {
        bundle = @(app);
        pid_t parent = getppid();

        jack_status_t status;
        client = jack_client_open("app_input", JackNoStartServer, &status);
        if (client == NULL) {
            fprintf(stderr, "app_input: no jack server\n");
            return 1;
        }
        for (int c = 0; c < CHANNELS; c++) {
            char name[16];
            snprintf(name, sizeof name, "out_%d", c + 1);
            out_port[c] = jack_port_register(client, name, JACK_DEFAULT_AUDIO_TYPE, JackPortIsOutput, 0);
        }
        jack_set_process_callback(client, process, NULL);
        jack_on_shutdown(client, on_jack_gone, NULL);
        if (jack_activate(client) != 0) {
            fprintf(stderr, "app_input: cannot activate\n");
            return 1;
        }
        connect_crone();

        // SIGTERM: give the app its sound back, leave jack
        signal(SIGTERM, SIG_IGN);
        signal(SIGINT, SIG_IGN);
        dispatch_queue_t q = dispatch_get_main_queue();
        dispatch_source_t term = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, q);
        dispatch_source_t intr = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGINT, 0, q);
        void (^quit)(void) = ^{
          teardown();
          jack_client_close(client);
          exit(0);
        };
        dispatch_source_set_event_handler(term, quit);
        dispatch_source_set_event_handler(intr, quit);
        dispatch_resume(term);
        dispatch_resume(intr);

        follow();
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), NSEC_PER_SEC / 2,
                                  NSEC_PER_SEC / 10);
        dispatch_source_set_event_handler(timer, ^{
          // norns is gone (crashed, killed): no app stays muted for it
          if (getppid() != parent) {
              quit();
          }
          @autoreleasepool {
              follow();
          }
        });
        dispatch_resume(timer);
        dispatch_main();
    }
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: app_input <bundle id>\n");
        return 2;
    }
    if (@available(macOS 14.2, *)) {
        return run(argv[1]);
    }
    fprintf(stderr, "app_input: macOS 14.2 or later taps apps\n");
    return 1;
}
