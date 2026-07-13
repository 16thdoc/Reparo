@echo off
setlocal EnableExtensions

set "REPARO_QUIET_INNER=0"
if /I "%~1"=="/__quiet_inner" (
  set "REPARO_QUIET_INNER=1"
  shift /1
)

set "REPARO_QUIET=%REPARO_QUIET%"
if not defined REPARO_QUIET set "REPARO_QUIET=0"
for %%A in (%*) do (
  if /I "%%~A"=="/quiet" set "REPARO_QUIET=1"
  if /I "%%~A"=="-quiet" set "REPARO_QUIET=1"
  if /I "%%~A"=="--quiet" set "REPARO_QUIET=1"
  if /I "%%~A"=="/silent" set "REPARO_QUIET=1"
  if /I "%%~A"=="-silent" set "REPARO_QUIET=1"
  if /I "%%~A"=="--silent" set "REPARO_QUIET=1"
)
if not defined REPARO_INSTALL_LOG set "REPARO_INSTALL_LOG=%TEMP%\reparo-install-windows.log"
if "%REPARO_QUIET%"=="1" if not "%REPARO_QUIET_INNER%"=="1" (
  call "%~f0" /__quiet_inner %* >"%REPARO_INSTALL_LOG%" 2>&1
  exit /b %errorlevel%
)

set "INSTALL_ROOT=%ProgramData%\Reparo"
set "BIN_ROOT=%INSTALL_ROOT%\bin"
set "BOOTSTRAP=%TEMP%\Reparo.bootstrap.ps1"
set "REPARO=%INSTALL_ROOT%\Reparo.ps1"
set "SHIM=%BIN_ROOT%\reparo.cmd"
if not defined REPARO_URL set "REPARO_URL=https://api.github.com/repos/16thdoc/Reparo/contents/Reparo.ps1?ref=main"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent()); if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } exit 1"
if errorlevel 1 (
  echo ERROR: This installer must run as Administrator or SYSTEM so it can install/update ProgramData.
  exit /b 1
)

echo.
echo === Reparo Windows installer ===
echo Install root: %INSTALL_ROOT%
echo Bootstrap:    %BOOTSTRAP%
echo Source:       %REPARO_URL%
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
  "$ErrorActionPreference = 'Stop'; [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12; $url = '%REPARO_URL%'; $headers = @{}; if ($url -match '^https://api\.github\.com/repos/.+/contents/') { $headers['Accept'] = 'application/vnd.github.raw'; $headers['User-Agent'] = 'Reparo' }; if ($url -match '^https://raw\.githubusercontent\.com/') { $sep = if ($url.Contains('?')) { '&' } else { '?' }; $url = ('{0}{1}x={2}' -f $url, $sep, [Uri]::EscapeDataString((Get-Date -Format 'yyyyMMddHHmmss'))); $headers['Cache-Control'] = 'no-cache'; $headers['Pragma'] = 'no-cache' }; Invoke-WebRequest -Uri $url -Headers $headers -OutFile '%BOOTSTRAP%' -UseBasicParsing; Unblock-File -LiteralPath '%BOOTSTRAP%' -ErrorAction SilentlyContinue"

if errorlevel 1 (
  echo ERROR: Download failed.
  exit /b %errorlevel%
)

echo Installing/updating Reparo runtime...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BOOTSTRAP%" -Install -SourceUrl "%BOOTSTRAP%"

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

if not exist "%BIN_ROOT%" mkdir "%BIN_ROOT%"
if errorlevel 1 (
  echo ERROR: Could not create "%BIN_ROOT%".
  exit /b %errorlevel%
)

echo Creating/updating reparo command shim...
> "%SHIM%" echo @echo off
>> "%SHIM%" echo powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%REPARO%" %%*
if errorlevel 1 (
  echo ERROR: Could not create "%SHIM%".
  exit /b %errorlevel%
)

echo Verifying PATH entry for reparo...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop'; $bin = '%BIN_ROOT%'; $sep = [IO.Path]::PathSeparator; $machine = [Environment]::GetEnvironmentVariable('Path','Machine'); $machineParts = @($machine -split [regex]::Escape([string]$sep) | Where-Object { $_ }); $user = [Environment]::GetEnvironmentVariable('Path','User'); $userParts = @($user -split [regex]::Escape([string]$sep) | Where-Object { $_ }); if (($machineParts -contains $bin) -or ($userParts -contains $bin)) { Write-Host 'PATH already includes Reparo bin.'; exit 0 }; try { [Environment]::SetEnvironmentVariable('Path', (@($machineParts) + $bin) -join $sep, 'Machine'); Write-Host 'Added Reparo bin to machine PATH.' } catch { [Environment]::SetEnvironmentVariable('Path', (@($userParts) + $bin) -join $sep, 'User'); Write-Host 'Added Reparo bin to user PATH.' }"

if errorlevel 1 (
  echo ERROR: Could not update PATH.
  exit /b %errorlevel%
)

set "PATH=%PATH%;%BIN_ROOT%"

echo.
echo Reparo is installed/updated.
echo Current window test:
call "%SHIM%" -Version

echo.
echo You can now run:
echo   reparo
echo   reparo -Update
echo   reparo -Status
echo   reparo -Tail
echo.
echo If an old terminal does not recognize it yet, open a new terminal.

exit /b 0
