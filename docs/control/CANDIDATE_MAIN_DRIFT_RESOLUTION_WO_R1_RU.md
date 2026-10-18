# WORK ORDER — Project Control: закрытие CANDIDATE_MAIN_DRIFT (диагностика R1)

Статус: DIAGNOSTIC COMPLETE. Канонический владелец контроля выполняет ротацию;
настоящую ветку предложено использовать только как носитель документа и evidence.

## 1. Наблюдение

GitHub Project Control на сетевых candidate-PR (в т.ч. #779/#780) возвращает
`CANDIDATE_MAIN_DRIFT`: observed main `3d7672cba293d8e7bd72427b803f73fc8fcee5da`
!= canonical main. Свежий fetch на принимающей машине (2026-10-18):

- `origin/main = 0d1173303fb6b84e6aa046423ab7c49600176492` — уже новее, чем
  `f369858c9bf7d6247785898537d7c8841b08b7bd` из более раннего acceptance-контекста.

## 2. Источник рассогласования (подтверждено кодом и локальным воспроизведением)

1. Проверка: `scripts/harness/project_overview.py` — candidate-режим сравнивает
   `coordination.observed_main` канонического registry-снимка
   (`config/control/project-program-registry.v1.json`) с живым `origin/main`,
   и допускает альтернативное доказательство свежести по топологии
   (`_candidate_contains_canonical_main`: canonical HEAD — предок candidate HEAD).
2. На чистом `origin/main` tip дрейфа НЕТ (топология проходит) → ошибка на PR —
   это (a) устаревшая база long-lived candidate-ветки плюс (b) реально
   устаревший `observed_main` в самом каноническом снимке (3d7672c при tip
   0d1173303).
3. Узкая правка одного поля `observed_main` **невозможна по контракту**:
   любое изменение registry требует `REGISTRY_GENERATION_ADVANCE_REQUIRED`
   (generation 82→83), а generation жёстко связана с
   `executions/E2026-09-09-V0-MVP-R1/project-epoch.v1.json`,
   `harness/scheduler-policy.v1.json` (lease) и каноническим Work Order эпохи
   (`MVP_CANONICAL_EPOCH_WORK_ORDER_MISMATCH` при ручной рассинхронизации).
   Проверено локально: ручной набор правок (registry + lease + epoch) не
   проходит `tests/harness` binding-тесты — ротация должна выполняться
   штатным control-механизмом канонического владельца (CONTROL_DEVELOPMENT),
   а не ручным редактированием.

## 3. Требуемое действие канонического владельца

1. Штатная ротация registry generation 82→83 через CONTROL_DEVELOPMENT с
   обновлением `coordination.observed_main = <живой origin/main>`,
   lease `effective_registry_generation` и binding-документов эпохи.
2. После merge ротации — catch-up/rebase сетевых candidate-веток на новый main;
   candidate, содержащий canonical tip, проходит проверку и без правки поля.
3. Скрытие/отключение проверки, правка исторических acceptance-записей —
   запрещены; current FAIL Project Control на NET-SMOOTH1 ветках классифицируется
   как ожидаемый drift long-lived repair-ветки (прецедент: R42 P0 evidence),
   не как дефект сетевого кода.

## 4. Evidence

- Локальное воспроизведение candidate-проверки: pristine main — drift
  отсутствует; ветка с правкой `observed_main` (без ротации generation) —
  drift отсутствует в overview, но CI
  `REGISTRY_GENERATION_ADVANCE_REQUIRED:82<=82` (run 39087410799) и
  `AssertionError: 83 != 82` (binding-тест, run 39089156423).
- `scripts/harness/project_overview.py:37-94`;
  `tests/harness/mvp_act0_base.py` (`test_exact_product_base_and_epoch_are_bound`);
  `scripts/harness/control_candidate_validation.py:82`.
