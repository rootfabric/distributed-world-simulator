# FABRIC R5.6.1 R2 — COM Float64 representation repair

Дата: 2026-10-21. Статус: **IMPLEMENTER LINUX EXACT PASS / FRESH WINDOWS & INDEPENDENT ACCEPTANCE PENDING**.

## Frozen product

- GitHub PR: https://github.com/rootfabric/distributed-world-simulator/pull/784
- HEAD: `91223acb7bf79c37e12fc11d44054ad3e2732455`
- TREE: `3bb5f214a563ce2bb66b548555cf5f049e6fe932`
- RED parent: `1b2e707c3605c502280efe157ed112816f85c6df`
- Research BASE: `4f301fae461567362d408a51802cc3dde6730999`
- Canonical Linux Godot: `4.7.1.stable.double.custom_build.a13da4feb`, SHA256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.
- Frozen GitHub Actions source: run `39523271734` (archive/bundle SHA256 PASS), rebuilt detached checkout checked HEAD/TREE/parent and clean tracked state.

## Причина ремонта

Исходный R2 возвращал scalar absolute `center_of_mass` в одном Float64, который при паре точечных масс на соседних представимых Float64 координатах 10¹²…10¹⁵ метров не мог сохранить их COM в середине. Истинная относительная координата имела потери `0.000061...0.0625 м`, но `query_range()` продолжал выдавать success. Это **новый отдельный недостаток представления COM**, не ошибка уже исправленной инерции. Исходный adversarial REVIEW: [review branch](https://github.com/rootfabric/distributed-world-simulator/tree/review/fabric-r56-r2-com-representation-precision-r1).

## Узкое исправление

В `r5_6_1_r2_dynamic_aggregate_index_v1.gd` введён явный исследовательский допуск `COM_ABS_PRECISION_M=1e-6` м для **ошибки преобразования** локального COM относительно fixed canonical origin в публикуемый absolute Float64. API проверяет обратный перевод реально опубликованного значения в исходный относительный frame, и при превышении бюджета возвращает `R56_R2_RANGE_CENTER_PRECISION_UNSAFE` с axis/error/budget, до построения descriptor и checksum. Запрос остаётся read-only, изменение индекса не происходит при отказе. Физический point-mass floor, индекс Fenwick и сложность O(k log N) **его** обновления не менялись.

Это выбранный bounded research контракт, а не обещание общей точности всей физической модели на любых расстояниях. Погрешности накопления Fenwick, геометрии и внешнего Construction source не охвачены данным частным условием. Для реального world integration потребуется contract для anchored COM DTO либо отдельно утверждённый envelope.

## Тесты RED→GREEN

- Один и тот же новый 8-кейсный COM скрипт до guard: `RED`, exit 1, 52 checks / 7 failures.
- После guard: `GREEN`, exit 0, 52/0. Шесть невыразимых COM (X/Y/Z, в том числе отрицательная координата) отклонены, два корректных/допустимых случая опубликованы. Состояние BIT после отказов не менялось.
- `r2-numeric` 54/0 продолжил проходить, включая старую исправленную инерцию.

## Fresh exact на опубликованном GitHub HEAD

Успешно выполнен **неизменённый** `RUN_FABRIC_R5_6_1_R2_TESTS.sh`, уже из независимого detached checkout опубликованного `91223acb7bf79c37e12fc11d44054ad3e2732455`.

| Gate | Результат |
| --- | --- |
| Cold import + 6 parse | PASS |
| R2 acceptance | 3 × 626/0, raw byte-MATCH |
| R2 scale 5k/20k/100k | 255/0 |
| Prior inertia numeric | 54/0 |
| New COM representability | **52/0**, unsafe=6, safe=2 |
| R1 original | 203/0 |
| R1 source admission | 26/0 |
| BRIDGE-4 | 49/0 |
| Strict collector schema v3 | PASS |
| Adversarial evidence corruption | **16/16 REJECT** |
| Test runner | EXIT 0 |

Canonical deterministic R2 hash unchanged: `7fb3eb72caec05dd5341399c8f032f90165a4459610ab3058d798a97fa98dd43`. Git HEAD/TREE and engine SHA before/after match. Внутренний SHA256SUMS включён в ZIP.

## Что ещё требуется для окончательного закрытия PR

1. Полный Windows exact на **этом** HEAD/TREE каноническим Windows Godot double, с новыми COM 52/0, collector v3 и 16/16 tamper. GitHub-hosted/локальная Ubuntu проверка **не заменяет** эту приёмку. Self-hosted Windows Actions workflow `39523271734` создан, но при составлении отчёта его Windows job ещё ожидает исполнения.
2. Fresh **separate-actor Reviewer** с новым adversarial falsifier и утверждением численного envelope.
3. Fresh separate-actor Verifier на новом frozen subject, сравнение Windows/Linux.
4. Только после этого — отдельное разрешение на merge в исследовательскую ветку. \`main\` не изменять.

**Текущий итог: реализовано, опубликовано и на Linux проверено; не MERGE_READY.**
