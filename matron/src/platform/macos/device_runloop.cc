/*
 * device_runloop.cc
 */

#include <dispatch/dispatch.h>
#include <pthread.h>
#include <stdio.h>

#include "device_runloop.h"

static pthread_once_t once = PTHREAD_ONCE_INIT;
static pthread_t rl_thread;
static CFRunLoopRef rl = NULL;
static dispatch_semaphore_t rl_ready;

static MIDIClientRef client = 0;
static void (*setup_changed)(void) = NULL;

static void keepalive(void *info) {
    (void)info;
}

static void *rl_main(void *p) {
    (void)p;
    pthread_setname_np(pthread_self(), "device_runloop");
    rl = CFRunLoopGetCurrent();
    // a runloop with no sources returns immediately; give it one that never fires
    CFRunLoopSourceContext ctx = {};
    ctx.perform = keepalive;
    CFRunLoopSourceRef src = CFRunLoopSourceCreate(NULL, 0, &ctx);
    CFRunLoopAddSource(rl, src, kCFRunLoopDefaultMode);
    dispatch_semaphore_signal(rl_ready);
    CFRunLoopRun();
    return NULL;
}

static void rl_start(void) {
    rl_ready = dispatch_semaphore_create(0);
    pthread_create(&rl_thread, NULL, rl_main, NULL);
    dispatch_semaphore_wait(rl_ready, DISPATCH_TIME_FOREVER);
}

CFRunLoopRef device_runloop(void) {
    pthread_once(&once, rl_start);
    return rl;
}

void device_runloop_sync(void (^block)(void)) {
    CFRunLoopRef loop = device_runloop();
    if (pthread_equal(pthread_self(), rl_thread)) {
        block();
        return;
    }
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    CFRunLoopPerformBlock(loop, kCFRunLoopDefaultMode, ^{
      block();
      dispatch_semaphore_signal(done);
    });
    CFRunLoopWakeUp(loop);
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    dispatch_release(done);
}

MIDIClientRef coremidi_client(void) {
    device_runloop_sync(^{
      if (client != 0) {
          return;
      }
      OSStatus err = MIDIClientCreateWithBlock(CFSTR("norns"), &client, ^(const MIDINotification *n) {
        if (n->messageID == kMIDIMsgSetupChanged && setup_changed != NULL) {
            setup_changed();
        }
      });
      if (err != noErr) {
          fprintf(stderr, "coremidi: MIDIClientCreate failed (%d)\n", (int)err);
          client = 0;
      }
    });
    return client;
}

void coremidi_set_setup_changed(void (*fn)(void)) {
    setup_changed = fn;
}
