#!/usr/bin/env bash
# After the emulator is booted:
#   1. Root adbd (google_apis = userdebug). Play Store images cannot root.
#   2. Push Samsung identity to /data/local.prop and reboot so Chrome
#      reads SM-S928B from Build.MODEL / client hints.
#   3. Skip Chrome first-run / welcome / default-browser / sync
#   4. Open https://www.google.com in Chrome
#   5. Open the Google search for newscredo.com
#   6. Via Chrome DevTools: find the result link to https://newscredo.com, scroll smoothly, tap it
#   7. On newscredo.com: smooth-scroll, randomly dwell 70-120s, tap internal links
#      (articles / categories), repeat browse cycle 2 times, screenshots to artifacts/
set -euo pipefail
ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
ARTIFACTS="${ROOT}/artifacts"
mkdir -p "$ARTIFACTS"
CHROME_PKG="com.android.chrome"
TARGET_URL="https://www.google.com"
SEARCH_URL="https://www.google.com/search?q=newscredo.com"
RESULT_HOST="https://newscredo.com"   # result link to click: https://newscredo.com
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
# Find "Newscredo - News" in the real page DOM through Chrome DevTools
# (uiautomator cannot see web page text in Chrome, only the toolbar),
# scroll smoothly until it is in view, then tap it with a real touch gesture.
tap_search_result() {
  python3 -m pip install -q websocket-client --break-system-packages >/dev/null 2>&1 \
    || python3 -m pip install -q websocket-client >/dev/null 2>&1 || true
  adb forward tcp:9222 localabstract:chrome_devtools_remote >/dev/null 2>&1 || true
  RESULT_HOST="$RESULT_HOST" RESULT_TEXT="$RESULT_TEXT" ARTIFACTS="$ARTIFACTS" MAX_SCROLLS="${MAX_SCROLLS:-40}" python3 - <<'PY'
import json, os, sys, time, urllib.request
import websocket
TARGET = os.environ["RESULT_TEXT"].strip().lower()
HOST = os.environ["RESULT_HOST"].strip().lower()
ARTIFACTS = os.environ["ARTIFACTS"]
MAX_SCROLLS = int(os.environ["MAX_SCROLLS"])
def get_tabs():
    with urllib.request.urlopen("http://127.0.0.1:9222/json", timeout=5) as r:
        return json.loads(r.read().decode())
tab = None
for _ in range(30):
    try:
        pages = [t for t in get_tabs() if t.get("type") == "page"]
        pages.sort(key=lambda t: "google." not in t.get("url", ""))
        if pages:
            tab = pages[0]
            break
    except Exception:
        pass
    time.sleep(1)
if not tab:
    print("DevTools tab not reachable", flush=True)
    sys.exit(2)
print("attached to:", tab.get("url"), flush=True)
ws = websocket.create_connection(tab["webSocketDebuggerUrl"], timeout=20, suppress_origin=True)
_id = 0
def cdp(method, **params):
    global _id
    _id += 1
    ws.send(json.dumps({"id": _id, "method": method, "params": params}))
    while True:
        msg = json.loads(ws.recv())
        if msg.get("id") == _id:
            return msg.get("result", {})
def js(expr):
    r = cdp("Runtime.evaluate", expression=expr, returnByValue=True)
    return r.get("result", {}).get("value")
# ---- debug dump so the real selectors are visible in artifacts ----
DEBUG_JS = """(() => JSON.stringify({
  url: location.href, title: document.title,
  headings: [...document.querySelectorAll('h3,[role=heading]')]
      .map(e => (e.innerText||'').trim()).filter(Boolean).slice(0,40),
  links: [...document.querySelectorAll('a[href]')]
      .map(a => ({t:(a.innerText||'').trim().slice(0,100), h:a.href}))
      .filter(x => x.t).slice(0,40),
  body: (document.body.innerText||'').slice(0,1500)
}))()"""
dbg = js(DEBUG_JS)
with open(os.path.join(ARTIFACTS, "page-debug.json"), "w") as f:
    f.write(dbg or "{}")
d = json.loads(dbg or "{}")
print("page title:", d.get("title"), flush=True)
print("headings:", d.get("headings"), flush=True)
body = (d.get("body") or "").lower()
if "unusual traffic" in body or "not a robot" in body or "captcha" in body:
    print("Google is showing a bot check / CAPTCHA page", flush=True)
FIND_JS = """(() => {
  const HOST = %s, TEXT = %s;
  const vis = e => { const r = e.getBoundingClientRect(), st = getComputedStyle(e);
    return r.width > 0 && r.height > 0 && st.visibility !== 'hidden' && st.display !== 'none'; };
  const pointsToHost = a => {
    try {
      const u = new URL(a.href);
      if (u.pathname === '/search') return false;
      const h = decodeURIComponent(a.href).toLowerCase();
      return u.hostname === HOST || u.hostname === 'www.' + HOST ||
             h.includes('://' + HOST) || h.includes('://www.' + HOST);
    } catch (e) { return false; }
  };
  const links = [...document.querySelectorAll('a[href]')].filter(a => pointsToHost(a) && vis(a));
  const score = a => (a.querySelector('h3,[role=heading]') ? 2 : 0) +
                     (((a.innerText || '').trim().toLowerCase().startsWith(TEXT)) ? 1 : 0);
  links.sort((x, y) => score(y) - score(x));
  let best = null;
  if (links.length) {
    const a = links[0];
    const t = a.querySelector('h3,[role=heading]') || a;
    const r = t.getBoundingClientRect();
    best = {tag: t.tagName, text: (t.innerText || '').trim().slice(0, 100),
            href: a.href, x: r.left + r.width / 2, y: r.top + r.height / 2};
  }
  return JSON.stringify({found: best, count: links.length, scrollY: window.scrollY,
    innerH: window.innerHeight, innerW: window.innerWidth,
    maxY: document.documentElement.scrollHeight - window.innerHeight});
})()""" % (json.dumps(HOST), json.dumps(TARGET))
def smooth_scroll(dist, x, y):
    # real scroll gesture, speed in CSS px/second -> smooth, not a jump
    cdp("Input.synthesizeScrollGesture", x=x, y=y, yDistance=-dist,
        speed=500, gestureSourceType="touch")
    time.sleep(1.0)
for attempt in range(MAX_SCROLLS + 1):
    info = json.loads(js(FIND_JS) or "{}")
    found = info.get("found")
    H, W = info.get("innerH", 800), info.get("innerW", 400)
    if found:
        y = found["y"]
        if 80 < y < H - 80:
            print(f"found <{found['tag']}> '{found['text']}' at ({found['x']:.0f},{found['y']:.0f}) after {attempt} scrolls", flush=True)
            cdp("Input.synthesizeTapGesture", x=found["x"], y=y)
            time.sleep(4)
            now = js("location.href") or ""
            if now == tab.get("url") or "google.com/search" in now:
                href = found.get("href")
                if href:
                    print("tap did not navigate, opening href:", href, flush=True)
                    cdp("Page.navigate", url=href)
            print("now at:", js("location.href"), flush=True)
            sys.exit(0)
        print(f"found but off-center (y={y:.0f}), scrolling to it...", flush=True)
        smooth_scroll(int(y - H / 2), int(W / 2), int(H * 0.6))
        continue
    print(f"not found yet (attempt {attempt}, scrollY={info.get('scrollY')}/{info.get('maxY')}), scrolling...", flush=True)
    if info.get("scrollY", 0) >= info.get("maxY", 0) - 5 and attempt > 3:
        print("reached the bottom of the page", flush=True)
        break
    smooth_scroll(int(H * 0.4), int(W / 2), int(H * 0.7))
print("result not found", flush=True)
sys.exit(1)
PY
}
# ---------------------------------------------------------------------------
# Browse newscredo.com: smooth random scrolls + random internal link taps
# Cycle: open page → smooth scroll → dwell 70-120s → tap link → repeat ×2
# ---------------------------------------------------------------------------
browse_newscredo() {
  python3 -m pip install -q websocket-client --break-system-packages >/dev/null 2>&1 \
    || python3 -m pip install -q websocket-client >/dev/null 2>&1 || true
  adb forward tcp:9222 localabstract:chrome_devtools_remote >/dev/null 2>&1 || true
  ARTIFACTS="$ARTIFACTS" python3 - <<'PY'
import json, os, sys, time, random, urllib.request
import websocket

ARTIFACTS = os.environ["ARTIFACTS"]
NUM_CYCLES = 2          # user asked: repeat 2 times
MIN_DWELL  = 70         # seconds per page
MAX_DWELL  = 120

def get_tabs():
    with urllib.request.urlopen("http://127.0.0.1:9222/json", timeout=5) as r:
        return json.loads(r.read().decode())

tab = None
for _ in range(40):
    try:
        pages = [t for t in get_tabs() if t.get("type") == "page"]
        # prefer the newscredo tab
        pages.sort(key=lambda t: 0 if "newscredo.com" in t.get("url", "") else 1)
        if pages:
            tab = pages[0]
            break
    except Exception:
        pass
    time.sleep(1)
if not tab:
    print("DevTools tab not reachable for browse", flush=True)
    sys.exit(2)

print("browse attached to:", tab.get("url"), flush=True)
ws = websocket.create_connection(tab["webSocketDebuggerUrl"], timeout=30, suppress_origin=True)
_id = 0

def cdp(method, **params):
    global _id
    _id += 1
    ws.send(json.dumps({"id": _id, "method": method, "params": params}))
    while True:
        msg = json.loads(ws.recv())
        if msg.get("id") == _id:
            return msg.get("result", {})

def js(expr):
    r = cdp("Runtime.evaluate", expression=expr, returnByValue=True)
    return r.get("result", {}).get("value")

def page_dims():
    return json.loads(js("""(() => JSON.stringify({
        H: window.innerHeight, W: window.innerWidth,
        scrollY: window.scrollY,
        maxY: Math.max(0, document.documentElement.scrollHeight - window.innerHeight)
    }))()""") or "{}")

def smooth_scroll_random(total_time_sec):
    """Spend ~total_time_sec doing intermittent smooth scrolls (random speed/distance)."""
    end = time.time() + total_time_sec
    scroll_count = 0
    while time.time() < end:
        d = page_dims()
        H = d.get("H", 800)
        W = d.get("W", 400)
        maxY = d.get("maxY", 0)
        curY = d.get("scrollY", 0)

        # random direction: mostly down, sometimes up a bit
        if curY >= maxY - 20 and maxY > 0:
            direction = 1   # scroll up
        elif curY < 30:
            direction = -1  # scroll down
        else:
            direction = -1 if random.random() < 0.75 else 1

        dist = random.randint(int(H * 0.25), int(H * 0.55))
        speed = random.randint(280, 650)   # px/s – human-like
        x = int(W * random.uniform(0.35, 0.65))
        y = int(H * random.uniform(0.45, 0.75))

        cdp("Input.synthesizeScrollGesture",
            x=x, y=y,
            yDistance=direction * dist,
            speed=speed,
            gestureSourceType="touch")
        scroll_count += 1

        # short pause between gestures (reading)
        pause = random.uniform(1.8, 4.5)
        remaining = end - time.time()
        if remaining <= 0:
            break
        time.sleep(min(pause, remaining))
    print(f"  performed {scroll_count} smooth scrolls over ~{total_time_sec}s", flush=True)

def find_internal_links():
    """Return list of visible internal article/category links with screen coords."""
    raw = js("""(() => {
        const host = location.hostname.replace(/^www\\./, '');
        const vis = e => {
            const r = e.getBoundingClientRect(), st = getComputedStyle(e);
            return r.width > 8 && r.height > 8 && st.visibility !== 'hidden'
                   && st.display !== 'none' && r.top < window.innerHeight
                   && r.bottom > 0 && r.left < window.innerWidth && r.right > 0;
        };
        const isInternal = a => {
            try {
                const u = new URL(a.href, location.href);
                if (u.hostname.replace(/^www\\./, '') !== host) return false;
                if (u.hash && u.pathname === location.pathname) return false; // pure anchors
                // prefer articles or category pages
                const p = u.pathname;
                if (p === '/' || p === location.pathname) return false;
                return true;
            } catch(e) { return false; }
        };
        const score = a => {
            let s = 0;
            const t = (a.innerText || '').trim().toLowerCase();
            const href = a.href.toLowerCase();
            if (a.querySelector('h1,h2,h3,h4,[role=heading]')) s += 3;
            if (/\\/category\\//.test(href)) s += 2;
            if (/\\/20[0-9]{2}\\//.test(href)) s += 2;  // dated article
            if (t.length > 20) s += 1;
            if (t.length > 40) s += 1;
            return s;
        };
        const links = [...document.querySelectorAll('a[href]')]
            .filter(a => isInternal(a) && vis(a));
        links.sort((x,y) => score(y) - score(x));
        return JSON.stringify(links.slice(0, 25).map(a => {
            const t = a.querySelector('h1,h2,h3,h4,[role=heading]') || a;
            const r = t.getBoundingClientRect();
            return {
                text: (t.innerText || a.innerText || '').trim().slice(0, 90),
                href: a.href,
                x: r.left + r.width / 2,
                y: r.top + r.height / 2,
                score: score(a)
            };
        }));
    })()""")
    try:
        return json.loads(raw or "[]")
    except Exception:
        return []

def tap_link(link):
    x, y = link["x"], link["y"]
    H = page_dims().get("H", 800)
    # if link is near edge, scroll it into comfortable center first
    if y < 100 or y > H - 100:
        mid = H / 2
        dist = int(y - mid)
        d = page_dims()
        cdp("Input.synthesizeScrollGesture",
            x=int(d.get("W", 400)/2), y=int(H*0.6),
            yDistance=-dist, speed=450, gestureSourceType="touch")
        time.sleep(1.2)
        # re-query position after scroll
        links = find_internal_links()
        for L in links:
            if L["href"] == link["href"]:
                x, y = L["x"], L["y"]
                break
    print(f"  tapping '{link['text'][:60]}' → {link['href']}", flush=True)
    cdp("Input.synthesizeTapGesture", x=x, y=y)
    time.sleep(3.5)
    # verify navigation
    now = js("location.href") or ""
    if now.rstrip("/") == link["href"].rstrip("/"):
        print(f"  navigated OK → {now}", flush=True)
        return True
    # fallback: force navigate if tap didn't work (e.g. overlay)
    print(f"  tap may have missed, forcing navigate to {link['href']}", flush=True)
    cdp("Page.navigate", url=link["href"])
    time.sleep(4)
    return True

# ---------- main browse loop ----------
visited = set()
current = js("location.href") or ""
print(f"starting browse on: {current}", flush=True)

for cycle in range(1, NUM_CYCLES + 1):
    print(f"\n===== BROWSE CYCLE {cycle}/{NUM_CYCLES} =====", flush=True)
    dwell = random.randint(MIN_DWELL, MAX_DWELL)
    print(f"  dwelling ~{dwell}s with smooth scrolls...", flush=True)
    smooth_scroll_random(dwell)

    # screenshot after dwell
    try:
        import subprocess
        name = f"0{4+cycle}-after-dwell-cycle{cycle}.png"
        subprocess.run(["adb", "exec-out", "screencap", "-p"],
                       stdout=open(os.path.join(ARTIFACTS, name), "wb"), check=False)
        print(f"  screenshot {name}", flush=True)
    except Exception as e:
        print(f"  screenshot failed: {e}", flush=True)

    # pick a random high-scoring internal link we haven't visited
    links = find_internal_links()
    candidates = [L for L in links if L["href"] not in visited and L.get("score", 0) >= 1]
    if not candidates:
        candidates = [L for L in links if L["href"] not in visited]
    if not candidates:
        print("  no more internal links found, stopping", flush=True)
        break

    # prefer higher score but still random among top ones
    top = candidates[:8]
    choice = random.choice(top)
    visited.add(choice["href"])
    tap_link(choice)

    # small settle after navigation
    time.sleep(2)
    print(f"  now at: {js('location.href')}", flush=True)

# final dwell on the last page
final_dwell = random.randint(MIN_DWELL, MAX_DWELL)
print(f"\n===== FINAL DWELL ~{final_dwell}s on last page =====", flush=True)
smooth_scroll_random(final_dwell)

try:
    import subprocess
    subprocess.run(["adb", "exec-out", "screencap", "-p"],
                   stdout=open(os.path.join(ARTIFACTS, "07-final-page.png"), "wb"), check=False)
    print("  screenshot 07-final-page.png", flush=True)
except Exception:
    pass

print("\nbrowse_newscredo finished", flush=True)
print("visited:", list(visited), flush=True)
ws.close()
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
  # 4) realistic browsing: smooth scroll + random internal taps, 2 cycles
  log "starting realistic browse on newscredo.com (2 cycles, 70-120s dwell each)"
  browse_newscredo
  screenshot "08-browse-done.png"
else
  log "could not find a link to ${RESULT_HOST} in results"
  screenshot "03-not-found.png"
fi
log "done"
ls -la "$ARTIFACTS"
