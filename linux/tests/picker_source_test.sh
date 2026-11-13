#!/usr/bin/env bash
# the folder picker and the key names, as text in the sources (no Windows here to run them): "cancelled" only for ERROR_CANCELLED, no hand-typed GUIDs, every failure logged with its HRESULT,
# the PowerShell fallback present; the GIF note names Ctrl on Windows and Linux and Cmd only under __APPLE__, and the window really has that key
set -u
cd "$(dirname "$0")/../.." || exit 1
fail=0
chk() { if ! eval "$2"; then echo "FAIL $1"; fail=1; else echo "ok   $1"; fi; }
P=matron/src/platform/windows/folder_picker_win.cc
chk "only ERROR_CANCELLED is a cancel" "grep -q 'HRESULT_FROM_WIN32(ERROR_CANCELLED)' $P && [ \$(grep -c 'R_CANCEL;' $P) -le 2 ]"
chk "ids come from the headers (__uuidof), none typed by hand" "grep -q '__uuidof(IFileOpenDialog)' $P && ! grep -q 'const GUID' $P"
chk "every step logs its HRESULT to norns.log" "grep -q 'HRESULT 0x%08lX' $P && grep -q 'log_step(\"Show\"' $P && grep -q 'CoCreateInstance(FileOpenDialog)' $P"
chk "a failure reaches the callback as n = -1 with a text" "grep -q 'j->done(one, -1' $P"
chk "the PowerShell helper is the fallback" "grep -q 'powershell.exe' $P && grep -q 'trying the PowerShell helper' $P"
chk "the bridge passes the error text on" "grep -q 'if (n < 0)' matron/src/platform/macos/sdl_bridge.cc"
K=matron/src/platform/common/key_names.h
chk "Cmd only under __APPLE__" "awk '/#ifdef __APPLE__/,/#else/' $K | grep -q 'shift-cmd-G' && ! awk '/#else/,/#endif/' $K | grep -qi 'cmd'"
chk "the toast comes from key_names.h" "grep -q 'show_toast(GIF_STOP_TOAST' matron/src/platform/macos/sdl_bridge.cc && ! grep -q 'shift-cmd' matron/src/platform/macos/sdl_bridge.cc"
chk "the window has the key the note names (Ctrl+Shift+G starts and stops a recording)" "grep -q 'SDL_SCANCODE_G' matron/src/platform/linux/desktop_shell_linux.cc && grep -q 'GIF_MENU_HINT' matron/src/platform/linux/desktop_shell_linux.cc"
chk "no Cmd/Mac key words in the Windows-visible text of the menu" "! grep -n -i 'cmd\|command key' matron/src/platform/linux/desktop_shell_linux.cc"
exit "$fail"
