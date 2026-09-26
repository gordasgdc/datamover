import re, glob, sys
src = "mac-native/Sources/DataMoverMac/"
tables = open(src + "Localization.swift").read() + open(src + "LocalizationExtra.swift").read()
entries = re.findall(r'^\s*"([^"]+)":\s*\[(.*?)\],?\s*$', tables, re.M | re.S)
defined = {k for k, _ in entries}
bad = []
for k, body in entries:
    langs = dict(re.findall(r'\.(ro|en|es):\s*"((?:[^"\\]|\\.)*)"', body))
    if set(langs) != {"ro", "en", "es"}: bad.append(f"{k}: lipsește o limbă")
    specs = {l: sorted(re.findall(r'%[@d]', v)) for l, v in langs.items()}
    if len({tuple(s) for s in specs.values()}) > 1: bad.append(f"{k}: specificatori diferiți")
used = set()
for f in glob.glob(src + "**/*.swift", recursive=True):
    used |= set(re.findall(r'L\.t\("([^"\\]+)"\)', open(f).read()))
missing = sorted(u for u in used - defined if "\\(" not in u)
bad += [f"{m}: folosită, nedefinită" for m in missing]
for b in bad: print("    " + b)
sys.exit(1 if bad else 0)
