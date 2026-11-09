#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#include "args.h"
#include "battery.h"
#include "clock.h"
#include "clocks/clock_crow.h"
#include "clocks/clock_internal.h"
#include "clocks/clock_link.h"
#include "clocks/clock_midi.h"
#include "clocks/clock_scheduler.h"
#include "config.h"
#include "device.h"
#include "device_hid.h"
#include "device_list.h"
#include "device_midi.h"
#include "device_monitor.h"
#include "device_monome.h"
#include "events.h"
#include "hardware/screen/ssd1322.h"
#include "hello.h"
#include "i2c.h"
#include "input.h"
#include "jack_client.h"
#include "matron_main.h"
#ifdef NORNS_LINUX_DESKTOP
#include <string>
#include "platform/linux/crash_report.h"
#endif
#include "metro.h"
#include "osc.h"
#include "platform.h"
#include "screen.h"
#include "screen_events.h"
#include "screen_results.h"
#include "stat.h"

#include "oracle.h"
#include "weaver.h"

void print_version(void);

void matron_cleanup(void) {
    // runs once: it ends with exit(), which runs it again as the atexit handler
    static bool done = false;
    if (done) {
        return;
    }
    done = true;
#ifdef NORNS_LINUX_DESKTOP
    dev_list_monome_all_off(800); // the grids' and arcs' LEDs off before the devices are closed (a quit, a window close, a restart)
#endif
    dev_monitor_deinit();
    osc_deinit();
    o_deinit();
    w_deinit();

    config_deinit();
    i2c_deinit();
    battery_deinit();
    stat_deinit();
    jack_client_deinit();
    ssd1322_deinit();
    screen_results_deinit();
    fprintf(stderr, "matron shutdown complete\n");
    exit(0);
}

#ifdef NORNS_LINUX_DESKTOP
#include <errno.h>
#include <signal.h>

// the LEDs of every grid and arc go off when norns ends (docs/port/KNOWN-ISSUES.md 30): in matron_cleanup (a quit, a window close), after a crash report (best effort) and on SIGTERM / SIGHUP / SIGINT (a launcher
// restart, a logout, a closed terminal, Ctrl+C). a signal handler can only do signal-safe things: it writes the signal number into a pipe, a thread started here takes it from there, switches the LEDs off (bounded
// by a timeout) and ends the process with the signal's default action, as it would have ended without this
static int quit_pipe[2] = {-1, -1};

static void crash_leds_off(void) {
    dev_list_monome_all_off(1000);
}

#ifndef NORNS_WINDOWS
static void on_end_signal(int sig) {
    int e = errno;
    unsigned char b = (unsigned char)sig;
    ssize_t r = write(quit_pipe[1], &b, 1);
    (void)r;
    errno = e;
}

static void *end_signal_thread(void *unused) {
    (void)unused;
    unsigned char b = 0;
    ssize_t r;
    do {
        r = read(quit_pipe[0], &b, 1);
    } while (r < 0 && errno == EINTR);
    if (r == 1) {
        dev_list_monome_all_off(800);
        signal(b, SIG_DFL);
        sigset_t set;
        sigemptyset(&set);
        sigaddset(&set, b);
        pthread_sigmask(SIG_UNBLOCK, &set, NULL);
        kill(getpid(), b);
    }
    return NULL;
}

static void leds_off_on_signals(void) {
    if (pipe(quit_pipe) != 0) {
        return;
    }
    pthread_t th;
    if (pthread_create(&th, NULL, end_signal_thread, NULL) != 0) {
        return;
    }
    pthread_detach(th);
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_end_signal;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGHUP, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);
}
#else
// Windows: no POSIX signals; the console control handler and the window close end the process, and no grids are open in M1
static void leds_off_on_signals(void) {}
#endif
#endif

int matron_main(int argc, char **argv) {
#ifdef NORNS_LINUX_DESKTOP
    {
        // a crash leaves a report in the log and in <norns home>/logs/crash/ (the launcher sets HOME to the norns home)
        const char *home = getenv("HOME");
        #ifdef NORNS_WINDOWS
        bool absolute = home != NULL && ((home[0] >= 'A' && home[0] <= 'z' && home[1] == ':') || home[0] == '/');
#else
        bool absolute = home != NULL && home[0] == '/';
#endif
        std::string dir = absolute ? std::string(home) + "/logs/crash" : "";
        crash_report_install(dir.empty() ? NULL : dir.c_str());
        crash_report_set_hook(crash_leds_off);
        leds_off_on_signals();
    }
#endif
    args_parse(argc, argv);

    print_version();
    init_platform();
    printf("platform: %s (%d)\n", platform_name(), platform());

    events_init(); // <-- must come first!
    if (config_init()) {
        fprintf(stderr, "configuration failed\n");
        return -1;
    }

    metros_init();

    battery_init();
    stat_init();
    osc_init();
    ssd1322_init();
    if (jack_client_init()) {
        screen_clear();
        screen_level(15);
        screen_move(10, 40);
        screen_text("audio system fail.");
        screen_update();
        ssd1322_refresh();
        return -1;
    }
    clock_init();
    clock_internal_init();
    clock_midi_init();
    clock_crow_init();
#if HAVE_ABLETON_LINK
    clock_link_init();
    clock_link_start();
#endif
    clock_scheduler_init();

    fprintf(stderr, "init oracle...\n");
    o_init(); // oracle (audio)

    fprintf(stderr, "init weaver...\n");
    w_init(); // weaver (scripting)

    dev_list_init();
#ifndef NORNS_LINUX_DESKTOP
    dev_list_add(DEV_TYPE_MIDI_VIRTUAL, NULL, "virtual", NULL);
#endif
    // (the Linux desktop's "virtual" device is the JACK MIDI one, made by dev_monitor_scan: input and output, platform/linux/jack_midi_in.cc;
    // upstream's ALSA virtual port is only the fallback when there is no JACK MIDI)

    fprintf(stderr, "init dev_monitor...\n");
    dev_monitor_init();

    // start listening for screen events
    screen_results_init();
    screen_events_init();

    // now is a good time to set our cleanup
    fprintf(stderr, "setting cleanup...\n");
    atexit(matron_cleanup);

    fprintf(stderr, "init input...\n");
    // start reading input to interpreter
    input_init();

    i2c_init();

    fprintf(stderr, "running startup...\n");
    // i/o subsystems are ready; run user startup routine
    w_startup();

    // scan for connected input devices
    fprintf(stderr, "scanning devices...\n");
    dev_monitor_scan();

    // handle all resulting events, then run "post-startup"
    fprintf(stderr, "handling pending events...\n");
    event_handle_pending();

    fprintf(stderr, "running post-startup...\n");
    w_post_startup();

    // blocks until quit
    event_loop();
    return 0;
}

void print_version(void) {
    printf("MATRON\n");
    printf("norns version: %d.%d.%d\n", VERSION_MAJOR, VERSION_MINOR, VERSION_PATCH);
    printf("git hash: %s\n\n", VERSION_HASH);
}

#if 0
int main(int argc, char **argv) {
    matron_main();
}
#endif