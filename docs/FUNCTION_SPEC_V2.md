# PMC Function Specification V2.0

**Project:** Programmable Photonic Timing & Measurement Controller  
**定位:** 面向硅光/拉曼测量系统的可编程光子测量时序控制 IP  
**Project type:** RTL Design + UVM Verification  
**Status:** RTL baseline implemented; verification handoff ready

## 1. System positioning

PMC is a control-plane IP located between an SoC/MCU and the physical optical measurement hardware.

Software configures **how a measurement should run**. PMC then executes the timing-sensitive sequence in hardware.

PMC controls:

- excitation source enable;
- detector/sensor trigger timing;
- phase settle delay;
- sensor-ready qualification;
- frame completion timeout;
- repeated frame capture;
- abort and fault-safe shutdown;
- event/interrupt reporting.

PMC does **not** process Raman payload data and does not implement ADC, image/pixel transport, spectrum reconstruction, FFT, DMA, MIPI, or machine-learning algorithms.

## 2. Application abstraction

PMC models a Raman/photonic measurement as 1 to 8 sequential phases.

Supported phase types:

| Type | Encoding | Excitation | Sensor capture | Phase time meaning |
|---|---:|---|---|---|
| DARK | `00` | OFF | Yes | settle delay before first frame |
| SIGNAL | `01` | ON | Yes | settle delay after excitation-ready |
| WAIT | `10` | OFF | No | total wait duration |
| Reserved | `11` | - | - | illegal configuration |

A typical measurement can therefore be expressed as:

`DARK -> SIGNAL -> WAIT -> SIGNAL`

This is an engineering abstraction for chip-Raman / optical sensing workflows. It must not be presented as an unpublished internal architecture of any company.

## 3. Clock and reset

- Single local control clock: `pclk_i`.
- Active-low reset: `preset_ni`.
- APB and all internal logic use the same clock.
- External device status inputs may be asynchronous and are synchronized by local 2-FF synchronizers.

## 4. APB software interface

- 32-bit APB peripheral interface.
- Address width: 12 bits, 4 KiB window.
- Word-aligned 32-bit accesses only.
- Zero wait state: `PREADY=1`.
- Misaligned or unmapped access raises `PSLVERR` during ACCESS phase.
- Write to read-only CSR raises `PSLVERR` and has no side effect.

## 5. Programming bank and active snapshot

Software writes a programming bank while the controller is idle or busy.

On an accepted `START`, PMC atomically snapshots:

- phase count;
- all phase descriptors;
- all phase times;
- sensor-ready timeout;
- frame timeout;
- excitation-ready timeout;
- trigger width.

The active measurement uses only the snapshot. Writes performed while BUSY affect the **next** measurement.

## 6. Command semantics

`CTRL.ENABLE` is RW. `START` and `ABORT` are write-one pulse commands.

START is accepted only when:

- command is issued from IDLE;
- effective ENABLE is 1;
- no hard external fault is active;
- phase table is valid;
- controller is not BUSY;
- ABORT is not written in the same transaction.

`ENABLE=1` and `START=1` may be written in the same CTRL access.

If START and ABORT are written together:

- ABORT dominates for an active measurement;
- START is rejected;
- `CMD_REJECT` event is set.

START while BUSY is rejected without disturbing the current measurement.

Clearing ENABLE while BUSY aborts the active measurement.

## 7. Phase descriptor

Each phase has two 32-bit programming words.

### PHASEn_CFG

- `[1:0] TYPE`
- `[15:8] FRAME_COUNT`
- all other bits reserved/read-as-zero/write-ignored.

Rules:

- DARK: `FRAME_COUNT = 1..255`
- SIGNAL: `FRAME_COUNT = 1..255`
- WAIT: `FRAME_COUNT = 0`

### PHASEn_TIME

- DARK: settle delay before the first frame.
- SIGNAL: settle delay after excitation-ready.
- WAIT: phase duration.
- Zero is legal and means no additional delay.

