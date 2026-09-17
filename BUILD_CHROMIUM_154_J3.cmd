@echo off
setlocal
title Kiwi Chromium 154 ARM64 Release Builder - j3

cd /d "%~dp0"
echo Kiwi Chromium 154 ARM64 builder
echo Jobs: 3
echo Project: %CD%
echo.

wsl -d Ubuntu -- env JOBS=3 bash "/mnt/c/Users/phuoc/Downloads/src.next/.build/build_chromium154_apk.sh"
set "BUILD_EXIT=%ERRORLEVEL%"

wsl -d Ubuntu -- bash -lc "if [ -f /root/chromium154/src/out/KiwiReleaseNinja/kiwi-build.log ]; then cp -f /root/chromium154/src/out/KiwiReleaseNinja/kiwi-build.log /mnt/c/Users/phuoc/Downloads/src.next/release-apk/chromium154/build.log; fi" >nul 2>&1
>>"release-apk\chromium154\launcher.log" echo [%DATE% %TIME%] WSL exit code: %BUILD_EXIT%

echo.
if not "%BUILD_EXIT%"=="0" (
    echo Build failed with exit code %BUILD_EXIT%.
    echo See release-apk\chromium154\build.log
) else (
    echo Build successful.
    echo APK: release-apk\chromium154\Kiwi-Chromium154-arm64.apk
)
echo.
pause
exit /b %BUILD_EXIT%
