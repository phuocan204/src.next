[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$distro = "Ubuntu"
$projectRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path

Write-Host "Kiwi Browser ARM64 release builder" -ForegroundColor Cyan
Write-Host "Project: $projectRoot"

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw "WSL is not installed. Run 'wsl --install -d Ubuntu', restart Windows, then run this file again."
}

$installedDistros = @(& wsl.exe --list --quiet 2>$null) -replace "`0", ""
if ($installedDistros -notcontains $distro) {
    throw "The Ubuntu WSL distribution is not installed. Run 'wsl --install -d Ubuntu', restart if requested, then try again."
}

if ($projectRoot -notmatch '^(?<Drive>[A-Za-z]):(?<Path>\\.*)$') {
    throw "The project must be stored on a local Windows drive. Unsupported path: $projectRoot"
}
$driveLetter = $Matches.Drive.ToLowerInvariant()
$linuxPath = $Matches.Path.Replace('\', '/')
$wslProjectRoot = "/mnt/$driveLetter$linuxPath"

$wslBuildScript = "$wslProjectRoot/.build/build_release_wsl.sh"
Write-Host "The first build can take several hours and needs roughly 100 GB of free disk space." -ForegroundColor Yellow
Write-Host "You may run this file again after an interrupted build; Ninja will reuse completed work." -ForegroundColor Yellow
Write-Host ""

& wsl.exe -d $distro -u root -- bash $wslBuildScript $wslProjectRoot
if ($LASTEXITCODE -ne 0) {
    throw "Release build failed (exit code $LASTEXITCODE). Check release-apk/build.log."
}

$apkPath = Join-Path $projectRoot "release-apk\KiwiBrowser-arm64-release.apk"
if (-not (Test-Path -LiteralPath $apkPath)) {
    throw "The build command finished but the expected APK was not found: $apkPath"
}

Write-Host ""
Write-Host "Release APK ready:" -ForegroundColor Green
Write-Host $apkPath
