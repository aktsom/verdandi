// serialosc_win.cc (Windows build): is serialosc running (as a process or as a service), and stop it. docs/port/phase-m6.md. the decisions are serialosc_core.h (exact names, tested on Linux); this file asks Windows.
//   scan: the process list (Toolhelp) and the services (the service control manager, read only: no administrator rights needed to look)
//   stop: the service first (ControlService STOP; "access denied" = the user is not an administrator: say so and give the exact command, never elevate), then the processes of the exact names (TerminateProcess works for
//         the user's own processes). nothing else is ever touched.
#include <windows.h>
#include <tlhelp32.h>
#include <stdio.h>
#include <string.h>

#include <string>

#include "grid_core.h"
#include "serialosc_core.h"

namespace {

std::string narrow(const wchar_t *w) {
    char b[1024];
    return WideCharToMultiByte(CP_UTF8, 0, w, -1, b, sizeof b, NULL, NULL) > 0 ? b : "";
}

void scan(vso::State *st) {
    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap != INVALID_HANDLE_VALUE) {
        PROCESSENTRY32W pe;
        pe.dwSize = sizeof pe;
        for (BOOL ok = Process32FirstW(snap, &pe); ok; ok = Process32NextW(snap, &pe)) {
            std::string img = narrow(pe.szExeFile);
            if (vso::is_serialosc_image(img)) {
                vso::Proc p;
                p.pid = pe.th32ProcessID;
                p.image = img;
                st->procs.push_back(p);
            }
        }
        CloseHandle(snap);
    }
    SC_HANDLE scm = OpenSCManagerW(NULL, NULL, SC_MANAGER_ENUMERATE_SERVICE | SC_MANAGER_CONNECT);
    if (!scm) return;
    DWORD need = 0, count = 0, resume = 0;
    EnumServicesStatusExW(scm, SC_ENUM_PROCESS_INFO, SERVICE_WIN32, SERVICE_STATE_ALL, NULL, 0, &need, &count, &resume, NULL);
    if (need > 0) {
        BYTE *buf = (BYTE *)malloc(need + 4096);
        if (buf && EnumServicesStatusExW(scm, SC_ENUM_PROCESS_INFO, SERVICE_WIN32, SERVICE_STATE_ALL, buf, need + 4096, &need, &count, &resume, NULL)) {
            ENUM_SERVICE_STATUS_PROCESSW *e = (ENUM_SERVICE_STATUS_PROCESSW *)buf;
            for (DWORD i = 0; i < count; i++) {
                vso::Svc s;
                s.name = narrow(e[i].lpServiceName);
                s.display = narrow(e[i].lpDisplayName);
                s.running = e[i].ServiceStatusProcess.dwCurrentState == SERVICE_RUNNING;
                SC_HANDLE h = OpenServiceW(scm, e[i].lpServiceName, SERVICE_QUERY_CONFIG);
                if (h) {
                    DWORD n = 0;
                    QueryServiceConfigW(h, NULL, 0, &n);
                    if (n > 0) {
                        QUERY_SERVICE_CONFIGW *cfg = (QUERY_SERVICE_CONFIGW *)malloc(n);
                        if (cfg && QueryServiceConfigW(h, cfg, n, &n) && cfg->lpBinaryPathName) s.path = narrow(cfg->lpBinaryPathName);
                        free(cfg);
                    }
                    CloseServiceHandle(h);
                }
                if (vso::is_serialosc_service(s)) st->services.push_back(s);
            }
        }
        free(buf);
    }
    CloseServiceHandle(scm);
}

ULONGLONG STATUS_AT;
bool ADMIN_NEEDED;
std::string ADMIN_CMD, LAST;

} // namespace

// the state as key=value lines for the grid page
int vgrid_win_serialosc_status(char *buf, size_t n) {
    // the page asks twice a second: the service list is looked at again every 3 seconds only
    static vso::State st;
    if (STATUS_AT == 0 || GetTickCount64() - STATUS_AT > 3000) {
        st = vso::State();
        scan(&st);
        STATUS_AT = GetTickCount64();
    }
    std::string s = std::string("running=") + (vso::present(st) ? "1" : "0") + "\n";
    if (vso::present(st)) {
        s += "so_note=" + vso::note(st) + "\n";
        s += "so_prevent=" + vso::prevent_text(st) + "\n";
        for (const auto &p : st.procs) s += "so_proc=" + std::to_string(p.pid) + " " + p.image + "\n";
        for (const auto &v : st.services) s += "so_service=" + v.name + (v.running ? " (running)" : " (stopped)") + "\n";
    }
    if (ADMIN_NEEDED) s += "so_admin=" + ADMIN_CMD + "\n";
    if (!LAST.empty()) s += "so_last=" + LAST + "\n";
    snprintf(buf, n, "%s", s.c_str());
    return (int)s.size();
}

// stops serialosc: returns the number of things that are still running afterwards (0 = done). LAST says what happened
int vgrid_win_serialosc_stop(void) {
    vso::State st;
    scan(&st);
    ADMIN_NEEDED = false;
    std::string said;
    for (const auto &a : vso::plan(st)) {
        if (a.kind == vso::Action::STOP_SERVICE) {
            SC_HANDLE scm = OpenSCManagerW(NULL, NULL, SC_MANAGER_CONNECT);
            std::wstring wn(a.service.begin(), a.service.end());
            SC_HANDLE h = scm ? OpenServiceW(scm, wn.c_str(), SERVICE_STOP | SERVICE_QUERY_STATUS) : NULL;
            SERVICE_STATUS ss;
            if (h && ControlService(h, SERVICE_CONTROL_STOP, &ss)) {
                said += "the service " + a.service + " was stopped. ";
            } else {
                DWORD e = GetLastError();
                if (e == ERROR_ACCESS_DENIED || !h) {
                    ADMIN_NEEDED = true;
                    vso::Svc sv;
                    sv.name = a.service;
                    ADMIN_CMD = vso::admin_stop_command(sv) + "   (in an administrator Command Prompt)";
                    said += "the service " + a.service + " needs administrator rights to stop. ";
                } else {
                    said += "the service " + a.service + " could not be stopped (Windows error " + std::to_string((unsigned long)e) + "). ";
                }
            }
            if (h) CloseServiceHandle(h);
            if (scm) CloseServiceHandle(scm);
        }
    }
    Sleep(300);
    vso::State again;
    scan(&again);
    for (const auto &p : again.procs) {
        HANDLE h = OpenProcess(PROCESS_TERMINATE | SYNCHRONIZE, FALSE, p.pid);
        if (h && TerminateProcess(h, 0)) {
            WaitForSingleObject(h, 2000);
            said += "ended " + p.image + " (" + std::to_string(p.pid) + "). ";
        } else {
            said += p.image + " (" + std::to_string(p.pid) + ") could not be ended (Windows error " + std::to_string((unsigned long)GetLastError()) + "). ";
        }
        if (h) CloseHandle(h);
    }
    Sleep(500);
    vso::State after;
    scan(&after);
    int left = (int)after.procs.size();
    for (const auto &v : after.services) if (v.running) left++;
    STATUS_AT = 0;
    LAST = said.empty() ? "serialosc was not running" : said;
    fprintf(stderr, "grid: stop serialosc: %s%s\n", LAST.c_str(), left ? " (still running)" : "");
    return left;
}

// true when serialosc is running (for the grid monitor: a held port and serialosc)
bool vgrid_win_serialosc_present(void) {
    vso::State st;
    scan(&st);
    return vso::present(st);
}
