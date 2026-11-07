-- driver of linux/tests/virmidi_pkexec_test.sh: one load with the real shell (the fake pkexec is first on the PATH), polled like the page's timer does.
-- prints  RESULT <status> <loaded|detail> [after-running]
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
util = dofile("lua/lib/util.lua"); package.loaded.util = util
local dir = assert(arg[1])
local V = require 'core/virmidi'
V.STATUS = dir .. "/status"
V.DONE = dir .. "/done"
V.SYS_MODULE = dir .. "/sys/snd_virmidi"
V.PROC_MODULES = dir .. "/proc_modules_none"
V.TIMEOUT = 2          -- seconds the load may take: the fake "slow" mode hangs for 30
V.PATIENCE = 6
V.is_root = function() return false end
local started = V.start_load()
if not started then
  print("RESULT " .. V.load_status() .. " " .. tostring(V.load_detail()))
  os.exit(0)
end
local first = V.load_status()
local saw_running = first == "running"
local status
for _ = 1, 100 do
  os.execute("sleep 0.1")
  status = V.load_status()
  if status ~= "running" then break end
  saw_running = true
end
local tail = status == "ok" and (V.loaded() and "loaded" or "not-loaded") or tostring(V.load_detail())
print("RESULT " .. status .. " " .. tail .. (saw_running and " after-running" or ""))
