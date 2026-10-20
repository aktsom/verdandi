-- scenarios for the Finder's open panel next to norns' file browser (lua/lib/fileselect.lua
-- on macOS). run from the repo root:
--   <lua 5.3> macos/tests/fileselect_finder_test.lua
-- the window side (_norns.choose_file ...) and the screen are faked
local fails = 0
local function check(cond, what)
  if not cond then
    fails = fails + 1
    print("FAIL " .. what)
  end
end

local opened, closed = {}, 0
_norns = {
  choose_file = function(dir) table.insert(opened, dir) end,
  choose_file_close = function() closed = closed + 1 end,
}
util = {
  scandir = function() return {"kick.wav", "loops/"} end,
  file_exists = function() return true end,
  s_to_hms = function() return "0:01" end,
  trim_string_to_width = function(s) return s end,
}
norns = {menu = {status = function() return false end, init = function() end}, none = function() end}
screen = setmetatable({}, {__index = function() return function() end end})
clock = {cancel = function() end, run = function() end}
softcut = setmetatable({}, {__index = function() return function() end end})
audio = {file_info = function() return 2, 48000, 48000 end}
key, enc, redraw, refresh = function() end, function() end, function() end, function() end
local script_key = key

local fs = dofile("lua/lib/fileselect.lua")
local got
local function cb(path) got = path end

-- the panel comes up with the browser, in its folder, and follows it
fs.enter("/home/we/dust", cb)
check(opened[#opened] == "/home/we/dust/", "the panel opens in the browser's folder")
fs.pushd("/home/we/dust/audio/loops/")
check(opened[#opened] == "/home/we/dust/audio/loops/", "and goes where the browser goes")

-- chosen in the Finder: the script gets it, the browser is gone
_norns.file_chosen("/home/we/dust/audio/mac/kick.wav")
check(got == "/home/we/dust/audio/mac/kick.wav", "the Finder's choice goes to the script")
check(key == script_key, "the script has its keys back")
check(closed >= 1, "the panel is told to go")
got = nil
_norns.file_chosen("/home/we/dust/audio/mac/late.wav")
check(got == nil, "a choice after the browser closed goes nowhere")

-- dropped on the window while the browser is up: a file is taken, a folder is not
fs.enter("/home/we/dust/audio/", cb)
_norns.file_dropped("/home/we/dust/audio/mac/pack")
check(got == nil and fs.active, "a dropped folder of samples is only added to dust")
_norns.file_dropped("/home/we/dust/audio/mac/loop 2.wav")
check(got == "/home/we/dust/audio/mac/loop 2.wav", "a dropped file is the choice")

-- chosen in norns' own browser: the panel goes away too
got = nil
local before = closed
fs.enter("/home/we/dust/audio/", cb)
fs.key(3, 1)
fs.key(3, 0)
check(got == "/home/we/dust/audio/kick.wav", "norns' browser still chooses (got " .. tostring(got) .. ")")
check(closed == before + 1, "and the panel goes away")

-- cancelled in norns' browser
got = nil
fs.enter("/home/we/dust/audio/", cb)
fs.key(2, 1)
fs.key(2, 0)
check(got == "cancel" and not fs.active, "K2 still cancels")

print(fails == 0 and "fileselect finder: all scenarios pass" or (fails .. " failures"))
os.exit(fails == 0)
