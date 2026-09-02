# PMC V2 Reference Architecture Survey

## 1. Goal

PMC V2 is intentionally not designed from a blank sheet. The project uses mature open-source RTL as **architecture references** for generic digital building blocks, while keeping the Raman/photonic measurement behavior, phase semantics, safety policy, and system integration original to this project.

No third-party RTL file is copied verbatim into this repository. The implementation is an independent re-implementation informed by the patterns below.

## 2. Reference projects

### 2.1 PULP Platform `apb_timer`

Repository: `pulp-platform/apb_timer`

Relevant source files:

- `src/apb_timer.sv`
- `src/timer.sv`

Useful patterns:

- APB peripheral with `PSEL/PENABLE/PWRITE/PADDR/PWDATA/PRDATA/PREADY/PSLVERR`.
- Zero-wait-state register access when no peripheral stall is required.
- Counter + compare style timing block.
- APB register decode separated from the timing behavior.

PMC adoption:

- APB is used only as the software control/status plane.
- PMC uses a zero-wait APB access model.
- Timing is kept in a dedicated reusable timing engine.

Not adopted:

- PULP timer register map.
- PULP timer prescaler behavior.
- PULP timer interrupt encoding.

### 2.2 `Kleven2k/ramsey`

Repository: `Kleven2k/ramsey`

Relevant source file:

- `rtl/sequencer/pulse_sequencer.sv`

This project is an FPGA timing sequencer for optical/ODMR experiments. Its sequencer drives configurable laser, microwave and readout windows using a state machine and cycle-based durations.

Useful patterns:

- Experiment timing represented as deterministic hardware states rather than a software delay loop.
- Duration parameters expressed directly in clock cycles.
- Dedicated gate outputs for physical experiment windows.
- Repetition counter for multiple shots.
- Single-cycle event pulses are explicitly cleared every cycle.

PMC adoption:

- Measurement phases are executed by a deterministic hardware sequencer.
- Optical-control outputs are treated as timing-critical hardware signals.
- Sensor trigger width is programmable in clock cycles.
- Multi-frame capture uses a hardware frame counter.

Not adopted:

- ODMR-specific microwave states.
- Frequency sweep logic.
- Photon counting and shot accumulation datapath.

### 2.3 lowRISC OpenTitan primitives

Repository: `lowRISC/opentitan`

Relevant source files:

- `hw/ip/prim_generic/rtl/prim_flop_2sync.sv`
- `hw/ip/prim/rtl/prim_intr_hw.sv`

Useful patterns:

- A two-flop synchronizer is a standard primitive for asynchronous **level** inputs.
- Event interrupts are sticky: a momentary hardware event sets interrupt state until software clears it.
- Interrupt enable/mask is separate from interrupt pending state.

PMC adoption:

- External asynchronous ready/done/fault signals are first synchronized into the PMC clock domain.
- Event interrupt status is sticky.
- Software W1C clear and hardware set are resolved with hardware-set priority.
- `irq_o` is generated from pending state AND interrupt enable.

Important interface restriction:

- A plain 2-FF synchronizer does not guarantee capture of an arbitrarily narrow asynchronous pulse.
- Therefore `sensor_frame_done_async_i` is defined as a **level handshake**: the sensor must hold DONE high until `sensor_frame_ack_o` is observed.

## 3. Reuse policy

| Block | Policy | Reason |
|---|---|---|
| APB slave shell | Re-implement from mature APB peripheral pattern | Keep project self-contained and simple |
| Cycle timer | Re-implement from mature counter/compare pattern | PMC timing semantics are project-specific |
| 2-FF synchronizer | Re-implement standard primitive | No OpenTitan dependency required |
| Sticky interrupt | Re-implement event-interrupt pattern | PMC register map is custom |
| Pulse generator | Re-implement from experiment-sequencer concept | Width and stop semantics are PMC-specific |
| Phase table | Original | Application-specific |
| Measurement sequencer | Original | Application-specific |
| Safety interlock | Original | Application-specific |

## 4. Design consequence

PMC V2 is not a small CPU and does not implement instruction fetch, branch, general-purpose registers, or instruction prefetch. It is a **programmable measurement sequencer**: software configures a bounded table of measurement phases, and dedicated hardware executes them deterministically.
