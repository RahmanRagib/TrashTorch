@echo off
setlocal
set "SCRIPT=%~dp0Invoke-SystemCleanup.ps1"

if not exist "%SCRIPT%" (
    echo Could not find "%SCRIPT%".
    echo Make sure Invoke-SystemCleanup.ps1 is in the same folder as this file.
    pause
    exit /b 1
)

net session >nul 2>&1
if %errorlevel% equ 0 goto :run

echo Requesting administrator privileges...
set "ARGS=%*"
if defined ARGS (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs -ArgumentList '%ARGS%'"
) else (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
)
exit /b

:run
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
echo.
pause
