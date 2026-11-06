-- lua/core/mi_ugens.lua: what the shipped mi-UGens pack is, from its stamp (written by linux/mi-ugens-seed.sh), for SYSTEM > CLEAN UP and the manual.
-- run from the repo root:  NORNS_PLATFORM=linux lua5.3 linux/tests/mi_info_test.lua
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL " .. what) else print("ok   " .. what) end end
local okc, M = pcall(dofile, "lua/core/mi_ugens.lua")
if not okc then print("FAIL lua/core/mi_ugens.lua does not load: " .. tostring(M)); os.exit(1) end
local tmp = os.tmpname(); os.remove(tmp); os.execute("mkdir -p '" .. tmp .. "/.local/share/SuperCollider/Extensions'")
local dir = tmp .. "/.local/share/SuperCollider/Extensions/mi-UGens"
local function put(p, t) local f = assert(io.open(p, "w")); f:write(t); f:close() end

local i = M.info(tmp)
check(i.state == "none" and M.line(i) == nil, "no pack in the extension folder: state none, no line")
os.execute("mkdir -p '" .. dir .. "'")
i = M.info(tmp)
check(i.state == "foreign" and M.line(i):find("not from Verdandi", 1, true) ~= nil, "a folder without our stamp: foreign")
put(dir .. "/.verdandi-stamp", "pack=mi-UGens\nserial=3\ncommit=10f6824f68ad63475f67dfe3fe5016e2d2634f84\nbuilt=2026-11-06\nverdandi=0.1~git20261106.5.abcdef0\n")
i = M.info(tmp)
check(i.state == "own" and i.serial == 3 and i.commit == "10f6824f68ad63475f67dfe3fe5016e2d2634f84" and i.built == "2026-11-06", "a stamped folder: own, serial, commit, build date")
check(M.line(i) == "mi-UGens: 10f6824, shipped with Verdandi 0.1~git20261106.5.abcdef0", "the line is: mi-UGens: <commit>, shipped with Verdandi <version>, got " .. tostring(M.line(i)))
check(M.detail(i):find("2026%-11%-06") ~= nil and M.detail(i):find("v7b1/mi%-UGens") ~= nil, "the detail has the build date and where the source is")
put(dir .. "/.verdandi-stamp", "garbage\n")
i = M.info(tmp)
check(i.state == "foreign", "a stamp without our keys: foreign (not ours)")
os.execute("rm -rf '" .. tmp .. "'")
os.exit(fails == 0 and 0 or 1)
