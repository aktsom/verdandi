<#
update-and-run.ps1: get the newest Verdandi build, unpack it next to the old ones, start it. The PowerShell variant of update-and-run.cmd (the same steps; the cmd one is used when curl.exe and tar.exe exist).
No administrator rights, no installation. Windows PowerShell 5.1 (Windows 10 and 11) is enough.
  1. reads which build this folder is (BUILD.txt) and which build is the newest (BUILD.txt of the GitHub release "windows-latest")
  2. if the newest is not here yet: downloads the zip, checks its size and its SHA-256 when the release has one, unpacks it into a NEW folder Verdandi-<version>-<hash> next to this one
  3. closes a running Verdandi after asking, offers to remove the older unpacked builds (default: no), starts the new Verdandi.exe
Your files are in %USERPROFILE%\Verdandi and are never touched: only folders that hold Verdandi.exe and norns.exe can be removed.
Options: -NoStart (do not start at the end)  -KeepOld (do not offer to remove older builds)  -Yes (close a running Verdandi without asking)
For tests: $env:VERDANDI_UPDATE_BASE (a folder or an address of the release files instead of GitHub), $env:VERDANDI_UPDATE_SOURCE (owner/repository)
#>
param([switch]$NoStart, [switch]$KeepOld, [switch]$Yes)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # (Invoke-WebRequest is very slow with the progress bar of Windows PowerShell 5.1)
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

function Say([string]$text) { Write-Host $text }
function Ask([string]$question, [bool]$default) {
    $hint = if ($default) { 'Y/n' } else { 'y/N' }
    $a = Read-Host "$question [$hint]"
    if ([string]::IsNullOrWhiteSpace($a)) { return $default }
    return $a.Trim().ToLower().StartsWith('y')
}
function Finish([int]$code) { if ($code -ne 0 -and -not $NoStart) { Read-Host 'Press Enter to close this window' | Out-Null }; exit $code }

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$parent = Split-Path -Parent $here
$data = if ($env:VERDANDI_HOME) { $env:VERDANDI_HOME } else { Join-Path $env:USERPROFILE 'Verdandi' }
$tag = 'windows-latest'
# the ASIO build (FLAVOR.txt in its folder) updates to the ASIO build: its own zip and folder name
$zipName = 'Verdandi-windows-latest'
$namePrefix = 'Verdandi'
if (Test-Path (Join-Path $here 'FLAVOR.txt')) { $zipName = 'Verdandi-windows-asio-latest'; $namePrefix = 'Verdandi-asio' }

Say ''
Say ' Verdandi: update and run'
Say ' ------------------------'
$current = 'unknown'
$buildFile = Join-Path $here 'BUILD.txt'
if (Test-Path $buildFile) { $current = (Get-Content $buildFile -TotalCount 1).Trim() }
Say " This folder holds build: $current"
Say "   $here"

function Start-Build([string]$target) {
    if ($NoStart) { return }
    Say ''
    Say ' Starting Verdandi ...'
    Start-Process -FilePath (Join-Path $target 'Verdandi.exe') -WorkingDirectory $target
}
function Offer-Current([int]$code) {
    if (-not $NoStart -and (Test-Path (Join-Path $here 'Verdandi.exe'))) {
        Say ''
        if (Ask ' Start the build in this folder anyway?' $true) { Start-Build $here; exit 0 }
    }
    Finish $code
}

# where the releases are
$repo = $env:VERDANDI_UPDATE_SOURCE
$sourceFile = Join-Path $here 'UPDATE-SOURCE.txt'
if (-not $repo -and (Test-Path $sourceFile)) { $repo = (Get-Content $sourceFile -TotalCount 1).Trim() }
$base = $env:VERDANDI_UPDATE_BASE
if (-not $base -and $repo) { $base = "https://github.com/$repo/releases/download/$tag" }
if (-not $base) {
    Say ''
    Say ' This copy does not know where the newest build is published: UPDATE-SOURCE.txt is missing or empty.'
    Say ' Download the zip by hand from the Releases page of the repository, or ask for a newer zip.'
    Offer-Current 2
}

function Fetch([string]$name, [string]$outFile, [bool]$required) {
    $src = "$base/$name"
    try {
        if (Test-Path -LiteralPath $base -PathType Container -ErrorAction SilentlyContinue) {
            Copy-Item -LiteralPath (Join-Path $base $name) -Destination $outFile -Force   # (a folder instead of an address: the tests)
        } else {
            Invoke-WebRequest -Uri $src -OutFile $outFile -UseBasicParsing -TimeoutSec 600
        }
        return $true
    } catch {
        if (-not $required) { return $false }
        $msg = $_.Exception.Message
        Say ''
        if ($msg -match '404') {
            Say " There is no published build at $base"
            Say ' Either nothing has been published yet, or the repository is private (then this script cannot download; download the zip in a browser while logged in to GitHub).'
        } elseif ($msg -match 'resolved|remote name|No such host|unable to connect|timed out|connection') {
            Say ' Cannot reach the server: there seems to be no internet connection, or a firewall or proxy is in the way.'
        } else {
            Say " The download failed: $msg"
        }
        Say ' Nothing was changed. You can also open the Releases page of the repository in a browser and download the zip by hand.'
        Offer-Current 2
    }
}

