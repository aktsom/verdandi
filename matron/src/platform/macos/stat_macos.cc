/*
 * stat_macos.cc
 *
 * macOS replacement for hardware/stat.cc (/proc/stat, thermal zone). posts the same
 * EVENT_STAT every STAT_INTERVAL seconds:
 *  - cpu: whole machine; cpu1..cpu4: the first four cores (the system menu shows four)
 *  - disk: free space on the volume holding the norns home (dust), MB in legacy df scale
 *  - temp: 0, macOS has no public temperature API
 */

#include <mach/mach.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/statvfs.h>
#include <unistd.h>

#include "events.h"
#include "hardware/stat.h"

#define STAT_INTERVAL 2
#define NUM_CORES 4

static pthread_t p;

static void *stat_check(void *);

void stat_init() {
    if (pthread_create(&p, NULL, stat_check, 0)) {
        fprintf(stderr, "STAT: Error creating thread\n");
    }
}

void stat_deinit() {
    pthread_cancel(p);
}

static int busy_percent(uint64_t busy, uint64_t total, uint64_t *prev_busy, uint64_t *prev_total) {
    uint64_t db = busy - *prev_busy;
    uint64_t dt = total - *prev_total;
    *prev_busy = busy;
    *prev_total = total;
    return dt > 0 ? (int)(100 * db / dt) : 0;
}

void *stat_check(void *x) {
    (void)x;
    pthread_setname_np(pthread_self(), "stat_check");
    int number = -1;
    int disk = 0;
    int cpu[NUM_CORES + 1] = {0};
    uint64_t prev_busy[NUM_CORES + 1] = {0};
    uint64_t prev_total[NUM_CORES + 1] = {0};
    const char *home = getenv("HOME");
    mach_port_t host = mach_host_self();

    while (1) {
        number++;
        if (number == 5) {
            number = 0;
        }

        if (number == 0) {
            struct statvfs vfs;
            if (statvfs(home != NULL ? home : "/", &vfs) == 0) {
                disk = (int)((uint64_t)vfs.f_bavail * vfs.f_frsize / 1024000);
            } else {
                fprintf(stderr, "Error: disk free read\n");
            }
        }

        host_cpu_load_info_data_t load;
        mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;
        if (host_statistics(host, HOST_CPU_LOAD_INFO, (host_info_t)&load, &count) == KERN_SUCCESS) {
            uint64_t busy = (uint64_t)load.cpu_ticks[CPU_STATE_USER] + load.cpu_ticks[CPU_STATE_SYSTEM] +
                            load.cpu_ticks[CPU_STATE_NICE];
            uint64_t total = busy + load.cpu_ticks[CPU_STATE_IDLE];
            cpu[0] = busy_percent(busy, total, &prev_busy[0], &prev_total[0]);
        }

        natural_t ncpu = 0;
        processor_info_array_t info = NULL;
        mach_msg_type_number_t ninfo = 0;
        if (host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &ncpu, &info, &ninfo) == KERN_SUCCESS) {
            processor_cpu_load_info_t cores = (processor_cpu_load_info_t)info;
            for (natural_t i = 0; i < ncpu && i < NUM_CORES; i++) {
                uint64_t busy = (uint64_t)cores[i].cpu_ticks[CPU_STATE_USER] + cores[i].cpu_ticks[CPU_STATE_SYSTEM] +
                                cores[i].cpu_ticks[CPU_STATE_NICE];
                uint64_t total = busy + cores[i].cpu_ticks[CPU_STATE_IDLE];
                cpu[i + 1] = busy_percent(busy, total, &prev_busy[i + 1], &prev_total[i + 1]);
            }
            vm_deallocate(mach_task_self(), (vm_address_t)info, ninfo * sizeof(integer_t));
        }

        union event_data *ev = event_data_new(EVENT_STAT);
        ev->stat.disk = disk;
        ev->stat.temp = 0;
        ev->stat.cpu = cpu[0];
        ev->stat.cpu1 = cpu[1];
        ev->stat.cpu2 = cpu[2];
        ev->stat.cpu3 = cpu[3];
        ev->stat.cpu4 = cpu[4];
        event_post(ev);

        sleep(STAT_INTERVAL);
    }
    return NULL;
}
