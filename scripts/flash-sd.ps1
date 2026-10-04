<#
.SYNOPSIS
  Writes the rockbandPi image to an SD card, adds the SONGS partition and
  copies the songs folder onto it (Windows).

.DESCRIPTION
  Uses Raspberry Pi Imager's command-line mode to write and verify the image
  (install it from https://www.raspberrypi.com/software/), then creates the
  exFAT SONGS partition and copies .\songs onto it with robocopy.
  Everything on the card is erased.

  Run from an elevated PowerShell (Run as Administrator).

.EXAMPLE
  .\scripts\flash-sd.ps1                     # pick the card from a list
  .\scripts\flash-sd.ps1 -DiskNumber 2
  .\scripts\flash-sd.ps1 -Image deploy\rockbandPi.img -Songs D:\RockBand
#>
#Requires -RunAsAdministrator
param(
    [int]$DiskNumber = -1,
    [string]$Image = "",
    [string]$Songs = (Join-Path $PSScriptRoot "..\songs")
)
$ErrorActionPreference = "Stop"

if ($DiskNumber -lt 0) {
    # Removable drives only (SD, USB); never system or boot disks or empty card-reader slots
    $candidates = @(Get-Disk | Where-Object {
        $_.BusType -in @("USB", "SD", "MMC") -and -not $_.IsSystem -and -not $_.IsBoot -and $_.Size -gt 0
    } | Sort-Object Number)
    if ($candidates.Count -eq 0) { throw "No SD card or USB drive found. Insert the card and try again." }

    Write-Host "Removable drives:"
    for ($i = 0; $i -lt $candidates.Count; $i++) {
        $d = $candidates[$i]
        $labels = (Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue |
            Get-Volume -ErrorAction SilentlyContinue |
            Where-Object FileSystemLabel | ForEach-Object FileSystemLabel) -join ","
        $line = "  {0}) disk {1}  {2} GB  {3}  {4}" -f ($i + 1), $d.Number, [math]::Round($d.Size / 1GB, 1), $d.BusType, $d.FriendlyName
        if ($labels) { $line += "  [partitions: $labels]" }
        Write-Host $line
    }
    Write-Host ""
    $choice = Read-Host "Flash which drive? [1-$($candidates.Count)]"
    $n = 0
    if (-not [int]::TryParse($choice, [ref]$n) -or $n -lt 1 -or $n -gt $candidates.Count) {
        Write-Host "Aborted."
        exit 1
    }
    $DiskNumber = $candidates[$n - 1].Number
}

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not $Image) {
    $Image = Get-ChildItem (Join-Path $repo "deploy") -Filter "*.img*" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $Image -or -not (Test-Path $Image)) {
    throw "No image found; build one with .\scripts\build-image.ps1 first."
}
$Image = (Resolve-Path $Image).Path

$disk = Get-Disk -Number $DiskNumber
if ($disk.IsSystem -or $disk.IsBoot) { throw "Disk $DiskNumber is a system/boot disk. Refusing." }
if ($disk.BusType -notin @("USB", "SD", "MMC")) {
    throw "Disk $DiskNumber is on bus '$($disk.BusType)', not USB/SD. Refusing to be safe."
}

$imagerDirs = @($env:ProgramFiles, [Environment]::GetEnvironmentVariable("ProgramFiles(x86)"))
$imager = $imagerDirs | Where-Object { $_ } |
    ForEach-Object { Join-Path $_ "Raspberry Pi Imager\rpi-imager.exe" } |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $imager) {
    throw "Raspberry Pi Imager not found. Install it from https://www.raspberrypi.com/software/"
}

$sizeGb = [math]::Round($disk.Size / 1GB, 1)
Write-Host "Disk:  $DiskNumber  $($disk.FriendlyName)  ($sizeGb GB, $($disk.BusType))"
Write-Host "Image: $Image"
Write-Host "Songs: $Songs"
Write-Host ""
$answer = Read-Host "ALL DATA ON DISK $DiskNumber WILL BE ERASED. Type the disk number to continue"
if ($answer -ne "$DiskNumber") { Write-Host "Aborted."; exit 1 }

Write-Host "Writing with Raspberry Pi Imager (this takes a while)..."
$imagerArgs = @("--cli", "`"$Image`"", "\\.\PHYSICALDRIVE$DiskNumber")
$proc = Start-Process -FilePath $imager -ArgumentList $imagerArgs -NoNewWindow -Wait -PassThru
if ($proc.ExitCode -ne 0) { throw "Raspberry Pi Imager failed (exit code $($proc.ExitCode))." }

# Let Windows re-read the new partition table
Write-Host "Waiting for Windows to re-read the card..."
$ready = $false
for ($i = 0; $i -lt 30 -and -not $ready; $i++) {
    Update-HostStorageCache
    Start-Sleep -Seconds 1
    $ready = [bool](Get-Partition -DiskNumber $DiskNumber -PartitionNumber 2 -ErrorAction SilentlyContinue)
}
if (-not $ready) {
    throw "The card's partitions did not show up. Remove and reinsert it, then run: .\scripts\copy-songs.ps1 -DiskNumber $DiskNumber"
}

& (Join-Path $PSScriptRoot "copy-songs.ps1") -DiskNumber $DiskNumber -Songs $Songs

Write-Host ""
Write-Host "Done. If Windows offers to format the card's Linux partition, click Cancel."
Write-Host "Eject the card, put it in the Pi and power it on."
