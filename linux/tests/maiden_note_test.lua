-- lua/core/maiden_note.lua: lua5.3 linux/tests/maiden_note_test.lua (from the repo root)
package.path = "lua/?.lua;lua/core/?.lua;" .. package.path
local M = require 'core/maiden_note'
local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL", what) end end
check(M.text(nil) == "maiden is not in this Windows build yet", "no reason: the old text")
check(M.text("") == "maiden is not in this Windows build yet", "empty reason: the old text")
check(M.text("maiden is not started: port 5000 is used by node.exe") == "maiden is not started: port 5000 is used by node.exe", "the launcher's line is shown")
if fails > 0 then print(fails .. " FAILED") os.exit(1) end
print("maiden_note_test: ok")
