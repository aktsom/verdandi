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
    -- M3 first: it needs no scsynth, and a slow SuperCollider start must not decide whether it runs
    -- M3: the input switch on a machine that may have no input at all (the CI runner): MIC and SYS must say no or yes, never hang or crash, and OFF must always work
    if os.getenv("VERDANDI_SMOKE_INPUT") == "1" and _norns.mic_input then
      local function state(what, ok)
        local s2, why = _norns.audio_input()
        print(string.format("VERDANDI_SMOKE_INPUT %s ok=%s state=%s note=[%s]", what, tostring(ok), s2, why))
      end
      state("start", true)
      state("mic", _norns.mic_input(true))
      _norns.mic_input(false)
      state("sys", _norns.app_input("system"))
      clock.sleep(2)
      state("sys-2s", true)
      _norns.app_input(nil)
      state("off", true)
      _norns.audio_measure()
      clock.sleep(1)
      print("VERDANDI_SMOKE_INPUT measured=" .. tostring(_norns.audio_info().measured_ms))
      -- the AUDIO page's live apply with a device that does not exist: an answer, never a hang, and the script (this one) runs on
      if _norns.audio_apply then
        local rc, msg = _norns.audio_apply("output=wasapi:No Such Speakers 4711\nbuffer=auto\n")
        print(string.format("VERDANDI_SMOKE_APPLY rc=%s msg=[%s]", tostring(rc), tostring(msg)))
        clock.sleep(1)
        print("VERDANDI_SMOKE_APPLY after: mode=" .. tostring(_norns.audio_info().mode))
      end
      print("VERDANDI_SMOKE_INPUT_DONE")
    end
    -- M4: the MIDI layer on a machine that may have no MIDI device (the CI runner): the status table, the OSC route through the real loopback of the machine, and Ableton Link switched on and off
    if os.getenv("VERDANDI_SMOKE_INPUT") == "1" and _norns.midi_status then
      local st = _norns.midi_status()
      print("VERDANDI_SMOKE_MIDI status " .. st:gsub("\n", " | "))
      if _norns.grid_status then print("VERDANDI_SMOKE_GRID status [" .. _norns.grid_status():gsub("\n", " | ") .. "]") end
      local rc, why = _norns.midi_route_test("osc", "")
      print("VERDANDI_SMOKE_MIDI osc-start rc=" .. tostring(rc) .. " " .. tostring(why))
      for _ = 1, 20 do
        clock.sleep(0.5)
        local state = _norns.midi_status():match("route_state=(%w+)")
        if state == "done" or state == "failed" then break end
      end
      print("VERDANDI_SMOKE_MIDI osc-route " .. tostring(_norns.midi_status():match("route=([^\n]*)")))
      -- Link: on, a moment for the network, the numbers, off. no other peer on the runner is expected: it must only start and stop without a crash
      clock.set_source("link")
      clock.sleep(2)
      local li = _norns.link_info()
      print(string.format("VERDANDI_SMOKE_MIDI link peers=%d tempo=%.1f latency_ms=%.1f", li.peers, li.tempo, li.latency_ms))
      clock.set_source("internal")
      print("VERDANDI_SMOKE_MIDI done")
    end
    -- M6: the tools scripts use through os.execute / io.popen (busybox sh, git from the program's PATH)
    if os.getenv("VERDANDI_SMOKE_INPUT") == "1" and _norns.midi_status then
      local function sh(cmd) local p = io.popen(cmd .. " 2>&1"); local t = p and p:read("a") or ""; if p then p:close() end; return (t:gsub("%s+$", "")) end
      print("VERDANDI_SMOKE_TOOLS git [" .. sh("git --version") .. "]")
      local d = "/home/we/dust/data/verdandi_smoke"
      sh("echo same > " .. d .. "/t1 && cp " .. d .. "/t1 " .. d .. "/t2")
      local cmpout = sh("cmp " .. d .. "/t1 " .. d .. "/t2 && echo CMP_SAME")
      print("VERDANDI_SMOKE_TOOLS busybox " .. (cmpout:find("CMP_SAME") and "ok" or ("FAIL [" .. cmpout .. "] ls: [" .. sh("ls " .. d):gsub("\n", " ") .. "]")))
      print("VERDANDI_SMOKE_TOOLS applets [" .. sh("busybox --list"):gsub("%s+", " ") .. "]")
      local r = d .. "/subtest"
      sh("mkdir -p " .. r .. " && cd " .. r .. " && git init -q sub && cd sub && echo s > s.txt && git add s.txt && git -c user.name=t -c user.email=t@t commit -q -m s && cd .. && git init -q top && cd top && git -c protocol.file.allow=always submodule add -q ../sub voice && git -c user.name=t -c user.email=t@t commit -q -m t && cd .. && git -c protocol.file.allow=always clone -q --recurse-submodules top copy")
      print("VERDANDI_SMOKE_TOOLS submodule " .. (sh("cat " .. r .. "/copy/voice/s.txt"):find("^s") and "ok" or "FAIL: " .. sh("ls " .. r .. "/copy")))
      -- M9 (docs/port/phase-m9.md): the installer of the script twins, UNCHANGED (fetched by the workflow), against the real tools: its library check (find -printf, rewritten), its update check (nice, timeout, git against a
      -- clone that is one commit behind), the pull, and its restart request (sudo systemctl restart norns-*). run beside the rest of the smoke test, not in front of it
      if util.file_exists(d .. "/installer.lua") then
        clock.run(function()
          local T = d .. "/twins"
          print("VERDANDI_SMOKE_TWINS git-config [" .. sh("git config --show-origin core.autocrlf"):gsub("\n", " ") .. "]")
          sh("rm -rf " .. T .. " && mkdir -p " .. T .. " && cd " .. T .. " && git init -q --bare origin.git && git clone -q origin.git work && cd work && git config user.name t && git config user.email t@t && mkdir -p lib && echo 'engine { }' > lib/engine_x.sc && echo 'print(1)' > twins.lua && git add -A && git commit -q -m one && git push -q -u origin HEAD && cd .. && git clone -q origin.git clone")
          print("VERDANDI_SMOKE_TWINS clone-status [" .. sh("git -C " .. T .. "/clone status --porcelain --untracked-files=no | wc -l"):gsub("%s+", "") .. "]")
          local Installer = dofile(d .. "/installer.lua")
          local I = Installer:new{requirements = {"AnalogChew", "AnalogLoss", "AnalogDegrade"}, zip = "https://example.invalid/x.zip", path = T .. "/clone"}
          print("VERDANDI_SMOKE_TWINS library-check satisfied=" .. tostring(I:ready()) .. " missing=[" .. table.concat(I.missing_requirements or {}, ",") .. "]")
          print("VERDANDI_SMOKE_TWINS find-printf [" .. sh("find " .. T .. "/clone -maxdepth 1 -name 'twins.lua' -type f -printf '%p!'") .. "]")
          print("VERDANDI_SMOKE_TWINS nice [" .. sh("nice -n 19 echo niced") .. "]")
          print("VERDANDI_SMOKE_TWINS sudo [" .. sh("sudo echo sudoed") .. "]")
          print("VERDANDI_SMOKE_TWINS timeout-nice [" .. sh("timeout -k 5 20 nice -n 19 git --version") .. "]")
          -- up to date: no prompt
          I:check()
          local t0 = util.time()
          while I.update.state == "checking" and util.time() - t0 < 60 do clock.sleep(0.5) end
          print("VERDANDI_SMOKE_TWINS check-uptodate state=" .. tostring(I.update.state) .. " behind=" .. tostring(I.update.behind))
          -- the author pushes a commit that changes an engine file
          print("VERDANDI_SMOKE_TWINS push-two [" .. sh("cd " .. T .. "/work && echo 'engine { var two; }' > lib/engine_x.sc && git add -A && git commit -q -m two && git push -q"):gsub("\n", " ") .. "]")
          print("VERDANDI_SMOKE_TWINS behind-manual [" .. sh("git -C '" .. T .. "/clone' fetch --quiet; echo B$(git -C '" .. T .. "/clone' rev-list --count HEAD..@{u} 2>&1); git -C '" .. T .. "/clone' log --oneline -3 origin/HEAD 2>&1; git -C '" .. T .. "/origin.git' log --oneline -3 2>&1"):gsub("\n", " | ") .. "]")
          I.update.state = nil
          I:check()
          t0 = util.time()
          while I.update.state == "checking" and util.time() - t0 < 60 do clock.sleep(0.5) end
          print("VERDANDI_SMOKE_TWINS check-behind state=" .. tostring(I.update.state) .. " behind=" .. tostring(I.update.behind))
          -- a tracked file with a local change: no prompt (the author's pull would conflict)
          sh("cd " .. T .. "/clone && echo '-- mine' >> twins.lua")
          I.update.state = nil
          I:check()
          t0 = util.time()
          while I.update.state == "checking" and util.time() - t0 < 60 do clock.sleep(0.5) end
          print("VERDANDI_SMOKE_TWINS check-dirty state=" .. tostring(I.update.state))
          sh("cd " .. T .. "/clone && git checkout -- twins.lua")
          print("VERDANDI_SMOKE_TWINS clean-again [" .. sh("git -C " .. T .. "/clone status --porcelain --untracked-files=no | wc -l"):gsub("%s+", "") .. "]")
          -- K3: pull
          I.update.state = "update"
          I:key(3, 1)
          t0 = util.time()
          while (I.update.state == "update" or I.update.state == "installing") and util.time() - t0 < 90 do clock.sleep(0.5) end
          print("VERDANDI_SMOKE_TWINS pull state=" .. tostring(I.update.state) .. " behind_now=" .. tostring(I:count_behind()))
          print("VERDANDI_SMOKE_TWINS after-pull-status [" .. sh("git -C " .. T .. "/clone status --porcelain --untracked-files=no | wc -l"):gsub("%s+", "") .. "] file [" .. sh("cat " .. T .. "/clone/lib/engine_x.sc") .. "]")
          -- K3 again: the restart request of the installer (sudo systemctl restart norns-...), taken back at once so that this run goes on
          local t1 = util.time()
          I:do_restart()
          local req = io.open("/home/we/.norns-request-restart")
          print(string.format("VERDANDI_SMOKE_TWINS restart returned_in=%.1fs request_file=%s", util.time() - t1, tostring(req ~= nil)))
          if req then req:close(); os.remove("/home/we/.norns-request-restart") end
          print("VERDANDI_SMOKE_TWINS done")
        end)
      end
    end
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
      print(string.format("VERDANDI_SMOKE_AUDIO mode=%s device=[%s] api=[%s] host_apis=[%s] input=%s rate=%d frames=%d out_latency_ms=%.1f scsynth=%s blocks_to_scsynth=%d blocks_from_scsynth=%d underruns=%d drops=%d",
        a.mode, a.device, a.host_api, a.host_apis, a.input, a.rate, a.frames, a.out_latency_ms, tostring(a.scsynth), a.to_scsynth - a0.to_scsynth, a.from_scsynth - a0.from_scsynth, a.underruns, a.drops))
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
