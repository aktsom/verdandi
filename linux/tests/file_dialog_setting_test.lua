-- "Open the file dialog when a script loads a file" (right-click menu, Linux desktop): lua/lib/fileselect.lua and lua/core/ui_settings.lua. run from the repo root:
--   lua5.3 linux/tests/file_dialog_setting_test.lua
-- off by default: a script's file chooser is norns's own on-screen browser only (no call to _norns.choose_file, which opens the system dialog); ticked: the dialog
-- opens as before; unticking stops it at once; the setting is saved in ui.conf (file_dialog=1/0) and loaded at start; a damaged value falls back to off with a
-- log line; the result of a chosen file reaches the script as before; cancelling returns nothing and the browser stays usable; without the Linux desktop's
-- _norns.ui_file_dialog (macOS, the device) nothing changes. (the C side - the tick in the menu, a real dialog - is in the window tests of run_all.sh)
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local tmp = os.tmpname()
os.remove(tmp)
os.execute("mkdir -p " .. tmp)
local real_open, real_remove, real_rename = io.open, os.remove, os.rename
local function map(p) return (p:gsub("^/home/we", tmp)) end
io.open = function(p, m) return real_open(map(p), m) end
os.remove = function(p) return real_remove(map(p)) end
os.rename = function(a, b) return real_rename(map(a), map(b)) end

local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL " .. what) end end
local function slurp(p) local h = real_open(map(p)); if not h then return nil end local c = h:read("a"); h:close(); return c end
local function put(p, text) local h = real_open(map(p), "w"); h:write(text); h:close() end

