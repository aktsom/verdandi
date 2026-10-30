/*
 * box_style_font.inc: the built-in 3 x 5 pixel font of the box (box_style.c). drawn for this project (nothing is copied from another font); used when norns.ttf is not found and for a label that does not
 * fit the button in the screen's font. one row per byte, the low three bits, the left pixel is bit 2. upper case, digits and the punctuation a message can have; a lower case letter is drawn as its
 * capital, anything else as a question mark. advance 4 (3 pixels and 1 of space).
 */
#define FONT3X5_ROWS 5
#define FONT3X5_ADVANCE 4

static const unsigned char font3x5_table[128][FONT3X5_ROWS] = {
    [' '] = {0, 0, 0, 0, 0},
    ['!'] = {2, 2, 2, 0, 2},
    ['\''] = {2, 2, 0, 0, 0},
    ['#'] = {5, 7, 5, 7, 5},
    ['%'] = {5, 1, 2, 4, 5},
    ['('] = {1, 2, 2, 2, 1},
    [')'] = {4, 2, 2, 2, 4},
    ['*'] = {5, 2, 7, 2, 5},
    ['+'] = {0, 2, 7, 2, 0},
    [','] = {0, 0, 0, 2, 4},
    ['-'] = {0, 0, 7, 0, 0},
    ['.'] = {0, 0, 0, 0, 2},
    ['/'] = {1, 1, 2, 4, 4},
    ['0'] = {7, 5, 5, 5, 7},
    ['1'] = {2, 6, 2, 2, 7},
    ['2'] = {6, 1, 2, 4, 7},
    ['3'] = {6, 1, 2, 1, 6},
    ['4'] = {5, 5, 7, 1, 1},
    ['5'] = {7, 4, 6, 1, 6},
    ['6'] = {3, 4, 7, 5, 7},
    ['7'] = {7, 1, 2, 2, 2},
    ['8'] = {7, 5, 7, 5, 7},
    ['9'] = {7, 5, 7, 1, 6},
    [':'] = {0, 2, 0, 2, 0},
    ['='] = {0, 7, 0, 7, 0},
    ['?'] = {6, 1, 2, 0, 2},
    ['_'] = {0, 0, 0, 0, 7},
    ['A'] = {2, 5, 7, 5, 5},
    ['B'] = {6, 5, 6, 5, 6},
    ['C'] = {3, 4, 4, 4, 3},
    ['D'] = {6, 5, 5, 5, 6},
    ['E'] = {7, 4, 6, 4, 7},
    ['F'] = {7, 4, 6, 4, 4},
    ['G'] = {3, 4, 5, 5, 3},
    ['H'] = {5, 5, 7, 5, 5},
    ['I'] = {7, 2, 2, 2, 7},
    ['J'] = {1, 1, 1, 5, 2},
    ['K'] = {5, 5, 6, 5, 5},
    ['L'] = {4, 4, 4, 4, 7},
    ['M'] = {5, 7, 7, 5, 5},
    ['N'] = {6, 5, 5, 5, 5},
    ['O'] = {2, 5, 5, 5, 2},
    ['P'] = {6, 5, 6, 4, 4},
    ['Q'] = {2, 5, 5, 6, 3},
    ['R'] = {6, 5, 6, 5, 5},
    ['S'] = {3, 4, 2, 1, 6},
    ['T'] = {7, 2, 2, 2, 2},
    ['U'] = {5, 5, 5, 5, 7},
    ['V'] = {5, 5, 5, 5, 2},
    ['W'] = {5, 5, 7, 7, 5},
    ['X'] = {5, 5, 2, 5, 5},
    ['Y'] = {5, 5, 2, 2, 2},
    ['Z'] = {7, 1, 2, 4, 7},
};

static const unsigned char *font3x5_glyph(unsigned char ch) {
    if (ch >= 'a' && ch <= 'z') {
        ch = (unsigned char)(ch - 'a' + 'A');
    }
    if (ch >= 128 || (ch != ' ' && font3x5_table[ch][0] == 0 && font3x5_table[ch][1] == 0 && font3x5_table[ch][2] == 0 && font3x5_table[ch][3] == 0 && font3x5_table[ch][4] == 0)) {
        ch = '?';
    }
    return font3x5_table[ch];
}
