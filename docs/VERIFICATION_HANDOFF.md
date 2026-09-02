# PMC V2 Verification Handoff

The RTL baseline is ready for UVM verification planning.

## Verification focus

The project is control/timing dominated. The primary question is not data movement but whether the right event occurs in the right cycle under the right priority.

Recommended verification groups:

1. APB/CSR legality and register attributes.
2. Recipe validation and START command classification.
3. DARK/SIGNAL/WAIT phase execution.
4. Multi-frame sequencing.
5. Trigger-width exact-cycle checking.
6. Excitation-ready, sensor-ready and frame timeout boundaries.
7. Success-on-deadline priority.
8. Sensor DONE/ACK/deassert handshake.
9. Fault injection in every active state.
10. Software ABORT and ENABLE clear.
11. BUSY programming-bank writes vs active snapshot stability.
12. W1C race: hardware set vs software clear.
13. IRQ enable/mask/status behavior.
14. terminal status persistence.
15. constrained-random mixed phase recipes.

## Recommended UVM agents

- APB master agent.
- Reactive sensor agent.
- Reactive excitation agent.

The sensor agent must model the level-based DONE/ACK contract, not a one-cycle asynchronous pulse.

## Recommended SVA targets

- trigger width equals programmed value;
- no trigger in WAIT phase;
- no trigger while not BUSY;
- excitation disabled outside SIGNAL execution;
- hard fault implies safe outputs;
- DONE/ABORTED/FAILED mutually exclusive;
- active recipe snapshot stable while BUSY;
- no second trigger until prior DONE has cleared;
- HW interrupt/error set dominates same-cycle W1C.
