@echo off
rem update-and-run.cmd: get the newest Verdandi build, unpack it next to the old ones, start it.
rem no administrator rights, no installation. Uses only what Windows 10 and 11 have: curl.exe, tar.exe, certutil. If curl.exe or tar.exe is missing it starts update-and-run.ps1 (PowerShell) instead.
rem
rem what it does, in order:
rem   1. reads which build this folder is (BUILD.txt) and which build is the newest (BUILD.txt of the GitHub release "windows-latest", a few bytes)
rem   2. if the newest is not here yet: downloads the zip, checks its size and its SHA-256 when the release has one, unpacks it into a NEW folder  Verdandi-<version>-<hash>  next to this one
rem   3. closes a running Verdandi after asking, offers to remove the older unpacked builds (default: no), starts the new Verdandi.exe
rem   your files (scripts, audio, settings, logs) are in %USERPROFILE%\Verdandi and are never touched: only folders that hold Verdandi.exe and norns.exe can be removed.
rem
rem options (the first letter is enough):  /NOSTART  do not start Verdandi at the end     /KEEP  do not offer to remove older builds     /YES  close a running Verdandi without asking
rem for tests: VERDANDI_CHOICE (another program for the questions), VERDANDI_UPDATE_BASE (the folder of the release files instead of the GitHub address), VERDANDI_UPDATE_SOURCE (owner/repository)
setlocal EnableExtensions EnableDelayedExpansion

set "NOSTART=" & set "KEEP=" & set "YES="
:args
if "%~1"=="" goto :argsdone
if /i "%~1"=="/NOSTART" set "NOSTART=1"
if /i "%~1"=="/KEEP" set "KEEP=1"
if /i "%~1"=="/YES" set "YES=1"
shift
goto :args
:argsdone

set "HERE=%~dp0"
if "%HERE:~-1%"=="\" set "HERE=%HERE:~0,-1%"
for %%I in ("%HERE%\..") do set "PARENT=%%~fI"
set "TAG=windows-latest"
rem the ASIO build (FLAVOR.txt in its folder) updates to the ASIO build: its own zip and folder name
set "ZIPNAME=Verdandi-windows-latest"
set "NAMEPFX=Verdandi"
if exist "%HERE%\FLAVOR.txt" (
  set "ZIPNAME=Verdandi-windows-asio-latest"
  set "NAMEPFX=Verdandi-asio"
)
set "CHOICE=choice.exe"
if defined VERDANDI_CHOICE set "CHOICE=%VERDANDI_CHOICE%"
set "DATA=%USERPROFILE%\Verdandi"
if defined VERDANDI_HOME set "DATA=%VERDANDI_HOME%"

echo.
echo  Verdandi: update and run
echo  ------------------------

rem ---- this build
set "CURRENT="
if exist "%HERE%\BUILD.txt" for /f "usebackq tokens=1,2" %%a in ("%HERE%\BUILD.txt") do if not defined CURRENT set "CURRENT=%%a %%b"
if not defined CURRENT set "CURRENT=unknown"
echo  This folder holds build: !CURRENT!
echo    %HERE%

rem ---- where the releases are
set "REPO="
if defined VERDANDI_UPDATE_SOURCE set "REPO=%VERDANDI_UPDATE_SOURCE%"
if not defined REPO if exist "%HERE%\UPDATE-SOURCE.txt" for /f "usebackq delims=" %%a in ("%HERE%\UPDATE-SOURCE.txt") do if not defined REPO set "REPO=%%a"
set "BASE=%VERDANDI_UPDATE_BASE%"
if not defined BASE if defined REPO set "BASE=https://github.com/%REPO%/releases/download/%TAG%"
if not defined BASE (
  echo.
  echo  This copy does not know where the newest build is published: UPDATE-SOURCE.txt is missing or empty.
  echo  Download the zip by hand from the Releases page of the repository, or ask for a newer zip.
  goto :offer_current
)

rem ---- the tools
curl.exe --version >nul 2>nul
if errorlevel 1 goto :use_powershell
tar.exe --version >nul 2>nul
if errorlevel 1 goto :use_powershell

set "WORK=%TEMP%\verdandi-update"
if exist "%WORK%" rd /s /q "%WORK%" >nul 2>nul
mkdir "%WORK%" >nul 2>nul
if not exist "%WORK%" (
  echo.
  echo  Cannot make the temporary folder %WORK%. Is the disk full or is the TEMP folder write-protected?
  goto :offer_current
)

