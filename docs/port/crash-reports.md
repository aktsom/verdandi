# Crash reports on Linux

The Linux desktop build installs handlers for SIGSEGV, SIGABRT, SIGBUS, SIGFPE and SIGILL (`matron/src/platform/linux/crash_report.cc`, installed first thing in `matron_main`). A crash writes, to the log (`<norns home>/norns.log`, which is norns' stderr) and appended to `<norns home>/crash-report.txt`:

- the signal, the **thread's name** (`watch_loop`, ...), thread id, pid and, for a fault, the address;
- the backtrace (`backtrace_symbols_fd`): names of the functions the program exports (the binary is linked with `-export-dynamic`) and `norns(+0xOFFSET)` for the others.

Then the default action runs again, so the process still dies by the same signal and **the core dump is made as before** (`coredumpctl list`, `coredumpctl info`, `coredumpctl gdb`).

## Reading an offset
The package keeps the function names of `/opt/verdandi/build/norns/norns` (only debug info is stripped), so the offsets of static functions resolve:
`nm -n /opt/verdandi/build/norns/norns | awk '$1 <= "000000000006b36f"' | tail -1` (put the offset, 16 digits) or `addr2line -f -e /opt/verdandi/build/norns/norns 0x6b36f`; `coredumpctl gdb` shows the names directly.

## Cost
Keeping the function names instead of `strip --strip-unneeded`: the norns program is 1.77 MB instead of 1.39 MB (+374 KB, about +28 KB in the compressed package). The handler itself is a few hundred lines and uses nothing but signal-safe calls in the handler.

## Not covered
Crashes of other programs (sclang, scsynth, jackd, maiden) are not caught by this: use `coredumpctl list`.
