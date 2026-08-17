# ECO VIS2.2-D — Ubuntu validation checkpoint

Дата: 2026-08-17

Ветка:

`feature/eco-vis2-2-replicated-causal-observatory`

Validated code-under-test:

`7bf0e83ed6c6907731022ff4d372980e596b2135`

Godot:

`4.7.1.stable.double.custom_build.a13da4feb`

Платформа:

Ubuntu/Linux, native double-precision Godot build.

## Контекст repair

Предыдущий VIS2.2-D candidate `ac91a7d193ce144e32ca56b5be9e4d960be95355` был заблокирован реальным Ubuntu parser/runtime preflight:

- collision D dependency symbols с parent inheritance chain (`ObservatoryPanel`, `TraceAdapter`, `TreatmentRunner`);
- inline PH5 guard вызывал `bool(...)` для отсутствующего dynamic property и получал `Nonexistent 'bool' constructor`;
- последующий `set_replicate_count_for_next_fork` failure был каскадным следствием того, что root D script не скомпилировался.

Repair lineage:

- `afdf819897afde2d64dbca2d5c43a547284de05f` — namespace VIS2.2-D dependencies через stage-local `VIS22D_*` symbols;
- `6052c51596e0f45f27898ad4dace74dfd88ce0f2` — harden inline PH5 guard (`lab.get("_vis22d_active") != true`);
- `7bf0e83ed6c6907731022ff4d372980e596b2135` — native Ubuntu focused gate `RUN_ECO_VIS2_2D_UBUNTU_TEST.sh`.

## Реальный Ubuntu validation run

Перед запуском Godot import завершился успешно:

- `Godot import exit code: 0`
- `IMPORT: OK`

Import создал 259 untracked `*.gd.uid` sidecar files; validation checkout разрешил только эти generated UID files и не обнаружил других локальных изменений.

Exact branch/ref:

- remote HEAD: `7bf0e83ed6c6907731022ff4d372980e596b2135`
- local detached HEAD: `7bf0e83ed6c6907731022ff4d372980e596b2135`

Native Ubuntu gate:

`bash ./RUN_ECO_VIS2_2D_UBUNTU_TEST.sh "$godot_bin"`

Observed result:

- exact Godot identity: PASS
- isolated ecology dependency graph: PASS
- parser preflight: PASS
- strict shutdown leak gate active (ObjectDB + RID + resources + StringName + verbose smoke)
- integrated observatory smoke: `PASS (63 assertions)`
- final: `ECO.VIS2.2-D Ubuntu focused gate: PASS`

No parser errors, runtime errors, ObjectDB/RID/resource/StringName shutdown leak diagnostics were observed in the reported run.

## Status

`UBUNTU_RUNTIME_VALIDATED_CANDIDATE`

This checkpoint is evidence-only. It does not modify simulation/runtime code and does not constitute merge/global acceptance by itself.
