/*
 * display_name.h: the name of the application where a person sees it (the window title). linux/norns.sh sets NORNS_DISPLAY_NAME
 * from linux/brand.sh; without it (the Mac app, other launchers) the product name is used, so nothing changes there.
 * Internal names (JACK client, MIDI ports, file names) keep MACOS_PRODUCT.
 */
#pragma once

#include <stdlib.h>

static inline const char *display_name(const char *product) {
    const char *n = getenv("NORNS_DISPLAY_NAME");
    return (n != NULL && n[0] != '\0') ? n : product;
}
