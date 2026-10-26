#!/bin/bash
cd /tmp/claude-0/multi
python3 measure.py "$1" "$2" > "out-$2-$1.txt" 2>&1
echo finished >> "out-$2-$1.txt"
