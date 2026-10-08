# deshitify-brave

[![CI](https://github.com/james-gonzalez/deshitify-brave/actions/workflows/ci.yml/badge.svg)](https://github.com/james-gonzalez/deshitify-brave/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/james-gonzalez/deshitify-brave)](https://github.com/james-gonzalez/deshitify-brave/releases/latest)

One script per OS (macOS, Windows, Linux) that removes Brave Browser's upsell
nags (Rewards, Wallet, VPN, Leo AI, News), turns off telemetry, and plugs a few
privacy leaks (WebRTC IP leak, keystroke-leaking search suggestions).

It works through Chromium's **managed policy** mechanism, the same one MDM/GPO
uses, so no MDM or GPO is needed. Policy-controlled settings show as "managed by
your organization" and are greyed out in `brave://settings`. That is expected.

## Quick start

Grab the script for your OS from the
[latest release](https://github.com/james-gonzalez/deshitify-brave/releases/latest)
(or clone this repo), then run it:

| OS | Script | Run |
| --- | --- | --- |
| macOS | `deshitify-brave.sh` | `./deshitify-brave.sh` |
| Linux | `deshitify-brave-linux.sh` | `./deshitify-brave-linux.sh` |
| Windows | `deshitify-brave.ps1` | `.\deshitify-brave.ps1` |

It asks for elevation (sudo password, or a UAC prompt on Windows), writes the
policy, then offers to quit and relaunch Brave. Policies take effect on the next
launch.

To preview without changing anything, add the dry-run flag. To see what is
currently applied, use the show flag. To get back to stock Brave, add the undo
flag (see below).

## Options

The default run applies the **core** policies. Everything else is opt-in and
combinable.

| Option (macOS / Linux) | Option (Windows) | Adds |
| --- | --- | --- |
| *(none)* | *(none)* | Core: upsells, telemetry, nags, data leaks, baseline performance |
| `--aggressive` | `-Aggressive` | Disables sync, password manager, autofill, translate |
| `--paranoid` | `-Paranoid` | Hardening: no Tor/Cast/3P cookies/Google sign-in, forces HTTPS |
| `--performance` | `-Performance` | Trades responsiveness for memory and battery (Memory Saver, battery saver) |
| `--skip KEY[,KEY]` | `-Skip KEY[,KEY]` | Leaves the named policies out (repeatable; unknown names are rejected) |
| `--show` | `-Show` | Prints the policy currently applied; changes nothing and needs no elevation |
| `--dry-run` | `-DryRun` | Prints what would be written; changes nothing |
| `--undo` | `-Undo` | Removes the policy and restores stock Brave |
| `--flatpak` (Linux only) | n/a | Also grants a Flatpak install read access to the policy dir |

Examples:

```bash
./deshitify-brave.sh --aggressive --paranoid --dry-run
./deshitify-brave.sh --skip NetworkPredictionOptions   # keep prefetching on
```

If PowerShell blocks the script, run it once with
`powershell -ExecutionPolicy Bypass -File .\deshitify-brave.ps1`.

## What gets set

### Core (always applied)

**Upsell surfaces**

| Feature | Policy |
| --- | --- |
| Brave Rewards | `BraveRewardsDisabled` |
| Brave Wallet | `BraveWalletDisabled` |
| Brave VPN | `BraveVPNDisabled` |
| Leo AI chat | `BraveAIChatEnabled` |
| Brave News | `BraveNewsDisabled` |
| Brave Talk | `BraveTalkDisabled` |
| Brave Playlist | `BravePlaylistEnabled` |
| Wayback Machine prompt | `BraveWaybackMachineEnabled` |

**Telemetry**

| What it stops | Policy |
| --- | --- |
| P3A "anonymous" usage pings | `BraveP3AEnabled` |
| Install/usage stats ping | `BraveStatsPingEnabled` |
| Web Discovery data collection | `BraveWebDiscoveryEnabled` |
| Chromium crash/metrics reporting | `MetricsReportingEnabled` |
| URL-keyed "anonymized" data collection | `UrlKeyedAnonymizedDataCollectionEnabled` |
| Google web spell check (local spell check still works) | `SpellCheckServiceEnabled` |
| Feedback reports with screenshots/system info | `UserFeedbackAllowed` |
| Domain-reliability uploads to Google | `DomainReliabilityAllowed` |
| Privacy Sandbox ad topics | `PrivacySandboxAdTopicsEnabled` |
| Privacy Sandbox site-suggested ads | `PrivacySandboxSiteEnabledAdsEnabled` |
| Privacy Sandbox ad measurement | `PrivacySandboxAdMeasurementEnabled` |
| Shopping list / price tracking | `ShoppingListEnabled` |

**Nags**

| What it stops | Policy |
| --- | --- |
| "Make Brave your default browser" prompt | `DefaultBrowserSettingEnabled` |
| Promotional content and tabs | `PromotionsEnabled` |
| In-product surveys | `FeedbackSurveysEnabled` |

**Data leaks**

| What it stops | Policy |
| --- | --- |
| Keystrokes sent to your search engine as you type | `SearchSuggestEnabled` |
| Failed-page lookups sent to Google | `AlternateErrorPagesEnabled` |
| Safe Browsing "Enhanced" (streams visited URLs to Google), capped at Standard | `SafeBrowsingProtectionLevel` |
| WebRTC leaking your real IP behind a VPN | `WebRtcIPHandling` |

**Baseline performance**

| What it does | Policy |
| --- | --- |
| Stops Brave running in the background after you quit (Linux/Windows only; Chromium has no macOS support) | `BackgroundModeEnabled` |
| Stops prefetching pages it guesses you'll click | `NetworkPredictionOptions` |
| Locks GPU acceleration on | `HardwareAccelerationModeEnabled` |
| Coalesces background-tab JS timers to once a minute after 5 minutes | `IntensiveWakeUpThrottlingEnabled` |

`NetworkPredictionOptions` trades speed for privacy: prefetching makes likely
clicks load faster but sends Brave's guesses to the network. If you prefer the
speed, pass `--skip NetworkPredictionOptions` (`-Skip` on Windows).
`HardwareAccelerationModeEnabled` already matches Chromium's default, so it
speeds nothing up; it just stops the setting being changed.

### `--aggressive`

Removes functionality some people rely on daily.

| What it disables | Policy |
| --- | --- |
| Sync | `SyncDisabled` |
| Built-in password manager | `PasswordManagerEnabled` |
| Address autofill | `AutofillAddressEnabled` |
| Credit card autofill | `AutofillCreditCardEnabled` |
| Translate | `TranslateEnabled` |

### `--paranoid`

Hardening with noticeable behaviour changes.

| What it does | Policy |
| --- | --- |
| Disables Tor windows | `TorDisabled` |
| Disables Google Cast / LAN device probing (kills Chromecast) | `EnableMediaRouter` |
| Blocks third-party cookies | `BlockThirdPartyCookies` |
| Forces HTTPS-only mode | `HttpsOnlyMode` |
| Stops sites probing for saved payment methods | `PaymentMethodQueryEnabled` |
| Disables Google sign-in integration | `BrowserSignin` |
| Locks De-AMP on (skip Google-hosted AMP pages) | `BraveDeAmpEnabled` |
| Locks debouncing on (skip tracking redirect URLs) | `BraveDebouncingEnabled` |
| Locks language fingerprinting protection on | `BraveReduceLanguageEnabled` |

### `--performance`

Trades responsiveness for memory and battery.

| What it does | Policy |
| --- | --- |
| Turns on Memory Saver (background tabs are discarded) | `HighEfficiencyModeEnabled` |
| Sets Memory Saver to maximum savings (tabs discarded sooner) | `MemorySaverModeSavings` |
| Enables battery saver when the battery is low (throttles frame rate) | `BatterySaverModeAvailability` |

A discarded tab stays in the strip but is fully unloaded. Switching back reloads
it, and unsaved form input in that tab is lost. `BatterySaverModeAvailability`
matches Chromium's default, so like hardware acceleration it mainly locks the
setting. Memory Saver used to be part of `--aggressive`; it now lives here.

### Deliberately not touched

- **Component updates, ad-block list fetches, Safe Browsing list downloads.**
  Blocking them would stop Brave keeping its protections current.
- **`TotalMemoryLimitMb`.** A fixed ceiling is worse than Brave's own
  memory-pressure heuristic, and it is Windows/macOS only.

Keys that were once set but no longer do anything (`SafeBrowsingExtendedReportingEnabled`,
`WelcomePageOnOSUpgradeEnabled`, and the misnamed `WebRtcIPHandlingPolicy`) were
removed. `tests/validate-policies.py` checks every key against upstream
Chromium's policy definitions so a renamed or dropped policy can't sit here
looking effective.

## Verify

Run the script with `--show` (`-Show`) to see what it wrote, then open
`brave://policy` to see what Brave actually loaded. Every listed key should
show **OK**, or **Deprecated** for the three `PrivacySandbox*` keys (still
applied). Two caveats:

- **OK** means Brave parsed the policy, not that the feature behind it still exists.
- A key Brave doesn't recognise is simply absent from the page, not flagged.
  This is why the validator exists.

## How it works

Brave reads Chromium managed policy on launch and enforces it over anything set
in `brave://settings`. Each script writes the policy to the platform's standard
location (stable Brave channel):

| OS | Location |
| --- | --- |
| macOS | `/Library/Managed Preferences/<you>/com.brave.Browser.plist` |
| Linux | `/etc/brave/policies/managed/deshitify-brave.json` |
| Windows | `HKEY_LOCAL_MACHINE\SOFTWARE\Policies\BraveSoftware\Brave` |

Brave's own docs list all supported policies:
[Group Policy](https://support.brave.app/hc/en-us/articles/360039248271-Group-Policy).

## Undo

Run the same script with the undo flag (`--undo` / `-Undo`).

- **macOS:** deletes the plist and flushes the preference cache (`cfprefsd`).
- **Linux:** deletes the JSON file. If you installed with `--flatpak`, run
  `--undo --flatpak` to revert that too.
- **Windows:** removes the registry values it wrote (and the key if nothing else
  uses it).

Either way, `brave://settings` is fully yours again.

## Requirements

- Brave Browser (on Linux: native package, or Flatpak with `--flatpak`)
- macOS or Linux: `sudo` (the policy locations are root-owned)
- Windows: Administrator (the script relaunches itself elevated if needed)

## Contributing

CI lints the scripts (ShellCheck, PSScriptAnalyzer), smoke-tests `--dry-run`
on Linux, macOS and Windows, and runs `python3 tests/validate-policies.py`
(add `--online` to check against live upstream definitions). Run it before
changing any policy key. A weekly workflow repeats the online check and opens an
issue if upstream renames or drops a key.

Releases are automated with [semantic-release](https://semantic-release.gitbook.io/)
using [Conventional Commits](https://www.conventionalcommits.org/). Each push to
`main` with a releasable change cuts a GitHub Release with the three scripts
attached.

## License

Apache 2.0. See [LICENSE](LICENSE).
