#!/usr/bin/env bash
#
# deshitify-brave-linux.sh — turn off Brave's built-in nags, upsells, and telemetry
# on Linux via Chromium managed-policy support (the same mechanism enterprise
# deployments use).
#
# Usage:
#   ./deshitify-brave-linux.sh                # apply core + privacy policies
#   ./deshitify-brave-linux.sh --aggressive   # also disable sync/autofill/password manager/translate
#   ./deshitify-brave-linux.sh --dry-run      # print the JSON that would be written, change nothing
#   ./deshitify-brave-linux.sh --undo         # remove the managed policy and restore defaults
#
# What this does:
#   Writes /etc/brave/policies/managed/deshitify-brave.json, which Brave (being
#   Chromium underneath) reads as an enterprise policy file. This is the
#   supported, documented way to configure Brave outside of brave://settings —
#   see https://support.brave.app/hc/en-us/articles/360039248271-Group-Policy
#
# Notes:
#   - Requires sudo (the policy directory is root-owned).
#   - Policy-set values are greyed out in brave://settings and show "managed by
#     your organization" — that's expected, it's how policy enforcement works.
#   - Flatpak installs are sandboxed and can't see /etc by default. Re-run with
#     --flatpak to also grant the Flatpak app read access to the policy dir.
#   - Run --undo to remove the file and get standard, unmanaged Brave back.

set -euo pipefail

POLICY_DIR="/etc/brave/policies/managed"
POLICY_FILE="${POLICY_DIR}/deshitify-brave.json"
FLATPAK_ID="com.brave.Browser"

DRY_RUN=0
UNDO=0
AGGRESSIVE=0
FLATPAK=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --undo) UNDO=1 ;;
    --aggressive) AGGRESSIVE=1 ;;
    --flatpak) FLATPAK=1 ;;
    -h|--help)
      sed -n '2,22p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

if [[ "$(uname)" != "Linux" ]]; then
  echo "This script is Linux-only. On macOS use deshitify-brave.sh, on Windows use deshitify-brave.ps1." >&2
  exit 1
fi

BRAVE_BIN=""
for candidate in brave-browser brave-browser-stable brave; do
  if command -v "$candidate" >/dev/null 2>&1; then
    BRAVE_BIN="$candidate"
    break
  fi
done
BRAVE_FOUND=0
[[ -n "$BRAVE_BIN" ]] && BRAVE_FOUND=1
command -v flatpak >/dev/null 2>&1 && flatpak info "$FLATPAK_ID" >/dev/null 2>&1 && BRAVE_FOUND=1
if [[ "$BRAVE_FOUND" -eq 0 ]]; then
  echo "Warning: Brave Browser not found (checked brave-browser, brave-browser-stable, brave, flatpak). Continuing anyway —" >&2
  echo "the policy will apply the next time Brave is installed/launched." >&2
fi

if [[ "$UNDO" -eq 1 ]]; then
  if [[ -f "$POLICY_FILE" ]]; then
    echo "Removing $POLICY_FILE"
    sudo rm -f "$POLICY_FILE"
    echo "Done. Restart Brave for the change to take effect."
  else
    echo "No managed policy file found at $POLICY_FILE — nothing to undo."
  fi
  if [[ "$FLATPAK" -eq 1 ]] && command -v flatpak >/dev/null 2>&1; then
    echo "Removing Flatpak filesystem override for $FLATPAK_ID"
    sudo flatpak override --reset "$FLATPAK_ID" 2>/dev/null || true
  fi
  exit 0
fi

# --- Core: kill the upsell surfaces (Rewards/Wallet/VPN nags, Leo, News, Talk, Playlist, Wayback prompt)
CORE_KEYS=$(cat <<'CORE_JSON'
  "BraveRewardsDisabled": true,
  "BraveWalletDisabled": true,
  "BraveVPNDisabled": true,
  "BraveAIChatEnabled": false,
  "BraveNewsDisabled": true,
  "BraveTalkDisabled": true,
  "BravePlaylistEnabled": false,
  "BraveWaybackMachineEnabled": false,
CORE_JSON
)

# --- Privacy: stop the phone-home pings (P3A "anonymous" telemetry, stats ping, web discovery, Chromium metrics)
PRIVACY_KEYS=$(cat <<'PRIVACY_JSON'
  "BraveP3AEnabled": false,
  "BraveStatsPingEnabled": false,
  "BraveWebDiscoveryEnabled": false,
  "MetricsReportingEnabled": false,
PRIVACY_JSON
)

