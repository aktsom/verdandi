// a USB MIDI device that is unplugged or powered off and comes back (the BeatStep Pro of the owner's laptop: "dev_monitor: adding midi device", two ports, "midi inconsistency for device" at the unplug, and a second
// "adding midi device" that listed nothing). the REAL device monitor (device_monitor.cc, included here), device list (device_list.cc), device (device.cc, device_midi.cc with its read threads) and lua/core/midi.lua run in one
// process; what they stand on is faked: udev (a device is a node, a subsystem, a syspath that is a real directory with midiC<n>D<m> entries, attributes) and ALSA (cards that are present or not, rawmidi handles that are exclusive per
// subdevice, reads that block until bytes arrive or the card is gone: -ENODEV). udev events are injected by calling add_dev / rm_dev as the watch loop does.
// run from run_all.sh: the scenarios (same node again, a new node, no remove event at all, a remove that comes after the add, the card not ready on the first look) and a stress run of random plug and unplug sequences.
#include <dirent.h>
#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include <condition_variable>
#include <deque>
#include <map>
#include <mutex>
#include <set>
#include <string>
#include <vector>

extern "C" {
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
}

#include "device_monitor.cc"

#ifdef REPLUG_OLD_CODE
// the device code as it was before the fix (to show the failing state): it has none of the new calls
extern "C" int dev_list_midi_ports_listed(const char *) { return -1; }
extern "C" void dev_monitor_watch_tick(double *) {}
#endif

// ------------------------------------------------------------------------------------------------------ fake udev
struct udev_device {
    const char *node, *subsystem, *syspath;
    std::map<std::string, std::string> props, attrs;
    struct udev_device *parent;
};
extern "C" {
struct udev *udev_new(void) { return NULL; }
struct udev_monitor *udev_monitor_new_from_netlink(struct udev *, const char *) { return NULL; }
int udev_monitor_filter_add_match_subsystem_devtype(struct udev_monitor *, const char *, const char *) { return -1; }
int udev_monitor_enable_receiving(struct udev_monitor *) { return -1; }
int udev_monitor_get_fd(struct udev_monitor *) { return -1; }
struct udev_device *udev_monitor_receive_device(struct udev_monitor *) { return NULL; }
struct udev_enumerate *udev_enumerate_new(struct udev *) { return (struct udev_enumerate *)calloc(1, 8); }
int udev_enumerate_add_match_subsystem(struct udev_enumerate *, const char *) { return 0; }
int udev_enumerate_scan_devices(struct udev_enumerate *) { return 0; }
struct udev_list_entry *udev_enumerate_get_list_entry(struct udev_enumerate *);
struct udev_list_entry *udev_list_entry_get_next(struct udev_list_entry *);
const char *udev_list_entry_get_name(struct udev_list_entry *);
struct udev_enumerate *udev_enumerate_unref(struct udev_enumerate *e) { free(e); return NULL; }
struct udev_device *udev_device_new_from_syspath(struct udev *, const char *syspath);
struct udev_device *udev_device_unref(struct udev_device *) { return NULL; }
struct udev_device *udev_device_get_parent_with_subsystem_devtype(struct udev_device *, const char *, const char *) { return NULL; }
const char *udev_device_get_action(struct udev_device *) { return "add"; }
const char *udev_device_get_devnode(struct udev_device *d) { return d->node; }
const char *udev_device_get_subsystem(struct udev_device *d) { return d->subsystem; }
const char *udev_device_get_syspath(struct udev_device *d) { return d->syspath; }
struct udev_device *udev_device_get_parent(struct udev_device *d) { return d->parent; }
const char *udev_device_get_property_value(struct udev_device *d, const char *k) {
    auto i = d->props.find(k);
    return i == d->props.end() ? NULL : i->second.c_str();
}
const char *udev_device_get_sysattr_value(struct udev_device *d, const char *k) {
    auto i = d->attrs.find(k);
    return i == d->attrs.end() ? NULL : i->second.c_str();
}
// the kernel driver bound to a device (a platform device's "snd_virmidi"): the fake keeps it in the attribute "__driver"
const char *udev_device_get_driver(struct udev_device *d) {
    auto i = d->attrs.find("__driver");
    return i == d->attrs.end() ? NULL : i->second.c_str();
}
}

// the sound cards udev lists (an enumeration) and the devices that stand behind their syspaths
static std::vector<std::string> enum_paths;
static std::map<std::string, udev_device *> by_syspath;
extern "C" {
struct udev_list_entry *udev_enumerate_get_list_entry(struct udev_enumerate *) { return enum_paths.empty() ? NULL : (struct udev_list_entry *)(uintptr_t)1; }
struct udev_list_entry *udev_list_entry_get_next(struct udev_list_entry *e) {
    uintptr_t i = (uintptr_t)e;
    return i < enum_paths.size() ? (struct udev_list_entry *)(i + 1) : NULL;
}
const char *udev_list_entry_get_name(struct udev_list_entry *e) {
    uintptr_t i = (uintptr_t)e;
    return i >= 1 && i <= enum_paths.size() ? enum_paths[i - 1].c_str() : NULL;
}
struct udev_device *udev_device_new_from_syspath(struct udev *, const char *syspath) {
    auto it = by_syspath.find(syspath);
    return it == by_syspath.end() ? NULL : it->second;
}
}

