/* tls_pressure.so: LD_PRELOAD library that makes the process's static TLS big (SIZE bytes, default 24000), as a desktop
 * with GPU drivers and PipeWire's JACK library does. with glibc 2.34+ a thread whose stack is only PTHREAD_STACK_MIN
 * (16 KiB) then cannot be created (EINVAL): matron's metros did exactly that (docs/port/KNOWN-ISSUES.md item 4).
 *   cc -shared -fPIC -o tls_pressure.so linux/tests/tls_pressure.c */
#ifndef SIZE
#define SIZE 24000
#endif
__thread char tls_pressure_block[SIZE] __attribute__((tls_model("initial-exec")));
void tls_pressure_touch(void) {
    tls_pressure_block[0] = 1;
}
