-- start and restart cycles for the Windows CI (windows/ci/smoke-m1.sh, step m2-run-cycles). only active when VERDANDI_TEST_CYCLES=<n> is in the environment (the test sets it; nobody else does).
-- the launcher numbers the starts in VERDANDI_ROUND (1, 2, ...). Once norns has finished starting (SuperCollider answered, or the wait ran out: the failure is then in the log) this asks for a RESTART three
-- seconds later, exactly as SYSTEM > RESTART and APPLY on the AUDIO page do (norns.exe ends with exit code 42, the launcher starts everything again), until the start number reaches n: then it shuts down (SLEEP: exit code 0).
-- why not a script: _norns.restart() clears the script first and saves that, so after a restart nothing is resumed (as on a norns), and a test script that is seeded for the first start never runs again.
local M = {}

function M.settings()
  local total = tonumber(os.getenv("VERDANDI_TEST_CYCLES") or "")
  if total == nil or total < 1 then return nil end
  return total, tonumber(os.getenv("VERDANDI_ROUND") or "") or 1
end

-- settings that must survive a restart (the Windows rename bug: a second save of ui.conf was lost, the old theme came back): every round saves a brightness into ui.conf and the next round, after the restart,
-- must read exactly that value. the line VERDANDI_CYCLE_KEEP says what was wanted and what was read; the CI fails on ok=false. `ui` is the ui_settings module (a parameter for the tests)
function M.keep_value(round) return (1 + (round % 9)) / 10 end
function M.keep_check(round, ui)
  if ui == nil then
    local ok, mod = pcall(require, 'core/ui_settings')
    ui = ok and mod or nil
  end
  if ui == nil or ui.state == nil or ui.save == nil then return nil end
  local line
  if round > 1 then
    local want, got = M.keep_value(round - 1), ui.state.brightness
    line = string.format("VERDANDI_CYCLE_KEEP round=%d wanted=%.1f got=%s ok=%s", round, want, tostring(got), tostring(got ~= nil and math.abs(got - want) < 0.001))
  else
    line = "VERDANDI_CYCLE_KEEP round=1 first"
  end
  ui.state.brightness = M.keep_value(round)
  local saved = ui.save()
  return line .. " saved=" .. tostring(saved)
end

-- VERDANDI_TEST_SCRIPT_COPY=1: before every restart a script is imitated that copies the classes of the mi-UGens pack into the per-user extensions folder under another name (what the emplaitress mod did with the
-- Linux build of the pack: the same classes twice on sclang's include path, which stopped the NEXT start with "duplicate Class found"). the launcher's duplicate guard has to move that copy aside before the next
-- start. returns the line that was printed, or nil when the test is off. `exec` is os.execute (a parameter for the tests)
function M.simulate_script_copy(round, exec)
  if os.getenv("VERDANDI_TEST_SCRIPT_COPY") ~= "1" then return nil end
  exec = exec or os.execute
  local base = "/home/we/.local/share/SuperCollider/Extensions"
  local ok = exec("mkdir -p " .. base .. "/mi-UGens-copy && cp -r " .. base .. "/mi-UGens/Classes " .. base .. "/mi-UGens-copy/")
  local line = "VERDANDI_CYCLE_COPY round=" .. tostring(round) .. " ok=" .. tostring(ok == true or ok == 0)
  print(line)
  return line
end

-- kind: "ok" or "timeout" (how the start-up ended); the actions are parameters so that the logic can be tested
function M.after_startup(kind, actions)
  local total, round = M.settings()
  if total == nil then return end
  actions = actions or {}
  local sleep = actions.sleep or function(s) clock.sleep(s) end
  local run = actions.run or function(f) clock.run(f) end
  local restart = actions.restart or function() _norns.restart() end
  local shutdown = actions.shutdown or function() norns.shutdown() end
  print("VERDANDI_CYCLE " .. round .. " of " .. total .. " (start-up " .. tostring(kind) .. ")")
  local keep = M.keep_check(round, actions.ui)
  if keep then print(keep) end
  run(function()
    sleep(3)
    if round < total then
      M.simulate_script_copy(round, actions.exec)
      print("VERDANDI_CYCLE_RESTART " .. round)
      restart()
    else
      print("VERDANDI_CYCLE_DONE " .. round)
      sleep(1)
      shutdown()
    end
  end)
end

return M
