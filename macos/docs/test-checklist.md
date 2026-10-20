# norns for macOS: test checklist

what has not been tested on the machine it was built on. tick what works, and for what
does not, send the logs: `~/norns/norns.log`, `sclang.log`, `jackd.log`, `auv3_bridge.log`
(they contain paths of your Mac, so look them over before you share them).

## a Mac with macOS 15 (Sequoia), not the one it was built on

- [ ] open `norns.dmg`, drag norns into Applications, start it: macOS refuses at first
      (not notarized); right-click > Open, or System Settings > Privacy & Security > Open Anyway
- [ ] allow the microphone; norns shows its screen, the HOME menu reacts to K2/K3 (2, 3, return, esc)
- [ ] SELECT a script (awake, then something with an engine: passersby, cranes): it plays
- [ ] MIC > SYS: play a video in the browser, allow "record audio from other apps"; the video is
      heard through norns (MIX: in moves), not directly; MIC > OFF: the video is heard directly again
- [ ] quit norns while on SYS, start it again: SYS again, with the note; the video goes into norns
- [ ] Manual.pdf and the Licenses folder open from the dmg

## audio interface

- [ ] SYSTEM > AUDIO: choose the interface as INPUT and OUTPUT, APPLY: norns restarts its audio
      on it; a rate the interface cannot do falls back to the defaults with a note
- [ ] BUFFER 64 / 128: no dropouts with a script running (cranes, mlr)
- [ ] the interface unplugged and plugged back in while norns runs

## hardware

- [ ] monome grid (USB): shows in SYSTEM > DEVICES > GRID, a grid script (mlr, awake) works
- [ ] monome arc: shows as an arc, rings light, turning and pushing work
- [ ] crow (USB): a crow script (crow-studies) sends and receives
- [ ] a MIDI keyboard / controller: notes and CCs reach a script (passersby), MIDI out to a synth
- [ ] a gamepad, if you have one (SYSTEM > DEVICES > HID)

## the AUv3 plugin in a DAW

- [ ] Logic (Audio FX or MIDI-controlled effect), Ableton Live, Bitwig or Reaper: norns shows up
      after starting norns.app once; insert it on a track, press play: "connected"
- [ ] the track's audio goes into norns (MIX: in), norns comes back into the track
- [ ] MIDI on the plugin's track reaches norns (device "norns AUv3")
- [ ] stop the DAW: norns goes back to the interface within a second
- [ ] with MIC on SYS, play the DAW through the plugin: the DAW is heard (SYS pauses), no
      feedback; stop it: SYS takes the apps again

## the window

- [ ] drop a wav from the Finder (linked into dust/audio/mac), with option (copied), a voice
      memo from Voice Memos, a sample from a sample browser or DAW
- [ ] a script's file parameter (barcode: buffer 1 sample): the Finder panel opens, the chosen
      sample is loaded; dropping a sample on the window while the browser is up does the same
- [ ] the MIX page by mouse (drag, scroll), the OUT fader and MUTE, the arc and grid windows
