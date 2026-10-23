-- a script's metro must tick, also when the process has a lot of static TLS (linux/tests/tls_pressure.c)
n = 0
m = metro.init(function() n = n + 1 end, 0.05, 20)
m:start()
#sleep 2
print("PROBE metro ticks", n)
for i = 1, 20 do screen.ping() end
#sleep 1
print("PROBE metro done")
