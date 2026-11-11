#!/usr/bin/env bash
# linux/tests/metro_win_test.sh: the Windows metros (metro.cc with NORNS_WINDOWS) against a fake event queue: a stopped metro stops, also when stopped right after its start. run from anywhere.
set -u
cd "$(dirname "$0")/../.." || exit 1
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
cp matron/src/metro.cc matron/src/metro.h linux/tests/metro_win_test.cc "$T/" || exit 1
cat > "$T/events.h" <<'H'
#pragma once
#include <stdint.h>
enum { EVENT_METRO = 1 };
union event_data { struct { int id; uint64_t stage; } metro; };
#ifdef __cplusplus
extern "C" {
#endif
union event_data *event_data_new(int type);
void event_post(union event_data *ev);
#ifdef __cplusplus
}
#endif
H
g++ -std=gnu++14 -O1 -DNORNS_WINDOWS -I"$T" "$T/metro_win_test.cc" "$T/metro.cc" -lpthread -o "$T/mt" || exit 1
"$T/mt"
