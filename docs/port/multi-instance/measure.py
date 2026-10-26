#!/usr/bin/env python3
# harness: start N instances (MODE), wait for each to be ready, report what is listening, errors, CPU and memory, startup time
import os, re, signal, subprocess, sys, time
n, mode = int(sys.argv[1]), sys.argv[2]
S = '/tmp/claude-0/multi'
CLK = os.sysconf('SC_CLK_TCK')
def sh(c): return subprocess.run(c, shell=True, capture_output=True, text=True).stdout
def session_pids(sid): 
    out = []
    for l in sh('ps -eo pid,sid,comm,args --no-headers').splitlines():
        p = l.split(None, 3)
        if int(p[1]) == sid: out.append((int(p[0]), p[2], p[3] if len(p) > 3 else ''))
    return out
def cpu_ticks(pid):
    try:
        f = open('/proc/%d/stat' % pid).read().rsplit(')', 1)[1].split()
        return int(f[11]) + int(f[12])
    except Exception: return 0
def pss_kb(pid):
    try:
        for l in open('/proc/%d/smaps_rollup' % pid):
            if l.startswith('Pss:'): return int(l.split()[1])
    except Exception: pass
    return 0
sh('pkill -x norns; pkill -x scsynth; pkill -x sclang; pkill -x jackd; sleep 1')
for d in os.listdir(S):
    if d.startswith('home'): sh('rm -rf %s/%s' % (S, d))
sh('rm -f /tmp/norns-sidecar.ipc')
if not sh('pgrep -x Xvfb').strip():
    subprocess.Popen('Xvfb :99 -screen 0 1280x800x24', shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL); time.sleep(1.5)
if mode == 'shared':
    subprocess.Popen('jackd -r -d dummy -r 48000 -p 1024 > %s/jackd-shared.log 2>&1' % S, shell=True, start_new_session=True)
    time.sleep(2)
procs, t0 = {}, {}
for i in range(1, n + 1):
    t0[i] = time.time()
    procs[i] = subprocess.Popen([S + '/inst.sh', str(i), mode], start_new_session=True, stdout=open('%s/inst%d.out' % (S, i), 'w'), stderr=subprocess.STDOUT)
    if os.environ.get('SEQUENTIAL') == '1' and i < n:
        # the next one starts when this one is ready (or after 45 s): who wins a port must not be a race
        H = '%s/home%d' % (S, i)
        for _ in range(90):
            a = os.path.exists(H + '/norns.log') and 'norns.startup_status.ok' in open(H + '/norns.log', errors='replace').read()
            b = os.path.exists(H + '/sclang.log') and 'engines: [' in open(H + '/sclang.log', errors='replace').read()
            if a and b: break
            time.sleep(0.5)
        time.sleep(2)
ready = {}
deadline = time.time() + 150
while time.time() < deadline and len(ready) < n:
    for i in range(1, n + 1):
        if i in ready: continue
        H = '%s/home%d' % (S, i)
        a = os.path.exists(H + '/norns.log') and 'norns.startup_status.ok' in open(H + '/norns.log', errors='replace').read()
        b = os.path.exists(H + '/sclang.log') and 'engines: [' in open(H + '/sclang.log', errors='replace').read()
        if a and b: ready[i] = time.time() - t0[i]
    time.sleep(0.5)
print('MODE', mode, 'N', n)
print('ready (s since start):', {i: round(t, 1) for i, t in ready.items()}, 'not ready:', [i for i in range(1, n + 1) if i not in ready])
time.sleep(5)
# idle CPU and memory over 20 s
allp = {}
for i in range(1, n + 1): allp[i] = session_pids(procs[i].pid)
base = {p: cpu_ticks(p) for i in allp for p, _, _ in allp[i]}
w0 = time.time(); time.sleep(20); w = time.time() - w0
tot_cpu = 0; tot_pss = 0
for i in allp:
    cpu = sum(cpu_ticks(p) - base.get(p, 0) for p, _, _ in allp[i]) / CLK / w * 100
    pss = sum(pss_kb(p) for p, _, _ in allp[i]) / 1024
    tot_cpu += cpu; tot_pss += pss
    names = sorted(set(c for _, c, _ in allp[i]))
    if n == 1:
        for p, c, a in allp[i]:
            print('   %-16s pid %-7d PSS %6.0f MB  CPU %.1f%%' % (c, p, pss_kb(p) / 1024, (cpu_ticks(p) - base.get(p, 0)) / CLK / w * 100))
    print('instance %d: %d processes (%s) idle CPU %.1f%% of one core, PSS %.0f MB' % (i, len(allp[i]), ','.join(names), cpu, pss))
print('total: idle CPU %.1f%% of one core, PSS %.0f MB' % (tot_cpu, tot_pss))
import socket as _s
def sockets_of(pid):
    inodes = set()
    try:
        for fd in os.listdir('/proc/%d/fd' % pid):
            try:
                l = os.readlink('/proc/%d/fd/%d' % (pid, int(fd)))
                if l.startswith('socket:['): inodes.add(l[8:-1])
            except OSError: pass
    except OSError: return []
    out = []
    for proto, f in (('udp', 'udp'), ('udp', 'udp6'), ('tcp', 'tcp'), ('tcp', 'tcp6')):
        try: lines = open('/proc/%d/net/%s' % (pid, f)).read().splitlines()[1:]
        except OSError: continue
        for l in lines:
            c = l.split()
            if c[9] not in inodes: continue
            if proto == 'tcp' and c[3] != '0A': continue
            addr, port = c[1].split(':')
            out.append((proto, int(port, 16), addr))
    return out
print('bound ports per instance (udp, and tcp in listen state), by process:')
seen = {}
for i in allp:
    for p, comm, args in allp[i]:
        for proto, port, addr in sockets_of(p):
            seen.setdefault((i, comm), set()).add((proto, port))
for (i, comm), ports in sorted(seen.items()):
    print('  instance %d %-12s %s' % (i, comm, ' '.join('%s/%d' % x for x in sorted(ports))))
print('JACK ports seen (first clients), per JACK server:')
if mode == 'shared':
    print(sh('jack_lsp 2>/dev/null | sed "s/:.*//" | sort | uniq -c'))
else:
    for i in range(1, n + 1):
        if mode == 'jack': print(' j%d:' % i, sh('JACK_DEFAULT_SERVER=j%d jack_lsp 2>/dev/null | sed "s/:.*//" | sort | uniq -c | tr "\\n" " "' % i))
print('log lines that look like clashes:')
print(sh("grep -h -i 'address already in use\\|already in use\\|bind\\|failed\\|error\\|cannot\\|renamed\\|-01' %s/home*/norns.log %s/home*/sclang.log %s/inst*.out 2>/dev/null | sort | uniq -c | sort -rn | head -25" % (S, S, S)))
for i in procs:
    try: os.killpg(procs[i].pid, signal.SIGTERM)
    except Exception: pass
time.sleep(3)
sh('pkill -9 -x norns; pkill -9 -x scsynth; pkill -9 -x sclang; pkill -9 -x jackd')
