/*
 * plugin_arch_note.h: Linux desktop. the note for the device window while a SuperCollider plug-in listed by linux/plugin_arch_check is still
 * built for another machine (plugin_arch.h), else NULL. looks at the listed files again at each call.
 */

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

extern const char *plugin_arch_note_text(void);

#ifdef __cplusplus
}
#endif
