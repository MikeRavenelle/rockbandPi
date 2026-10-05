<#
.SYNOPSIS
  Builds YARG from source as a Linux x86_64 IL2CPP player on Windows by running
  scripts/build-yarg.sh in WSL.

.DESCRIPTION
  The Unity editor runs in a Linux container, so the build runs inside WSL 2
  (Ubuntu or Debian), using Docker Desktop's WSL integration or Podman
  installed in the distro.

  It needs a Unity Personal license file. Activate one by signing in to Unity
  Hub; the Windows license file is C:\ProgramData\Unity\Unity_lic.ulf, and it
  is passed to the build automatically when it exists.

  The result is build\yarg\player. To put it in the image, set
  YARG_SOURCE=local in config\kiosk.conf and run .\scripts\build-image.ps1.

.EXAMPLE
  .\scripts\build-yarg.ps1
  .\scripts\build-yarg.ps1 -Distro Ubuntu -License C:\path\to\Unity_lic.ulf
#>
param(
    [string]$Distro = "",
    [string]$License = "$env:ProgramData\Unity\Unity_lic.ulf"
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

$envPrefix = ""
if (Test-Path $License) {
    $licenseWsl = (& wsl.exe @wslArgs -e wslpath -a ($License -replace '\\', '/')).Trim()
    $envPrefix = "UNITY_LICENSE_FILE='$licenseWsl' "
}

Write-Host "Building YARG in WSL at $repoWsl"
& wsl.exe @wslArgs -e bash -lc "cd '$repoWsl' && ${envPrefix}scripts/build-yarg.sh"
if ($LASTEXITCODE -ne 0) { throw "YARG build failed (exit code $LASTEXITCODE)." }

Write-Host ""
Write-Host "Done. The YARG player is in $repo\build\yarg\player."
Write-Host "Set YARG_SOURCE=local in config\kiosk.conf, then run .\scripts\build-image.ps1"
