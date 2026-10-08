#!/usr/bin/env bash
#
# deshitify-brave.sh — turn off Brave's built-in nags, upsells, and telemetry
# on macOS via Chromium managed-policy support (the same mechanism MDM uses).
#
# Usage:
#   ./deshitify-brave.sh                # apply core + privacy policies
#   ./deshitify-brave.sh --aggressive   # also disable sync/autofill/password manager/translate
#   ./deshitify-brave.sh --paranoid     # also harden: no Tor/Cast/3P cookies/Google sign-in, force HTTPS
#   ./deshitify-brave.sh --performance  # also trade memory for speed: Memory Saver at max savings, battery saver
#   ./deshitify-brave.sh --dry-run      # print the plist that would be written, change nothing
#   ./deshitify-brave.sh --undo         # remove the managed policy and restore defaults
#
# What this does:
#   Writes /Library/Managed Preferences/<you>/com.brave.Browser.plist, which Brave
#   (being Chromium underneath) reads as an enterprise policy file. This is the
#   supported, documented way to configure Brave outside of chrome://settings —
#   see https://support.brave.app/hc/en-us/articles/360039248271-Group-Policy
#
# Notes:
#   - Requires sudo (the Managed Preferences directory is root-owned).
#   - Policy-set values are greyed out in brave://settings and show "managed by
#     your organization" — that's expected, it's how policy enforcement works.
#   - Run --undo to remove the file and get standard, unmanaged Brave back.

set -euo pipefail

BUNDLE_ID="com.brave.Browser"
TARGET_USER="$(id -un)"
POLICY_DIR="/Library/Managed Preferences/${TARGET_USER}"
POLICY_FILE="${POLICY_DIR}/${BUNDLE_ID}.plist"

DRY_RUN=0
UNDO=0
AGGRESSIVE=0
PARANOID=0
PERFORMANCE=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --undo) UNDO=1 ;;
    --aggressive) AGGRESSIVE=1 ;;
    --paranoid) PARANOID=1 ;;
    --performance) PERFORMANCE=1 ;;
    -h|--help)
      sed -n '2,24p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

if [[ "$(uname)" != "Darwin" ]]; then
  echo "This script is macOS-only." >&2
  exit 1
fi

if [[ ! -d "/Applications/Brave Browser.app" ]]; then
  echo "Warning: /Applications/Brave Browser.app not found. Continuing anyway —" >&2
  echo "the policy will apply the next time Brave is installed/launched." >&2
fi

if [[ "$UNDO" -eq 1 ]]; then
  if [[ -f "$POLICY_FILE" ]]; then
    echo "Removing $POLICY_FILE"
    sudo rm -f "$POLICY_FILE"
    sudo killall cfprefsd 2>/dev/null || true
    echo "Done. Restart Brave for the change to take effect."
  else
    echo "No managed policy file found at $POLICY_FILE — nothing to undo."
  fi
  exit 0
fi

# --- Core: kill the upsell surfaces (Rewards/Wallet/VPN nags, Leo, News, Talk, Playlist, Wayback prompt)
CORE_KEYS=$(cat <<'EOF'
    <key>BraveRewardsDisabled</key>
    <true/>
    <key>BraveWalletDisabled</key>
    <true/>
    <key>BraveVPNDisabled</key>
    <true/>
    <key>BraveAIChatEnabled</key>
    <false/>
    <key>BraveNewsDisabled</key>
    <true/>
    <key>BraveTalkDisabled</key>
    <true/>
    <key>BravePlaylistEnabled</key>
    <false/>
    <key>BraveWaybackMachineEnabled</key>
    <false/>
EOF
)

# --- Privacy: stop the phone-home pings (P3A "anonymous" telemetry, stats ping, web discovery, Chromium metrics,
# URL-keyed data collection, Google spell check, feedback reports, Safe Browsing extended reporting,
# domain-reliability uploads, Privacy Sandbox ad APIs, shopping list/price tracking)
PRIVACY_KEYS=$(cat <<'EOF'
    <key>BraveP3AEnabled</key>
    <false/>
    <key>BraveStatsPingEnabled</key>
    <false/>
    <key>BraveWebDiscoveryEnabled</key>
    <false/>
    <key>MetricsReportingEnabled</key>
    <false/>
    <key>UrlKeyedAnonymizedDataCollectionEnabled</key>
    <false/>
    <key>SpellCheckServiceEnabled</key>
    <false/>
    <key>UserFeedbackAllowed</key>
    <false/>
    <key>DomainReliabilityAllowed</key>
    <false/>
    <key>PrivacySandboxAdTopicsEnabled</key>
    <false/>
    <key>PrivacySandboxSiteEnabledAdsEnabled</key>
    <false/>
    <key>PrivacySandboxAdMeasurementEnabled</key>
    <false/>
    <key>ShoppingListEnabled</key>
    <false/>
EOF
)

# --- Nag suppression: standard Chromium policies for the default-browser prompt, promotional
# content, and in-product surveys. PromotionsEnabled (Chromium 128+) is used rather than the
# older PromotionalTabsEnabled, which upstream now flags Deprecated.
NAG_KEYS=$(cat <<'EOF'
    <key>DefaultBrowserSettingEnabled</key>
    <false/>
    <key>PromotionsEnabled</key>
    <false/>
    <key>FeedbackSurveysEnabled</key>
    <false/>
EOF
)

