#!/usr/bin/env bash
# web-preflight.sh — verificarea paginii DataMover (docs/), idempotentă, read-only.
#   scripts/web-preflight.sh [docs_dir] [--online]
# Verifică: HTML de bază, chei RO/EN/ES complete, active locale existente și cu
# dimensiunile declarate, linkuri interne, canonical/OG, lipsa căilor locale și a
# secretelor; cu --online: HTTP 200 pentru downloaduri, ghiduri și linkurile legale.
set -uo pipefail
DOCS="docs"; ONLINE=0
for a in "$@"; do case $a in --online) ONLINE=1;; *) DOCS="$a";; esac; done
python3 - "$DOCS" "$ONLINE" <<'PY'
import sys, re, os, json, html.parser, subprocess, urllib.request
docs, online = sys.argv[1], sys.argv[2] == "1"
page = os.path.join(docs, "index.html"); src = open(page, encoding="utf-8").read()
fails = []
def ok(c, m):
    print(("  ✓ " if c else "  ✗ ") + m)
    if not c: fails.append(m)

class P(html.parser.HTMLParser):
    VOID = {"meta","link","img","br","input","source","use","path","rect","circle","hr","stop"}
    def __init__(s): super().__init__(); s.stack=[]; s.err=[]; s.ids=[]; s.refs=[]
    def handle_starttag(s, t, a):
        d = dict(a)
        if "id" in d: s.ids.append(d["id"])
        for k in ("src","href"):
            if d.get(k): s.refs.append((t, k, d[k], d))
        if t not in s.VOID: s.stack.append(t)
    def handle_startendtag(s, t, a): s.handle_starttag(t, a); (s.stack.pop() if s.stack and s.stack[-1]==t and t not in s.VOID else None)
    def handle_endtag(s, t):
        if t in s.VOID: return
        if s.stack and s.stack[-1] == t: s.stack.pop()
        else: s.err.append(f"</{t}> neașteptat (deschis: {s.stack[-3:]})")
p = P(); p.feed(src)
ok(not p.err and not p.stack, f"HTML echilibrat {p.err[:2] or ''}{p.stack[-3:] if p.stack else ''}")
ok(len(p.ids) == len(set(p.ids)), "id-uri unice")
ok('<html lang="ro">' in src and 'name="viewport"' in src, "lang + viewport")
ok('<link rel="canonical" href="https://gordas.dev/datamover/">' in src, "canonical https://gordas.dev/datamover/")
for k in ("og:title","og:description","og:image","twitter:card","description"):
    ok(re.search(r'(property|name)="%s" content="[^"]+"' % k, src) is not None, f"meta {k}")
try:
    ld = json.loads(re.search(r'<script type="application/ld\+json">(.*?)</script>', src, re.S).group(1))
    ok(ld.get("@type") == "SoftwareApplication" and "offers" not in ld and "aggregateRating" not in ld, "JSON-LD SoftwareApplication fără preț/rating")
except Exception as e: ok(False, f"JSON-LD valid ({e})")
ok("gordasgdc.github.io" in src and "location.search + location.hash" in src, "redirecție github.io păstrează query/hash")

# chei i18n
keys = set(re.findall(r'data-i18n(?:-html|-alt|-aria)?="([^"]+)"', src)) | {"doc.title","doc.desc"}
for lang in ("en","es"):
    m = re.search(r'\n\s*%s: \{(.*?)\n\s*\}' % lang, src, re.S)
    got = set(re.findall(r'"([a-z0-9.]+)":', m.group(1))) if m else set()
    miss = sorted(keys - got); extra = sorted(got - keys)
    ok(not miss, f"{lang.upper()}: toate cele {len(keys)} chei traduse {miss[:5] if miss else ''}")
    ok(not extra, f"{lang.upper()}: fără chei orfane {extra[:5] if extra else ''}")

# active locale + dimensiuni
def dims(f):
    o = subprocess.run(["sips","-g","pixelWidth","-g","pixelHeight",f],capture_output=True,text=True).stdout
    w = re.search(r"pixelWidth: ([\d.]+)", o); h = re.search(r"pixelHeight: ([\d.]+)", o)
    return (int(float(w.group(1))), int(float(h.group(1)))) if w and h else None
urls = set()
for t, k, v, d in p.refs:
    if v.startswith(("http://","https://")): urls.add(v); continue
    if v.startswith(("#","mailto:")):
        if v.startswith("#") and len(v) > 1 and t == "a": ok(v[1:] in p.ids, f"ancoră internă {v}")
        continue
    f = os.path.join(docs, v.split("?")[0])
    ok(os.path.isfile(f), f"activ local {v}")
    if t == "img" and os.path.isfile(f) and d.get("width"):
        real = dims(f); decl = (int(d["width"]), int(d["height"]))
        ok(real == decl or (f.endswith(".svg")), f"dimensiuni {v} {decl} = {real}")
    if t == "img": ok(bool(d.get("alt") is not None), f"alt pe {v}")
for f in re.findall(r'content="https://gordas.dev/datamover/([^"]+\.(?:jpg|png|webp))"', src):
    ok(os.path.isfile(os.path.join(docs, f)), f"imagine OG locală {f}")
big = [f for f in os.listdir(os.path.join(docs,"img","2.16")) if os.path.getsize(os.path.join(docs,"img","2.16",f)) > 300_000]
ok(not big, f"imagini ≤ 300 KB {big}")

# conținut interzis
ok(not re.search(r"/Users/|file://|localhost|127\.0\.0\.1|claude|scratchpad", src, re.I), "fără căi locale / urme de unelte")
ok(not re.search(r"(ghp_|github_pat_|sk-[A-Za-z0-9]{20}|AKIA[0-9A-Z]{16}|BEGIN [A-Z ]*PRIVATE KEY)", src), "fără secrete")
ok(not re.search(r"\b(preț|pret|cumpără|cumpara|price|buy|precio|comprar)\b", src, re.I), "fără preț/cumpără (Regula 3)")
ok('prefers-reduced-motion' in src and ':focus-visible' in src, "reduced-motion + focus vizibil")
ok("https://gordas.dev/termeni" in src and "https://gordas.dev/confidentialitate" in src and "AS IS" in src, "footer legal (Regula 19)")

if online:
    urls |= {"https://gordas.dev/datamover/guides/DataMover_Ghid_RO.pdf"} if os.path.isfile(os.path.join(docs,"guides/DataMover_Ghid_RO.pdf")) else set()
    for u in sorted(urls):
        try:
            code = subprocess.run(["curl","-sIL","-o","/dev/null","-w","%{http_code}","--max-time","30",u],capture_output=True,text=True).stdout
        except Exception as e: code = str(e)
        ok(code == "200", f"HTTP {code} {u}")
print("WEB PREFLIGHT: " + ("OK" if not fails else f"{len(fails)} problemă(e)"))
sys.exit(1 if fails else 0)
PY
