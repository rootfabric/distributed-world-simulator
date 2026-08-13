# ECO P3.8 — Deterministic Ecosystem Persistence — CANDIDATE

Статус: `IMPLEMENTATION CANDIDATE / TARGETED LINUX PASS / P3.7 ACCEPTANCE + EXACT WINDOWS CANONICAL PENDING`.

## Scope

P3.8 завершает P3 implementation chain детерминированным checkpoint/state codec поверх immutable P3.7 result. Текущий P3.7 result уже рекурсивно содержит P3.6 disturbance, P3.5 seasonal environment, P3.4 environmental gradient, P3.3 spatial state и P3.2 ancestry, поэтому persisted current state содержит полный необходимый P3 simulation state для продолжения coexistence trajectory.

Checkpoint state содержит:

```text
schema/version
P3.7 candidate aggregate identity
root P3.7 result hash
generation
current validated P3.7 result
current P3.7 result hash
semantic state hash
```

`advance(state, N)` детерминированно продолжает P3.7 trajectory из `next_community`, не используя RNG и не завися от wall clock/FPS/timestep history.

## Checkpoint envelope

Binary payload создаётся exact Godot Variant serialization (`var_to_bytes`) после полной semantic validation. Перед payload записывается fail-closed envelope:

```text
DWS_ECO_P3_8_CHECKPOINT_V1
payload_sha256=<sha256 raw payload>
payload_bytes=<exact byte count>
state_hash=<semantic state hash>

<binary payload>
```

До `bytes_to_var` проверяются magic, exact payload length и SHA-256, поэтому truncated/trailing/digest-tampered checkpoints reject без попытки decode. После decode повторно выполняется P3.8 + embedded P3.7 semantic validation.

## Targeted exact-Godot evidence

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
P3.7 parent regression = PASS (64 assertions)
P3.8 parser/preload = PASS
P3.8 fresh A/B/C = PASS (52 assertions each; byte-identical logs)
P3.8 cross-process writer = PASS
P3.8 cross-process resume = PASS

aggregate_hash=6132820a5c6597765b4f3abeeb8cf9fc9e6aaffb90ba83a1263997b17fc6f3a0
initial_state_hash=6070494e77828f4e25a00eed9695de9e87fdf94e472f5018d660a7c20b15d7fb
cut_state_hash=07f6ecaa00d508b87042948a23cf4e0eaa600d79a8229e16b859c461dada509d
final_state_hash=1395e6cdfc6dc5ea963b0d077fc00c618645c8866a7e47e822bcbdd98e429cf9
checkpoint_sha256=1722f3ce96a8244bfaf2f8295c162b51552c6c5cc4cfd1126b40691a37bab367
final_p3_7_result_hash=abf4251fd456117c54b4b69954d5fa3027b80085e1beac1eee347d0c604ad5b5
parent_p3_7=ef05ffb15d33819d3a6c4a1d534670e570ecb2ec674ad4a232e151e680a0e53a
source_p3_7=d3a5755300e9e19f87adc2406a420ae6ea2789f0d503542453435de83e6218a9
fresh_process_log_sha256=8f6fec6eaf0394950820fc5869b233a1efcc562dbd96f20d95df9a7b173fb876
```

Cross-process proof делает настоящий file boundary: процесс A сохраняет generation 5, завершается; новый Godot process B загружает checkpoint и продолжает до generation 12. Его final state hash в точности равен independently computed uninterrupted generation-12 state.

Дополнительно доказаны два разных checkpoint cuts (`5+7` и `9+3`) с одним final state, реальный `FileAccess` save/load, exact typed round-trip, byte-identical reserialization, embedded P3.3→P3.7 ancestry, empty ecosystem persistence, RNG non-consumption и fail-closed malformed/tampered envelope/state.

## Gate

`RUN_ECO_P3_8_TESTS.ps1` fail-closed требует `P3.7 = ACCEPTED*`, затем выполняет accepted P3.7 parent regression, два full fresh processes и отдельный cross-process writer/resume proof.

Targeted Linux PASS не является Windows canonical acceptance. P3 implementation chain теперь complete-as-candidate, но весь P3 route не считается canonically complete до последовательного acceptance P3.3→P3.8.
