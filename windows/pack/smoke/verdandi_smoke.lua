-- verdandi_smoke: the script of the automatic start test (windows/ci/smoke-m1.sh). it draws, waits two seconds, saves its screen as a PNG and says so in the log.
-- it is loaded like any script: norns resumes the last script at start, and the test seeded system.state with this one.
engine.name = nil

local frames = 0

function init()
  print("VERDANDI_SMOKE init")
  clock.run(function()
    clock.sleep(2)
    -- the window keyboard must be a HID device (it was missing in the first Windows build: keys did nothing), and a key that is pressed reaches keyboard.code
    local have = false
    for _, d in pairs(hid.devices) do if d.name and d.name:find("keyboard") then have = true end end
    print("VERDANDI_SMOKE keyboard device " .. (have and "yes" or "NO"))
    local got = nil
    keyboard.code = function(key, value) got = key end
    for id, d in pairs(hid.devices) do
      if d.name and d.name:find("keyboard") then _norns.hid.event(id, 1, 30, 1) end
    end
    print("VERDANDI_SMOKE key event " .. tostring(got))
    redraw()
    screen.export_screenshot("verdandi_smoke")
    print("VERDANDI_SMOKE screenshot " .. norns.state.data .. "verdandi_smoke.png")
    print("VERDANDI_SMOKE_OK frames=" .. frames .. " clock=" .. tostring(clock.get_beats and clock.get_beats() or "n/a"))
    -- M2: the audio chain. scsynth starts a while after norns (sclang compiles first): wait for it to attach to the bridge, let some blocks flow, then say what the audio runs on and how the bridge did
    if _norns.audio_info then
      local a = _norns.audio_info()
      for _ = 1, 70 do
        if a.scsynth then break end
        clock.sleep(1)
        a = _norns.audio_info()
      end
      local a0 = a
      clock.sleep(3)
      a = _norns.audio_info()
      print(string.format("VERDANDI_SMOKE_AUDIO mode=%s device=[%s] rate=%d frames=%d latency_ms=%.1f scsynth=%s blocks_to_scsynth=%d blocks_from_scsynth=%d underruns=%d drops=%d",
        a.mode, a.device, a.rate, a.frames, a.latency_ms, tostring(a.scsynth), a.to_scsynth - a0.to_scsynth, a.from_scsynth - a0.from_scsynth, a.underruns, a.drops))
      print("VERDANDI_SMOKE_AUDIO_NOTE [" .. a.note .. "]")
    end
  end)
end

function redraw()
  frames = frames + 1
  screen.clear()
  screen.level(15)
  screen.move(8, 20)
  screen.text("verdandi windows")
  screen.level(8)
  screen.move(8, 34)
  screen.text("smoke test")
  screen.level(4)
  screen.rect(8, 44, 112, 8)
  screen.fill()
  screen.update()
end
