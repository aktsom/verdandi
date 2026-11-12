/* exit_win.h (M2): how norns.exe ends on Windows. */
#ifndef VERDANDI_EXIT_WIN_H
#define VERDANDI_EXIT_WIN_H
#ifdef __cplusplus
extern "C" {
#endif

/* Ends the process at once, from any thread, with `code` (42 = restart, see the launcher): stops the sound card (so that no callback runs into objects being destroyed), flushes the logs and calls
 * TerminateProcess. No atexit handler, no lua_close, no static destructors: with the card's callback thread, the metro and clock threads, the sidecar thread and the window's thread all alive, the
 * normal exit() path crashed with an access violation after "shutting down lua vm" on every restart. A watchdog ends the process after 3 s even if stopping the card hangs. Never returns. */
void verdandi_win_exit(int code);

/* a line "stage: <what> at +12.3 s since norns.exe was started" in norns.log (time of the process, from its creation): where the time of a start or restart goes (docs/port/phase-m5 notes, launcher.log has the other half) */
void verdandi_stage(const char *what);

#ifdef __cplusplus
}
#endif
#endif