# --- Leak plugging: stop small background data leaks (keystrokes to search engine, error-page
# lookups to Google, WebRTC exposing your real IP behind a VPN) and cap Safe Browsing at
# Standard so it can't be bumped to Enhanced (which streams visited URLs to Google in real time)
LEAK_KEYS=$(cat <<'EOF'
    <key>SearchSuggestEnabled</key>
    <false/>
    <key>AlternateErrorPagesEnabled</key>
    <false/>
    <key>SafeBrowsingProtectionLevel</key>
    <integer>1</integer>
    <key>WebRtcIPHandling</key>
    <string>default_public_interface_only</string>
EOF
)

# --- Performance: stop preloading/prefetching pages Brave guesses you'll click next (saves
# network + battery), keep GPU acceleration on, and force background-tab JavaScript timers to
# be coalesced to once a minute after 5 minutes backgrounded (real CPU/battery saving on many
# tabs). BackgroundModeEnabled is deliberately absent — Chromium only supports it on Windows
# and Linux, so it would sit in brave://policy doing nothing on macOS.
PERF_KEYS=$(cat <<'EOF'
    <key>NetworkPredictionOptions</key>
    <integer>2</integer>
    <key>HardwareAccelerationModeEnabled</key>
    <true/>
    <key>IntensiveWakeUpThrottlingEnabled</key>
    <true/>
EOF
)

# --- Aggressive (opt-in): disables features some people actually rely on, so off by default
AGGRESSIVE_KEYS=$(cat <<'EOF'
    <key>SyncDisabled</key>
    <true/>
    <key>PasswordManagerEnabled</key>
    <false/>
    <key>AutofillAddressEnabled</key>
    <false/>
    <key>AutofillCreditCardEnabled</key>
    <false/>
    <key>TranslateEnabled</key>
    <false/>
EOF
)

# --- Paranoid (opt-in): hardening that changes behaviour you'll notice (no Tor windows, no
# Chromecast, sites relying on third-party cookies break, plain-HTTP sites need a click-through),
# plus locking Brave's De-AMP, debouncing, and language fingerprinting protection on
PARANOID_KEYS=$(cat <<'EOF'
    <key>TorDisabled</key>
    <true/>
    <key>EnableMediaRouter</key>
    <false/>
    <key>BlockThirdPartyCookies</key>
    <true/>
    <key>HttpsOnlyMode</key>
    <string>force_enabled</string>
    <key>PaymentMethodQueryEnabled</key>
    <false/>
    <key>BrowserSignin</key>
    <integer>0</integer>
    <key>BraveDeAmpEnabled</key>
    <true/>
    <key>BraveDebouncingEnabled</key>
    <true/>
    <key>BraveReduceLanguageEnabled</key>
    <true/>
EOF
)

# --- Performance tier (opt-in): trades responsiveness for memory and battery. Memory Saver
# discards background tabs — they reload when you switch back, so you'll see a flash and
# unsaved form input in a discarded tab is lost. Savings level 2 discards them sooner.
# Battery saver throttles the frame rate once the battery is low.
PERFORMANCE_KEYS=$(cat <<'EOF'
    <key>HighEfficiencyModeEnabled</key>
    <true/>
    <key>MemorySaverModeSavings</key>
    <integer>2</integer>
    <key>BatterySaverModeAvailability</key>
    <integer>1</integer>
EOF
)

BODY="${CORE_KEYS}
${PRIVACY_KEYS}
${NAG_KEYS}
${LEAK_KEYS}
${PERF_KEYS}"

if [[ "$AGGRESSIVE" -eq 1 ]]; then
  BODY="${BODY}
${AGGRESSIVE_KEYS}"
fi

if [[ "$PARANOID" -eq 1 ]]; then
  BODY="${BODY}
${PARANOID_KEYS}"
fi

if [[ "$PERFORMANCE" -eq 1 ]]; then
  BODY="${BODY}
${PERFORMANCE_KEYS}"
fi

PLIST_CONTENT=$(cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
${BODY}
</dict>
</plist>
EOF
)

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Would write to: $POLICY_FILE"
  echo "---"
  echo "$PLIST_CONTENT"
  exit 0
fi

echo "This will write a managed-policy plist for Brave. You'll be prompted for your password (sudo)."
sudo mkdir -p "$POLICY_DIR"
echo "$PLIST_CONTENT" | sudo tee "$POLICY_FILE" > /dev/null
sudo chown root:wheel "$POLICY_FILE"
sudo chmod 644 "$POLICY_FILE"
sudo killall cfprefsd 2>/dev/null || true

echo
echo "Applied managed policy to: $POLICY_FILE"
if [[ "$AGGRESSIVE" -eq 1 ]]; then
  echo "Mode: aggressive (sync, autofill, password manager, translate also disabled)"
else
  echo "Mode: core (re-run with --aggressive to also disable sync/autofill/password manager/translate)"
fi
if [[ "$PARANOID" -eq 1 ]]; then
  echo "Paranoid: on (Tor, Cast, third-party cookies, Google sign-in, payment probing off; HTTPS forced; De-AMP, debouncing, language fingerprinting protection locked on)"
fi
if [[ "$PERFORMANCE" -eq 1 ]]; then
  echo "Performance: on (Memory Saver at maximum savings, battery saver below threshold)"
fi
echo
echo "Quit and reopen Brave, then check brave://policy to confirm."
echo "Run './deshitify-brave.sh --undo' any time to revert."

if pgrep -x "Brave Browser" >/dev/null 2>&1; then
  read -r -p "Brave is currently running — quit and relaunch it now? [y/N] " REPLY
  if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    osascript -e 'quit app "Brave Browser"'
    sleep 1
    open -a "Brave Browser"
  fi
fi
