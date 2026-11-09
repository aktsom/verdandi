@echo off
rem Verdandi Windows M0: run the SuperCollider part on your own PC. double-click this file in the unpacked artifact folder.
rem it needs nothing installed and no admin rights: it unpacks sc-win64.zip into a folder next to it, compiles the class library with norns's classes
rem (norns's own server boot is switched off), renders one second of a sine wave offline (no audio device is opened, nothing is played) and writes
rem M0-LOCAL-REPORT.txt. every program is stopped after 5 minutes if it hangs. send the report file back.
setlocal EnableDelayedExpansion
cd /d "%~dp0"
set REPORT=%CD%\M0-LOCAL-REPORT.txt
echo Verdandi M0 local test> "%REPORT%"
ver >> "%REPORT%"
echo %DATE% %TIME%>> "%REPORT%"
echo folder: %CD%>> "%REPORT%"

if not exist sc-win64.zip ( echo sc-win64.zip is not next to this file>> "%REPORT%" & type "%REPORT%" & pause & exit /b 1 )
if not exist run\SuperCollider\sclang.exe (
  mkdir run 2>nul
  tar -xf sc-win64.zip -C run
)
set FWD=%CD:\=/%
rem sclang config: the class library of SuperCollider, norns's classes and the no-boot class, nothing else
(
  echo includePaths:
  echo   - %FWD%/run/SuperCollider/SCClassLibrary
  echo   - %FWD%/norns-sc/core
  echo   - %FWD%/norns-sc/engines
  echo   - %FWD%/norns-sc/linux-compat
  echo   - %FWD%/sc-smoke
  echo excludeDefaultPaths: true
) > sclang.cfg

rem both programs are started from this folder with RELATIVE names only: sclang reads its command line in the ANSI code page, so a folder with an accented letter would fail otherwise
echo.>> "%REPORT%"
echo --- sclang --->> "%REPORT%"
if exist score.osc del score.osc
powershell -NoProfile -Command "$p = Start-Process -FilePath '.\run\SuperCollider\sclang.exe' -ArgumentList '-D','-l','sclang.cfg','m0-job.scd' -NoNewWindow -PassThru -RedirectStandardOutput 'sclang.out' -RedirectStandardError 'sclang.err'; if (-not $p.WaitForExit(300000)) { $p.Kill(); 'TIMEOUT: sclang stopped after 5 minutes' } else { 'sclang exit code ' + $p.ExitCode }" >> "%REPORT%" 2>&1
if exist sclang.out type sclang.out >> "%REPORT%"
if exist sclang.err type sclang.err >> "%REPORT%"

echo.>> "%REPORT%"
echo --- scsynth offline render --->> "%REPORT%"
if exist out.wav del out.wav
powershell -NoProfile -Command "$p = Start-Process -FilePath '.\run\SuperCollider\scsynth.exe' -ArgumentList '-N','score.osc','_','out.wav','48000','WAV','int16','-o','2' -NoNewWindow -PassThru -RedirectStandardOutput 'scsynth.out' -RedirectStandardError 'scsynth.err'; if (-not $p.WaitForExit(300000)) { $p.Kill(); 'TIMEOUT: scsynth stopped after 5 minutes' } else { 'scsynth exit code ' + $p.ExitCode }" >> "%REPORT%" 2>&1
if exist scsynth.out type scsynth.out >> "%REPORT%"
if exist scsynth.err type scsynth.err >> "%REPORT%"
if exist out.wav ( for %%F in (out.wav) do echo out.wav is %%~zF bytes ^(expected about 192000^)>> "%REPORT%" ) else echo out.wav was not written>> "%REPORT%"

echo.
type "%REPORT%"
echo.
echo ===== Done. Send M0-LOCAL-REPORT.txt back. =====
pause
