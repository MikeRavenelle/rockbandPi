<#
.SYNOPSIS
  Builds the rockbandPi SD card image on Windows by running scripts/build-image.sh in WSL.

.DESCRIPTION
  pi-gen needs Linux, so the build runs inside WSL 2 (Ubuntu or Debian), using
  Docker Desktop's WSL integration or Podman installed in the distro.

  Clone the repository inside WSL (for example ~/rockbandPi) for a much faster
  build and correct line endings. A clone on C:\ works if Git was set to
  core.autocrlf=false before cloning.

.EXAMPLE
  .\scripts\build-image.ps1
  .\scripts\build-image.ps1 -Distro Ubuntu -Config config/kiosk.conf
#>
param(
    [string]$Distro = "",
    [string]$Config = "config/kiosk.conf"
)
$ErrorActionPreference = "Stop"

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw "WSL is not installed. Run 'wsl --install' (as Administrator), reboot, then try again."
}

$wslArgs = @()
if ($Distro) { $wslArgs += @("-d", $Distro) }

# Translate the repo path into the WSL view (\\wsl$\... or C:\...)
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$repoWsl = (& wsl.exe @wslArgs -e wslpath -a ($repo -replace '\\', '/')).Trim()
if (-not $repoWsl) { throw "Could not translate $repo into a WSL path." }

Write-Host "Building in WSL at $repoWsl"
& wsl.exe @wslArgs -e bash -lc "cd '$repoWsl' && scripts/build-image.sh '$Config'"
if ($LASTEXITCODE -ne 0) { throw "Build failed (exit code $LASTEXITCODE)." }

Write-Host ""
Write-Host "Done. The image is in $repo\deploy. Flash it with:"
Write-Host "  .\scripts\flash-sd.ps1 -DiskNumber <n>"
