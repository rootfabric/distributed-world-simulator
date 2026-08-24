# V0 P6 R3 — WIP handoff для локального продолжения

Дата фиксации: 2026-08-24 (UTC+10)

Ветка:

`repair/v0-p6-persistence-exactly-once-r1`

База repair:

`main @ 9ade3233f8d9f16b77edcc8cf273fe8e649d5637`

Последний runtime repair HEAD перед этим handoff:

`28467bd2982af6f9e84da482b65174694ad85165`

## Что уже зафиксировано

1. Новый P6 R3 Project Epoch, HIGH-risk Repair Work Order и Repair Map поверх уже смерженного P6.
2. Exactly-once repair:
   - повтор PENDING не допускается к повторному handler execution;
   - OperationId history больше не вытесняется так, чтобы старую операцию можно было выполнить повторно;
   - capacity exhaustion fail-closed;
   - restore/lookup semantics усилены.
3. Удалена архитектурно неверная модель P6-private persistence owner.
4. `P6OutpostState` больше не является собственной canonical truth; это read-only projection существующих canonical sources.
5. SHADOW path переведён в read-only режим и не может самостоятельно создать новую canonical writer authority.
6. Zero-write модель P6 направлена на отсутствие собственного filesystem/save-format owner.
7. Исторический P6 R2 PASS не переписывается; R3 repair явно считается незавершённым до новых literal evidence gates.

Основные commits:

- `031b06bca9785ebc3224753d0894cb03bec2ea34` — R3 repair control + Repair Map.
- `cb299be9a778c4455ae4d43aa21ca26fd1623b27` — exactly-once PENDING/capacity repair.
- `28467bd2982af6f9e84da482b65174694ad85165` — remove private persistence and canonical outpost truth.

## Что НЕ считается завершённым

Ни один из пунктов ниже нельзя обозначать PASS без нового literal evidence:

- canonical composition proof по реальным P4/M4/P5/M6 public surfaces;
- real OS-process restart/recovery proof только через persisted bytes;
- полный world/core regression;
- настоящий 30-минутный two-client soak;
- MCP visual proof для P6.7-P6.11;
- fresh exact-head Reviewer PASS;
- fresh exact-head Verifier PASS;
- final Project Control / directional audit;
- checkpoint proposal/acceptance.

## Следующий локальный шаг

1. Получить ветку и проверить точный HEAD.
2. Прогнать Godot import/parse на проектном double build.
3. Запустить focused P6 tests, начиная с operation ledger, mutation admission, ownership map, persistence adapter, outpost projection, shadow authority и zero-write fence.
4. Исправить любые compile/runtime несовместимости после перехода старых P6 tests с private state на canonical-owner composition.
5. Перепривязать restart gate к существующему M6 process recovery runner; никакой передачи state/ledger через память тестового процесса.
6. Проверить P4 Construction persistence вместе с M4 Item Graph/P5 gameplay, не создавая нового P6 replay/persistence owner.
7. После focused GREEN — full world/core regression.
8. Отдельно получить literal 30-minute two-client soak и MCP visual evidence.
9. Только после этого делать Evidence Map, fresh Reviewer/Verifier и closure.

## Запреты на продолжение

Не создавать:

- новый P6 filesystem repository;
- новый P6 save format;
- второй Item Graph;
- второй Construction truth;
- P6-private equipment/inventory store;
- P6-private replay oracle;
- замену настоящего soak ускоренным циклом;
- замену process restart переинициализацией объектов в одном процессе.

Статус на момент handoff:

`P6 R3 REPAIR — WIP / NOT VERIFIED / NOT MERGE READY`
