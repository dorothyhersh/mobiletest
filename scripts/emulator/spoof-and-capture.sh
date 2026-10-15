#!/usr/bin/env bash
# Real organic mobile traffic simulator for gardengar.com
# - Opens Google search
# - Performs a real touch tap on the organic result (keeps Google referrer)
# - Browses 2-5 internal pages with human-like scroll + dwell
# - No forced country / timezone / locale (uses real runner IP)
# - Screenshots saved to artifacts/
set -euo pipefail

ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
ARTIFACTS="${ROOT}/artifacts"
mkdir -p "$ARTIFACTS"

CHROME_PKG="com.android.chrome"
TARGET_URL="https://www.google.com"
SEARCH_URL="https://www.google.com/search?q=gardengar.com"
RESULT_HOST="gardengar.com"
RESULT_TEXT="gardengar"
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
  log "no root — identity spoofing limited"
  return 1
}

# Lightweight Samsung identity (model only). No country / timezone / locale forcing.
samsung_prop_file() {
  cat <<'PROP'
ro.product.brand=samsung
ro.product.manufacturer=samsung
ro.product.model=SM-S928B
ro.product.name=e3sxxx
ro.product.device=e3s
ro.product.marketname=Galaxy S24 Ultra
ro.build.fingerprint=samsung/e3sxxx/e3s:14/UP1A.231005.007/S928BXXS3AXKF:user/release-keys
ro.build.type=user
ro.build.tags=release-keys
ro.build.version.release=14
ro.build.version.sdk=34
ro.sf.lcd_density=420
PROP
}

write_samsung_identity() {
  local tmp
  tmp="$(mktemp)"
  samsung_prop_file > "$tmp"
  adb push "$tmp" /data/local.prop
  adb_sh chmod 644 /data/local.prop
  rm -f "$tmp"
  log "pushed /data/local.prop (model only, no geo)"
  adb_sh ls -l /data/local.prop || true
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
      ro.build.fingerprint ro.build.version.release ro.build.version.sdk \
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
  adb push "$tmp" /data/local/tmp/chrome-command-line >/dev/null
  adb_sh chmod 644 /data/local/tmp/chrome-command-line || true
  if [[ "$HAVE_ROOT" == "1" ]]; then
    adb push "$tmp" /data/local/chrome-command-line >/dev/null || true
    adb_sh chmod 644 /data/local/chrome-command-line || true
  fi
  rm -f "$tmp"
  adb shell pm grant "$CHROME_PKG" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
  adb shell am force-stop "$CHROME_PKG" >/dev/null 2>&1 || true
  log "Chrome first-run flags written for ${CHROME_PKG}"
}

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
  log "Chrome is not installed"
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

