#sleep 8
norns.script.load("code/probe/heavy.lua")
#sleep 10
#sh /tmp/res/measure.sh "heavy script (PolySub, 4 notes a second with a 4 s release, six softcut voices)" 20
print("PROBE measure done")