rem ---- which build is the newest?
echo.
echo  Looking for the newest build ...
curl.exe -f -L -sS --retry 2 --connect-timeout 20 -o "%WORK%\BUILD.txt" "%BASE%/BUILD.txt"
set "RC=%errorlevel%"
if not "%RC%"=="0" goto :download_failed
set "LATEST=" & set "LVER=" & set "LHASH="
for /f "usebackq tokens=1,2" %%a in ("%WORK%\BUILD.txt") do if not defined LATEST call :set_latest "%%a" "%%b"
rem the version and the hash become part of a folder name: only digits and dots, and hex digits (checked by taking those characters away: nothing may be left)
if not defined LVER goto :bad_latest
if not defined LHASH goto :bad_latest
set "CHK=!LVER!"
for %%c in (0 1 2 3 4 5 6 7 8 9 .) do if defined CHK call set "CHK=%%CHK:%%c=%%"
if defined CHK goto :bad_latest
set "CHK=!LHASH!"
for %%c in (0 1 2 3 4 5 6 7 8 9 a b c d e f) do if defined CHK call set "CHK=%%CHK:%%c=%%"
if defined CHK goto :bad_latest
set "NEWNAME=!NAMEPFX!-!LVER!-!LHASH!"
echo  The newest build is:     !LVER! !LHASH!

if /i "!LATEST!"=="!CURRENT!" (
  echo.
  echo  You already have the newest build.
  set "TARGET=%HERE%"
  goto :got_target
)
if exist "%PARENT%\!NEWNAME!\Verdandi.exe" (
  echo.
  echo  The newest build is already unpacked: %PARENT%\!NEWNAME!
  set "TARGET=%PARENT%\!NEWNAME!"
  goto :got_target
)

rem ---- download
echo.
echo  Downloading the newest build (about 20 MB; this can take a minute) ...
curl.exe -f -L -# --retry 2 --connect-timeout 20 -o "%WORK%\new.zip" "%BASE%/%ZIPNAME%.zip"
set "RC=%errorlevel%"
if not "%RC%"=="0" goto :download_failed
set "SIZE=0"
for %%F in ("%WORK%\new.zip") do set "SIZE=%%~zF"
if %SIZE% LSS 1000000 (
  echo.
  echo  The downloaded file is only %SIZE% bytes: that is an error page, not the zip. Nothing was changed.
  goto :offer_current
)
rem the SHA-256 of the zip, when the release has one (certutil is part of Windows)
curl.exe -f -L -sS --retry 1 --connect-timeout 20 -o "%WORK%\new.sha256" "%BASE%/%ZIPNAME%.zip.sha256" >nul 2>nul
if exist "%WORK%\new.sha256" (
  set "EXPECT="
  for /f "usebackq tokens=1" %%e in ("%WORK%\new.sha256") do if not defined EXPECT set "EXPECT=%%e"
  set "ACTUAL="
  for /f "skip=1 delims=" %%h in ('certutil -hashfile "%WORK%\new.zip" SHA256 2^>nul') do if not defined ACTUAL set "ACTUAL=%%h"
  if defined ACTUAL set "ACTUAL=!ACTUAL: =!"
  if defined EXPECT if defined ACTUAL (
    if /i not "!EXPECT!"=="!ACTUAL!" (
      echo.
      echo  The downloaded zip does not match its checksum ^(it is damaged or incomplete^). Nothing was changed. Try again.
      goto :offer_current
    )
    echo  Checksum ok.
  )
)

rem ---- unpack into a folder of its own (first into a temporary folder on the same drive, then renamed: a half unpacked build never has the final name)
echo  Unpacking ...
set "TMPUNPACK=%PARENT%\.verdandi-unpack"
if exist "%TMPUNPACK%" rd /s /q "%TMPUNPACK%" >nul 2>nul
mkdir "%TMPUNPACK%" >nul 2>nul
tar.exe -xf "%WORK%\new.zip" -C "%TMPUNPACK%"
if errorlevel 1 goto :unpack_failed
set "UNPACKED="
for /f "delims=" %%D in ('dir /b /ad "%TMPUNPACK%\Verdandi*" 2^>nul') do if not defined UNPACKED set "UNPACKED=%TMPUNPACK%\%%D"
if not defined UNPACKED goto :unpack_failed
if not exist "!UNPACKED!\Verdandi.exe" goto :unpack_failed
move "!UNPACKED!" "%PARENT%\!NEWNAME!" >nul
if errorlevel 1 goto :unpack_failed
rd /s /q "%TMPUNPACK%" >nul 2>nul
set "TARGET=%PARENT%\!NEWNAME!"
echo  Unpacked: !TARGET!
goto :got_target

