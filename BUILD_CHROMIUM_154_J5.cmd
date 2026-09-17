@echo off
setlocal
title Kiwi Chromium 154 Full ARM64 Release Builder - j5

cd /d "%~dp0"
echo Kiwi Chromium 154 Full ARM64 builder
echo Includes: toolbar customization, extension menu, popup and actions
echo Jobs: 5
echo Project: %CD%
echo.

wsl -d Ubuntu -- bash "/mnt/c/Users/phuoc/Downloads/src.next/.build/build_chromium154_apk.sh"
set "BUILD_EXIT=%ERRORLEVEL%"

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
