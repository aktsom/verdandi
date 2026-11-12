-- Windows: the user's folder can have a blank in its name (C:\Users\Jane Smith\Verdandi). a script's shell command names /home/we/..., which is replaced by the real folder: unquoted, the blank cut the path in two and
-- "cp /home/we/a /home/we/b" copied the wrong things (found by the CI: its home folder is called "user home input"). now the replacement is quoted by the shell's rules: escaped outside quotes, as it is inside them.
-- run with HOME set to a folder with a blank in its name:   mkdir -p "/tmp/q q" && env HOME="/tmp/q q" lua5.3 linux/tests/windows_cmd_quote_test.lua
local home = os.getenv("HOME")
assert(home and home:find(" ", 1, true) and home ~= "/home/we", "run with HOME set to a folder with a blank")
local fails = 0
local function check(c, w) if not c then fails = fails + 1; print("FAIL " .. w) end end
package.config = "\\\n;\n?\n!\n-\n" -- "Windows" (the rule is Windows only)
_norns = {}
dofile("lua/core/virtual_home.lua")
os.execute("mkdir -p '" .. home .. "/dust'")
local function read(p) local f = io.open(p); if not f then return nil end local t = f:read("a"); f:close(); return t end
-- unquoted
check(os.execute("echo one > /home/we/dust/t1 && cp /home/we/dust/t1 /home/we/dust/t2"), "an unquoted command with /home/we works")
check(read("/home/we/dust/t2") == "one\n", "and the copy is where it should be: " .. tostring(read("/home/we/dust/t2")))
-- inside double and single quotes (already quoted by the script)
check(os.execute('cp "/home/we/dust/t1" "/home/we/dust/t3"') and read("/home/we/dust/t3") == "one\n", "inside double quotes")
check(os.execute("cp '/home/we/dust/t1' '/home/we/dust/t4'") and read("/home/we/dust/t4") == "one\n", "inside single quotes")
-- a name of the script with a blank, quoted by the script
check(os.execute('mkdir -p "/home/we/dust/my script" && echo x > "/home/we/dust/my script/f"') and read("/home/we/dust/my script/f") == "x\n", "a script folder with a blank, quoted")
-- popen, and the output comes back with the virtual path
local p = io.popen("ls /home/we/dust/t1")
local out = p:read("a"); p:close()
check(out == "/home/we/dust/t1\n", "popen: the path comes back virtual: " .. out)
-- something that is not the home is not touched
check(os.execute("test \"/homestead\" = \"/homestead\" && test -d /tmp"), "other paths are left alone")
-- the mapping of file names is as before
check(read("/home/we/dust/t1") == "one\n", "files go through the plain mapping")
print(fails == 0 and "windows cmd quote: all scenarios pass" or (fails .. " failures"))
os.exit(fails == 0)
