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
