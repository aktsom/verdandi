/* audio_asio_probe.h (M19): what is registered as an ASIO driver on this PC and what each one says when it is loaded the way an audio program loads it. PortAudio's ASIO host API silently drops a driver
 * that does not answer (and the whole host API when none does), so the only way to say WHY there is no ASIO is to look ourselves: the registry (the 64-bit and the 32-bit view), the driver file (does it
 * exist, is it 64-bit), COM (the class can be made), the driver's own init (the message it gives when another program has the card). docs/port/phase-m19.md */
#ifndef VERDANDI_AUDIO_ASIO_PROBE_H
#define VERDANDI_AUDIO_ASIO_PROBE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    VA_OK = 0,        /* loaded, initialised, the numbers below are the driver's */
    VA_REGISTRY,      /* the registry entry has no usable class id */
    VA_NO_CLASS,      /* the class is not registered for this program (a 32-bit driver in a 64-bit program, or not registered at all) */
    VA_NO_FILE,       /* the driver file is not there */
    VA_WRONG_BITS,    /* the driver file is 32-bit */
    VA_CREATE,        /* COM could not make the class (the driver file would not load, or the class says no) */
    VA_INIT,          /* the driver's init said no: the message is what the driver wrote (usually: another program has the card) */
    VA_TIMEOUT        /* the driver did not answer within the time allowed */
} va_status;

#define VA_CH 40

typedef struct {
    char name[64];      /* the name in the registry (the one PortAudio shows) */
    char clsid[48];
    char file[260];     /* the driver file (InprocServer32), "" when not found */
    int view;           /* 64 or 32: the registry view the entry was found in */
    va_status status;
    char detail[240];   /* why it failed, in plain words (the driver's own message when it has one) */
    int in_ch, out_ch;
    long buf_min, buf_max, buf_pref, buf_gran; /* frames; gran -1 = powers of two, 0 = only the preferred size */
    double rate;
    long version;
    char driver_name[64]; /* what the driver calls itself */
    unsigned can_rates;   /* bit 0 44100, 1 48000, 2 88200, 3 96000: the rates the driver says it can run at (ASIOCanSampleRate) */
    int n_in_names, n_out_names;
    char in_names[VA_CH][24], out_names[VA_CH][24]; /* what the driver calls its channels ("Analog 1", "SPDIF L"); the first VA_CH of each */
} va_driver;

#define VA_MAX 16

/* looks at every registered driver. log (may be NULL) gets one plain line each ("asio: ..."). returns how many drivers are registered; out has them (up to max) */
int va_probe(va_driver *out, int max, void (*log)(const char *line));

/* the same for ONE driver, by its registry name, without a line in the log: the card's clock now (out->rate), the rates it can run at, the channel names. used right before a stream is opened, to see which rate the
 * card runs at (another program may have set it). returns 0 when the driver was found and answered (out->status == VA_OK), else -1 (out->status and out->detail say why when it was found) */
int va_probe_one(const char *name, va_driver *out);

/* the summary for the page and the log: how many registered, how many usable, one sentence of the reason when none is */
void va_summary(const va_driver *d, int n, char *out, size_t outn, int *usable);

#ifdef __cplusplus
}
#endif
#endif
