#!/usr/bin/env python3
"""AzerothVeil — localisation check (run by scripts/check.sh).

Every L["..."] used in the addon's code (outside comments and Locales/) must have an entry in each
translation file listed below. Keys are compared as written in the source (escapes included).
Exit 1 and list them if any is missing; translations no code uses are only reported.
"""
import os
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "addon"
TRANSLATIONS = ["Locales/frFR.lua"]          # (English is the keys themselves: enUS needs none)
KEY = re.compile(r'L\["((?:[^"\\]|\\.)*)"\]')
ENTRY = re.compile(r'\s*L\["((?:[^"\\]|\\.)*)"\]\s*=')


def code_part(line):
    """The line without its -- comment (a -- inside a string is kept)."""
    in_string, i = False, 0
    while i < len(line):
        c = line[i]
        if c == '"':
            in_string = not in_string
        elif c == "\\" and in_string:
            i += 2
            continue
        elif not in_string and line.startswith("--", i):
            return line[:i]
        i += 1
    return line


used = {}
for folder, _, files in os.walk(ROOT):
    if os.path.relpath(folder, ROOT).startswith("Locales"):
        continue
    for name in sorted(files):
        if not name.endswith(".lua"):
            continue
        path = os.path.join(folder, name)
        with open(path, encoding="utf-8") as f:
            for n, line in enumerate(f, 1):
                for m in KEY.finditer(code_part(line)):
                    used.setdefault(m.group(1), f"{os.path.relpath(path, ROOT)}:{n}")

failed = False
for loc in TRANSLATIONS:
    with open(os.path.join(ROOT, loc), encoding="utf-8") as f:
        have = {m.group(1) for m in (ENTRY.match(l) for l in f) if m}
    missing = [k for k in used if k not in have]
    unused = [k for k in have if k not in used]
    for k in missing:
        print(f"  missing in {loc}: {used[k]}  {k}")
    if unused:
        print(f"  ({loc}: {len(unused)} translation(s) no code uses)")
    failed = failed or bool(missing)
print(f"  {len(used)} texts, translated in {', '.join(TRANSLATIONS)}" if not failed else "  untranslated texts above")
sys.exit(1 if failed else 0)
