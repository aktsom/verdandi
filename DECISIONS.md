# DECISIONS

## GATE A: fork vs upstream-as-platform-folders (DECIDED: option 1, by Ken)

**Question:** where does the Linux (and later Windows) code live, and do we approach ha1dcre?

Findings from the inventory (`docs/port/INVENTORY.md`): the reusable desktop layer (skins,
key mapping, vgrid protocol, GIF writer) sits in `matron/src/platform/macos/`; upstream
norns already builds on desktop Linux and has the Linux device code, so most Linux work is
the desktop layer (window, menu, picker, drop, SYS input) plus build/launcher/packaging.

**Options**
1. Platform folders in this fork: new `matron/src/platform/linux/` (later `windows/`), shared
   files moved or referenced from a `platform/common/` folder; macOS files untouched at first.
   Keeps the code offerable upstream.
2. Fork-only layout: Linux files added next to the macOS ones, no shared folder, no upstream
   intent. Least refactoring, most duplication risk.
3. Approach ha1dcre before starting: ask whether they want a Linux/Windows port upstream and
   in what layout. Highest coordination cost; I will not contact anyone without Ken.

**Recommendation:** Option 1, with shared files left in place in Phase 1-2 and moved to
`platform/common/` only in a separate commit once Linux works (keeps macOS behavior and its
tests unchanged meanwhile). Whether to approach ha1dcre is Ken's call, after Linux works.

**Needed from Ken:** pick 1, 2 or 3 (and if 3, who contacts ha1dcre).

Notification: not sent. `SANDBOX.md` (notification hook) is missing from the repo.

## Phase 2 decisions (DECIDED by Ken)
1. libmonome pty: patch (A) for now (`linux/patches/libmonome-pty-serial.patch`). Phase 5.5 (OSC / serialosc,
   see PLAN.md) is meant to replace the pty trick on all platforms (Gate F).
2. "norns keys": both the internal device (A) and the ALSA sequencer port (B). B is runtime-optional and
   stays untested until the hardware checklist.
3. `sdl_bridge.cc`: option A, the same file on Linux, platform seams behind `desktop_shell.h`.
4. Menu: in-window menu (no menu bar). The dust link folder keeps the name `mac` for now.
Order of work: `docs/port/phase-2.md` section 6; stop after step 5 with `HARDWARE-CHECKLIST.md` updated.

## Phase 3 decisions (DECIDED by Ken, after `docs/port/phase-3.md`)
1. Steps 1 and 2 first (SPP/continue, then JACK MIDI input), tests first. Steps 3-5 wait for Ken's laptop output.
2. The probe readiness fix is applied (`linux/tests/norns_probe.sh`).
3. crone without physical JACK ports starts **unconnected with a warning that is visible in the norns window or
   menu, not only in the log**. Pi and macOS behavior unchanged. (Step 3, waits.)
4. `norns.sh` re-runs itself under `pw-jack` only when PipeWire is running and no JACK server answers;
   `NORNS_AUDIO_SERVER` override stays. (Step 3, waits.)
5. SYSTEM > AUDIO rows are read-only under PipeWire; `PIPEWIRE_QUANTUM` is marked experimental. (Step 4, waits.)
6. JACK MIDI client "Verdandi", device "Verdandi JACK in", no auto-connect.
7. MIDI start after SPP begins at the SPP position (once).
8. Ken runs the laptop checklist and sends the output.

## Decision 9 (APPROVED by Ken, after his laptop results): which device crone uses
crone follows the system default sink for the output and the default source for the input; `audio.conf` can
override each by port-name prefix (`out_ports=`, `in_ports=`); SYS uses the monitor ports of the chosen output.
Details, the `wpctl` query and the risks: `docs/port/phase-3.md` ("Decision 9"). Hardware note: the RME Fireface is
not class-compliant on Linux; Windows still needs ASIO (Gate D).

## Decision 10 (DECIDED by Ken, built in step 5): SYS and feedback
SYS = **all application clients except norns' own clients** (no feedback: norns' output is not among the sources).
The sink monitor exists only as an **optional extra** (`NORNS_SYS_MONITOR=1` or `sys_monitor=1` in `audio.conf`), as its
own input mode "sink monitor (hears norns too)" with a standing warning on the device screen while it is on and the input
monitor switched off. Decision 9 (crone follows the default sink, `audio.conf` overrides) is unchanged.
