-- Linux desktop: stop serialosc from the norns screen without a terminal (SYSTEM > DEVICES > SERIALOSC; docs/port/KNOWN-ISSUES.md 31). it asks systemd the way a user may when the system lets them (no password
-- prompt: --no-ask-password, bounded by timeout): on a system that wants sudo this fails, and the page shows the command to type instead. nothing else is touched, and it is never run without the page's question.
local M = {}

M.COMMAND = "sudo systemctl stop serialosc.service" -- what to type in a terminal

--- true if systemd stopped the unit
function M.stop()
  local ok = os.execute("timeout 20 systemctl --no-ask-password stop serialosc.service > /dev/null 2>&1")
  return ok == true or ok == 0
end

return M
