-- the width check for our own menu pages (page_width_test.lua): a recording screen with the REAL text metrics of the norns screen font (a table made by
-- linux/tests/font_widths_dump.c from the font file, measured by cairo), and the rules a drawn row must obey on the 128 x 64 screen:
--   a text starts at x >= 0 and ends at x <= 128; a right-aligned text starts at x >= 0; no two texts on one baseline overlap (a gap of at least 1 pixel)
-- scripts' own drawing is not checked or changed (a long file name in a script's fileselect overflows on the device too).
-- usage:  local W = dofile("linux/tests/page_width.lua"); W.load(os.getenv("FONT_WIDTHS")); W.install()  (replaces the global screen)
--         ... call page.redraw() ...;  local bad = W.violations(); W.clear()
local W = {}

local adv, xb, iw = {}, {}, {}
local cairo_checks = {}

function W.load(path)
  local f = assert(io.open(path), "FONT_WIDTHS: the table of font metrics (linux/tests/font_widths_dump.c)")
  for line in f:lines() do
    local c, a, b, w = line:match("^C (%d+) (%S+) (%S+) (%S+)$")
    if c then adv[tonumber(c)], xb[tonumber(c)], iw[tonumber(c)] = tonumber(a), tonumber(b), tonumber(w) end
    local w2, s = line:match("^S (%S+) (.*)$")
    if w2 then cairo_checks[#cairo_checks + 1] = {s = s, w = tonumber(w2)} end
  end
  f:close()
end

-- the advance and the ink width of a string, as cairo gives them (ink = the advances of all but the last glyph + the last glyph's bearing and width - the first bearing)
local function measure(s)
  local n = #s
  if n == 0 then return 0, 0 end
  local sum = 0
  for i = 1, n do sum = sum + (adv[s:byte(i)] or adv[63] or 5) end
  local last, first = s:byte(n), s:byte(1)
  local ink = sum - (adv[last] or 5) + (xb[last] or 0) + (iw[last] or 0) - (xb[first] or 0)
  return sum, ink
end
W.measure = measure
function W.extents(s) local _, ink = measure(s) return ink end

-- the self-check against cairo's own numbers for whole strings (called by the test)
function W.self_check()
  local bad = {}
  for _, c in ipairs(cairo_checks) do
    local got = W.extents(c.s)
    if math.abs(got - c.w) > 0.01 then bad[#bad + 1] = string.format("%q: cairo %.2f, table %.2f", c.s, c.w, got) end
  end
  return bad
end

local recs, cx, cy = {}, 0, 0
local face, size = 1, 8
W.fonts_used = {}

function W.install()
  local s = setmetatable({}, {__index = function() return function() end end})
  s.clear = function() recs = {} end
  s.move = function(x, y) cx, cy = x, y end
  s.rel_move = function(dx, dy) cx, cy = cx + dx, cy + dy end
  s.font_face = function(f) face = f end
  s.font_size = function(z) size = z end
  s.text_extents = function(t) return W.extents(tostring(t)) end
  s.text = function(t)
    t = tostring(t)
    local a, ink = measure(t)
    recs[#recs + 1] = {s = t, x = cx, y = cy, w = ink, kind = "left", face = face, size = size}
    cx = cx + a
  end
  s.text_right = function(t)
    t = tostring(t)
    local _, ink = measure(t)
    recs[#recs + 1] = {s = t, x = cx - ink, y = cy, w = ink, kind = "right", face = face, size = size}
  end
  s.text_center = function(t)
    t = tostring(t)
    local _, ink = measure(t)
    recs[#recs + 1] = {s = t, x = cx - ink / 2, y = cy, w = ink, kind = "center", face = face, size = size}
  end
  screen = s
  return s
end

function W.clear() recs = {} end
function W.records() return recs end

-- what is wrong with the last redraw: lines of text
function W.violations()
  local bad = {}
  for _, r in ipairs(recs) do
    if r.w > 0 then
      if r.x < -0.5 then bad[#bad + 1] = string.format("%q starts at x=%.1f (left of the screen)", r.s, r.x) end
      if r.x + r.w > 128.5 then bad[#bad + 1] = string.format("%q ends at x=%.1f (right of the screen, width %.0f, %s at %s)", r.s, r.x + r.w, r.w, r.kind, tostring(r.y)) end
    end
  end
  for i = 1, #recs do
    for j = i + 1, #recs do
      local a, b = recs[i], recs[j]
      -- the same text drawn twice at the same place is one text (a page that repeats a block: no visible effect)
      if a.y == b.y and a.w > 0 and b.w > 0 and not (a.s == b.s and a.x == b.x) then
        local a0, a1, b0, b1 = a.x, a.x + a.w, b.x, b.x + b.w
        if a0 < b1 + 1 and b0 < a1 + 1 then
          bad[#bad + 1] = string.format("%q [%.0f..%.0f] and %q [%.0f..%.0f] overlap on the row at y=%s", a.s, a0, a1, b.s, b0, b1, tostring(a.y))
        end
      end
    end
  end
  return bad
end

return W
