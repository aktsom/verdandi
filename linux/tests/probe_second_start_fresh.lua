# a start on a home where a crashed norns left its control files (run_all.sh, second_start_scenario): it starts normally, its matron clears the old request and answer,
# and a second start still raises it
#sleep 5
norns.script.load("code/probe/window_probe.lua")
#sleep 3
#sh bash "$NORNS_HOME/norns/linux/tests/second_start_check.sh" files files_after_start
#sh bash "$NORNS_HOME/norns/linux/tests/second_start_check.sh" second fresh_second
print("PROBE fresh start done")
#xdo search --name ^Verdandi.Linux$ windowfocus
#xdo key ctrl+q
#sleep 4
