#!/usr/bin/env python3
"""Check the policy keys deshitify-brave writes are real and actually honoured.

Keys are parsed straight out of the three scripts, so this runs on any platform.

Offline checks (always): the three scripts agree on which keys each tier writes,
no key sits in two opt-in tiers, and the PowerShell -Undo list covers everything
the script can write.

Online checks (--online): every key is cross-referenced against Chromium's own
policy definitions on GitHub, confirming it exists, is supported on the platform
whose script writes it, and has not been removed by TARGET_CHROMIUM. This is what
catches an upstream rename -- a policy Brave silently ignores looks identical to a
working one unless you go and read brave://policy.
"""
import concurrent.futures as cf
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

TARGET_CHROMIUM = 155  # Brave stable's Chromium major; bump as Brave moves.

REPO = Path(__file__).resolve().parent.parent
RAW = ("https://raw.githubusercontent.com/chromium/chromium/main/"
       "components/policy/resources/templates/policy_definitions/")
TREE = "https://api.github.com/repos/chromium/chromium/git/trees/"
CONTENTS = ("https://api.github.com/repos/chromium/chromium/contents/"
            "components/policy/resources/templates")
BRAVE_GNI = ("https://raw.githubusercontent.com/brave/brave-core/master/components/policy/"
             "resources/templates/policy_definitions/brave_policies.gni")

TIERS = ["Core", "Privacy", "Nag", "Leak", "Perf", "Aggressive", "Paranoid", "Performance"]
OPT_IN = ["Aggressive", "Paranoid", "Performance"]

# Keys a platform deliberately omits because Chromium does not honour them there.
EXCEPTIONS = {"BackgroundModeEnabled": {"macOS"}}

failures = []


def fail(msg):
    failures.append(msg)


def parse_mac():
    src = (REPO / "deshitify-brave.sh").read_text()
    out = {}
    for tier in TIERS:
        m = re.search(r"^" + tier.upper() + r"_KEYS=\$\(cat <<'EOF'\n(.*?)\nEOF", src, re.S | re.M)
        if not m:
            fail(f"macOS script: no {tier.upper()}_KEYS block")
            continue
        out[tier] = re.findall(r"<key>(\w+)</key>", m.group(1))
    return out


def parse_linux():
    src = (REPO / "deshitify-brave-linux.sh").read_text()
    out = {}
    for tier in TIERS:
        t = tier.upper()
        m = re.search(r"^" + t + r"_KEYS=\$\(cat <<'" + t + r"_JSON'\n(.*?)\n" + t + r"_JSON", src, re.S | re.M)
        if not m:
            fail(f"Linux script: no {t}_KEYS block")
            continue
        out[tier] = re.findall(r'^\s*"(\w+)":', m.group(1), re.M)
    return out


def parse_windows():
    src = (REPO / "deshitify-brave.ps1").read_text(encoding="utf-8-sig")
    out = {}
    for tier in TIERS:
        m = re.search(r"\$" + tier + r"Keys\s*=\s*\[ordered\]@\{(.*?)\n\}", src, re.S)
        if not m:
            fail(f"PowerShell script: no ${tier}Keys block")
            continue
        out[tier] = re.findall(r"^\s*(\w+)\s*=\s*@\{", m.group(1), re.M)
    return out, src


PLATFORMS = {}
PLATFORMS["macOS"] = parse_mac()
PLATFORMS["Linux"] = parse_linux()
PLATFORMS["Windows"], PS_SRC = parse_windows()
if failures:
    print("\n".join("FAIL: " + f for f in failures))
    sys.exit(1)

print("Parsed keys per tier")
print("=" * 72)
for tier in TIERS:
    counts = " ".join(f"{p}={len(k.get(tier, []))}" for p, k in PLATFORMS.items())
    print(f"  {tier:12s} {counts}")

print()
print("Offline checks")
print("=" * 72)

for tier in TIERS:
    sets = {p: set(k.get(tier, [])) for p, k in PLATFORMS.items()}
    for plat, keys in sets.items():
        expected = set()
        for other, okeys in sets.items():
            expected |= {k for k in okeys if plat not in EXCEPTIONS.get(k, set())}
        if keys != expected:
            fail(f"{tier}: {plat} has {keys ^ expected} vs the other platforms")
print(f"  tier contents agree across all three scripts (minus documented exceptions)")

for plat, tiers in PLATFORMS.items():
    for i, a in enumerate(OPT_IN):
        for b in OPT_IN[i + 1:]:
            dup = set(tiers.get(a, [])) & set(tiers.get(b, []))
            if dup:
                fail(f"{plat}: {dup} appears in both --{a.lower()} and --{b.lower()}")
