# COMPOSITION-R3 — P1 transient crossing / Repair Map

Дата: 2026-09-07. Work Order: FABRIC-COMPOSITION-R3-WO-001 / P1-REPAIR-001. Risk: HIGH. Статус: FIX_REQUIRED.

## Subject и evidence

Исходный subject: `ddf2b2c51d76d0afe3331cfaf17a6d4e7fb86054`, tree `9d83ee9ee038c0f84d10722cb32d3dbc0f947a7d`. Независимое замечание: PR #581, discussion_r3949495805, review 5131713763. Pre-repair exact CI: 34118369494, artifact 10017223630, ZIP SHA256 `4d3ec651bbbd13a1b6ece77e7b9580d551ea2580e7db76c82baeeaddad1772bb`.

Архив извлечён и его Git tree проверен на совпадение с subject. Approved Linux double SHA256 проверен. Отдельный production-entry-point regression воспроизвёл отсутствие proposal в четырёх случаях: положительная/отрицательная нагрузка × FULL/BAKE, capacity `[4.0280,1000.0]`, dt=0.015 s. Результат до исправления: 254 assertions, 4 failures.

Важно: t≈0.60802 s — время максимума, НЕ первого crossing. Независимый closed-form reference первого пересечения 4.0280 N: `0.603748955145611 s`. Исправление обязано локализовать первое пересечение, а не выдавать максимум за момент отказа.

## Root cause и владельцы

Entry: canonical bridge execute(advance) → R3 runtime advance → FABRIC0 coupled DAE advance → endpoint-only _find_earliest_crossing. Второй caller: BAKE→FULL remainder после guard. max_step_s ограничивает устойчивость RK4, но не доказывает монотонность effort на шаге. Уменьшение постоянного шага или capacity test не устраняет класс ошибки.

Construction/Matter остаются canonical owners; R3 остаётся derived consumer. Исторический FABRIC0, R1 и R2 не редактируются. Исправление находится в R3 event-bracketing adapter, общем для FULL и BAKE и remainder после guard. Это ограниченная грамматика линейного guided slider, не универсальная сертификация всех прежних DAE consumers.

## Выбранный bounded design

В пределах принятой R3 грамматики x/v имеют affine constant-coefficient flow между событиями. Пробный шаг существующего RK4 задаёт полином четвёртой степени по доле шага; effort каждой опоры — линейная комбинация x/v и также полином степени ≤4. Adapter выводит его коэффициенты из R2-derived K/C/m/R и coupler, изолирует ВСЕ корни кубической производной через рекурсивное разделение по производным, затем проверяет монотонные интервалы. Bisection и event state используют фактические пробы существующего DAE integrator. Смена mode запускает новый поиск остатка из нового состояния. Это bracketing над существующим integrator, не новый device-specific trajectory solver.

Неясность около касания в пределах численной точности, nonfinite probes и превышение bounded event work обязаны fail-closed без commit состояния. Контроль численной ошибки не выдаётся за закон материальной dissipation. Произвольно узкий пик не исправляется постоянной сеткой substeps.

## Siblings и обязательные проверки

- Исходный falsifier ±force, FULL/BAKE; правильные bond/time и отсутствие canonical damage до commit.
- Более узкий пик около максимума, смещение фазы пользовательского шага и несколько dt.
- Peak ниже capacity: нет ложного failure; guard-only transient возвращает BAKE в FULL.
- First crossing, negative crossing, simultaneous candidates, post-guard remainder.
- Atomic reject, stale owner/revision, fracture ledger, deterministic cold replay сохраняются.
- Основной R3 suite, observer, fresh-process replay, R2 и R1; fresh exact import; fatal scan; nonzero assertion count; source/log digests.

## Closure

Runtime и новые тесты публикуются единым bounded commit после локального red→green. Затем frozen new HEAD/TREE, exact CI, fresh independent Reviewer и Verifier, Evidence Map/critique и source-research Director closure. Новый runtime commit делает старые verdict stale. Main acceptance / production activation / merge не заявляются. PR #581 остаётся review-only, immutable R2 не меняется. HOLDOUT-R4 не активируется до независимого acceptance.
