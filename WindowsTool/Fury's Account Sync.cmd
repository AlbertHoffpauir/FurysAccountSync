@echo off
title Fury's Account Sync
if not exist "%~dp0FurysAccountSync.ps1" goto missing
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0FurysAccountSync.ps1" %*
if "%errorlevel%"=="0" goto done
echo.
echo Fury's Account Sync stopped with a problem, code %errorlevel%. The lines above say why.
pause
goto done
:missing
echo FurysAccountSync.ps1 is not next to this file.
echo Unzip the whole folder first, then run this file from inside that folder.
pause
:done
