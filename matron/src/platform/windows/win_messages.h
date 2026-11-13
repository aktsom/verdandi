/* win_messages.h: the plain sentences of the Windows build about what is not there yet (docs/port/windows-gaps.md). pure text, tested by linux/tests/capture_dir_test.c: no Linux words (zenity, portal), no
 * "nothing to import: not audio or a script" (which said the files were wrong when the feature was missing). */
#ifndef VERDANDI_WIN_MESSAGES_H
#define VERDANDI_WIN_MESSAGES_H
#define WIN_IMPORT_NOT_AVAILABLE "importing is not available yet in this Windows build: copy the files into the dust folder"
#define WIN_DIALOG_NOT_AVAILABLE "no file dialog in this Windows build yet: copy the files into the dust folder"
#endif
