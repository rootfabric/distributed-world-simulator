# Construction focused fixture: canonical staging после carrying

Исходный test на `e1337382` воспроизводит183 assertions /1 failure на stage1:
`CONSTRUCTION_MATERIAL_INSUFFICIENT`. Журнал rollback не причина: тот же failure
получен с исходным journal. Native fixture создаёт5 ore и назначает hotbar alias;
Construction fixture добавляет3 ore в inventory slot. Обе stacks сохраняются
после A→B→A. Принятый P4 allocator намеренно исключает items без inventory slot:
доступны3, stage0 тратит2, stage1 требует4 и получает только1.

Изменён только существующий разрешённый MVP test. После обоих seam crossings он
вызывает existing `native_command6` → canonical `item.transfer` для той же
hotbar ore stack в `inventory/a`, свободный slot определяет существующий owner.
Перед этим проверен перенос hotbar identity через seam; после — сохранение
всех item identities, definitions и quantities, полного количества ore8 и
очистка alias у перемещённой stack. Старые assertions и рецепт2/4/2 сохранены.
Native carry fixture и P4 allocator/runtime не менялись.

Рабочий red→green:223 assertions /0 failures. Это ещё не exact committed run;
его JSON head labels относятся к pre-commit, поэтому он не служит acceptance.
Следующий шаг — exact committed223/P4-ordering64 с правильными EXPECTED_HEAD/TREE
и fresh bounded review/verification отдельно от journal subjects73b88181/3b82145a.

Focused test остаётся backend composition. Его presentation proxy assertions
не заменяют required physics interaction и пять реальных процессов. Whole MVP6,
five-process, full connected Construction и PC0 clearance не объявлены VERIFIED.
Новых ресурсов/owners/ledger не добавлено; main repair PR646 не менялся.

## Exact результат

Frozen `84ab0c0fba87f12dcfc94e32bb9cfa4eb8abb481`, tree
`f7e3f255bcc4878f3e738e011e3d45bf3edcdb81`: Windows и Linux223/64/77 PASS,
proper report HEAD/TREE, отсутствие fatal markers, source clean. Reviewer и
Verifier дали отдельные bounded PASS; Verifier самостоятельно повторил223.
Проверены canonical расход8→6→2→0, один OPERATIONAL construct, обе native
handoff cases и две derived presentations. Physics interaction и five-process
не заявлены. Runtime scripts byte-identical frozen journal subject73b88181.

Linux run35100372324, artifact10447788421, фактический ZIP SHA256:
`cfae9802f9e13e2314763ca3ec926a8a1bc65057fb68774ef3e59ed11d50d63a`.
Все raw результаты и role verdicts: `construction-fixture-evidence-r1/manifest.json`.
Исторический183/1 сохранён; после staging это больше не текущий focused blocker.
Canonical PC0, connected live/physics и full MVP6 acceptance остаются открытыми.
