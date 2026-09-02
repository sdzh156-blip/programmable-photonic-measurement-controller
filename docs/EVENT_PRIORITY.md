# PMC V2.1 Event Priority and Corner Cases

Global execution priority after reset:

1. illegal-state / synchronized hard fault
2. software ABORT or ENABLE clear while BUSY
3. successful handshake / phase or measurement completion
4. timeout expiry
5. normal FSM transition

Command-reject/configuration errors are non-fatal side events and do not override an already-running measurement outcome.

| Event A | Event B | Frozen result |
|---|---|---|
| frame-done toggle event | FRAME timeout | frame completion wins |
| sensor_ready | sensor-ready timeout | ready wins |
| excitation_ready low re-arm | excitation-ready timeout | re-arm success wins |
| excitation_ready high qualification | excitation-ready timeout | qualification success wins |
| frame completion | software abort | abort wins |
| frame completion | sensor error | sensor error wins |
| frame completion | excitation fault | excitation fault wins |
| timeout | software abort | abort wins |
| software abort | excitation fault | excitation fault wins |
| last-frame completion | excitation fault | fault; no MEAS_DONE |
| SW W1C | HW new set | HW set wins |
| BUSY START | current measurement | CMD_REJECT; current measurement continues |
| COMMAND START+ABORT in IDLE | same write | no start; CMD_REJECT |
| COMMAND START+ABORT in BUSY | same write | abort; START rejected |
| reset | any event | reset wins |

## Verification-important boundaries

- `FRAME_COUNT=1`: exactly one trigger with `frame_index=0`.
- `PHASE_TIME=0`: no programmable settle/wait delay; fixed state-transition latency may still exist.
- `PHASE_TIME=1`: one full programmable wait cycle.
- programming-bank writes while BUSY must not alter active phase/frame/timing behavior.
- every SIGNAL phase starts from excitation disabled, observes synchronized READY low, then enables excitation and accepts a fresh READY high before settling/capture.
- SIGNAL -> SIGNAL therefore performs a fresh low/high READY qualification; excitation is not intentionally held continuously across phase boundary.
- a frame-completion toggle change is converted to one local pulse; completion pulses outside `WAIT_FRAME` are ignored.
- no DONE/ACK level-clear sequence exists in V2.1.
- source toggle reset/baseline is part of the external interface contract and must be verified in the reactive sensor model.
- trigger receiver minimum-pulse-width is an integration constraint; programmed width must satisfy it.
