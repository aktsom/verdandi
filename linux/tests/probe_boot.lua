#sleep 5
print("PROBE engines", engine.names and #engine.names)
norns.script.load("code/probe/probe.lua")
#sleep 4
print("PROBE loaded", norns.state.name, engine.name)
_norns.key(2, 1)
_norns.enc(1, 3)
#sleep 1
print("PROBE done")
