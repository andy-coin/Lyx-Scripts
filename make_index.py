#!/usr/bin/env python3
"""Generate ReaPack index.xml from git.
Install path = Scripts/<index name>/<category>/<file>; "../" may climb to the index-name folder,
so root scripts land in Scripts/Lyx Scripts/ exactly like the hand-copied folder (same action IDs). Run after committing; commit index.xml afterwards.
Version of each package = date of the last commit touching that file, so editing + committing
a script is enough to make ReaPack offer an update. No header comments needed in scripts."""
import re, subprocess, sys
from datetime import datetime, timezone
from urllib.parse import quote
from xml.sax.saxutils import escape, quoteattr

REPO = "andy-coin/Lyx-Scripts"
SKIP = re.compile(r"Test|Temp|^Script-")  # ponytail: name filter, move to a list file if it grows
# personal drafts / unfinished: stay in the local folder, not published
PRIVATE = {"Lyx_Empty.lua", "Lyx_Add number in drum map.lua", "Lyx_New.lua",
           "Lyx_Track versions alternative-move selected item(s) to comp track.lua"}

def git(*a): return subprocess.check_output(["git", *a], text=True)

files = [f for f in git("ls-files", "-z").split("\0") if f]
modes = {l.split("\t", 1)[1]: l.split()[0] for l in git("ls-files", "-s", "-z").split("\0") if l}

def pick(f):
    if modes.get(f) not in ("100644", "100755") or not f.endswith(".lua") or SKIP.search(f.rsplit("/", 1)[-1]):
        return None
    name = f.rsplit("/", 1)[-1]
    if name in PRIVATE: return None
    if f.startswith("MIDI Editor/") and f.count("/") == 1: return ("MIDI Editor", "midi_editor")
    if f.startswith("_lib/") and f.count("/") == 1 and name.startswith("_Lyx_"):
        return ("Main", None)  # library: installed, no action
    if "/" in f: return None
    if name.startswith("Lyx_"): return ("Main", "main")
    return None

# Folder tools: one package each, every published file of the folder installed beside the main
# script (same layout as the local folder). Version = last commit touching any of those files.
BUNDLES = {
    "Buss Driver": "Buss Driver/MB_Buss Driver(LYX mod) - Routing Utility GUI Manager Tool - Batch add or remove sends or receives on selected tracks.lua",
    "Theme Layout Modifier": "Theme Layout Modifier/Lyx_Theme Layout Modifier.lua",
    "neutronic_Quick Adder (Lyx mod)": "neutronic_Quick Adder (Lyx mod)/neutronic_Quick Adder 2.lua",
}
BUNDLE_SKIP = re.compile(r"(^|/)(test|_backup)/|_test\.lua$|handoff\.md$")

cats = {}
bundles = []
for folder, main_file in sorted(BUNDLES.items()):
    parts = [f for f in files if f.startswith(folder + "/") and not BUNDLE_SKIP.search(f)
             and modes.get(f) in ("100644", "100755")]
    if main_file not in parts: continue
    h, t = git("log", "-1", "--format=%H %cI", "--", *parts).split()
    ts = datetime.fromisoformat(t).astimezone(timezone.utc)
    bundles.append((main_file, sorted(parts), h, ts))
cats["Main"] = []

for f in files:
    p = pick(f)
    if not p: continue
    cat, main = p
    h, t = git("log", "-1", "--format=%H %cI", "--", f).split()
    ts = datetime.fromisoformat(t).astimezone(timezone.utc)
    cats.setdefault(cat, []).append((f, main, h, ts))

out = ['<?xml version="1.0" encoding="utf-8"?>', '<index version="1" name="Lyx Scripts">']
for cat in sorted(cats):
    out.append(f"  <category name={quoteattr(cat)}>")
    for f, main, h, ts in sorted(cats[cat]):
        name = f.rsplit("/", 1)[-1]
        url = f"https://github.com/{REPO}/raw/{h}/{quote(f)}"
        m = f" main={quoteattr(main)}" if main else ""
        if cat == "Main": m += f" file={quoteattr('../' + f)}"  # Scripts/Lyx Scripts/<name> or _lib/<name>
        out.append(f"    <reapack name={quoteattr(name)} type=\"script\" desc={quoteattr(name[:-4])}>")
        out.append(f"      <version name=\"{ts:%Y.%m.%d.%H%M}\" author=\"Lyx\" time=\"{ts:%Y-%m-%dT%H:%M:%SZ}\">")
        out.append(f"        <source{m}>{escape(url)}</source>")
        out.append("      </version>")
        out.append("    </reapack>")
    if cat == "Main":
        for main_file, parts, h, ts in bundles:
            name = main_file.rsplit("/", 1)[-1]
            out.append(f"    <reapack name={quoteattr(name)} type=\"script\" desc={quoteattr(name[:-4])}>")
            out.append(f"      <version name=\"{ts:%Y.%m.%d.%H%M}\" author=\"Lyx\" time=\"{ts:%Y-%m-%dT%H:%M:%SZ}\">")
            for f in parts:
                url = f"https://github.com/{REPO}/raw/{h}/{quote(f)}"
                m = ' main="main"' if f == main_file else ""
                out.append(f"        <source{m} file={quoteattr('../' + f)}>{escape(url)}</source>")
            out.append("      </version>")
            out.append("    </reapack>")
    out.append("  </category>")
out.append("</index>")
open("index.xml", "w", encoding="utf-8").write("\n".join(out) + "\n")
print({c: len(v) for c, v in cats.items()}, "bundles:", [b[0].split("/")[0] for b in bundles], file=sys.stderr)