// ------------------------------------------------------------------------------------------------------ fake ALSA
struct _snd_rawmidi {
    int card, dev, sub;
    bool is_in;
    bool dead = false;
    std::deque<unsigned char> in;
};
struct _snd_rawmidi_status { int dummy; };
struct _snd_ctl { int card; };
struct _snd_rawmidi_info { int device, stream, dummy_ports; };

static std::mutex amtx;
static std::condition_variable acv;
struct FakeCard {
    bool present = false;
    int ports = 2;
    bool ctl_ready = true; // the control node answers
};
static std::map<int, FakeCard> cards;
static std::set<_snd_rawmidi *> open_handles;
static int open_fail_count = 0; // the next N opens fail with -EBUSY

// the nodes /dev/snd/midiC<n>D<m> exist when the fake card is there (device_list.cc asks access(); the link has --wrap=access)
extern "C" int __real_access(const char *, int);
extern "C" int __wrap_access(const char *path, int mode) {
    int card = 0, dev = 0;
    if (sscanf(path, "/dev/snd/midiC%dD%d", &card, &dev) == 2) {
        std::lock_guard<std::mutex> l(amtx);
        return (cards.count(card) && cards[card].present) ? 0 : -1;
    }
    return __real_access(path, mode);
}

static void alsa_reset() {
    std::lock_guard<std::mutex> l(amtx);
    cards.clear();
    open_fail_count = 0;
    for (auto *h : open_handles) delete h;
    open_handles.clear();
}
static void alsa_plug(int card, int ports) {
    std::lock_guard<std::mutex> l(amtx);
    cards[card].present = true; cards[card].ports = ports; cards[card].ctl_ready = true;
}
static void alsa_unplug(int card) { // the device goes: every handle on it answers -ENODEV from now on, but stays open until the program closes it
    std::lock_guard<std::mutex> l(amtx);
    cards[card].present = false;
    for (auto *h : open_handles) if (h->card == card) h->dead = true;
    acv.notify_all();
}
static void alsa_feed(int card, int sub, std::vector<unsigned char> bytes) {
    std::lock_guard<std::mutex> l(amtx);
    for (auto *h : open_handles) if (h->card == card && h->sub == sub && h->is_in && !h->dead) for (auto b : bytes) h->in.push_back(b);
    acv.notify_all();
}
static int open_handle_count(int card) {
    std::lock_guard<std::mutex> l(amtx);
    int n = 0;
    for (auto *h : open_handles) if (h->card == card) n++;
    return n;
}

extern "C" {
int snd_ctl_open(snd_ctl_t **ctlp, const char *name, int) {
    int card = 0;
    if (sscanf(name, "hw:%d", &card) != 1) return -ENOENT;
    std::lock_guard<std::mutex> l(amtx);
    if (!cards.count(card) || !cards[card].present || !cards[card].ctl_ready) return -ENOENT;
    *ctlp = (snd_ctl_t *)new _snd_ctl{card};
    return 0;
}
int snd_ctl_close(snd_ctl_t *c) { delete (_snd_ctl *)c; return 0; }
size_t snd_rawmidi_info_sizeof(void) { return sizeof(_snd_rawmidi_info); }
void snd_rawmidi_info_set_device(snd_rawmidi_info_t *i, unsigned int d) { ((_snd_rawmidi_info *)i)->device = (int)d; }
void snd_rawmidi_info_set_stream(snd_rawmidi_info_t *i, snd_rawmidi_stream_t s) { ((_snd_rawmidi_info *)i)->stream = (int)s; }
int snd_ctl_rawmidi_info(snd_ctl_t *c, snd_rawmidi_info_t *i) {
    std::lock_guard<std::mutex> l(amtx);
    int card = ((_snd_ctl *)c)->card;
    if (!cards.count(card) || !cards[card].present) return -ENODEV;
    ((_snd_rawmidi_info *)i)->dummy_ports = cards[card].ports;
    return 0;
}
unsigned int snd_rawmidi_info_get_subdevices_count(const snd_rawmidi_info_t *i) { return (unsigned)((_snd_rawmidi_info *)i)->dummy_ports; }
int snd_rawmidi_open(snd_rawmidi_t **in, snd_rawmidi_t **out, const char *name, int) {
    int card, dev, sub;
    if (sscanf(name, "hw:%d,%d,%d", &card, &dev, &sub) != 3) return -ENOENT;
    std::lock_guard<std::mutex> l(amtx);
    if (!cards.count(card) || !cards[card].present) return -ENOENT;
    if (open_fail_count > 0) { open_fail_count--; return -EBUSY; }
    // a subdevice is exclusive, per direction: a handle that is still open on it (also one of a device that is gone) keeps it busy
    for (auto *h : open_handles)
        if (h->card == card && h->dev == dev && h->sub == sub && ((in && h->is_in) || (out && !h->is_in))) return -EBUSY;
    if (in) { auto *h = new _snd_rawmidi{card, dev, sub, true}; open_handles.insert(h); *in = (snd_rawmidi_t *)h; }
    if (out) { auto *h = new _snd_rawmidi{card, dev, sub, false}; open_handles.insert(h); *out = (snd_rawmidi_t *)h; }
    return 0;
}
int snd_rawmidi_close(snd_rawmidi_t *m) {
    std::lock_guard<std::mutex> l(amtx);
    open_handles.erase((_snd_rawmidi *)m);
    delete (_snd_rawmidi *)m;
    return 0;
}
ssize_t snd_rawmidi_read(snd_rawmidi_t *m, void *buf, size_t n) {
    _snd_rawmidi *h = (_snd_rawmidi *)m;
    std::unique_lock<std::mutex> l(amtx);
    for (;;) {
        if (h->dead) return -ENODEV;
        if (!h->in.empty()) {
            size_t k = 0;
            while (k < n && !h->in.empty()) { ((unsigned char *)buf)[k++] = h->in.front(); h->in.pop_front(); }
            return (ssize_t)k;
        }
        pthread_testcancel();
        acv.wait_for(l, std::chrono::milliseconds(20));
        pthread_testcancel();
    }
}
ssize_t snd_rawmidi_write(snd_rawmidi_t *, const void *, size_t n) { return (ssize_t)n; }
int snd_rawmidi_status_malloc(snd_rawmidi_status_t **p) { *p = (snd_rawmidi_status_t *)new _snd_rawmidi_status{0}; return 0; }
void snd_rawmidi_status_free(snd_rawmidi_status_t *p) { delete (_snd_rawmidi_status *)p; }
int snd_rawmidi_status(snd_rawmidi_t *, snd_rawmidi_status_t *) { return 0; }
size_t snd_rawmidi_status_get_xruns(const snd_rawmidi_status_t *) { return 0; }
int snd_rawmidi_drop(snd_rawmidi_t *) { return 0; }
}

