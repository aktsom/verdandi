#!/usr/bin/env python3
"""x_close_window.py WINDOW_ID: what a window manager's close button does: sends the window a WM_DELETE_WINDOW client message (SDL turns it into SDL_WINDOWEVENT_CLOSE).
There is no window manager under Xvfb in the tests, so this plays its part. needs libX11 (always there where SDL's x11 driver runs); no other module."""
import ctypes, ctypes.util, sys

x = ctypes.CDLL(ctypes.util.find_library("X11"))
x.XOpenDisplay.restype = ctypes.c_void_p
x.XInternAtom.restype = ctypes.c_ulong
x.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
x.XSendEvent.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_long, ctypes.c_void_p]
x.XFlush.argtypes = [ctypes.c_void_p]
x.XCloseDisplay.argtypes = [ctypes.c_void_p]

class ClientMessage(ctypes.Structure):
    _fields_ = [("type", ctypes.c_int), ("serial", ctypes.c_ulong), ("send_event", ctypes.c_int), ("display", ctypes.c_void_p),
                ("window", ctypes.c_ulong), ("message_type", ctypes.c_ulong), ("format", ctypes.c_int), ("data", ctypes.c_long * 5)]

class XEvent(ctypes.Union):
    _fields_ = [("xclient", ClientMessage), ("pad", ctypes.c_long * 24)]

d = x.XOpenDisplay(None)
if not d:
    sys.exit("no display")
win = int(sys.argv[1], 0)
ev = XEvent()
ev.xclient.type = 33  # ClientMessage
ev.xclient.window = win
ev.xclient.message_type = x.XInternAtom(d, b"WM_PROTOCOLS", 0)
ev.xclient.format = 32
ev.xclient.data[0] = x.XInternAtom(d, b"WM_DELETE_WINDOW", 0)
ev.xclient.data[1] = 0
x.XSendEvent(d, win, 0, 0, ctypes.byref(ev))
x.XFlush(d)
x.XCloseDisplay(d)
