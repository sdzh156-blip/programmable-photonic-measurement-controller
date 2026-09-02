# PMC V2.1 Reference Architecture Survey

## 1. Goal

PMC is intentionally not designed from a blank sheet. Generic digital structures are informed by established open-source RTL, while Raman/photonic measurement behavior, phase semantics, sequencing policy and system integration remain project-specific.

No third-party RTL file is copied verbatim into this repository. The local RTL is an independent implementation informed by the reviewed patterns.

## 2. Reference confidence levels

References are not treated as equally mature.

- **Mature generic RTL references:** PULP Platform and lowRISC/OpenTitan. These are used to cross-check common peripheral, timer, synchronizer and interrupt structures.
- **Application-domain reference:** `Kleven2k/ramsey`. It is relevant because it implements an FPGA optical/ODMR pulse sequencer, but it is a recent/small repository and is not treated as an industrial-maturity baseline.
- **Portfolio-proven CDC pattern:** event toggle + 2FF + destination pulse regeneration, reused from the 2D-DMA project methodology for one-shot cross-domain events.

## 3. PULP Platform `apb_timer`

Repository: `pulp-platform/apb_timer`

Relevant source:
- `src/apb_timer.sv`
- timer implementation under the repository source tree

Useful patterns:
- APB peripheral organization;
- register decode separated from timing behavior;
- counter/compare timing resources;
- low-bandwidth control/status plane.

PMC adoption:
- APB for software control/status only;
- dedicated timing engine rather than embedding counters throughout the FSM;
- register semantics isolated from the APB shell.

Not adopted:
- PULP register map;
- prescaler semantics;
- timer interrupt encoding.

## 4. lowRISC OpenTitan primitives

Repository: `lowRISC/opentitan`

Relevant source:
- `hw/ip/prim_generic/rtl/prim_flop_2sync.sv`
- `hw/ip/prim/rtl/prim_intr_hw.sv`

Useful patterns:
- 2-FF synchronizer as a standard primitive for asynchronous **persistent levels**;
- sticky hardware-event interrupt state;
- separate interrupt pending and enable/mask state;
- explicit RTL primitives with independently verifiable responsibilities.

PMC adoption:
- `sensor_ready`, `sensor_error`, `excitation_ready` and `excitation_fault` use 2-FF level synchronization;
- event interrupt status is sticky;
- software W1C and hardware set resolve with hardware-set priority;
- IRQ is generated from pending AND enable.

Important restriction:
- a plain 2-FF synchronizer does not guarantee capture of an arbitrarily narrow asynchronous pulse. Therefore frame completion is **not** modeled as a one-cycle async pulse and is not modeled as a DONE/ACK level handshake in V2.1.

## 5. Toggle-event CDC pattern

Frame completion is a one-shot event. V2.1 uses the same classification and solution already used in the 2D-DMA project:

```text
source event
   -> toggle source bit
   -> 2FF into destination
   -> compare synchronized current/previous toggle
   -> one-cycle destination event
```

Why this was chosen:
- preserves a one-shot event across unrelated clocks without requiring the destination to sample a narrow pulse;
- avoids a one-cycle ACK returning to an asynchronous source;
- matches the portfolio's established distinction between level CDC and event CDC.

Required assumptions:
- source toggle has a defined reset/baseline value;
- source does not toggle twice before the destination can observe distinct changes;
- one frame transaction produces exactly one completion toggle.

This is an architectural pattern reused from the existing 2D-DMA work, not a claim that OpenTitan's `prim_flop_2sync` alone implements event CDC.

## 6. `Kleven2k/ramsey`

Repository: `Kleven2k/ramsey`

This project is an FPGA pulse sequencer / photon-counter application for optical/ODMR experiments. It is useful as evidence that deterministic hardware pulse/state sequencing is a realistic experiment-control architecture.

Useful concepts:
- optical experiment timing represented as deterministic hardware states rather than software delay loops;
- cycle-based configurable durations;
- dedicated experiment gate outputs;
- repetition/shot counting.

PMC adoption:
- deterministic phase sequencer;
- timing-critical physical-control outputs;
- programmable trigger width;
- hardware frame repetition counter.

Not adopted:
- ODMR-specific microwave states;
- frequency-sweep logic;
- photon-counting/accumulation datapath;
- source RTL itself.

Maturity note: at the V2.1 review this repository is treated only as an application-domain reference. Its limited project history/adoption means it is not used to justify generic RTL correctness by itself.

## 7. Reuse policy

| Block | Policy | Primary basis |
|---|---|---|
| APB shell | independent implementation | mature APB peripheral patterns |
| Cycle timer | independent implementation | PULP timer organization / counter semantics |
| 2-FF level synchronizer | standard primitive reimplementation | OpenTitan-style level synchronization |
| Toggle-event synchronizer | independent implementation | 2D-DMA event-CDC methodology |
| Sticky interrupt | independent implementation | OpenTitan event-interrupt pattern |
| Pulse generator | independent implementation | experiment-sequencer concept |
| Phase table | original | photonic measurement requirements |
| Measurement sequencer | original | photonic measurement requirements |
| Digital fault-safe shutdown | original | project-specific fault policy |

## 8. Design consequence

PMC is not a small CPU and does not implement instruction fetch, branch, general-purpose registers or instruction prefetch. It is a **programmable measurement sequencer**: software configures a bounded table of measurement phases and dedicated hardware executes them deterministically.
