# ECO A14.7 E3 Linux A13 Fidelity SIGSEGV — forensic work order

Immutable product subject: HEAD d2ddebcdf5f6aecec85e7d85772f30a15ff3f748, TREE 910833e082f376ea7d0ed0b14530edddd1503ef8; PR #856. Main aac301b9a9a89e027f6d99864437eb750a4202ca remains untouched.

Original fail: A13 Fidelity Linux Double job 120867298535 in run 40092302959, pinned Godot 4.7.1 Double SHA bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7, native SIGSEGV (-11), after successful 23.88s cold import and 4.224s fidelity test. Test log contains only engine startup, 0 checks and no GDScript assertion. Windows Double and Portable successful. Tracked source identity clean, 0 drift.

Action A: rerun ONLY the exact failed Linux job on unchanged E3 head; no disabling gates.
Action B: this direct-child diagnostic branch exports source to a GitHub artifact for local pinned Double reproduction; hash/check exact subject.
Action C: self-hosted native Linux exact import, original unmodified fidelity test, capture exit, logs, CPU/environment and gdb backtrace (if available). Require exit zero AND exact PASS marker. Do not convert crashes to green.
Action D: if reproducible, isolate native stage with additional test-only markers/probes and use independently verified RED to GREEN. Preserve full A13 fidelity contract, A9 exact replay, checksum, source and A8. Do not edit product biology on speculative cause; no merger until Linux equivalent exact acceptance.
Action E: finish queued native Linux regressions; do not stop self-hosted runner. All pinned Windows E3/Product/independent PASS remain frozen.

This diagnostic branch is NOT a claim of fix. READY_FOR_MERGE=false.
