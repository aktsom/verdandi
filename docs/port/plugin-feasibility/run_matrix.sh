#!/bin/bash
cd /tmp/shm
echo "# machine: $(nproc) cores, kernel $(uname -r), $(date -u +%F)"
for sr in 44100 48000; do for n in 64 128 256 512 1024 2048; do ./shm_rt sync $sr $n 5; done; done
for n in 128 512 2048; do for ppm in 0 100 -100; do ./shm_rt async 48000 $n 10 $ppm 2; done; done
