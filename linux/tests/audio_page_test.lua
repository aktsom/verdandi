-- SYSTEM > AUDIO on Linux (lua/core/menu/audio.lua), per audio server mode. run from the repo root:
--   NORNS_AUDIO_SERVER_MODE=<pipewire|jack|jackd|""> lua5.3 linux/tests/audio_page_test.lua <mode>
-- the mode comes in as the argument too, run_all.sh runs one process per mode (os.getenv cannot be set from lua)
local mode = arg[1]
local tmp = os.tmpname()
os.remove(tmp)
os.execute("mkdir -p " .. tmp)

-- /home/we is the norns home: map it to a temporary folder
local real_open, real_remove = io.open, os.remove
local function map(p) return (p:gsub("^/home/we", tmp)) end
io.open = function(p, m) return real_open(map(p), m) end
os.remove = function(p) return real_remove(map(p)) end

local fails = 0
local function check(ok, what)
  if not ok then fails = fails + 1; print("FAIL", mode, what) end
end

-- the device list the tool prints (TSV: id, name, inputs, outputs)
local tool = tmp .. "/tool.tsv"
local f = real_open(tool, "w")
f:write("hw:CARD=Mic\tUSB Mic\t2\t0\n", "hw:CARD=Dac\tDragonFly\t0\t2\n", "hw:CARD=Both\tInterface\t8\t8\n")
f:close()

local pushed = {}
package.loaded.util = {
  clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end,
  file_exists = function(p) local h = real_open(map(p)); if h then h:close() return true end return false end,
  os_capture = function() return real_open(tool):read("a") end,
}
util = package.loaded.util
local env = {NORNS_AUDIO_SERVER_MODE = (mode ~= "" and mode) or nil, NORNS_AUDIO_TOOL = "tool", NORNS_AUDIO_RATE = "48000"}
local getenv = os.getenv
os.getenv = function(k) if env[k] ~= nil or k == "NORNS_AUDIO_SERVER_MODE" then return env[k] end return getenv(k) end

local texts = {}
screen = {
  clear = function() texts = {} end, level = function() end, move = function() end, update = function() end,
  text = function(s) table.insert(texts, s) end, text_right = function(s) table.insert(texts, s) end,
  text_extents = function(s) return #s * 5 end,
}
local restarted = false
local status = {"", "", ""}
_norns = {restart = function() restarted = true end, audio_status = function() return status[1], status[2], status[3] end}
_menu = {redraw = function() end, set_page = function(p) pushed[#pushed + 1] = p end}
local function shown(s) for _, t in ipairs(texts) do if t:find(s, 1, true) then return true end end return false end

norns = {none = function() end}
local page = dofile("lua/core/menu/audio.lua")
local function conf()
  local h = real_open(tmp .. "/audio.conf")
  if not h then return nil end
  local c = h:read("a"); h:close(); return c
end
local function go(row) for _ = 1, 10 do page.enc(2, -1) end for _ = 2, row do page.enc(2, 1) end end

-- an existing audio.conf with the card choice by prefix (decision 9): apply must not lose it
local h = real_open(tmp .. "/audio.conf", "w")
h:write("in_ports=USB Mic\nout_ports=Other DAC\nperiod=512\n")
h:close()

status = {"", "Built-in Audio Analog Stereo", "AudioQuest DragonFly"}
page.init()
page.redraw()

if mode == "pipewire" then
  check(shown("Built-in"), "pipewire: input row shows the connected card")
  check(shown("AudioQ"), "pipewire: output row shows the connected card")
  go(1); page.enc(3, 1); page.redraw()
  check(shown("Built-in"), "pipewire: input row is read-only")
  go(3); page.enc(3, 1); page.redraw()
  check(shown("48000"), "pipewire: rate row is read-only and shows the system rate")
  go(4); page.enc(3, -1); page.redraw()
  check(shown("exp"), "pipewire: buffer is marked experimental")
  check(shown("256") or shown("128"), "pipewire: buffer changes (512 -> a smaller step)")
  go(5); page.key(3, 1)
  local c = conf()
  check(c and c:find("in_ports=USB Mic", 1, true), "pipewire: apply keeps in_ports")
  check(c and c:find("out_ports=Other DAC", 1, true), "pipewire: apply keeps out_ports")
  check(c and c:find("period=256", 1, true), "pipewire: apply writes the period")
  check(c and not c:find("input=", 1, true), "pipewire: apply writes no device ids")
  check(restarted, "pipewire: apply restarts")
elseif mode == "jack" then
  go(4); page.enc(3, -1); page.redraw()
  check(not shown("exp"), "jack: no buffer row to change")
  go(5); page.key(3, 1)
  check(not restarted, "jack: a server we do not own cannot be restarted")
  check(conf():find("period=512", 1, true), "jack: audio.conf untouched")
elseif mode == "jackd" then
  go(1); page.enc(3, 1); page.redraw()
  check(shown("USB Mic"), "jackd: input row lists devices that capture")
  go(2); page.enc(3, 1); page.redraw()
  check(shown("DragonFly"), "jackd: output row lists devices that play")
  go(5); page.key(3, 1)
  local c = conf()
  check(c and c:find("input=hw:CARD=Mic", 1, true), "jackd: apply writes the input id")
  check(c and c:find("output=hw:CARD=Dac", 1, true), "jackd: apply writes the output id")
  check(c and c:find("in_ports=USB Mic", 1, true), "jackd: apply keeps in_ports")
  check(restarted, "jackd: apply restarts")
else -- no mode: the macOS page, unchanged
  go(1); page.enc(3, 1); page.redraw()
  check(shown("USB Mic"), "default mode: devices from the tool")
  go(5); page.key(3, 1)
  check(conf():find("input=hw:CARD=Mic", 1, true), "default mode: apply writes input=")
  check(restarted, "default mode: apply restarts")
end

-- a warning from crone is on the page in every mode
status = {"no sound card output ports found: audio output is not connected", "", ""}
page.init(); page.redraw()
check(shown("no sound card output"), "the warning is on the page")

os.execute("rm -rf " .. tmp)
print(fails == 0 and ("audio page (" .. mode .. "): all scenarios pass") or (fails .. " failures"))
os.exit(fails == 0)
