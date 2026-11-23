-- M31 (docs/port/phase-m31.md): the standing note on the norns window follows the audio state of the Windows build WHILE the program runs (the 3-second poll of the notes calls _menu.audio_note_update): a driver that vanishes
-- says NO SOUND with the reason, the note goes when the sound is back, a note of another kind is never cleared by it. run from the repo root: lua5.3 linux/tests/audio_note_poll_test.lua
local src = io.open("lua/core/menu.lua"):read("a")
local block = src:match("(%-%- Windows: when the sound card could not be opened.-)\n%-%- the mouse on the oled")
assert(block, "the audio note block was not found in lua/core/menu.lua")
local fails = 0
local function check(cond, what) if not cond then fails = fails + 1; print("FAIL " .. what) end end
local info = {mode = "device", note = ""}
local shown_count, hooks = 0, {}
_norns = {audio_info = function() return info end, set_warning = function() end}
_menu = {show_note = function() shown_count = shown_count + 1 end}
hook = {system_post_startup = {register = function(_, name, fn) hooks[name] = fn end}}
load(block)()
check(type(_menu.audio_note_update) == "function", "the function exists")
check(hooks["menu-audio-fallback"] ~= nil, "it is also run once at the start (the hook)")

info = {mode = "device", note = ""}
_menu.audio_note_update()
check(_menu.audio_note == nil, "sound on a device and nothing to say: no note")

-- the driver vanishes: the card does not call back, the reopen fails
info = {mode = "fallback", note = "no sound: audio device 'asio:Fireface' is not there. null audio is used, the device is tried again every 3 s"}
_menu.audio_note_update()
check(_menu.audio_note and _menu.audio_note:find("^NO SOUND%. audio device 'asio:Fireface' is not there"), "NO SOUND with the reason (the prefix 'no sound: ' is not said twice): " .. tostring(_menu.audio_note))
local n = shown_count
_menu.audio_note_update()
check(shown_count == n, "the same state again changes nothing (no flicker)")

-- the driver comes back (the watchdog reopened it)
info = {mode = "device", note = "the sound card was reopened (the card answers again)"}
_menu.audio_note_update()
check(_menu.audio_note == nil, "the sound is back: the note is gone (a confirmation is not a standing note)")

-- playing on another device than the chosen one (busy ASIO): a standing note
info = {mode = "device", note = "ASIO driver 'X' is busy: another program has it. Using WASAPI on 'Y' instead"}
_menu.audio_note_update()
check(_menu.audio_note and _menu.audio_note:find("^AUDIO: ASIO driver 'X' is busy"), "a standing note for a busy driver: " .. tostring(_menu.audio_note))
info = {mode = "device", note = ""}
_menu.audio_note_update()
check(_menu.audio_note == nil, "and it goes when the note goes")

-- a note of another kind (the Linux/macOS 'not connected', set by another hook) is not cleared by this function
_menu.audio_note = "AUDIO: not connected, see SYSTEM > AUDIO"
info = {mode = "device", note = ""}
_menu.audio_note_update()
check(_menu.audio_note == "AUDIO: not connected, see SYSTEM > AUDIO", "a note that is not its own stays")
print(fails == 0 and "audio note poll: all scenarios pass" or (fails .. " failures"))
os.exit(fails == 0)
