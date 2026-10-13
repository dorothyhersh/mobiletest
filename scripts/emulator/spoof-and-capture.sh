#!/usr/bin/env bash
# After the emulator is booted:
#   1. Root adbd (google_apis = userdebug). Play Store images cannot root.
#   2. Push Samsung identity to /data/local.prop and reboot so Chrome
#      reads SM-S928B from Build.MODEL / client hints.
#   3. Skip Chrome first-run / welcome / default-browser / sync
#   4. Open https://deviceinfo.me in Chrome
#   5. Screenshot to artifacts/
set -euo pipefail

ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
ARTIFACTS="${ROOT}/artifacts"
mkdir -p "$ARTIFACTS"

CHROME_PKG="com.android.chrome"
TARGET_URL="https://newscredo.com"
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

dismiss_chrome_sheets() {
  python3 - <<'PY'
import re, subprocess, time

NEEDLES = [
    "use without an account",
    "no thanks",
    "don't allow",
    "dont allow",
    "not now",
    "skip",
    "got it",
    "accept & continue",
    "accept and continue",
    "continue",
    "ok",
    "dismiss",
    "never",
    "no, thanks",
]

def dump():
    subprocess.run(
        ["adb", "shell", "uiautomator", "dump", "/sdcard/uidump.xml"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
    )
    p = subprocess.run(
        ["adb", "exec-out", "cat", "/sdcard/uidump.xml"],
        capture_output=True, check=False,
    )
    return p.stdout.decode("utf-8", "replace")

def nodes(xml):
    out = []
    for m in re.finditer(r"<node\s+([^>]+)/?>", xml):
        attrs = dict(re.findall(r'(\w+)="([^"]*)"', m.group(1)))
        bounds = attrs.get("bounds") or ""
        mm = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", bounds)
        if not mm:
            continue
        x1, y1, x2, y2 = map(int, mm.groups())
        blob = " ".join(
            [
                attrs.get("text", ""),
                attrs.get("content-desc", ""),
                attrs.get("resource-id", ""),
            ]
        ).strip().lower()
        out.append((blob, (x1 + x2) // 2, (y1 + y2) // 2))
    return out

tapped = 0
for _ in range(8):
    xml = dump()
    found = False
    for blob, x, y in nodes(xml):
        if not blob:
            continue
        if any(n in blob for n in NEEDLES):
            subprocess.run(["adb", "shell", "input", "tap", str(x), str(y)], check=False)
            tapped += 1
            found = True
            time.sleep(1.2)
            break
    if not found:
        break

print(f"dismissed {tapped} chrome sheets", flush=True)
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

launch_chrome() {
  adb shell am start \
    -p "$CHROME_PKG" \
    -a android.intent.action.VIEW \
    -c android.intent.category.BROWSABLE \
    -d "$TARGET_URL" \
    -f 0x10000000 >/dev/null

  log "launched ${CHROME_PKG} → ${TARGET_URL}"
}

wait_for_page() {
  local i=0
  while (( i < 40 )); do
    if adb_sh dumpsys activity activities 2>/dev/null | grep -qi "deviceinfo"; then
      log "deviceinfo activity visible"
      sleep 10
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done
  log "did not observe deviceinfo in activity dump; waiting anyway"
  sleep 12
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
launch_chrome
sleep 3
dismiss_chrome_sheets
launch_chrome
wait_for_page
dismiss_chrome_sheets
screenshot "deviceinfo-samsung.png"
sleep 6
screenshot "deviceinfo-samsung-late.png"

log "done"
ls -la "$ARTIFACTS"
