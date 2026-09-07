# HOLDOUT-R4 — необходимые условия следующей генерации G2

**G1 остаётся отрицательным экспериментом. Этот документ не активирует G2, SCALE-R5, INTEGRATION-R6 или production.** Исследуемый frozen R3 `fd6e83b35301d7a15e92c55939654f1f95729730` не изменяется ради уже раскрытых тестов. R4 harness `9c5ee890d9f770756e37c1d3df84b4f3c1dbd477` измеряет результат, а не исправляет физику.

## Что требуется перед новым freeze

### Общий граф электрических примитивов

Нужен исполняемый общий nodal/Kirchhoff путь для connected ветвлений, контуров и мостов, построенный из уже принятых R2 resistor coefficients. Число boundary ports должно быть входными данными, а не двумя скрытыми константами. Независимые Dirichlet potentials не отбрасываются. Физически floating/недоопределённые компоненты отвергаются с конкретным диагнозом.

Результат должен содержать реальные токи каждого ребра и boundary port, nodal potentials, KCL и power balance. Эквивалентный total R сам по себе не является доказательством распределённой схемы. Новый R4 measurement contract `electrical_observables` уже обнаруживает missing/подставленный readback; использовать его как consumer contract или явно versioned adapter, не добавлять expected values в runtime.

### Многокоординатная механика

Из графа масс, опор, spring/damper bonds собирать mass/stiffness/damping и граничные условия. Нельзя добавлять отдельный solver под известный four-span кейс или ограничивать число mobile masses единицей. Почти вырожденные, но определённые матрицы требуют явной численной области точности/conditioning и достоверных residual, а не blanket topology rejection. Structural failure и source ownership остаются в существующих canonical владельцах.

### Каноническое сохранение дробных значений

G1 обнаружил нарушение JSON roundtrip checksum уже в исходном состоянии native case: в том же Godot процессе warm replay проходит, а после `JSON.stringify/parse` поле Matter `bulk_volume_m3` меняется на один ULP и `R3_REPLAY_DOCUMENT_INVALID` блокирует восстановление.

Нужен отдельный Repair Map для общей границы canonical serialization/hash, её callers и sibling contracts. Доказать сохранение семантики finite numbers, прочтения хеша и независимого current-owner binding при записи/чтении. Варианты решения требуют выбора единственного канонического codec/normalization правила, а не второго владельца состояния. Запрещены пере-хеширование повреждённого журнала после чтения, ослабление checksum, специальное округление G1 inputs и доверие самоподписанному внешнему journal.

### Проверка перед freeze

Все раскрытые кейсы G1 становятся открытой regression corpus, но никогда повторно не называются независимым holdout. До нового freeze пройти R1/R2/R3 и G1 regressions, distributed readback falsifiers, linked-worktree launch и JSON cold replay. Для BAKE сохранить честный FULL fallback и различать exact algebraic elimination, реальное сокращение состояний и измеренное ускорение.

## Процедура G2

Отдельный bounded repair Work Order и отдельная ветка должны сначала реализовать и независимо принять общие возможности. Затем закрепить новый точный kernel HEAD/TREE, численный envelope, физические допуски, boundary/readback contract и operator library. Только после этого новый независимый автор раскрывает ещё не использованные topology/state/parameter families. История G1, его входные bytes, отрицательный verdict и все ошибки измерения сохраняются.

Приёмка R4 требует исполнения всех обязательных физических семейств и независимой проверки доказательств; успешный запуск самого тестового стенда не равен успешному обобщению. `SCALE-R5` остаётся заблокирован до действительного R4 PASS. Merge в замороженные R2/R3 или main здесь не нужен и не разрешён.
