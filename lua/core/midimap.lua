-- MIDI MAP on a computer (Linux desktop): turns MIDI messages into the keys K1-K3 and encoders E1-E3 of the norns screen, and learns the mappings. docs/port/midi-map-plan.md 2.
-- a TAP: lua/core/midi.lua calls `norns.midimap.event(device, data)` after the script's handlers and the params MAP have had the message; this layer removes nothing, so scripts always
-- receive every message, mapped or not. the params MAP wins a CC that both want (settings: on_clash). the keys and encoders go out the way the computer keyboard's do
-- (lua/core/keyboard.lua): _norns.show_control, then _norns.key / _norns.enc, so the window shows the key and the knob move. the numbers are core/midimap_value.lua, the settings
-- core/midimap_settings.lua, the page core/menu/midimap.lua.
--
-- learn: start_pick (the page's LEARN: the window is armed, a click on E1-E3 / K1-K3 is a pick, not a key), pick(id), then LISTEN for the first CC (or, for a key, a note on) of a device that is
-- a controller; an encoder then listens for a few more messages of that CC to suggest its format (confirm). a time-out, cancel, leaving the page or a device change end it.

local V = require 'core/midimap_value'
local S = require 'core/midimap_settings'

local M = {enabled = os.getenv("NORNS_PLATFORM") ~= nil}

M.IDS = S.IDS
M.ALL_IDS = S.ALL_IDS
M.TIMEOUT = 15   -- seconds of nothing in PICK or LISTEN
M.CONFIRM_MSGS = 6 -- messages of the learned CC that the suggestion looks at (the first included)
M.CONFIRM_SILENCE = 3 -- seconds
M.clock = function() return util.time() end
M.learn = {state = "idle"}
M.guess = {}      -- id -> true while the mode of an encoder is a suggestion from learn (the page shows a ?)
M.on_change = nil -- the page's redraw: called when something the page shows changed without a key (a time-out, a result)
M.log = function(s) print("midimap: " .. s) end

local rt = {}     -- per control: {abs, rel, key, src, dev}
local seen_version

local function is_enc(id) return id:sub(1, 1) == "e" end
local function is_arc(id) return id:sub(1, 1) == "a" end
local function is_knob(id) return id:sub(1, 1) ~= "k" end -- a norns encoder or an arc encoder: takes a CC, not a note
local function number_of(id) return tonumber(id:sub(2)) end
--- the id the window uses for a control (device_skin.h: K1-K3 are 1-3, E1-E3 are 4-6; the arc's encoders 1-4 are 7-10)
local function skin_id(id) return (is_enc(id) and 3 or is_arc(id) and 6 or 0) + number_of(id) end

local function state_of(id)
  local r = rt[id]
  if r == nil then
    r = {abs = V.abs_new(), rel = V.rel_new(), key = V.key_new(), arc = V.arc_new(), src = nil, dev = nil}
    rt[id] = r
  end
  return r
end

local function send_key(n, z)
  if _norns.show_control then _norns.show_control(1, n, z) end
  _norns.key(n, z)
end

local function send_enc(n, d)
  if _norns.show_control then _norns.show_control(2, n, d) end
  _norns.enc(n, d)
end

local function toast(text)
  if _norns.toast then _norns.toast(text) end
end

local function notify() if M.on_change then M.on_change() end end

--- release every key this layer holds down (the mapping changed, the device went, learn began, the page closed)
function M.release_all()
  for _, id in ipairs(M.IDS) do
    local r = rt[id]
    if r and V.key_held(r.key) then
      V.key_reset(r.key)
      send_key(number_of(id), 0)
    end
  end
end

--- the ids of the keys held down by this layer (for tests and for the page)
function M.held()
  local out = {}
  for _, id in ipairs(M.IDS) do
    local r = rt[id]
    if r and V.key_held(r.key) then out[#out + 1] = id end
  end
  return out
end

local function reset_states()
  for _, id in ipairs(M.ALL_IDS) do
    local r = rt[id]
    if r then
      V.abs_reset(r.abs); V.rel_reset(r.rel); V.key_reset(r.key); V.arc_reset(r.arc); r.src, r.dev = nil, nil
    end
  end
end

--- a change in the settings (any set, clear, preset, load) releases what is held and starts the values again
local function push_arc_config()
  if _norns.arc_keys_config then _norns.arc_keys_config(S.state.arc_keys_accel and 1 or 0) end
end

local function sync()
  if seen_version ~= S.version then
    push_arc_config()
    M.release_all()
    reset_states()
    seen_version = S.version
  end
end
M.changed = sync

function M.load()
  M.cancel_quiet()
  S.load()
  rt = {}
  M.guess = {}
  seen_version = S.version
  push_arc_config()
end

-- ---------------------------------------------------------------- the params MAP
local function pmap_learning()
  return norns ~= nil and norns.pmap ~= nil and norns.pmap.learning ~= nil and norns.pmap.learning() == true
end

local function param_name(pid)
  local ok, p = pcall(function() return params:lookup_param(pid) end)
  if ok and type(p) == "table" and p.name then return tostring(p.name) end
  return tostring(pid)
end

--- the controls whose CC is also in the params MAP of the loaded script: a list of {id, cc, param, name}. with on_clash=both there is nothing to warn about
function M.clashes()
  local out = {}
  if S.state.on_clash ~= "params" or norns == nil or norns.pmap == nil then return out end
  for _, id in ipairs(M.ALL_IDS) do
    local c = S.state.ctl[id]
    if c.type == "cc" and c.num ~= nil then
      for pid, p in pairs(norns.pmap.data or {}) do
        if p.cc == c.num and (c.ch == 0 or p.ch == c.ch) then
          local vp = midi and midi.vports and midi.vports[p.dev]
          local name = vp and vp.name or ""
          local dev_ok
          if c.dev == "ANY" then dev_ok = not V.is_non_controller(name) else dev_ok = V.name_matches(c.dev, name) end
          if dev_ok then
            out[#out + 1] = {id = id, cc = c.num, param = pid, name = param_name(pid)}
            break
          end
        end
      end
    end
  end
  return out
end

function M.clash_short(item)
  return string.format("%s CC%d: PARAMS MAP WINS", item.id:upper(), item.cc)
end

function M.clash_text(item)
  return string.format("%s: CC %d IS IN THE PARAMS MAP (%s). THE PARAMS MAP GETS IT.", item.id:upper(), item.cc, tostring(item.name):upper())
end

--- after a script loaded (hook script_post_init): its params MAP may use a CC of a control. one log line each, one toast
function M.after_script_load()
  local list = M.clashes()
  if #list == 0 then return end
  local script = norns and norns.state and norns.state.shortname or "the script"
  for _, item in ipairs(list) do
    M.log(string.format("%s: CC %d is in the params map of %s (%s), left to the script", item.id:upper(), item.cc, script, item.param))
  end
  local text = M.clash_text(list[1])
  if #list > 1 then text = text .. " +" .. (#list - 1) .. " MORE" end
  toast(text)
end

--- the settings the keyboard module asks for (lua/core/keyboard.lua, the arc keys)
function M.arc_keys_on() return S.state.arc_keys ~= false end
function M.arc_keys_ramp() return S.state.arc_keys_accel == true end

--- put it in the script hook list (once, at start), and answer the window's click on a control while a pick is armed (sdl_bridge.cc: _norns.midimap_pick("e" or "k", n))
function M.install()
  _norns.midimap_pick = function(kind, n)
    local ok, err = pcall(function()
      if kind == "x" then
        if M.learn.state == "pick" then M.cancel() end -- a click on nothing ends a pick (not a listen: a stray click must not lose a nearly done learn)
      else
        M.pick(tostring(kind) .. tostring(n))
      end
    end)
    if not ok then M.log("pick: " .. tostring(err)) end
  end
  if hook and hook.script_post_init and hook.script_post_init.register then
    hook.script_post_init:register("midimap-clash", function() local ok, err = pcall(M.after_script_load) if not ok then M.log("load check: " .. tostring(err)) end end)
  end
end

-- ---------------------------------------------------------------- the virtual arc (docs/port/arc-plan.md)
local arc_told = false -- the closed window was said once (reset when a turn gets through)

--- turn a ring of the virtual arc window by ticks (the same path as the mouse); the window being closed is said once and nothing else happens. a build without the call does nothing
local function send_arc(n, ticks)
  if not _norns.arc_turn then return end
  if _norns.arc_turn(n, ticks) then
    arc_told = false
  elseif not arc_told then
    arc_told = true
    toast("ARC WINDOW IS CLOSED: F8")
  end
end

-- ---------------------------------------------------------------- two controls on one message
--- the message a control answers to as a comparable kind: "cc" or "note", and its number, or nil for an empty control
local function kind_of(c)
  if c.type == "none" or c.num == nil then return nil end
  return c.type
end

--- the control (other than `id`) that would also answer to a CC or note with this device and channel filter, or nil
function M.find_overlap(id, type_, num, dev, ch)
  for _, other in ipairs(M.ALL_IDS) do
    local c = S.state.ctl[other]
    if other ~= id and kind_of(c) == type_ and c.num == num and V.dev_overlap(c.dev, dev) and V.ch_overlap(c.ch, ch) then return other end
  end
  return nil
end

--- id -> the other control it shares a message with (both directions), for the ! marks
function M.overlaps()
  local out = {}
  for _, id in ipairs(M.ALL_IDS) do
    local c = S.state.ctl[id]
    local k = kind_of(c)
    if k then
      local other = M.find_overlap(id, k, c.num, c.dev, c.ch)
      if other then out[id] = other end
    end
  end
  return out
end

-- ---------------------------------------------------------------- WATCH: which relative format does a unit send?
M.watching = false
local watch = V.watch_new()

function M.watch_start() watch = V.watch_new(); M.watching = true end
function M.watch_stop() M.watching = false end
function M.watch_view() return V.watch_view(watch) end

-- ---------------------------------------------------------------- ONE TURN: the gain of an arc encoder from one turn of its knob
local calib = nil

function M.calib_start(id)
  if S.state.ctl[id] == nil or not is_arc(id) then return false end
  M.release_all()
  calib = {id = id, units = 0, abs = V.abs_new(), src = nil}
  return true
end

function M.calib_units() return calib and calib.units or nil end
function M.calib_target() return calib and calib.id or nil end

function M.calib_cancel() calib = nil end

--- the end of ONE TURN: the gain from the size of the turn (its direction does not matter), stored; nil if nothing was counted
function M.calib_finish()
  if calib == nil then return nil end
  local id, units = calib.id, math.abs(calib.units)
  calib = nil
  local g = V.gain_from_turn(units)
  if g then S.set(id, "gain", g) end
  return g
end

-- ---------------------------------------------------------------- learn
local function window(arm, state, id)
  if _norns.midimap_arm then _norns.midimap_arm(arm) end
  if _norns.midimap_show then _norns.midimap_show(state, id and skin_id(id) or 0) end
end

local timer
local function timer_stop()
  if timer then pcall(function() timer:stop() end) end
end
local function timer_start()
  if metro and metro.init then
    if timer == nil then timer = metro.init(function() M.tick() end, 0.25, -1) end
    timer:start()
  end
end

local function end_learn()
  local L = M.learn
  L.state, L.target, L.msgs, L.src, L.ask = "idle", nil, nil, nil, nil
  timer_stop()
  window(0, 0, nil)
  notify()
end

function M.cancel_quiet()
  if M.learn.state ~= "idle" then end_learn() end
end

--- cancel (a time-out, the K2 key, leaving): nothing changes, the window is released
function M.cancel(msg)
  if M.learn.state == "idle" then return end
  end_learn()
  M.learn.msg = msg or "LEARN STOPPED"
  notify()
end

--- leaving the page: no learn, no held key
function M.leave()
  M.cancel_quiet()
  calib = nil
  M.watching = false
  M.learn.msg, M.learn.warn = nil, nil
  M.release_all()
end

local function listen_text(id)
  return is_knob(id) and "MOVE A KNOB" or "PRESS A BUTTON"
end

--- the text of the question when the CC a control was given is used by another control
function M.ask_text()
  local a = M.learn.ask
  if a == nil then return nil end
  return string.format("%s %d IS %s. MOVE IT TO %s?", a.type == "note" and "NOTE" or "CC", a.num, a.other:upper(), a.id:upper())
end

function M.start_pick()
  M.release_all()
  local L = M.learn
  L.state, L.target, L.deadline, L.msg, L.warn = "pick", nil, M.clock() + M.TIMEOUT, nil, nil
  window(1, 1, nil)
  toast("LEARN: CLICK A CONTROL")
  timer_start()
  notify()
end

--- the click on a control in the window (or the page's own choice): the target of the learn
function M.pick(id)
  local L = M.learn
  if L.state ~= "pick" and L.state ~= "listen" then return end
  if S.state.ctl[id] == nil then return end
  L.state, L.target, L.deadline, L.msg, L.warn = "listen", id, M.clock() + M.TIMEOUT, nil, nil
  window(1, 2, id)
  toast("LEARN " .. id:upper() .. ": " .. listen_text(id))
  notify()
end

--- LEARN inside a control's detail view: straight to LISTEN
function M.start_listen(id)
  M.release_all()
  M.learn.state = "pick"
  M.pick(id)
  timer_start()
end

local function warn_for(id)
  for _, item in ipairs(M.clashes()) do
    if item.id == id then
      M.learn.warn = M.clash_text(item)
      M.learn.warn_short = M.clash_short(item)
      toast(M.learn.warn)
      return
    end
  end
  M.learn.warn, M.learn.warn_short = nil, nil
end

local MODE_NAMES = {abs = "ABS", rel2c = "REL 2S", relsm = "REL SIGN", relob = "REL OFS"}
M.MODE_NAMES = MODE_NAMES

--- the end of the confirmation of an encoder: the suggestion, if there is one
function M.finish_confirm()
  local L = M.learn
  if L.state ~= "confirm" then return end
  local id = L.target
  local sug, why = V.suggest(L.msgs or {})
  local text
  if sug then
    S.set(id, "mode", sug)
    M.guess[id] = true
    text = "MODE " .. MODE_NAMES[sug] .. "? CHECK IT"
  else
    text = why
  end
  end_learn()
  M.learn.msg = text
  notify()
end

local function assigned(id, what)
  M.guess[id] = nil
  warn_for(id)
  M.learn.msg = id:upper() .. " = " .. what
end

--- the learned message goes to the control; if another control already answers to it the question is asked first (K3 yes / K2 no on the page, M.answer)
local function take(id, type_, num, first)
  local other = M.find_overlap(id, type_, num, "ANY", 0)
  if other then
    local L = M.learn
    L.state, L.ask, L.deadline = "ask", {id = id, other = other, type = type_, num = num, first = first}, M.clock() + M.TIMEOUT
    window(0, 2, id)
    L.msg = nil
    notify()
    return false
  end
  return true
end

--- the answer to the question: yes clears the other control and goes on, no (or cancel) leaves everything as it was
function M.answer(yes)
  local L = M.learn
  if L.state ~= "ask" or L.ask == nil then return end
  local a = L.ask
  if not yes then
    M.cancel("LEARN STOPPED")
    return
  end
  M.clear(a.other)
  L.ask = nil
  local id = a.id
  S.assign(id, a.type, a.num)
  if is_knob(id) then
    L.state, L.msgs, L.src, L.last = "confirm", {a.first}, L.src, M.clock()
    window(0, 2, id)
    assigned(id, "CC " .. a.num)
    L.msg = "TURN IT BOTH WAYS"
  else
    end_learn()
    assigned(id, (a.type == "note" and "NOTE " or "CC ") .. a.num)
  end
  notify()
end

local function learn_event(d, kind, ch, d1, d2)
  local L = M.learn
  if L.state == "pick" or L.state == "ask" then return end
  if V.is_non_controller(d.name) then return end
  if L.state == "listen" then
    local id = L.target
    if is_knob(id) then
      if kind ~= 0xB0 then
        if kind == 0x90 and d2 > 0 then
          L.msg = "A NOTE? USE A CC"
          notify()
        end
        return
      end
      L.src = {dev = d.name, ch = ch, cc = d1}
      if not take(id, "cc", d1, d2) then return end
      S.assign(id, "cc", d1)
      L.state, L.msgs, L.last = "confirm", {d2}, M.clock()
      window(0, 2, id)
      assigned(id, "CC " .. d1)
      L.msg = "TURN IT BOTH WAYS"
      notify()
    else
      if kind == 0xB0 and d2 > 0 then
        if not take(id, "cc", d1) then return end
        S.assign(id, "cc", d1)
        end_learn()
        assigned(id, "CC " .. d1)
      elseif kind == 0x90 and d2 > 0 then
        if not take(id, "note", d1) then return end
        S.assign(id, "note", d1)
        end_learn()
        assigned(id, "NOTE " .. d1)
      else
        return
      end
      notify()
    end
  elseif L.state == "confirm" then
    local s = L.src
    if kind == 0xB0 and d1 == s.cc and d.name == s.dev and ch == s.ch then
      L.msgs[#L.msgs + 1] = d2
      L.last = M.clock()
      if #L.msgs >= M.CONFIRM_MSGS then M.finish_confirm() end
    end
  end
end

--- once in a while (the learn's metro, or a test): the time-outs
function M.tick()
  local L = M.learn
  local now = M.clock()
  if (L.state == "pick" or L.state == "listen" or L.state == "ask") and now > L.deadline then
    M.cancel("LEARN STOPPED")
  elseif L.state == "confirm" and now - L.last > M.CONFIRM_SILENCE then
    M.finish_confirm()
  elseif L.state ~= "idle" then
    notify() -- the countdown on the page
  end
end

--- the seconds left of a PICK or LISTEN (0 when there is no time-out)
function M.seconds_left()
  local L = M.learn
  if L.state ~= "pick" and L.state ~= "listen" and L.state ~= "ask" then return 0 end
  return math.max(0, math.ceil(L.deadline - M.clock()))
end

--- a device went away: what it held is released, and a learn is over
function M.device_removed(d)
  if d == nil then return end
  calib = nil
  for _, id in ipairs(M.IDS) do
    local r = rt[id]
    if r and r.dev == d.id and V.key_held(r.key) then
      V.key_reset(r.key)
      send_key(number_of(id), 0)
    end
  end
  if M.learn.state ~= "idle" then M.cancel("LEARN STOPPED") end
end

function M.clear(id)
  local ok, why = S.clear(id)
  if ok then M.guess[id] = nil; sync() end
  return ok, why
end

-- ---------------------------------------------------------------- the messages
local function matches(c, d, ch)
  if c.ch ~= 0 and c.ch ~= ch then return false end
  if c.dev == "ANY" then return not V.is_non_controller(d.name) end
  return V.name_matches(c.dev, d.name)
end

local function act(d, kind, ch, d1, d2)
  local pm = norns ~= nil and norns.pmap ~= nil and norns.pmap.rev or nil
  local params_wins = S.state.on_clash == "params"
  for _, id in ipairs(M.ALL_IDS) do
    local c = S.state.ctl[id]
    if c.type ~= "none" and c.num == d1 and matches(c, d, ch) then
      if kind == 0xB0 and c.type == "cc" then
        local taken = params_wins and pm ~= nil and d.port ~= nil and pm[d.port] ~= nil and pm[d.port][ch] ~= nil and pm[d.port][ch][d1] ~= nil
        if not taken then
          local r = state_of(id)
          if is_arc(id) then
            local src = d.name .. "/" .. ch
            if r.src ~= src then V.abs_reset(r.abs); V.arc_reset(r.arc); r.src = src end
            local units
            if c.mode == "abs" then units = V.abs_delta(r.abs, d2, M.clock()) else units = V.rel_decode(c.mode, d2) end
            local n = V.arc_step(r.arc, units, c.gain, c.accel, M.clock())
            if n ~= 0 then send_arc(number_of(id), n) end
          elseif is_enc(id) then
            local src = d.name .. "/" .. ch
            if r.src ~= src then V.abs_reset(r.abs); V.rel_reset(r.rel); r.src = src end
            local n
            if c.mode == "abs" then n = V.abs_step(r.abs, d2, c.sens, M.clock())
            else n = V.rel_step(r.rel, c.mode, d2, c.sens) end
            if n ~= 0 then send_enc(number_of(id), n) end
          else
            local what = V.key_cc(r.key, d2, c.threshold)
            r.dev = d.id
            if what == "press" then send_key(number_of(id), 1) elseif what == "release" then send_key(number_of(id), 0) end
          end
        end
      elseif (kind == 0x90 or kind == 0x80) and c.type == "note" and id:sub(1, 1) == "k" then
        local r = state_of(id)
        local what = V.key_note(r.key, kind == 0x90 and "on" or "off", d2)
        r.dev = d.id
        if what == "press" then send_key(number_of(id), 1) elseif what == "release" then send_key(number_of(id), 0) end
      end
    end
  end
end

--- one MIDI message from a device (lua/core/midi.lua calls this after everything else; the caller catches errors). data = the bytes
function M.event(d, data)
  if not M.enabled or d == nil or data == nil then return end
  local status = data[1]
  if status == nil or status >= 0xF0 or status < 0x80 then return end -- realtime and system messages are never looked at
  local kind = status - status % 16
  if kind ~= 0xB0 and kind ~= 0x90 and kind ~= 0x80 then return end
  local d1 = data[2]
  if d1 == nil then return end
  local d2 = data[3] or 0
  local ch = status % 16 + 1
  sync()
  if M.watching then
    if kind == 0xB0 and d.name ~= nil then V.watch_add(watch, d.name, ch, d1, d2); notify() end
    return
  end
  if calib ~= nil then
    local c = S.state.ctl[calib.id]
    if kind == 0xB0 and c.type == "cc" and c.num == d1 and matches(c, d, ch) then
      local src = d.name .. "/" .. ch
      if calib.src ~= src then V.abs_reset(calib.abs); calib.src = src end
      calib.units = calib.units + (c.mode == "abs" and V.abs_delta(calib.abs, d2, M.clock()) or V.rel_decode(c.mode, d2))
      notify()
    end
    return
  end
  if M.learn.state ~= "idle" then
    learn_event(d, kind, ch, d1, d2)
    return
  end
  if pmap_learning() then return end
  act(d, kind, ch, d1, d2)
end

return M
