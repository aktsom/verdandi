/*
 * mi_foreign_note.h: Linux desktop. while norns runs: a script that downloaded the Raspberry Pi mi-UGens (K3 "download + install") leaves files that
 * stop SuperCollider at the next start. see mi_foreign.h. read only: nothing is moved here (sclang may have the files open; the move is the confirmation in
 * SYSTEM > CLEAN UP, or the launcher's move at the next start).
 */

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// the note for the device window, or NULL: new wrong-architecture mi-UGens items appeared since the first look
extern const char *mi_foreign_note_text(void);
// the same items for the CLEAN UP page: one "path<TAB>reason" per line, or NULL
extern const char *mi_foreign_fix_text(void);

#ifdef __cplusplus
}
#endif