# ---------------------------------------------------------------------------
# REAL organic click from Google SERP
# ---------------------------------------------------------------------------
tap_search_result() {
  python3 -m pip install -q websocket-client --break-system-packages >/dev/null 2>&1 \
    || python3 -m pip install -q websocket-client >/dev/null 2>&1 || true
  adb forward tcp:9222 localabstract:chrome_devtools_remote >/dev/null 2>&1 || true

  RESULT_HOST="$RESULT_HOST" RESULT_TEXT="$RESULT_TEXT" ARTIFACTS="$ARTIFACTS" MAX_SCROLLS="${MAX_SCROLLS:-50}" python3 - <<'PY'
import json, os, sys, time, urllib.request
import websocket

TARGET = os.environ["RESULT_TEXT"].strip().lower()
HOST = os.environ["RESULT_HOST"].strip().lower()
ARTIFACTS = os.environ["ARTIFACTS"]
MAX_SCROLLS = int(os.environ["MAX_SCROLLS"])

def get_tabs():
    with urllib.request.urlopen("http://127.0.0.1:9222/json", timeout=8) as r:
        return json.loads(r.read().decode())

tab = None
for _ in range(40):
    try:
        pages = [t for t in get_tabs() if t.get("type") == "page"]
        pages.sort(key=lambda t: 0 if "google." in t.get("url", "") else 1)
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

ws = websocket.create_connection(
    tab["webSocketDebuggerUrl"],
    timeout=90,
    suppress_origin=True,
    ping_interval=15,
    ping_timeout=10
)

_id = 0
def cdp(method, **params):
    global _id
    _id += 1
    ws.send(json.dumps({"id": _id, "method": method, "params": params}))
    deadline = time.time() + 25
    while time.time() < deadline:
        try:
            msg = json.loads(ws.recv())
            if msg.get("id") == _id:
                return msg.get("result", {})
        except Exception as e:
            print(f"cdp recv error: {e}", flush=True)
            time.sleep(0.5)
    raise TimeoutError(f"CDP timeout for {method}")

def js(expr):
    r = cdp("Runtime.evaluate", expression=expr, returnByValue=True)
    return r.get("result", {}).get("value")

# Enable necessary domains
cdp("Page.enable")
cdp("Runtime.enable")
cdp("Network.enable")

# Debug dump
DEBUG_JS = """(() => JSON.stringify({
  url: location.href, title: document.title,
  headings: [...document.querySelectorAll('h3,[role=heading]')]
      .map(e => (e.innerText||'').trim()).filter(Boolean).slice(0,30),
  body: (document.body.innerText||'').slice(0,1200)
}))()"""
dbg = js(DEBUG_JS)
with open(os.path.join(ARTIFACTS, "page-debug.json"), "w") as f:
    f.write(dbg or "{}")
d = json.loads(dbg or "{}")
print("page title:", d.get("title"), flush=True)
print("headings:", d.get("headings"), flush=True)

body = (d.get("body") or "").lower()
if "unusual traffic" in body or "not a robot" in body or "captcha" in body:
    print("WARNING: Google bot check / CAPTCHA detected", flush=True)

FIND_JS = """(() => {
  const HOST = %s, TEXT = %s;
  const vis = e => {
    const r = e.getBoundingClientRect(), st = getComputedStyle(e);
    return r.width > 0 && r.height > 0 && st.visibility !== 'hidden' && st.display !== 'none';
  };
  const pointsToHost = a => {
    try {
      const raw = (a.href || '');
      const h = decodeURIComponent(raw).toLowerCase();
      const u = new URL(raw, location.href);
      if (u.hostname === HOST || u.hostname === 'www.' + HOST || u.hostname === 'm.' + HOST) return true;
      if (h.includes('://' + HOST) || h.includes('://www.' + HOST) || h.includes('://m.' + HOST)) return true;
      if (h.includes('%%2f%%2f' + HOST) || h.includes('%%2f%%2fwww.' + HOST)) return true;
      if (h.includes('/url?q=') && h.includes(HOST)) return true;
      if (h.includes('/goto?url=') && h.includes(HOST)) return true;
      const cite = (a.getAttribute('data-href') || a.getAttribute('ping') || '').toLowerCase();
      if (cite.includes(HOST)) return true;
      const txt = ((a.innerText || '') + ' ' + (a.textContent || '')).toLowerCase();
      if (txt.includes(HOST) || txt.includes(TEXT)) return true;
      let p = a.parentElement;
      for (let i = 0; i < 6 && p; i++, p = p.parentElement) {
        const citeEl = p.querySelector('cite, .TbwUpd, .qzEoUe, span[role="text"]');
        if (citeEl && (citeEl.innerText || '').toLowerCase().includes(HOST)) return true;
      }
      return false;
    } catch (e) { return false; }
  };
  const links = [...document.querySelectorAll('a[href]')].filter(a => pointsToHost(a) && vis(a));
  const score = a => {
    let s = 0;
    const t = (a.innerText || '').trim().toLowerCase();
    const href = (a.href || '').toLowerCase();
    if (a.querySelector('h3,[role=heading]')) s += 5;
    if (t.includes(TEXT) || t.includes(HOST)) s += 3;
    if (href.includes(HOST) && !href.includes('google.com')) s += 4;
    if (href.includes('/url?q=') || href.includes('/goto?url=')) s += 3;
    try {
      const u = new URL(a.href);
      if (u.pathname === '/' || u.pathname === '') s += 2;
    } catch(e) {}
    return s;
  };
  links.sort((x, y) => score(y) - score(x));
  let best = null;
  if (links.length) {
    const a = links[0];
    const t = a.querySelector('h3,[role=heading]') || a;
    const r = t.getBoundingClientRect();
    best = {
      tag: t.tagName,
      text: (t.innerText || a.innerText || '').trim().slice(0, 120),
      href: a.href,
      x: r.left + r.width / 2,
      y: r.top + r.height / 2,
      score: score(a)
    };
  }
  return JSON.stringify({
    found: best, count: links.length,
    scrollY: window.scrollY,
    innerH: window.innerHeight, innerW: window.innerWidth,
    maxY: document.documentElement.scrollHeight - window.innerHeight
  });
})()""" % (json.dumps(HOST), json.dumps(TARGET))

def smooth_scroll(dist, x, y):
    cdp("Input.synthesizeScrollGesture",
        x=x, y=y, yDistance=-dist, speed=480, gestureSourceType="touch")
    time.sleep(1.1)

def is_on_target():
    url = (js("location.href") or "").lower()
    return HOST in url and "google." not in url and "chrome-error" not in url

# Main search loop
for attempt in range(MAX_SCROLLS + 1):
    info = json.loads(js(FIND_JS) or "{}")
    found = info.get("found")
    H = info.get("innerH", 800)
    W = info.get("innerW", 400)

    if found:
        y = found["y"]
        if 80 < y < H - 80:
            print(f"found <{found['tag']}> '{found['text']}' score={found.get('score')} "
                  f"at ({found['x']:.0f},{found['y']:.0f}) after {attempt} scrolls", flush=True)
            print(f"  href={found['href'][:100]}", flush=True)

            # Real human-like tap (this is what creates organic attribution)
            cdp("Input.synthesizeTapGesture", x=found["x"], y=y)
            print("real tap performed – waiting for Google redirect...", flush=True)

            # Wait for navigation (Google click-tracking → site)
            for wait in range(18):
                time.sleep(1.2)
                now = (js("location.href") or "").lower()
                print(f"  [{wait+1}] now at: {now[:90]}", flush=True)

                if "chrome-error" in now:
                    print("chrome-error detected, retrying tap once...", flush=True)
                    time.sleep(2)
                    cdp("Input.synthesizeTapGesture", x=found["x"], y=y)
                    time.sleep(4)
                    continue

                if is_on_target():
                    print("SUCCESS: landed on target via real organic click", flush=True)
                    ws.close()
                    sys.exit(0)

                # Still on Google redirect page is OK – keep waiting
                if "google.com/url" in now or "google.com/goto" in now or "/url?q=" in now:
                    continue

            # Final check
            if is_on_target():
                print("SUCCESS after extended wait", flush=True)
                ws.close()
                sys.exit(0)

            print("tap did not result in landing on target after retries", flush=True)
            # Do NOT hard-navigate – that would create direct traffic
            ws.close()
            sys.exit(1)

        # Found but off-screen → scroll it into view
        print(f"found but off-center (y={y:.0f}), scrolling into view...", flush=True)
        smooth_scroll(int(y - H / 2), int(W / 2), int(H * 0.6))
        continue

    print(f"not found yet (attempt {attempt}, scrollY={info.get('scrollY')}/{info.get('maxY')})", flush=True)
    if info.get("scrollY", 0) >= info.get("maxY", 0) - 10 and attempt > 4:
        print("reached bottom of SERP", flush=True)
        break
    smooth_scroll(int(H * 0.38), int(W / 2), int(H * 0.65))

print("organic result not found or tap failed – refusing to hard-navigate (would be direct traffic)", flush=True)
ws.close()
sys.exit(1)
PY
}

