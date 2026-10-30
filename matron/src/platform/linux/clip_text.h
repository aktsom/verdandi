/*
 * clip_text.h: what the window tells Lua about the clipboard (docs/port/colour-picker-plan.md). Linux desktop only.
 * the clipboard can hold anything: Lua is given at most CLIP_MAX characters of plain text, and otherwise only what was found
 */
#pragma once

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define CLIP_MAX 64 // characters of the clipboard that are read (a colour is 7)

typedef enum {
    CLIP_OK = 0,  // out holds the text (at most CLIP_MAX bytes)
    CLIP_EMPTY,   // nothing on the clipboard
    CLIP_LONG,    // more than CLIP_MAX bytes: the text is not given
    CLIP_BINARY,  // control characters: not plain text
} clip_status_t;

// text: what SDL gave (NULL = no text), out: at least CLIP_MAX + 1 bytes. never reads more than CLIP_MAX + 1 bytes of text
extern clip_status_t clip_classify(const char *text, char *out, size_t outsz);

// the status as the word Lua is given
extern const char *clip_status_name(clip_status_t s);

#ifdef __cplusplus
}
#endif
