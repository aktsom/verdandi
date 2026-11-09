/*
 * jack/jack.h of the JACK-compatible NULL backend (Windows, M1): the subset of the JACK API that crone and matron use, implemented in-process by jack_null.c.
 * behaviour: one process-wide graph, a timer thread calls the process callbacks of the activated clients once per block (default 128 frames at 48000 Hz, set with
 * VERDANDI_JACK_NULL_RATE and VERDANDI_JACK_NULL_FRAMES), connected output ports are summed into input ports, there are two physical capture and two physical playback
 * ports (client "system") that carry silence in and drop what is written. there is no audio device. the real audio backend (PortAudio, ASIO/WASAPI) will attach at the
 * same place later.
 */
#ifndef VERDANDI_JACK_NULL_JACK_H
#define VERDANDI_JACK_NULL_JACK_H

#include <jack/ringbuffer.h>
#include <jack/types.h>

#ifdef __cplusplus
extern "C" {
#endif

jack_client_t *jack_client_open(const char *client_name, jack_options_t options, jack_status_t *status, ...);
int jack_client_close(jack_client_t *client);
int jack_activate(jack_client_t *client);
int jack_deactivate(jack_client_t *client);
const char *jack_get_client_name(jack_client_t *client);
jack_nframes_t jack_get_sample_rate(jack_client_t *client);

int jack_set_process_callback(jack_client_t *client, JackProcessCallback cb, void *arg);
void jack_on_shutdown(jack_client_t *client, JackShutdownCallback cb, void *arg);
int jack_set_xrun_callback(jack_client_t *client, JackXRunCallback cb, void *arg);
int jack_set_port_registration_callback(jack_client_t *client, JackPortRegistrationCallback cb, void *arg);
int jack_set_client_registration_callback(jack_client_t *client, JackClientRegistrationCallback cb, void *arg);

jack_port_t *jack_port_register(jack_client_t *client, const char *port_name, const char *port_type, unsigned long flags, unsigned long buffer_size);
void *jack_port_get_buffer(jack_port_t *port, jack_nframes_t nframes);
const char *jack_port_name(const jack_port_t *port);
const char *jack_port_type(const jack_port_t *port);
int jack_port_flags(const jack_port_t *port);
jack_port_t *jack_port_by_name(jack_client_t *client, const char *port_name);
const char **jack_get_ports(jack_client_t *client, const char *port_name_pattern, const char *type_name_pattern, unsigned long flags);
const char **jack_port_get_all_connections(const jack_client_t *client, const jack_port_t *port);
void jack_free(void *ptr);

int jack_connect(jack_client_t *client, const char *source_port, const char *destination_port);
int jack_disconnect(jack_client_t *client, const char *source_port, const char *destination_port);

float jack_cpu_load(jack_client_t *client);
jack_nframes_t jack_frame_time(const jack_client_t *client);
jack_nframes_t jack_last_frame_time(const jack_client_t *client);

#ifdef __cplusplus
}
#endif

#endif
