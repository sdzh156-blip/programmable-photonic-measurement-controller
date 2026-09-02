# V1 -> V2 -> V2.1 Architecture Migration

## V1 -> V2

Removed / replaced:
- AHB-Lite CSR slave -> APB slave.
- monolithic measurement-control emphasis -> explicit sequencer + timing engine + pulse engine.
- CPU-like recipe ideas were rejected; phase descriptors remain bounded measurement configuration.

Retained:
- DARK / SIGNAL / WAIT phases;
- active configuration snapshot;
- sensor-ready / frame / excitation-ready timeouts;
- terminal DONE / ABORTED / FAILED status;
- event priority and safe-state behavior;
- W1C sticky error/interrupt state with hardware-set priority.

## V2.0 -> V2.1 review corrections

V2.0 used a synchronized DONE level plus one-cycle ACK and `WAIT_FRAME_CLEAR`. Review found that the return one-cycle ACK itself was not a robust contract for an asynchronous sensor. V2.1 therefore reuses the portfolio's established event CDC pattern:

```text
sensor frame completion
  -> source toggle
  -> 2FF synchronization
  -> synchronized change detection
  -> one-cycle local frame event
```

Consequences:
- remove `sensor_frame_ack_o`;
- remove `ST_WAIT_FRAME_CLEAR`;
- rename external completion input to `sensor_frame_done_toggle_async_i`;
- add `sync2_toggle_event.sv`;
- keep READY/FAULT as 2-FF synchronized persistent levels.

V2.1 also corrects three review findings:

1. **Consecutive SIGNAL stale READY:** each SIGNAL now requires READY-low re-arm before excitation enable, followed by a fresh READY-high qualification.
2. **Mixed persistent/command CSR:** `CTRL` now holds ENABLE only; `COMMAND` at `0x038` holds W1P START/ABORT.
3. **Fault diagnosis:** `DEVICE_STATUS` at `0x03C` exposes synchronized READY/FAULT levels.

Terminology is also tightened: the RTL implements **digital fault-safe shutdown / safe-state control**, not an independent physical laser-safety interlock.

## V2.1 design emphasis

- application-appropriate APB control plane;
- explicit measurement phase sequencing rather than a CPU instruction engine;
- deterministic timing and pulse generation;
- CDC mechanism selected by signal semantics: level vs event;
- clear software command semantics;
- explicit external interface assumptions;
- evidence-driven pre-DV review before UVM freeze.
