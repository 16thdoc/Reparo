@echo off
setlocal EnableExtensions

set "REPARO_QUIET_INNER=0"
if /I "%~1"=="/__quiet_inner" (
  set "REPARO_QUIET_INNER=1"
  shift /1
)

set "REPARO_QUIET=%REPARO_QUIET%"
if not defined REPARO_QUIET set "REPARO_QUIET=1"
for %%A in (%*) do (
  if /I "%%~A"=="/quiet" set "REPARO_QUIET=1"
  if /I "%%~A"=="-quiet" set "REPARO_QUIET=1"
  if /I "%%~A"=="--quiet" set "REPARO_QUIET=1"
  if /I "%%~A"=="/silent" set "REPARO_QUIET=1"
  if /I "%%~A"=="-silent" set "REPARO_QUIET=1"
  if /I "%%~A"=="--silent" set "REPARO_QUIET=1"
  if /I "%%~A"=="/verbose" set "REPARO_QUIET=0"
  if /I "%%~A"=="-verbose" set "REPARO_QUIET=0"
  if /I "%%~A"=="--verbose" set "REPARO_QUIET=0"
)
if not defined REPARO_INSTALL_LOG set "REPARO_INSTALL_LOG=%TEMP%\reparo-install-windows.log"
if "%REPARO_QUIET%"=="1" if not "%REPARO_QUIET_INNER%"=="1" (
  call "%~f0" /__quiet_inner %* >"%REPARO_INSTALL_LOG%" 2>&1
  exit /b %errorlevel%
)

set "INSTALL_ROOT=%ProgramData%\Reparo"
set "BIN_ROOT=%INSTALL_ROOT%\bin"
set "REPARO=%INSTALL_ROOT%\Reparo.ps1"
set "SHIM=%BIN_ROOT%\reparo.cmd"
if not defined REPARO_RELEASE_URL set "REPARO_RELEASE_URL=https://raw.githubusercontent.com/16thdoc/Reparo/main/deploy/reparo-release.json"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent()); if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } exit 1"
if errorlevel 1 (
  echo ERROR: This installer must run as Administrator or SYSTEM so it can install/update ProgramData.
  exit /b 1
)

echo.
echo === Reparo Windows installer ===
echo Install root: %INSTALL_ROOT%
if defined REPARO_URL (
  echo Source:       custom HTTPS artifact with required REPARO_SHA256
) else (
  echo Source:       reviewed immutable release from %REPARO_RELEASE_URL%
)
echo.

if exist "%REPARO%" (
  echo Existing Reparo runtime found; this will update it in place.
) else (
  echo No existing Reparo runtime found; this will install it.
)
echo.

