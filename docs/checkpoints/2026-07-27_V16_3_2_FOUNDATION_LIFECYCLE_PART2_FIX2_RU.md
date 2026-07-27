# Checkpoint v16.3.2 fix2 — Terminal Lifecycle World-Load Fence

**Дата:** 27 июля 2026 года
**Версия:** `v16.3.2-foundation-lifecycle-part2-fix2`
**Основа:** `v16.3.2-foundation-lifecycle-part2-fix1`

## Причина исправления

После failed shutdown предыдущая версия сохраняла runtime и выставляла `_runtime_release_blocked`, но сбрасывала `_shutdown_in_progress`. Если worker завершался позднее, прямой вызов `load_world()` из UI мог повторно выполнить drain, освободить старый runtime и запустить новый мир при lifecycle `FAILED`.

Это нарушало fail-closed инвариант: terminal failure процесса не должен превращаться обратно в обычную игровую сессию.

## Центральная граница загрузки мира

`SimulatorApp.load_world()` теперь до создания нового runtime проверяет:

1. `_runtime_release_blocked`;
2. terminal lifecycle state `FAILED`;
3. обычный `_shutdown_in_progress`;
4. `_loading_world`.

При release fence возвращается `RUNTIME_RELEASE_BLOCKED`. При `FAILED` без fence возвращается `LIFECYCLE_FAILED`.

Защита находится непосредственно в `load_world()`, поэтому одинаково действует для:

- консольной команды `world.load`;
- SystemMenu, вызывающего `load_world()` напрямую;
- тестовых и будущих API-вызовов;
- любых presentation adapters.

## Инвариант после failed shutdown

Даже если worker позднее стал drainable:

```text
drain=false
→ lifecycle FAILED
→ worker позднее завершился
→ load_world() отклонён
→ старый runtime сохранён
→ новый runtime не создан
```

Повторный drain и очистка release fence разрешены только emergency shutdown path. После успешного аварийного cleanup процесс завершается с ненулевым кодом и не продолжает нормальную симуляцию.

## Тестовое покрытие

`tests/runtime/test_simulator_shutdown_failures.gd` дополнительно проверяет:

- позднее завершение worker-а после failed shutdown;
- прямой `load_world("playground")`;
- сохранение `FAILED`;
- сохранение старого runtime и world ID;
- отсутствие второго runtime в host;
- отсутствие повторного stop/drain вне emergency path;
- сохранение `_runtime_release_blocked`;
- последующий безопасный emergency drain и exit code `1`.

Failure-path набор содержит 62 assertions.

## Следующий этап

После принятия fix2 lifecycle Part 2 считается закрытым для обнаруженных P1 fail-closed сценариев. Следующий основной checkpoint:

```text
v16.3.3-foundation-world-aggregate-part3
```

Он должен начать разделение SimulationKernel/PresentationHost и создать единый `WorldEntityAggregate`.