// ------------------------------------------------------------------------------------------------------ what the rest of matron would be
extern "C" {
int keys_midi_take_pipe(void) { return -1; }
int jack_midi_in_take_pipe(void) { return -1; }
void jack_midi_in_set_clock_flag(const bool *) {}
long jack_midi_out_send(const uint8_t *, size_t) { return -1; }
long aseq_out_send(const uint8_t *, size_t) { return -1; }
void clock_midi_handle_message(uint8_t) {}
void clock_midi_handle_message_at(uint8_t, double) {}
void clock_midi_handle_song_position(uint16_t) {}
int dev_monome_init(void *) { return -1; }
int dev_hid_init(void *) { return -1; }
int dev_crow_init(void *) { return -1; }
int dev_serial_init(void *, lua_State *) { return -1; }
void dev_monome_all_led(struct dev_monome *, int8_t, bool) {}
void dev_monome_refresh(struct dev_monome *) {}
int monome_led_all(monome_t *, unsigned int) { return 0; }
int jack_midi_in_start(void) { return -1; }
int aseq_out_start(void) { return -1; }
}

// events: a queue the test "main loop" drains, as event_loop does (the real events.cc needs the whole of matron)
static std::mutex evmtx;
static std::deque<union event_data *> evq;
extern "C" union event_data *event_data_new(event_t t) {
    union event_data *e = (union event_data *)calloc(1, sizeof(union event_data));
    ((struct event_common *)e)->type = t;
    return e;
}
extern "C" void event_data_free(union event_data *e) { free(e); }
extern "C" void event_post(union event_data *e) {
    std::lock_guard<std::mutex> l(evmtx);
    evq.push_back(e);
}

// ------------------------------------------------------------------------------------------------------ the Lua side: lua/core/midi.lua as norns runs it
static lua_State *L;
static void lua_world() {
    L = luaL_newstate();
    luaL_openlibs(L);
    const char *prelude =
        "package.path = 'lua/?.lua;lua/core/?.lua;lua/lib/?.lua;' .. package.path\n"
        "util = dofile('lua/lib/util.lua'); package.loaded.util = util\n"
        "tab = dofile('lua/lib/tabutil.lua')\n"
        "params = {lookup = {}}\n"
        "_menu = {rebuild_params = function() end, menu_midi_event = function() end}\n"
        "norns = {none = function() end}\n"
        "removed_mapped = {}\n"
        "norns.midimap = {device_removed = function(d) removed_mapped[#removed_mapped + 1] = d.name end}\n"
        "_norns = {midi = {}, midi_send = function() end}\n"
        "midi = dofile('lua/core/midi.lua')\n"
        "events_seen = {}\n";
    if (luaL_dostring(L, prelude) != 0) {
        fprintf(stderr, "lua: %s\n", lua_tostring(L, -1));
        exit(3);
    }
}
static void lua_call_midi(const char *fn, int nargs_before) { (void)fn; (void)nargs_before; }

