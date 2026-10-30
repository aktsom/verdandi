/*
 * clip_text.c: see clip_text.h
 */

#include <string.h>

#include "clip_text.h"

clip_status_t clip_classify(const char *text, char *out, size_t outsz) {
    if (out != NULL && outsz > 0) {
        out[0] = '\0';
    }
    if (text == NULL || text[0] == '\0') {
        return CLIP_EMPTY;
    }
    size_t n = 0;
    // look at no more than CLIP_MAX + 1 bytes: a large clipboard is never walked through
    while (n <= CLIP_MAX && text[n] != '\0') {
        unsigned char c = (unsigned char)text[n];
        if ((c < 0x20 && c != '\t' && c != '\n' && c != '\r') || c == 0x7f) {
            return CLIP_BINARY;
        }
        n++;
    }
    if (n > CLIP_MAX) {
        return CLIP_LONG;
    }
    if (out == NULL || outsz < n + 1) {
        return CLIP_LONG;
    }
    memcpy(out, text, n);
    out[n] = '\0';
    return CLIP_OK;
}

const char *clip_status_name(clip_status_t s) {
    switch (s) {
    case CLIP_OK:
        return "ok";
    case CLIP_EMPTY:
        return "empty";
    case CLIP_LONG:
        return "long";
    case CLIP_BINARY:
        return "binary";
    }
    return "empty";
}
