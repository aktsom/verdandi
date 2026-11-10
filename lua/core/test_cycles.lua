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
  run(function()
    sleep(3)
    if round < total then
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
