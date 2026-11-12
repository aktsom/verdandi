#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void clock_link_init();
void clock_link_start();
void clock_link_join_session();
void clock_link_leave_session();
void clock_link_set_quantum(double quantum);
void clock_link_set_tempo(double tempo);
void clock_link_set_transport_start();
void clock_link_set_transport_stop();
void clock_link_set_start_stop_sync(bool sync_enabled);
double clock_link_get_beat();
double clock_link_get_tempo();
uint64_t clock_link_number_of_peers();
#ifdef NORNS_WINDOWS
// Windows: the output latency (ms) that is added to the beat Link gives (0 while there is no sound card)
double clock_link_latency_ms();
// Windows: is Link start/stop sync switched on, and does the Link session play now (as far as this program has seen)
bool clock_link_start_stop_sync_enabled();
bool clock_link_is_playing();
#endif

#ifdef __cplusplus
}
#endif
