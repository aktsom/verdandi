# Sending control values from a Max for Live device to Verdandi (an example client)

Verdandi listens for OSC on `127.0.0.1:9201` (UDP, this computer only). Any program can send to it; this is one way to do it from Ableton Live with Max for Live. **Not tried here** (no Ableton, no Max in the build environment): the objects are standard Max, check the numbers on your side.

1. In Live, create a Max MIDI Effect (or Audio Effect) and click **Edit** to open the Max editor.
2. Place a `live.dial` (the control), set its **Unit Style** to *Int* and its range 0 to 127 in the Inspector. **Why Int:** Verdandi takes integers as they are (0 to 127) and floats as 0.0 to 1.0; a dial that sends a float 64.0 would be read as "full".
3. Connect it to `[prepend /cc 1 74]` (channel 1, CC number 74; change them as you like), then to `[udpsend 127.0.0.1 9201]`. `udpsend` sends an OSC packet: address `/cc`, arguments `1 74 <value>`.
4. Save the device. Move the dial: SYSTEM > DEVICES > MIDI ROUTES shows `OSC IN 127.0.0.1:9201 (n)` counting up, and in MIDI MAP the device `osc` appears with CC 74 in WATCH.
5. For notes: `[prepend /note 1 60]` takes a velocity and sends `/note 1 60 <vel>`; `/noteoff 1 60` the end. Raw MIDI: `/midi 176 74 64`.

The same messages work from any other program that can send OSC to a UDP port.