:got_target
rem ---- a running Verdandi would be brought to the front instead of the new one starting
tasklist /FI "IMAGENAME eq Verdandi.exe" 2>nul | find /i "Verdandi.exe" >nul
if not errorlevel 1 (
  echo.
  echo  Verdandi is running now. The new build can only start when it is closed ^(its data is saved when it ends^).
  if defined YES (
    set "ANSWER=Y"
  ) else (
    %CHOICE% /C YN /M " Close Verdandi now"
    if errorlevel 2 (set "ANSWER=N") else (set "ANSWER=Y")
  )
  if /i "!ANSWER!"=="Y" (
    taskkill /F /IM Verdandi.exe /IM norns.exe /IM sclang.exe /IM scsynth.exe >nul 2>nul
    ping -n 3 127.0.0.1 >nul
  ) else (
    echo  Not closed. The new build is unpacked in !TARGET!; start it from there when you have closed Verdandi.
    goto :end
  )
)

rem ---- older builds
if defined KEEP goto :start_it
set "OLDLIST="
set "OLDCOUNT=0"
for /f "delims=" %%D in ('dir /b /ad "%PARENT%\Verdandi*" 2^>nul') do call :consider "%PARENT%\%%D"
if "%OLDCOUNT%"=="0" goto :start_it
echo.
echo  Older unpacked builds next to it ^(your files in %DATA% are not touched^):
for %%P in (%OLDLIST%) do echo    %%~P
echo  The folder this script was started from ^(%HERE%^) is not removed by it; delete it yourself later if you want.
%CHOICE% /C YN /D N /T 60 /M " Remove these older builds (no after 60 seconds)"
if errorlevel 2 goto :start_it
for %%P in (%OLDLIST%) do call :remove_one "%%~P"
goto :start_it

rem a folder that holds Verdandi.exe and norns.exe and is not the new build, not the data folder and not this one
:consider
set "CAND=%~1"
if /i "%CAND%"=="%TARGET%" exit /b 0
if /i "%CAND%"=="%DATA%" exit /b 0
if /i "%CAND%"=="%HERE%" exit /b 0
if not exist "%CAND%\Verdandi.exe" exit /b 0
if not exist "%CAND%\norns.exe" exit /b 0
set /a OLDCOUNT+=1
set "OLDLIST=%OLDLIST% "%CAND%""
exit /b 0

:remove_one
rd /s /q "%~1" >nul 2>nul
if exist "%~1" (echo    could not remove %~1 ^(something in it is still open^)) else (echo    removed %~1)
exit /b 0

:start_it
if defined NOSTART goto :end
echo.
echo  Starting Verdandi ...
start "" /D "!TARGET!" "!TARGET!\Verdandi.exe"
goto :end

:set_latest
set "LVER=%~1"
set "LHASH=%~2"
set "LATEST=%~1 %~2"
exit /b 0

rem ---- things that went wrong, in plain words
:download_failed
echo.
if "%RC%"=="22" (
  echo  There is no published build at
  echo    %BASE%
  echo  Either nothing has been published yet, or the repository is private ^(then this script cannot download; download the zip in a browser while logged in to GitHub^).
) else if "%RC%"=="6" (
  echo  Cannot find the server: there seems to be no internet connection, or a DNS or proxy problem.
) else if "%RC%"=="7" (
  echo  Cannot connect to the server: no internet, or a firewall or proxy blocks curl.exe.
) else if "%RC%"=="28" (
  echo  The server did not answer in time. Try again in a minute.
) else (
  echo  The download failed ^(curl.exe error %RC%^).
)
echo  Nothing was changed. You can also open the Releases page of the repository in a browser and download the zip by hand.
goto :offer_current

:bad_latest
echo.
echo  The newest build's BUILD.txt is not in the expected form ^("!LATEST!"^). Nothing was changed.
goto :offer_current

:unpack_failed
echo.
echo  The zip could not be unpacked ^(tar.exe failed^). Is the drive full or write-protected, or is a file of an old build open? Nothing was changed.
if exist "%TMPUNPACK%" rd /s /q "%TMPUNPACK%" >nul 2>nul
goto :offer_current

:use_powershell
echo.
echo  curl.exe or tar.exe is missing ^(they come with Windows 10 version 1803 and later^): using PowerShell instead.
if defined NOSTART (set "PSARGS=-NoStart") else (set "PSARGS=")
if defined KEEP set "PSARGS=!PSARGS! -KeepOld"
if defined YES set "PSARGS=!PSARGS! -Yes"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%\update-and-run.ps1" !PSARGS!
exit /b %errorlevel%

rem when the newest build cannot be fetched, the one in this folder can still be started
:offer_current
if defined NOSTART goto :end_fail
if not exist "%HERE%\Verdandi.exe" goto :end_fail
echo.
%CHOICE% /C YN /D Y /T 30 /M " Start the build in this folder anyway (yes after 30 seconds)"
if errorlevel 2 goto :end_fail
set "TARGET=%HERE%"
goto :start_it

:end_fail
echo.
if not defined NOSTART pause
endlocal & exit /b 2

:end
endlocal & exit /b 0
