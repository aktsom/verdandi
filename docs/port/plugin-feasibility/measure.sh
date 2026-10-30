#!/bin/bash
# measure.sh LABEL SECONDS: RSS, PSS, private memory (kB) and CPU (% of one core over SECONDS) of every process of one headless norns (norns, sclang, scsynth, jackd, maiden, ws-wrapper; Xvfb is the test harness' display and is listed apart)
label="$1"; secs="${2:-15}"; out=/tmp/res/res.txt
names="norns sclang scsynth jackd maiden ws-wrapper Xvfb"
declare -A t0
tick=$(getconf CLK_TCK)
for n in $names; do for p in $(pgrep -x "$n"); do read -r -a f < /proc/$p/stat; t0[$p]=$(( ${f[13]} + ${f[14]} )); done; done
sleep "$secs"
echo "== $label ($secs s window)" >> $out
tot_rss=0; tot_pss=0; tot_priv=0; tot_cpu=0
for n in $names; do for p in $(pgrep -x "$n"); do
  [ -r /proc/$p/stat ] || continue
  read -r -a f < /proc/$p/stat; t1=$(( ${f[13]} + ${f[14]} ))
  cpu=$(awk -v a=${t0[$p]:-$t1} -v b=$t1 -v s=$secs -v k=$tick 'BEGIN{printf "%.1f", (b-a)/k/s*100}')
  rss=$(awk '/^Rss:/{print $2}' /proc/$p/smaps_rollup); pss=$(awk '/^Pss:/{print $2}' /proc/$p/smaps_rollup)
  pv=$(awk '/^Private_(Clean|Dirty):/{s+=$2} END{print s}' /proc/$p/smaps_rollup)
  th=$(ls /proc/$p/task | wc -l)
  printf "%-11s pid %-6s threads %-3s RSS %7s kB  PSS %7s kB  private %7s kB  CPU %5s %%\n" "$n" "$p" "$th" "$rss" "$pss" "$pv" "$cpu" >> $out
  if [ "$n" != Xvfb ]; then tot_rss=$((tot_rss+rss)); tot_pss=$((tot_pss+pss)); tot_priv=$((tot_priv+pv)); tot_cpu=$(awk -v a=$tot_cpu -v b=$cpu 'BEGIN{print a+b}'); fi
done; done
printf "TOTAL (without Xvfb)  RSS %s kB  PSS %s kB  private %s kB  CPU %s %% of one core\n" $tot_rss $tot_pss $tot_priv $tot_cpu >> $out
