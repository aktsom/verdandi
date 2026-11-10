Verdandi for Windows, milestone M1 (first runnable build, no sound yet)

START: double-click Verdandi.exe in this folder. No installation and no administrator rights are needed.
Unpack the WHOLE zip into a folder of its own first (do not start it from inside the zip).

What you should see: the norns window with its screen, keys and encoders. The first start takes some seconds
(SuperCollider compiles its class library). Your files live in  %USERPROFILE%\Verdandi  (dust, logs).

Scripts: awake is included and appears in SELECT on the first start. To add more, copy a script folder into
%USERPROFILE%\Verdandi\dust\code (so that, for example, dust\code\awake\awake.lua exists).
The MAIDEN button says that maiden is not in this build yet. Windows Firewall may ask about norns.exe and sclang.exe:
you can cancel the prompt, nothing needs the network.

SOUND (version 0.2.0, milestone M2): Verdandi plays through your Windows default output. SYSTEM > AUDIO (menu: F10 or
right mouse button) lists the playback devices; choose one and press K3 on APPLY (Verdandi restarts itself). If the device
is busy or missing Verdandi starts silent, with a note on the window instead of freezing. Details: windows\README.md of the
repository ("Windows M2"). Please send back logs\norns.log, sclang.log and audio.conf.

Not in this build (the lines below were written for M1; sound is now in, input from the sound card is not): sound (scsynth runs on a silent null audio device), grids and arcs, MIDI, USB devices, Ableton Link,
maiden, an installer. Dropping files on the window and the file picker are not available yet.

If something does not work: look into  %USERPROFILE%\Verdandi\logs  (launcher.log, norns.log, sclang.log;
a crash leaves a report in logs\crash) and send those files back.

Windows may warn about an unknown program (the build is not signed yet): "More info", then "Run anyway".
If you downloaded the zip: right-click it, Properties, tick "Unblock", OK, and only then unpack it.
