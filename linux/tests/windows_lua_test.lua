-- the Lua side of the Windows build, with a stand-in for _norns.listdir (the native listing that only the Windows build has): no ls/find/grep/cp/rm/nmcli is needed.
--   lua5.3 linux/tests/windows_lua_test.lua   (from the repo root)
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL " .. what) end end

local root = os.tmpname()
os.remove(root)
root = "/tmp/wlt" .. root:match("(%w+)$") -- (not "lua_...": select.lua turns every ".lua" in a path into a "/")
os.execute("mkdir -p " .. root .. "/code/awake/lib " .. root .. "/code/awake/data " .. root .. "/code/.hidden " .. root .. "/code/zeta/docs " .. root .. "/code/x")
for _, f in ipairs({"code/awake/awake.lua", "code/awake/lib/helper.lua", "code/awake/data/d.lua", "code/zeta/z.lua", "code/zeta/docs/q.lua", "code/top.lua", "code/.hidden/h.lua", "code/zeta/notes.txt", "code/x/.dot.lua"}) do
  io.open(root .. "/" .. f, "w"):write("-- x"):close()
end

-- the same shape as the C function: folders first with a "/", then files, hidden names left out, nil when the folder is missing
local function listdir(dir)
  local p = io.popen('ls -p --group-directories-first "' .. dir .. '" 2>/dev/null')
  local t = {}
  for line in p:lines() do t[#t + 1] = line end
  if not p:close() then return nil end
  return t
end

_norns = {listdir = listdir, execute = function() error("a shell command was run") end}
util = require "util"
norns = {none = function() end}
local code = root .. "/code/"

-- scan: what find|grep|sort gave
local tree = util.script_tree(code, listdir)
check(tree == "awake/awake.lua\nzeta/z.lua", "script_tree: " .. tree:gsub("\n", " | "))
check(util.script_tree(root .. "/nothing/", listdir) == "", "script_tree of a missing folder is empty")
check(#util.scandir(root .. "/code/awake") == 3 and util.scandir(root .. "/code/awake")[1] == "data/", "scandir uses the listing")
check(util.ls_text(root .. "/code/zeta") == "docs/\nnotes.txt\nz.lua", "ls_text")
local from, to = root .. "/code/top.lua", root .. "/copy.lua"
check(util.copy_file(from, to) and util.read_text(to) == "-- x", "copy_file and read_text")
check(util.read_text(root .. "/none") == "", "read_text of a missing file")

-- SELECT: an empty list must not raise on K3 and must say so
paths = {code = code, favorites = root .. "/favorites"}
tab = {count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end}
local lines = {}
screen = setmetatable({}, {__index = function() return function() end end})
screen.clear = function() lines = {} end
screen.text_center = function(s) lines[#lines + 1] = s end
screen.text = function(s) lines[#lines + 1] = s end
_menu = {redraw = function() end, set_page = function() end}
package.loaded.tabutil = {load = function() return nil end, save = function() end}
local select = dofile("lua/core/menu/select.lua")
paths.code = root .. "/nothing/"
select.init()
check(select.len == 0, "empty scan: len 0")
for _, n in ipairs({1, 2, 3}) do
  check(pcall(select.key, n, 1), "key " .. n .. " on an empty list does not raise")
end
check(pcall(select.enc, 3, 1) and pcall(select.enc, 3, -1), "K3-turn on an empty list does not raise")
select.redraw()
local said = table.concat(lines, "|")
check(said:find("no scripts found", 1, true) and said:find("maiden", 1, true), "empty list says no scripts found / maiden: " .. said)
paths.code = code
select.init()
check(select.len == 2 and select.list[1].name == "awake" and select.list[2].name == "zeta/z", "scan shows the scripts: " .. tostring(select.len) .. " " .. tostring(select.list[1] and select.list[1].name) .. " " .. tostring(select.list[2] and select.list[2].name))
check(pcall(select.key, 3, 1), "key 3 on a list")

-- network: no nmcli on Windows
local wifi = dofile("lua/core/wifi.lua")
check(wifi.update() == nil and wifi.state == 0 and wifi.conn_count == 0, "wifi.update gives an empty state")
check(#wifi.connections() == 0 and #wifi.ssids() == 0 and wifi.active_connection() == nil, "wifi queries are empty")
check(wifi.radio_state() == "disabled", "wifi radio state")

os.execute("rm -rf " .. root .. " " .. root .. "x")
if fails == 0 then print("windows_lua_test: all passed") end
os.exit(fails == 0 and 0 or 1)
