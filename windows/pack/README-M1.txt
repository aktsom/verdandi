Verdandi for Windows, milestone M1 (first runnable build, no sound yet)

START: double-click Verdandi.exe in this folder. To get the newest build instead, double-click update-and-run.cmd here: it downloads it, unpacks it into a new folder next to this one and starts it (your files in %USERPROFILE%\Verdandi stay as they are). BUILD.txt says which build this is. No installation and no administrator rights are needed.
Unpack the WHOLE zip into a folder of its own first (do not start it from inside the zip).

What you should see: the norns window with its screen, keys and encoders. The first start takes some seconds
(SuperCollider compiles its class library). Your files live in  %USERPROFILE%\Verdandi  (dust, logs).

Scripts: awake is included and appears in SELECT on the first start. To add more, copy a script folder into
%USERPROFILE%\Verdandi\dust\code (so that, for example, dust\code\awake\awake.lua exists).
The MAIDEN button says that maiden is not in this build yet. Windows Firewall may ask about norns.exe and sclang.exe:
you can cancel the prompt, nothing needs the network.

SOUND (version 0.3.0, milestone M3): Verdandi plays through your Windows default output (WASAPI shared mode, next to your other programs). SYSTEM > AUDIO (menu: F10 or right mouse button)
has HOST (WASAPI; ASIO in the ASIO build), OUTPUT, OUT CH, INPUT, IN L, IN R, RATE, BUFFER, then APPLY (K3: Verdandi restarts itself), TEST (K3: a click goes out and is listened for on the
input) and three numbers: LATENCY, MEASURED, LEVEL. If a device is busy or missing Verdandi starts silent or on another device, with a plain note on the window instead of freezing.
INPUT: always OFF when Verdandi starts. The MIC button on the window (or K3 of the menu keys as on the Linux build) goes MIC > SYS > OFF: MIC is the input device chosen on the AUDIO page,
SYS is what Windows plays (WASAPI loopback). Details and the click-by-click set-ups for Ableton, TotalMix FX and the RME: windows\README.md of the repository ("Windows M3").
Please send back logs\norns.log, sclang.log and audio.conf, and the list printed by  norns.exe  with  VERDANDI_AUDIO_LIST=1 .

Not in this build: grids and arcs, MIDI, USB devices, Ableton Link, maiden, an installer. Dropping files on the window and the file picker are not available yet.

If something does not work: look into  %USERPROFILE%\Verdandi\logs  (launcher.log, norns.log, sclang.log;
a crash leaves a report in logs\crash) and send those files back.

Windows may warn about an unknown program (the build is not signed yet): "More info", then "Run anyway".
If you downloaded the zip: right-click it, Properties, tick "Unblock", OK, and only then unpack it.
