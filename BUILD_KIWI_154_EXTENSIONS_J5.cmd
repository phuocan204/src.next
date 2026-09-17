@echo off
setlocal
title Kiwi Chromium 154 Extensions ARM64 Builder - j5

cd /d "%~dp0"
echo Kiwi Chromium 154 Extensions ARM64 builder
echo Jobs: 5
echo Build cache: /root/chromium154/src/out/KiwiExtensionProbe
echo.

wsl -d Ubuntu -- bash "/mnt/c/Users/phuoc/Downloads/src.next/.build/build_chromium154_extensions_apk.sh"
set "BUILD_EXIT=%ERRORLEVEL%"

echo.
if not "%BUILD_EXIT%"=="0" (
    echo Build failed with exit code %BUILD_EXIT%.
    echo Run this file again after the latest error is fixed; completed steps are cached.
    echo Log: release-apk\chromium154-extensions\build.log
) else (
    echo Build successful.
    echo APK: release-apk\chromium154-extensions\Kiwi-Chromium154-Extensions-arm64.apk
)
echo.
pause
exit /b %BUILD_EXIT%

