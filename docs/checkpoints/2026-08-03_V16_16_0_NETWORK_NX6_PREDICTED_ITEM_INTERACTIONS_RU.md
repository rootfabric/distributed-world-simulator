# Checkpoint v16.16.0 — Network NX6 Predicted Item Interactions

```text
stage:      NX6 — Predicted Item Interactions
delivery:   fix3
branch:     feature/nx6-predicted-item-interactions
base:       c727b1cf25b4e5916098a057b89b7fa1eb878dc6
base gate:  NX5 fix1 — ACCEPTED
decision:   ACCEPTED
frozen:     true
```

**Implementation head до acceptance-коммита:** `daca47edb47b0fde71b0be08224e7536545dabaf`

## Причина fix3

Fix2 исправил зависимую цепочку placement→mount→detach и реализовал `bridge.stop()`, но вызов cleanup находился только в test-only subclass. Реальная `playground.tscn` продолжала использовать базовый `playground_runtime.gd`, который освобождал bridge без stop.

## Исправления fix3

- базовый production `playground_runtime.gd` вызывает `_m7_item_bridge.stop("NX6_PLAYGROUND_UNLOAD")`;
- stop выполняется до отключения runtime-сигналов, обнуления runtime и освобождения bridge;
- `playground.tscn` остаётся привязана к обычному production runtime;
- M7 multiprocess client загружает и инстанцирует реальную `res://scenes/testing/playground.tscn`;
- process flow больше не использует `nx6_lifecycle_safe_playground_runtime.gd`;
- apply scripts удаляют оставшийся после fix2 test-only wrapper и его UID;
- integration загружает реальную сцену, проверяет её script binding и вызывает production `prepare_for_unload()` с stop probe;
- authoritative completion, placement ghost и server-generated mount identity из fix2 сохранены без изменения protocol hash.

## Проверяемый production-порядок

```text
item_gameplay save
→ bridge.stop("NX6_PLAYGROUND_UNLOAD")
→ runtime signal disconnect
→ presenter cleanup
→ runtime null
→ adapter null
→ bridge null
```

## Основание независимой приёмки

Полная независимая матрица fix2 прошла без runtime-регрессий; единственным блокером оставалось отсутствие `bridge.stop()` в фактическом production unload path. Fix3 изменил только этот lifecycle path и добавил тест реальной `playground.tscn`, не меняя protocol hash, prediction journal, completion mailbox или authoritative item semantics.

### Независимая полная матрица до fix3

```text
Archive safety / manifest / replay: PASS
Editor import:                      PASS
NX6 contracts:                      940 assertions PASS
NX6 integration fix2:                55 assertions PASS
M7 playable contracts:               63 assertions PASS
M7 graphical multiprocess:           51 assertions PASS
M7 recovery:                          36 assertions PASS
NX5 contracts:                     6 104 assertions PASS
NX5 integration:                      49 assertions PASS
M3 contracts:                         77 assertions PASS
M4 playground:                        23 assertions PASS
Conditioned ENet:                     27 assertions PASS
NX2 physical ENet:                    66 assertions PASS
JSON / PowerShell / bash:            PASS
git diff --check:                    PASS
Conflict markers:                      0
Remaining Godot/Xvfb:                  0
```

### Точечная проверка fix3

```text
Fix3 archive SHA-256:              3DFCA972801EF619C6FB774C22A4562B8E65B27C23C4939EF2A05BCECA5F90C0
Editor import:                     PASS
NX6 contracts:                     940 assertions PASS
NX6 integration fix3:               66 assertions PASS
Production playground source parse: PASS
Real playground.tscn binding:       PASS
Production unload stop probe:       PASS
Bash runner/apply syntax:            PASS
JSON / git diff check:              PASS
Conflict markers / NUL:               0
Archive replay:                     15/15 PASS
Manifest payload:                   14/14 PASS
Linux runner/apply modes:           0755
Remaining Godot/Xvfb:                 0
```

Fix3 закрывает единственный P1 из независимого review: production unload теперь останавливает pump, откатывает pending predictions, восстанавливает canonical consumers и разрывает runtime callback до освобождения bridge.

## Решение

```text
checkpoint: v16.16.0-network-nx6-predicted-item-interactions
delivery:   fix3
decision:   ACCEPTED
branch:     feature/nx6-predicted-item-interactions
frozen:     true
next:       integration/c24-nx6-mw10-rl3
```

Статус `FIX3_IMPLEMENTED_CANDIDATE` в authoring validation JSON является историческим статусом до закрытия независимого review и этим acceptance-коммитом заменён на `ACCEPTED` для выбора frozen head.
