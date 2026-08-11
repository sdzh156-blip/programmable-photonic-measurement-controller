# RTL Architecture

The V1 implementation intentionally contains six synthesizable Verilog source files.

| File | Responsibility |
|---|---|
| `rtl/photonic_ctrl_top.v` | Integration-only top level |
| `rtl/ahb_lite_slave.v` | AHB-Lite address/data pipeline and two-cycle ERROR response |
| `rtl/photonic_csr.v` | Programming CSR bank, W1P commands, ERROR_STATUS W1C |
| `rtl/measurement_ctrl.v` | START acceptance, active snapshot, phase sequencer, event priority, safe-state |
| `rtl/timing_engine.v` | Shared 32-bit cycle timer |
| `rtl/irq_ctrl.v` | INT_STATUS/INT_ENABLE and IRQ reduction |

## Control flow

1. Software programs the recipe and timeout registers through AHB-Lite.
2. A `START` W1P request is emitted by `photonic_csr`.
3. `measurement_ctrl` validates the programming bank. If valid, it atomically snapshots the complete recipe and timeout set.
4. The active recipe executes sequentially from phase 0 to `PHASE_COUNT-1`.
5. DARK and SIGNAL phases issue one-cycle sensor triggers; WAIT is timing-only.
6. A single `timing_engine` is reused for settle and timeout intervals because the waits are mutually exclusive.
7. Fault/abort/completion outcome is committed on the event edge; cleanup states do not delay software-visible terminal status.

## Design-review decisions embodied in RTL

- No independent `TRIGGER` FSM state. Trigger/tag is generated on the `WAIT_SENSOR_READY -> WAIT_FRAME` transition, eliminating a one-cycle frame-done blind window.
- Programming and active configuration are separate. BUSY-time software writes cannot modify the current measurement.
- Sensor ready is expected to remain asserted until the trigger is observed.
- Excitation ready is expected to remain asserted while excitation stays enabled; loss of a qualified excitation is represented by `excitation_fault_i`.
- `SETTLE_CYCLES` defines a minimum programmable delay, not an exact trigger time.
- Success-at-deadline wins over timeout.
- Hard fault > abort/disable > success/completion > timeout > normal transition.
- SIGNAL->SIGNAL may keep excitation enabled; SIGNAL->DARK/WAIT/end disables it on the phase terminal edge.
