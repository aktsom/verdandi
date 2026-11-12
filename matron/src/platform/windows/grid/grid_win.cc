// grid_win.cc (Windows build): the serial ports of the computer, which of them are monome grids, and the glue to norns' device list. docs/port/phase-m5.md.
//   list:   SetupAPI, the ports of the class "Ports (COM & LPT)" that are present: name (COM6), USB vendor and product id, the USB serial (read from the parent for a composite device), the friendly name. nothing is opened.
//   probe:  a port that is a grid is opened for a moment (exclusive: another program that has it says "access denied" = held) and, for the mext family, asked the system query with a time limit.
//   hot-plug: WM_DEVICECHANGE (the window of midi_winmm.c calls the poke of both monitors) and the scan every 2 seconds.
//   the grid is then opened by libmonome through the device list (dev_monome_init); libmonome asks the serial of the port from a hook that this file sets (monome_platform_serial_hook, windows/patches).
#include <windows.h>
#include <setupapi.h>
#include <cfgmgr32.h>
#include <initguid.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <map>
#include <mutex>
#include <string>
#include <vector>

#include "device/device.h"
#include "device/device_list.h"
#include "grid_core.h"
#include "grid_handshake.h"
#include "grid_monitor.h"
#include "platform/windows/audio/exit_win.h"
#include "platform/windows/midi/midi_win.h"

bool vgrid_win_serialosc_present(void);

DEFINE_GUID(VGRID_GUID_COMPORT, 0x86e0d1e0L, 0x8089, 0x11d0, 0x9c, 0xe4, 0x08, 0x00, 0x3e, 0x30, 0x1f, 0x73);

extern "C" char *(*monome_platform_serial_hook)(const char *path);

