<#
.SYNOPSIS
    deshitify-brave.ps1 — turn off Brave's built-in nags, upsells, and telemetry
    on Windows via Chromium managed-policy support (the same mechanism GPO uses).

.DESCRIPTION
    Writes values under HKLM:\SOFTWARE\Policies\BraveSoftware\Brave, which Brave
    (being Chromium underneath) reads as an enterprise policy source. This is the
    supported, documented way to configure Brave outside of brave://settings —
    see https://support.brave.app/hc/en-us/articles/360039248271-Group-Policy

    Requires Administrator (HKLM is machine-wide). The script re-launches itself
    elevated if needed.

    Policy-set values are greyed out in brave://settings and show "managed by
    your organization" — that's expected, it's how policy enforcement works.

.PARAMETER Aggressive
    Also disable sync, autofill, password manager, and translate.

.PARAMETER DryRun
    Print the registry values that would be written, change nothing.

.PARAMETER Undo
    Remove the policy values this script manages and restore stock Brave.

.EXAMPLE
    .\deshitify-brave.ps1
.EXAMPLE
    .\deshitify-brave.ps1 -Aggressive
.EXAMPLE
    .\deshitify-brave.ps1 -DryRun
.EXAMPLE
    .\deshitify-brave.ps1 -Undo
#>

[CmdletBinding()]
param(
    [switch]$Aggressive,
    [switch]$DryRun,
    [switch]$Undo,
    # Internal: set when the script re-launched itself elevated, so the new
    # console window pauses instead of vanishing before you can read it.
    [switch]$Elevated
)

$ErrorActionPreference = 'Stop'

$PolicyKey = 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave'
$PolicyKeyDisplay = 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\BraveSoftware\Brave'

# --- Core: kill the upsell surfaces (Rewards/Wallet/VPN nags, Leo, News, Talk, Playlist, Wayback prompt)
$CoreKeys = [ordered]@{
    BraveRewardsDisabled       = @{ Type = 'DWord'; Value = 1 }
    BraveWalletDisabled        = @{ Type = 'DWord'; Value = 1 }
    BraveVPNDisabled           = @{ Type = 'DWord'; Value = 1 }
    BraveAIChatEnabled         = @{ Type = 'DWord'; Value = 0 }
    BraveNewsDisabled          = @{ Type = 'DWord'; Value = 1 }
    BraveTalkDisabled          = @{ Type = 'DWord'; Value = 1 }
    BravePlaylistEnabled       = @{ Type = 'DWord'; Value = 0 }
    BraveWaybackMachineEnabled = @{ Type = 'DWord'; Value = 0 }
}

# --- Privacy: stop the phone-home pings (P3A "anonymous" telemetry, stats ping, web discovery, Chromium metrics)
$PrivacyKeys = [ordered]@{
    BraveP3AEnabled          = @{ Type = 'DWord'; Value = 0 }
    BraveStatsPingEnabled    = @{ Type = 'DWord'; Value = 0 }
    BraveWebDiscoveryEnabled = @{ Type = 'DWord'; Value = 0 }
    MetricsReportingEnabled  = @{ Type = 'DWord'; Value = 0 }
}

# --- Nag suppression: standard Chromium policy for "what's new" pages after OS upgrades
# (PromotionalTabsEnabled was dropped upstream — Brave now reports it "Deprecated", so it's omitted)
$NagKeys = [ordered]@{
    WelcomePageOnOSUpgradeEnabled = @{ Type = 'DWord'; Value = 0 }
}

# --- Leak plugging: stop small background data leaks (keystrokes to search engine, error-page
# lookups to Google, WebRTC exposing your real IP behind a VPN) and cap Safe Browsing at
# Standard so it can't be bumped to Enhanced (which streams visited URLs to Google in real time)
$LeakKeys = [ordered]@{
    SearchSuggestEnabled        = @{ Type = 'DWord'; Value = 0 }
    AlternateErrorPagesEnabled  = @{ Type = 'DWord'; Value = 0 }
    SafeBrowsingProtectionLevel = @{ Type = 'DWord'; Value = 1 }
    WebRtcIPHandlingPolicy      = @{ Type = 'String'; Value = 'default_public_interface_only' }
}

# --- Performance: stop Brave running as a background process after you quit it, and stop
# preloading/prefetching pages it guesses you'll click next (saves network + battery)
$PerfKeys = [ordered]@{
    BackgroundModeEnabled    = @{ Type = 'DWord'; Value = 0 }
    NetworkPredictionOptions = @{ Type = 'DWord'; Value = 2 }
}

# --- Aggressive (opt-in): disables features some people actually rely on, so off by default
$AggressiveKeys = [ordered]@{
    SyncDisabled             = @{ Type = 'DWord'; Value = 1 }
    PasswordManagerEnabled   = @{ Type = 'DWord'; Value = 0 }
    AutofillAddressEnabled   = @{ Type = 'DWord'; Value = 0 }
    AutofillCreditCardEnabled = @{ Type = 'DWord'; Value = 0 }
    TranslateEnabled         = @{ Type = 'DWord'; Value = 0 }
}

