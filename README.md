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

**Nags** (always applied)
| What it stops | Policy |
| --- | --- |
| "What's new" page after OS/browser upgrades | `WelcomePageOnOSUpgradeEnabled` |

**Data leaks** (always applied)
| What it stops | Policy |
| --- | --- |
| Keystrokes sent to your search engine as you type | `SearchSuggestEnabled` |
| Failed-page lookups sent to Google | `AlternateErrorPagesEnabled` |
| Safe Browsing "Enhanced" (streams visited URLs to Google) — capped at Standard | `SafeBrowsingProtectionLevel` |
| WebRTC leaking your real IP behind a VPN | `WebRtcIPHandlingPolicy` |

**Performance** (always applied)
| What it stops | Policy |
| --- | --- |
| Brave running as a background process after you quit it | `BackgroundModeEnabled` |
| Preloading/prefetching pages it guesses you'll click | `NetworkPredictionOptions` |

**Aggressive, opt-in only** (`--aggressive`) — these remove functionality
some people rely on day to day, so they're off unless you ask for them:
| What it disables | Policy |
| --- | --- |
| Sync | `SyncDisabled` |
| Built-in password manager | `PasswordManagerEnabled` |
| Address autofill | `AutofillAddressEnabled` |
| Credit card autofill | `AutofillCreditCardEnabled` |
| Translate | `TranslateEnabled` |

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
