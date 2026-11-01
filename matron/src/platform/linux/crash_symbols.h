#pragma once
/*
 * crash_symbols: the names of our own functions, static ones too, for the crash report (crash_report.cc). a backtrace names only the functions a program exports; the packaged norns binary keeps all its function names in
 * its own file (.symtab), so the table is read from /proc/self/exe once at start (this allocates) and searched in the signal handler (which does not). Linux desktop only.
 */
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// reads the function symbols of an ELF file; the number found (0 for a stripped file, a file that is not ELF, a missing file or NULL). a second call replaces the table
extern int crash_symbols_load(const char *exe);
// the load address of the main program (0 for a program that is not position independent)
extern uintptr_t crash_symbols_bias(void);
// the function that contains the address (an address in the file: the runtime address minus crash_symbols_bias()); *off = the distance from its start. NULL if none. async-signal-safe
extern const char *crash_symbols_find(uintptr_t addr, uintptr_t *off);

#ifdef __cplusplus
}
#endif
