# PMC V2.1 Verification Handoff

The V2.1 RTL is a pre-DV baseline candidate. It is not verification-frozen until static and Icarus smoke CI pass for the V2.1 change itself.

## Verification focus

PMC is control/timing dominated. The primary question is whether the correct event occurs at the correct cycle, under the correct state and priority, while CDC assumptions and external-device behavior remain valid.

Recommended verification groups:

1. APB protocol, decode, misalignment, RO write and unmapped access.
2. CSR attributes: CTRL persistent ENABLE, COMMAND W1P START/ABORT, read-as-zero COMMAND, DEVICE_STATUS readback.
3. Recipe validation and START acceptance/rejection classification.
4. DARK/SIGNAL/WAIT execution and mixed recipes.
5. Active snapshot stability while BUSY despite programming-bank writes.
6. Trigger width exact-cycle checks including width=1 and max width.
7. Sensor READY timeout and success-on-deadline.
8. Frame timeout and frame-done-event-on-deadline priority.
9. Toggle CDC: exactly one local completion event for each observed source toggle.
10. Toggle CDC: no replay of an unchanged source toggle; alternating 0->1 / 1->0 completions both work.
11. Toggle CDC: asynchronous source phase relative to `pclk_i`.
12. Toggle CDC reset-baseline contract and negative tests for contract violation.
13. Completion toggle arriving outside `WAIT_FRAME` is ignored and does not complete a later frame.
14. Consecutive SIGNAL phases: synchronized READY must return low before a new enable and fresh READY-high acceptance.
15. Timeout while waiting for excitation READY-low re-arm.
16. Timeout while waiting for fresh excitation READY-high.
17. Multi-frame sequencing and exact frame index/tag behavior.
18. Fault injection from every active state: sensor error / excitation fault.
19. Software ABORT, ENABLE clear and START+ABORT same COMMAND write.
20. Priority races: fault vs abort, abort vs completion, completion vs timeout.
21. Sticky ERROR/INT W1C race: hardware set wins same-cycle software clear.
22. IRQ enable/mask/status behavior and terminal-status persistence.
23. DEVICE_STATUS visibility when START is rejected due to an already-active external fault.
24. Constrained-random mixed phase recipes and randomized sensor/excitation response latency.

## Recommended UVM agents

- APB master agent.
- Reactive sensor agent.
- Reactive excitation agent.

The sensor agent shall model the V2.1 event-toggle contract, not a one-cycle async DONE pulse and not the old DONE/ACK level protocol. For each accepted frame transaction it should optionally delay completion and then invert its source-domain completion toggle exactly once. Randomized asynchronous phase relative to `pclk_i` should be part of the normal stimulus.

The excitation agent shall model READY as a persistent level that deasserts after disable and asserts after a configurable latency following a fresh enable. It must support stale-READY-style stress, slow deassertion, slow assertion and hard-fault injection.

## Recommended reference model

A compact phase-level reference model should snapshot the programmed recipe on accepted START and predict:
- current phase/frame;
- excitation enable expectation;
- trigger count/tag metadata;
- terminal result;
- expected sticky error/interrupt events.

Do not over-model synchronizer internal flop cycles in the high-level scoreboard. CDC-specific cycle behavior should be checked with dedicated monitors/SVA and directed tests.

## Recommended SVA targets

- trigger width equals programmed value;
- no trigger in WAIT phase;
- no trigger while not BUSY;
- excitation disabled outside qualified SIGNAL execution;
- every SIGNAL enable is preceded by observed READY-low re-arm;
- hard synchronized fault leads to digital safe outputs;
- DONE/ABORTED/FAILED mutually exclusive;
- active recipe snapshot stable while BUSY;
- each synchronized toggle change produces a single-cycle local frame event;
- no local frame event without a synchronized toggle change;
- COMMAND access does not modify CTRL.ENABLE;
- HW interrupt/error set dominates same-cycle W1C.

## Sign-off note

A passing smoke test is evidence only for the scenarios it executes. V2.1 sign-off requires directed corner cases, randomized regression, functional coverage closure, SVA results and subsequent lint/synthesis/timing checks; none should be inferred from a single happy-path CI result.
