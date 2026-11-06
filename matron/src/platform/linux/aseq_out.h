/*
 * aseq_out.h: the virtual MIDI device as a native ALSA sequencer port. a client "Verdandi" with one readable port "Verdandi out" that other programs subscribe to (Reaper on Linux and other DAWs that only read ALSA MIDI list it
 * as a MIDI input device, aseqdump, aconnect, qjackctl's ALSA tab) without a JACK bridge. it is fed by the same send path as the JACK output (Verdandi:midi_out): everything a script sends to the "virtual" device, all message types
 * including real-time and sysex. the sender never waits: the bytes go into a bounded queue (aseq_pump.h) and a worker thread hands them to the sequencer for direct delivery; what does not fit is dropped, counted and said in the
 * log at most every 10 seconds. nothing is connected automatically. off with NORNS_ALSA_MIDI=0 (audio.conf alsa_midi=0); on by default. there is no input port: what reaches norns from a DAW is Verdandi:midi_in (JACK, or
 * a bridge to it).
 * norns' own client is found by its process id (midi_autoconnect.cc: ownAlsaNames), so a bridge's JACK port for it is never linked to Verdandi:midi_in (no loop); it is no norns MIDI device (the device list is made from
 * the rawmidi nodes udev reports, and the "virtual" device is the JACK one).
 */

#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// make the client and the port and start the worker. 0 = up (also when it already is), -1 = not (switched off, no kernel sequencer, failed): norns then has no ALSA port and says why once in the log
extern int aseq_out_start(void);

// stop the worker and close the client (the port disappears)
extern void aseq_out_stop(void);

// device_midi.cc: bytes a script sent to the virtual device. cut into messages and queued. n when taken (also with nobody subscribed), -1 when there is no client. never waits
extern long aseq_out_send(const uint8_t *data, size_t n);

// the ALSA client id (for tests and messages), -1 if not up
extern int aseq_out_client_id(void);

// the optional auto-connect of "Verdandi out" to ALSA ports named by alsa_midi_out_to= (NORNS_ALSA_MIDI_OUT_TO), see aseq_link.h: how many ports it is subscribed to now, and the names of their clients
// (comma separated, written to `names`). 0 and "" when it is off or nothing matches. never waits
extern int aseq_out_link_status(char *names, size_t n);

#ifdef __cplusplus
}
#endif
