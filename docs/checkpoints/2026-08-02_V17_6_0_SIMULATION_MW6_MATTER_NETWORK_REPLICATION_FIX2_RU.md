# Checkpoint v17.6.0 — MW6 matter network replication fix2

```text
checkpoint: v17.6.0-simulation-mw6-matter-network-replication
delivery: fix2
build_id: mw6-matter-network-replication-fix2
base_delivery: MW6 fix1
branch: feature/mw6-matter-network-replication
status: CANDIDATE FOR INDEPENDENT REVIEW
```

## Причина fix2

MW6 `fix1` прошёл focused-профиль: `130 assertions PASS` за `17.900 s`. Однако M6 standalone был заблокирован parser errors в добавленном resync-contract:

```text
Cannot infer the type of "initial" variable
Cannot infer the type of "join_b" variable
```

`_new_service()` может вернуть `null`, поэтому его результат остаётся Variant и GDScript не выводит тип последующих вызовов через `:=`.

## Исправление

```gdscript
var initial: Dictionary = service.create_snapshot()
var join_b: Dictionary = service.join(...)
```

Других `:=`-выражений, добавленных в этот M6 test через nullable `_new_service()`, нет.

## Не изменено

- MW6 matter authority и replication stream;
- `MultiplayerGameplayReplicaStore`;
- bounded graphical snapshot resync из fix1;
- M6 server persistence/replay semantics;
- focused assertion topology;
- production Moon и world catalog.

## Требуемая проверка

```text
MW6 focused:     130/130 PASS
M6 standalone:   10/10 PASS
M6 process:      128 assertions PASS
A3 full profile: PASS три последовательных запуска
MW5:             142/142 PASS
MW4:             187/187 PASS
MW3:             7519/7519 PASS
MW2:             7470/7470 PASS
MW1:             3685/3685 PASS
MW0:             2011/2011 PASS
git diff --check: PASS
```
