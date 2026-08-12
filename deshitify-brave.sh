#!/usr/bin/env bash
#
# deshitify-brave.sh — turn off Brave's built-in nags, upsells, and telemetry
# on macOS via Chromium managed-policy support (the same mechanism MDM uses).
#
# Usage:
#   ./deshitify-brave.sh                # apply core + privacy policies
#   ./deshitify-brave.sh --aggressive   # also disable sync/autofill/password manager/translate
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

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --undo) UNDO=1 ;;
    --aggressive) AGGRESSIVE=1 ;;
    -h|--help)
      sed -n '2,20p' "$0"
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

# --- Privacy: stop the phone-home pings (P3A "anonymous" telemetry, stats ping, web discovery, Chromium metrics)
PRIVACY_KEYS=$(cat <<'EOF'
    <key>BraveP3AEnabled</key>
    <false/>
    <key>BraveStatsPingEnabled</key>
    <false/>
    <key>BraveWebDiscoveryEnabled</key>
    <false/>
    <key>MetricsReportingEnabled</key>
    <false/>
EOF
)

# --- Nag suppression: standard Chromium policy for "what's new" pages after OS upgrades
# (PromotionalTabsEnabled was dropped upstream — Brave now reports it "Deprecated", so it's omitted)
NAG_KEYS=$(cat <<'EOF'
    <key>WelcomePageOnOSUpgradeEnabled</key>
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
    <key>WebRtcIPHandlingPolicy</key>
    <string>default_public_interface_only</string>
EOF
)

# --- Performance: stop Brave running as a background process after you quit it, and stop
# preloading/prefetching pages it guesses you'll click next (saves network + battery)
PERF_KEYS=$(cat <<'EOF'
    <key>BackgroundModeEnabled</key>
    <false/>
    <key>NetworkPredictionOptions</key>
    <integer>2</integer>
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

BODY="${CORE_KEYS}
${PRIVACY_KEYS}
${NAG_KEYS}
${LEAK_KEYS}
${PERF_KEYS}"

if [[ "$AGGRESSIVE" -eq 1 ]]; then
  BODY="${BODY}
${AGGRESSIVE_KEYS}"
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
