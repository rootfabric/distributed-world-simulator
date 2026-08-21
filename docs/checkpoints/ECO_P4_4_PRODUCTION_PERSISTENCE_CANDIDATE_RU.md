# ECO P4.4 — Production Persistence — CANDIDATE

Статус: `CANDIDATE_TARGETED_EXACT_ATTACHED_GODOT_PASS_FULL_CHAIN_GATE_PENDING`.

Parent P4.3: `4bdfd994a27ef15ff4010643e35f4652a0a2f3fdb2d3fcfa6b86b816b14cca62` — ACCEPTED.

P4.4 вводит **первый production-owned persistence format** для ecology region. P3.8 остаётся research/reference codec и не становится production storage contract автоматически.

## Контракт

- production snapshot хранит exact P4.3 Catch-up state вместе с derived region/clock/catch-up identities;
- snapshot имеет собственный `snapshot_hash` и pin на accepted P4.3 aggregate;
- bytes имеют magic `DWS_ECO_P4_4_REGION_SNAPSHOT_V1`, `format_version=1`, payload SHA-256, exact byte count и snapshot hash;
- deserialization fail-closed проверяет envelope до использования вложенного state;
- pending backlog и fractional observed horizon переживают restart без semantic drift;
- current format migration — identity; неизвестные/будущие версии reject до появления явной migration function;
- P3.8 research checkpoint magic специально не принимается как P4.4 production snapshot;
- слой не читает wall clock и не владеет server handoff/network/client authority.

## Targeted exact-Godot evidence

Exact Godot: `4.7.1.stable.double.custom_build.a13da4feb`.

`PASS (45 assertions) x3`; fresh-process logs byte-identical.

```text
log_sha256=9a85c1703469ffa5d0cdf2fd8535082ebe4da37aedafbc689745ea9647d4d64a
aggregate_hash=3967ac8f07ec44d48a8f6b8580afbf9f4f3c25cff9a07931fece0dc7d7184c33
snapshot_hash=49b65f80bb33115ee0280b759b1da0176f3756989a7d623a9f95aa02d003fa25
file_sha256=d9ba432abc3253c918e459fb0f2747970ca375cc60696872b7b10329aa5fae43
resumed_catchup_hash=fe1b7911ef74d3e39224311ab1dffb17d69efe23c3959cc13f9732f69297af18
```

Targeted harness использует deterministic P3 persistence stub только для P4 interface semantics. Full lifecycle acceptance требует committed real-chain run.

## Frozen full-chain semantic identities

```text
aggregate_hash=4960096ae214a3b5f33a6c2507d0edb26348a0820b3469afc42eb92bdc62c1e2
snapshot_hash=c6ee61dc4250fcd22b762902ff35354957c884c8b1818aed8209fe4f6c829006
resumed_catchup_hash=cc2a4815e1eae75b879ea52d8ba404880c69344928f953e8aaa38bd062b1ce3a
parent_p4_3=4bdfd994a27ef15ff4010643e35f4652a0a2f3fdb2d3fcfa6b86b816b14cca62
```

P4.5 Region Ownership / Server Handoff остаётся CLOSED до отдельного P4.4 lifecycle acceptance.
