# PMC Function Specification V2.1

**Project:** Programmable Photonic Timing & Measurement Controller  
**定位:** 面向硅光/拉曼测量系统的可编程光子测量时序控制 IP  
**Project type:** RTL Design + UVM Verification  
**Status:** Pre-DV architecture cleanup; RTL must pass V2.1 CI before freeze

## 1. System positioning

PMC is a control-plane IP located between an SoC/MCU and physical optical measurement hardware. Software configures **how a measurement should run**; PMC executes the timing-sensitive sequence in hardware.

PMC controls excitation enable, sensor trigger timing, settle/wait intervals, READY qualification, frame-completion timeout, repeated captures, abort/fault response and event/interrupt reporting. PMC does **not** process Raman payload data and does not implement ADC, image/pixel transport, spectrum reconstruction, FFT, DMA, MIPI or machine-learning algorithms.

This is an engineering abstraction for chip-Raman / optical-sensing workflows. It must not be presented as an unpublished internal architecture of any company.

## 2. Measurement model

A measurement consists of 1 to 8 sequential phases:

| Type | Encoding | Excitation | Sensor capture | PHASE_TIME meaning |
|---|---:|---|---|---|
| DARK | `00` | OFF | Yes | settle before first frame |
| SIGNAL | `01` | ON after fresh READY qualification | Yes | settle after READY-high |
| WAIT | `10` | OFF | No | wait duration |
| Reserved | `11` | - | - | illegal |

Example: `DARK -> SIGNAL -> WAIT -> SIGNAL`.

## 3. Clock, reset and CDC classification

- APB and all PMC internal logic use `pclk_i`.
- Active-low reset: `preset_ni`.
- External persistent status levels (`sensor_ready`, `sensor_error`, `excitation_ready`, `excitation_fault`) use 2-FF synchronization into `pclk_i`.
- Frame completion is an event, not a persistent level. The sensor exposes a **toggle bit** that flips exactly once for each completed frame. PMC synchronizes that toggle through 2 FFs and regenerates one local one-cycle `frame_done_event` from the synchronized-toggle change.
- The source-side frame-completion toggle shall be initialized to 0 before normal PMC operation / reset release and shall not toggle more than once per completed frame.
- Events must not be produced faster than the destination synchronizer can observe distinct toggle changes. The normal PMC protocol naturally spaces completion events by a trigger/capture transaction; violating this source contract is outside V2.1 guarantees.

This CDC scheme intentionally mirrors the event-toggle method already used elsewhere in the project portfolio rather than relying on a one-cycle asynchronous pulse or DONE/ACK level handshake.

## 4. APB software interface

- 32-bit APB peripheral interface.
- 12-bit address, 4 KiB window.
- Word-aligned 32-bit accesses only.
- Zero wait state: `PREADY=1`.
- Misaligned or unmapped access raises `PSLVERR` during ACCESS.
- Write to read-only CSR raises `PSLVERR` and has no side effect.

## 5. Programming bank and active snapshot

Software may update the programming bank while IDLE or BUSY. On an accepted START, PMC snapshots phase count, phase descriptors, phase times, READY/frame timeouts and trigger width. The active measurement uses only that snapshot; BUSY-time programming writes affect the next accepted measurement.

## 6. Command semantics

Persistent state and one-shot commands are separated:

- `CTRL.ENABLE[0]`: RW persistent enable.
- `COMMAND.START[0]`: W1P command.
- `COMMAND.ABORT[1]`: W1P command.
- COMMAND reads as zero.

START is accepted only when:

- state is IDLE and controller is not BUSY;
- `CTRL.ENABLE=1` before the COMMAND access;
- no synchronized hard fault is active;
- phase-table configuration is valid;
- ABORT is not asserted in the same COMMAND write.

Because ENABLE and START are separate CSRs in V2.1, software shall enable PMC first and then issue START. START while BUSY is rejected without disturbing the current measurement. ABORT while BUSY terminates the active measurement. Clearing ENABLE while BUSY also aborts the active measurement.

If START and ABORT are written together, START is rejected; if BUSY, ABORT dominates and terminates the active measurement. If IDLE, no measurement starts and CMD_REJECT is recorded.

## 7. Phase descriptor

Each phase has two 32-bit programming words.

### PHASEn_CFG

- `[1:0] TYPE`
- `[15:8] FRAME_COUNT`
- other bits reserved/read-as-zero/write-ignored.

Rules:
- DARK/SIGNAL: `FRAME_COUNT = 1..255`
- WAIT: `FRAME_COUNT = 0`

### PHASEn_TIME

- DARK: settle before first frame.
- SIGNAL: settle after a **fresh** excitation READY-high qualification.
- WAIT: phase duration.
- Zero is legal and means no additional programmable delay.

## 8. Configuration validity

A recipe is invalid when phase count is 0 or >8, an active phase uses reserved type, DARK/SIGNAL has zero frame count, WAIT has nonzero frame count, no capture phase exists, trigger width is zero for a capture recipe, required sensor/frame timeout is zero, or excitation-ready timeout is zero when any SIGNAL exists.

