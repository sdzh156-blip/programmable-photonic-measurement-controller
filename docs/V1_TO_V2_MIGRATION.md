# V1 -> V2 Architecture Migration

## Removed / replaced

- AHB-Lite CSR slave -> APB slave.
- monolithic measurement-control emphasis -> explicit sequencer + timing engine + pulse engine.
- one-cycle frame-done assumption -> synchronized level DONE/ACK handshake.

## Retained concepts

- DARK / SIGNAL / WAIT phases.
- active configuration snapshot.
- sensor-ready / frame / excitation-ready timeouts.
- terminal DONE / ABORTED / FAILED status.
- event priority and safe state.
- W1C sticky error/interrupt state with hardware-set priority.

## New V2 design emphasis

- application-appropriate APB control plane;
- mature open-source reference survey before RTL design;
- explicit optical pulse/timing generation;
- robust asynchronous level synchronization contract;
- clearer verification boundary and UVM handoff.
