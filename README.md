# deshitify-brave

Scripts (macOS + Windows + Linux) that strip Brave Browser's upsell nags (Rewards,
Wallet, VPN, Leo AI, News) and quietly plug a few privacy leaks (telemetry,
WebRTC IP leaks, keystroke-leaking search suggestions) — all via Chromium's
managed policy mechanism, the same one MDM/GPO uses. No MDM/GPO required.

Policy-managed settings show up as "managed by your organization" and are
greyed out in `brave://settings` — that's expected, it's how policy
enforcement works.

## Usage

**macOS** (`deshitify-brave.sh`):

```bash
./deshitify-brave.sh                # apply core + privacy + leak + performance policies
./deshitify-brave.sh --aggressive   # also disable sync, autofill, password manager, translate
./deshitify-brave.sh --paranoid     # also harden: no Tor/Cast/3P cookies/Google sign-in, force HTTPS
./deshitify-brave.sh --performance  # also trade memory for speed: Memory Saver at max savings, battery saver
./deshitify-brave.sh --dry-run      # print the plist that would be written, change nothing
./deshitify-brave.sh --undo         # remove the managed policy, restore stock Brave
```

You'll be prompted for your password — writing to macOS's Managed
Preferences directory requires `sudo`. At the end, the script offers to quit
and relaunch Brave for you.

**Windows** (`deshitify-brave.ps1`):

```powershell
.\deshitify-brave.ps1                # apply core + privacy + leak + performance policies
.\deshitify-brave.ps1 -Aggressive    # also disable sync, autofill, password manager, translate
.\deshitify-brave.ps1 -Paranoid      # also harden: no Tor/Cast/3P cookies/Google sign-in, force HTTPS
.\deshitify-brave.ps1 -Performance   # also trade memory for speed: Memory Saver at max savings, battery saver
.\deshitify-brave.ps1 -DryRun        # print the registry values that would be written, change nothing
.\deshitify-brave.ps1 -Undo          # remove the managed policy, restore stock Brave
```

Writing to `HKEY_LOCAL_MACHINE` needs Administrator — the script relaunches
itself elevated (a UAC prompt) if it isn't already. At the end, it offers to
quit and relaunch Brave for you. If script execution is blocked, run once
with `powershell -ExecutionPolicy Bypass -File .\deshitify-brave.ps1`.

**Linux** (`deshitify-brave-linux.sh`):

```bash
./deshitify-brave-linux.sh                # apply core + privacy + leak + performance policies
./deshitify-brave-linux.sh --aggressive   # also disable sync, autofill, password manager, translate
./deshitify-brave-linux.sh --paranoid     # also harden: no Tor/Cast/3P cookies/Google sign-in, force HTTPS
./deshitify-brave-linux.sh --performance  # also trade memory for speed: Memory Saver at max savings, battery saver
./deshitify-brave-linux.sh --dry-run      # print the JSON that would be written, change nothing
./deshitify-brave-linux.sh --undo         # remove the managed policy, restore stock Brave
./deshitify-brave-linux.sh --flatpak      # also grant a Flatpak install read access to the policy dir
```

You'll be prompted for your password — writing to `/etc/brave/policies/managed/`
requires `sudo`. At the end, the script offers to quit and relaunch Brave for
you. Flatpak's sandbox can't see `/etc` by default, so add `--flatpak` (with
`--undo --flatpak` to revert) if you installed Brave that way.

Verify it worked by opening `brave://policy` in Brave — every listed key
should show status **OK**.

## What it disables

**Upsell surfaces** (always applied)
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

**Telemetry** (always applied)
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

**Nags** (always applied)
| What it stops | Policy |
| --- | --- |
| "Make Brave your default browser" prompt | `DefaultBrowserSettingEnabled` |
| Promotional content and tabs | `PromotionsEnabled` |
| In-product surveys | `FeedbackSurveysEnabled` |

**Data leaks** (always applied)
| What it stops | Policy |
| --- | --- |
| Keystrokes sent to your search engine as you type | `SearchSuggestEnabled` |
| Failed-page lookups sent to Google | `AlternateErrorPagesEnabled` |
| Safe Browsing "Enhanced" (streams visited URLs to Google) — capped at Standard | `SafeBrowsingProtectionLevel` |
| WebRTC leaking your real IP behind a VPN | `WebRtcIPHandling` |

**Performance** (always applied)
| What it does | Policy |
| --- | --- |
| Stops Brave running as a background process after you quit it (Linux/Windows only — Chromium has no macOS support for it) | `BackgroundModeEnabled` |
| Stops preloading/prefetching pages it guesses you'll click | `NetworkPredictionOptions` |
| Locks GPU acceleration on | `HardwareAccelerationModeEnabled` |
| Coalesces background-tab JavaScript timers to once a minute after 5 minutes backgrounded | `IntensiveWakeUpThrottlingEnabled` |

Note that `NetworkPredictionOptions` is a deliberate trade *against* speed —
prefetching makes pages you're likely to click load faster, at the cost of
sending Brave's guesses about your next click to the network. The privacy win
is the point; if you'd rather have the speed, drop that key.

`HardwareAccelerationModeEnabled` and `BatterySaverModeAvailability` below
already match Chromium's own defaults, so on a stock profile they don't speed
anything up — they stop the setting being changed, which is the point of
policy.

