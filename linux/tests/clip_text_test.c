/*
 * clip_text_test.c: what the window tells Lua about the clipboard (matron/src/platform/linux/clip_text.c), and with SDL (-DHAVE_SDL, a display) the real clipboard round trip:
 * set a text, read it back, classify it. valid, empty, too long, binary, a big text that is never walked through.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "clip_text.h"
#ifdef HAVE_SDL
#include <SDL.h>
#endif

static int fails = 0;
static void check(int ok, const char *what) {
    if (!ok) {
        fails++;
        printf("FAIL %s\n", what);
    }
}

int main(void) {
    char out[CLIP_MAX + 1];
    check(clip_classify("#3B6EA8", out, sizeof out) == CLIP_OK && strcmp(out, "#3B6EA8") == 0, "a colour is ok and given");
    check(clip_classify("3b6", out, sizeof out) == CLIP_OK && strcmp(out, "3b6") == 0, "3 digits are ok");
    check(clip_classify("  #3B6EA8\n", out, sizeof out) == CLIP_OK && strcmp(out, "  #3B6EA8\n") == 0, "blanks and a newline are plain text: Lua trims them");
    check(clip_classify("\t#3B6EA8\r\n", out, sizeof out) == CLIP_OK, "tab and CR LF are plain text");
    check(clip_classify("h\xc3\xa9llo", out, sizeof out) == CLIP_OK, "UTF-8 is text");
    check(clip_classify(NULL, out, sizeof out) == CLIP_EMPTY && out[0] == '\0', "NULL is empty");
    check(clip_classify("", out, sizeof out) == CLIP_EMPTY, "an empty string is empty");
    char sixty4[CLIP_MAX + 1];
    memset(sixty4, 'a', CLIP_MAX);
    sixty4[CLIP_MAX] = '\0';
    check(clip_classify(sixty4, out, sizeof out) == CLIP_OK && strlen(out) == CLIP_MAX, "exactly 64 characters are given");
    char sixty5[CLIP_MAX + 2];
    memset(sixty5, 'a', CLIP_MAX + 1);
    sixty5[CLIP_MAX + 1] = '\0';
    check(clip_classify(sixty5, out, sizeof out) == CLIP_LONG && out[0] == '\0', "65 characters are too long and nothing is given");
    check(clip_classify("a\x01" "b", out, sizeof out) == CLIP_BINARY, "a control character is binary");
    check(clip_classify("\x7f", out, sizeof out) == CLIP_BINARY, "DEL is binary");
    check(clip_classify("\x1b[31mred", out, sizeof out) == CLIP_BINARY, "an escape sequence is binary");
    // a large text: only the first 65 bytes are looked at (valgrind-style check: the string is huge and ends far away)
    size_t big = 50u * 1024 * 1024;
    char *huge = (char *)malloc(big + 1);
    memset(huge, 'x', big);
    huge[big] = '\0';
    check(clip_classify(huge, out, sizeof out) == CLIP_LONG, "50 MB of text is too long");
    huge[100] = '\x02';
    check(clip_classify(huge, out, sizeof out) == CLIP_LONG, "a control character beyond byte 65 is not looked for (too long first)");
    free(huge);
    check(strcmp(clip_status_name(CLIP_OK), "ok") == 0 && strcmp(clip_status_name(CLIP_EMPTY), "empty") == 0 && strcmp(clip_status_name(CLIP_LONG), "long") == 0 &&
              strcmp(clip_status_name(CLIP_BINARY), "binary") == 0, "the words Lua is given");
    check(clip_classify("#3B6EA8", out, 4) == CLIP_LONG, "a too small buffer never overflows");
#ifdef HAVE_SDL
    if (getenv("DISPLAY") != NULL && SDL_Init(SDL_INIT_VIDEO) == 0) {
        SDL_Window *w = SDL_CreateWindow("clip", 0, 0, 64, 64, 0);
        check(SDL_SetClipboardText("#3B6EA8") == 0, "SDL sets the clipboard");
        char *t = SDL_HasClipboardText() ? SDL_GetClipboardText() : NULL;
        check(t != NULL && clip_classify(t, out, sizeof out) == CLIP_OK && strcmp(out, "#3B6EA8") == 0, "the real clipboard gives the text back");
        SDL_free(t);
        SDL_SetClipboardText("");
        t = SDL_HasClipboardText() ? SDL_GetClipboardText() : NULL;
        check(clip_classify(t, out, sizeof out) == CLIP_EMPTY, "an emptied clipboard is empty");
        if (t != NULL) SDL_free(t);
        SDL_SetClipboardText("a\x01" "b");
        t = SDL_HasClipboardText() ? SDL_GetClipboardText() : NULL;
        check(t == NULL || clip_classify(t, out, sizeof out) == CLIP_BINARY || clip_classify(t, out, sizeof out) == CLIP_EMPTY, "binary on the real clipboard is not given");
        if (t != NULL) SDL_free(t);
        SDL_DestroyWindow(w);
        SDL_Quit();
        printf("(the real SDL clipboard was used)\n");
    } else {
        printf("(no display: the real SDL clipboard was not tried)\n");
    }
#endif
    if (fails == 0) {
        printf("clip_text_test: all passed\n");
    }
    return fails != 0;
}
