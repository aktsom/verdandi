-- lua/core/box_settings.lua (docs/port/box-style-plan.md 2.6 to 2.9, tests 4 to 6): the look of the box on the Linux desktop. run from the repo root:
--   lua5.3 linux/tests/box_settings_test.lua
-- hex validation (3 or 6 digits, a bad one rejected with a message and the colour kept, black allowed, low contrast said), box.conf (defaults, round trip, unknown keys kept and logged, a damaged
-- value falls back with a log line, a look that is gone becomes CUSTOM), the four built-in looks and the PRESET order, the colours working for both styles (a single colour never changes the style, a
-- look sets style and colours), one look = one small file in box-presets/ (save, load, overwrite only after the confirmation, delete, built-in protected, damaged and foreign files ignored with a
-- log line, name validation: no path characters, a length limit), applied at once (_norns.box_look), nothing happens without _norns.box_look (macOS, the device)
package.path = "lua/?.lua;lua/core/?.lua;lua/lib/?.lua;" .. package.path
local tmp = os.tmpname()
os.remove(tmp)
os.execute("mkdir -p " .. tmp)
local real_open, real_remove, real_rename = io.open, os.remove, os.rename
local function map(p) return (p:gsub("^/home/we", tmp)) end
io.open = function(p, m) return real_open(map(p), m) end
os.remove = function(p) return real_remove(map(p)) end
os.rename = function(a, b) return real_rename(map(a), map(b)) end

local fails = 0
local function check(ok, what) if not ok then fails = fails + 1; print("FAIL " .. what) end end
local function slurp(p) local h = real_open(map(p)); if not h then return nil end local c = h:read("a"); h:close(); return c end
local function put(p, text) local h = real_open(map(p), "w"); h:write(text); h:close() end
local function exists(p) local h = real_open(map(p)); if h then h:close() return true end return false end

