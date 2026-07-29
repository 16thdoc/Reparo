@echo off
setlocal EnableExtensions

set "TASKNAME=Reparo-Force-AllowReboot-System"
set "SCRIPT=C:\ProgramData\Reparo\Reparo.ps1"
set "PWSH=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "REPARO_ARGS=-Force -AllowReboot"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent()); if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } exit 1"
if errorlevel 1 (
    echo ERROR: This tool must run as Administrator or SYSTEM so it can create a SYSTEM scheduled task.
    exit /b 1
)

echo Checking for Reparo...
if not exist "%SCRIPT%" (
    echo Reparo not found at "%SCRIPT%"
    exit /b 1
)

echo Creating scheduled task to run Reparo %REPARO_ARGS% as SYSTEM...
schtasks /Delete /TN "%TASKNAME%" /F >nul 2>&1
schtasks /Create ^
    /TN "%TASKNAME%" ^
    /SC ONCE ^
    /ST 23:59 ^
    /RU SYSTEM ^
    /RL HIGHEST ^
    /TR "\"%PWSH%\" -NoProfile -ExecutionPolicy Bypass -File \"%SCRIPT%\" %REPARO_ARGS%" ^
    /F

if errorlevel 1 (
    echo Failed to create SYSTEM scheduled task.
    exit /b 1
)

echo Starting Reparo %REPARO_ARGS% SYSTEM task...
schtasks /Run /TN "%TASKNAME%"
if errorlevel 1 (
    echo Failed to start SYSTEM scheduled task.
    exit /b 1
)

echo Reparo %REPARO_ARGS% started as SYSTEM. Windows Update may restart the computer only if required.
echo Check logs under C:\ProgramData\Reparo\Logs
exit /b 0
