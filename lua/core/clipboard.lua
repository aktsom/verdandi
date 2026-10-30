-- the system clipboard for hex colour codes (docs/port/colour-picker-plan.md), Linux desktop only. copying hands the text to the window (_norns.clipboard_set, an event to the window's
-- thread: SDL's clipboard belongs to that thread); pasting asks for it (_norns.clipboard_request) and the answer comes back later as _norns.clipboard_text(text, status), from the same thread
-- through the event queue. the window reads at most 64 characters and says what it found: "ok", "empty", "long" (more than 64, the text is not given), "binary" (not plain text)
local colour = require 'core/colour'

local M = {}
M.MAX = 64
M.waiting = nil

--- is there a clipboard at all (a computer build with the window's binding)
function M.available()
  return _norns ~= nil and _norns.clipboard_set ~= nil and _norns.clipboard_request ~= nil
end

--- put a text on the clipboard: true, or false when there is no clipboard
function M.copy(text)
  if not M.available() then return false end
  _norns.clipboard_set(tostring(text))
  return true
end

--- ask for the clipboard: cb(status, text) is called once, later (never from inside this call)
function M.request(cb)
  if not M.available() then
    cb("none", "")
    return
  end
  M.waiting = cb
  _norns.clipboard_request()
end

-- the window's answer
function M.arrived(text, status)
  local cb = M.waiting
  M.waiting = nil
  if cb ~= nil then cb(status, text) end
end

--- a clipboard answer as a colour: the six digits, or nil and a short message
function M.as_colour(status, text)
  if status == "none" then return nil, "no clipboard" end
  if status == "empty" then return nil, "clipboard is empty" end
  if status == "long" then return nil, "clipboard text too long" end
  if status == "binary" then return nil, "clipboard is not text" end
  text = tostring(text or "")
  if #text > M.MAX or text:find("[%z\1-\8\11\12\14-\31\127]") then return nil, "clipboard is not a colour" end
  local hex = colour.hex(text)
  if hex == nil then return nil, "not a colour: " .. (#text > 12 and (text:sub(1, 10) .. "..") or text) end
  return hex
end

--- paste a colour: cb(hex) with the six digits, or cb(nil, message)
function M.paste_colour(cb)
  M.request(function(status, text)
    local hex, why = M.as_colour(status, text)
    cb(hex, why)
  end)
end

if _norns ~= nil then
  _norns.clipboard_text = function(text, status) M.arrived(text, status) end
end

return M