// the main loop, as event_loop / w_handle_midi_*: drain what the device threads and the monitor posted
static void drain() {
    for (;;) {
        union event_data *e = NULL;
        {
            std::lock_guard<std::mutex> l(evmtx);
            if (evq.empty()) return;
            e = evq.front();
            evq.pop_front();
        }
        lua_getglobal(L, "_norns");
        lua_getfield(L, -1, "midi");
        switch (e->type) {
        case EVENT_MIDI_ADD: {
            struct dev_common *base = (struct dev_common *)e->midi_add.dev;
            lua_getfield(L, -1, "add");
            lua_pushinteger(L, base->id + 1);
            lua_pushstring(L, base->name);
            lua_pushlightuserdata(L, e->midi_add.dev);
            lua_pushboolean(L, 0);
            if (lua_pcall(L, 4, 0, 0) != 0) { fprintf(stderr, "midi.add: %s\n", lua_tostring(L, -1)); lua_pop(L, 1); }
            break;
        }
        case EVENT_MIDI_REMOVE:
            lua_getfield(L, -1, "remove");
            lua_pushinteger(L, e->midi_remove.id + 1);
            if (lua_pcall(L, 1, 0, 0) != 0) { fprintf(stderr, "midi.remove: %s\n", lua_tostring(L, -1)); lua_pop(L, 1); }
            break;
        case EVENT_MIDI_EVENT: {
            lua_getfield(L, -1, "event");
            lua_pushinteger(L, e->midi_event.id + 1);
            lua_newtable(L);
            for (size_t i = 0; i < e->midi_event.nbytes && i < 3; i++) { lua_pushinteger(L, e->midi_event.data[i]); lua_rawseti(L, -2, (int)i + 1); }
            if (lua_pcall(L, 2, 0, 0) != 0) { fprintf(stderr, "midi.event: %s\n", lua_tostring(L, -1)); lua_pop(L, 1); }
            break;
        }
        default: break;
        }
        lua_settop(L, 0);
        free(e);
    }
}

// the names in midi.devices (sorted, "|" between) and the vport names that have a device
static std::string lua_str(const char *code) {
    if (luaL_dostring(L, code) != 0) { std::string m = lua_tostring(L, -1); lua_pop(L, 1); return "LUA ERROR: " + m; }
    std::string r = lua_tostring(L, -1) ? lua_tostring(L, -1) : "";
    lua_pop(L, 1);
    return r;
}
static std::string device_names() {
    return lua_str("local n = {} for _, d in pairs(midi.devices) do n[#n + 1] = d.name end table.sort(n) return table.concat(n, '|')");
}
static std::string vport_map() { // "1=name,2=name" for vports that have a device
    return lua_str("local t = {} for i = 1, 16 do if midi.vports[i].device then t[#t + 1] = i .. '=' .. midi.vports[i].name end end return table.concat(t, ',')");
}
static std::string vport_names() { // every vport that has a name (the remembered ones too)
    return lua_str("local t = {} for i = 1, 16 do if midi.vports[i].name ~= 'none' then t[#t + 1] = i .. '=' .. midi.vports[i].name end end return table.concat(t, ',')");
}

// ------------------------------------------------------------------------------------------------------ a plugged device, as udev shows it
static std::string tmproot;
static std::map<int, std::string> card_dir;
static std::vector<udev_device *> keep;
static const char *PRODUCT = "Arturia BeatStep Pro";

static udev_device *card_device(int card) { // the sound card's "add" event: its syspath holds midiC<n>D0
    std::string dir = tmproot + "/card" + std::to_string(card);
    mkdir(dir.c_str(), 0755);
    mkdir((dir + "/midiC" + std::to_string(card) + "D0").c_str(), 0755);
    card_dir[card] = dir;
    auto *usb = new udev_device{NULL, "usb", "/nonexistent", {}, {{"product", PRODUCT}}, NULL};
    std::string *node = new std::string("/dev/snd/controlC" + std::to_string(card));
    std::string *sp = new std::string(dir);
    auto *d = new udev_device{node->c_str(), "sound", sp->c_str(), {}, {}, usb};
    keep.push_back(usb); keep.push_back(d);
    by_syspath[dir] = d;
    return d;
}
static udev_device *midi_node_device(int card) { // the "remove" event of the midi node itself
    std::string *node = new std::string("/dev/snd/midiC" + std::to_string(card) + "D0");
    auto *d = new udev_device{node->c_str(), "sound", "/nonexistent", {}, {}, NULL};
    keep.push_back(d);
    return d;
}
static void settle(int ms = 120) { usleep(ms * 1000); drain(); }
static void forget_enum(int card) {
    std::string dir = tmproot + "/card" + std::to_string(card);
    for (size_t i = 0; i < enum_paths.size(); i++) if (enum_paths[i] == dir) { enum_paths.erase(enum_paths.begin() + (long)i); break; }
}
static void know_enum(int card) {
    std::string dir = tmproot + "/card" + std::to_string(card);
    for (auto &p : enum_paths) if (p == dir) return;
    enum_paths.push_back(dir);
}
// the udev "add" of a sound card (what the watch loop does with the event), and the card showing up in an enumeration
static void udev_add(int card) { know_enum(card); add_dev(card_device(card), DEV_FILE_SOUND); }
static void plug(int card, int ports = 2) {
    alsa_plug(card, ports);
    udev_add(card);
    settle();
}
static void unplug(int card, bool udev_remove = true) {
    alsa_unplug(card);
    forget_enum(card);
    if (udev_remove) rm_dev(midi_node_device(card), DEV_FILE_SOUND);
    settle();
}
// one round of the watch loop's own check (it runs every 3 seconds, and at once when a read thread found a device gone)
static void tick() {
    double last = 0;
    dev_monitor_watch_tick(&last);
    settle();
}

