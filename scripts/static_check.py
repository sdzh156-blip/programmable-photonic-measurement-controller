#!/usr/bin/env python3
"""Lightweight repository sanity checks when no Verilog compiler is available."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
RTL = ROOT / "rtl"
EXPECTED = [
    "photonic_ctrl_top.v",
    "ahb_lite_slave.v",
    "photonic_csr.v",
    "measurement_ctrl.v",
    "timing_engine.v",
    "irq_ctrl.v",
]

def code_only(text: str) -> str:
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'//.*', '', text)
    text = re.sub(r'"(?:\\.|[^"\\])*"', '""', text)
    return text

errors = []
modules = {}
for name in EXPECTED:
    p = RTL / name
    if not p.exists():
        errors.append(f"missing {p}")
        continue
    text = p.read_text()
    code = code_only(text)
    mods = re.findall(r"\bmodule\s+([A-Za-z_][A-Za-z0-9_]*)", code)
    ends = re.findall(r"\bendmodule\b", code)
    if len(mods) != 1 or len(ends) != 1:
        errors.append(f"expected exactly one module/endmodule in {name}; got {mods}/{len(ends)}")
    elif mods:
        modules[name] = mods[0]
    for op, cl in [("(", ")"), ("[", "]"), ("{", "}")]:
        if code.count(op) != code.count(cl):
            errors.append(f"unbalanced {op}{cl} in {name}: {code.count(op)} vs {code.count(cl)}")
    begins = len(re.findall(r'\bbegin\b', code))
    ends2 = len(re.findall(r'\bend\b', code))
    if begins != ends2:
        errors.append(f"begin/end token count mismatch in {name}: {begins} vs {ends2}")

filelist = [x.strip() for x in (ROOT / "filelist.f").read_text().splitlines() if x.strip()]
for name in EXPECTED:
    rel = f"rtl/{name}"
    if rel not in filelist:
        errors.append(f"{rel} absent from filelist.f")

if modules.get('photonic_ctrl_top.v') != 'photonic_ctrl_top':
    errors.append('top module name mismatch')

if errors:
    print("STATIC CHECK FAIL")
    for e in errors:
        print(" -", e)
    sys.exit(1)
print("STATIC CHECK PASS: structure, module counts, and delimiters look consistent.")
