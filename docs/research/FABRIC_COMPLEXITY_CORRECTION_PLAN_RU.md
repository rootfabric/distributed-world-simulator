# FABRIC — корректировка плана: от стендов к конструктору сложности

Дата: 6 сентября 2026. Основание: `FABRIC_COMPLEXITY_AUDIT_2026_09_06_RU.md`.
Статус: **research execution recommendation / NOT MAIN ACTIVATION**.

Этот план уточняет ранее предложенные следующие этапы, но не создаёт второй scheduler и не меняет canonical owner. Реализация каждой стадии требует scoped Work Order и действующих main-owned gates. Исторические acceptance, freeze manifests и logs не переписываются.

## Целевой результат

Пользователь собирает объект из общих деталей, материалов и связей. Компилятор получает из этих данных физические законы и состояние. Функция, нагрузка, отказ и последствия возникают из расчёта; имена машины и выбранного теста не меняют solver. Безопасная редукция сохраняет наблюдаемые величины и может отказаться от упрощения. Canonical мир остаётся внешним authoritative owner.

Библиотека именованных сборок допустима: motor может быть композицией общих законов. Запрещён не сам термин motor, а скрытая специальная динамика, добавленная для прохождения конкретного fixture. Проверка запрещённых имён не заменяет поведенческие опыты.

## Новая последовательность

| Этап | Результат | Условие перехода |
|---|---|---|
| AUDIT-R0 | Сверка claim/code, два повторных diagnostic runs, журнал findings | Выполнен текущим аудитом; runtime defects не исправлены |
| **REPAIR-R1 — NEXT** | Integrity + сквозной canonical binding | F01/F02/F03 закрыты новыми regressions; старые positive paths сохранены |
| PHYSICS-R2 | Typed material/geometry-to-law compilation, малые объекты | Аналитические и metamorphic проверки; no surrogate strength-as-conductance |
| COMPOSITION-R3 | Один наблюдаемый динамический механизм на общем solver | State, feedback, physical failure, canonical mutation и rebake в одном опыте |
| HOLDOUT-R4 | Независимо заданные неизвестные семейства | Freeze grammar до reveal; неизменный kernel; независимые физические ориентиры |
| SCALE-R5 | Полная стоимость локального события на растущем мире | Раздельно N, активные DOF, boundary size, metadata/solver work и amortization |
| INTEGRATION-R6 | Передача минимальной capability в DWS | Fresh current-main candidate, scoped consumer contract, review/verification/human merge gates |

VIS1 остаётся наблюдателем. Доработка его управления/инспектора может сопровождать R2/R3. Thermal/hydraulic и distributed execution следуют за проверенной композицией, а не становятся обязательным огромным пакетом до первого результата.

## REPAIR-R1 — первый обязательный Work Order

Fix location: FABRIC1 lifecycle, B0.7 successor validation и сквозной compiler/runtime context. Не лечить ошибку FULL restart принудительным BAKE, не отключать validation и не подменять authority именем fixture.

Ожидаемые invariants:

```text
uninterrupted execution == restart at each phase
successor ledger == previous ledger union exactly one new event
current authority is supplied independently of discardable capsule/artifact
artifact source frontier == actual canonical source frontier
readonly Matter stays readonly
NO_SAFE_BAKE does not forbid an otherwise valid FULL object
failed operation does not partially advance coupled runtimes
```

Тестировать перед/после start, refinement, canonical commit, successor observation, rebake и restoration. Особые случаи: два отказа подряд в FULL; повтор/задержка event; прежнее событие удалено или заменено; изменён owner/epoch при неизменных graph bytes; капсула с пересчитанным checksum и старой authority; повреждение каждой части capsule; failure функциональной проекции после начала transition. Старый артефакт не должен сам удостоверять текущую authority.

Проверять entry point полного COMPLEX4/BRIDGE4, не только отдельный validator. Открыть версии/поправки freeze явно: хороший freeze защищает семантику, но не запрещает исправление дефекта. Independent reviewer оценивает достаточность evidence, а не количество asserts.

## PHYSICS-R2 — размерности и локальные законы

Разделить геометрию, constitutive parameters и failure capacity: mass/inertia, length/area, stiffness/damping, conductivity/resistance, strength/threshold. Нельзя автоматически получать электрическую проводимость из механической прочности. Преобразование должно явно ссылаться на версионированный material-law contract; отсутствующий закон означает unsupported/fail-closed, не выдуманный default.

Минимальные fixtures: один упругий элемент с mass и anchor; два последовательных и два параллельных резистивных элемента; малые конструкции 2/6/20 деталей. Назначение физических boundary ports не должно требовать специально подогнанного benchmark на 100+ внутренних узлов.

Опыты:

1. При одной и той же модели упругого элемента меняется жёсткость, затем отдельно capacity. Первое меняет упругий отклик; второе только границу отказа до появления damage. Эталон — самостоятельно вычисленная аналитическая формула, не тот же assembler FULL.
2. Меняются length/area/material по объявленному закону. Проверить ожидаемую чувствительность, преобразования единиц и баланс энергии. Перестановка IDs и global rigid transform не должны менять физический смысл.
3. Нагрузка 70/90/110 при capacity 100 и early guard 80. При 90 допустим refinement, но не автоматическое объявление разрушения. Разгрузка после 90 не должна оставлять ложный damage. Реальный failure определяется отдельным критерием.
4. FULL fallback для малой/неподходящей к BAKE системы. Ни искусственное добавление hidden nodes, ни ослабление safety не допускаются.

