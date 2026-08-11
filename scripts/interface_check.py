#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
RTL = ROOT / 'rtl'

def strip_comments(s):
    s = re.sub(r'/\*.*?\*/', '', s, flags=re.S)
    return re.sub(r'//.*', '', s)

mods = {}
for p in RTL.glob('*.v'):
    s = strip_comments(p.read_text())
    m = re.search(r'\bmodule\s+(\w+)\s*\((.*?)\);', s, flags=re.S)
    if not m:
        print('FAIL: cannot parse module header:', p)
        sys.exit(1)
    ports = []
    for chunk in m.group(2).split(','):
        mm = re.search(r'([A-Za-z_]\w*)\s*$', chunk.strip())
        if mm:
            ports.append(mm.group(1))
    mods[m.group(1)] = set(ports)

s = strip_comments((RTL / 'photonic_ctrl_top.v').read_text())
errors = []
for mod, inst, body in re.findall(r'\b(\w+)\s+(\w+)\s*\((.*?)\);', s, flags=re.S):
    if mod not in mods or mod == 'photonic_ctrl_top':
        continue
    conns = set(re.findall(r'\.(\w+)\s*\(', body))
    missing = mods[mod] - conns
    extra = conns - mods[mod]
    if missing or extra:
        errors.append((inst, mod, missing, extra))

if errors:
    for e in errors:
        print('FAIL:', e)
    sys.exit(1)
print('INTERFACE CHECK PASS: all top-level named instance connections match module ports.')