# --- Nag suppression: standard Chromium policy for "what's new" pages after OS upgrades
# (PromotionalTabsEnabled was dropped upstream — Brave now reports it "Deprecated", so it's omitted)
NAG_KEYS=$(cat <<'NAG_JSON'
  "WelcomePageOnOSUpgradeEnabled": false,
NAG_JSON
)

# --- Leak plugging: stop small background data leaks (keystrokes to search engine, error-page
# lookups to Google, WebRTC exposing your real IP behind a VPN) and cap Safe Browsing at
# Standard so it can't be bumped to Enhanced (which streams visited URLs to Google in real time)
LEAK_KEYS=$(cat <<'LEAK_JSON'
  "SearchSuggestEnabled": false,
  "AlternateErrorPagesEnabled": false,
  "SafeBrowsingProtectionLevel": 1,
  "WebRtcIPHandlingPolicy": "default_public_interface_only",
LEAK_JSON
)

# --- Performance: stop Brave running as a background process after you quit it, and stop
# preloading/prefetching pages it guesses you'll click next (saves network + battery)
PERF_KEYS=$(cat <<'PERF_JSON'
  "BackgroundModeEnabled": false,
  "NetworkPredictionOptions": 2,
PERF_JSON
)

# --- Aggressive (opt-in): disables features some people actually rely on, so off by default
AGGRESSIVE_KEYS=$(cat <<'AGGRESSIVE_JSON'
  "SyncDisabled": true,
  "PasswordManagerEnabled": false,
  "AutofillAddressEnabled": false,
  "AutofillCreditCardEnabled": false,
  "TranslateEnabled": false,
AGGRESSIVE_JSON
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

# Strip the trailing comma off the last entry so the object is valid JSON.
BODY="$(echo "$BODY" | sed '$ s/,$//')"

JSON_CONTENT="{
${BODY}
}"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Would write to: $POLICY_FILE"
  echo "---"
  echo "$JSON_CONTENT"
  exit 0
fi

echo "This will write a managed-policy JSON file for Brave. You'll be prompted for your password (sudo)."
sudo mkdir -p "$POLICY_DIR"
echo "$JSON_CONTENT" | sudo tee "$POLICY_FILE" > /dev/null
sudo chown root:root "$POLICY_FILE"
sudo chmod 644 "$POLICY_FILE"

if [[ "$FLATPAK" -eq 1 ]]; then
  if command -v flatpak >/dev/null 2>&1; then
    echo "Granting Flatpak $FLATPAK_ID read access to $POLICY_DIR"
    sudo flatpak override --filesystem="$POLICY_DIR:ro" "$FLATPAK_ID"
  else
    echo "Warning: --flatpak given but flatpak isn't installed. Skipping override." >&2
  fi
fi

echo
echo "Applied managed policy to: $POLICY_FILE"
if [[ "$AGGRESSIVE" -eq 1 ]]; then
  echo "Mode: aggressive (sync, autofill, password manager, translate also disabled)"
else
  echo "Mode: core (re-run with --aggressive to also disable sync/autofill/password manager/translate)"
fi
echo
echo "Quit and reopen Brave, then check brave://policy to confirm."
echo "If you're on Flatpak and Brave doesn't pick this up, re-run with --flatpak."
echo "Run './deshitify-brave-linux.sh --undo' any time to revert."

if pgrep -x "brave" >/dev/null 2>&1 || pgrep -x "brave-browser" >/dev/null 2>&1; then
  read -r -p "Brave is currently running — quit and relaunch it now? [y/N] " REPLY
  if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    pkill -x brave 2>/dev/null || pkill -x brave-browser 2>/dev/null || true
    sleep 1
    if [[ -n "$BRAVE_BIN" ]]; then
      nohup "$BRAVE_BIN" >/dev/null 2>&1 &
      disown
    elif command -v flatpak >/dev/null 2>&1 && flatpak info "$FLATPAK_ID" >/dev/null 2>&1; then
      nohup flatpak run "$FLATPAK_ID" >/dev/null 2>&1 &
      disown
    else
      echo "Warning: couldn't find Brave's executable to relaunch — start it yourself." >&2
    fi
  fi
fi
