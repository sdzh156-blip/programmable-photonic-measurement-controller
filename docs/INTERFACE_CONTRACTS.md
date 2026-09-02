# PMC V2 External Interface Contracts

## APB

- software master owns APB sequencing;
- one 32-bit word per access;
- no byte strobes in V2;
- zero wait-state peripheral;
- illegal/misaligned access reports `PSLVERR`.

## Sensor

`ready`, `done`, and `error` are treated as asynchronous external levels and synchronized into `pclk_i`.

### Ready

- high means the sensor can accept a new trigger;
- PMC only consumes READY in `WAIT_SENSOR_READY`.

### Trigger

- pulse width is programmable;
- frame timeout is not armed until the trigger pulse is complete.

### Frame done

- sensor asserts DONE and holds it high;
- PMC asserts one-cycle ACK after accepting the completion;
- sensor deasserts DONE after observing ACK;
- PMC waits for synchronized DONE-low before arming the next frame.

### Sensor error

- hard fault level;
- must remain asserted long enough to cross the 2-FF synchronizer;
- terminates the measurement with FAILED status.

## Excitation

### Enable

- driven only for SIGNAL phases;
- forced low on completion, abort, timeout or hard fault.

### Ready

- high means the enabled excitation source is stable and capture may proceed after the configured settle interval.
- deassert when excitation is disabled.

### Fault

- hard fault level;
- terminates measurement and forces excitation off.
