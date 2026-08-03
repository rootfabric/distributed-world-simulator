# Checkpoint v16.16.0 — Network NX6 Predicted Item Interactions

```text
stage:      NX6 — Predicted Item Interactions
delivery:   fix3
branch:     feature/nx6-predicted-item-interactions
base:       c727b1cf25b4e5916098a057b89b7fa1eb878dc6
base gate:  NX5 fix1 — ACCEPTED
decision:   FIX3 IMPLEMENTED CANDIDATE
```

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

## Авторская проверка

```text
Godot:                         4.7.1 stable double a13da4feb
Production source reconstruction: base Git blob byte-exact PASS
Editor import (isolated):      PASS
NX6 contracts:                 940 assertions — PASS
NX6 integration fix3:           66 assertions — PASS
Real playground scene binding: PASS in isolated fixture
Bash syntax:                   PASS
Linux runners/apply mode:      0755
M7 graphical multiprocess:     NOT RUN — full accepted tree unavailable
```

Полное принятие требует повторного запуска M7 playable contracts, graphical multiprocess, recovery и принятых Network/World regressions на полном дереве.
