#!/usr/bin/env python3
"""x_cover_window.py [COLOUR]: a plain X window over the whole display, magenta by default, on top of everything until this program is killed. it plays the part of "another
window in front" for linux/tests/second_start_test.sh and the second-start scenario of run_all.sh (no window manager there: a new window is simply on top). needs libX11 only."""
import ctypes, ctypes.util, sys, time

x = ctypes.CDLL(ctypes.util.find_library("X11"))
x.XOpenDisplay.restype = ctypes.c_void_p
x.XDefaultRootWindow.restype = ctypes.c_ulong
x.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
x.XCreateSimpleWindow.restype = ctypes.c_ulong
x.XCreateSimpleWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_int, ctypes.c_uint, ctypes.c_uint, ctypes.c_uint, ctypes.c_ulong, ctypes.c_ulong]
x.XMapWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
x.XStoreName.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_char_p]
x.XFlush.argtypes = [ctypes.c_void_p]
x.XDisplayWidth.argtypes = [ctypes.c_void_p, ctypes.c_int]
x.XDisplayHeight.argtypes = [ctypes.c_void_p, ctypes.c_int]

d = x.XOpenDisplay(None)
if not d:
    sys.exit("no display")
colour = int(sys.argv[1], 16) if len(sys.argv) > 1 else 0xFF00FF
w = x.XCreateSimpleWindow(d, x.XDefaultRootWindow(d), 0, 0, x.XDisplayWidth(d, 0), x.XDisplayHeight(d, 0), 0, 0, colour)
x.XStoreName(d, w, b"cover")
x.XMapWindow(d, w)
x.XFlush(d)
print(w, flush=True)
while True:
    time.sleep(1)