**Aggressive, opt-in only** (`--aggressive`) — these remove functionality
some people rely on day to day, so they're off unless you ask for them:
| What it disables | Policy |
| --- | --- |
| Sync | `SyncDisabled` |
| Built-in password manager | `PasswordManagerEnabled` |
| Address autofill | `AutofillAddressEnabled` |
| Credit card autofill | `AutofillCreditCardEnabled` |
| Translate | `TranslateEnabled` |

**Paranoid, opt-in only** (`--paranoid`) — hardening that changes behaviour
you'll notice, so it's off unless you ask for it. Combine with `--aggressive`
for both:
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

**Performance, opt-in only** (`--performance` / `-Performance`) — trades
responsiveness for memory and battery, so it's off unless you ask for it.
Combine freely with `--aggressive` and `--paranoid`:
| What it does | Policy |
| --- | --- |
| Turns on Memory Saver (background tabs are discarded and reload when revisited) | `HighEfficiencyModeEnabled` |
| Sets Memory Saver to maximum savings (tabs are discarded sooner) | `MemorySaverModeSavings` |
| Enables battery saver once the battery is low (throttles frame rate) | `BatterySaverModeAvailability` |

A discarded tab stays in the tab strip but is fully unloaded — switching back
triggers a reload, so you'll see a flash and any unsaved form input in that
tab is gone. That's the trade; it's why this is a separate tier rather than
always-on. Memory Saver used to ride along with `--aggressive`; it now lives
here, so `--aggressive` on its own no longer turns it on.

`TotalMemoryLimitMb` (a hard memory ceiling) is deliberately not set. Brave
already discards tabs under real memory pressure, which is a better heuristic
than a number picked without knowing your machine — and Chromium only supports
that policy on Windows and macOS anyway.

**Deliberately left alone**: component updates, ad-block list fetches, and
Safe Browsing list downloads still reach Brave's/Google's servers — blocking
them would stop Brave keeping its protections up to date.

**Not set, because Chromium ignores them.** Every key above is checked against
upstream Chromium's policy definitions by `tests/validate-policies.py`, so a
policy that's been renamed or dropped can't sit here looking effective:

| Policy | Why it's gone |
| --- | --- |
| `SafeBrowsingExtendedReportingEnabled` | No effect from Chromium 145 — the feature was removed outright, so Brave no longer sends these reports however the policy is set. `SafeBrowsingProtectionLevel` is the live control. |
| `WelcomePageOnOSUpgradeEnabled` | Only ever `chrome.win:45-62`; dead since Chromium 63 on every platform. |
| `WebRtcIPHandlingPolicy` | Never the real name — the policy is `WebRtcIPHandling`, which is what's set now. |
| `TotalMemoryLimitMb` | Windows/macOS only, and a fixed ceiling is worse than Brave's own memory-pressure heuristic. |

## How it works

Brave is built on Chromium, which supports "managed policy" configuration —
normally pushed by MDM/GPO in a corporate environment, but readable from a
plain file too.

On **macOS**, the script writes a plist to:

```
/Library/Managed Preferences/<you>/com.brave.Browser.plist
```

On **Windows**, the script writes DWORD/String values under:

```
HKEY_LOCAL_MACHINE\SOFTWARE\Policies\BraveSoftware\Brave
```

On **Linux**, the script writes a JSON file to:

```
/etc/brave/policies/managed/deshitify-brave.json
```

Brave reads these on launch and enforces whatever's in them, regardless of
what you'd otherwise set in `brave://settings`. See Brave's own docs on
[Group Policy](https://support.brave.app/hc/en-us/articles/360039248271-Group-Policy)
for the full list of supported policies.

## Undoing it

**macOS**:

```bash
./deshitify-brave.sh --undo
```

This deletes the policy file and flushes macOS's preference cache
(`cfprefsd`), handing full control back to `brave://settings`.

**Windows**:

```powershell
.\deshitify-brave.ps1 -Undo
```

This removes the values the script wrote from the registry (dropping the
key too if nothing else uses it), handing full control back to
`brave://settings`.

**Linux**:

```bash
./deshitify-brave-linux.sh --undo
```

This deletes the policy file, handing full control back to
`brave://settings`.

## Requirements

**macOS**:
- macOS
- Brave Browser
- `sudo` access (the Managed Preferences directory is root-owned)

**Windows**:
- Windows
- Brave Browser
- Administrator access (`HKEY_LOCAL_MACHINE` is machine-wide)

**Linux**:
- Linux
- Brave Browser (native package, or Flatpak with `--flatpak`)
- `sudo` access (`/etc/brave/policies/managed/` is root-owned)

## Versioning & releases

Releases are automated with [semantic-release](https://semantic-release.gitbook.io/),
using its default [Angular commit convention](https://github.com/conventional-changelog/commitlint/tree/master/%40commitlint/config-angular#type-enum)
(a flavor of [Conventional Commits](https://www.conventionalcommits.org/)).
Every push to `main` is scanned for commit types, and if there's a releasable
change, a GitHub Release and tag are cut automatically with
`deshitify-brave.sh`, `deshitify-brave.ps1`, and `deshitify-brave-linux.sh`
attached as downloadable assets.

## License

Apache 2.0 — see [LICENSE](LICENSE).
