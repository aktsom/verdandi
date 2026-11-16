#!/usr/bin/env bash
# windows/ci/register_asio_stub.sh install|remove [DLL]: registers (or removes) the stub ASIO driver of the CI (windows/ci/asio_stub.c) the way a real driver's installer does: HKLM\SOFTWARE\ASIO\<name> with the CLSID,
# and the class under HKLM\SOFTWARE\Classes\CLSID\<clsid>\InprocServer32, in the 64-bit view. needs administrator rights (the runner has them).
#   REG   the reg command (default: reg; the Linux test uses "wine64 reg")      DLL   the Windows path of the driver file
set -u
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'
REG="${REG:-reg}"
CLSID="{D9B1E8E3-6F1C-4D6A-9C57-7C1A3F7B5E01}"
NAME="Verdandi Test ASIO"
case "${1:-}" in
    install)
        dll="${2:?the driver file}"
        $REG add "HKLM\\SOFTWARE\\ASIO\\$NAME" /v CLSID /d "$CLSID" /f /reg:64 > /dev/null || exit 1
        $REG add "HKLM\\SOFTWARE\\ASIO\\$NAME" /v Description /d "$NAME" /f /reg:64 > /dev/null || exit 1
        $REG add "HKLM\\SOFTWARE\\Classes\\CLSID\\$CLSID" /ve /d "$NAME" /f /reg:64 > /dev/null || exit 1
        $REG add "HKLM\\SOFTWARE\\Classes\\CLSID\\$CLSID\\InprocServer32" /ve /d "$dll" /f /reg:64 > /dev/null || exit 1
        $REG add "HKLM\\SOFTWARE\\Classes\\CLSID\\$CLSID\\InprocServer32" /v ThreadingModel /d Apartment /f /reg:64 > /dev/null || exit 1
        echo "the stub ASIO driver is registered: $NAME -> $dll"
        ;;
    remove)
        $REG delete "HKLM\\SOFTWARE\\ASIO\\$NAME" /f /reg:64 > /dev/null 2>&1
        $REG delete "HKLM\\SOFTWARE\\Classes\\CLSID\\$CLSID" /f /reg:64 > /dev/null 2>&1
        echo "the stub ASIO driver is removed"
        ;;
    *) echo "usage: register_asio_stub.sh install DLL | remove"; exit 2 ;;
esac