namespace {

std::mutex TABLE_LOCK;
std::map<std::string, vgrid::Port> TABLE; // COM name -> what the last list found

std::string wide_to_utf8(const wchar_t *w) {
    char buf[512];
    if (WideCharToMultiByte(CP_UTF8, 0, w, -1, buf, sizeof buf, NULL, NULL) <= 0) return "";
    return buf;
}

std::string instance_id(DEVINST inst) {
    wchar_t id[MAX_DEVICE_ID_LEN];
    if (CM_Get_Device_IDW(inst, id, MAX_DEVICE_ID_LEN, 0) != CR_SUCCESS) return "";
    return wide_to_utf8(id);
}

int win_list(vgrid_port_info *out, int max) {
    HDEVINFO set = SetupDiGetClassDevsW(&VGRID_GUID_COMPORT, NULL, NULL, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
    if (set == INVALID_HANDLE_VALUE) return 0;
    std::map<std::string, vgrid::Port> table;
    int n = 0;
    SP_DEVINFO_DATA dd;
    dd.cbSize = sizeof dd;
    for (DWORD i = 0; SetupDiEnumDeviceInfo(set, i, &dd) && n < max; i++) {
        vgrid::Port p;
        HKEY key = SetupDiOpenDevRegKey(set, &dd, DICS_FLAG_GLOBAL, 0, DIREG_DEV, KEY_READ);
        if (key == INVALID_HANDLE_VALUE) continue;
        wchar_t pn[64] = L"";
        DWORD len = sizeof pn, type = 0;
        LONG ok = RegQueryValueExW(key, L"PortName", NULL, &type, (LPBYTE)pn, &len);
        RegCloseKey(key);
        if (ok != ERROR_SUCCESS) continue;
        p.name = wide_to_utf8(pn);
        wchar_t fr[256] = L"";
        if (SetupDiGetDeviceRegistryPropertyW(set, &dd, SPDRP_FRIENDLYNAME, NULL, (PBYTE)fr, sizeof fr, NULL) || SetupDiGetDeviceRegistryPropertyW(set, &dd, SPDRP_DEVICEDESC, NULL, (PBYTE)fr, sizeof fr, NULL)) {
            p.friendly = wide_to_utf8(fr);
            size_t par = p.friendly.rfind(" (COM"); // "USB Serial Device (COM6)"
            if (par != std::string::npos) p.friendly.resize(par);
        }
        // the device and its parents (a composite device has the vendor id and the serial in the parent)
        DEVINST inst = dd.DevInst;
        for (int depth = 0; depth < 4 && inst; depth++) {
            std::string id = instance_id(inst);
            if (p.vid == 0) vgrid::vid_pid_of(id, &p.vid, &p.pid);
            if (p.serial.empty()) p.serial = vgrid::serial_of_instance(id);
            if (p.vid != 0 && !p.serial.empty()) break;
            DEVINST parent = 0;
            if (CM_Get_Parent(&parent, inst, 0) != CR_SUCCESS) break;
            inst = parent;
        }
        table[p.name] = p;
        snprintf(out[n].name, sizeof out[n].name, "%s", p.name.c_str());
        out[n].vid = p.vid;
        out[n].pid = p.pid;
        snprintf(out[n].serial, sizeof out[n].serial, "%s", p.serial.c_str());
        snprintf(out[n].friendly, sizeof out[n].friendly, "%s", p.friendly.c_str());
        n++;
    }
    SetupDiDestroyDeviceInfoList(set);
    std::lock_guard<std::mutex> g(TABLE_LOCK);
    TABLE.swap(table);
    return n;
}

struct HandleIo {
    HANDLE h;
};
long io_write(void *ctx, const uint8_t *d, size_t n) {
    DWORD w = 0;
    return WriteFile(((HandleIo *)ctx)->h, d, (DWORD)n, &w, NULL) ? (long)w : -1;
}
long io_read(void *ctx, uint8_t *d, size_t n, int ms) {
    HANDLE h = ((HandleIo *)ctx)->h;
    COMMTIMEOUTS t;
    t.ReadIntervalTimeout = MAXDWORD;
    t.ReadTotalTimeoutMultiplier = MAXDWORD;
    t.ReadTotalTimeoutConstant = (DWORD)ms;
    t.WriteTotalTimeoutMultiplier = 0;
    t.WriteTotalTimeoutConstant = 500;
    SetCommTimeouts(h, &t);
    DWORD r = 0;
    return ReadFile(h, d, (DWORD)n, &r, NULL) ? (long)r : -1;
}

std::string conf_value(const char *key);

int win_probe(const char *port, char *why, size_t whyn) {
    std::string path = std::string("\\\\.\\") + port;
    HANDLE h = CreateFileA(path.c_str(), GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, NULL);
    if (h == INVALID_HANDLE_VALUE) {
        DWORD e = GetLastError();
        snprintf(why, whyn, "Windows error %lu", (unsigned long)e);
        bool held = e == ERROR_ACCESS_DENIED || e == ERROR_SHARING_VIOLATION;
        // serialosc has the port and the owner switched on "stop serialosc by itself" (audio.conf serialosc_autostop=1, off by default): it is stopped, at most once a minute, and the port is tried again
        static ULONGLONG last_auto;
        if (held && conf_value("serialosc_autostop") == "1" && GetTickCount64() - last_auto > 60000 && vgrid_win_serialosc_present()) {
            last_auto = GetTickCount64();
            fprintf(stderr, "grid: %s is held and serialosc is running: stopping serialosc (serialosc_autostop=1)\n", port);
            vgrid_win_serialosc_stop();
            Sleep(500);
            h = CreateFileA(path.c_str(), GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, NULL);
        }
        if (h == INVALID_HANDLE_VALUE) return held ? 1 : 2;
    }
    vgrid::Port p;
    {
        std::lock_guard<std::mutex> g(TABLE_LOCK);
        auto it = TABLE.find(port);
        if (it != TABLE.end()) p = it->second;
    }
    int result = 0;
    if (vgrid::speaks_mext(p)) {
        DCB dcb;
        memset(&dcb, 0, sizeof dcb);
        dcb.DCBlength = sizeof dcb;
        if (GetCommState(h, &dcb)) {
            dcb.BaudRate = CBR_115200;
            dcb.ByteSize = 8;
            dcb.StopBits = ONESTOPBIT;
            dcb.Parity = NOPARITY;
            dcb.fBinary = 1;
            SetCommState(h, &dcb);
        }
        PurgeComm(h, PURGE_RXCLEAR | PURGE_TXCLEAR);
        HandleIo io = {h};
        vgrid_io vio = {&io, io_write, io_read};
        int hs = vgrid_handshake(&vio);
        if (hs <= 0) {
            snprintf(why, whyn, "%s", hs < 0 ? "the port failed" : "no answer to the monome query");
            result = 2;
        }
    }
    CloseHandle(h);
    if (result == 0) Sleep(100); // the driver lets go of the port
    return result;
}

std::string conf_value(const char *key);

char *serial_hook(const char *path) {
    std::lock_guard<std::mutex> g(TABLE_LOCK);
    auto it = TABLE.find(path);
    if (it == TABLE.end()) return NULL;
    std::string s = vgrid::libmonome_serial(it->second);
    return s.empty() ? NULL : _strdup(s.c_str());
}

void sink_add(const char *path, const char *name) { dev_list_add(DEV_TYPE_MONOME, path, strdup(name), NULL); }
void sink_remove(const char *path) { dev_list_remove(DEV_TYPE_MONOME, path); }
int sink_listed(const char *path) { return dev_list_path_listed(DEV_TYPE_MONOME, path); }
int sink_info(const char *path, char *name, size_t nn, char *serial, size_t sn, int *cols, int *rows) { return dev_list_monome_info(path, name, nn, serial, sn, cols, rows); }

vgrid_backend BACKEND = {win_list, win_probe};
vgrid_sink SINK = {sink_add, sink_remove, sink_listed, sink_info};

std::string conf_value(const char *key) {
    const char *home = getenv("HOME");
    if (!home || !*home) return "";
    std::string path = std::string(home) + "/audio.conf";
    FILE *f = fopen(path.c_str(), "r");
    if (!f) return "";
    char line[512];
    std::string out;
    size_t kl = strlen(key);
    while (fgets(line, sizeof line, f)) {
        if (strncmp(line, key, kl) == 0 && line[kl] == '=') {
            out = line + kl + 1;
            while (!out.empty() && (out.back() == '\n' || out.back() == '\r')) out.pop_back();
        }
    }
    fclose(f);
    return out;
}

bool STARTED;

} // namespace

void vgrid_win_monitor_init(void) {
    monome_platform_serial_hook = serial_hook;
    std::string serials = conf_value("monome_serial"), ignore = conf_value("monome_ignore");
    vgrid_monitor_init(&BACKEND, &SINK, serials.c_str(), ignore.c_str());
    fprintf(stderr, "grid: serial ports are looked at for monome grids (USB id CAFE:1110, or an FTDI port whose serial is a monome's); a change of devices is noticed at once and every 2 seconds%s%s\n",
            serials.empty() ? "" : "; monome_serial is set", ignore.empty() ? "" : "; monome_ignore is set");
}

void vgrid_win_monitor_start(void) {
    if (STARTED) return;
    STARTED = true;
    vgrid_monitor_start();
}

void vgrid_win_monitor_deinit(void) {
    vgrid_monitor_stop();
}

void vgrid_win_poke(void) { vgrid_monitor_poke(); }

int vgrid_win_status(char *buf, size_t n) { return vgrid_monitor_status(buf, n); }

// the LEDs of every grid off, before the process ends in a way that skips the orderly shutdown (restart, shutdown, window close): bounded, best effort
void vgrid_win_leds_off(void) { dev_list_monome_all_off(800); }
