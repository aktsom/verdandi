# M37: a busy MIDI device must never freeze Verdandi's start-up (Linux first, Windows checked)

Written before the change. Base: the head of `linux-port` after M31b (`7182d251`). The installed build the owner ran: 0.10.21 `911939d`.

## What happened

The owner started Verdandi while Reaper already held the MIDI interface `mio` (ALSA raw MIDI, `/dev/snd/midiC1D0`). Verdandi showed the start animation and played sound, then the screen stayed black. norns, sclang, scsynth and maiden were alive, sclang had said `/crone/ready`: matron itself had not finished its start-up. Closing Reaper did not free it. Two logs:

- run 1 ended after `dev_monitor: adding midi device mio`, `device opened (bidirectional)`, `midi: added mio (/dev/snd/midiC1D0 port 0)` and (from another thread) the line that skips the virtual raw MIDI card VirMIDI;
- run 2 ended at `dev_monitor: adding midi device mio`, without `device opened`.

In both, `handling pending events...` (`matron/src/main.cc:294`) never came. Starting Verdandi first and Reaper after works (Reaper then says it cannot open `hw:mio`), and so does starting with Reaper closed.

## Where it blocks (read from the code)

1. **`matron/src/device/device_midi.cc:117-119`** opens the raw port with `snd_rawmidi_open(..., 0)`: flags 0 = a BLOCKING open. For ALSA raw MIDI the kernel does not answer "busy" to a blocking open: it puts the caller to sleep until the other program lets go (`snd_rawmidi_open` in the kernel waits on the card's open queue unless the file is `O_NONBLOCK`; a DAW such as Reaper opens non-blocking and so is told "could not be opened"). This is also why starting Verdandi second hangs and starting it first does not.
2. That open runs **on the main thread during start-up**: `main.cc:291` `dev_monitor_scan()` -> `add_dev` -> `add_dev_sound` -> `dev_list_add` (`device_list.cc`) -> `dev_new` -> `dev_midi_init`. Nothing reaches `main.cc:294` until it returns.
3. The device monitor thread (`watch_loop`, started earlier at `main.cc:269`) runs the same add path every 3 seconds (`dev_monitor_midi_check`) and for each udev event. Two threads can therefore try to open **the same port** at the same time: the check of "is this port listed" (`device_list.cc`) and the insert into the list are not one step, so a thread that is slower finds the port not yet listed and opens it as well; a second blocking open of a port **Verdandi itself holds** can never return. This explains why closing Reaper afterwards freed nothing: the open that Reaper blocked was woken, but a second opener of the same port, now held by the first, sleeps for ever.
4. Run 1 and run 2 are therefore the same blocking call seen at different ports and times (which port Reaper held, and which thread was the second opener), not two different bugs. This is an inference from the code and the two logs; the logs were not available here, and the kernel behaviour is documented, not tried on the owner's machine.
5. Other places that can wait on a device: `snd_rawmidi_write` in `dev_midi_send` (`device_midi.cc:459`, a blocking write on the main/Lua thread when a device does not take its data), the `open()` of a tty or evdev node (`device_crow.cc:32`, `device_serial.cc:36`, `device_hid.cc:103`) and the reads in `device_crow.cc:54-61` (crow start-up). The ALSA sequencer calls are already non-blocking (`aseq_out.cc:146` uses `SND_SEQ_NONBLOCK`; `midi_autoconnect.cc:117` opens with flag 0 on its own worker thread, not on the start-up path).

## The change

Linux desktop only (`NORNS_LINUX_DESKTOP`, not `NORNS_WINDOWS`, not macOS); the norns hardware build and macOS keep their code.

1. **Non-blocking open.** The input and the output are opened separately with `SND_RAWMIDI_NONBLOCK`. A busy answer (`-EBUSY`) means: close what was opened, skip the port, say why. The input handle is then switched back to blocking mode (`snd_rawmidi_nonblock(in, 0)`), so the reader thread is exactly as before; the output stays non-blocking. A failure that is not "busy" (a device with only an input or only an output) behaves as before.
2. **One add at a time.** The check "is this port listed" and the open and insert are done under one lock, so two threads can never open the same port.
3. **Bounded write.** `dev_midi_send` writes in pieces, waits at most 250 ms for a device that takes nothing (and 5 s in all), then drops the rest and says so once. A slow device that keeps taking data is not cut off.
4. **A bounded scan.** The start-up scan runs on a helper thread; `dev_monitor_scan` waits for it at most 3 seconds, then says so and lets start-up go on. Whatever the helper is waiting for (a tty, a HID node, anything that cannot be made non-blocking) can no longer stop the start-up.
5. **Retry, said once.** The 3-second check already tries every card that has ports not in the list. A skipped port is now remembered with its reason: the skip is logged once (device name, node, port, `busy: another program has it open`), the retries are silent, and when it is finally added the log says `midi: <name> is free now: added`. A card that is unplugged forgets its skips.
6. **Visible.** `_norns.midi_skipped()` returns the skipped ports; SYSTEM > DEVICES shows `midi: 1 busy` in the list and `BUSY: mio` on the title row of the MIDI list. No new page.

## Windows

WinMM answers a busy port at once (`midiInOpen` returns `MMSYSERR_ALLOCATED`, `midi_winmm.c:130-134`; the output the same, `:175-179`): reported as "held by another program" (`midi_port.cc:114-126`), shown on SYSTEM > DEVICES > midi routes (`midiwin.lua`) and in the list label (`devices.lua:42-45`), and tried again by the monitor thread every 3 s (`midi_monitor.cc:119-127`). The first scan runs on that thread, not on the main thread (`vmidi_monitor_start`, `midi_monitor.cc:246`). So Windows skips and does not wait. What it cannot do is bound a driver that hangs inside `midiInOpen` itself (no time-out exists for that system call): not a busy port, not seen, not changed here.

## Tests (linux/tests/midi_replug_test.cc: the real monitor, list and read threads with a fake udev and ALSA)

The fake ALSA now behaves like the kernel: an open that finds the port busy waits until it is free, unless the open is non-blocking, which answers `-EBUSY`. New cases: a port held by another program at start (the add returns, one log line, the other ports and cards work), the other program lets go (the port is added by itself, one log line), a port that Verdandi holds itself and a second thread adding at the same time, a start-up scan that blocks (a blocking stand-in), a write to a device that takes nothing, the note text for the page, the log not flooded over many checks. They fail on the code before the change (`docs/port/phase-m37-without.txt`).

## Not changed

How devices are read (no ALSA sequencer). Not tried here: a real `mio`, Reaper, a real kernel (no ALSA hardware in the test container); the owner's checks are in `HARDWARE-CHECKLIST.md`.
