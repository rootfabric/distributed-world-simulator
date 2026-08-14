# ECO P4.5 — Region Ownership / Server Handoff — PRE-ACCEPTANCE CANDIDATE

Статус: `CANDIDATE_TARGETED_EXACT_ATTACHED_GODOT_PASS_P4_4_ACCEPTANCE_AND_FULL_CHAIN_GATE_PENDING`.

P4.5 реализован поверх frozen P4.4 aggregate `4960096ae214a3b5f33a6c2507d0edb26348a0820b3469afc42eb92bdc62c1e2`, но P4.4 на момент этого candidate ещё не lifecycle-accepted. Поэтому это опережающая реализация, а не открытие canonical P4.5 gate.

## Контракт

- один canonical owner server на RegionState snapshot;
- integer `ownership_epoch` используется как fencing token и растёт ровно на 1 при handoff;
- `ownership_hash` связывает region, owner, epoch и exact P4.4 `snapshot_hash`;
- canonical snapshot commit выполняется только по exact CAS claim: owner + epoch + ownership hash + snapshot hash;
- `prepare_handoff` не мутирует source state;
- handoff package привязан к exact source ownership и exact snapshot;
- target acceptance сохраняет snapshot и переводит epoch `N -> N+1`;
- старый source claim после handoff fenced;
- replay одного handoff package fail-closed;
- handoff package, подготовленный до snapshot mutation, становится stale;
- для одинакового future snapshot путь `advance -> handoff` сходится с `handoff -> advance` к одному target ownership hash;
- wall clock, lease duration, socket/address и process-local IDs не входят в canonical identity.

## Exact attached-Godot targeted evidence

Godot: `4.7.1.stable.double.custom_build.a13da4feb`.

`PASS (52 assertions) x3`, fresh-process logs byte-identical.

```text
log_sha256=15ed9204b5da0ca95594c8f018f07a12385e237cbfc5404aff1a013e2628afaf
aggregate=c966d60e6101e934f63945c7a5ea834ecf6e61646d3aaf54fca4657ccc7b5419
source_ownership=f89f476285a40fdf0fe0f79557001f536fff4df2c8da9085cd5ecffce314d1de
handoff=3d9e94ffddc7f9cf3f6e765c08b620a2bf3436b751fbadcedb694fe5c9e2624c
target_ownership=b7d0edb5c943dbe0f1ba62066dd94c5a5d84eff82177897174ba37f984b734c4
```

Targeted harness использует минимальный P4.4 validator stub с **реальным frozen P4.4 snapshot hash**. Полный committed P3.1→P4.5 gate должен выполняться только после P4.4 acceptance.

P4.6 Interest + Client Read Model остаётся CLOSED.