Invalid START sets CONFIG_ERROR and does not enter BUSY.

## 9. Sensor interface contract

Inputs:
- `sensor_ready_async_i`: persistent level; high means sensor can accept a trigger.
- `sensor_frame_done_toggle_async_i`: event toggle; flips once per completed frame.
- `sensor_error_async_i`: persistent hard-fault level.

Outputs:
- `sensor_trigger_o`: programmable-width trigger pulse.
- `frame_tag_valid_o`: asserted while trigger is active.
- `frame_type_o`, `measurement_id_o`, `phase_index_o`, `frame_index_o`: metadata tags.

Frame-completion behavior:
- no `sensor_frame_ack_o` exists in V2.1;
- PMC converts each observed toggle change into one local completion event;
- an event is consumed only in `WAIT_FRAME`; an event in another state is ignored;
- frame timeout starts after the trigger pulse completes;
- an event observed on the timeout deadline wins over timeout.

The external sensor/integration must be able to detect the configured trigger width. System integration shall choose a trigger width long enough for the receiving device/interface.

## 10. Excitation interface contract

Inputs:
- `excitation_ready_async_i`: persistent level; high means enabled source is qualified/stable.
- `excitation_fault_async_i`: persistent fault level.

Output:
- `excitation_enable_o`: excitation command gate.

Every SIGNAL phase performs a fresh re-arm sequence:
1. keep excitation disabled;
2. wait for synchronized READY to be low, with excitation-ready timeout;
3. assert excitation enable;
4. wait for synchronized READY to become high, with excitation-ready timeout;
5. execute configured settle interval;
6. capture configured frames;
7. deassert excitation at phase completion or abnormal exit.

This prevents a stale synchronized READY-high from a preceding SIGNAL phase from being accepted as qualification for the next phase.

DARK and WAIT keep excitation disabled.

## 11. Timing semantics

All programmable timing values are in `pclk_i` cycles.

- loading `N>0` waits exactly N full clock cycles according to the shared timing-engine contract;
- `N=1` waits one full programmable cycle;
- zero phase delay is skipped;
- success observed on the deadline cycle wins over timeout;
- trigger width is programmable 1..65535 cycles;
- frame timeout starts after trigger completion.

Exact N=1/deadline behavior is a mandatory directed-verification item before sign-off.

## 12. Fault-safe shutdown and event priority

The PMC implements **digital fault-safe shutdown / safe-state control**, not an independent physical laser-safety interlock. External fault levels cross a 2-FF synchronizer, so shutdown includes synchronization latency. Any real personnel/equipment safety interlock must be implemented independently at system level.

Priority while BUSY:
1. reset;
2. synchronized hard external fault;
3. software ABORT or ENABLE clear;
4. normal success/completion;
5. timeout;
6. ordinary state transition.

Hard faults are sensor error and excitation fault. A hard fault terminates BUSY, sets FAILED, forces excitation off, suppresses/stops trigger activity and records sticky error/interrupt events.

## 13. Terminal status

STATUS contains BUSY, DONE, ABORTED and FAILED. DONE/ABORTED/FAILED describe the last accepted measurement and are mutually exclusive. They are cleared by the next accepted START. Rejected START does not overwrite prior terminal status.

## 14. Device status

`DEVICE_STATUS` exposes synchronized external levels for diagnosis even when a command is rejected:

| Bit | Meaning |
|---:|---|
| 0 | SENSOR_READY |
| 1 | SENSOR_ERROR |
| 2 | EXCITATION_READY |
| 3 | EXCITATION_FAULT |

The frame-completion toggle/event is intentionally not exposed as a persistent status bit.

## 15. Error status

ERROR_STATUS is sticky W1C:

| Bit | Meaning |
|---:|---|
| 0 | CONFIG_ERROR |
| 1 | CMD_REJECT |
| 2 | SENSOR_READY_TIMEOUT |
| 3 | FRAME_TIMEOUT |
| 4 | SENSOR_ERROR |
| 5 | EXCITATION_READY_TIMEOUT (includes failure to re-arm READY-low or qualify READY-high) |
| 6 | EXCITATION_FAULT |
| 7 | ILLEGAL_STATE |

Update rule: `next = (old & ~sw_clear) | hw_set`; hardware set wins over software clear on the same edge.

## 16. Interrupt events

INT_STATUS is sticky W1C; INT_ENABLE masks IRQ generation.

| Bit | Event |
|---:|---|
| 0 | MEAS_DONE |
| 1 | ABORT_DONE |
| 2 | CONFIG_ERROR |
| 3 | CMD_REJECT |
| 4 | SENSOR_READY_TIMEOUT |
| 5 | FRAME_TIMEOUT |
| 6 | SENSOR_ERROR |
| 7 | EXCITATION_READY_TIMEOUT |
| 8 | EXCITATION_FAULT |
| 9 | ILLEGAL_STATE |

`irq_o = |(INT_STATUS & INT_ENABLE)`.

PMC is GIC-facing at system level but does not implement GIC functionality.

## 17. Version

`VERSION = 0x0002_0100` for V2.1.
