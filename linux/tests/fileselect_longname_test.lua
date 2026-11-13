-- lua/lib/fileselect.lua: a long file name is shown cut with "..", but the preview (E3) and the selection (K3) must use the REAL name; files the filter hides must not shift the rows.
-- (before: the preview opened "very long na..." and the Tape Reader said "cannot open sndfile"). run from the repo root: lua5.3 linux/tests/fileselect_longname_test.lua
package.path = "lua/?.lua;lua/lib/?.lua;" .. package.path
local fails = 0
local function check(c, what) if not c then fails = fails + 1; print("FAIL " .. what) end end
local LONG = "a very long file name for a sample that sits under an external folder, take 12 (final mix).wav"
local files = {"notes.txt", LONG, "short.wav", "readme.md"}
screen = setmetatable({}, {__index = function() return function() end end})
screen.text_extents = function(s) return #s * 5 end
local opened = {}
audio = {file_info = function(p) if p:match("%.wav$") then return 2, 480000, 48000 end return 0, 0, 0 end,
  tape_play_open = function(p) opened[#opened + 1] = p end, tape_play_start = function() end, tape_play_stop = function() end}
util = {scandir = function() local t = {} for i, f in ipairs(files) do t[i] = f end return t end,
  trim_string_to_width = function(s, w) if #s * 5 > w then return s:sub(1, math.floor(w / 5) - 3) .. "..." end return s end,
  s_to_hms = function(s) return tostring(s) end, clamp = function(x, a, b) return math.max(a, math.min(b, x)) end, time = os.time}
clock = {run = function(f) local co = coroutine.wrap(f) co() end, sleep = function() end, cancel = function() end}
norns = {menu = {set = function() end, init = function() end, status = function() return false end}}
_norns = {}
metro = setmetatable({}, {__index = function() return {} end})
local fs = dofile("lua/lib/fileselect.lua")
local got
fs.enter("/home/we/dust/audio/[ext] Pack/", function(p) got = p end, "audio")
-- the filter hides the .txt and .md files: two rows
check(#fs.display_list == 2, "the filter leaves two rows (" .. #fs.display_list .. ")")
check(fs.display_list[1]:sub(-3) == "...", "the long name is cut with .. in the row: " .. tostring(fs.display_list[1]))
-- E3 right on the first row: the preview opens the real file
fs.enc(3, 1)
local last = opened[#opened]
check(last == nil or last == "/home/we/dust/audio/[ext] Pack/" .. LONG, "the preview opened the real name, not the cut text: " .. tostring(last))
-- K3 on the first row: the chosen path is the real one
fs.key(3, 1)
check(fs.path == "/home/we/dust/audio/[ext] Pack/" .. LONG, "the chosen path is the real name: " .. tostring(fs.path))
-- the second row is short.wav (the hidden notes.txt does not shift it)
fs.done = false; fs.path = nil
fs.pos = 1
fs.key(3, 1)
check(fs.path == "/home/we/dust/audio/[ext] Pack/short.wav", "the second row is short.wav, not a hidden file: " .. tostring(fs.path))
if fails > 0 then print(fails .. " failed"); os.exit(1) end
print("fileselect long names: all passed")
