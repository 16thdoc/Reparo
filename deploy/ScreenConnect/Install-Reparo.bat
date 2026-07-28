@echo off
setlocal EnableExtensions

set "INSTALL_ROOT=%ProgramData%\Reparo"
set "BOOTSTRAP=%TEMP%\Reparo.bootstrap.ps1"
set "REPARO=%INSTALL_ROOT%\Reparo.ps1"
set "URL=https://raw.githubusercontent.com/16thdoc/Reparo/main/Reparo.ps1"

if /I "%~1"=="-Offline" goto :offline

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent()); if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } exit 1"
if errorlevel 1 (
  echo ERROR: This installer must run as Administrator or SYSTEM so it can install/update ProgramData.
  exit /b 1
)

echo.
echo === Reparo installer ===
echo Install root: %INSTALL_ROOT%
echo Bootstrap:    %BOOTSTRAP%
echo Source:       %URL%
echo.

if exist "%REPARO%" (
  echo Existing Reparo runtime found; this will update it in place.
) else (
  echo No existing Reparo runtime found; this will install it.
)
echo.

if not exist "%INSTALL_ROOT%" mkdir "%INSTALL_ROOT%"
if errorlevel 1 (
  echo ERROR: Could not create "%INSTALL_ROOT%".
  exit /b %errorlevel%
)

echo Downloading Reparo...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop'; [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%URL%' -OutFile '%BOOTSTRAP%' -UseBasicParsing; Unblock-File -LiteralPath '%BOOTSTRAP%' -ErrorAction SilentlyContinue"

if errorlevel 1 (
  echo ERROR: Download failed.
  exit /b %errorlevel%
)

echo Installing/updating Reparo runtime...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BOOTSTRAP%" -New -InstallRoot "%INSTALL_ROOT%" -SourceUrl "%URL%"

if errorlevel 1 (
  echo ERROR: Reparo install failed.
  exit /b %errorlevel%
)

del "%BOOTSTRAP%" >nul 2>&1

if not exist "%REPARO%" (
  echo ERROR: Expected installed script was not found:
  echo   %REPARO%
  exit /b 1
)

echo.
echo Reparo is installed/updated.
echo Reparo owns its command shim and PATH registration.
echo Current window test:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%REPARO%" -Version

echo.
echo You can now run:
echo   reparo
echo   reparo -Update
echo   reparo -Status
echo   reparo -Tail
echo.
echo If an old terminal does not recognize it yet, open a new terminal.

exit /b 0

:offline
echo.
echo === Reparo offline installer mode ===
echo GitHub download skipped.
if not exist "%REPARO%" (
  echo ERROR: Reparo is not installed. Use ScreenConnect-Reparo-Embedded.ps1 for an offline first install.
  exit /b 1
)

echo Existing Reparo runtime found:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%REPARO%" -Version
exit /b %errorlevel%
