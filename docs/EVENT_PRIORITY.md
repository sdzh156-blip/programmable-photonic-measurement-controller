# Event Priority and Corner Cases

Global execution priority after reset:

1. illegal-state / hard fatal fault
2. software ABORT or ENABLE clear while BUSY
3. successful handshake / phase or measurement completion
4. timeout expiry
5. normal FSM transition

Command-reject/configuration errors are non-fatal side events and do not override an already-running measurement outcome.

| Event A | Event B | Frozen result |
|---|---|---|
| `sensor_frame_done` | FRAME timeout | Frame done wins |
| `sensor_ready` | sensor-ready timeout | Ready wins |
| `excitation_ready` | excitation-ready timeout | Ready wins |
| `sensor_frame_done` | software abort | Abort wins |
| `sensor_frame_done` | sensor error | Sensor error wins |
| `sensor_frame_done` | excitation fault | Excitation fault wins |
| timeout | software abort | Abort wins |
| software abort | excitation fault | Excitation fault wins |
| last-frame completion | excitation fault | Fault; no MEAS_DONE |
| SW W1C | HW new set | HW set wins |
| BUSY START | current measurement | CMD_REJECT; current measurement continues |
| START + ABORT in IDLE | same CTRL write | No start; CMD_REJECT |
| START + ABORT in BUSY | same CTRL write | Abort; START rejected |
| reset | any event | Reset wins |

## Verification-important boundaries

- `FRAME_NUM=1`: exactly one trigger with `frame_index=0`.
- `SETTLE=0`: no programmable wait; fixed FSM latency may still exist.
- `SETTLE=1`: at least one full programmable wait cycle.
- programming-bank writes while BUSY must not alter active phase/frame/timing behavior.
- SIGNAL -> SIGNAL may keep excitation high; SIGNAL -> DARK/WAIT/end disables it at phase terminal edge.
- stale frame-done outside WAIT_FRAME is ignored.
