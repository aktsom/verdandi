/* alsa/asoundlib.h for Windows (M1): there is no ALSA. only the opaque types that shared headers name (device_midi.h); the MIDI devices are Windows stubs in this milestone. */
#ifndef VERDANDI_WIN_ASOUNDLIB_H
#define VERDANDI_WIN_ASOUNDLIB_H
typedef struct _snd_rawmidi snd_rawmidi_t;
typedef struct _snd_seq snd_seq_t;
#endif