# ---------------------------------------------------------------------------
# Realistic multi-page engagement (2–5 pages)
# ---------------------------------------------------------------------------
browse_site() {
  python3 -m pip install -q websocket-client --break-system-packages >/dev/null 2>&1 \
    || python3 -m pip install -q websocket-client >/dev/null 2>&1 || true
  adb forward tcp:9222 localabstract:chrome_devtools_remote >/dev/null 2>&1 || true

  ARTIFACTS="$ARTIFACTS" RESULT_HOST="$RESULT_HOST" python3 - <<'PY'
import json, os, sys, time, random, urllib.request
import websocket

ARTIFACTS = os.environ["ARTIFACTS"]
HOST = os.environ["RESULT_HOST"].strip().lower()

# Random number of pages: 2–5 (including the landing page)
NUM_PAGES = random.randint(2, 5)
MIN_DWELL = 28
MAX_DWELL = 75

def get_tabs():
    with urllib.request.urlopen("http://127.0.0.1:9222/json", timeout=8) as r:
        return json.loads(r.read().decode())

tab = None
for _ in range(40):
    try:
        pages = [t for t in get_tabs() if t.get("type") == "page"]
        pages.sort(key=lambda t: 0 if HOST in t.get("url", "").lower() else 1)
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

ws = websocket.create_connection(
    tab["webSocketDebuggerUrl"],
    timeout=90,
    suppress_origin=True,
    ping_interval=15,
    ping_timeout=10
)

_id = 0
def cdp(method, **params):
    global _id, ws
    for attempt in range(3):
        try:
            _id += 1
            ws.send(json.dumps({"id": _id, "method": method, "params": params}))
            deadline = time.time() + 20
            while time.time() < deadline:
                msg = json.loads(ws.recv())
                if msg.get("id") == _id:
                    return msg.get("result", {})
        except Exception as e:
            print(f"CDP error (attempt {attempt+1}): {e}", flush=True)
            try:
                ws.close()
            except: pass
            time.sleep(1.5)
            # reconnect
            tabs = get_tabs()
            pages = [t for t in tabs if t.get("type") == "page"]
            if not pages:
                raise
            tab = pages[0]
            ws = websocket.create_connection(
                tab["webSocketDebuggerUrl"], timeout=90,
                suppress_origin=True, ping_interval=15, ping_timeout=10
            )
    raise RuntimeError("CDP failed after retries")

def js(expr):
    r = cdp("Runtime.evaluate", expression=expr, returnByValue=True)
    return r.get("result", {}).get("value")

cdp("Page.enable")
cdp("Runtime.enable")

def page_dims():
    return json.loads(js("""(() => JSON.stringify({
        H: window.innerHeight, W: window.innerWidth,
        scrollY: window.scrollY,
        maxY: Math.max(0, document.documentElement.scrollHeight - window.innerHeight)
    }))()""") or "{}")

def smooth_scroll_random(total_time_sec):
    end = time.time() + total_time_sec
    scroll_count = 0
    while time.time() < end:
        d = page_dims()
        H = d.get("H", 800)
        W = d.get("W", 400)
        maxY = d.get("maxY", 0)
        curY = d.get("scrollY", 0)

        if curY >= maxY - 30 and maxY > 0:
            direction = 1
        elif curY < 40:
            direction = -1
        else:
            direction = -1 if random.random() < 0.78 else 1

        dist = random.randint(int(H * 0.22), int(H * 0.52))
        speed = random.randint(260, 620)
        x = int(W * random.uniform(0.32, 0.68))
        y = int(H * random.uniform(0.42, 0.72))

        cdp("Input.synthesizeScrollGesture",
            x=x, y=y, yDistance=direction * dist,
            speed=speed, gestureSourceType="touch")
        scroll_count += 1

        pause = random.uniform(1.6, 4.2)
        remaining = end - time.time()
        if remaining <= 0:
            break
        time.sleep(min(pause, remaining))
    print(f"  performed {scroll_count} smooth scrolls over ~{total_time_sec}s", flush=True)

def find_internal_links():
    raw = js("""(() => {
        const host = location.hostname.replace(/^www\\./, '').replace(/^m\\./, '');
        const vis = e => {
            const r = e.getBoundingClientRect(), st = getComputedStyle(e);
            return r.width > 10 && r.height > 10 && st.visibility !== 'hidden'
                   && st.display !== 'none' && r.top < window.innerHeight
                   && r.bottom > 0;
        };
        const isInternal = a => {
            try {
                const u = new URL(a.href, location.href);
                const h = u.hostname.replace(/^www\\./, '').replace(/^m\\./, '');
                if (h !== host) return false;
                if (u.hash && u.pathname === location.pathname) return false;
                if (u.pathname === '/' || u.pathname === location.pathname) return false;
                return true;
            } catch(e) { return false; }
        };
        const score = a => {
            let s = 0;
            const t = (a.innerText || '').trim().toLowerCase();
            const href = a.href.toLowerCase();
            if (a.querySelector('h1,h2,h3,h4,[role=heading]')) s += 4;
            if (/\\/category\\//.test(href) || /\\/tag\\//.test(href)) s += 2;
            if (/\\/20[0-9]{2}\\//.test(href)) s += 2;
            if (t.length > 15) s += 1;
            if (t.length > 35) s += 1;
            return s;
        };
        const links = [...document.querySelectorAll('a[href]')]
            .filter(a => isInternal(a) && vis(a));
        links.sort((x,y) => score(y) - score(x));
        return JSON.stringify(links.slice(0, 20).map(a => {
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
    if y < 90 or y > H - 90:
        mid = H / 2
        dist = int(y - mid)
        d = page_dims()
        cdp("Input.synthesizeScrollGesture",
            x=int(d.get("W", 400)/2), y=int(H*0.55),
            yDistance=-dist, speed=420, gestureSourceType="touch")
        time.sleep(1.3)
        links = find_internal_links()
        for L in links:
            if L["href"] == link["href"]:
                x, y = L["x"], L["y"]
                break
    print(f"  tapping '{link['text'][:55]}' → {link['href']}", flush=True)
    cdp("Input.synthesizeTapGesture", x=x, y=y)
    time.sleep(3.8)
    now = js("location.href") or ""
    if now.rstrip("/") == link["href"].rstrip("/"):
        print(f"  navigated OK → {now}", flush=True)
        return True
    # Soft fallback only for internal links (already on-site)
    print(f"  tap may have missed, soft navigate to {link['href']}", flush=True)
    cdp("Page.navigate", url=link["href"])
    time.sleep(3.5)
    return True

# ---------- main engagement loop ----------
visited = set()
current = js("location.href") or ""
print(f"starting engagement browse on: {current}", flush=True)
print(f"will visit {NUM_PAGES} pages total", flush=True)

for page_num in range(1, NUM_PAGES + 1):
    print(f"\n===== PAGE {page_num}/{NUM_PAGES} =====", flush=True)
    dwell = random.randint(MIN_DWELL, MAX_DWELL)
    print(f"  dwelling ~{dwell}s with smooth scrolls...", flush=True)
    smooth_scroll_random(dwell)

    # Screenshot
    try:
        import subprocess
        name = f"0{4 + page_num}-page{page_num}.png"
        subprocess.run(["adb", "exec-out", "screencap", "-p"],
                       stdout=open(os.path.join(ARTIFACTS, name), "wb"), check=False)
        print(f"  screenshot {name}", flush=True)
    except Exception as e:
        print(f"  screenshot failed: {e}", flush=True)

    if page_num >= NUM_PAGES:
        break

    # Pick next internal page
    links = find_internal_links()
    candidates = [L for L in links if L["href"] not in visited and L.get("score", 0) >= 1]
    if not candidates:
        candidates = [L for L in links if L["href"] not in visited]
    if not candidates:
        print("  no more internal links, stopping early", flush=True)
        break

    top = candidates[:7]
    choice = random.choice(top)
    visited.add(choice["href"])
    tap_link(choice)
    time.sleep(2)
    print(f"  now at: {js('location.href')}", flush=True)

# Final short dwell
final_dwell = random.randint(18, 40)
print(f"\n===== FINAL DWELL ~{final_dwell}s =====", flush=True)
smooth_scroll_random(final_dwell)

try:
    import subprocess
    subprocess.run(["adb", "exec-out", "screencap", "-p"],
                   stdout=open(os.path.join(ARTIFACTS, "09-final.png"), "wb"), check=False)
    print("  screenshot 09-final.png", flush=True)
except Exception:
    pass

print("\nbrowse finished")
print("visited pages:", list(visited), flush=True)
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

# ===================== MAIN =====================
log "waiting for first boot"
wait_for_boot

if ensure_root; then
  HAVE_ROOT=1
fi

settle_device
dump_identity

if [[ "$HAVE_ROOT" == "1" ]]; then
  write_samsung_identity
  log "rebooting so identity props load"
  adb reboot
  wait_for_boot
  if ensure_root; then
    HAVE_ROOT=1
  else
    HAVE_ROOT=0
  fi
  settle_device
  dump_identity
else
  log "skipping /data/local.prop (no root)"
fi

resolve_chrome
skip_chrome_welcome

# 1) Google homepage
open_url "$TARGET_URL"
wait_for_page 5
dismiss_chrome_sheets
screenshot "01-google-home.png"

# 2) Search results
open_url "$SEARCH_URL"
wait_for_page 7
dismiss_chrome_sheets
screenshot "02-search-results.png"

# 3) REAL organic click (no hard-navigate fallback)
log "attempting real organic click from Google SERP..."
if tap_search_result; then
  wait_for_page 8
  screenshot "03-organic-landed.png"
  sleep 4
  screenshot "04-organic-settled.png"

  log "starting multi-page engagement (2-5 pages)"
  browse_site
  screenshot "10-engagement-done.png"
else
  log "FAILED to perform real organic click – no direct navigation used"
  screenshot "03-organic-failed.png"
  exit 1
fi

log "done – check artifacts/ for screenshots and identity.txt"
ls -la "$ARTIFACTS"
