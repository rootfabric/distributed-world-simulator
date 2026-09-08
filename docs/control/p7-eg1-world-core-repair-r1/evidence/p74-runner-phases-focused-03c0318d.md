# P7.4 runner-phases focused validation — candidate 03c0318d

Executed on the local Ubuntu closure machine before full-suite dispatch.

## Focused recording-executor orchestration test

```
command: python3 docs/control/p7-eg1-world-core-repair-r1/test_p74_runner_phases.py
exit: 0
result: P74_RUNNER_PHASES_ORCHESTRATION_PASS
```

Proved: 330 summary stages, three ordered native P7.4 phase invocations
(`-- --phase=seed|recover-deliver|recover-replay`), unchanged ordinary
script invocations, failure propagation bound to the failing phase stage
(exit 17, no recover-replay, no main_scene_cli_all), final aggregate present.

## Real three-phase run on the pinned engine

Engine: 4.7.1.stable.double.custom_build.a13da4feb, SHA-256 bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
Isolated profile: fresh temp HOME/XDG roots; PLANET_SIMULATOR_INVENTORY_PROFILE=planet_default; LIBGL_ALWAYS_SOFTWARE=1.

```text
V0-P7.4 seed: PASS (21 assertions, 0 failures)
V0-P7.4 recover-deliver: PASS (25 assertions, 0 failures)
V0-P7.4 recover-replay: PASS (17 assertions, 0 failures)
```

This is focused orchestration evidence only; it does not replace the full
world/core regression or the P7 29-leaf train on the exact candidate.
