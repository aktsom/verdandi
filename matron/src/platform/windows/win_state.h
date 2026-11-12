/* win_state.h (Windows build): the size and place of the main window, kept in <home>/main-window.conf and put back at the next start. pure C, no SDL: linux/tests/win_state_test.c.
 * the place is only used when the window would be seen there: a screen that is gone (a second monitor unplugged since) must not put the window where nobody can reach it. */
#ifndef VERDANDI_WIN_STATE_H
#define VERDANDI_WIN_STATE_H
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int has_pos, x, y; /* the place of the window's top left corner */
    int has_size, w, h;
} ws_t;

typedef struct {
    int x, y, w, h;
} ws_rect;

/* the file's text */
int ws_format(const ws_t *s, char *buf, size_t n);
void ws_parse(const char *text, ws_t *s);
/* what to do with a saved state: out gets the size (kept inside min and the biggest screen) and the place (only if at least 80 x 30 pixels of its title bar area (120 x 40 at the top left corner) are on a screen). 0 = nothing saved */
int ws_place(const ws_t *saved, const ws_rect *screens, int nscreens, int min_w, int min_h, ws_t *out);
int ws_load(const char *path, ws_t *s);
/* through a temporary file; the target is removed first (rename does not replace on Windows). 0 = ok */
int ws_save(const char *path, const ws_t *s);

#ifdef __cplusplus
}
#endif
#endif
