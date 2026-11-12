// grid_monitor.h: which grids are plugged in, now and again (Windows build, docs/port/phase-m5.md). one scan = the serial ports with what Windows knows about them (a backend), grid_core.h decides which are grids,
// the difference to what is listed is added and removed through a sink (norns' device list, or a test). a thread scans when Windows says a device changed and every 2 seconds.
//   a grid is the same grid when its SERIAL is the same, on whatever COM port: moved to another USB socket it leaves the list and comes back at once under the new port, with the same name and serial (the vport
//   follows the name and serial in lua/core/grid.lua as on Linux).
//   a port is probed before it is handed to the device list: another program that has it (serialosc, a serial terminal) is said in plain words, and a grid that does not answer is said, and tried again.
//   a port that is not a grid is never opened.
#pragma once

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct vgrid_port_info {
    char name[16];      /* "COM6" */
    int vid, pid;       /* 0 = not known */
    char serial[64];    /* "" = none */
    char friendly[96];  /* "USB Serial Device" */
} vgrid_port_info;

typedef struct vgrid_backend {
    int (*list)(vgrid_port_info *out, int max);
    /* may this port be opened now? 0 yes; 1 another program has it; 2 other trouble (why says it). must not keep it open */
    int (*probe)(const char *port, char *why, size_t whyn);
} vgrid_backend;

typedef struct vgrid_sink {
    void (*add)(const char *path, const char *name);
    void (*remove)(const char *path);
    int (*listed)(const char *path);   /* is a device with this path in the list now (the add worked: libmonome got its answer) */
    /* what the listed device is: name, serial, columns, rows (0 0 = arc). 0 = not listed */
    int (*info)(const char *path, char *name, size_t namen, char *serial, size_t serialn, int *cols, int *rows);
} vgrid_sink;

void vgrid_monitor_init(const vgrid_backend *be, const vgrid_sink *sink, const char *monome_serial, const char *monome_ignore);
/* one scan. returns the number of grids added and removed */
int vgrid_monitor_scan(void);
void vgrid_monitor_poke(void);
int vgrid_monitor_start(void);
void vgrid_monitor_stop(void);
/* "key=value" lines for the DEVICES page: grid=<port>\t<serial>\t<name>\t<cols>\t<rows>, note=<port>: <text>, other=<port>: <text> */
int vgrid_monitor_status(char *buf, size_t n);

#ifdef __cplusplus
}
#endif
