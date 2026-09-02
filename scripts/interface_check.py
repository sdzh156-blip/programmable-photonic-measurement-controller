#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
top = (ROOT / "rtl/photonic_ctrl_top.sv").read_text()

required_instances = {
    "u_apb_slave": "apb_slave",
    "u_photonic_csr": "photonic_csr",
    "u_timing_engine": "timing_engine",
    "u_pulse_engine": "pulse_engine",
    "u_phase_sequencer": "phase_sequencer",
    "u_irq_ctrl": "irq_ctrl",
    "u_sync_sensor_ready": "sync2_level",
    "u_sync_sensor_frame_done_toggle": "sync2_toggle_event",
    "u_sync_sensor_error": "sync2_level",
    "u_sync_excitation_ready": "sync2_level",
    "u_sync_excitation_fault": "sync2_level",
}

errors = []
for inst, mod in required_instances.items():
    pat = rf"\b{re.escape(mod)}\b[\s\S]*?\b{re.escape(inst)}\s*\("
    if not re.search(pat, top):
        errors.append(f"missing instance {inst} of {mod}")

for signal in [
    "sensor_ready_sync", "sensor_frame_done_toggle_sync", "sensor_frame_done_event",
    "sensor_error_sync", "excitation_ready_sync", "excitation_fault_sync",
    "timer_start", "timer_done", "trigger_start", "trigger_done",
    "int_set", "int_status", "int_enable"
]:
    if signal not in top:
        errors.append(f"missing integration signal {signal}")

for legacy in ["sensor_frame_ack_o", "sensor_frame_done_async_i", "start_enable_value"]:
    if legacy in top:
        errors.append(f"legacy integration construct still present: {legacy}")

if errors:
    print("INTERFACE CHECK FAIL")
    for err in errors:
        print(" -", err)
    sys.exit(1)
print("INTERFACE CHECK PASS: required V2.1 blocks and integration signals are present.")
