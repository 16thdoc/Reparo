<#
.SYNOPSIS
Prepares one or more SSH-reachable Linux hosts for the Moshi mobile terminal.

.DESCRIPTION
Installs mosh, tmux, curl, and moshi-hook on each target. Optional switches can
authorize a Moshi-generated SSH public key, pair agent hooks, install hook
configuration, create a systemd user service, and open the mosh UDP range.

The helper configures the host side only. Without Easy Pair, create a connection
in Moshi manually and use the private key whose public key is passed here.

.EXAMPLE
./deploy/Install-MoshiRemote.ps1 -ComputerName devbox -Preview

.EXAMPLE
$token = Read-Host 'Moshi hook pairing token' -AsSecureString
$key = Get-Clipboard # Moshi-generated public key, not the private key
./deploy/Install-MoshiRemote.ps1 -ComputerName devbox -AuthorizedKey $key `
    -PairingToken $token -InstallAgentHooks -ConfigureService -EnableLinger
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string[]]$ComputerName,

    [string]$SshCommand = 'ssh',

    [ValidateRange(1, 600)]
    [int]$ConnectTimeoutSeconds = 10,

    [string]$AuthorizedKey,

    [Security.SecureString]$PairingToken,

    [switch]$InstallAgentHooks,

    [string]$AgentProjectPath,

    [switch]$ConfigureService,

    [switch]$EnableLinger,

    [switch]$OpenMoshFirewall,

    [ValidatePattern('^https://')]
    [string]$MoshiHookInstallUrl = 'https://getmoshi.app/install.sh',

    [switch]$Preview
)

$ErrorActionPreference = 'Stop'

function ConvertTo-Utf8Base64 {
    param([AllowEmptyString()][string]$Value)

    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))
}

function ConvertFrom-ReparoSecureString {
    param([Parameter(Mandatory)][Security.SecureString]$Value)

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function New-MoshiRemoteSetupScript {
    param(
        [string]$PublicKey,
        [string]$HookToken,
        [string]$ProjectPath,
        [bool]$ShouldInstallAgentHooks,
        [bool]$ShouldConfigureService,
        [bool]$ShouldEnableLinger,
        [bool]$ShouldOpenFirewall,
        [string]$HookInstallUrl
    )

    $template = @'
#!/usr/bin/env bash
set -euo pipefail

authorized_key_b64='__AUTHORIZED_KEY_B64__'
pairing_token_b64='__PAIRING_TOKEN_B64__'
agent_project_path_b64='__AGENT_PROJECT_PATH_B64__'
hook_install_url_b64='__HOOK_INSTALL_URL_B64__'
install_agent_hooks=__INSTALL_AGENT_HOOKS__
configure_service=__CONFIGURE_SERVICE__
enable_linger=__ENABLE_LINGER__
open_firewall=__OPEN_FIREWALL__

export PATH="$HOME/.local/bin:$PATH"

warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
decode() { printf '%s' "$1" | base64 --decode; }

if [ "$(id -u)" -eq 0 ]; then
  run_root() { "$@"; }
elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
  run_root() { sudo -n "$@"; }
else
  run_root() { die "root or passwordless sudo is required for: $*"; }
fi

missing_packages=0
for command_name in curl mosh-server tmux tar base64; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    missing_packages=1
  fi
done

if [ "$missing_packages" -eq 1 ]; then
  if command -v apt-get >/dev/null 2>&1; then
    run_root apt-get update
    run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y curl ca-certificates coreutils tar mosh tmux
  elif command -v dnf >/dev/null 2>&1; then
    run_root dnf install -y curl ca-certificates coreutils tar mosh tmux
  elif command -v yum >/dev/null 2>&1; then
    run_root yum install -y curl ca-certificates coreutils tar mosh tmux
  elif command -v pacman >/dev/null 2>&1; then
    run_root pacman -S --needed --noconfirm curl ca-certificates coreutils tar mosh tmux
  elif command -v zypper >/dev/null 2>&1; then
    run_root zypper --non-interactive install curl ca-certificates coreutils tar mosh tmux
  else
    die 'no supported package manager found (apt, dnf, yum, pacman, or zypper)'
  fi
fi

for command_name in curl mosh-server tmux tar base64; do
  command -v "$command_name" >/dev/null 2>&1 || die "$command_name is still unavailable after package setup"
done

hook_install_url="$(decode "$hook_install_url_b64")"
curl -fsSL "$hook_install_url" | INSTALL_DIR="$HOME/.local/bin" sh
command -v moshi-hook >/dev/null 2>&1 || die 'moshi-hook was installed but is not available on PATH'

key_status='Skipped'
if [ -n "$authorized_key_b64" ]; then
  authorized_key="$(decode "$authorized_key_b64")"
  umask 077
  mkdir -p "$HOME/.ssh"
  touch "$HOME/.ssh/authorized_keys"
  chmod 700 "$HOME/.ssh"
  chmod 600 "$HOME/.ssh/authorized_keys"
  if grep -qxF -- "$authorized_key" "$HOME/.ssh/authorized_keys"; then
    key_status='Present'
  else
    if [ -s "$HOME/.ssh/authorized_keys" ] && [ "$(tail -c 1 "$HOME/.ssh/authorized_keys" | wc -l)" -eq 0 ]; then
      printf '\n' >> "$HOME/.ssh/authorized_keys"
    fi
    printf '%s\n' "$authorized_key" >> "$HOME/.ssh/authorized_keys"
    key_status='Added'
  fi
  unset authorized_key
fi

firewall_status='Skipped'
if [ "$open_firewall" -eq 1 ]; then
  if command -v ufw >/dev/null 2>&1; then
    run_root ufw allow 60000:61000/udp
    firewall_status='Ufw'
  elif command -v firewall-cmd >/dev/null 2>&1 && run_root firewall-cmd --state >/dev/null 2>&1; then
    run_root firewall-cmd --add-port=60000-61000/udp --permanent
    run_root firewall-cmd --reload
    firewall_status='Firewalld'
  else
    firewall_status='Manual'
    warn 'no active ufw or firewalld found; allow UDP 60000-61000 in the host/network firewall if required'
  fi
fi

pair_status='Skipped'
if [ -n "$pairing_token_b64" ]; then
  pairing_token="$(decode "$pairing_token_b64")"
  moshi-hook pair --token "$pairing_token"
  unset pairing_token pairing_token_b64
  pair_status='Paired'
fi

hooks_status='Skipped'
if [ "$install_agent_hooks" -eq 1 ]; then
  if [ -n "$agent_project_path_b64" ]; then
    agent_project_path="$(decode "$agent_project_path_b64")"
    [ -d "$agent_project_path" ] || die "agent project path does not exist: $agent_project_path"
    cd -- "$agent_project_path"
  else
    cd -- "$HOME"
  fi
  moshi-hook install
  hooks_status='Installed'
fi

service_status='Skipped'
if [ "$configure_service" -eq 1 ]; then
  if command -v systemctl >/dev/null 2>&1; then
    unit_dir="$HOME/.config/systemd/user"
    mkdir -p "$unit_dir/default.target.wants"
    cat > "$unit_dir/moshi-hook.service" <<'UNIT'
[Unit]
Description=Moshi agent hook daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=%h/.local/bin/moshi-hook serve
Restart=on-failure
RestartSec=5
Environment=PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=default.target
UNIT
    ln -sfn ../moshi-hook.service "$unit_dir/default.target.wants/moshi-hook.service"

    if [ "$enable_linger" -eq 1 ]; then
      command -v loginctl >/dev/null 2>&1 || die 'loginctl is required for -EnableLinger'
      run_root loginctl enable-linger "$(id -un)"
    fi

    if systemctl --user daemon-reload >/dev/null 2>&1 && systemctl --user restart moshi-hook.service; then
      service_status='Running'
    else
      service_status='EnabledNextLogin'
      warn "the user service is installed and enabled but could not start in this SSH session; run 'systemctl --user start moshi-hook' after login"
    fi
  else
    service_status='Manual'
    warn "systemd is unavailable; start the daemon with 'moshi-hook serve' under this host's process manager"
  fi
fi

printf 'MOSHI_DEPLOY|Host=%s|User=%s|Mosh=%s|Tmux=%s|Hook=%s|Key=%s|Pair=%s|Hooks=%s|Service=%s|Firewall=%s\n' \
  "$(hostname)" "$(id -un)" "$(command -v mosh-server)" "$(command -v tmux)" \
  "$(command -v moshi-hook)" "$key_status" "$pair_status" "$hooks_status" "$service_status" "$firewall_status"
'@

    return $template.
        Replace('__AUTHORIZED_KEY_B64__', (ConvertTo-Utf8Base64 $PublicKey)).
        Replace('__PAIRING_TOKEN_B64__', (ConvertTo-Utf8Base64 $HookToken)).
        Replace('__AGENT_PROJECT_PATH_B64__', (ConvertTo-Utf8Base64 $ProjectPath)).
        Replace('__HOOK_INSTALL_URL_B64__', (ConvertTo-Utf8Base64 $HookInstallUrl)).
        Replace('__INSTALL_AGENT_HOOKS__', [int]$ShouldInstallAgentHooks).
        Replace('__CONFIGURE_SERVICE__', [int]$ShouldConfigureService).
        Replace('__ENABLE_LINGER__', [int]$ShouldEnableLinger).
        Replace('__OPEN_FIREWALL__', [int]$ShouldOpenFirewall)
}

if ($AuthorizedKey) {
    $AuthorizedKey = $AuthorizedKey.Trim()
    if ($AuthorizedKey -match '[\r\n]' -or $AuthorizedKey -notmatch '^(ssh-|ecdsa-|sk-)[A-Za-z0-9@._+-]+\s+[A-Za-z0-9+/=]+(?:\s+.*)?$') {
        throw 'AuthorizedKey must be one valid single-line OpenSSH public key.'
    }
}

if ($EnableLinger) {
    $ConfigureService = $true
}

$plainPairingToken = ''
if ($PairingToken) {
    $plainPairingToken = ConvertFrom-ReparoSecureString $PairingToken
    if ([string]::IsNullOrWhiteSpace($plainPairingToken)) {
        throw 'PairingToken cannot be empty.'
    }
}

$remoteScript = New-MoshiRemoteSetupScript `
    -PublicKey $AuthorizedKey `
    -HookToken $plainPairingToken `
    -ProjectPath $AgentProjectPath `
    -ShouldInstallAgentHooks ([bool]$InstallAgentHooks) `
    -ShouldConfigureService ([bool]$ConfigureService) `
    -ShouldEnableLinger ([bool]$EnableLinger) `
    -ShouldOpenFirewall ([bool]$OpenMoshFirewall) `
    -HookInstallUrl $MoshiHookInstallUrl
$plainPairingToken = $null

$results = New-Object System.Collections.Generic.List[object]

foreach ($target in $ComputerName) {
    Write-Host ''
    Write-Host "========== $target ==========" -ForegroundColor Cyan

    try {
        if ([string]::IsNullOrWhiteSpace($target) -or $target -match '^-|[\x00-\x1F\x7F]') {
            throw "Invalid SSH target: '$target'"
        }

        $sshArgs = @(
            '-T',
            '-o', "ConnectTimeout=$ConnectTimeoutSeconds",
            '--',
            $target,
            'bash',
            '-s'
        )

        if ($Preview) {
            $features = @('packages', 'moshi-hook')
            if ($AuthorizedKey) { $features += 'authorized-key' }
            if ($PairingToken) { $features += 'hook-pairing' }
            if ($InstallAgentHooks) { $features += 'agent-hooks' }
            if ($ConfigureService) { $features += 'user-service' }
            if ($EnableLinger) { $features += 'linger' }
            if ($OpenMoshFirewall) { $features += 'firewall' }
            Write-Host "[Preview] Would pipe a redacted setup script to: $SshCommand $($sshArgs -join ' ')" -ForegroundColor Yellow
            $results.Add([pscustomobject]@{
                ComputerName = $target
                Status       = 'Preview'
                Details      = "Features: $($features -join ', ')"
            }) | Out-Null
            continue
        }

        $previousErrorActionPreference = $ErrorActionPreference
        try {
            # Windows PowerShell 5.1 promotes native stderr to NativeCommandError
            # when ErrorActionPreference is Stop, even if the command succeeds.
            $ErrorActionPreference = 'Continue'
            $output = @($remoteScript | & $SshCommand @sshArgs 2>&1)
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }

        if ($output) {
            $output | ForEach-Object { Write-Host $_ }
        }

        if ($exitCode -ne 0) {
            throw "SSH setup failed with exit code $exitCode"
        }

        $deployLine = $output | Where-Object { [string]$_ -match '^MOSHI_DEPLOY\|' } | Select-Object -Last 1
        $results.Add([pscustomobject]@{
            ComputerName = $target
            Status       = 'Success'
            Details      = if ($deployLine) { [string]$deployLine } else { 'Setup completed, but no deploy marker was returned.' }
        }) | Out-Null
    }
    catch {
        Write-Host "Failed: $($_.Exception.Message)" -ForegroundColor Red
        $results.Add([pscustomobject]@{
            ComputerName = $target
            Status       = 'Failed'
            Details      = $_.Exception.Message
        }) | Out-Null
    }
}

$remoteScript = $null

Write-Host ''
Write-Host '========== SUMMARY ==========' -ForegroundColor Magenta
$results | Format-Table -AutoSize

if ($results.Status -contains 'Failed') {
    exit 1
}