print(f"  no key appears in two opt-in tiers")

m = re.search(r"\$ManagedNames\s*=(.*?)\n\n", PS_SRC, re.S)
named = set(re.findall(r"\$(\w+)Keys\.Keys", m.group(1))) if m else set()
if named != set(TIERS):
    fail(f"PowerShell -Undo misses tiers: {set(TIERS) - named}")
print(f"  PowerShell -Undo covers all {len(TIERS)} tiers")

if "--online" not in sys.argv:
    print()
    print("Skipping upstream validation (pass --online to enable)")
else:
    print()
    print(f"Online checks against Chromium policy definitions (target: Chromium {TARGET_CHROMIUM})")
    print("=" * 72)

    def get(url):
        headers = {"User-Agent": "deshitify-brave-tests"}
        # api.github.com allows 60 requests/hour unauthenticated, which two concurrent
        # CI jobs can exhaust; GITHUB_TOKEN raises that to 5000.
        token = os.environ.get("GITHUB_TOKEN")
        if token and url.startswith("https://api.github.com/"):
            headers["Authorization"] = f"Bearer {token}"
        try:
            return urllib.request.urlopen(
                urllib.request.Request(url, headers=headers), timeout=60).read().decode()
        except urllib.error.HTTPError as e:
            if e.code in (403, 429):
                sys.exit(f"SKIP: GitHub rate-limited this runner ({e.code}) fetching {url}. "
                         "Set GITHUB_TOKEN to raise the limit.")
            raise

    brave_keys = set(re.findall(r'"BraveSoftware/(\w+)\.yaml"', get(BRAVE_GNI)))
    sha = next(e["sha"] for e in json.loads(get(CONTENTS)) if e["name"] == "policy_definitions")
    tree = json.loads(get(f"{TREE}{sha}?recursive=1"))
    if tree.get("truncated"):
        fail("Chromium policy tree came back truncated; cannot validate")
    paths = {e["path"].rsplit("/", 1)[-1][:-5]: e["path"]
             for e in tree["tree"] if e["path"].endswith(".yaml")}

    wanted = sorted({k for t in PLATFORMS.values() for ks in t.values() for k in ks})

    def supported_on(key):
        if key in brave_keys:
            return key, None
        if key not in paths:
            return key, []
        y = get(RAW + paths[key])
        m = re.search(r"^supported_on:\n((?:\s*-\s*\S+\n)+)", y, re.M)
        return key, re.findall(r"^\s*-\s*(\S+)\s*$", m.group(1), re.M) if m else []

    with cf.ThreadPoolExecutor(16) as ex:
        SUP = dict(ex.map(supported_on, wanted))

    SHORT = {"macOS": "mac", "Linux": "linux", "Windows": "win"}
    for plat, tiers in PLATFORMS.items():
        keys = sorted({k for ks in tiers.values() for k in ks})
        bad = []
        for key in keys:
            toks = SUP[key]
            if toks is None:
                continue  # Brave's own policy, not in Chromium's definitions
            if not toks:
                bad.append((key, "not a Chromium policy"))
                continue
            hits = []
            for t in toks:
                m = re.match(r"chrome\.(\*|win7?|mac|linux):(\d+)(?:-(\d+)?)?$", t)
                if not m:
                    continue
                scope, lo, hi = m.group(1), int(m.group(2)), m.group(3)
                if scope != "*" and not scope.startswith(SHORT[plat]):
                    continue
                hits.append((lo, int(hi) if hi else None, t))
            if not hits:
                bad.append((key, f"unsupported on {SHORT[plat]}: {' '.join(toks)}"))
                continue
            for lo, hi, t in hits:
                if lo > TARGET_CHROMIUM:
                    bad.append((key, f"needs Chromium {lo} ({t})"))
                elif hi is not None and hi < TARGET_CHROMIUM:
                    # Brave may still register a handler for such a policy, so
                    # brave://policy can show it OK; the behaviour behind it is
                    # what has gone, which the page cannot tell you.
                    bad.append((key, f"support ended at Chromium {hi} ({t})"))
        print(f"  {plat:8s} {len(keys):>2} keys  {'all live' if not bad else str(len(bad)) + ' INERT'}")
        for key, why in bad:
            print(f"           !! {key}: {why}")
            fail(f"{plat}: {key} -- {why}")

print()
print("=" * 72)
if failures:
    print(f"FAILED ({len(failures)} problem(s))")
    for f in failures:
        print("  - " + f)
    sys.exit(1)
print("PASSED")
