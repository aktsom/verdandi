-- lua/core/clipboard.lua: copy, the answer to a paste, and what counts as a colour (docs/port/colour-picker-plan.md). run from the repo root:  lua5.3 linux/tests/clipboard_test.lua
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL " .. what) end end

-- without the window's binding: nothing happens, and it says so
_norns = {}
local clip = require 'core/clipboard'
check(not clip.available() and clip.copy("#123456") == false, "no binding: copy says false")
local got
clip.request(function(status) got = status end)
check(got == "none", "no binding: a request is answered at once with none")
local hex, why = clip.as_colour("none", "")
check(hex == nil and why == "no clipboard", "no binding: the message")

-- with a binding: set goes to the window, a request is answered later through _norns.clipboard_text
package.loaded["core/clipboard"] = nil
local sent, asked = nil, 0
_norns = {clipboard_set = function(t) sent = t end, clipboard_request = function() asked = asked + 1 end}
clip = require 'core/clipboard'
check(clip.available() and clip.copy("#3B6EA8") == true and sent == "#3B6EA8", "copy hands the text to the window")
local result
clip.paste_colour(function(h, w) result = {h, w} end)
check(asked == 1 and result == nil, "a request is sent and nothing is answered yet")
_norns.clipboard_text("#3b6ea8", "ok")
check(result and result[1] == "3B6EA8", "the window's answer arrives through _norns.clipboard_text: " .. tostring(result and result[1]))
-- the answer is delivered once
result = nil
_norns.clipboard_text("#FFFFFF", "ok")
check(result == nil, "an answer nobody asked for is ignored")

local cases = {
  {"3B6EA8", "ok", "3B6EA8"}, {"#3B6EA8", "ok", "3B6EA8"}, {"3b6", "ok", "33BB66"}, {"#fa0", "ok", "FFAA00"}, {"  #3B6EA8\n", "ok", "3B6EA8"}, {"\t3B6EA8\r\n", "ok", "3B6EA8"},
  {"hello", "ok", nil, "not a colour: hello"}, {"#12", "ok", nil, "not a colour"}, {"#3B6EA8Z", "ok", nil, "not a colour"}, {"#1234567", "ok", nil, "not a colour"},
  {"", "empty", nil, "clipboard is empty"}, {"", "long", nil, "clipboard text too long"}, {"", "binary", nil, "clipboard is not text"},
  {string.rep("A", 100), "ok", nil, "clipboard is not a colour"}, {"\0\1\2", "ok", nil, "clipboard is not a colour"}, {"3B6E\0A8", "ok", nil, "clipboard is not a colour"},
  {"\27[31m#FF0000", "ok", nil, "clipboard is not a colour"},
}
for _, c in ipairs(cases) do
  local h, w = clip.as_colour(c[2], c[1])
  check(h == c[3], string.format("'%s' (%s) is %s, got %s", c[1]:gsub("[%c]", "?"), c[2], tostring(c[3]), tostring(h)))
  if c[4] then check(w ~= nil and w:find(c[4], 1, true), "its message: " .. tostring(w)) end
end
-- a long text in the message is cut
local _, msg = clip.as_colour("ok", "abcdefghijklmnopqrstuvwxyz")
check(msg and #msg < 30, "a long refused text is cut in the message: " .. tostring(msg))
if fails == 0 then print("clipboard_test: all passed") end
os.exit(fails == 0 and 0 or 1)
