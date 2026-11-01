-- lua/core/serialosc_stop.lua: the stop command runs systemctl without asking for a password (a stub systemctl in PATH here); a refusal gives false; no systemctl gives false. run with the stub's folder first in PATH:
--   NORNS_PLATFORM=linux STUB_LOG=<file> PATH=<stub dir>:$PATH lua5.3 linux/tests/serialosc_stop_test.lua <yes|no>
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local mode = arg[1] or "yes"
local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL " .. what) end end
local S = require 'core/serialosc_stop'
check(S.COMMAND == "sudo systemctl stop serialosc.service", "the command to show")
local r = S.stop()
check(r == (mode == "yes"), "stop() returned " .. tostring(r) .. " for a stub that " .. (mode == "yes" and "succeeds" or "refuses"))
local f = io.open(os.getenv("STUB_LOG") or "/dev/null")
local logged = f and f:read("a") or ""
if f then f:close() end
check(logged:find("--no-ask-password", 1, true) and logged:find("stop", 1, true) and logged:find("serialosc.service", 1, true), "the stub was called with --no-ask-password stop serialosc.service (" .. logged:gsub("\n", " ") .. ")")
if fails == 0 then print("serialosc stop (" .. mode .. "): all passed") end
os.exit(fails == 0 and 0 or 1)
