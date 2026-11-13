/* key_names.h: the keys named in messages of the window. macOS has the Command key; Windows and Linux have Ctrl (there is no Cmd key there). */
#ifndef VERDANDI_KEY_NAMES_H
#define VERDANDI_KEY_NAMES_H
#ifdef __APPLE__
#define GIF_KEYS_TEXT "shift-cmd-G"
#define GIF_MENU_HINT ""
#else
#define GIF_KEYS_TEXT "Ctrl+Shift+G"
#define GIF_MENU_HINT "Ctrl+Shift+G"
#endif
#define GIF_STOP_TOAST "REC  GIF  \xc2\xb7  " GIF_KEYS_TEXT " stops"
#endif
