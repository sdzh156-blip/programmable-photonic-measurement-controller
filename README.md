# Programmable Photonic Measurement Controller

**Programmable Photonic Measurement Controller for Raman Spectroscopy System**  
面向拉曼光谱系统的可编程硅光测量控制器

A control-oriented digital IP project that translates a programmable measurement recipe into deterministic sensor/excitation control. The V1 controller deliberately handles the **control plane only**; pixel payload, image processing, Raman reconstruction, DMA, MIPI, and CDC are outside the RTL scope.

## Key features

- 32-bit AMBA 3 AHB-Lite CSR slave
- Up to 8 sequential programmable measurement phases
- `DARK`, `SIGNAL`, and `WAIT` phase types
- Atomic programming-bank -> active-recipe snapshot on accepted `START`
- Generic phase engine with shared 32-bit timing resource
- Sensor `ready / trigger / frame_done / error` control contract
- Excitation `enable / ready / fault` control contract
- Frame/phase/measurement tags
- Sensor-ready, frame-completion, and excitation-ready timeouts
- Software abort and ENABLE-clear termination
- Fatal/non-fatal error classification
- Safe-state behavior and explicit event priority
- Sticky W1C error/interrupt status with hardware-set priority

## RTL structure

```text
rtl/
├── photonic_ctrl_top.v
├── ahb_lite_slave.v
├── photonic_csr.v
├── measurement_ctrl.v
├── timing_engine.v
└── irq_ctrl.v
```

See [`docs/RTL_ARCHITECTURE.md`](docs/RTL_ARCHITECTURE.md) and [`docs/REGISTER_MAP.md`](docs/REGISTER_MAP.md).

## Smoke test

A small directed testbench is included only to exercise the initial RTL baseline before the UVM phase.

```bash
make smoke
```

The Makefile targets Synopsys VCS by default, matching the intended development environment.

## Project phase

Current milestone: **RTL implementation baseline**.  
Next milestone: SystemVerilog/UVM verification environment, independent event-based reference model, SVA, functional coverage, regression, and bug closure.

## Scope boundary

This is an engineering abstraction inspired by silicon-photonic/Raman measurement workflows. It is not a claim about any company's unpublished internal hardware architecture.