echo Resolving and verifying Reparo...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop'; [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12; $stage = Join-Path ([IO.Path]::GetTempPath()) ('ReparoInstall-' + [guid]::NewGuid().ToString('N')); $bootstrap = Join-Path $stage 'Reparo.ps1'; $manifestPath = Join-Path $stage 'release.json'; New-Item -ItemType Directory -Path $stage -ErrorAction Stop | Out-Null; try { $url = $env:REPARO_URL; $expectedHash = $env:REPARO_SHA256; $expectedVersion = $null; $fallbackUrl = $null; if ([string]::IsNullOrWhiteSpace($url)) { $manifestUrl = $env:REPARO_RELEASE_URL; $manifestUri = $null; if (-not [Uri]::TryCreate($manifestUrl, [UriKind]::Absolute, [ref]$manifestUri) -or $manifestUri.Scheme -ne 'https' -or $manifestUri.UserInfo) { throw 'REPARO_RELEASE_URL must be an absolute HTTPS URL without credentials.' }; Invoke-WebRequest -Uri $manifestUri -Headers @{'User-Agent'='Reparo';'Cache-Control'='no-cache';'Pragma'='no-cache'} -OutFile $manifestPath -UseBasicParsing; if ((Get-Item -LiteralPath $manifestPath).Length -gt 16384) { throw 'Release manifest exceeds 16 KiB.' }; $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -ErrorAction Stop; $fields = @('version','commit','reparoUrl','sha256','linuxUrl','linuxSha256','linuxInstallerUrl','linuxInstallerSha256'); if ((@($manifest.PSObject.Properties.Name | Sort-Object) -join ',') -cne (@($fields | Sort-Object) -join ',')) { throw 'Release manifest schema is invalid.' }; if ($manifest.version -notmatch '^\d+\.\d+\.\d+\.\d+$' -or $manifest.commit -cnotmatch '^[0-9a-f]{40}$' -or $manifest.reparoUrl -cne ('https://raw.githubusercontent.com/16thdoc/Reparo/{0}/Reparo.ps1' -f $manifest.commit) -or $manifest.sha256 -cnotmatch '^[A-F0-9]{64}$') { throw 'Release manifest pin is invalid.' }; $fallbackUrl = [string]$manifest.reparoUrl; $url = 'https://file.thetechnologist.io/reparo/{0}/Reparo.ps1' -f $manifest.commit; $expectedHash = [string]$manifest.sha256; $expectedVersion = [string]$manifest.version } elseif ($expectedHash -cnotmatch '^[A-F0-9]{64}$') { throw 'Custom REPARO_URL requires an uppercase 64-character REPARO_SHA256.' }; $sourceUri = $null; if (-not [Uri]::TryCreate($url, [UriKind]::Absolute, [ref]$sourceUri) -or $sourceUri.Scheme -ne 'https' -or $sourceUri.UserInfo) { throw 'Reparo source must be an absolute HTTPS URL without credentials.' }; $downloadHeaders = @{'User-Agent'='Reparo';'Cache-Control'='no-cache';'Pragma'='no-cache'}; $downloadOptions = @{}; if ($fallbackUrl) { $downloadHeaders['User-Agent'] = 'Reparo-Download/Windows/Install'; $downloadOptions['TimeoutSec'] = 60 }; try { Invoke-WebRequest -Uri $sourceUri -Headers $downloadHeaders -OutFile $bootstrap -UseBasicParsing -ErrorAction Stop @downloadOptions } catch { if (-not $fallbackUrl) { throw }; if (-not ($_.Exception -is [Net.WebException]) -and $_.Exception.GetType().FullName -notin @('System.Net.Http.HttpRequestException','Microsoft.PowerShell.Commands.HttpResponseException','System.Threading.Tasks.TaskCanceledException','System.TimeoutException')) { throw }; Write-Warning 'Reparo download mirror unavailable; using the reviewed GitHub artifact. This download is omitted from mirror analytics.'; Invoke-WebRequest -Uri $fallbackUrl -Headers $downloadHeaders -OutFile $bootstrap -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop }; $item = Get-Item -LiteralPath $bootstrap; if ($item.Length -lt 1 -or $item.Length -gt 2097152) { throw 'Downloaded Reparo.ps1 size is outside the 1-byte to 2-MiB limit.' }; $actualHash = (Get-FileHash -LiteralPath $bootstrap -Algorithm SHA256).Hash; if ($actualHash -cne $expectedHash) { throw ('Reparo SHA-256 mismatch. Expected {0}, got {1}.' -f $expectedHash,$actualHash) }; $text = [IO.File]::ReadAllText($bootstrap); $versions = [regex]::Matches($text, '(?m)^\$script:ReparoVersion\s*=\s*''(?<v>\d+\.\d+\.\d+\.\d+)''\s*\r?$'); if ($versions.Count -ne 1 -or ($expectedVersion -and $versions[0].Groups['v'].Value -ne $expectedVersion)) { throw 'Downloaded Reparo.ps1 version identity is invalid.' }; Unblock-File -LiteralPath $bootstrap -ErrorAction SilentlyContinue; & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $bootstrap -Install; if ($LASTEXITCODE -ne 0) { throw ('Reparo install exited with code {0}.' -f $LASTEXITCODE) } } finally { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }"

if errorlevel 1 (
  echo ERROR: Reparo install failed.
  exit /b %errorlevel%
)

if not exist "%REPARO%" (
  echo ERROR: Expected installed script was not found:
  echo   %REPARO%
  exit /b 1
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
