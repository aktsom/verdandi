/*
 * desktop_platform.h
 *
 * which desktop layer this build has. NORNS_SDL_BRIDGE: the window is made by
 * platform/macos/sdl_bridge.cc on the main thread (macOS, and desktop Linux:
 * NORNS_LINUX_DESKTOP is defined by wscript for `--desktop` builds on Linux).
 */

#pragma once

#if defined(__APPLE__) || defined(NORNS_LINUX_DESKTOP)
#define NORNS_SDL_BRIDGE 1
#endif