-- the environment of the norns menu and of a script
local opened, dialog_set, looks = {}, {}, 0
local on_desktop = true
local function install_norns()
  _norns = {
    ui_look = function() looks = looks + 1 end,
    choose_file = function(dir) opened[#opened + 1] = dir end,
    choose_file_close = function() end,
    key = function() end, enc = function() end, show_control = function() end,
  }
  if on_desktop then _norns.ui_file_dialog = function(on) dialog_set[#dialog_set + 1] = on end end
end
install_norns()
screen = setmetatable({}, {__index = function() return function() end end})
util = {
  clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end,
  scandir = function(dir) return {"a.wav", "b.wav", "sub/"} end,
  s_to_hms = function(s) return tostring(s) end, trim_string_to_width = function(s) return s end,
}
audio = {file_info = function() return 2, 48000, 48000 end}
package.loaded.util = util
clock = {cancel = function() end}
local menu_mode = false
norns = {none = function() end, menu = {
  status = function() return menu_mode end, get_key = function() return "k" end, get_enc = function() return "e" end,
  get_redraw = function() return "r" end, get_refresh = function() return "f" end,
  set = function() end, init = function() end}}
local fs = require 'fileselect' -- sets _norns.file_chosen
local ui = require 'core/ui_settings'
local logged = {}
ui.log = function(s) logged[#logged + 1] = s end
local function logged_has(s) for _, l in ipairs(logged) do if l:find(s, 1, true) then return true end end return false end

local function fresh_start() -- what a restart does: a new state from the file, applied
  opened, dialog_set, logged = {}, {}, {}
  ui.state = nil
  ui.load_and_apply()
end
local function use_chooser() -- a script opens the chooser, leaves it again with no file
  local got
  fs.enter("/home/we/dust/audio/", function(p) got = p end, "audio")
  return function() fs.path = nil; fs.exit() end, function() return got end
end

-- ---- off by default ----
fresh_start()
check(ui.state.file_dialog == false, "default: the setting is off")
check(dialog_set[#dialog_set] == false, "at start the window is told: off (so that the menu shows no tick)")
local leave = use_chooser()
check(#opened == 0, "default: a script's chooser does not open the system dialog (" .. #opened .. " calls)")
check(fs.active == true, "default: norns's own browser is up")
fs.getlist()
check(#opened == 0, "default: changing folder in the browser opens no dialog either")
leave()

-- ---- ticked ----
ui.set_file_dialog(true)
check(ui.state.file_dialog == true, "ticked: the setting is on")
check(dialog_set[#dialog_set] == true, "ticked: the window is told")
check((slurp("/home/we/ui.conf") or ""):find("file_dialog=1", 1, true) ~= nil, "ticked: saved in ui.conf as file_dialog=1")
opened = {}
leave = use_chooser()
check(#opened == 1 and opened[1] == "/home/we/dust/audio/", "ticked: the chooser opens the dialog once, in the browser's folder (" .. #opened .. " calls)")
fs.getlist()
check(#opened == 2, "ticked: and again when the browser changes folder (as before)")
leave()

-- ---- unticked at once ----
ui.set_file_dialog(false)
check((slurp("/home/we/ui.conf") or ""):find("file_dialog=0", 1, true) ~= nil, "unticked: saved as file_dialog=0")
opened = {}
leave = use_chooser()
check(#opened == 0, "unticked: no dialog any more, without a restart")
leave()

-- ---- a change made in the window's menu reaches lua (C calls _norns.ui_file_dialog_changed) ----
check(type(_norns.ui_file_dialog_changed) == "function", "lua answers the menu's tick (_norns.ui_file_dialog_changed)")
_norns.ui_file_dialog_changed("1")
check(ui.state.file_dialog == true and (slurp("/home/we/ui.conf") or ""):find("file_dialog=1", 1, true) ~= nil, "the menu ticked it: on and saved")
_norns.ui_file_dialog_changed("0")
check(ui.state.file_dialog == false and (slurp("/home/we/ui.conf") or ""):find("file_dialog=0", 1, true) ~= nil, "the menu unticked it: off and saved")

-- ---- the other lines of ui.conf stay ----
put("/home/we/ui.conf", "brightness=0.6\ncolour=pink\ncontrast=0.3\nfile_dialog=0\nsomething=else\n")
fresh_start()
ui.set_file_dialog(true)
local text = slurp("/home/we/ui.conf")
check(text:find("brightness=0.6", 1, true) and text:find("colour=pink", 1, true) and text:find("contrast=0.3", 1, true) and text:find("something=else", 1, true),
  "the other settings and unknown lines are kept when the file is written")

-- ---- saved and loaded across a restart ----
fresh_start()
check(ui.state.file_dialog == true, "restart: file_dialog=1 is loaded")
check(dialog_set[#dialog_set] == true, "restart: the window is told on (so that the menu shows the tick)")
opened = {}
leave = use_chooser()
check(#opened == 1, "restart: the dialog opens without ticking again")
leave()
put("/home/we/ui.conf", "brightness=0.6\n")
fresh_start()
check(ui.state.file_dialog == false and dialog_set[#dialog_set] == false, "a ui.conf from before this setting: off")

-- ---- a damaged value ----
for _, v in ipairs({"maybe", "2", "-1", "", "1.5", "yes please"}) do
  put("/home/we/ui.conf", "file_dialog=" .. v .. "\nbrightness=0.7\n")
  fresh_start()
  check(ui.state.file_dialog == false, "damaged file_dialog='" .. v .. "': off")
  check(logged_has("file_dialog"), "damaged file_dialog='" .. v .. "': a log line names it")
  check(ui.state.brightness == 0.7, "damaged file_dialog='" .. v .. "': the other settings are fine")
end
for _, v in ipairs({"on", "ON", "true", "1"}) do
  put("/home/we/ui.conf", "file_dialog=" .. v .. "\n")
  fresh_start()
  check(ui.state.file_dialog == true, "file_dialog='" .. v .. "' reads as on")
end
for _, v in ipairs({"off", "false", "0"}) do
  put("/home/we/ui.conf", "file_dialog=" .. v .. "\n")
  fresh_start()
  check(ui.state.file_dialog == false and not logged_has("file_dialog"), "file_dialog='" .. v .. "' reads as off, no log line")
end

-- ---- the result of the dialog reaches the script as before ----
put("/home/we/ui.conf", "file_dialog=1\n")
fresh_start()
local got
fs.enter("/home/we/dust/audio/", function(p) got = p end, "audio")
_norns.file_chosen("/home/we/dust/audio/mac/picked.wav") -- what the shell's import hands back after the dialog
check(got == "/home/we/dust/audio/mac/picked.wav", "a file chosen in the dialog is returned to the script (got " .. tostring(got) .. ")")
check(fs.active == false, "...and the browser is closed")
-- the same with the setting off: a file dropped on the window or chosen by some other route still works
ui.set_file_dialog(false)
got = nil
fs.enter("/home/we/dust/audio/", function(p) got = p end, "audio")
_norns.file_chosen("/home/we/dust/audio/other.wav")
check(got == "/home/we/dust/audio/other.wav", "off: a chosen or dropped file is still returned")

-- ---- cancelling ----
ui.set_file_dialog(true)
got = nil
local calls = 0
fs.enter("/home/we/dust/audio/", function(p) calls = calls + 1; got = p end, "audio")
-- the dialog is cancelled: the shell calls nothing at all (single_done with no path), so the script has heard nothing and the browser is up
check(calls == 0 and fs.active == true, "cancelled dialog: the script is not called, the browser is still up")
fs.enc(2, 1)
check(fs.active == true or calls == 1, "cancelled dialog: the browser still answers the encoder")
if fs.active then
  fs.key(2, 1) -- K2 leaves without a file (on the release)
  fs.key(2, 0)
  check(calls == 1 and got == "cancel", "K2 in the browser: the script gets 'cancel' (got " .. tostring(got) .. ")")
end

-- ---- macOS and the device: no ui_file_dialog, the chooser behaves as it always did ----
on_desktop = false
install_norns()
opened = {}
fs.getlist() -- (active is false now)
fs.active = true
fs.getlist()
check(#opened == 1, "without _norns.ui_file_dialog (macOS): the panel is requested as before (" .. #opened .. " calls)")
on_desktop = true
fs.active = false

os.execute("rm -rf '" .. tmp .. "'")
if fails > 0 then print("file_dialog_setting_test: " .. fails .. " failed") os.exit(1) end
print("file_dialog_setting_test: all passed")
