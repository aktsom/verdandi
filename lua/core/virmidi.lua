-- Linux desktop: the guided setup of the ALSA raw MIDI route for Reaper (docs/port/RUN-ON-LAPTOP.md, manual "A DAW that reads ALSA MIDI only"). Reaper on Linux lists raw hw: MIDI devices and no sequencer ports, so
-- "Verdandi out" (the ALSA sequencer port of the virtual MIDI device) is subscribed to the sequencer port of the kernel's virtual MIDI card (snd-virmidi), which Reaper reads as the raw device hw:VirMIDI. the subscription is
-- made by norns when alsa_midi_out_to= is set (matron/src/platform/linux/aseq_link.h, aseq_out.cc); this file is what the screen says and does around it: whether the module is loaded, the notes, the load without a terminal
-- (polkit's pkexec: a password dialog of the desktop, never sudo; the command to type when that cannot be done), the Reaper entry to enable, and how to keep it after a reboot.
-- everything that touches the system is a field that the tests replace (exec, read, write, remove, now, have, is_root, exists).
local M = {}

M.COMMAND = "sudo modprobe snd-virmidi midi_devs=1" -- what to type in a terminal
M.STATUS = "/home/we/.virmidi-load"                  -- written when the load is started (its time)
M.DONE = "/home/we/.virmidi-done"                    -- written by the background command: its exit code
local PATIENCE = 150                                  -- seconds a load may take (the password dialog is a person)

function M.exec(cmd)
  local ok = os.execute(cmd)
  return ok == true or ok == 0
end
function M.read(p)
  local f = io.open(p)
  if not f then return nil end
  local t = f:read("a")
  f:close()
  return t
end
function M.write(p, text)
  local f = io.open(p, "w")
  if not f then return false end
  f:write(text)
  f:close()
  return true
end
function M.remove(p) os.remove(p) end
function M.now() return os.time() end
function M.have(prog) return M.exec("command -v " .. prog .. " > /dev/null 2>&1") end
function M.is_root()
  local f = io.popen("id -u 2> /dev/null")
  local u = f and f:read("l")
  if f then f:close() end
  return u == "0"
end
function M.exists(p)
  local f = io.open(p .. "/initstate")
  if f then f:close() return true end
  return false
end

--- the setting: the prefix of the ALSA port that "Verdandi out" is connected to ("" = off)
function M.to()
  return ((os.getenv("NORNS_ALSA_MIDI_OUT_TO") or ""):match("^%s*(.-)%s*$"))
end
function M.configured() return M.to() ~= "" end

--- does this prefix name the virtual MIDI card (so that the module has to be loaded)?
function M.wants_module(to)
  local t = (to or ""):lower()
  return t:find("virmidi", 1, true) ~= nil or t:find("virtual raw", 1, true) ~= nil
end

function M.loaded() return M.exists("/sys/module/snd_virmidi") end

--- "VirMIDI 3-0" (what the ALSA client is called) is what to enable in Reaper; its hw form follows the device index
function M.reaper_entry(client) return client end
function M.reaper_hw(client)
  local card, dev = (client or ""):match("^VirMIDI (%d+)%-(%d+)$")
  if not card then return nil end
  return "hw:VirMIDI," .. dev
end

--- the note on the window (one line, 78 characters at most), or nil: nothing to say. t = {to, count, names, loaded, since, now}
function M.note(t)
  local to = t.to or ""
  if to == "" then return nil end
  if (t.count or 0) > 0 then
    if t.since and t.now and t.now - t.since <= 20 then
      local first = (t.names or ""):match("^[^,]+") or to
      return ("ALSA MIDI: VERDANDI OUT -> " .. first .. ". REAPER: ENABLE " .. M.reaper_entry(first)):sub(1, 78)
    end
    return nil
  end
  if M.wants_module(to) then
    if not t.loaded then return "ALSA MIDI: snd-virmidi is not loaded. SYSTEM > DEVICES > VIRMIDI" end
    return ("ALSA MIDI: no port named " .. to:sub(1, 30) .. " yet (waiting)"):sub(1, 78)
  end
  return nil
end

--- load the module without a terminal, in the background (the password dialog of the desktop must not hold norns): polkit's pkexec, or modprobe itself when norns runs as root. never sudo.
--- true: started. false: not started (loaded already, or no way to ask: then the state is "failed" and the page shows the command to type)
function M.start_load()
  if M.loaded() then return false end
  M.remove(M.DONE)
  local cmd
  if M.is_root() then
    cmd = "timeout 60 modprobe snd-virmidi midi_devs=1"
  elseif M.have("pkexec") then
    cmd = "timeout 120 pkexec modprobe snd-virmidi midi_devs=1"
  else
    M.write(M.DONE, "127\n")
    return false
  end
  M.write(M.STATUS, tostring(M.now()) .. "\n")
  M.exec("( " .. cmd .. " > /dev/null 2>&1; echo $? > " .. M.DONE .. " ) > /dev/null 2>&1 &")
  return true
end

--- "idle" (nothing was started), "running", "ok" (the command finished with 0), "failed" (a refusal, no agent, an error, no answer for two minutes)
function M.load_status()
  local done = M.read(M.DONE)
  if done then
    return (tonumber(done:match("^%s*(%d+)")) == 0) and "ok" or "failed"
  end
  local st = M.read(M.STATUS)
  if st then
    local t = tonumber(st:match("^%s*(%d+)"))
    if t and M.now() - t > PATIENCE then return "failed" end
    return "running"
  end
  return "idle"
end

function M.guide_lines()
  return {"REAPER READS RAW MIDI, NOT SEQUENCER PORTS.",
          "THE KERNEL'S VIRTUAL MIDI CARD (SND-VIRMIDI) IS THE BRIDGE.",
          "VERDANDI OUT FEEDS IT, REAPER READS IT."}
end

--- how to keep it after a reboot (the package does not do it by itself: a package should not load kernel modules or add ports to every DAW unasked)
function M.permanent_lines()
  return {"KEEP IT AFTER A REBOOT, AS ADMIN:",
          "/etc/modules-load.d/verdandi-virmidi.conf: snd-virmidi",
          "/etc/modprobe.d/verdandi-virmidi.conf: options snd-virmidi midi_devs=1 (ONE PORT IN REAPER'S LIST)",
          "THE MANUAL HAS THE COMMANDS."}
end

return M
