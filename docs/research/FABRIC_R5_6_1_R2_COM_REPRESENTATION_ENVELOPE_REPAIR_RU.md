# FABRIC R5.6.1 R2 — narrow center-of-mass representability repair

Status: **implemented research R2 candidate / independent acceptance pending**.

## Причина

На принятом к технической Windows exact варианте R2 (HEAD `1b2e707c3605c502280efe157ed112816f85c6df`) независимый Linux Reviewer обнаружил отдельный от ранее закрытой inertia cancellation дефект области представления: два канонически допустимых положительных point masses на соседних числах Float64 имеют истинный COM между этими числами. Внутренний индекс считает source-relative COM и инерцию правильно, но API возвращает один абсолютный Float64 `center_of_mass = source_anchor + local_center`. Малое смещение при суммировании теряется без отказа.

Пример с точками 1e15 м и 1e15+0.125 м: истинный COM на 0.0625 м правее первого центра; опубликованный абсолютный COM округлялся к первому центру (скрытая ошибка 6.25 см). Construction Snapshot.validate допускает оба исходных конечных значения. Исходный отдельный reviewer falsifier: [review/fabric-r56-r2-com-representation-precision-r1](https://github.com/rootfabric/distributed-world-simulator/tree/review/fabric-r56-r2-com-representation-precision-r1).

## Выбранная граница R2 (explicit research contract)

Для **текущего point-mass R2 result schema** вводится целевой максимальный абсолютный ущерб точности, возникающий *только при переводе* из стабильной source-anchored системы в возвращаемый абсолютный Float64:

`COM_ABS_PRECISION_M = 1e-6 m` (1 мкм).

Это консервативный численный контракт данного исследовательского стенда, а не объявление универсального диапазона достоверной физики DWS и не оценка суммарной ошибки BIT/канонических источников. Значение выбранно достаточно строгим, чтобы не публиковать незаметные сантиметровые ошибки в контурах связи геометрии и движения. Продуктовому интеграционному R6 потребуется собственный масштабно-ориентированный physical envelope и/или изменение API на anchor + local offset.

До публикации checksum descriptor `query_range` вычисляет фактически представимое абсолютное значение каждого COM компонента, переводит его **обратно в ту же source-anchored систему** и сравнивает с внутренним относительным COM. Если `abs(recovered_local - original_local) > 1e-6 m`, то возвращается:

`R56_R2_RANGE_CENTER_PRECISION_UNSAFE` с `axis`, `representation_error_m`, `absolute_accuracy_budget_m`.

Результат не публикуется, индекс и canonical source **не изменяются**. В отличие от запрета всех больших координат это пропускает, например, точно представимый midpoint между x=1e12 и x=1e12+1. Для разрешённого представления на x=1e9 и следующем Float64 допускается error ~5.96e-8 m (меньше выбранного порога); на x=1e12...1e15 непредставимые промежуточные COM теперь отклоняются. Отдельные Y, Z и отрицательные большие координаты проверяются аналогично.

Ограничение: round-trip guard фиксирует **потерю точности представления вывода относительно рассчитанного source-local центра**, не доказывает полной точности произвольных сумм и тензора, а также не позволяет позднее восстановить потерянный локальный offset из опубликованного scalar. Для более сильной точности без отказа потребуется новое DTO с origin + local offset; он **не подменяется** неявно в существующей схеме.

## Scope

- Единственное runtime-изменение: `r5_6_1_r2_dynamic_aggregate_index_v1.gd` — validation `world_center` перед формированием descriptor; 10 Fenwick moments, алгоритм обновления O(k log N) и внешняя Construction authority не меняются.
- Отдельный тест `fabric_r5_6_1_r2_center_precision_acceptance.gd`: 8 кейсов, 52 asserts, 6 fail-closed отказов, 2 valid positive cases, X/Y/Z, неизменность состояния. Самостоятельный RED на предыдущем HEAD: **52/7 FAIL**; после narrow guard **52/0 PASS**.
- Linux/Windows exact runners включают COM parse/runtime. Strict collector schema `fabric.r56_r2.dynamic_aggregates.exact_evidence.v3` требует новую COM payload и строго валидирует все восемь кейсов. Collector отрицательных свидетельств проверяет отсутствие COM-гейта, подмену допуска, ложное принятие и повреждение counters.
- Предыдущие R2 626/0, scale 255/0, numeric 54/0, R1 203/0, Narrow Admission 26/0 и BRIDGE-4 49/0 остаются обязательными регрессиями.
- Никаких изменений `main`, Construction/Matter, закрытых FABRIC R5.1–R5.5, R1 и BRIDGE-4; R2 не становится production authoritative solver.

## Acceptance

1. Canonical Godot Linux/Windows exact **на новом опубликованном HEAD/TREE**; strict collector v3 и отрицательные falsifiers.
2. Независимый Reviewer принимает сам numeric envelope (не выдавая `1e-6m` за исторический универсальный контракт), проверяет representability на других координатах, оракул инерции и fail-closed.
3. Отдельный Verifier проверяет новый COM RED→GREEN, SHA256 identity и Linux/Windows payload parity.
4. Human approval перед исследовательским merge; `main` не трогать.

Состояние после локальной реализации не является `MERGE_READY` до пунктов 1–4.
