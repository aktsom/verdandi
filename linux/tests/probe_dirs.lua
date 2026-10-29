# the folders and the environment the launcher sets up (linux/tests/launcher_logs_test.sh)
#sleep 3
print("PROBE dirs cache", os.getenv("XDG_CACHE_HOME"), os.getenv("MESA_SHADER_CACHE_MAX_SIZE"))
print("PROBE dirs tidy", os.getenv("NORNS_TIDY"))
#sleep 1
