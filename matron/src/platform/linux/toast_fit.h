#pragma once
/*
 * toast_fit: a message (a toast: "saved", "MIDI actions on", the serialosc note) is cut into lines that are no wider than the space it has, at most TOAST_MAX_LINES of them (docs/port/KNOWN-ISSUES.md 33).
 * the width is asked of the renderer through a callback, so the same code serves the cairo pill, the pixel pills of the four pixel looks and the screen window's pill, each with its own font. pure: no
 * drawing, no allocation; linux/tests/toast_fit_test.c. Linux desktop only.
 *   - a "\n" in the text is a line break; words are kept whole; a word wider than a line is cut between characters (UTF-8 characters stay whole)
 *   - more than TOAST_MAX_LINES lines: the last one ends in ".." and is shortened until it fits
 *   - every line is at most max_w wide by the callback's measure (even when max_w is smaller than one character: then a line holds one character)
 */
#ifdef __cplusplus
extern "C" {
#endif

#define TOAST_MAX_LINES 3
#define TOAST_LINE_MAX 192

// the width of a NUL-terminated text in the renderer's unit
typedef double (*toast_measure_fn)(void *ctx, const char *s);

typedef struct {
    int n;                                      // lines used, at least 1
    char line[TOAST_MAX_LINES][TOAST_LINE_MAX]; // the lines
    double width[TOAST_MAX_LINES];              // their widths
    double widest;                              // the widest of them
    int truncated;                              // 1 if text was left out (the last line ends in "..")
} toast_lines_t;

extern void toast_fit(const char *text, toast_measure_fn measure, void *ctx, double max_w, toast_lines_t *out);

#ifdef __cplusplus
}
#endif
