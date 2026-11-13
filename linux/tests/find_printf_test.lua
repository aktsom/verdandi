-- core/find_printf.lua: `find -printf '%p<c>'` as `-exec printf` (the Windows build's busybox has no -printf), the exact command line of the installer of twins, run against GNU find on a folder tree
-- (the same names found, the same output), and what is left alone. run from the repo root: lua5.3 linux/tests/find_printf_test.lua
package.path = "lua/?.lua;" .. package.path
local ffp = require 'core/find_printf'
local fails = 0
local function check(c, what) if not c then fails = fails + 1; print("FAIL " .. what) end end
local function sh(cmd) local f = io.popen(cmd); local o = f:read("a"); f:close(); return o end

-- a tree like the folders twins' installer searches
local root = os.tmpname(); os.remove(root)
os.execute("mkdir -p '" .. root .. "/Ext/PortedPlugins/Classes' '" .. root .. "/Ext/PortedPlugins/plugins' '" .. root .. "/dust/code/ignored dir/ignore' '" .. root .. "/dust/code/twins/.git'")
for _, f in ipairs({"Ext/PortedPlugins/Classes/AnalogChew.sc", "Ext/PortedPlugins/plugins/AnalogChew_scsynth.scx", "Ext/PortedPlugins/plugins/AnalogChew_scsynth.so",
  "dust/code/twins/.git/AnalogLoss.sc", "dust/code/ignored dir/ignore/AnalogDegrade.sc", "dust/code/twins/AnalogLoss.sc"}) do
  os.execute("touch '" .. root .. "/" .. f .. "'")
end
local function sorted(s) local t = {}; for e in s:gmatch("([^!]+)") do t[#t + 1] = e end; table.sort(t); return table.concat(t, "|") end

-- the command of the installer (Lua string.format makes %% into %), with the folders of the tree
local clauses = {}
for _, req in ipairs({"AnalogChew", "AnalogLoss"}) do
  for _, h in ipairs({req .. ".sc", req .. ".so", req .. "_scsynth.so"}) do clauses[#clauses + 1] = string.format("-name '%s'", h) end
end
local cmd = string.format("find %s %s -name .git -prune -o \\( %s \\) -not -path '*ignore*' -type f -printf '%%p!' 2>/dev/null",
  root .. "/Ext", root .. "/dust/code", table.concat(clauses, " -o "))
local new = ffp.rewrite(cmd)
check(new:find("-exec printf '%s!' {} \\;", 1, true), "the installer's -printf '%p!' becomes -exec printf '%s!' {} \\;")
check(not new:find("-printf", 1, true), "no -printf is left")
check(new:find("2>/dev/null", 1, true) and new:find("-not -path '*ignore*' -type f", 1, true), "the rest of the command is as it was")
local a, b = sorted(sh(cmd)), sorted(sh(new))
check(a == b and a ~= "", "GNU find gives the same files with both forms: " .. a)
check(not a:find(".git", 1, true) and not b:find("ignore", 1, true), ".git is pruned and *ignore* paths are left out in both")
-- other forms
check(ffp.rewrite("find . -type f -printf '%p\\n'") == "find . -type f -exec printf '%s\\n' {} \\;", "newline format")
check(ffp.rewrite('find . -printf "%p!"') == "find . -exec printf '%s!' {} \\;", "double quotes accepted")
check(ffp.rewrite("find . -printf '100%%%p'") == "find . -exec printf '100%%%s' {} \\;", "a literal %% stays a literal percent for printf")
check(ffp.rewrite("find . -printf '%p %p\\n'"):find("'%s %s\\n' {} {}", 1, true) ~= nil, "two %p take two {}")
-- left alone
for _, c in ipairs({"find . -printf '%f\\n'", "find . -printf '%h/%f'", "find . -printf '%T@ %p\\n'", "find . -printf 'a$HOME'", "echo hello", "ls -printf", "grep -printf x file", "find . -type f"}) do
  check(ffp.rewrite(c) == c, "left alone: " .. c)
end
check(ffp.rewrite(nil) == nil, "nil stays nil")
-- two finds in one line
local two = ffp.rewrite("find a -printf '%p!' ; find b -printf '%p,'")
check(two == "find a -exec printf '%s!' {} \\; ; find b -exec printf '%s,' {} \\;", "two finds in one command line")
os.execute("rm -rf '" .. root .. "'")
if fails > 0 then print(fails .. " failed"); os.exit(1) end
print("find_printf: all passed")
