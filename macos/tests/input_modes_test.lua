-- scenarios for the MIC button's input modes in lua/core/menu.lua (mic, system, app, off).
-- run from the repo root:
--   <lua 5.3> macos/tests/input_modes_test.lua
-- pulls the block out of lua/core/menu.lua and runs it with jack, the window and the file
-- that keeps "off" faked
local src = io.open("lua/core/menu.lua"):read("a")
local block = src:match("(%-%- MIC: what norns' input hears.-)\nhook%.system_post_startup")
assert(block, "input block not found")
local mic_off, kept = os.tmpname(), os.tmpname()
os.remove(mic_off)
os.remove(kept)
block = block:gsub('"/home/we/%.mic%-off"', string.format("%q", mic_off))
block = block:gsub('"/home/we/%.norns%-input"', string.format("%q", kept))

local fails = 0
local function check(cond, what)
  if not cond then
    fails = fails + 1
    print("FAIL " .. what)
  end
end

local function exists(p)
  local f = io.open(p)
  if f then f:close() end
  return f ~= nil
end

-- jack: the mac's input (system:capture_1/2) plugged into crone:input_1/2, as jack_lsp -c
-- lists it (each port, its connections indented below); execute() changes it
local links
local function jack_lsp()
  local out = {"system:capture_1", "system:capture_2"}
  for _, port in ipairs({"crone:input_1", "crone:input_2", "crone:input_3"}) do
    table.insert(out, port)
    for _, l in ipairs(links) do
      if l == port then table.insert(out, "   system:capture_" .. port:sub(-1)) end
    end
  end
  return table.concat(out, "\n") .. "\n"
end

local calls
local function setup(with_apps)
  links = {"crone:input_1", "crone:input_2"}
  calls = {exec = {}, app = {}, shown = {}}
  util = {
    os_capture = function(cmd) return cmd == "jack_lsp -c" and jack_lsp() or "" end,
    file_exists = exists,
  }
  _norns = {
    execute = function(cmd)
      table.insert(calls.exec, cmd)
      local op, _, dst = cmd:match("^(%S+) (%S+) (%S+)$")
      if op == "jack_disconnect" then
        for i, l in ipairs(links) do if l == dst then table.remove(links, i) break end end
      elseif op == "jack_connect" then
        table.insert(links, dst)
      end
    end,
    show_control = function(kind, n) if kind == 4 then table.insert(calls.shown, n) end end,
  }
  if with_apps then
    _norns.app_input = function(target, label) table.insert(calls.app, {target = target, label = label}) end
  end
  _menu = {}
  load(block)()
end

local function last_app() return calls.app[#calls.app] end
local function last_shown() return calls.shown[#calls.shown] end

-- the button: MIC > SYS > OFF > MIC
setup(true)
check(_menu.input == "mic" and _menu.mic_live, "starts on the mac's input")
_menu.next_input()
check(_menu.input == "system", "MIC > SYS")
check(last_app().target == "system" and last_app().label:match("system audio"), "every app tapped, and said so")
check(#links == 0, "the mac's input unplugged while the apps play in")
check(last_shown() == 2 and not _menu.mic_live, "the button says SYS")
check(exists(mic_off), "the next start begins off (no surprise tap, no feedback)")
_menu.next_input()
check(_menu.input == "off" and last_app().target == nil and last_app().label == "off", "SYS > OFF: no tap")
check(#links == 0 and last_shown() == 0, "off: nothing plugged in, unlit")
_menu.next_input()
check(_menu.input == "mic" and #links == 2, "OFF > MIC: the input plugged back in as it was")
check(last_app().target == nil and last_shown() == 1 and not exists(mic_off), "mic: no tap, lit, kept on")

-- the menu: one app
_norns.input_chosen("app", "com.google.Chrome", "Google Chrome")
check(_menu.input == "app" and last_app().target == "com.google.Chrome" and last_app().label == "Google Chrome",
  "an app from the menu is tapped, by its name on the device")
check(#links == 0 and last_shown() == 3, "app: the mac's input out, the button says APP")
_menu.next_input()
check(_menu.input == "off" and last_app().target == nil, "APP > OFF")
_norns.input_chosen("system", "", "")
check(_menu.input == "system" and last_app().target == "system", "menu: all apps")
-- the tap ends on its own (no permission, jack gone): off, quietly
_norns.input_ended()
check(_menu.input == "off" and last_app().target == nil and last_app().label == nil, "tap ended: off, no second note")
_norns.input_ended()
check(_menu.input == "off", "ended again: still off")
_norns.input_chosen("mic", "", "")
check(_menu.input == "mic" and #links == 2, "menu: back to the mac's input")
_norns.input_chosen("app", "", "")
check(_menu.input == "off", "an app without a bundle id: off")

-- the old switch still works
_menu.set_mic(false)
check(_menu.input == "off" and #links == 0, "set_mic(false)")
_menu.set_mic(true)
check(_menu.input == "mic" and #links == 2, "set_mic(true)")

-- the next start after SYS: SYS again, and said so
_menu.next_input()
check(_menu.input == "system" and exists(kept), "SYS is kept")
setup(true)
_menu.check_mic()
check(_menu.input == "system" and #links == 0 and last_app().target == "system" and last_app().label ~= nil,
  "starts with SYS, with a note (the apps go quiet)")
_menu.check_mic()
check(#calls.app == 1, "checked once")
-- after an app: that app
_norns.input_chosen("app", "com.google.Chrome", "Google Chrome")
setup(true)
_menu.check_mic()
check(_menu.input == "app" and last_app().target == "com.google.Chrome" and last_app().label == "Google Chrome",
  "starts with the app")
-- after OFF: off, quietly, nothing kept for an app
_menu.next_input()
check(_menu.input == "off" and not exists(kept), "OFF forgets the app")
setup(true)
check(exists(mic_off), "kept off")
_menu.check_mic()
check(_menu.input == "off" and #links == 0 and last_app().label == nil and last_shown() == 0, "starts off, no note")
-- after MIC: mic, nothing kept
_menu.next_input()
check(not exists(kept) and not exists(mic_off), "MIC keeps nothing")

-- no app tapping here: MIC > OFF > MIC
os.remove(mic_off)
setup(false)
_menu.next_input()
check(_menu.input == "off", "without app input MIC > OFF")
_menu.next_input()
check(_menu.input == "mic", "OFF > MIC")
_norns.input_chosen("system", "", "")
check(_menu.input == "off", "all apps without app input: off")

os.remove(mic_off)
os.remove(kept)
print(fails == 0 and "input modes: all scenarios pass" or (fails .. " failures"))
os.exit(fails == 0)
