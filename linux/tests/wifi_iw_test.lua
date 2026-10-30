-- the network page on a computer without the `iw` tool ("sh: 1: iw: not found" in logs/norns.log): lua/core/wifi.lua does not run `iw` when it is missing, and the page (lua/core/menu/wifi.lua)
-- shows a short message instead of "SIGNAL: dBm" or an error. run from the repo root:  NORNS_PLATFORM=linux lua5.3 linux/tests/wifi_iw_test.lua
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL " .. what) end end
local lines = {}
screen = setmetatable({}, {__index = function() return function() end end})
screen.clear = function() lines = {} end
screen.text = function(s) lines[#lines + 1] = s end
screen.text_right = function(s) lines[#lines + 1] = s end
package.loaded.listselect = {}
package.loaded.textentry = {enter = function() end}
util = {clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end}
_menu = {redraw = function() end}
local page = dofile("lua/core/menu/wifi.lua")
local function shown(s) for _, l in ipairs(lines) do if tostring(l):find(s, 1, true) then return l end end end
local function conn(wireless) return {is_wireless = function() return wireless end} end
local function try(w)
  wifi = w
  local ok, err = pcall(page.redraw)
  return ok, err
end
local base = {status = "connected", connection_name = "home", ip = "192.168.1.5", conn_count = 1, state = 2}
local function with(t) local w = {} for k, v in pairs(base) do w[k] = v end for k, v in pairs(t) do w[k] = v end return w end

local ok, err = try(with({connection = conn(true), signal = nil, have_iw = false}))
check(ok, "no iw, no signal at all: the page does not raise an error (" .. tostring(err) .. ")")
check(shown("SIGNAL: n/a (iw missing)"), "no iw: the page says SIGNAL: n/a (iw missing)")
ok, err = try(with({connection = conn(true), signal = "", have_iw = false}))
check(ok and shown("SIGNAL: n/a (iw missing)"), "no iw, empty signal: the same message")
ok, err = try(with({connection = conn(true), signal = "", have_iw = true}))
check(ok and shown("SIGNAL: n/a") and not shown("iw missing"), "iw there but no reading: SIGNAL: n/a without the iw remark")
ok, err = try(with({connection = conn(true), signal = "-52", have_iw = true}))
check(ok and shown("SIGNAL: -52dBm"), "a reading is shown as before")
ok, err = try(with({connection = conn(false), signal = "", have_iw = false}))
check(ok and not shown("SIGNAL"), "a wired connection shows no signal line")

-- the capture is behind the same check in lua/core/wifi.lua, and on the device the original line is the one used
local src = io.open("lua/core/wifi.lua"):read("a")
check(src:find('command -v iw', 1, true) ~= nil, "wifi.lua looks for iw before running it on a computer")
check(src:find('NORNS_PLATFORM', 1, true) ~= nil, "the iw check is behind NORNS_PLATFORM")
check(src:find("wifi.signal = util.os_capture(\"iw dev \" .. name .. \" link | grep 'signal' | awk '{print $2}'\")", 1, true) ~= nil, "the device's original capture line is unchanged")
if fails == 0 then print("wifi_iw_test: all passed") end
os.exit(fails == 0 and 0 or 1)
