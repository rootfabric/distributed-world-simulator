# V0-P4 prebuild no-runtime-diff assertion

At this pre-build checkpoint, P4 intentionally changes only:

- `docs/**` P4 evidence/checkpoint files;
- `tests/construction/test_v0_p4_real_resource_exact_consume_contract.gd` (+ UID);
- `RUN_V0_P4_EXACT_CONSUME_CONTRACT.ps1`.

No `scripts/**`, `config/resources/**`, `config/worlds/**`, `project.godot`, `main.tscn`, network protocol file, persistence runtime, Construction production implementation, or M4 production implementation is intentionally changed.

This assertion is a review aid, not a substitute for comparing the exact branch head against `ef3ad5f0afc433802d639171d938e4720b3a46ec`.
