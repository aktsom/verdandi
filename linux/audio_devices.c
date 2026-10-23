/*
 * audio_devices: the ALSA sound cards, for SYSTEM > AUDIO (lua/core/menu/audio.lua) when norns starts its
 * own jackd. one line per card:
 *
 *   <hw:CARD=id> TAB <name> TAB <input channels> TAB <output channels>
 *
 * the id is what jackd takes as -C / -P. channels: 2 if the card has a capture / playback stream, else 0
 * (the real count would need opening the device, which fails while PipeWire holds it). tabs and newlines in
 * names become spaces. no cards: no output.
 */

#include <alsa/asoundlib.h>
#include <stdio.h>
#include <string.h>

static void clean(char *s) {
    for (; *s; s++) {
        if (*s == '\t' || *s == '\n' || *s == '\r') {
            *s = ' ';
        }
    }
}

int main(void) {
    int card = -1;
    while (snd_card_next(&card) == 0 && card >= 0) {
        char hw[32];
        snprintf(hw, sizeof hw, "hw:%d", card);
        snd_ctl_t *ctl;
        if (snd_ctl_open(&ctl, hw, 0) < 0) {
            continue;
        }
        snd_ctl_card_info_t *info;
        snd_ctl_card_info_alloca(&info);
        if (snd_ctl_card_info(ctl, info) < 0) {
            snd_ctl_close(ctl);
            continue;
        }
        int ins = 0, outs = 0, dev = -1;
        while (snd_ctl_pcm_next_device(ctl, &dev) == 0 && dev >= 0) {
            snd_pcm_info_t *pcm;
            snd_pcm_info_alloca(&pcm);
            snd_pcm_info_set_device(pcm, (unsigned)dev);
            snd_pcm_info_set_subdevice(pcm, 0);
            snd_pcm_info_set_stream(pcm, SND_PCM_STREAM_CAPTURE);
            if (snd_ctl_pcm_info(ctl, pcm) >= 0) {
                ins = 2;
            }
            snd_pcm_info_set_stream(pcm, SND_PCM_STREAM_PLAYBACK);
            if (snd_ctl_pcm_info(ctl, pcm) >= 0) {
                outs = 2;
            }
        }
        char id[128], name[256];
        snprintf(id, sizeof id, "%s", snd_ctl_card_info_get_id(info));
        snprintf(name, sizeof name, "%s", snd_ctl_card_info_get_name(info));
        clean(name);
        if (ins + outs > 0) {
            printf("hw:CARD=%s\t%s\t%d\t%d\n", id, name, ins, outs);
        }
        snd_ctl_close(ctl);
    }
    return 0;
}