// ------------------------------------------------------------------------------------------------------ the virtual MIDI card (snd-virmidi): udev shows the card with the id "VirMIDI" under a platform device bound to snd_virmidi,
// and no "product" anywhere. /proc/asound (NORNS_PROC_ASOUND) has its names
static udev_device *virmidi_card_device(int card, const char *id = "VirMIDI", const char *driver = "snd_virmidi") {
    std::string dir = tmproot + "/card" + std::to_string(card);
    mkdir(dir.c_str(), 0755);
    mkdir((dir + "/midiC" + std::to_string(card) + "D0").c_str(), 0755);
    card_dir[card] = dir;
    auto *plat = new udev_device{NULL, "platform", "/nonexistent", {}, {{"__driver", driver}}, NULL};
    std::string *node = new std::string("/dev/snd/controlC" + std::to_string(card));
    std::string *sp = new std::string(dir);
    auto *d = new udev_device{node->c_str(), "sound", sp->c_str(), {}, {{"id", id}}, plat};
    keep.push_back(plat); keep.push_back(d);
    by_syspath[dir] = d;
    return d;
}
static void proc_asound(int card, const char *id, const char *longname, const char *rawname) {
    std::string root = tmproot + "/proc";
    mkdir(root.c_str(), 0755);
    mkdir((root + "/card" + std::to_string(card)).c_str(), 0755);
    FILE *f = fopen((root + "/cards").c_str(), "w");
    fprintf(f, " %d [%-14s]: %s - %s\n                      %s\n", card, id, id, id, longname);
    fclose(f);
    f = fopen((root + "/card" + std::to_string(card) + "/midi0").c_str(), "w");
    fprintf(f, "%s\n", rawname);
    fclose(f);
    f = fopen((root + "/card" + std::to_string(card) + "/id").c_str(), "w");
    fprintf(f, "%s\n", id);
    fclose(f);
    setenv("NORNS_PROC_ASOUND", root.c_str(), 1);
}
static void udev_add_virmidi(int card, const char *id = "VirMIDI", const char *driver = "snd_virmidi") {
    know_enum(card);
    add_dev(virmidi_card_device(card, id, driver), DEV_FILE_SOUND);
}
static std::string logfile;
static void capture_log() { // the monitor's stderr lines, for the child of a CASE
    logfile = tmproot + "/stderr.log";
    freopen(logfile.c_str(), "w", stderr);
}
static std::string log_text() {
    fflush(stderr);
    std::string out;
    FILE *f = fopen(logfile.c_str(), "r");
    if (!f) return out;
    char buf[4096];
    size_t n;
    while ((n = fread(buf, 1, sizeof buf, f)) > 0) out.append(buf, n);
    fclose(f);
    return out;
}
static int count_of(const std::string &hay, const std::string &needle) {
    int n = 0;
    for (size_t p = hay.find(needle); p != std::string::npos; p = hay.find(needle, p + 1)) n++;
    return n;
}
// what a DAW does: opens the raw port for reading. a port that norns holds answers -EBUSY
static int daw_open(int card) {
    snd_rawmidi_t *in = NULL;
    std::string name = "hw:" + std::to_string(card) + ",0,0";
    int rc = snd_rawmidi_open(&in, NULL, name.c_str(), 0);
    if (rc == 0) snd_rawmidi_close(in);
    return rc;
}

static void world(const char *name) {
    char t[] = "/tmp/replugXXXXXX";
    tmproot = mkdtemp(t);
    alsa_reset();
    enum_paths.clear(); by_syspath.clear(); card_dir.clear();
    dev_list_init();
    lua_world();
    unsetenv("NORNS_MIDI_IGNORE"); unsetenv("NORNS_ALSA_MIDI_OUT_TO"); unsetenv("NORNS_PROC_ASOUND");
    (void)name;
}


// ------------------------------------------------------------------------------------------------------ the cases
#include <sys/wait.h>
static int failures;
#define EXPECT(cond, what)                                                       \
    do {                                                                         \
        if (!(cond)) {                                                           \
            printf("  FAIL: %s\n", what);                                        \
            fflush(stdout);                                                      \
            _exit(2);                                                            \
        }                                                                        \
    } while (0)
#define EXPECT_EQ(got, want, what)                                                                                 \
    do {                                                                                                          \
        std::string g_ = (got), w_ = (want);                                                                      \
        if (g_ != w_) {                                                                                           \
            printf("  FAIL: %s: got [%s], wanted [%s]\n", what, g_.c_str(), w_.c_str());                          \
            fflush(stdout);                                                                                       \
            _exit(2);                                                                                             \
        }                                                                                                         \
    } while (0)
