# deshitify-brave

A macOS script that strips Brave Browser's upsell nags (Rewards, Wallet, VPN,
Leo AI, News) and quietly plugs a few privacy leaks (telemetry, WebRTC IP
leaks, keystroke-leaking search suggestions) — all via Chromium's managed
policy mechanism, the same one MDM uses. No MDM required.

Policy-managed settings show up as "managed by your organization" and are
greyed out in `brave://settings` — that's expected, it's how policy
enforcement works.

## Usage

```bash
./deshitify-brave.sh                # apply core + privacy + leak + performance policies
./deshitify-brave.sh --aggressive   # also disable sync, autofill, password manager, translate
./deshitify-brave.sh --dry-run      # print the plist that would be written, change nothing
./deshitify-brave.sh --undo         # remove the managed policy, restore stock Brave
```

You'll be prompted for your password — writing to macOS's Managed
Preferences directory requires `sudo`. At the end, the script offers to quit
and relaunch Brave for you.

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
normally pushed by MDM in a corporate environment, but readable from a
plain plist file too. This script writes one to:

```
/Library/Managed Preferences/<you>/com.brave.Browser.plist
```

Brave reads this on launch and enforces whatever's in it, regardless of what
you'd otherwise set in `brave://settings`. See Brave's own docs on
[Group Policy](https://support.brave.app/hc/en-us/articles/360039248271-Group-Policy)
for the full list of supported policies.

## Undoing it

```bash
./deshitify-brave.sh --undo
```

This deletes the policy file and flushes macOS's preference cache
(`cfprefsd`), handing full control back to `brave://settings`.

## Requirements

- macOS
- Brave Browser
- `sudo` access (the Managed Preferences directory is root-owned)

## License

Apache 2.0 — see [LICENSE](LICENSE).
