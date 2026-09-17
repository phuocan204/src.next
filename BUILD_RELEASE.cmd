@echo off
setlocal
title Kiwi Browser ARM64 Release Builder

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_release.ps1"
set "BUILD_EXIT=%ERRORLEVEL%"

echo.
if not "%BUILD_EXIT%"=="0" (
  echo Build failed with exit code %BUILD_EXIT%.
  echo See release-apk\build.log for details.
) else (
  echo Build completed successfully.
)
echo.
pause
exit /b %BUILD_EXIT%