Уточнение multidomain: V*A и force*velocity дают мощность. Для conventional thermal port температура T [K] и heat flow Qdot [W] не образуют power как T*Qdot. Выбрать размерностно корректное thermal energy accounting или отдельную согласованную power-conjugate формулировку; не переименовывать generic scalars.

## COMPOSITION-R3 — один механизм, причинность в обе стороны

Предлагаемый первый стенд: масса/ползун + пружина/демпфер + общий electromechanical power coupler + источник с конечным сопротивлением + нагрузка и breakable support. Точные допущения фиксируются до реализации. Переиспользовать FABRIC0 power maps, dimensions, stateful/hybrid mechanisms и B0.4/B0.5 там, где они подходят; не создавать параллельный solver.

Изменение электрической нагрузки должно менять механическое движение/усилие; изменение механической нагрузки — ток/потребление. Это важнее четырёх названий доменов в enum. Путь отказа выбирается solver по состоянию, а не `support_id`, переданным сценарием для получения нужного OFF.

Проверять: boundary effort/flow, trajectory, stored energy, dissipated energy, source work, constraints, first failure identity/time и effect после canonical commit. Мощность не возникает при FULL/BAKE handoff. Source command имеет revision/owner preconditions; при отказе canonical commit physical proposal не становится фактом.

Эталон: независимый небольшой аналитический/численный reference. FULL и BAKE могут использовать одну физическую грамматику, но согласие двух веток общего ошибочного assembler не является единственным oracle. Уменьшение timestep/tolerance должно давать объяснимую сходимость.

VIS: render из canonical/physical snapshots, физическая пауза и шаг, нагрузка мышью/клавишей с явной величиной, инспектор сил/энергии/revision/owner/fidelity. Сохранить старый storyboard отдельно. Подключение UI не должно создавать второй solver или прямое присваивание BROKEN/ON/OFF.

## HOLDOUT-R4 — честная проверка обобщения

До reveal фиксируются primitive grammar, compiler, reduction policy, метрики и критерии. Независимый контекст создаёт несколько отличающихся семейства topology/состояний, а не только новые seeds одного backbone generator. Включить малые механизмы, контуры/мосты/ветвления, разное число boundary ports, nearly singular и unreducible cases.

No post-reveal runtime tuning. При обнаруженном общем bug завести новую freeze generation и новый holdout; сохранить предыдущий FAIL. Генератор только создаёт данные из допустимых примитивов. Он не содержит готовой failure sequence, на которую ориентируется solver.

Проверять permutations/renaming, unit changes, физически эквивалентную декомпозицию детали, масштабные преобразования, нагрузку на неожиданную связь. При сохранении смысла ответы эквивалентны; при изменении физического смысла ответ должен меняться ожидаемым образом.

## SCALE-R5 — sparse physics без скрытой глобальной работы

Сначала меньшие физически достоверные случаи, затем 5k/20k/100k как независимые durable predicates. Начальное построение/индексация O(N) допустимы и измеряются отдельно. Не фиксировать unbake island всегда равным 20: его размер определяется консервативной причинной областью.

Раздельные axes: total canonical N; local active DOF k; boundary port count b; changed dependencies; simultaneous events; distance to instability. Для одинакового локального воздействия и ограниченного k измерять горячую работу, включая metadata visits, graph walks, hashes, descriptor validation, solver/reconstruction/rebake, allocations и memory. `global_physical_rebuilds=0` не отменяет O(N) обходов metadata.

Контрольный глобальный пример обязателен: потеря опоры у всей конструкции. При реальной распространяющейся опасности система обязана расширить refinement, даже если это нарушит желаемый маленький active set. Безопасность важнее красивого графика локальности.

Perf сравнивать с полезным FULL baseline: cached factorization и sparse solve, где применимо, плюс полный runtime path. Отдельно показывать arithmetic work estimate, measured CPU/RSS и стоимость compile/rebuild. Точка окупаемости: число исполнений, после которого затраты на compile + reduced execution + rebuild становятся меньше FULL для той же нагрузки. Не выдавать `((n+b)/b)^2` за измеренное ускорение сервера.

## Проверка canonical durability

Новый процесс должен загрузить Construction/Matter и авторитетную историю из диска, когда все derived caches удалены. Сравнить с непрерывным исполнением: canonical checksum, source revision, event ledger и физические observable. Проверять crash before/after canonical commit и повреждённые capsules. Создание нового RefCounted при сохранённом in-memory store — отдельный warm recovery test, не cold world restart.

## Исправление доказательного процесса

Для каждого результата вести отдельные категории: CONTRACT, NUMERICAL_MODEL, PHYSICAL_ORACLE, INTEGRATION, SCALE, REVIEW. Исторический CLOSED не повышает автоматически все категории. Новые captures сохраняют HEAD/TREE, input hashes, transitive dependency identity, binary digest, commands, exits, raw log SHA-256 и отчёт reviewer. Текущий аудит — self-audit с новыми наблюдениями, не независимое принятие старой реализации.

Reuse разрешать только при проверенной замкнутой dependency surface и соответствии нового claim старому тесту. Отсутствие diff файла недостаточно, когда изменились callers, execution environment или интеграционная граница. Anti-hang/sharding сохранять: timeout меняет разрешённую стратегию исполнения, но не отменяет нужный oracle или required scale.

## Ближайшее действие

**FABRIC-REPAIR-R1 — FULL restart continuation + event-history integrity + canonical authority binding.**

После него: PHYSICS-R2. Не начинать сейчас новый FABRIC2, сразу четыре домена или distributed physics. Этот маршрут не блокирует основной визуальный сетевой MVP автоматически; продуктовый control остаётся в main.
