-- string.format("%d", x) needs a whole number in Lua 5.3: the menu code that formats numbers that can be fractions must not raise (KNOWN-ISSUES 26), and an error in a menu key or encoder handler must be
-- logged and shown on the screen instead of doing nothing (lua/core/menu.lua, the block between "BEGIN handler guard" and "END handler guard", cut out and run here). run from the repo root:
--   NORNS_PLATFORM=linux lua5.3 linux/tests/menu_format_test.lua
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL " .. what) end end
local function eq(a, b, what) check(a == b, what .. ": got " .. tostring(a) .. ", wanted " .. tostring(b)) end
norns = {none = function() end}
-- ---- the clean-up page's sizes: a float number of bytes, a size that is not whole after the division
local c = dofile("lua/core/menu/cleanup.lua")
check(c.human ~= nil, "cleanup exposes human() for the test")
if c.human then
  for _, b in ipairs({0, 5, 5.5, 1023, 1023.9, 1024, 1536, 10.7 * 1024, 15.3 * 1024 * 1024, 1e9, 2.5e12, "12.5", "abc", 99.99}) do
    local ok, r = pcall(c.human, b)
    check(ok, "human(" .. tostring(b) .. ") does not raise: " .. tostring(r))
    check(ok and type(r) == "string" and r:match("^%d+%.?%d*[BKMG]$") ~= nil, "human(" .. tostring(b) .. ") is a size: " .. tostring(r))
  end
  eq(c.human(1536), "1.5K", "1536 bytes"); eq(c.human(15.3 * 1024 * 1024), "15M", "15.3 MB"); eq(c.human(5.5), "5B", "5.5 bytes")
end
-- ---- the handler guard of menu.lua
local src = io.open("lua/core/menu.lua"):read("a")
local block = src:match("%-%- BEGIN handler guard\n(.-)\n%-%- END handler guard")
check(block ~= nil, "lua/core/menu.lua has the handler guard block")
local function world(desktop)
  local w = {notes = {}, prints = {}, redraws = 0, shown = 0}
  _menu = {mode = true, redraw = function() w.redraws = w.redraws + 1 end, show_note = function() w.shown = w.shown + 1; w.note = _menu.error_note end}
  util = {time = function() return w.t or 100 end}
  local real_print = print
  print = function(...) w.prints[#w.prints + 1] = table.concat({...}, " ") end
  local env = os.getenv
  os.getenv = function(k) if k == "NORNS_PLATFORM" then return desktop and "linux" or nil end return env(k) end
  local f = assert(load(block .. "\nreturn call_handler", "guard", "t", setmetatable({}, {__index = _G})))
  local env_g = _G
  local call = f()
  os.getenv = env
  w.restore = function() print = real_print end
  return w, call
end
do
  local w, call = world(true)
  local got
  local r = call("key", function(a, b) got = a .. b end, "x", "y")
  eq(got, "xy", "a handler that works is called with its arguments"); check(w.shown == 0 and _menu.error_note == nil, "and nothing is shown")
  local ok, err = pcall(call, "key", function() error("tape.lua:234: bad argument #2 to 'format' (number has no integer representation)") end)
  check(ok, "an error in a handler does not escape (desktop)")
  check(_menu.error_note ~= nil and _menu.error_note:find("ERROR", 1, true) and #_menu.error_note <= 80, "a short message is set for the screen: " .. tostring(_menu.error_note))
  check(_menu.error_note:find("bad argument", 1, true) or _menu.error_note:find("integer", 1, true), "it says what went wrong")
  check(w.shown >= 1 and w.note == _menu.error_note, "and the screen note is refreshed")
  check((_menu.error_note_until or 0) > 100, "with a time to go")
  local logged = false
  for _, l in ipairs(w.prints) do if l:find("menu key handler error", 1, true) and l:find("bad argument", 1, true) then logged = true end end
  check(logged, "and it is logged with the handler's name and the error")
  check(w.redraws >= 1, "the page is redrawn after an error (it stays whole)")
  -- a second error replaces the first, a good call later does not clear it early
  call("enc", function() error("short") end)
  check(_menu.error_note:find("enc", 1, true) or _menu.error_note:find("short", 1, true), "the newest error is the one shown: " .. tostring(_menu.error_note))
  -- an error object that is not a string, and a very long message
  call("key", function() error({}) end)
  check(type(_menu.error_note) == "string", "a non-string error still gives a message")
  call("key", function() error(string.rep("x", 500)) end)
  check(#_menu.error_note <= 80, "a long message is cut")
  -- values come back
  local a, b = call("key", function() return 1, 2 end)
  check(a == 1 and b == 2, "results are returned")
  w.restore()
end
do
  local w, call = world(false)
  local ok = pcall(call, "key", function() error("device") end)
  check(not ok, "on the device the error is left alone (upstream behaviour)")
  check(_menu.error_note == nil, "and no note is set")
  w.restore()
end
if fails == 0 then print("menu format: all passed") end
os.exit(fails == 0 and 0 or 1)