#define CASE(name, ...)                                                                                              \
    do {                                                                                                             \
        fflush(stdout);                                                                                              \
        pid_t pid_ = fork();                                                                                         \
        if (pid_ == 0) {                                                                                             \
            world(name);                                                                                             \
            __VA_ARGS__;                                                                                             \
            fflush(stdout);                                                                                          \
            _exit(0);                                                                                                \
        }                                                                                                            \
        int st_ = 0;                                                                                                 \
        waitpid(pid_, &st_, 0);                                                                                      \
        if (!WIFEXITED(st_) || WEXITSTATUS(st_) != 0) {                                                              \
            printf("FAIL: %s (%s %d)\n", name, WIFSIGNALED(st_) ? "signal" : "exit", WIFSIGNALED(st_) ? WTERMSIG(st_) : WEXITSTATUS(st_)); \
            failures++;                                                                                              \
        } else {                                                                                                     \
            printf("ok:   %s\n", name);                                                                              \
        }                                                                                                            \
    } while (0)

static const char *TWO = "Arturia BeatStep Pro 1|Arturia BeatStep Pro 2";
static void listen_on_vport1() { lua_str("midi.vports[1].event = function(d) events_seen[#events_seen + 1] = d[1] end"); }
static int seen() { return atoi(lua_str("return tostring(#events_seen)").c_str()); }
static int handles(int card) { return open_handle_count(card); }