$work = Join-Path $env:TEMP 'verdandi-update'
if (Test-Path $work) { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $work -Force | Out-Null

Say ''
Say ' Looking for the newest build ...'
Fetch 'BUILD.txt' (Join-Path $work 'BUILD.txt') $true | Out-Null
$latest = (Get-Content (Join-Path $work 'BUILD.txt') -TotalCount 1).Trim()
$m = [regex]::Match($latest, '^([0-9][0-9.]*) ([0-9a-f]+)$')
if (-not $m.Success) {
    Say ''
    Say " The newest build's BUILD.txt is not in the expected form (`"$latest`"). Nothing was changed."
    Offer-Current 2
}
$newName = "$namePrefix-$($m.Groups[1].Value)-$($m.Groups[2].Value)"
Say " The newest build is:     $latest"

$target = $null
if ($latest -eq $current) {
    Say ''
    Say ' You already have the newest build.'
    $target = $here
} elseif (Test-Path (Join-Path (Join-Path $parent $newName) 'Verdandi.exe')) {
    Say ''
    Say " The newest build is already unpacked: $(Join-Path $parent $newName)"
    $target = Join-Path $parent $newName
} else {
    Say ''
    Say ' Downloading the newest build (about 20 MB; this can take a minute) ...'
    $zip = Join-Path $work 'new.zip'
    Fetch "$zipName.zip" $zip $true | Out-Null
    $size = (Get-Item $zip).Length
    if ($size -lt 1000000) {
        Say ''
        Say " The downloaded file is only $size bytes: that is an error page, not the zip. Nothing was changed."
        Offer-Current 2
    }
    $shaFile = Join-Path $work 'new.sha256'
    if (Fetch "$zipName.zip.sha256" $shaFile $false) {
        $expect = ((Get-Content $shaFile -TotalCount 1).Trim() -split '\s+')[0]
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash
        if ($expect -and ($expect -ine $actual)) {
            Say ''
            Say ' The downloaded zip does not match its checksum (it is damaged or incomplete). Nothing was changed. Try again.'
            Offer-Current 2
        }
        Say ' Checksum ok.'
    }
    Say ' Unpacking ...'
    $tmp = Join-Path $parent '.verdandi-unpack'
    try {
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
        $unpacked = Get-ChildItem $tmp -Directory -Filter 'Verdandi*' | Select-Object -First 1
        if (-not $unpacked -or -not (Test-Path (Join-Path $unpacked.FullName 'Verdandi.exe'))) { throw 'the zip has no Verdandi folder with Verdandi.exe' }
        Move-Item -LiteralPath $unpacked.FullName -Destination (Join-Path $parent $newName)
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    } catch {
        Say ''
        Say " The zip could not be unpacked ($($_.Exception.Message)). Is the drive full or write-protected, or is a file of an old build open? Nothing was changed."
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
        Offer-Current 2
    }
    $target = Join-Path $parent $newName
    Say " Unpacked: $target"
}

# a running Verdandi would be brought to the front instead of the new one starting
$running = Get-Process -Name Verdandi -ErrorAction SilentlyContinue
if ($running) {
    Say ''
    Say ' Verdandi is running now. The new build can only start when it is closed (its data is saved when it ends).'
    if ($Yes -or (Ask ' Close Verdandi now?' $true)) {
        Get-Process -Name Verdandi, norns, sclang, scsynth -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    } else {
        Say " Not closed. The new build is unpacked in $target; start it from there when you have closed Verdandi."
        Finish 0
    }
}

# older builds: folders next to the new one that hold Verdandi.exe and norns.exe (never the data folder, never the new build)
if (-not $KeepOld) {
    Set-Location $parent
    $old = @(Get-ChildItem $parent -Directory -Filter 'Verdandi*' -ErrorAction SilentlyContinue | Where-Object {
        $_.FullName -ne $target -and $_.FullName -ne $data -and
        (Test-Path (Join-Path $_.FullName 'Verdandi.exe')) -and (Test-Path (Join-Path $_.FullName 'norns.exe')) })
    if ($old.Count -gt 0) {
        Say ''
        Say " Older unpacked builds next to it (your files in $data are not touched):"
        $old | ForEach-Object { Say "   $($_.FullName)" }
        if (Ask ' Remove these older builds?' $false) {
            foreach ($d in $old) {
                try { Remove-Item -LiteralPath $d.FullName -Recurse -Force; Say "   removed $($d.FullName)" }
                catch { Say "   could not remove $($d.FullName) (something in it is still open)" }
            }
        }
    }
}

Start-Build $target
exit 0
