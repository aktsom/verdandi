-- the script's global refresh() (linux/tests/refresh_test.sh): called about 60 times a second while the script runs (as the device's screen thread does),
-- not after the script is cleared or replaced, not at all (and no error) for a script without refresh()
#sleep 2
norns.script.load("code/refresh_a/refresh_a.lua")
#sleep 1
c0 = norns.REFRESH_COUNT
#sleep 3
print("PROBE a_running", norns.state.name, norns.REFRESH_COUNT - c0)
norns.script.load("code/refresh_b/refresh_b.lua")
#sleep 1
print("PROBE b_loaded", norns.state.name, refresh == norns.none)
c1 = norns.REFRESH_COUNT
#sleep 2
print("PROBE after_replace", norns.REFRESH_COUNT - c1)
norns.script.load("code/refresh_a/refresh_a.lua")
#sleep 1
norns.script.clear()
c2 = norns.REFRESH_COUNT
#sleep 2
print("PROBE after_clear", norns.REFRESH_COUNT - c2, refresh == norns.none)
