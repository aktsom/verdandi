
#include <sndfile.h>

#ifdef NORNS_WINDOWS
// a UTF-8 or long path (an [ext] folder, a long file name): crone/src/sf_path.h
#include "../../crone/src/sf_path.h"
#define SND_FILE_OPEN sf_open_path
#else
#define SND_FILE_OPEN sf_open
#endif
#include "snd_file.h"

struct snd_file_desc snd_file_inspect(const char *path) {
    SF_INFO sfinfo;
    sfinfo.format = 0;
    SNDFILE *sndfile = SND_FILE_OPEN(path, SFM_READ, &sfinfo);
    struct snd_file_desc res = {.channels = 0, .frames = 0, .samplerate = 0};
    if (sndfile == NULL) {
        return res;
    }
    res.channels = sfinfo.channels;
    res.frames = sfinfo.frames;
    res.samplerate = sfinfo.samplerate;
    sf_close(sndfile);
    return res;
}
