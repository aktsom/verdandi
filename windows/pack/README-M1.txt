Verdandi for Windows, milestone M1 (first runnable build, no sound yet)

START: double-click Verdandi.exe in this folder. No installation and no administrator rights are needed.
Unpack the WHOLE zip into a folder of its own first (do not start it from inside the zip).

What you should see: the norns window with its screen, keys and encoders. The first start takes some seconds
(SuperCollider compiles its class library). Your files live in  %USERPROFILE%\Verdandi  (dust, logs).

Not in this build: sound (scsynth runs on a silent null audio device), grids and arcs, MIDI, USB devices, Ableton Link,
maiden, an installer. Dropping files on the window and the file picker are not available yet.

If something does not work: look into  %USERPROFILE%\Verdandi\logs  (launcher.log, norns.log, sclang.log;
a crash leaves a report in logs\crash) and send those files back.

Windows may warn about an unknown program (the build is not signed yet): "More info", then "Run anyway".
If you downloaded the zip: right-click it, Properties, tick "Unblock", OK, and only then unpack it.
