# PMC V2.1 External Interface Contracts

## APB

- software master owns APB sequencing;
- one 32-bit word per access;
- no byte strobes in V2.1;
- zero wait-state peripheral;
- illegal/misaligned access reports `PSLVERR`;
- `CTRL` contains persistent ENABLE only;
- `COMMAND` contains W1P START/ABORT only.

## CDC classification

PMC does not apply one CDC mechanism to every external signal. Signals are classified by semantics:

- persistent state levels -> 2-FF synchronizer;
- one-shot frame-completion event -> source toggle + 2-FF + destination change detector / pulse regeneration.

This avoids relying on an arbitrarily narrow asynchronous pulse and avoids a return ACK pulse that an asynchronous receiver might miss.

## Sensor

### Ready

`sensor_ready_async_i` is an asynchronous persistent level and is synchronized with 2 FFs.

- high means the sensor can accept a new trigger;
- PMC consumes READY only in `WAIT_SENSOR_READY`;
- READY is not itself a frame-completion indication.

### Trigger

`sensor_trigger_o` is generated in the PMC clock domain and its width is programmable in `pclk_i` cycles.

The receiving sensor/integration must be able to detect the configured trigger width. The system integrator shall choose a width that meets the receiver's minimum pulse-width requirement. V2.1 does not implement an additional return handshake for trigger delivery.

Frame timeout is armed only after the trigger pulse completes.

### Frame completion toggle

`sensor_frame_done_toggle_async_i` is an asynchronous **event toggle**, not a DONE level.

Source contract:

1. initialize the toggle to 0 before normal PMC operation/reset release;
2. keep it stable between frame-completion events;
3. invert it exactly once when a triggered frame completes;
4. do not generate another completion toggle until the next frame transaction.

PMC behavior:

```text
source completion
      -> toggle bit changes
      -> 2-FF synchronization
      -> compare with delayed synchronized copy
      -> one-cycle frame_done_event in pclk domain
```

There is no `sensor_frame_ack_o` and no `WAIT_FRAME_CLEAR` state. A regenerated event is consumed only in `WAIT_FRAME`; out-of-state events are ignored.

The toggle protocol assumes distinct source changes are spaced sufficiently for the 2-FF destination synchronizer to observe them separately. Normal frame sequencing satisfies this by permitting one completion per triggered frame.

### Sensor error

`sensor_error_async_i` is an asynchronous persistent hard-fault level synchronized through 2 FFs. It must remain asserted long enough to cross the synchronizer. A synchronized assertion terminates an active measurement with FAILED status and fault-safe outputs.

## Excitation

### Enable

`excitation_enable_o` is driven only during SIGNAL execution after re-arm qualification and is forced low on phase completion, measurement completion, abort, timeout or hard fault.

### Ready

`excitation_ready_async_i` is an asynchronous persistent level synchronized through 2 FFs.

Every SIGNAL phase performs fresh qualification:

```text
excitation_enable = 0
        -> wait READY_sync = 0
        -> excitation_enable = 1
        -> wait READY_sync = 1
        -> settle
        -> capture
```

Both waiting-for-low and waiting-for-high are bounded by `EXCITATION_READY_TIMEOUT`. This prevents stale READY from a previous SIGNAL phase from being accepted as a new qualification.

### Fault

`excitation_fault_async_i` is a persistent hard-fault level synchronized through 2 FFs. A synchronized assertion terminates the active measurement and forces excitation off.

## Fault-safe scope

PMC implements **digital fault-safe shutdown / safe-state control**. Because external faults are synchronized, response includes CDC latency. This logic is not an independent physical laser/personnel-safety interlock; such an interlock must be implemented separately at system level when required.
