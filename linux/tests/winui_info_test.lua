-- the common code of the list pages (lua/core/menu/winui.lua; Windows 0.10.3, docs/port/phase-m12.md): rows cut with "..." and never scrolling, and the info area at the bottom: the full text of the selected row over two
-- lines, an ellipsis in the middle when it is longer, the same place on every page. run from the repo root: lua5.3 linux/tests/winui_info_test.lua   (with FONT_WIDTHS=<table> the real font's widths are used)
package.path = "lua/?.lua;lua/lib/?.lua;lua/core/?.lua;" .. package.path
local fails = 0
local function check(c, what) if not c then fails = fails + 1; print("FAIL " .. what) end end
local W
if os.getenv("FONT_WIDTHS") then
  W = dofile("linux/tests/page_width.lua"); W.load(os.getenv("FONT_WIDTHS")); W.install()
else
  screen = setmetatable({}, {__index = function() return function() end end})
  screen.text_extents = function(s) return (utf8.len(s) or #s) * 5 end
end
local calls = {}
local base = {}
for _, k in ipairs({"clear", "text", "text_right", "level", "move", "rect", "fill"}) do base[k] = screen[k] end
local x, y = 0, 0
screen.move = function(a, b) x, y = a, b end
screen.text = function(s) calls[#calls + 1] = {kind = "text", x = x, y = y, s = s} end
screen.text_right = function(s) calls[#calls + 1] = {kind = "right", x = x, y = y, s = s} end
screen.rect = function(a, b, c, d) calls[#calls + 1] = {kind = "rect", x = a, y = b, w = c, h = d} end
screen.level = function() end
screen.fill = function() end
local winui = require 'core/menu/winui'
local function width(s) return screen.text_extents(s) end
local function valid_utf8(s) return utf8.len(s) ~= nil end

-- ---- cut: "..." at the end, only where it was cut, never in the middle of a character
check(winui.cut("short", 100) == "short", "text that fits is left alone")
local long = "Speakers (Realtek(R) High Definition Audio Device)"
local c = winui.cut(long, 80)
check(width(c) <= 80 and c:sub(-3) == "..." and c:sub(1, 6) == long:sub(1, 6), "a long name is cut with ... and fits: " .. c)
local accents = "Sortie num\xc3\xa9rique (H\xc3\xa9bergement \xe2\x80\x93 \xc3\x89cran) \xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e USB"
c = winui.cut(accents, 60)
check(valid_utf8(c) and width(c) <= 60 and c:sub(-3) == "...", "a name with accents and symbols is cut between characters: " .. c)
check(winui.fit(long, 80, true, 20) == winui.fit(long, 80, true, 0), "fit never scrolls (tick makes no difference)")
check(winui.cut("x", 2) == "..." or width(winui.cut("x", 2)) >= 0, "a place smaller than the ellipsis does not loop")

-- ---- the rows: label and value share the width
local l, v, was = winui.row_texts("OUTPUT", "Speakers", 120)
check(l == "OUTPUT" and v == "Speakers" and not was, "both fit: both whole")
l, v, was = winui.row_texts("OUTPUT", long, 120)
check(l == "OUTPUT" and v:sub(-3) == "..." and width(v) <= 120 - width("OUTPUT") - 6 and was, "a short label keeps its place, the long value is cut: " .. v)
l, v, was = winui.row_texts(long, "stopped", 120)
check(v == "stopped" and l:sub(-3) == "..." and width(l) <= 120 - width("stopped") - 6 and was, "a short value keeps its place, the long label is cut: " .. l)
l, v, was = winui.row_texts(long, long, 120)
check(width(l) <= 48 and width(v) <= 120 - 48 - 6 and was, "both long: 40% for the label, the rest for the value")
check(select(3, winui.row_texts("A", "", 120)) == false, "no value: nothing cut")
-- a row draws the cut texts; the marks stay
calls = {}
local sl, sv, rc = winui.row(8, "OUTPUT", long, true, "*")
local texts = {}
for _, k in ipairs(calls) do if k.kind ~= "rect" then texts[#texts + 1] = k end end
check(rc and #texts == 3, "a selected row with a mark draws the mark, the label and the cut value")
for _, t in ipairs(texts) do check(valid_utf8(t.s), "valid text in a row") end

-- ---- wrap2: two lines, a name with no blank, the end kept
local function ok_lines(lines, what)
  check(#lines >= 1 and #lines <= 2, what .. ": one or two lines (" .. #lines .. ")")
  for i, ln in ipairs(lines) do check(width(ln) <= 124, what .. ": line " .. i .. " fits (" .. width(ln) .. " px)"); check(valid_utf8(ln), what .. ": line " .. i .. " is valid UTF-8") end
end
local lines = winui.wrap2("OUTPUT", 124); ok_lines(lines, "short"); check(#lines == 1 and lines[1] == "OUTPUT", "a short text is one line")
lines = winui.wrap2("OUTPUT  " .. long, 124); ok_lines(lines, "a device name")
check(#lines == 2 and lines[2]:sub(-8) == "Device)" or lines[2]:sub(-8) == " Device)" or lines[2]:sub(-7) == "Device)", "a long device name keeps its end: " .. table.concat(lines, " | "))
local medium = "OUTPUT  Speakers (Realtek High Def Audio)"
lines = winui.wrap2(medium, 124); ok_lines(lines, "a medium device name")
check(#lines == 2 and (lines[1] .. " " .. lines[2]) == medium:gsub("%s+", " ") and not lines[2]:find("^%.%.%."), "it fits over two lines: nothing is left out: " .. table.concat(lines, " | "))
local device = "Digital Audio Interface (Professional Multichannel Studio Sound Card Extended Edition) 7-8"
lines = winui.wrap2("INPUT  " .. device, 124); ok_lines(lines, "a longer device name")
check(lines[2]:sub(1, 3) == "..." and lines[2]:sub(-3) == "7-8", "too long for two lines: the second line starts with ... and ends with the port numbers: " .. table.concat(lines, " | "))
local path = "/home/we/dust/audio/[ext] A very long folder name for samples/Drum Machines/808 Kit One Shots/kick drum long name take 12 final mix.wav"
lines = winui.wrap2(path, 124); ok_lines(lines, "a long path")
check(lines[2]:sub(1, 3) == "..." and lines[2]:sub(-4) == ".wav", "a long file name with a long path: ... and the file type at the end: " .. table.concat(lines, " | "))
lines = winui.wrap2(string.rep("x", 200) .. ".wav", 124); ok_lines(lines, "one word with no blank")
check(lines[2]:sub(-4) == ".wav", "a name with no blank at all: the end stays")
lines = winui.wrap2(accents .. " " .. accents .. " " .. accents, 124); ok_lines(lines, "non-ASCII")
check(lines[2]:sub(1, 3) == "..." or #lines == 2, "non-ASCII text: two lines")
check(#winui.wrap2("", 124) == 0 and #winui.wrap2(nil, 124) == 0, "nothing: no lines")
lines = winui.wrap2("a    b\t\tc", 124); check(#lines == 1 and lines[1] == "a b c", "blanks are collapsed")
-- the line breaks at a blank when there is one near the end of the line
lines = winui.wrap2("one two three four five six seven eight nine ten eleven twelve thirteen fourteen", 124); ok_lines(lines, "words")
check(lines[1]:sub(-1) ~= " " and not lines[1]:find("%s$") and (lines[2] == nil or not lines[2]:find("^%s")), "no blank at the break")

-- ---- the info area: always in the same place
calls = {}
winui.info("OUTPUT  " .. long)
local rects, ts = {}, {}
for _, k in ipairs(calls) do if k.kind == "rect" then rects[#rects + 1] = k else ts[#ts + 1] = k end end
check(#rects == 1 and rects[1].y == winui.RULE_Y and rects[1].w == 128, "a rule above the info area (y " .. winui.RULE_Y .. ")")
check(#ts == 2 and ts[1].y == winui.INFO_Y[1] and ts[2].y == winui.INFO_Y[2], "two lines on the two baselines " .. winui.INFO_Y[1] .. " and " .. winui.INFO_Y[2])
calls = {}
winui.info("short")
local only
for _, k in ipairs(calls) do if k.kind == "text" then only = k end end
check(only and only.y == winui.INFO_Y[2], "one line sits on the lower baseline")
calls = {}
winui.info("")
check(#calls == 0, "no text: a blank area (nothing drawn)")
-- the area is under the list: the last list row's baseline plus its descenders is above the rule
check(8 + 9 * (winui.ROWS - 1) + 2 < winui.RULE_Y and winui.STATUS_Y < winui.RULE_Y, "the list and the status line end above the rule")
check(winui.INFO_Y[1] - 7 > winui.RULE_Y and winui.INFO_Y[2] <= 63, "the two lines are under the rule and on the screen")

-- ---- the list: 4 rows, the selected one second where the list is long
local rows = {}
for i = 1, 9 do rows[i] = {label = "ROW" .. i, value = (i == 5) and long or "v" .. i} end
calls = {}
local top, full, cutflag = winui.list(rows, 5)
check(top == 4, "the list scrolls so that the selected row is second from the top (" .. top .. ")")
check(full == "ROW5  " .. long and cutflag, "the full text of the selected row and that it was cut")
local ys = {}
for _, k in ipairs(calls) do if k.kind == "text" then ys[k.y] = true end end
check(ys[8] and ys[17] and ys[26] and ys[35] and not ys[44], "rows at 8, 17, 26 and 35 and nothing at the status line")
top, full, cutflag = winui.list(rows, 1); check(top == 1 and not cutflag, "the first row: nothing cut")
top = winui.list(rows, 9); check(top == 6, "the last row: the window of rows ends with it (" .. top .. ")")
if fails > 0 then print(fails .. " failed"); os.exit(1) end
print("winui info: all passed")
