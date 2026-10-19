#!/usr/bin/env python3
"""Generate ReaPack index.xml from git. Run after committing; commit index.xml afterwards.
Version of each package = date of the last commit touching that file, so editing + committing
a script is enough to make ReaPack offer an update. No header comments needed in scripts."""
import re, subprocess, sys
from datetime import datetime, timezone
from urllib.parse import quote
from xml.sax.saxutils import escape, quoteattr

REPO = "andy-coin/Lyx-Reascripts"
SKIP = re.compile(r"Test|Temp|^Script-")  # ponytail: name filter, move to a list file if it grows

def git(*a): return subprocess.check_output(["git", *a], text=True)

files = [f for f in git("ls-files", "-z").split("\0") if f]
modes = {l.split("\t", 1)[1]: l.split()[0] for l in git("ls-files", "-s", "-z").split("\0") if l}

def pick(f):
    if modes.get(f) not in ("100644", "100755") or not f.endswith(".lua") or SKIP.search(f.rsplit("/", 1)[-1]):
        return None
    name = f.rsplit("/", 1)[-1]
    if f.startswith("MIDI Editor/") and f.count("/") == 1: return ("Lyx Scripts/MIDI Editor", "midi_editor")
    if "/" in f: return None
    if name.startswith("Lyx_"): return ("Lyx Scripts", "main")
    if name.startswith("_Lyx_"): return ("Lyx Scripts", None)  # library: installed, no action
    return None

cats = {}
for f in files:
    p = pick(f)
    if not p: continue
    cat, main = p
    h, t = git("log", "-1", "--format=%H %cI", "--", f).split()
    ts = datetime.fromisoformat(t).astimezone(timezone.utc)
    cats.setdefault(cat, []).append((f, main, h, ts))

out = ['<?xml version="1.0" encoding="utf-8"?>', '<index version="1" name="Lyx-Reascripts">']
for cat in sorted(cats):
    out.append(f"  <category name={quoteattr(cat)}>")
    for f, main, h, ts in sorted(cats[cat]):
        name = f.rsplit("/", 1)[-1]
        url = f"https://github.com/{REPO}/raw/{h}/{quote(f)}"
        m = f" main={quoteattr(main)}" if main else ""
        out.append(f"    <reapack name={quoteattr(name)} type=\"script\" desc={quoteattr(name[:-4])}>")
        out.append(f"      <version name=\"{ts:%Y.%m.%d.%H%M}\" author=\"Lyx\" time=\"{ts:%Y-%m-%dT%H:%M:%SZ}\">")
        out.append(f"        <source{m}>{escape(url)}</source>")
        out.append("      </version>")
        out.append("    </reapack>")
    out.append("  </category>")
out.append("</index>")
open("index.xml", "w", encoding="utf-8").write("\n".join(out) + "\n")
print({c: len(v) for c, v in cats.items()}, file=sys.stderr)
