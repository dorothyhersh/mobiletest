#!/usr/bin/env bash
# After the emulator is booted:
#   1. Root adbd (google_apis = userdebug). Play Store images cannot root.
#   2. Push Samsung identity to /data/local.prop and reboot so Chrome
#      reads SM-S928B from Build.MODEL / client hints.
#   3. Skip Chrome first-run / welcome / default-browser / sync
#   4. Open https://www.google.com in Chrome
#   5. Open the Google search for newscredo.com
#   6. Smoothly scroll until "Newscredo - News" is on screen, then tap it
#   7. Screenshots to artifacts/
set -euo pipefail
ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
ARTIFACTS="${ROOT}/artifacts"
mkdir -p "$ARTIFACTS"
CHROME_PKG="com.android.chrome"
TARGET_URL="https://www.google.com"
SEARCH_URL="https://www.google.com/search?q=newscredo.com"
RESULT_TEXT="Newscredo - News"
HAVE_ROOT=0
log() { printf '[capture] %s\n' "$*"; }
adb_sh() {
  adb shell "$@" | tr -d '\r'
}
wait_for_boot() {
  adb wait-for-device
  local i=0
  while (( i < 180 )); do
    local completed
    completed="$(adb_sh getprop sys.boot_completed 2>/dev/null || true)"
    if [[ "$completed" == "1" ]]; then
      sleep 6
      return 0
    fi
    sleep 2
    i=$((i + 1))
  done
  log "timed out waiting for boot"
  return 1
}
uid_is_root() {
  local uid
  uid="$(adb_sh id -u 2>/dev/null || true)"
  [[ "$uid" == "0" ]]
}
ensure_root() {
  local i out
  for i in 1 2 3 4 5 6; do
    if uid_is_root; then
      log "adb shell is root (uid=0)"
      return 0
    fi
    out="$(adb root 2>&1 || true)"
    log "adb root (${i}): ${out}"
    sleep 3
    adb wait-for-device
  done
  if uid_is_root; then
    log "adb shell is root (uid=0)"
    return 0
  fi
  log "no root — Play Store/user images block adbd. Identity will use emulator -prop only."
  return 1
}
samsung_prop_file() {
  cat <<'PROP'
ro.product.brand=samsung
ro.product.manufacturer=samsung
ro.product.model=SM-S928B
ro.product.name=e3sxxx
ro.product.device=e3s
ro.product.board=e3s
ro.product.marketname=Galaxy S24 Ultra
ro.build.product=e3s
ro.build.user=dpi
ro.build.host=21DJ6B09
ro.build.type=user
ro.build.tags=release-keys
ro.build.flavor=e3sxxx-user
ro.build.characteristics=phone
ro.build.id=UP1A.231005.007
ro.build.display.id=UP1A.231005.007.S928BXXS3AXKF
ro.build.version.incremental=S928BXXS3AXKF
ro.build.version.release=14
ro.build.version.release_or_codename=14
ro.build.version.sdk=34
ro.build.version.security_patch=2024-11-01
ro.build.fingerprint=samsung/e3sxxx/e3s:14/UP1A.231005.007/S928BXXS3AXKF:user/release-keys
ro.build.description=e3sxxx-user 14 UP1A.231005.007 S928BXXS3AXKF release-keys
ro.product.system.brand=samsung
ro.product.system.manufacturer=samsung
ro.product.system.model=SM-S928B
ro.product.system.name=e3sxxx
ro.product.system.device=e3s
ro.product.vendor.brand=samsung
ro.product.vendor.manufacturer=samsung
ro.product.vendor.model=SM-S928B
ro.product.vendor.name=e3sxxx
ro.product.vendor.device=e3s
ro.product.odm.brand=samsung
ro.product.odm.manufacturer=samsung
ro.product.odm.model=SM-S928B
ro.product.odm.name=e3sxxx
ro.product.odm.device=e3s
ro.product.product.brand=samsung
ro.product.product.manufacturer=samsung
ro.product.product.model=SM-S928B
ro.product.product.name=e3sxxx
ro.product.product.device=e3s
ro.product.bootimage.brand=samsung
ro.product.bootimage.manufacturer=samsung
ro.product.bootimage.model=SM-S928B
ro.product.bootimage.name=e3sxxx
ro.product.bootimage.device=e3s
ro.product.system_ext.brand=samsung
ro.product.system_ext.manufacturer=samsung
ro.product.system_ext.model=SM-S928B
ro.product.system_ext.name=e3sxxx
ro.product.system_ext.device=e3s
ro.system.build.fingerprint=samsung/e3sxxx/e3s:14/UP1A.231005.007/S928BXXS3AXKF:user/release-keys
ro.vendor.build.fingerprint=samsung/e3sxxx/e3s:14/UP1A.231005.007/S928BXXS3AXKF:user/release-keys
ro.bootimage.build.fingerprint=samsung/e3sxxx/e3s:14/UP1A.231005.007/S928BXXS3AXKF:user/release-keys
ro.odm.build.fingerprint=samsung/e3sxxx/e3s:14/UP1A.231005.007/S928BXXS3AXKF:user/release-keys
ro.product.build.fingerprint=samsung/e3sxxx/e3s:14/UP1A.231005.007/S928BXXS3AXKF:user/release-keys
ro.system_ext.build.fingerprint=samsung/e3sxxx/e3s:14/UP1A.231005.007/S928BXXS3AXKF:user/release-keys
ro.boot.em.model=SM-S928B
ro.csc.sales_code=EUX
ro.csc.country_code=GB
ro.csc.countryiso_code=GB
ro.product.first_api_level=34
ro.sf.lcd_density=420
persist.sys.locale=en-US
persist.sys.language=en
persist.sys.country=US
persist.sys.timezone=Europe/London
PROP
}
write_samsung_identity() {
  local tmp
  tmp="$(mktemp)"
  samsung_prop_file > "$tmp"
  adb push "$tmp" /data/local.prop
  adb_sh chmod 644 /data/local.prop
  rm -f "$tmp"
  log "pushed /data/local.prop"
  adb_sh ls -l /data/local.prop || true
}
apply_unprivileged_props() {
  adb shell setprop persist.sys.locale en-US >/dev/null 2>&1 || true
  adb shell setprop persist.sys.language en >/dev/null 2>&1 || true
  adb shell setprop persist.sys.country US >/dev/null 2>&1 || true
  adb shell setprop persist.sys.timezone Europe/London >/dev/null 2>&1 || true
}
dump_identity() {
  {
    echo "=== shell ==="
    adb_sh id || true
    echo "ro.debuggable=$(adb_sh getprop ro.debuggable)"
    echo "ro.build.type=$(adb_sh getprop ro.build.type)"
    echo
    echo "=== identity ==="
    for key in \
      ro.product.brand ro.product.manufacturer ro.product.model \
      ro.product.name ro.product.device ro.product.marketname \
      ro.product.product.model ro.build.fingerprint \
      ro.build.version.release ro.build.version.sdk \
      ro.build.characteristics ro.hardware ro.kernel.qemu \
      persist.sys.locale persist.sys.timezone; do
      printf '%s=%s\n' "$key" "$(adb_sh getprop "$key")"
    done
    echo
    echo "=== display ==="
    adb_sh wm size || true
    adb_sh wm density || true
  } | tee "$ARTIFACTS/identity.txt"
}
skip_chrome_welcome() {
  local cmdline='chrome --disable-fre --no-first-run --no-default-browser-check --disable-search-engine-choice-screen --disable-features=TranslateUI,ChromeWhatsNew,PrivacySandboxSettings4,InterestFeedContentSuggestions'
  local tmp
  tmp="$(mktemp)"
  printf '%s\n' "$cmdline" > "$tmp"
  adb shell am set-debug-app --persistent "$CHROME_PKG" >/dev/null || true
  # /data/local/tmp is world-writable even without root.
  adb push "$tmp" /data/local/tmp/chrome-command-line >/dev/null
  adb_sh chmod 644 /data/local/tmp/chrome-command-line || true
  if [[ "$HAVE_ROOT" == "1" ]]; then
    adb push "$tmp" /data/local/chrome-command-line >/dev/null || true
    adb_sh chmod 644 /data/local/chrome-command-line || true
  fi
  rm -f "$tmp"
  adb shell pm grant "$CHROME_PKG" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
  adb shell pm grant "$CHROME_PKG" android.permission.ACCESS_FINE_LOCATION >/dev/null 2>&1 || true
  adb shell pm grant "$CHROME_PKG" android.permission.ACCESS_COARSE_LOCATION >/dev/null 2>&1 || true
  adb shell pm grant "$CHROME_PKG" android.permission.CAMERA >/dev/null 2>&1 || true
  adb shell pm grant "$CHROME_PKG" android.permission.RECORD_AUDIO >/dev/null 2>&1 || true
  adb shell am force-stop "$CHROME_PKG" >/dev/null 2>&1 || true
  log "Chrome first-run flags written for ${CHROME_PKG}"
}
# Exact-match button text only (short needles like "ok" would also match
# "cookie" or text inside search results).
dismiss_chrome_sheets() {
  python3 - <<'PY'
import re, subprocess, time
EXACT = {
    "use without an account", "no thanks", "no, thanks", "don't allow",
    "not now", "skip", "got it", "accept & continue", "accept and continue",
    "no thanks, i'll stay signed out", "reject all", "accept all",
    "i agree", "dismiss",
}
def dump():
    subprocess.run(["adb","shell","uiautomator","dump","/sdcard/uidump.xml"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    p = subprocess.run(["adb","exec-out","cat","/sdcard/uidump.xml"],
                       capture_output=True, check=False)
    return p.stdout.decode("utf-8","replace")
def nodes(xml):
    for m in re.finditer(r"<node\s+([^>]+)/?>", xml):
        a = dict(re.findall(r'(\w+)="([^"]*)"', m.group(1)))
        mm = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", a.get("bounds",""))
        if not mm:
            continue
        x1,y1,x2,y2 = map(int, mm.groups())
        yield (a.get("text","").strip().lower(),
               a.get("content-desc","").strip().lower(),
               (x1+x2)//2, (y1+y2)//2)
tapped = 0
for _ in range(6):
    found = False
    for text, desc, x, y in nodes(dump()):
        if text in EXACT or desc in EXACT:
            subprocess.run(["adb","shell","input","tap",str(x),str(y)], check=False)
            tapped += 1; found = True; time.sleep(1.2)
            break
    if not found:
        break
print(f"dismissed {tapped} sheets", flush=True)
PY
}
resolve_chrome() {
  local pkg
  for pkg in com.android.chrome com.chrome.beta com.chrome.dev org.chromium.chrome; do
    if adb_sh pm path "$pkg" 2>/dev/null | grep -q "package:"; then
      CHROME_PKG="$pkg"
      log "using browser package ${CHROME_PKG}"
      return 0
    fi
  done
  log "Chrome is not installed on this system image"
  adb_sh pm list packages | tee "$ARTIFACTS/packages.txt" || true
  return 1
}
open_url() {
  adb shell am start \
    -p "$CHROME_PKG" \
    -a android.intent.action.VIEW \
    -c android.intent.category.BROWSABLE \
    -d "$1" \
    -f 0x10000000 >/dev/null
  log "opened $1"
}
wait_for_page() {
  sleep "${1:-6}"
}
# Scroll smoothly until the result text is visible, then tap it.
tap_search_result() {
  RESULT_TEXT="$RESULT_TEXT" MAX_SCROLLS="${MAX_SCROLLS:-40}" python3 - <<'PY'
import os, re, subprocess, sys, time

TARGET = os.environ["RESULT_TEXT"].strip().lower()
MAX_SCROLLS = int(os.environ["MAX_SCROLLS"])

def sh(*args):
    return subprocess.run(["adb", *args], capture_output=True, check=False)

def size():
    out = sh("shell", "wm", "size").stdout.decode()
    m = re.findall(r"(\d+)x(\d+)", out)
    return tuple(map(int, m[-1])) if m else (1080, 2340)

W, H = size()
TOP_SAFE, BOTTOM_SAFE = int(H * 0.18), int(H * 0.90)   # avoid URL bar / nav bar

def dump():
    sh("shell", "uiautomator", "dump", "/sdcard/uidump.xml")
    return sh("exec-out", "cat", "/sdcard/uidump.xml").stdout.decode("utf-8", "replace")

def find(xml):
    for m in re.finditer(r"<node\s+([^>]+)/?>", xml):
        a = dict(re.findall(r'(\w+)="([^"]*)"', m.group(1)))
        if "url_bar" in a.get("resource-id", ""):
            continue
        blob = (a.get("text", "") + " " + a.get("content-desc", "")).lower()
        if TARGET not in blob:
            continue
        mm = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", a.get("bounds", ""))
        if not mm:
            continue
        x1, y1, x2, y2 = map(int, mm.groups())
        if x2 - x1 <= 0 or y2 - y1 <= 0:
            continue
        yield (x1 + x2) // 2, (y1 + y2) // 2

def smooth_scroll():
    x = W // 2
    # slow, moderate-length swipe (700 ms) so it reads as a gentle scroll
    sh("shell", "input", "swipe", str(x), str(int(H * 0.72)),
       str(x), str(int(H * 0.42)), "700")
    time.sleep(1.0)

for attempt in range(MAX_SCROLLS + 1):
    hit = next((p for p in find(dump()) if TOP_SAFE < p[1] < BOTTOM_SAFE), None)
    if hit:
        sh("shell", "input", "tap", str(hit[0]), str(hit[1]))
        print(f"tapped '{TARGET}' at {hit} after {attempt} scrolls", flush=True)
        sys.exit(0)
    print(f"not on screen (attempt {attempt}), scrolling...", flush=True)
    smooth_scroll()

print("result not found", flush=True)
sys.exit(1)
PY
}
screenshot() {
  local name="$1"
  adb exec-out screencap -p > "${ARTIFACTS}/${name}"
  log "wrote ${ARTIFACTS}/${name} ($(wc -c < "${ARTIFACTS}/${name}") bytes)"
}
settle_device() {
  adb shell svc power stayon true >/dev/null || true
  adb shell settings put global stay_on_while_plugged_in 3 >/dev/null || true
  adb shell settings put secure lockscreen.disabled 1 >/dev/null || true
  adb shell locksettings set-disabled true >/dev/null 2>&1 || true
  adb shell wm dismiss-keyguard >/dev/null 2>&1 || true
  adb_sh wm size 1080x2340 || true
  adb_sh wm density 420 || true
}
# --- main ---
log "waiting for first boot"
wait_for_boot
if ensure_root; then
  HAVE_ROOT=1
fi
settle_device
apply_unprivileged_props
dump_identity
if [[ "$HAVE_ROOT" == "1" ]]; then
  write_samsung_identity
  log "rebooting so identity props load before Chrome"
  adb reboot
  wait_for_boot
  if ensure_root; then
    HAVE_ROOT=1
  else
    HAVE_ROOT=0
  fi
  settle_device
  apply_unprivileged_props
  dump_identity
else
  log "skipping /data/local.prop (no root). Boot-time emulator -prop still applied."
fi
resolve_chrome
skip_chrome_welcome

# 1) open google.com first
open_url "$TARGET_URL"
wait_for_page 5
dismiss_chrome_sheets
screenshot "01-google-home.png"

# 2) go to the search results (same as typing it in the address bar)
open_url "$SEARCH_URL"
wait_for_page 6
dismiss_chrome_sheets
screenshot "02-search-results.png"

# 3) scroll smoothly until "Newscredo - News" is found, then tap it
if tap_search_result; then
  wait_for_page 10
  screenshot "03-newscredo-opened.png"
  sleep 6
  screenshot "04-newscredo-late.png"
else
  log "could not find '${RESULT_TEXT}' in results"
  screenshot "03-not-found.png"
fi

log "done"
ls -la "$ARTIFACTS"