// the invariants of any state once things have settled: the list, Lua's devices, the vports and the open handles all say the same
static std::string check_state(const std::set<int> &present) {
    std::string bad;
    int total = 0;
    for (int c = 2; c <= 4; c++) {
        std::string path = "/dev/snd/midiC" + std::to_string(c) + "D0";
        int listed = dev_list_midi_ports_listed(path.c_str());
        bool p = present.count(c) > 0;
        if (listed != (p ? 2 : 0)) bad += " card" + std::to_string(c) + " listed " + std::to_string(listed) + " (want " + (p ? "2" : "0") + ");";
        if (handles(c) != (p ? 4 : 0)) bad += " card" + std::to_string(c) + " handles " + std::to_string(handles(c)) + " (want " + (p ? "4" : "0") + ");";
        total += listed;
    }
    int lua_n = atoi(lua_str("local n = 0 for _ in pairs(midi.devices) do n = n + 1 end return tostring(n)").c_str());
    if (lua_n != total) bad += " lua has " + std::to_string(lua_n) + " devices, the list " + std::to_string(total) + ";";
    // upstream's rule: a vport that has a name is wired to the device of that name (a second device of the same product only has a suffixed name that no vport has)
    std::string wiring = lua_str(
        "local bad = '' for i = 1, 16 do local n = midi.vports[i].name if n ~= 'none' then for _, d in pairs(midi.devices) do "
        "if d.name == n and midi.vports[i].device ~= d then bad = bad .. n .. '|' end end end end return bad");
    if (!wiring.empty()) bad += " vports not wired to the device of their name: " + wiring + ";";
    return bad;
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    int stress_runs = argc > 1 ? atoi(argv[1]) : 40;
    unsigned seed0 = argc > 2 ? (unsigned)atoi(argv[2]) : 1;


    // ---- the virtual MIDI card (snd-virmidi) must never be opened as a controller: Reaper reads its raw port, which has one reader
    CASE("a snd-virmidi card appears: not opened, not listed, one log line, the periodic check adds nothing; a DAW can open its raw port", {
        capture_log();
        proc_asound(2, "VirMIDI", "Virtual MIDI Card 1", "Virtual Raw MIDI (16 ports)");
        alsa_plug(2, 1); udev_add_virmidi(2); settle();
        EXPECT_EQ(device_names(), "", "the virtual card is not a norns MIDI device");
        EXPECT(handles(2) == 0, "no handle on the raw port");
        EXPECT(dev_list_midi_ports_listed("/dev/snd/midiC2D0") == 0, "not in the list");
        for (int i = 0; i < 4; i++) tick();
        EXPECT(handles(2) == 0, "the periodic check does not open it either");
        EXPECT_EQ(device_names(), "", "still nothing");
        EXPECT(daw_open(2) == 0, "a DAW can open the raw port (it is not busy)");
        EXPECT(count_of(log_text(), "skipped virtual raw MIDI card") == 1, "one log line, not one per check");
        EXPECT(count_of(log_text(), "adding midi device") == 0, "no 'adding midi device' for it");
        // a real controller next to it is still listed and opened
        plug(3);
        EXPECT_EQ(device_names(), TWO, "a real controller is listed as always");
        EXPECT_EQ(check_state({3}), "", "state");
        unplug(2); plug(2, 1);
        EXPECT(handles(2) == 0, "the card goes and comes back: still not opened");
    });
    CASE("the card is found by its /proc/asound names when the id and the driver say nothing (renamed id, no driver)", {
        capture_log();
        proc_asound(2, "Virtual", "Virtual MIDI Card 1", "Virtual Raw MIDI (16 ports)");
        alsa_plug(2, 1); udev_add_virmidi(2, "Virtual", "somedriver"); settle();
        EXPECT(handles(2) == 0 && device_names() == "", "skipped by the raw MIDI name");
        EXPECT(count_of(log_text(), "skipped virtual raw MIDI card") == 1, "and said");
    });
    CASE("the setting midi_ignore replaces the default list: with another list the virtual card is listed again, and a named controller is skipped", {
        capture_log();
        setenv("NORNS_MIDI_IGNORE", "Nothing here", 1);
        proc_asound(2, "VirMIDI", "Virtual MIDI Card 1", "Virtual Raw MIDI (16 ports)");
        alsa_plug(2, 1); udev_add_virmidi(2); settle();
        EXPECT(handles(2) > 0, "not in the list: opened as before (the setting is the owner's)");
        setenv("NORNS_MIDI_IGNORE", "BeatStep", 1);
        plug(3);
        EXPECT(handles(3) == 0, "a card whose name contains an entry is skipped");
    });
    CASE("the target of alsa_midi_out_to is a card a DAW reads: skipped too", {
        capture_log();
        setenv("NORNS_ALSA_MIDI_OUT_TO", "Arturia", 1);
        plug(3);
        EXPECT(handles(3) == 0 && device_names() == "", "skipped");
        EXPECT(count_of(log_text(), "skipped virtual raw MIDI card") == 1, "said once");
    });
    CASE("a virtual card that was opened before (the list changed, or the module came while an older norns ran): the next sweep releases it, Lua is told, a DAW can open it", {
        capture_log();
        setenv("NORNS_MIDI_IGNORE", "Nothing here", 1);
        proc_asound(2, "VirMIDI", "Virtual MIDI Card 1", "Virtual Raw MIDI (16 ports)");
        alsa_plug(2, 1); udev_add_virmidi(2); settle();
        EXPECT(handles(2) > 0, "opened");
        EXPECT(daw_open(2) == -EBUSY, "and a DAW is locked out: the problem");
        unsetenv("NORNS_MIDI_IGNORE");
        tick();
        EXPECT(handles(2) == 0, "released");
        EXPECT_EQ(device_names(), "", "out of the list");
        EXPECT(daw_open(2) == 0, "a DAW opens it without a restart of norns");
        EXPECT(count_of(log_text(), "released virtual raw MIDI card") == 1, "one line says so");
        tick(); tick();
        EXPECT(count_of(log_text(), "released virtual raw MIDI card") == 1, "and only once");
        EXPECT(handles(2) == 0, "it stays closed");
    });

    CASE("a clean unplug (udev remove) and the same node again: listed again, same names, same vports, the mapped events flow", {
        listen_on_vport1();
        plug(2);
        EXPECT_EQ(device_names(), TWO, "after the plug");
        EXPECT_EQ(vport_map(), "1=Arturia BeatStep Pro 1,2=Arturia BeatStep Pro 2", "vports after the plug");
        alsa_feed(2, 0, {0x90, 60, 100}); settle();
        EXPECT(seen() == 1, "a note reaches the script's handler");
        unplug(2);
        EXPECT_EQ(device_names(), "", "after the unplug");
        EXPECT_EQ(vport_map(), "", "no vport has a device");
        EXPECT_EQ(vport_names(), "1=Arturia BeatStep Pro 1,2=Arturia BeatStep Pro 2", "the vports remember the names");
        EXPECT_EQ(lua_str("return table.concat(removed_mapped, '|')"), TWO, "the MIDI MAP layer was told about both removals");
        plug(2);
        EXPECT_EQ(device_names(), TWO, "after the replug");
        EXPECT_EQ(vport_map(), "1=Arturia BeatStep Pro 1,2=Arturia BeatStep Pro 2", "the same vports again");
        alsa_feed(2, 0, {0x90, 62, 100}); settle();
        EXPECT(seen() == 2, "a note reaches the handler again without a restart");
        // MIDI MAP matches a device by its name: a control mapped to "Arturia BeatStep Pro" (the interface) or to one port works for the re-added devices, the params MAP uses the vport numbers (checked above)
        EXPECT_EQ(lua_str("local V = require('core/midimap_value') local ok = '' for _, d in pairs(midi.devices) do if V.name_matches('Arturia BeatStep Pro', d.name) and V.name_matches(d.name, d.name) and not V.is_non_controller(d.name) then ok = ok .. 'y' end end return ok"), "yy", "MIDI MAP name matching after the re-add");
        EXPECT_EQ(check_state({2}), "", "state");
    });
    CASE("a new node (the card number changed): the old entries are gone, the new ones are listed under the old names", {
        plug(2); unplug(2); plug(3);
        EXPECT_EQ(device_names(), TWO, "names");
        EXPECT_EQ(vport_map(), "1=Arturia BeatStep Pro 1,2=Arturia BeatStep Pro 2", "vports");
        EXPECT_EQ(check_state({3}), "", "state");
    });
    CASE("no udev remove at all: the device that vanished leaves the list by itself (its read thread says so), and the replug of the same node is listed under the same names", {
        listen_on_vport1();
        plug(2);
        unplug(2, false);
        tick();
        EXPECT_EQ(device_names(), "", "the vanished device is out of the list without a remove event");
        EXPECT_EQ(lua_str("return table.concat(removed_mapped, '|')"), TWO, "and Lua was told");
        plug(2);
        EXPECT_EQ(device_names(), TWO, "the replug of the same node");
        EXPECT_EQ(vport_map(), "1=Arturia BeatStep Pro 1,2=Arturia BeatStep Pro 2", "vports");
        alsa_feed(2, 0, {0x90, 60, 100}); settle();
        EXPECT(seen() == 1, "the new device delivers");
        EXPECT_EQ(check_state({2}), "", "state");
    });
    CASE("no udev remove, and the udev add of the new device comes first (the entries are stale when it arrives): they are replaced, not suffixed", {
        plug(2);
        alsa_unplug(2); alsa_plug(2, 2);
        usleep(150000); // the read threads find the device gone
        udev_add(2); settle();
        EXPECT_EQ(device_names(), TWO, "names without suffixes");
        EXPECT_EQ(check_state({2}), "", "state");
    });
    CASE("a remove that comes after the plug-in again is a late event: the new device stays", {
        plug(2);
        alsa_unplug(2); alsa_plug(2, 2);
        usleep(150000);
        udev_add(2); settle();
        rm_dev(midi_node_device(2), DEV_FILE_SOUND); settle();
        EXPECT_EQ(device_names(), TWO, "the late remove did not take the new device away");
        EXPECT_EQ(check_state({2}), "", "state");
    });
    CASE("the card does not answer when the udev add comes (not ready): nothing is listed, the periodic check lists it when it does", {
        { std::lock_guard<std::mutex> l(amtx); cards[2].present = true; cards[2].ports = 2; cards[2].ctl_ready = false; }
        udev_add(2); settle();
        EXPECT_EQ(device_names(), "", "not ready: nothing yet");
        tick();
        EXPECT_EQ(device_names(), "", "a check that finds it still not ready adds nothing and does not crash");
        { std::lock_guard<std::mutex> l(amtx); cards[2].ctl_ready = true; }
        tick();
        EXPECT_EQ(device_names(), TWO, "listed by the check");
        EXPECT_EQ(check_state({2}), "", "state");
    });
    CASE("a udev add that never came: the periodic check finds the card", {
        alsa_plug(2, 2); know_enum(2); card_device(2);
        tick();
        EXPECT_EQ(device_names(), TWO, "listed by the check");
        EXPECT_EQ(check_state({2}), "", "state");
    });
    CASE("a repeated udev add is skipped as a duplicate: no second set of entries", {
        plug(2);
        udev_add(2); settle(); udev_add(2); settle();
        tick();
        EXPECT_EQ(device_names(), TWO, "names");
        EXPECT_EQ(check_state({2}), "", "state");
    });
    CASE("a port that was busy when the add came is added by the check, without doubling the port that worked", {
        { std::lock_guard<std::mutex> l(amtx); open_fail_count = 3; }
        alsa_plug(2, 2);
        udev_add(2); settle();
        EXPECT_EQ(device_names(), "Arturia BeatStep Pro 2", "port 1 failed (busy), port 2 is there");
        tick();
        EXPECT_EQ(device_names(), TWO, "the check added the missing port");
        EXPECT_EQ(check_state({2}), "", "state");
    });
    CASE("a single-port device (a keyboard) unplugged without a remove and plugged in again", {
        plug(2, 1);
        EXPECT_EQ(device_names(), "Arturia BeatStep Pro", "one port: no number");
        unplug(2, false); tick();
        EXPECT_EQ(device_names(), "", "gone");
        plug(2, 1);
        EXPECT_EQ(device_names(), "Arturia BeatStep Pro", "back");
    });

    // random plug and unplug sequences: udev removes, silent vanishes, late removes, repeated adds, checks, in any order, two cards of the same product
    for (int run = 0; run < stress_runs; run++) {
        unsigned seed = seed0 + (unsigned)run;
        char name[96];
        snprintf(name, sizeof name, "stress: random plug and unplug sequence (seed %u)", seed);
        CASE(name, {
            srand(seed);
            std::set<int> present;
            std::string log;
            for (int step = 0; step < 24; step++) {
                int c = 2 + rand() % 2;
                switch (rand() % 7) {
                case 0: case 1: // plug (a card number that may be a recent one again)
                    if (!present.count(c)) { alsa_plug(c, 2); present.insert(c); udev_add(c); log += "plug" + std::to_string(c) + " "; }
                    break;
                case 2: // unplug with the udev remove
                    if (present.count(c)) { alsa_unplug(c); forget_enum(c); rm_dev(midi_node_device(c), DEV_FILE_SOUND); present.erase(c); log += "unplug" + std::to_string(c) + " "; }
                    break;
                case 3: // unplug, no udev remove
                    if (present.count(c)) { alsa_unplug(c); forget_enum(c); present.erase(c); log += "vanish" + std::to_string(c) + " "; }
                    break;
                case 4: // a remove that came too late (or for nothing)
                    rm_dev(midi_node_device(c), DEV_FILE_SOUND); log += "late-remove" + std::to_string(c) + " ";
                    break;
                case 5: // a repeated add
                    if (present.count(c)) { udev_add(c); log += "dup-add" + std::to_string(c) + " "; }
                    break;
                default: { double last = 0; dev_monitor_watch_tick(&last); log += "tick "; }
                }
                settle(8);
            }
            // converge: two checks (what the loop does within a few seconds)
            tick(); settle(30); tick(); settle(30);
            std::string bad = check_state(present);
            if (!bad.empty()) { printf("  sequence: %s\n", log.c_str()); }
            EXPECT_EQ(bad, "", "the settled state");
        });
    }
    if (failures) {
        printf("midi_replug_test: %d failed\n", failures);
        return 1;
    }
    printf("midi_replug_test: all passed\n");
    return 0;
}
