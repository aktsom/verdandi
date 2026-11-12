-- the text of the note that the MAIDEN button shows on the Windows build when it does not open a page (docs/port/phase-m7.md section 8).
-- why: the launcher's VERDANDI_MAIDEN_WHY ("maiden is not started: port 5000 is used by node.exe"), or nothing/empty when maiden is simply not part of the build.
local M = {}
M.NOT_IN_BUILD = "maiden is not in this Windows build yet"
function M.text(why)
  if why ~= nil and why ~= "" then return why end
  return M.NOT_IN_BUILD
end
return M
