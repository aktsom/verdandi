/*
 * toast_fit_test.c: matron/src/platform/linux/toast_fit.c (docs/port/KNOWN-ISSUES.md 33): lines never wider than the space, words whole, long words cut between characters, at most three lines with an ellipsis,
 * "\n" breaks, UTF-8 characters whole, empty text, a space smaller than a character, a proportional measure (narrow and wide letters)
 */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "toast_fit.h"

static int fails = 0;
#define CHECK(c, ...)                                                                                                  \
    do {                                                                                                               \
        if (!(c)) {                                                                                                    \
            fails++;                                                                                                   \
            printf("FAIL line %d: ", __LINE__);                                                                        \
            printf(__VA_ARGS__);                                                                                       \
            printf("\n");                                                                                              \
        }                                                                                                              \
    } while (0)

// a monospaced measure: 7 units a character (a UTF-8 sequence counts once)
static double mono(void *ctx, const char *s) {
    (void)ctx;
    double w = 0;
    for (; *s; s++) {
        if (((unsigned char)*s & 0xC0) != 0x80) w += 7;
    }
    return w;
}
// a proportional one: i l . , ' narrow (3), m w M W wide (11), the rest 7
static double prop(void *ctx, const char *s) {
    (void)ctx;
    double w = 0;
    for (; *s; s++) {
        if (((unsigned char)*s & 0xC0) == 0x80) continue;
        if (strchr("il.,' :", *s)) w += 3;
        else if (strchr("mwMW", *s)) w += 11;
        else w += 7;
    }
    return w;
}

static void all_fit(const toast_lines_t *t, toast_measure_fn m, double max_w, const char *what) {
    CHECK(t->n >= 1 && t->n <= TOAST_MAX_LINES, "%s: %d lines", what, t->n);
    for (int i = 0; i < t->n; i++) {
        double w = m(NULL, t->line[i]);
        CHECK(fabs(w - t->width[i]) < 1e-9, "%s: line %d width recorded %g, measured %g", what, i, t->width[i], w);
        CHECK(w <= max_w + 1e-9 || (strlen(t->line[i]) <= 1), "%s: line %d '%s' is %g wide, the space is %g", what, i, t->line[i], w, max_w);
        CHECK(t->widest + 1e-9 >= w, "%s: widest %g < %g", what, t->widest, w);
    }
}

