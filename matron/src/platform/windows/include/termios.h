/* termios.h for Windows (M1): the serial ports (crow) are not supported in this milestone; the types exist so that the shared device headers compile. the functions that use them are
 * Windows stubs (matron/src/platform/windows/devices_stub.cc), which log one plain line. */
#ifndef VERDANDI_WIN_TERMIOS_H
#define VERDANDI_WIN_TERMIOS_H
typedef unsigned int tcflag_t;
typedef unsigned char cc_t;
typedef unsigned int speed_t;
#define NCCS 32
struct termios {
    tcflag_t c_iflag, c_oflag, c_cflag, c_lflag;
    cc_t c_cc[NCCS];
    speed_t c_ispeed, c_ospeed;
};
#define B9600 9600
#define B38400 38400
#define B115200 115200
#endif
