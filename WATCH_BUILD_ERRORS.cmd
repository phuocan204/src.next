@echo off
setlocal
title Kiwi build error watcher
cd /d "%~dp0"
echo Watching release-apk\build.log every 10 minutes...
echo New failures are sent automatically to Codex for repair.
echo Fixer output: release-apk\codex-fixer.log
wsl -d Ubuntu -- python3 "/mnt/c/Users/phuoc/Downloads/src.next/.build/watch_build_errors.py" "/mnt/c/Users/phuoc/Downloads/src.next"
pause