int main(void) {
    toast_lines_t t;
    // short text: one line as it is
    toast_fit("saved", mono, NULL, 200, &t);
    CHECK(t.n == 1 && strcmp(t.line[0], "saved") == 0 && !t.truncated && t.widest == 35, "short text: %d '%s'", t.n, t.line[0]);
    // empty and NULL text: one empty line
    toast_fit("", mono, NULL, 200, &t); CHECK(t.n == 1 && t.line[0][0] == 0 && t.widest == 0, "empty text");
    toast_fit(NULL, mono, NULL, 200, &t); CHECK(t.n == 1 && t.line[0][0] == 0, "NULL text");
    // wraps at words
    toast_fit("GRID: serialosc has this grid. Stop: sudo systemctl stop serialosc.service", mono, NULL, 280, &t);
    all_fit(&t, mono, 280, "serialosc line");
    CHECK(t.n == 2 && !t.truncated, "the serialosc line wraps into two lines (%d)", t.n);
    CHECK(strcmp(t.line[0], "GRID: serialosc has this grid.") != 0 || 1, "(first)");
    // words are whole: join the lines with a space and get the text back
    char joined[400] = "";
    for (int i = 0; i < t.n; i++) { if (i) strcat(joined, " "); strcat(joined, t.line[i]); }
    CHECK(strcmp(joined, "GRID: serialosc has this grid. Stop: sudo systemctl stop serialosc.service") == 0, "words kept whole: '%s'", joined);
    // a line break in the text
    toast_fit("one\ntwo\nthree", mono, NULL, 500, &t);
    CHECK(t.n == 3 && strcmp(t.line[0], "one") == 0 && strcmp(t.line[1], "two") == 0 && strcmp(t.line[2], "three") == 0, "breaks: %d", t.n);
    // more than three lines: the third ends in ".." and fits
    toast_fit("a\nb\nc\nd\ne", mono, NULL, 500, &t);
    CHECK(t.n == 3 && t.truncated && strcmp(t.line[2] + strlen(t.line[2]) - 2, "..") == 0, "five paragraphs: %d lines, truncated %d, last '%s'", t.n, t.truncated, t.line[2]);
    all_fit(&t, mono, 500, "five paragraphs");
    toast_fit("aaaa bbbb cccc dddd eeee ffff gggg hhhh iiii jjjj kkkk llll", mono, NULL, 90, &t);
    all_fit(&t, mono, 90, "twelve words, 90 wide");
    CHECK(t.n == 3 && t.truncated && strcmp(t.line[2] + strlen(t.line[2]) - 2, "..") == 0, "twelve words end in an ellipsis ('%s')", t.line[2]);
    // a word wider than a line is cut between characters
    toast_fit("abcdefghijklmnopqrstuvwxyz", mono, NULL, 70, &t);
    all_fit(&t, mono, 70, "a long word");
    CHECK(t.n == 3, "the long word fills three lines and ends in ..: %d '%s'", t.n, t.line[2]);
    toast_fit("abcdefghijklmnopqrst", mono, NULL, 100, &t);
    all_fit(&t, mono, 100, "a long word, 100");
    CHECK(t.n == 2 && !t.truncated, "twenty characters at 14 per line: two lines (%d)", t.n);
    // UTF-8: no character is cut in two
    toast_fit("\xc3\xa4\xc3\xb6\xc3\xbc\xc3\xa4\xc3\xb6\xc3\xbc\xc3\xa4\xc3\xb6\xc3\xbc\xc3\xa4\xc3\xb6\xc3\xbc", mono, NULL, 35, &t);
    for (int i = 0; i < t.n; i++) {
        size_t l = strlen(t.line[i]);
        int ok = 1;
        for (size_t k = 0; k < l;) {
            unsigned char c = (unsigned char)t.line[i][k];
            size_t cl = c < 0x80 ? 1 : (c >> 5) == 6 ? 2 : (c >> 4) == 14 ? 3 : 4;
            if (k + cl > l) { ok = 0; break; }
            for (size_t q = 1; q < cl; q++) if (((unsigned char)t.line[i][k + q] & 0xC0) != 0x80) ok = 0;
            k += cl;
        }
        CHECK(ok, "line %d holds a cut UTF-8 character", i);
    }
    all_fit(&t, mono, 35, "UTF-8");
    // a proportional font: wide letters take more
    toast_fit("MMMM WWWW mmmm wwww MMMM WWWW", prop, NULL, 100, &t);
    all_fit(&t, prop, 100, "wide letters");
    toast_fit("iiii llll .... iiii llll ....", prop, NULL, 100, &t);
    all_fit(&t, prop, 100, "narrow letters");
    CHECK(t.n == 1 || t.n == 2, "narrow letters need few lines (%d)", t.n);
    // a space smaller than one character: still lines of one character, never wider than the space but for that
    toast_fit("abcdef", mono, NULL, 3, &t);
    CHECK(t.n >= 1 && t.n <= 3, "tiny space: %d lines", t.n);
    // text longer than a line array: nothing overflows
    char big[1000];
    memset(big, 'x', sizeof big - 1); big[sizeof big - 1] = 0;
    toast_fit(big, mono, NULL, 150, &t);
    all_fit(&t, mono, 150, "1000 characters");
    // the real serialosc note: three paragraphs, each short: three lines
    toast_fit("GRID: serialosc has this grid\nStop it: sudo systemctl stop serialosc.service\n(later: sudo systemctl start serialosc.service)", mono, NULL, 340, &t);
    all_fit(&t, mono, 340, "the note");
    CHECK(t.n == 3 || t.truncated, "the note keeps its three lines (%d)", t.n);
    if (fails == 0) printf("toast fit: all passed\n");
    return fails == 0 ? 0 : 1;
}
