-- winui.lua: helpers for the system pages of the Windows build (docs/port/phase-m3.md, "UI principle"): they must read like the menus of a norns: a short list, E2 selects, E3 changes, K2 goes back.
--   winui.remap / winui.wrap  brighter levels on every Windows system page (unselected rows were level 4 on a black screen: dim and olive with a theme tint)
--   winui.fit                 text that is never wider than its place: cut with "..." (no scrolling text: the selected row's full text is in the info area at the bottom)
--   winui.row                 one list row: a label, a value, a bar behind the selected row; both cut to fit
--   winui.list                the rows of a list page (4 rows), the standing status line under them, and the info area
--   winui.info                the info area, the same place on every list page: the full text of the selected row, wrapped over two lines, an ellipsis in the middle when it is longer than that
local winui = {}

-- level 0 stays black (fills, clears); 1..15 go to 8..15, so that "dim" text is still easy to read and the selected row (15) is still the brightest
function winui.remap(l)
  l = tonumber(l) or 0
  if l <= 0 then return 0 end
  return math.min(15, 8 + math.floor(l * 7 / 15 + 0.5))
end

-- wraps a page's redraw: screen.level is remapped while it draws. the page itself is not changed
function winui.wrap(redraw)
  return function(...)
    local real = screen.level
    screen.level = function(l) return real(winui.remap(l)) end
    local ok, err = pcall(redraw, ...)
    screen.level = real
    if not ok then error(err, 0) end
  end
end

local ELL = "..."

-- the UTF-8 characters of s (whole characters: an accent or a symbol is never cut in two)
local function chars(s)
  local t = {}
  for _, c in utf8.codes(s) do t[#t + 1] = utf8.char(c) end
  return t
end
local function safe_chars(s)
  if utf8.len(s) then return chars(s) end
  local t = {}
  for i = 1, #s do t[#t + 1] = s:sub(i, i) end
  return t
end

-- s shortened so that it is not wider than w pixels, "..." at the end where it was cut
local function cut(s, w)
  if screen.text_extents(s) <= w then return s end
  local cs = safe_chars(s)
  local n = #cs
  while n > 1 do
    n = n - 1
    local c = table.concat(cs, "", 1, n) .. ELL
    if screen.text_extents(c) <= w then return c end
  end
  return ELL
end
winui.cut = cut

-- s in w pixels, cut with "..." (the old second and third arguments, scroll and tick, are accepted and ignored: no list scrolls its text any more; the full text of the selected row is in the info area)
function winui.fit(s, w)
  return cut(tostring(s or ""), w)
end

-- a text cut at word ends into lines that each fit w pixels (the pages of a help text that is shown one after the other). a single word wider than w is cut with ".."
function winui.pages(text, w)
  local pages, cur = {}, ""
  for word in tostring(text or ""):gmatch("%S+") do
    local try = cur == "" and word or (cur .. " " .. word)
    if screen.text_extents(try) <= w then
      cur = try
    else
      if cur ~= "" then pages[#pages + 1] = cur end
      cur = screen.text_extents(word) <= w and word or cut(word, w)
    end
  end
  if cur ~= "" then pages[#pages + 1] = cur end
  return pages
end

-- how a row's label and value share the width: both whole when they fit; else the shorter one whole if it is under 40% and the other takes the rest; else 40% for the label and the rest for the value.
-- returns the shown label, the shown value, and whether anything was cut
function winui.row_texts(label, value, width)
  label, value = tostring(label or ""), tostring(value or "")
  local lw, vw = screen.text_extents(label), screen.text_extents(value)
  local gap = (value ~= "") and 6 or 0
  if lw + vw + gap <= width then return label, value, false end
  local shown_l, shown_v
  if lw <= width * 0.4 then
    shown_l, shown_v = label, cut(value, width - lw - gap)
  elseif vw <= width * 0.4 then
    shown_l, shown_v = cut(label, width - vw - gap), value
  else
    local l_w = math.floor(width * 0.4)
    shown_l, shown_v = cut(label, l_w), cut(value, width - l_w - gap)
  end
  return shown_l, shown_v, true
end

-- a row at baseline y: a bar (8 px high, the whole width) and the text of the selected row at 15, the others at 11 (on a Windows page that is already bright). mark: a short word at the very end (* chosen, ok ...).
-- the text is cut to fit and never scrolls; returns the label and the value as shown and whether they were cut
function winui.row(y, label, value, selected, mark)
  if selected then
    screen.level(3)
    screen.rect(0, y - 7, 128, 9)
    screen.fill()
  end
  screen.level(selected and 15 or 11)
  local mw = 0
  if mark and mark ~= "" then
    mw = screen.text_extents(mark) + 4
    screen.move(126, y)
    screen.text_right(mark)
  end
  local sl, sv, was_cut = winui.row_texts(label, value, 126 - 2 - mw)
  screen.move(2, y)
  screen.text(sl)
  if sv ~= "" then
    screen.move(126 - mw, y)
    screen.text_right(sv)
  end
  return sl, sv, was_cut
end

-- ---- the info area, the same place on every list page: a thin rule and two lines at the very bottom, under the list. 128 x 64: the rule at y 47, the lines at baselines 55 and 63
winui.ROWS = 4          -- the rows of a list: baselines 8, 17, 26, 35
winui.STATUS_Y = 44     -- the standing line of a page (what is going on: numbers, a count), under the list, over the rule
winui.RULE_Y = 47
winui.INFO_Y = {55, 63}
winui.INFO_W = 124

-- the text over at most two lines: broken at a blank near the end of the first line (a name with no blank at the last place that fits); when it is longer than two lines the second line starts with "..." and ends with the
-- END of the text (a file type, a port number): the middle is what is left out
function winui.wrap2(text, w)
  w = w or winui.INFO_W
  text = tostring(text or ""):gsub("%s+", " "):match("^ ?(.-) ?$")
  if text == "" then return {} end
  if screen.text_extents(text) <= w then return {text} end
  local cs = safe_chars(text)
  local n = #cs
  local i = 1
  while i < n and screen.text_extents(table.concat(cs, "", 1, i + 1)) <= w do i = i + 1 end
  local brk = i
  for j = i, math.max(1, i - 12), -1 do
    if cs[j + 1] == " " then brk = j break end -- the next character is a blank: the line may end here
  end
  local first = table.concat(cs, "", 1, brk):gsub(" +$", "")
  local rest = table.concat(cs, "", brk + 1, n):gsub("^ +", "")
  if screen.text_extents(rest) <= w then return {first, rest} end
  -- longer than two lines: the second line is "..." and the end of the text
  local rc = safe_chars(rest)
  local k = #rc
  local budget = w - screen.text_extents(ELL)
  local tail = ""
  for t = 1, #rc do
    local cand = table.concat(rc, "", #rc - t + 1, #rc)
    if screen.text_extents(cand) > budget then break end
    tail = cand
  end
  return {first, ELL .. tail}
end

-- draw the given lines (at most two) in the info area: the rule, then the lines on the two baselines (one line sits on the lower one). no lines: the area stays blank
function winui.info_lines(lines)
  if #lines == 0 then return lines end
  screen.level(3)
  screen.rect(0, winui.RULE_Y, 128, 1)
  screen.fill()
  screen.level(11)
  if #lines == 1 then
    screen.move(2, winui.INFO_Y[2])
    screen.text(lines[1])
  else
    screen.move(2, winui.INFO_Y[1])
    screen.text(lines[1])
    screen.move(2, winui.INFO_Y[2])
    screen.text(lines[2])
  end
  return lines
end

-- draw the info area for a text (wrapped over two lines, an ellipsis in the middle when longer). text "" (or nil): nothing is drawn, the area stays blank (the rule too)
function winui.info(text)
  return winui.info_lines(winui.wrap2(text, winui.INFO_W))
end

-- a long text in the info area, two lines at a time: the page that is on (tick counts the redraws; each page stays PAGE_TICKS of them). only for the help sentences of a page, never for the text of a row
function winui.help_pages(text, tick, page_ticks)
  local pages = winui.pages(text, winui.INFO_W)
  if #pages == 0 then return {} end
  local n = math.ceil(#pages / 2)
  local first = (math.floor((tick or 0) / (page_ticks or 12)) % n) * 2
  local out = {}
  for i = first + 1, math.min(first + 2, #pages) do out[#out + 1] = pages[i] end
  return out
end

-- the standing line under the list
function winui.status(text)
  screen.level(11)
  screen.move(2, winui.STATUS_Y)
  screen.text(cut(tostring(text or ""), 124))
end

-- the rows of a list page: rows = {{label=, value=, mark=}, ...}, pos = the selected one. draws the 4 rows around the selection (the selected one second from the top where the list is long enough, as before), and returns
-- the top row, and the full text of the selected row ("label  value") and whether it was cut
function winui.list(rows, pos)
  local n = winui.ROWS
  local top = math.max(1, math.min(pos - 1, math.max(1, #rows - n + 1)))
  local full, was_cut = "", false
  for k = 0, n - 1 do
    local i = top + k
    local r = rows[i]
    if r then
      local _, _, c = winui.row(8 + 9 * k, r.label, r.value, i == pos, r.mark)
      if i == pos then
        full = r.label .. ((r.value and r.value ~= "") and ("  " .. r.value) or "")
        was_cut = c
      end
    end
  end
  return top, full, was_cut
end

return winui
