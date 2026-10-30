#sleep 8
#sh /tmp/res/measure.sh "no script, idle" 15
norns.script.load("code/probe/perc.lua")
#sleep 8
#sh /tmp/res/measure.sh "script loaded (PolyPerc 4 notes a second, softcut loop)" 20
print("PROBE measure done")
