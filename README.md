# Programmable Photonic Timing & Measurement Controller

**面向硅光/拉曼测量系统的可编程光子测量时序控制器 — RTL Design & Verification Project**

PMC is a control-oriented digital IP that converts a software-programmed optical measurement recipe into deterministic hardware timing for an excitation source and a detector/sensor.

The application background is chip-scale Raman / photonic sensing. The design is an engineering abstraction for this class of measurement system; it is **not** a claim about any company's unpublished internal RTL architecture.

## Positioning

```text
SoC/MCU --APB--> PMC --timing/control--> Excitation
                    \--trigger/ack----> Sensor

Sensor payload data --------------------> separate acquisition / algorithm path
```

PMC answers **when and in what order to measure**. It does not process the Raman payload itself.

## V2 architecture

- 32-bit APB control/status interface
- 1..8 programmable measurement phases
- DARK / SIGNAL / WAIT phase semantics
- atomic programming-bank -> active-snapshot on accepted START
- deterministic measurement sequencer
- shared 32-bit timing engine
- programmable-width sensor trigger engine
- asynchronous level synchronizers for external ready/done/fault inputs
- DONE/ACK level handshake to prevent missed narrow pulses and stale completion reuse
- excitation and sensor timeout handling
- software abort and ENABLE-clear termination
- hard-fault safety interlock
- sticky W1C error and interrupt event state
- GIC-facing IRQ output, without implementing a GIC

## Why the architecture changed from V1

V1 used AHB-Lite mainly to access control registers. V2 changes the software port to APB because PMC is fundamentally a low-bandwidth peripheral-control IP. The project complexity is now concentrated where it belongs: measurement timing, phase sequencing, device handshakes, safety, and verification.

V2 also intentionally avoids turning the recipe into a CPU-style instruction set. There is no instruction fetch, branch, general-purpose register file, or instruction prefetch.

## Mature open-source references

Generic blocks were designed after reviewing mature implementations rather than inventing new protocol behavior from scratch:

- PULP Platform `apb_timer`: APB peripheral + cycle timer architecture
- `Kleven2k/ramsey`: FPGA optical/ODMR pulse sequencer architecture
- lowRISC OpenTitan `prim_flop_2sync`: two-flop level synchronizer pattern
- lowRISC OpenTitan `prim_intr_hw`: event interrupt state/enable architecture

See [`docs/REFERENCE_ARCHITECTURE_SURVEY.md`](docs/REFERENCE_ARCHITECTURE_SURVEY.md).

No third-party RTL source file is copied into this repository; the local implementation is project-specific.

## RTL

```text
rtl/
├── apb_slave.sv
├── photonic_csr.sv
├── phase_sequencer.sv
├── timing_engine.sv
├── pulse_engine.sv
├── sync2_level.sv
├── irq_ctrl.sv
└── photonic_ctrl_top.sv
```

## Documentation

- [`docs/FUNCTION_SPEC_V2.md`](docs/FUNCTION_SPEC_V2.md)
- [`docs/RTL_ARCHITECTURE.md`](docs/RTL_ARCHITECTURE.md)
- [`docs/REGISTER_MAP.md`](docs/REGISTER_MAP.md)
- [`docs/INTERFACE_CONTRACTS.md`](docs/INTERFACE_CONTRACTS.md)
- [`docs/REFERENCE_ARCHITECTURE_SURVEY.md`](docs/REFERENCE_ARCHITECTURE_SURVEY.md)
- [`docs/VERIFICATION_HANDOFF.md`](docs/VERIFICATION_HANDOFF.md)

## Local checks

```bash
make static
make smoke        # Synopsys VCS
```

For Icarus Verilog:

```bash
make smoke_iverilog
```

The repository GitHub Actions workflow installs Icarus Verilog and runs static + smoke checks.

## Current milestone

**V2 RTL baseline complete.**

Local lightweight structural checks pass in the current development environment. A Verilog compiler is not available in that environment, so compile/elaboration/simulation must be confirmed by VCS or GitHub CI before declaring RTL verification PASS.

Next milestone: SystemVerilog/UVM environment, SVA, functional coverage, regression, bug closure, then synthesis/timing/area reporting.
