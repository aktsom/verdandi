-- scenarios for keyboard.lua hardware keys (NORNS_HARDWARE_KEYS).
-- run from the repo root:
--   NORNS_HARDWARE_KEYS=1 <lua 5.3> macos/tests/keyboard_hardware_test.lua

package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path

-- stubs for what keyboard.lua touches at runtime
screen = {ping = function() end}
_path = {keyboard_layout = "/nonexistent/keyboard.layout"}
_menu = {mode = false, keycode = function() end, keychar = function() end, set_mode = function() end}
local log = {}
_norns = {
  key = function(n, z) table.insert(log, "K" .. n .. "=" .. z) end,
  enc = function(n, d) table.insert(log, "E" .. n .. (d > 0 and "+" or "") .. d) end,
}

require 'core/keyboard'
local te = require 'lib/textentry_kbd'

local failures = 0
local function code(name)
  for k, v in pairs(keyboard.codes) do if v == name then return k end end
  error("no code " .. name)
end
local function send(name, value) keyboard.process(1, code(name), value) end
local function check(what, want)
  local got = table.concat(log, " ")
  if got ~= want then
    failures = failures + 1
    print("FAIL " .. what .. ": got '" .. got .. "', want '" .. want .. "'")
  end
  log = {}
end

assert(keyboard.hardware_keys, "run with NORNS_HARDWARE_KEYS=1")
keyboard.clear()

-- script without keyboard handlers: keys and encoders
send('2', 1); send('2', 2); send('2', 0)
check("K2 press, repeat ignored, release", "K2=1 K2=0")
send('W', 1); send('W', 2); send('W', 0)
check("E1 right, autorepeat turns again", "E1+1 E1+1")
send('A', 1); send('A', 0)
check("E2 left", "E2-1")
send('DOWN', 1); send('DOWN', 0); send('LEFT', 1); send('LEFT', 0)
check("arrows in a script", "E2+1 E3-1")
send('LEFTSHIFT', 1); send('X', 1); send('X', 0); send('LEFTSHIFT', 0)
check("shift = 5 steps", "E3+5")

-- enter and space confirm (K3)
send('ENTER', 1); send('ENTER', 0); send('SPACE', 1); send('SPACE', 0); send('KPENTER', 1); send('KPENTER', 0)
check("enter / space / keypad enter = K3", "K3=1 K3=0 K3=1 K3=0 K3=1 K3=0")
send('ESC', 1); send('ESC', 0); send('BACKSPACE', 1); send('BACKSPACE', 0)
check("esc / backspace = K2", "K2=1 K2=0 K2=1 K2=0")

-- K1 held while turning, release after other keys
send('1', 1); send('S', 1); send('S', 0); send('1', 0)
check("K1 + E2", "K1=1 E2+1 K1=0")

-- script with a keyboard handler gets the keys
local typed = {}
keyboard.code = function(c, v) table.insert(typed, c .. "=" .. v) end
send('2', 1); send('2', 0); send('Q', 1); send('Q', 0)
check("script with keyboard.code: no hardware", "")
assert(table.concat(typed, " ") == "2=1 2=0 Q=1 Q=0", "script did not get the keys: " .. table.concat(typed, " "))

-- a key pressed as hardware releases as hardware even if the script grabbed the keyboard
keyboard.clear()
send('3', 1)
keyboard.code = function() error("release leaked to the script") end
send('3', 0)
check("release follows press", "K3=1 K3=0")
keyboard.clear()

-- menu: digits and letters are hardware, arrows keep the menu bindings
local menu_codes = {}
_menu.mode = true
_menu.keycode = function(c, v) table.insert(menu_codes, c .. "=" .. v) end
send('3', 1); send('3', 0); send('LEFT', 1); send('LEFT', 0)
check("menu: K3 hardware, arrow to menu", "K3=1 K3=0")
assert(table.concat(menu_codes, " ") == "LEFT=1 LEFT=0", "menu did not get the arrow: " .. table.concat(menu_codes, " "))
-- the menu ignores a script's keyboard handler
keyboard.code = function() end
send('Q', 1); send('Q', 0)
check("menu overrides script handler", "E1-1")
keyboard.clear()
_menu.mode = false

-- text entry types
te.code = function() end
send('Q', 1); send('Q', 0)
check("text entry: no hardware", "")
te.code = nil

-- other keys still reach the script
local got
keyboard.code = function(c, v) got = c end
send('P', 1)
check("unmapped key", "")
assert(got == 'P', "P not passed on")
keyboard.clear()

-- off without the env var
keyboard.hardware_keys = false
send('2', 1); send('2', 0)
check("disabled", "")

if failures == 0 then print("keyboard hardware keys: all scenarios pass") end
os.exit(failures == 0 and 0 or 1)
