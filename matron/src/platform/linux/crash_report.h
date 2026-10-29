#pragma once
/*
 * crash_report: a crash of the Linux desktop build leaves a readable report (signal, thread name, backtrace) in the log
 * (stderr is <norns home>/logs/norns.log) and in a file of its own, <norns home>/logs/crash/crash-<time>-<pid>.txt, made at the crash and only then. the default action is kept afterwards, so the core
 * dump (systemd-coredump, coredumpctl) is still made. docs/port/crash-reports.md
 */
#ifdef __cplusplus
extern "C" {
#endif

// handlers for SIGSEGV, SIGABRT, SIGBUS, SIGFPE, SIGILL. dir: the folder for the report files (NULL: only stderr)
extern void crash_report_install(const char *dir);

#ifdef __cplusplus
}
#endif
