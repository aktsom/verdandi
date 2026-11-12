// serialosc handling (matron/src/platform/windows/grid/serialosc_core.h): exact names only, services before processes, the plain note, the administrator command.
//   g++ -std=c++17 -I matron/src linux/tests/serialosc_core_test.cpp -o /tmp/serialosc_core_test && /tmp/serialosc_core_test
#include <stdio.h>
#include "platform/windows/grid/serialosc_core.h"
static int fails = 0;
#define CHECK(c, ...) do { if (!(c)) { fails++; printf("FAIL: " __VA_ARGS__); printf("\n"); } } while (0)
int main() {
    using namespace vso;
    for (const char *i : {"serialoscd.exe", "SerialOSCD.EXE", "serialosc-detector.exe", "serialosc-device.exe", "serialosc.exe"}) CHECK(is_serialosc_image(i), "%s is serialosc", i);
    for (const char *i : {"serialosc-helper.exe", "notserialoscd.exe", "serialoscd", "chrome.exe", "putty.exe", "serial.exe", "monome.exe", "ableton live 12 suite.exe"}) CHECK(!is_serialosc_image(i), "%s is NOT serialosc: no other program is touched", i);
    Svc s1; s1.name = "serialosc"; s1.path = "\"C:\\Program Files\\serialosc\\serialoscd.exe\" -x"; s1.running = true;
    Svc s2; s2.name = "Spooler"; s2.path = "C:\\Windows\\System32\\spoolsv.exe"; s2.running = true;
    Svc s3; s3.name = "MonomeBridge"; s3.display = "Monome"; s3.path = "C:\\tools\\serialoscd.exe"; s3.running = false;
    CHECK(is_serialosc_service(s1) && !is_serialosc_service(s2) && is_serialosc_service(s3), "services by name or program");
    State none;
    CHECK(!present(none) && note(none).empty() && plan(none).empty(), "nothing running: nothing said, nothing to do");
    State st; st.procs = {{100, "serialoscd.exe"}, {101, "serialosc-device.exe"}}; st.services = {s1};
    auto p = plan(st);
    CHECK(p.size() == 3 && p[0].kind == Action::STOP_SERVICE && p[0].service == "serialosc" && p[1].kind == Action::KILL_PROCESS && p[1].pid == 100, "the service first, then the processes");
    State stopped; stopped.services = {s3};
    CHECK(plan(stopped).empty() && present(stopped), "a service that is stopped needs no action");
    std::string n = note(st);
    CHECK(n.find("serialosc is running") == 0 && n.find("Windows service (serialosc)") != std::string::npos && n.find("K3 stops it") != std::string::npos, "the note: %s", n.c_str());
    CHECK(admin_stop_command(s1) == "sc stop serialosc" && admin_manual_command(s1) == "sc config serialosc start= demand", "the exact commands");
    CHECK(prevent_text(st).find("sc config serialosc start= demand") != std::string::npos, "how to keep it from coming back (service)");
    State proc_only; proc_only.procs = {{5, "serialoscd.exe"}};
    CHECK(prevent_text(proc_only).find("Startup apps") != std::string::npos, "how to keep it from coming back (a program)");
    printf(fails == 0 ? "serialosc_core: all checks pass\n" : "serialosc_core: %d failures\n", fails);
    return fails != 0;
}
