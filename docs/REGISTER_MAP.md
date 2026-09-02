# PMC V2 Register Map

All addresses are offsets inside the PMC APB window.

| Offset | Name | Access | Description |
|---:|---|---|---|
| 0x000 | CTRL | RW/W1P | ENABLE[0], START[1], ABORT[2] |
| 0x004 | STATUS | RO | BUSY[0], DONE[1], ABORTED[2], FAILED[3] |
| 0x008 | PHASE_COUNT | RW | valid 1..8 |
| 0x00C | SENSOR_READY_TIMEOUT | RW | cycles |
| 0x010 | FRAME_TIMEOUT | RW | cycles |
| 0x014 | EXCITATION_READY_TIMEOUT | RW | cycles |
| 0x018 | TRIGGER_WIDTH | RW | `[15:0]`, cycles, capture requires nonzero |
| 0x01C | MEASUREMENT_ID | RO | increments on accepted START |
| 0x020 | CURRENT_PHASE | RO | current active phase index |
| 0x024 | CURRENT_FRAME | RO | current active frame index |
| 0x028 | ERROR_STATUS | W1C/RO | sticky error bits |
| 0x02C | INT_STATUS | W1C/RO | sticky interrupt pending bits |
| 0x030 | INT_ENABLE | RW | interrupt enable mask |
| 0x034 | VERSION | RO | `0x0002_0000` |
| 0x038..0x03C | - | - | unmapped |
| 0x040 | PHASE0_CFG | RW | TYPE + FRAME_COUNT |
| 0x044 | PHASE0_TIME | RW | settle/wait cycles |
| 0x048 | PHASE1_CFG | RW | TYPE + FRAME_COUNT |
| 0x04C | PHASE1_TIME | RW | settle/wait cycles |
| 0x050 | PHASE2_CFG | RW | TYPE + FRAME_COUNT |
| 0x054 | PHASE2_TIME | RW | settle/wait cycles |
| 0x058 | PHASE3_CFG | RW | TYPE + FRAME_COUNT |
| 0x05C | PHASE3_TIME | RW | settle/wait cycles |
| 0x060 | PHASE4_CFG | RW | TYPE + FRAME_COUNT |
| 0x064 | PHASE4_TIME | RW | settle/wait cycles |
| 0x068 | PHASE5_CFG | RW | TYPE + FRAME_COUNT |
| 0x06C | PHASE5_TIME | RW | settle/wait cycles |
| 0x070 | PHASE6_CFG | RW | TYPE + FRAME_COUNT |
| 0x074 | PHASE6_TIME | RW | settle/wait cycles |
| 0x078 | PHASE7_CFG | RW | TYPE + FRAME_COUNT |
| 0x07C | PHASE7_TIME | RW | settle/wait cycles |

## PHASEn_CFG format

```text
31                       16 15        8 7        2 1      0
+--------------------------+-----------+----------+--------+
|       reserved = 0       |FRAME_COUNT|reserved  | TYPE   |
+--------------------------+-----------+----------+--------+
```

TYPE:

- `00` DARK
- `01` SIGNAL
- `10` WAIT
- `11` reserved/illegal
