# Functional Requirements Baseline

This file mirrors the requirements that the RTL implementation is intended to satisfy and that the later UVM/SVA plan should trace against.

## System and bus

- **SYS-001** — V1 uses one `hclk_i` clock domain.
- **SYS-002** — PMC does not process pixel/frame/spectrum payload data.
- **SYS-003** — Up to 8 sequential phases are supported.
- **BUS-001** — 32-bit AHB-Lite slave control interface.
- **BUS-002** — Only 32-bit word-aligned CSR accesses are legal.
- **BUS-003** — Legal CSR accesses are zero-wait-state.
- **BUS-004** — Data phase resolves from latched address/control transaction state for both reads and writes.
- **BUS-005** — Bad size, misalignment, and unmapped offsets return AHB ERROR without CSR side effects.
- **BUS-006** — AHB ERROR uses a two-cycle response.

## CSR and configuration

- **CSR-001** — Reserved bits read as zero and ignore writes.
- **CSR-002** — START/ABORT are W1P commands.
- **CSR-003** — ERROR_STATUS and INT_STATUS are W1C.
- **CSR-004** — Hardware set wins over software W1C in the same cycle.
- **CFG-001** — Accepted START atomically snapshots all active configuration.
- **CFG-002** — Programming-bank writes while BUSY do not affect the current measurement.
- **CFG-003** — Unused recipe entries are excluded from validation.

## Recipe and phases

- **REC-001** — Recipe executes sequentially with no branch/loop.
- **REC-002** — DARK, SIGNAL, WAIT are supported.
- **REC-003** — Recipe contains at least one capture phase.
- **REC-004** — RESERVED type rejects START.
- **REC-005** — DARK/SIGNAL `FRAME_NUM=1..255`; WAIT `FRAME_NUM=0`.
- **PHA-001** — DARK forces excitation off.
- **PHA-002** — SIGNAL requires excitation-ready qualification before trigger.
- **PHA-003** — WAIT forces excitation off and never triggers the sensor.

## Timing, trigger, and counters

- **TIM-001** — `SETTLE=0` bypasses programmable delay; `N>0` gives at least N full hclk cycles of minimum settling delay.
- **TIM-002** — A timeout value of zero is invalid when that timeout is required by the recipe.
- **TIM-003** — Success at the deadline edge wins over timeout.
- **TRG-001** — Sensor trigger is exactly one clock pulse.
- **TRG-002** — Trigger requires sensor-ready qualification.
- **TRG-003** — No second trigger while a frame is outstanding.
- **TRG-004** — No dedicated TRIGGER state; trigger/tag is generated on `WAIT_SENSOR_READY -> WAIT_FRAME`.
- **TAG-001** — `frame_tag_valid` is coincident with trigger.
- **TAG-002** — Measurement/phase/frame/type tags match current execution.
- **CNT-001** — Frame index restarts at zero for each capture phase.
- **CNT-002** — Trigger count exactly equals `FRAME_NUM`.
- **CNT-003** — Measurement ID increments only on accepted START.

## Commands, error, safety, and IRQ

- **CMD-001** — START while BUSY only sets CMD_REJECT and does not disturb execution.
- **CMD-002** — ABORT or ENABLE clear while BUSY performs safe controlled termination.
- **CMD-003** — START+ABORT conflict gives ABORT priority.
- **ERR-001** — Fatal errors terminate the current measurement.
- **ERR-002** — Hard fault wins over abort/completion.
- **ERR-003** — Abort wins over completion/timeout.
- **ERR-004** — External hard fault in IDLE is recorded and blocks START.
- **SAFE-001** — Reset forces excitation/trigger/tag low.
- **SAFE-002** — Fatal/abort/terminal paths enter safe-state on the outcome edge.
- **SAFE-003** — Illegal FSM encoding recovers via SAFE_EXIT and sets ILLEGAL_STATE.
- **STAT-001** — BUSY and DONE/ABORTED/FAILED commit on the terminal outcome edge.
- **IRQ-001** — `irq_o = |(INT_STATUS & INT_ENABLE)`.
- **IRQ-002** — Pending remains until W1C or reset.
- **IRQ-003** — Completion/abort/error sources set their interrupt pending bits.
