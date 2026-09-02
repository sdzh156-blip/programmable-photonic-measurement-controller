#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
RTL = ROOT / "rtl"
EXPECTED = [
    "sync2_level.sv",
    "timing_engine.sv",
    "pulse_engine.sv",
    "apb_slave.sv",
    "irq_ctrl.sv",
    "photonic_csr.sv",
    "phase_sequencer.sv",
    "photonic_ctrl_top.sv",
]

def code_only(text: str) -> str:
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'//.*', '', text)
    text = re.sub(r'"(?:\\.|[^"\\])*"', '""', text)
    return text

errors = []
mods = {}
for name in EXPECTED:
    path = RTL / name
    if not path.exists():
        errors.append(f"missing {path}")
        continue
    code = code_only(path.read_text())
    mod_names = re.findall(r"\bmodule\s+([A-Za-z_]\w*)", code)
    endmods = re.findall(r"\bendmodule\b", code)
    if len(mod_names) != 1 or len(endmods) != 1:
        errors.append(f"{name}: expected one module/endmodule, got {mod_names}/{len(endmods)}")
    elif mod_names:
        mods[name] = mod_names[0]
    for op, cl in [("(", ")"), ("[", "]"), ("{", "}")]:
        if code.count(op) != code.count(cl):
            errors.append(f"{name}: unbalanced {op}{cl}: {code.count(op)} vs {code.count(cl)}")
    if len(re.findall(r'\bbegin\b', code)) != len(re.findall(r'\bend\b', code)):
        errors.append(f"{name}: begin/end token count mismatch")

filelist = [line.strip() for line in (ROOT / "filelist.f").read_text().splitlines() if line.strip()]
for name in EXPECTED:
    rel = f"rtl/{name}"
    if rel not in filelist:
        errors.append(f"{rel} missing from filelist.f")

if mods.get("photonic_ctrl_top.sv") != "photonic_ctrl_top":
    errors.append("top module name mismatch")

critical = {
    "rtl/photonic_csr.sv": ["A_CTRL", "A_INT_STATUS", "A_VERSION", "start_req_o", "error_status_q"],
    "rtl/phase_sequencer.sv": ["start_accept", "ST_WAIT_EXC_READY", "ST_TRIGGER", "ST_WAIT_FRAME", "ST_WAIT_FRAME_CLEAR", "ST_SAFE_EXIT"],
    "rtl/irq_ctrl.sv": ["(status_q & ~sw_clear_i) | hw_set_i"],
}
for rel, needles in critical.items():
    text = (ROOT / rel).read_text()
    for needle in needles:
        if needle not in text:
            errors.append(f"{rel}: missing critical construct {needle!r}")

if errors:
    print("STATIC CHECK FAIL")
    for err in errors:
        print(" -", err)
    sys.exit(1)
print("STATIC CHECK PASS: V2 RTL structure and critical constructs look consistent.")
