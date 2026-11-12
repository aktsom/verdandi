-- winui.lua: helpers for the system pages of the Windows build (docs/port/phase-m3.md, "UI principle"): they must read like the menus of a norns: a short list, E2 selects, E3 changes, K2 goes back.
--   winui.remap / winui.wrap  brighter levels on every Windows system page (unselected rows were level 4 on a black screen: dim and olive with a theme tint)
--   winui.fit                 text that is never wider than its place: cut with "..", or on the selected row a slow marquee
--   winui.row                 one list row: a label, a value, a bar behind the selected row
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

local function cut(s, w)
  if screen.text_extents(s) <= w then return s end
  local n = utf8.len(s) or #s
  while n > 1 do
    n = n - 1
    local c = s:sub(1, (utf8.offset(s, n + 1) or (#s + 1)) - 1) .. ".."
    if screen.text_extents(c) <= w then return c end
  end
  return ".."
end

-- s in w pixels. scroll: the selected row's value runs slowly (tick counts the redraws of the page, 4 a second): a second of rest, then two characters a second, round and round
function winui.fit(s, w, scroll, tick)
  s = tostring(s or "")
  if screen.text_extents(s) <= w then return s end
  if not scroll then return cut(s, w) end
  local doubled = s .. "   " .. s
  local len = utf8.len(s) or #s
  local steps = len + 3
  local k = math.max(0, math.floor(((tick or 0) - 4) / 2)) % steps
  local start = utf8.offset(doubled, k + 1) or 1
  local shown = doubled:sub(start)
  -- as much of it as fits
  local n = utf8.len(shown) or #shown
  while n > 1 and screen.text_extents(shown) > w do
    n = n - 1
    shown = shown:sub(1, (utf8.offset(shown, n + 1) or (#shown + 1)) - 1)
  end
  return shown
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

-- a row at baseline y: bar (8 px high, the whole width) and the text of the selected row at 15, the others at 11 (on a Windows page that is already bright)
function winui.row(y, label, value, selected, tick)
  if selected then
    screen.level(3)
    screen.rect(0, y - 7, 128, 9)
    screen.fill()
  end
  screen.level(selected and 15 or 11)
  screen.move(2, y)
  screen.text(label)
  local lw = screen.text_extents(label)
  screen.move(126, y)
  screen.text_right(winui.fit(value, 126 - 2 - lw - 8, selected, tick))
end

return winui
