#pragma once
/*
 * crash_report: a crash of the Linux desktop build leaves a readable report (signal, thread name, backtrace) in the log
 * (stderr is <norns home>/norns.log) and in <norns home>/crash-report.txt. the default action is kept afterwards, so the core
 * dump (systemd-coredump, coredumpctl) is still made. docs/port/crash-reports.md
 */
#ifdef __cplusplus
extern "C" {
#endif

// handlers for SIGSEGV, SIGABRT, SIGBUS, SIGFPE, SIGILL. file: where to append the report too (NULL: only stderr)
extern void crash_report_install(const char *file);

#ifdef __cplusplus
}
#endif
