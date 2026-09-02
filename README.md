# Programmable Photonic Timing & Measurement Controller

**面向硅光/拉曼测量系统的可编程光子测量时序控制器 — RTL Design & Verification Project**

PMC is a control-oriented digital IP that converts a software-programmed optical measurement recipe into deterministic hardware timing for an excitation source and a detector/sensor.

The application background is chip-scale Raman / photonic sensing. The design is an engineering abstraction for this class of measurement system; it is **not** a claim about any company's unpublished internal RTL architecture.

## Positioning

```text
SoC/MCU --APB--> PMC --timing/control--> Excitation
                    \--trigger-------> Sensor
                    <--DONE toggle----/

Sensor payload data --------------------> separate acquisition / algorithm path
```

PMC answers **when and in what order to measure**. It does not process the Raman payload itself.

## V2.1 architecture

- 32-bit APB control/status interface
- 1..8 programmable measurement phases
- DARK / SIGNAL / WAIT phase semantics
- atomic programming-bank -> active-snapshot on accepted START
- deterministic measurement sequencer
- shared 32-bit timing engine
- programmable-width sensor trigger engine
- 2-FF synchronization for asynchronous READY/FAULT levels
- toggle + 2-FF + destination pulse regeneration for asynchronous frame-completion events
- fresh READY-low -> enable -> READY-high qualification for every SIGNAL phase
- separate persistent `CTRL.ENABLE` and one-shot `COMMAND.START/ABORT` CSRs
- readable synchronized device status
- digital fault-safe shutdown / safe-state control
- sticky W1C error and interrupt event state
- GIC-facing IRQ output, without implementing a GIC

## Design rationale

V1 used AHB-Lite mainly to access control registers. V2 moved the software port to APB because PMC is fundamentally a low-bandwidth peripheral-control IP. The project complexity is concentrated in measurement timing, phase sequencing, CDC/event handling, fault response and verification.

V2.1 removes the earlier DONE/ACK level protocol. Frame completion now follows the event-CDC method used elsewhere in the portfolio: the source toggles one bit per completion, PMC synchronizes the toggle and regenerates exactly one local event pulse. READY and FAULT remain level signals synchronized with 2-FF structures.

The recipe is intentionally not a CPU-style instruction set. There is no instruction fetch, branch, general-purpose register file, ALU or instruction prefetch.

## Open-source reference policy

Generic digital structures are informed by established open-source implementations rather than invented from scratch:

- PULP Platform `apb_timer`: mature APB peripheral / timer organization reference
- lowRISC OpenTitan `prim_flop_2sync`: mature two-flop level synchronizer reference
- lowRISC OpenTitan `prim_intr_hw`: mature event-interrupt state / enable reference
- `Kleven2k/ramsey`: optical/ODMR application-level pulse-sequencer reference; useful for domain behavior, not treated as an industrial-maturity baseline

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
├── sync2_toggle_event.sv
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

## Checks

```bash
make static
make smoke        # Synopsys VCS when available
make smoke_iverilog
```

GitHub Actions installs Icarus Verilog and runs static + smoke checks. V2.0 previously passed Icarus compile/smoke; V2.1 must pass its own CI before being treated as the new frozen RTL baseline.

## Current milestone

**V2.1 pre-DV architecture cleanup.**

The cleanup addresses event CDC, consecutive-SIGNAL readiness requalification, command-register semantics, device-status visibility, and fault-safe terminology. After V2.1 CI passes and the change is merged, the next milestone is SystemVerilog/UVM, SVA, functional coverage, regression, bug closure, then synthesis/timing/area reporting.
