/* fake_serialosc_device: a process that does nothing and ignores its arguments. started as
 *   exec -a serialosc-devic fake_serialosc_device -c /var/lib/serialosc /dev/ttyACM0
 * its command line is then that of serialosc's per-device process (linux/tests/serialosc_test.sh). */
#include <unistd.h>
int main(void) {
    for (;;) {
        sleep(1);
    }
}
