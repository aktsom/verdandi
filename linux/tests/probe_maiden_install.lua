-- scripts installed through maiden's API (linux/tests/maiden_install_test.sh): a Lua script that norns then loads, and a script that ships a
-- SuperCollider plug-in for another architecture (the plug-in check still reports it; nothing crashes)
#sleep 2
#sh curl -s -X POST "http://127.0.0.1:$NORNS_MAIDEN_PORT/api/v1/project/install?url=file://$ZIPS/hello.zip" > "$MARKS.install1"
#sleep 1
norns.script.load("code/hello/hello.lua")
#sleep 4
#sh curl -s -X POST "http://127.0.0.1:$NORNS_MAIDEN_PORT/api/v1/project/install?url=file://$ZIPS/armplug.zip" > "$MARKS.install2"
#sh "$REPO/build/linux/plugin_arch_check" "$NORNS_HOME" > "$MARKS.arm" 2>&1
#sh curl -s "http://127.0.0.1:$NORNS_MAIDEN_PORT/api/v1/projects" > "$MARKS.projects"
#sleep 1
print("PROBE install done")
