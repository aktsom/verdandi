/* ext_drop.h (M27): what a drop on the window does on Windows and Linux (the macOS drop is the Finder's link-or-copy and is not touched).
 * a dropped folder is added as an ext folder (lua: _norns.ext_dropped, the same rules and words as the SYSTEM > EXT FOLDERS page); a dropped file is refused with this one message, nothing is imported or copied. */
#ifndef VERDANDI_EXT_DROP_H
#define VERDANDI_EXT_DROP_H

#define EXT_DROP_REFUSED "FILES ARE NOT IMPORTED: DROP A FOLDER"

enum { EXT_DROP_ADD_FOLDER = 0, EXT_DROP_REFUSE = 1 };

/* is_dir: the path is a folder (a link to a folder counts) */
static inline int ext_drop_decide(int is_dir) {
    return is_dir ? EXT_DROP_ADD_FOLDER : EXT_DROP_REFUSE;
}

#endif
