-- linux/tests/twins_boot_test.sh: the real script twins (a clone of its repository in dust/code/twins) on a norns that starts with an EMPTY SuperCollider extension folder and the shipped PortedPlugins pack:
-- the launcher seeded the pack and copied the TwinGrain the script carries before sclang started; twins' own installer must say "all libraries installed" and the engine must load
#sleep 6
print("PROBE engines before", table.concat(engine.names or {}, ","))
norns.script.load("/home/we/dust/code/twins/twins.lua")
#sleep 16
-- the engine posts "twins: grains via ..." after it has built its SynthDefs: slow on a CI runner (the first run failed here with a 16 s wait), so wait for the line, up to 40 s
#sh for i in $(seq 20); do grep -aq "twins: grains via" "@home/logs/sclang.log" 2>/dev/null && break; sleep 2; done
print("PROBE script name", tostring(norns.state.name))
print("PROBE engine", tostring(engine.name))
print("PROBE engines", table.concat(engine.names or {}, ","))
print("PROBE twins done")