## 8. Measurement validity rules

A recipe is invalid when any of the following is true:

- phase count is 0 or greater than 8;
- an active phase uses reserved type `11`;
- DARK/SIGNAL uses zero frame count;
- WAIT uses nonzero frame count;
- no capture phase exists;
- trigger width is zero when capture exists;
- sensor-ready timeout is zero when capture exists;
- frame timeout is zero when capture exists;
- excitation-ready timeout is zero when any SIGNAL phase exists.

Invalid START sets CONFIG_ERROR and does not start BUSY.

## 9. Sensor interface contract

Inputs:

- `sensor_ready_async_i`: level, sensor can accept a new trigger.
- `sensor_frame_done_async_i`: level, current frame completed.
- `sensor_error_async_i`: level, hard sensor fault.

Outputs:

- `sensor_trigger_o`: programmable-width trigger pulse.
- `sensor_frame_ack_o`: one-cycle acknowledgement of accepted frame completion.
- `frame_tag_valid_o`: asserted while trigger is active.
- `frame_type_o`, `measurement_id_o`, `phase_index_o`, `frame_index_o`: metadata tags.

Important DONE handshake:

- `sensor_frame_done_async_i` must be held high until the sensor observes `sensor_frame_ack_o`.
- After ACK, sensor must deassert DONE before the next frame completion can be accepted.
- PMC includes an explicit `WAIT_FRAME_CLEAR` state so a synchronized stale DONE level cannot be consumed as the next frame completion.

## 10. Excitation interface contract

Inputs:

- `excitation_ready_async_i`: level, source is stable/qualified.
- `excitation_fault_async_i`: level, hard source fault.

Output:

- `excitation_enable_o`: excitation command gate.

SIGNAL phase sequence:

1. assert excitation enable;
2. wait excitation-ready with timeout;
3. execute settle delay;
4. capture configured frames;
5. deassert excitation at phase completion or any abnormal exit.

DARK and WAIT always keep excitation disabled.

## 11. Timing semantics

All programmable timing values are in `pclk_i` cycles.

Shared timing engine behavior:

- loading `N>0` waits exactly N full clock cycles;
- `N=1` waits one full cycle;
- zero-duration phase delay is skipped by the sequencer;
- success observed on the deadline cycle wins over timeout.

Trigger pulse behavior:

- width is programmable from 1 to 65535 cycles;
- frame timeout starts only after the trigger pulse completes;
- frame completion before WAIT_FRAME is ignored.

## 12. Safety and event priority

Priority while BUSY:

1. reset;
2. hard external fault;
3. software ABORT or ENABLE clear;
4. normal success/completion;
5. timeout;
6. ordinary state transition.

Hard external faults:

- sensor error;
- excitation fault.

Any hard fault forces:

- `BUSY=0`;
- `FAILED=1`;
- excitation disabled;
- trigger stopped/masked;
- sticky error and interrupt event set.

## 13. Terminal status

`STATUS` contains:

- BUSY;
- DONE;
- ABORTED;
- FAILED.

DONE/ABORTED/FAILED describe the last accepted measurement and are mutually exclusive.

They are cleared only by the next accepted START.

Rejected START does not overwrite prior terminal status.

## 14. Error status

ERROR_STATUS is sticky W1C.

| Bit | Meaning |
|---:|---|
| 0 | CONFIG_ERROR |
| 1 | CMD_REJECT |
| 2 | SENSOR_READY_TIMEOUT |
| 3 | FRAME_TIMEOUT |
| 4 | SENSOR_ERROR |
| 5 | EXCITATION_READY_TIMEOUT |
| 6 | EXCITATION_FAULT |
| 7 | ILLEGAL_STATE |

Update rule:

`next = (old & ~sw_clear) | hw_set`

Hardware set therefore wins over software clear on the same edge.

## 15. Interrupt events

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

`irq_o = |(INT_STATUS & INT_ENABLE)`

The IP is GIC-facing at system level but does not implement GIC functionality.
