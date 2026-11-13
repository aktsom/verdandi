-- lua/core/sc_class_check.lua: the startup check of sclang.log (a class that is missing, a class defined twice), on real logs
-- (linux/tests/fixtures/sclang-*.log). run from the repo root:  NORNS_PLATFORM=linux lua5.3 linux/tests/sc_class_check_test.lua
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL " .. what) else print("ok   " .. what) end end
local function slurp(p) local f = assert(io.open(p)); local s = f:read("a"); f:close(); return s end
local okc, C = pcall(dofile, "lua/core/sc_class_check.lua")
if not okc then print("FAIL lua/core/sc_class_check.lua does not load: " .. tostring(C)); os.exit(1) end

local home = "/home/we"
local ctx = {home = home}

-- missing class
local missing = slurp("linux/tests/fixtures/sclang-missing-class.log")
local r = C.report(missing, ctx)
check(#r == 1, "the missing-class log gives one finding (the repeated warnings are one), got " .. #r)
check(r[1] and r[1].kind == "missing" and r[1].class == "MiPlaits", "...it is the missing class MiPlaits")
local line = r[1] and r[1].line or ""
check(line:find("MiPlaits", 1, true) ~= nil, "the line names the class")
check(line:find(home .. "/.local/share/SuperCollider/Extensions", 1, true) ~= nil, "the line names the folder where it should be")
check(line:find("mi-UGens", 1, true) ~= nil, "the line names the pack the class comes from")
check(line:find("Emplaitress", 1, true) ~= nil, "the line says which engine was building when it failed (from the trace)")
check(line:find("\n") == nil and #line < 600, "one line, short enough to read")
check(line:find("likely", 1, true) ~= nil, "the line gives the likely cause")
-- the pack is there but moved to disabled/: cause differs
local r2 = C.report(missing, {home = home, pack = "none"})
check(r2[1] and r2[1].line:find("not in", 1, true) ~= nil, "pack state none: says the pack is not in the folder")
local r3 = C.report(missing, {home = home, pack = "own"})
check(r3[1] and r3[1].line:find("is in", 1, true) ~= nil, "pack state own: says it is there, so the class file is damaged or SuperCollider was not restarted")
-- a class that is not a Mi class: generic cause
local r4 = C.report("Execution warning: Class 'FooBar' not found\n", ctx)
check(r4[1] and r4[1].class == "FooBar" and r4[1].line:find("mi-UGens", 1, true) == nil, "a class that is not from mi-UGens: generic line, no mi-UGens advice")

-- duplicate class
local dup = slurp("linux/tests/fixtures/sclang-duplicate-class.log")
local d = C.report(dup, ctx)
check(#d == 1, "the duplicate log gives one finding per pair of folders, got " .. #d)
local x = d[1] or {}
check(x.kind == "duplicate", "...a duplicate")
check(x.classes and #x.classes >= 5 and x.classes[1] == "MiBeads", "...with its classes in log order (" .. tostring(x.classes and #x.classes) .. ")")
check(x.line and x.line:find(home .. "/.local/share/SuperCollider/Extensions/mi-UGens", 1, true) and x.line:find(home .. "/dust/code/mi-copy", 1, true), "the line names both folders")
check(x.line and x.line:find("MiBeads", 1, true) ~= nil, "the line names a class")
check(x.line and x.line:find("likely", 1, true) ~= nil and x.line:find("same pack twice", 1, true) ~= nil, "the line gives the likely cause")
check(x.fix and x.fix.target == home .. "/dust/code/mi-copy", "the folder to move aside is the one that is not Verdandi's own")
check(x.line and x.line:find("verdandi tidy disable '" .. home .. "/dust/code/mi-copy'", 1, true) ~= nil, "the line has the one command")
local d2 = C.report(dup, {home = "/elsewhere"})
check(d2[1] and d2[1].fix == nil, "folders outside the norns home get no move offer (never delete, move by hand)")

-- clean log, and an empty one
check(#C.report(slurp("linux/tests/fixtures/sclang-ok.log"), ctx) == 0, "a clean start gives nothing")
check(#C.report("", ctx) == 0, "an empty log gives nothing")
-- the same error twice in a log (two runs appended) is one finding
check(#C.report(missing .. missing, ctx) == 1, "the same finding twice is one")

-- the note
check(C.note(r) ~= nil and C.note(r):find("SUPERCOLLIDER", 1, true) ~= nil and C.note(r):find("CLEAN UP", 1, true) ~= nil, "the window note names SYSTEM > CLEAN UP")
check(C.note({}) == nil, "no findings: no note")

-- reading a file: bounded, and the note clears when the log is clean
local tmp = os.tmpname()
local f = io.open(tmp, "w"); f:write(string.rep("x", 3 * 1024 * 1024), "\n", missing); f:close()
local t0 = os.clock()
local s = C.scan(tmp, ctx)
check(#s == 1 and s[1].class == "MiPlaits", "scan finds the error at the end of a 3 MB log")
check(os.clock() - t0 < 1.0, "...in well under a second")
local f2 = io.open(tmp, "w"); f2:write(missing, string.rep("y", 3 * 1024 * 1024)); f2:close()
check(#C.scan(tmp, ctx) == 0, "an error that is further back than the bounded tail is not read (bounded)")
local f3 = io.open(tmp, "w"); f3:write(slurp("linux/tests/fixtures/sclang-ok.log")); f3:close()
check(#C.scan(tmp, ctx) == 0 and C.note(C.scan(tmp, ctx)) == nil, "a log of a clean start: nothing and no note")
os.remove(tmp)
check(#C.scan("/nonexistent/sclang.log", ctx) == 0, "no log file: nothing")
-- read only
local before = io.popen("ls -la linux/tests/fixtures | md5sum"):read("a")
C.scan("linux/tests/fixtures/sclang-duplicate-class.log", ctx)
check(io.popen("ls -la linux/tests/fixtures | md5sum"):read("a") == before, "scanning changes nothing")
-- Windows (M7): the extension folder is <home>/extensions, the unquoted form "Class Decimator not found" is read, and ONE line names all missing classes
local wf = C.report("Class Decimator not found\nClass 'SmoothDecimator' not found\nClass 'MiPlaits' not found\nClass Decimator not found\n", {home = "C:/Users/x/Verdandi", ext = "C:/Users/x/Verdandi/extensions"})
check(#wf == 3 and wf[1].class == "Decimator" and wf[1].line:find("C:/Users/x/Verdandi/extensions", 1, true), "windows: unquoted class form, extensions folder from ctx")
local one = C.summary(wf)
check(one and not one:find("\n", 1, true) and one:find("Decimator (sc3-plugins", 1, true) and one:find("MiPlaits (mi-UGens)", 1, true), "windows: one plain line: " .. tostring(one))
check(C.summary({}) == nil, "no findings: no line")
-- M7 round 4: a failed compile is explained (real sclang output)
local cd = C.compile_failure(slurp("linux/tests/fixtures/sclang-compile-failed-duplicate.log"))
check(cd and cd.kind == "duplicate" and cd.classes[1] == "MiDupTest" and cd.first == "/tmp/dup/a/MiDupTest.sc" and cd.second == "/tmp/dup/b/MiDupTest.sc", "compile failure: duplicate class, the first two paths")
check(cd and cd.line:find("two files define the same class", 1, true) and cd.line:find("restart norns", 1, true), "...the line says what and what to do")
local fits = cd ~= nil
for _, l in ipairs(cd and cd.detail or {}) do if #l > 21 then fits = false end end
check(fits and #cd.detail <= 5, "...the screen lines fit (21 characters, at most 5 lines)")
local cs = C.compile_failure(slurp("linux/tests/fixtures/sclang-compile-failed-syntax.log"))
check(cs and cs.kind == "error" and cs.file == "/tmp/syn/B.sc" and cs.line:find("Parse error", 1, true), "compile failure: a syntax error names its file")
local sf = true
for _, l in ipairs(cs and cs.detail or {}) do if #l > 21 then sf = false end end
check(sf, "...screen lines fit")
check(C.compile_failure(slurp("linux/tests/fixtures/sclang-ok.log")) == nil and C.compile_failure(nil) == nil, "a clean start: no explanation")
check(C.tail("/nonexistent/x.log") == "", "tail of a missing file is empty")
os.exit(fails == 0 and 0 or 1)
