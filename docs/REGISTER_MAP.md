# PMC CSR Register Map

All legal CSR accesses are 32-bit word-aligned AHB-Lite accesses.

| Offset | Register | Access | Description |
|---:|---|---|---|
| `0x000` | `CTRL` | RW/W1P | `ENABLE[0]`, `START[1]`, `ABORT[2]` |
| `0x004` | `STATUS` | RO | `BUSY[0]`, `DONE[1]`, `ABORTED[2]`, `FAILED[3]`, `ENABLE_STATUS[4]` |
| `0x008` | `PHASE_COUNT` | RW | Valid range 1..8 |
| `0x00C` | `SENSOR_READY_TIMEOUT` | RW | Sensor-ready timeout cycles |
| `0x010` | `FRAME_TIMEOUT` | RW | Frame completion timeout cycles |
| `0x014` | `EXC_READY_TIMEOUT` | RW | Excitation-ready timeout cycles |
| `0x018` | `MEASUREMENT_ID` | RO | Increments on accepted START |
| `0x01C` | `CURRENT_PHASE` | RO | Phase/frame observability |
| `0x020` | `ERROR_STATUS` | W1C/RO | Sticky error bits |
| `0x024` | `INT_STATUS` | W1C/RO | Sticky interrupt pending bits |
| `0x028` | `INT_ENABLE` | RW | Interrupt enable bits |
| `0x02C` | `VERSION` | RO | `0x0001_0000` |
| `0x040..0x07C` | `PHASE0..7_CFG/SETTLE` | RW | Recipe programming bank |

## Phase descriptor

`PHASEn_CFG`:

- `[1:0] TYPE`: `00=DARK`, `01=SIGNAL`, `10=WAIT`, `11=RESERVED`
- `[15:8] FRAME_NUM`: DARK/SIGNAL = 1..255, WAIT = 0
- all remaining bits are reserved and read as zero

`PHASEn_SETTLE[31:0]` is an unsigned cycle count.

## ERROR_STATUS

| Bit | Meaning | Class |
|---:|---|---|
| 0 | CONFIG_ERROR | Non-fatal |
| 1 | CMD_REJECT | Non-fatal |
| 2 | SENSOR_READY_TIMEOUT | Fatal |
| 3 | SENSOR_FRAME_TIMEOUT | Fatal |
| 4 | SENSOR_ERROR | Fatal |
| 5 | EXC_READY_TIMEOUT | Fatal |
| 6 | EXCITATION_FAULT | Fatal |
| 7 | ILLEGAL_STATE | Fatal |

## INT_STATUS / INT_ENABLE

| Bit | Source |
|---:|---|
| 0 | MEAS_DONE |
| 1 | ABORT_DONE |
| 2 | CONFIG_ERROR |
| 3 | CMD_REJECT |
| 4 | SENSOR_READY_TIMEOUT |
| 5 | SENSOR_FRAME_TIMEOUT |
| 6 | SENSOR_ERROR |
| 7 | EXC_READY_TIMEOUT |
| 8 | EXCITATION_FAULT |
| 9 | ILLEGAL_STATE |

`irq_o = |(INT_STATUS & INT_ENABLE)`.

For both `ERROR_STATUS` and `INT_STATUS`, a hardware set wins over a software W1C in the same cycle.