-- the fake environment: a window that records what it is told, a directory listing over the fake home
local looks_sent, last
_norns = {box_look = function(...) last = {...}; looks_sent = (looks_sent or 0) + 1 end}
util = {scandir = function(dir)
  local out = {}
  local p = io.popen("ls -p '" .. map(dir) .. "' 2>/dev/null")
  for l in p:lines() do out[#out + 1] = l end
  p:close()
  return out
end}
package.loaded.util = util
local real_execute = os.execute
os.execute = function(cmd) return real_execute((cmd:gsub("/home/we", tmp))) end
local box = require 'core/box_settings'
local logged = {}
box.log = function(s) logged[#logged + 1] = s end
local function logged_has(s) for _, l in ipairs(logged) do if l:find(s, 1, true) then return true end end return false end
local function reset() logged = {}; looks_sent = 0; last = nil end

-- ---- hex ----
for _, v in ipairs({"2c2e33", "2C2E33", "#2c2e33", " 2c2e33 ", "f80", "#F80", "000", "ffffff"}) do
  local r = box.parse_hex(v)
  check(r ~= nil, "hex '" .. v .. "' is valid")
end
local r, g, b = box.parse_hex("f80")
check(r == 255 and g == 136 and b == 0, "3 digits are doubled")
r = box.parse_hex("000")
check(r == 0, "black is allowed (a black box is fine)")
for _, v in ipairs({"", "12", "1234", "12345", "1234567", "ggg", "12 456", "12345g", "0x123456", "#", "##123"}) do
  local rr, why = box.parse_hex(v)
  check(rr == nil and type(why) == "string" and why:find("3 or 6"), "hex '" .. v .. "' is rejected with a message")
end
check(box.hex_hint("") == "" and box.hex_hint("#") == "" and box.hex_hint("2c2e33") == "" and box.hex_hint("zz") ~= "", "the entry's hint: nothing while empty or valid, a reason otherwise")
check(box.hex("2c2e33") == "2C2E33" and box.hex("#f80") == "FF8800", "hex() normalises to six upper case digits")

-- ---- defaults ----
reset()
box.load()
check(box.state.style == "aluminium", "default style: aluminium (until the owner decides)")
check(box.state.preset == "MAC", "default look: MAC")
check(box.state.colours.box == "D1D4D8" and box.state.colours.keys == "404246" and box.state.colours.encoders == "DCDDE0" and box.state.colours.buttons == "303135" and box.state.colours.font == "C3C6CB", "default colours: the Mac look = the aluminium as it always was")
check(box.state.show_buttons == true, "default: the page buttons are shown")
check(logged_has("not found"), "a missing box.conf: a log line, the defaults")

-- ---- the built-in looks (the same four as box_palette.c) ----
local csrc = assert(real_open("matron/src/platform/linux/box_palette.c")):read("a")
local want = {}
for name, a, bb, c, d, e in csrc:gmatch('{"(%u+)", 1, {0x(%x+), 0x(%x+), 0x(%x+), 0x(%x+), 0x(%x+)}}') do want[#want + 1] = {name, a, bb, c, d, e} end
check(#want == 4 and #box.BUILTIN == 4, "four built-in looks, as in the C table (" .. #want .. " found there)")
for _, l in ipairs(box.BUILTIN) do check(l.style == nil, "a look has no style: " .. l.name) end
for i, w in ipairs(want) do
  local l = box.BUILTIN[i]
  check(l and l.name == w[1] and l.colours.box == w[2] and l.colours.keys == w[3] and l.colours.encoders == w[4] and l.colours.buttons == w[5] and l.colours.font == w[6], "built-in look " .. w[1] .. " matches box_palette.c")
end
check(box.BUILTIN[1].name == "DARK" and box.BUILTIN[2].name == "LIGHT" and box.BUILTIN[3].name == "COLOUR" and box.BUILTIN[4].name == "MAC", "the order: DARK LIGHT COLOUR MAC")

-- ---- apply and the colours working for both styles ----
reset()
box.apply()
check(looks_sent == 1 and last[1] == 0 and last[2] == "D1D4D8" and last[6] == "C3C6CB" and last[7] == 1, "apply: style 0 (aluminium), the five colours, buttons shown")
reset()
box.set_part("box", "#3b6ea8")
check(box.state.style == "aluminium" and box.state.colours.box == "3B6EA8", "one colour is set and the style stays")
check(looks_sent == 1 and last[1] == 0 and last[2] == "3B6EA8", "applied at once, to the aluminium style")
check(box.label() == "MAC~", "the look reads MAC~ (changed since)")
check(slurp("/home/we/box.conf"):find("box=3B6EA8", 1, true), "saved at once")
box.set_style("pixel")
check(box.state.style == "pixel" and box.state.colours.box == "3B6EA8", "STYLE changes the shape language only: the colours stay")
check(last[1] == 1 and last[2] == "3B6EA8", "and applied: pixel with the same colours")
reset()
box.set_part("keys", "e8a317")
check(box.state.style == "pixel", "a single colour does not change the style (pixel)")
box.set_style("aluminium")
box.set_part("font", "fff")
check(box.state.style == "aluminium" and box.state.colours.font == "FFFFFF", "nor in aluminium")

-- ---- a look sets the colours only; the style is its own choice ----
box.select_look("LIGHT")
check(box.state.preset == "LIGHT" and box.state.colours.box == "D8D5CE" and box.state.colours.font == "34343A", "choosing LIGHT: its five colours")
check(box.state.style == "aluminium", "...and the style stays as it was (aluminium)")
box.set_style("pixel")
box.select_look("COLOUR")
check(box.state.style == "pixel" and box.state.colours.box == "2B6F73", "a look chosen in pixel stays pixel")
box.set_style("aluminium")
check(box.state.colours.box == "2B6F73" and box.state.preset == "COLOUR", "STYLE changes only the style: the colours and the look stay")
check(box.label() == "COLOUR", "the label is just COLOUR")
box.select_look("LIGHT")
box.set_part("box", "112233")
check(box.label() == "LIGHT~" and box.state.preset == "LIGHT" and box.state.style == "aluminium", "a changed colour: LIGHT~, the style is not touched")
box.select_look("MAC")
check(box.state.colours.box == "D1D4D8", "MAC is the Mac box's colours")
check(not box.select_look("NO SUCH LOOK"), "an unknown look is refused")
for _, style in ipairs({"aluminium", "pixel"}) do
  box.set_style(style)
  for _, l in ipairs(box.BUILTIN) do
    box.select_look(l.name)
    check(box.state.style == style, "look " .. l.name .. " leaves the style " .. style)
    check(last and last[1] == (style == "pixel" and 1 or 0) and last[2] == l.colours.box, "applied: " .. style .. " with " .. l.name)
  end
end

-- ---- STYLE never changes the colours (the old "first pixel takes DARK" rule is gone) ----
os.remove("/home/we/box.conf")
box.load()
box.set_style("pixel")
check(box.state.style == "pixel" and box.state.preset == "MAC" and box.state.colours.box == "D1D4D8", "pixel with the untouched defaults: still the MAC colours")
box.set_style("aluminium")
check(box.state.style == "aluminium" and box.state.colours.box == "D1D4D8", "back to aluminium: the colours are the same")
os.remove("/home/we/box.conf")
box.load()
box.set_part("box", "445566")
box.set_style("pixel")
check(box.state.colours.box == "445566" and box.state.preset == "MAC", "with a colour of his own the colours are kept")

-- ---- hex rows: a bad value is rejected, the previous colour kept; low contrast is accepted with a message ----
box.load()
os.remove("/home/we/box.conf")
box.load()
box.set_part("keys", "336699")
reset()
local ok, why = box.set_part("keys", "12zz")
check(ok == false and why:find("3 or 6") and box.state.colours.keys == "336699", "a bad hex is rejected with a message and the colour kept")
check(looks_sent == 0, "nothing was applied for a rejected value")
ok, why = box.set_part("nosuchpart", "123456")
check(ok == false, "an unknown part is refused")
box.set_part("buttons", "303030")
ok, why = box.set_part("font", "323232")
check(ok == true and why and why:find("contrast"), "a font almost the colour of the buttons is accepted with a low contrast message")
ok, why = box.set_part("font", "ffffff")
check(ok == true and why == nil, "a readable pair gives no message")
ok = box.set_part("box", "000")
check(ok == true and box.state.colours.box == "000000", "black is accepted")

-- ---- box.conf: round trip, the other keys kept, unknown keys, damaged values ----
os.remove("/home/we/box.conf")
box.load()
box.set_style("pixel")
box.select_look("COLOUR")
box.set_show_buttons(false)
local saved = slurp("/home/we/box.conf")
for _, line in ipairs({"style=pixel", "preset=COLOUR", "box=2B6F73", "keys=F2B63D", "encoders=E9DFC8", "buttons=1D4A4D", "font=F7F0DE", "show_buttons=0"}) do
  check(saved:find(line, 1, true), "box.conf has " .. line)
end
box.state = nil
reset()
box.load()
check(box.state.style == "pixel" and box.state.preset == "COLOUR" and box.state.colours.keys == "F2B63D" and box.state.show_buttons == false, "restart: the look and the style are remembered")
reset()
box.load_and_apply()
check(last and last[1] == 1 and last[2] == "2B6F73" and last[7] == 0, "at start the window is told: pixel, the colours, row hidden")
put("/home/we/box.conf", "style=pixel\nthis=that\nbox=112233\n# comment?\nshow_buttons=1\n")
reset()
box.load()
check(logged_has("unknown key 'this'"), "an unknown key is logged")
box.set_part("keys", "abcdef")
check(slurp("/home/we/box.conf"):find("this=that", 1, true), "an unknown key is kept when the file is written again")
check(box.state.colours.box == "112233", "known keys still read")
for _, c in ipairs({{"style", "round", "aluminium"}, {"box", "red", "D1D4D8"}, {"keys", "12", "404246"}, {"encoders", "#", "DCDDE0"}, {"buttons", "1234567", "303135"}, {"font", "g00", "C3C6CB"}, {"show_buttons", "maybe", true}}) do
  put("/home/we/box.conf", c[1] .. "=" .. c[2] .. "\n" .. (c[1] == "box" and "keys=0A0B0C\n" or "box=0A0B0C\n"))
  reset()
  box.load()
  local got = c[1] == "show_buttons" and box.state.show_buttons or (c[1] == "style" and box.state.style or box.state.colours[c[1]])
  check(got == c[3], "damaged " .. c[1] .. "='" .. c[2] .. "' falls back to " .. tostring(c[3]) .. " (got " .. tostring(got) .. ")")
  check(logged_has(c[1]), "damaged " .. c[1] .. ": a log line names it")
  if c[1] ~= "box" then check(box.state.colours.box == "0A0B0C", "damaged " .. c[1] .. ": the other settings are fine") end
end
put("/home/we/box.conf", "preset=GONE\nstyle=pixel\n")
reset()
box.load()
check(box.state.preset == "CUSTOM" and logged_has("GONE"), "preset= naming a look that does not exist: CUSTOM and a log line, the colours stay")
check(box.label() == "CUSTOM", "the label")

-- ---- nothing without _norns.box_look (macOS, the device) ----
local saved_look = _norns.box_look
_norns.box_look = nil
reset()
os.remove("/home/we/box.conf")
check(box.load_and_apply() == nil, "without _norns.box_look load_and_apply does nothing")
check(not exists("/home/we/box.conf"), "and writes nothing")
_norns.box_look = saved_look

-- ---- name validation ----
local function name_ok(n) local v, why = box.validate_name(n); return v, why end
check(name_ok("Barn door") == "Barn door", "a plain name")
check(name_ok("  padded  ") == "padded", "trimmed")
check(name_ok("a-b_c.d 1") == "a-b_c.d 1", "letters, digits, space, - _ .")
local longest = string.rep("x", 18)
check(name_ok(longest) == longest, "18 characters are fine")
for _, bad in ipairs({"", "   ", string.rep("x", 19), "a/b", "a\\b", "..", "../x", ".hidden", "a:b", "a*b", "a?b", 'a"b', "a<b", "a>b", "a|b", "a\nb", "a\0b", "a\tb", "caf\195\169", "a..b", "-", "DARK", "dark", "Light", "COLOUR", "mac", "CUSTOM"}) do
  local v, why = name_ok(bad)
  check(v == nil and type(why) == "string", "name " .. string.format("%q", bad) .. " is refused (" .. tostring(why) .. ")")
end
check(select(2, name_ok("dark")):find("built%-in"), "a built-in name: 'is a built-in name'")
check(select(2, name_ok("a/b")):find("path") or select(2, name_ok("a/b")):find("/"), "the message for a path character mentions it")
check(box.slug("Barn  Door") == "barn--door" and box.slug("Barn Door") == "barn-door" and box.slug("BARN-door") == "barn-door", "slug: lower case, spaces become dashes")

-- ---- saving looks: one file each, in box-presets/ ----
os.remove("/home/we/box.conf")
box.load()
box.select_look("COLOUR")
box.set_part("keys", "e8a317")
reset()
local ok2, why2 = box.save_look("Barn door")
check(ok2 == true, "save: ok (" .. tostring(why2) .. ")")
local text = slurp("/home/we/box-presets/barn-door.box")
check(text == "verdandi-box=1\nname=Barn door\nbox=2B6F73\nkeys=E8A317\nencoders=E9DFC8\nbuttons=1D4A4D\nfont=F7F0DE\n", "the file is exactly the documented format (colours only, no style): " .. tostring(text))
check(box.state.preset == "Barn door" and box.label() == "Barn door", "after saving the new look is the one in use")
check(slurp("/home/we/box.conf"):find("preset=Barn door", 1, true), "and box.conf says so")
check(not exists("/home/we/box-presets/barn-door.box.tmp"), "no temporary file is left")
local list = box.look_list()
check(#list == 5 and list[1].name == "DARK" and list[4].name == "MAC" and list[5].name == "Barn door", "the list: the built-in looks, then his own after them")
check(list[5].builtin == false and list[1].builtin == true, "built-in or his own is marked in the list")

-- overwrite: refused without confirmation, written with it
reset()
box.set_part("keys", "112233")
local o, w = box.save_look("barn DOOR")
check(o == false and w == "exists", "the same name in other letters exists already: asks first (" .. tostring(w) .. ")")
check(slurp("/home/we/box-presets/barn-door.box"):find("keys=E8A317", 1, true), "without the confirmation nothing was written")
o = box.save_look("barn DOOR", true)
check(o == true and slurp("/home/we/box-presets/barn-door.box"):find("keys=112233", 1, true), "with the confirmation the file is written")
check(slurp("/home/we/box-presets/barn-door.box"):find("name=barn DOOR", 1, true), "under the name as he typed it now")
check(#box.look_list() == 5, "still one look of his")

-- load: another look, then back
box.select_look("DARK")
check(box.state.colours.box == "2C2E33", "DARK chosen")
box.select_look("barn DOOR")
check(box.state.preset == "barn DOOR" and box.state.colours.keys == "112233", "his look: the colours restored")
-- loading a saved look never switches the style, whichever style it was saved in
box.set_style("aluminium")
box.save_look("Silver one")
box.set_style("pixel")
box.select_look("DARK")
box.select_look("Silver one")
check(box.state.style == "pixel", "a look saved in aluminium, loaded in pixel: the style stays pixel")
check(not slurp("/home/we/box-presets/silver-one.box"):find("style", 1, true), "a saved look has no style line")
put("/home/we/box-presets/older.box", "verdandi-box=1\nname=Older\nstyle=aluminium\nbox=010203\nkeys=040506\nencoders=070809\nbuttons=0A0B0C\nfont=0D0E0F\n")
box.reload_looks()
check(box.look_by_name("Older") and box.look_by_name("Older").colours.box == "010203", "a look file from the first version (with style=) is still read")
box.set_style("pixel")
box.select_look("Older")
check(box.state.style == "pixel", "its style line is ignored")
put("/home/we/box-presets/older2.box", "verdandi-box=1\nname=Older2\nstyle=round\nbox=010203\nkeys=040506\nencoders=070809\nbuttons=0A0B0C\nfont=0D0E0F\n")
box.reload_looks()
check(box.look_by_name("Older2") ~= nil, "even an unknown style value no longer matters")
os.remove("/home/we/box-presets/older.box")
os.remove("/home/we/box-presets/older2.box")
box.reload_looks()

-- built-in protection
reset()
local bo, bw = box.save_look("DARK")
check(bo == false and bw:find("built%-in"), "SAVE refuses a built-in name")
check(not exists("/home/we/box-presets/dark.box"), "no file for a built-in name")
local do_, dw = box.delete_look("DARK")
check(do_ == false, "a built-in look cannot be deleted")
check(box.look_by_name("DARK") ~= nil and #box.BUILTIN == 4, "the built-in looks are still there")
put("/home/we/box-presets/dark.box", "verdandi-box=1\nname=Dark\nstyle=pixel\nbox=000000\nkeys=000000\nencoders=000000\nbuttons=000000\nfont=FFFFFF\n")
reset()
box.reload_looks()
check(logged_has("built-in") and box.look_by_name("DARK").builtin == true and box.look_by_name("DARK").colours.box == "2C2E33", "a file that carries a built-in name is ignored with a log line")
os.remove("/home/we/box-presets/dark.box")

-- delete
box.select_look("barn DOOR")
reset()
local before = #box.look_list()
local dok = box.delete_look("barn DOOR")
check(dok == true and not exists("/home/we/box-presets/barn-door.box"), "delete removes the file")
check(#box.look_list() == before - 1, "and the look is out of the list")
check(box.state.preset == "CUSTOM" and box.label() == "CUSTOM", "the colours stay on the box, the label reads CUSTOM")
check(not box.delete_look("barn DOOR"), "deleting it again is refused")

-- damaged and foreign files: ignored with one log line each, never an error
local good = "verdandi-box=1\nname=%s\nbox=112233\nkeys=445566\nencoders=778899\nbuttons=AABBCC\nfont=DDEEFF\n"
put("/home/we/box-presets/binary.box", string.char(0, 1, 2, 255, 254) .. "garbage")
put("/home/we/box-presets/big.box", string.format(good, "big") .. string.rep("# padding\n", 400))
put("/home/we/box-presets/wrongfirst.box", "hello\n" .. string.format(good, "wrongfirst"):gsub("^verdandi%-box=1\n", ""))
put("/home/we/box-presets/newer.box", string.format(good, "newer"):gsub("verdandi%-box=1", "verdandi-box=2"))
put("/home/we/box-presets/badcolour.box", string.format(good, "badcolour"):gsub("keys=445566", "keys=red"))
put("/home/we/box-presets/mismatch.box", string.format(good, "something else"))
put("/home/we/box-presets/pathy.box", string.format(good, "../evil"))
put("/home/we/box-presets/nocolour.box", "verdandi-box=1\nname=nocolour\nstyle=pixel\nbox=112233\n")
put("/home/we/box-presets/empty.box", "")
put("/home/we/box-presets/notbox.txt", string.format(good, "notbox"))
put("/home/we/box-presets/fine.box", string.format(good, "fine"))
put("/home/we/box-presets/extra.box", string.format(good, "extra") .. "future=thing\n")
reset()
local okc = pcall(box.reload_looks)
check(okc, "reading damaged files does not raise an error")
local names = {}
for _, l in ipairs(box.look_list()) do names[l.name] = true end
check(names["fine"] and names["extra"], "valid files are in the list (an unknown key is ignored)")
for _, n in ipairs({"binary", "big", "wrongfirst", "newer", "badcolour", "something else", "../evil", "nocolour", "empty", "notbox"}) do
  check(not names[n], "'" .. n .. "' is not in the list")
end
for _, f in ipairs({"binary.box", "big.box", "wrongfirst.box", "newer.box", "badcolour.box", "mismatch.box", "pathy.box", "nocolour.box", "empty.box"}) do
  check(logged_has(f), "a log line names " .. f)
end
check(not logged_has("notbox.txt"), "a file that is not .box is not even looked at")
-- the exact text of one log line
local found
for _, l in ipairs(logged) do if l:find("badcolour.box", 1, true) then found = l end end
check(found and found:find("ignored", 1, true), "the log line says it is ignored: " .. tostring(found))
-- a copied file appears
put("/home/we/box-presets/copied.box", string.format(good, "Copied"):gsub("112233", "010203"))
box.reload_looks()
check(box.look_by_name("Copied") and box.look_by_name("Copied").colours.box == "010203", "a file copied from another computer appears")
-- 64 looks at most
for i = 1, 70 do put(string.format("/home/we/box-presets/many%02d.box", i), string.format(good, "many" .. string.format("%02d", i))) end
reset()
box.reload_looks()
local own = 0
for _, l in ipairs(box.look_list()) do if not l.builtin then own = own + 1 end end
check(own == 64, "at most 64 looks of his (" .. own .. ")")
check(logged_has("64"), "the extra files are ignored with a log line")
local sok, swhy = box.save_look("one more")
check(sok == false and swhy:find("64"), "saving a 65th is refused")

-- the PRESET order and stepping
os.execute("rm -f '" .. tmp .. "'/box-presets/*")
box.reload_looks()
box.save_look("Zed")
box.save_look("alpha")
local order = {}
for _, l in ipairs(box.look_list()) do order[#order + 1] = l.name end
check(table.concat(order, ",") == "DARK,LIGHT,COLOUR,MAC,alpha,Zed", "built-in first, then his own sorted by name: " .. table.concat(order, ","))
box.select_look("DARK")
box.step_preset(1)
check(box.state.preset == "LIGHT" and box.state.style == "pixel", "E3 steps to the next look (the style is not touched)")
box.step_preset(10)
check(box.state.preset == "Zed", "stepping stops at the end")
box.step_preset(-1)
check(box.state.preset == "alpha", "and back")
box.step_preset(0)
check(box.state.preset == "alpha", "a delta of 0 changes nothing")
box.set_part("box", "010101")
box.step_preset(1)
check(box.state.preset == "Zed" and box.state.colours.box ~= "010101", "stepping from a changed look goes on from its place in the list")
box.set_style("aluminium")
box.delete_look("Zed")
box.state.preset = "CUSTOM"
box.step_preset(1)
check(box.state.preset == "DARK", "from CUSTOM a step starts at the first look")

-- the window's checkbox: the C call, saved
reset()
check(type(_norns.box_buttons_changed) == "function", "lua answers the menu's tick (_norns.box_buttons_changed)")
_norns.box_buttons_changed("0")
check(box.state.show_buttons == false and slurp("/home/we/box.conf"):find("show_buttons=0", 1, true) and last[7] == 0, "the menu unticked it: hidden, saved, applied")
_norns.box_buttons_changed("1")
check(box.state.show_buttons == true and last[7] == 1, "ticked again")

os.execute("rm -rf '" .. tmp .. "'")
if fails > 0 then print("box_settings_test: " .. fails .. " failed") os.exit(1) end
print("box_settings_test: all passed")
