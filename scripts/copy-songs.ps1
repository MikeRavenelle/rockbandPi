<#
.SYNOPSIS
  Copies the songs folder onto the rockbandPi SONGS partition (Windows).

.DESCRIPTION
  Copies only new or changed files and never deletes anything on the card.

  With -DiskNumber (run as Administrator) it first creates and formats the
  SONGS partition if the card doesn't have one yet. flash-sd.ps1 does this
  automatically after writing the image.

  Without -DiskNumber it looks for a drive labelled SONGS, or copies over the
  network to the Pi's "songs" share with -Network.

.EXAMPLE
  .\scripts\copy-songs.ps1                      # card inserted: finds the SONGS drive
  .\scripts\copy-songs.ps1 -DiskNumber 2        # create SONGS on disk 2 if needed, then copy
  .\scripts\copy-songs.ps1 -Destination E:\     # a specific drive
  .\scripts\copy-songs.ps1 -Network rockband.local -User rockband
#>
param(
    [int]$DiskNumber = -1,
    [string]$Destination = "",
    [string]$Network = "",
    [string]$User = "rockband",
    [string]$Songs = (Join-Path $PSScriptRoot "..\songs")
)
$ErrorActionPreference = "Stop"

# Must match ROOT_SIZE_GIB in scripts/lib/songs-partition.sh and setup-partitions.sh
$RootSizeBytes = 16GB

function New-SongsPartition([int]$Number) {
    $disk = Get-Disk -Number $Number
    if ($disk.IsSystem -or $disk.IsBoot) { throw "Disk $Number is a system/boot disk. Refusing." }
    if ($disk.IsOffline) { Set-Disk -Number $Number -IsOffline $false }
    if ($disk.IsReadOnly) { Set-Disk -Number $Number -IsReadOnly $false }

    $existing = Get-Partition -DiskNumber $Number -ErrorAction SilentlyContinue |
        Get-Volume -ErrorAction SilentlyContinue | Where-Object FileSystemLabel -eq "SONGS"
    if ($existing) { return }

    $root = Get-Partition -DiskNumber $Number -PartitionNumber 2 -ErrorAction SilentlyContinue
    if (-not $root) { throw "Disk $Number has no rockbandPi system partition. Flash the image first." }

    # Same layout as the Linux/macOS flash script: SONGS starts 16 GB after the
    # system partition; the Pi grows the system partition into the gap.
    $offset = $root.Offset + $RootSizeBytes
    $minOffset = $root.Offset + $root.Size
    if ($offset -lt $minOffset) { $offset = $minOffset }
    $offset = [math]::Ceiling($offset / 1MB) * 1MB
    if ($disk.Size - $offset -lt 1GB) { throw "Card too small for a SONGS partition." }

    Write-Host "Creating the SONGS partition (exFAT)..."
    $part = New-Partition -DiskNumber $Number -Offset $offset -UseMaximumSize -MbrType IFS
    $null = Format-Volume -Partition $part -FileSystem exFAT -NewFileSystemLabel SONGS -Confirm:$false
    $part | Add-PartitionAccessPath -AssignDriveLetter
}

function Find-SongsDrive([int]$Number) {
    $vols = if ($Number -ge 0) {
        Get-Partition -DiskNumber $Number -ErrorAction SilentlyContinue | Get-Volume -ErrorAction SilentlyContinue
    } else {
        Get-Volume -ErrorAction SilentlyContinue
    }
    $vol = $vols | Where-Object { $_.FileSystemLabel -eq "SONGS" -and $_.DriveLetter } | Select-Object -First 1
    if ($vol) { return "$($vol.DriveLetter):\" }
    return $null
}

$Songs = (Resolve-Path $Songs).Path

if ($Network) {
    $Destination = "\\$Network\songs"
    if (-not (Test-Path $Destination)) {
        Write-Host "Connecting to $Destination as $User (use the kiosk password)..."
        & net.exe use $Destination /user:$User *
        if ($LASTEXITCODE -ne 0) { throw "Could not connect to $Destination." }
    }
} elseif (-not $Destination) {
    if ($DiskNumber -ge 0) { New-SongsPartition $DiskNumber }
    $Destination = Find-SongsDrive $DiskNumber
    if (-not $Destination) {
        throw "No SONGS drive found. Use -DiskNumber <n> (as Administrator) to create it, or -Destination / -Network."
    }
}

$hasSongs = Get-ChildItem $Songs -Force | Where-Object Name -ne "README.md" | Select-Object -First 1
if (-not $hasSongs) {
    Write-Host "No songs in $Songs; nothing to copy."
    exit 0
}

Write-Host "Copying $Songs -> $Destination (only new/changed files; can take a long time)"
# /E subfolders, /FFT exFAT 2-second timestamps, /XO skip older, /XF skip the README
& robocopy.exe $Songs $Destination /E /FFT /XO /XF README.md /R:1 /W:1 /MT:8 /NP /NDL
if ($LASTEXITCODE -ge 8) { throw "robocopy failed (exit code $LASTEXITCODE)." }

Write-Host ""
if ($Network) {
    Write-Host "Done. Refresh the library in YARG (Settings > Songs)."
} else {
    Write-Host "Done. Eject the card before removing it."
}
