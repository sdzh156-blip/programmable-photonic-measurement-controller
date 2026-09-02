# PMC V2 RTL Architecture

## 1. Block diagram

```text
                         SoC / MCU
                            |
                           APB
                            |
                     +------v------+
                     |  apb_slave  |
                     +------|------+
                            |
                     +------v-------+
                     | photonic_csr |
                     | prog bank    |
                     +------|-------+
                            |
                   configuration snapshot
                            |
                 +----------v-----------+
                 |   phase_sequencer    |
                 |                      |
                 | phase index / frame  |
                 | event priority       |
                 | safety policy        |
                 +----+------------+----+
                      |            |
               +------v---+   +----v--------+
               | timing   |   | pulse_engine|
               | engine   |   | trigger     |
               +----------+   +-------------+
                      |
             +--------+-----------------------------+
             |                                      |
        excitation                               sensor
         enable                                    trigger
             ^                                      ^
             |                                      |
      +------+-------+                       +------+-------+
      | sync2 levels |                       | sync2 levels |
      | ready/fault  |                       | ready/done/  |
      +--------------+                       | error        |
                                             +--------------+

                 event_set
                    |
               +----v----+
               | irq_ctrl|
               +----|----+
                    v
                   IRQ
```

## 2. `apb_slave.sv`

Responsibilities:

- APB ACCESS-phase detection.
- Word-alignment checking.
- zero-wait `PREADY`.
- `PSLVERR` aggregation from alignment and CSR decode.
- simple internal CSR request interface.

No register semantics are implemented here.

## 3. `photonic_csr.sv`

Responsibilities:

- Programming register bank.
- CTRL command pulse extraction.
- status/readback mux.
- phase table storage.
- sticky ERROR_STATUS with HW-set-over-W1C semantics.
- decode of INT_STATUS/INT_ENABLE software access.

Programming writes remain legal while BUSY because the sequencer runs from its active snapshot.

## 4. `phase_sequencer.sv`

This is the application-specific control core.

Main states:

```text
IDLE
  -> LOAD_PHASE
       -> WAIT_EXC_READY -> SETTLE -> WAIT_SENSOR_READY
       -> SETTLE ------------------> WAIT_SENSOR_READY
       -> WAIT_ONLY

WAIT_SENSOR_READY -> TRIGGER -> WAIT_FRAME -> WAIT_FRAME_CLEAR
WAIT_ONLY ---------------------------------> PHASE_ADVANCE
WAIT_FRAME_CLEAR --------------------------> PHASE_ADVANCE / next frame
PHASE_ADVANCE -> LOAD_PHASE / IDLE(done)
Any active state -> SAFE_EXIT on fault/abort
```

The explicit `WAIT_FRAME_CLEAR` state is important because DONE is synchronized as a level. It prevents the deassertion latency of a previous frame-done handshake from being mistaken for the next frame completion.

## 5. `timing_engine.sv`

One shared 32-bit countdown resource is used because the control flow only waits on one timing condition at a time.

- `start_i` loads a new delay and has priority over an old timer.
- `stop_i` cancels the current timer.
- `done_o` is high while active count equals 1.
- the sequencer checks success before timeout, implementing deadline-success-wins semantics.

## 6. `pulse_engine.sv`

A dedicated 16-bit pulse-width engine generates the sensor trigger.

The engine separates trigger generation from the measurement FSM, making pulse width independently testable and reusable.

## 7. `sync2_level.sv`

Standard two-flop synchronization is applied to external **level** inputs.

It is not used as a generic pulse catcher. Frame-done is therefore defined as an acknowledged level handshake.

## 8. `irq_ctrl.sv`

Implements event-style interrupts:

```text
INT_STATUS_next = (INT_STATUS_old & ~SW_CLEAR) | HW_SET
IRQ = OR(INT_STATUS & INT_ENABLE)
```

This mirrors the common event-interrupt architecture used by mature SoC peripherals.

## 9. Safe-state boundary

The controller masks physical control outputs with BUSY/fault qualification:

- excitation is forced OFF after termination/fault;
- trigger is suppressed outside an active measurement or during hard fault;
- timer and trigger engines are explicitly stopped by SAFE_EXIT.