$Policies = [ordered]@{}
foreach ($set in @($CoreKeys, $PrivacyKeys, $NagKeys, $LeakKeys, $PerfKeys)) {
    foreach ($name in $set.Keys) { $Policies[$name] = $set[$name] }
}
if ($Aggressive) {
    foreach ($name in $AggressiveKeys.Keys) { $Policies[$name] = $AggressiveKeys[$name] }
}

# -Undo removes every value the script can write, aggressive ones included, so a
# plain -Undo fully reverses a previous -Aggressive run.
$ManagedNames = @($CoreKeys.Keys) + @($PrivacyKeys.Keys) + @($NagKeys.Keys) +
                @($LeakKeys.Keys) + @($PerfKeys.Keys) + @($AggressiveKeys.Keys)

function Format-RegValue {
    param($Spec)
    if ($Spec.Type -eq 'String') { '"{0}"' -f $Spec.Value }
    else { 'dword:{0:x8}' -f $Spec.Value }
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $identity).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not ($IsWindows -or $env:OS -eq 'Windows_NT')) {
    Write-Error 'This script is Windows-only. On macOS use deshitify-brave.sh.'
    exit 1
}

$BravePaths = @(
    (Join-Path $env:ProgramFiles 'BraveSoftware\Brave-Browser\Application\brave.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'BraveSoftware\Brave-Browser\Application\brave.exe'),
    (Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\Application\brave.exe')
)
$BraveExe = $BravePaths | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $BraveExe) {
    Write-Warning 'brave.exe not found in the usual install locations. Continuing anyway — the policy will apply the next time Brave is installed/launched.'
}

if ($DryRun) {
    if ($Undo) {
        Write-Host "Would remove these values from: $PolicyKeyDisplay"
        Write-Host '---'
        $ManagedNames | ForEach-Object { Write-Host "  $_" }
    } else {
        Write-Host "Would write to: $PolicyKeyDisplay"
        Write-Host '---'
        Write-Host 'Windows Registry Editor Version 5.00'
        Write-Host ''
        Write-Host "[$PolicyKeyDisplay]"
        foreach ($name in $Policies.Keys) {
            Write-Host ('"{0}"={1}' -f $name, (Format-RegValue $Policies[$name]))
        }
    }
    exit 0
}

if (-not (Test-Administrator)) {
    Write-Host 'This needs Administrator (the policy lives in HKEY_LOCAL_MACHINE). Re-launching elevated...'
    $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Elevated')
    if ($Aggressive) { $psArgs += '-Aggressive' }
    if ($Undo) { $psArgs += '-Undo' }
    try {
        $proc = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $psArgs -Verb RunAs -PassThru -Wait
        exit $proc.ExitCode
    } catch {
        Write-Error "Elevation was declined or failed: $($_.Exception.Message)"
        exit 1
    }
}

if ($Undo) {
    if (Test-Path $PolicyKey) {
        $removed = 0
        $existing = Get-Item $PolicyKey
        foreach ($name in $ManagedNames) {
            if ($existing.GetValue($name, $null) -ne $null) {
                Remove-ItemProperty -Path $PolicyKey -Name $name
                $removed++
            }
        }
        # Only drop the key itself if nothing else (another GPO, another tool) lives there.
        $leftover = Get-Item $PolicyKey
        if ($leftover.ValueCount -eq 0 -and $leftover.SubKeyCount -eq 0) {
            Remove-Item -Path $PolicyKey
            Write-Host "Removed $removed value(s) and the now-empty key $PolicyKeyDisplay"
        } else {
            Write-Host "Removed $removed value(s) from $PolicyKeyDisplay (other policies left in place)"
        }
        Write-Host 'Done. Restart Brave for the change to take effect.'
    } else {
        Write-Host "No policy key found at $PolicyKeyDisplay — nothing to undo."
    }
    if ($Elevated) { Read-Host 'Press Enter to close' | Out-Null }
    exit 0
}

if (-not (Test-Path $PolicyKey)) { New-Item -Path $PolicyKey -Force | Out-Null }
foreach ($name in $Policies.Keys) {
    $spec = $Policies[$name]
    New-ItemProperty -Path $PolicyKey -Name $name -PropertyType $spec.Type -Value $spec.Value -Force | Out-Null
}

Write-Host ''
Write-Host "Applied managed policy to: $PolicyKeyDisplay"
if ($Aggressive) {
    Write-Host 'Mode: aggressive (sync, autofill, password manager, translate also disabled)'
} else {
    Write-Host 'Mode: core (re-run with -Aggressive to also disable sync/autofill/password manager/translate)'
}
Write-Host ''
Write-Host 'Quit and reopen Brave, then check brave://policy to confirm.'
Write-Host "Run '.\deshitify-brave.ps1 -Undo' any time to revert."

if (Get-Process -Name 'brave' -ErrorAction SilentlyContinue) {
    $reply = Read-Host 'Brave is currently running — quit and relaunch it now? [y/N]'
    if ($reply -match '^[Yy]$') {
        Get-Process -Name 'brave' -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 1
        if ($BraveExe) { Start-Process -FilePath $BraveExe }
        else { Write-Warning 'brave.exe not found — relaunch Brave yourself.' }
    }
}

if ($Elevated) { Read-Host 'Press Enter to close' | Out-Null }
