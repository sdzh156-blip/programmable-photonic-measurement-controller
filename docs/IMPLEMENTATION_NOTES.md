# Implementation Notes

This RTL is the first implementation baseline derived from the PMC Function SPEC V1.1 design-review decisions.

## Verification-sensitive areas

The following behaviors should receive dedicated UVM/SVA coverage in the next project phase:

1. AHB-Lite back-to-back write/read/mixed transfer pairing.
2. Two-cycle AHB ERROR response for bad size, misalignment, and unmapped addresses.
3. `SETTLE=0/1/N` and timeout `1/N` boundaries.
4. `frame_done + timeout` on the same deadline edge (frame_done wins).
5. hard fault + frame_done (fault wins).
6. abort + frame_done (abort wins).
7. HW interrupt/error set + SW W1C (HW set wins).
8. BUSY-time recipe rewrites proving active snapshot immutability.
9. SIGNAL->SIGNAL excitation hold and SIGNAL->DARK/WAIT/end deassert timing.
10. Trigger count exactly equals `FRAME_NUM` and no trigger occurs while a frame is outstanding.

## Tool note

The repository includes a VCS-oriented smoke-test Makefile. The current generation environment did not provide a Verilog compiler, so final compile/elaboration must be run in the user's existing VCS environment before the RTL baseline is tagged as compile-clean.
