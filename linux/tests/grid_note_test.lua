-- the standing note on the device window (lua/core/menu.lua _menu.show_note): the most urgent one, one at a time. run from the repo root:
--   lua5.3 linux/tests/grid_note_test.lua
local src = io.open("lua/core/menu.lua"):read("a")
local block = src:match("(%-%- MIC: what norns' input hears.-)\nhook%.system_post_startup")
assert(block, "input block not found")
local fails = 0
local function check(cond, what) if not cond then fails = fails + 1; print("FAIL " .. what) end end
local note
util = {os_capture = function() return "" end, file_exists = function() return false end}
_norns = {set_warning = function(t) note = t end, show_control = function() end}
_menu = {}
load(block)()
local function shown() _menu.show_note(); return note end

_menu.audio_note, _menu.grid_note, _menu.plugin_note, _menu.input = nil, nil, nil, "mic"
check(shown() == "", "nothing to say: no note")
_menu.audio_note = "AUDIO: not connected, see SYSTEM > AUDIO"
check(shown() == _menu.audio_note, "the audio note alone")
_menu.grid_note = "GRID: serialosc has this grid, see log"
check(shown() == _menu.grid_note, "the grid note comes before the audio note")
_menu.input = "monitor"
check(shown():find("feedback"), "the sink monitor warning comes before both")
_menu.input = "mic"
_menu.plugin_note = "PLUGINS: wrong-architecture plug-in, see log"
check(shown() == _menu.plugin_note, "the plug-in note comes before the grid note (SuperCollider will not start)")
_menu.input = "monitor"
check(shown():find("feedback"), "the sink monitor warning still comes first")
_menu.input = "mic"
_menu.plugin_note = nil
check(shown() == _menu.grid_note, "the plug-in note gone: the grid note again")
_menu.grid_note = nil
check(shown() == _menu.audio_note, "the grid note gone: the audio note again")
_menu.audio_note = nil
check(shown() == "", "all gone: no note")
print(fails == 0 and "device window notes: all scenarios pass" or (fails .. " failures"))
os.exit(fails == 0)
