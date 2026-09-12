# FABRIC R4 — qualification и устранение регрессий R1

WORK_ORDER: FABRIC-R4-QUALIFICATION-WO-001
Статус: IN_PROGRESS. Risk: HIGH. Acceptance: NOT_GRANTED.

## Точные исходные точки

PR #592: repair/fabric-holdout-r4-g2-generalized-capabilities-r1.
Candidate HEAD: ddb91770c1aa3b8e0ce7e22a513ff0e84e7caef7.
Candidate TREE: e0d619f80c48c9ead11cd9d66a68ead5f91b5ce2.
Baseline: b88004e77a9a424f1b23ba979f5ce8883a98f1a8.
Canonical policy main observed: 127c732a56cc5c25d5712f24a7627ed4bb877374.

TREE e0d6aa9996237d6710db5152ce77470f28cadbb7 из исходного сообщения неверен: Git object, bundle и CI identity дают e0d619f8… . Старое сообщение не является evidence.

## Диагноз и Repair Map

1. B0.4-D Linux падает в prerequisite B0.4-A: `positive INTO flow drives network`. Общая NetworkUtils.canonicalize после G2 запускает orbit-normalization всех дробных чисел. В вычисленном состоянии узел 77 содержит около 1.5868896825778374e-155; orbit исчерпывает 4096 шагов, checksum становится пустым, создание следующего физического состояния отклоняется. Диагностический контроль не достиг цикла и за 250000 шагов. База проходит тот же B0.4-A, candidate воспроизводимо падает на том же binary.
2. Complex Labs и CX-VIS0 падают в общем COMPLEX0@2000 на неизменённом golden transaction checksum. Общий numerical hashing изменён, хотя потребитель и golden не менялись. Это не повод переписать golden.
3. B0.6-CLOSE останавливается в COMPLEX2-PERF: 500 деталей, 16187145 us > 12000000 us. Локально отдельный PERF проходит и на базе, и на candidate. CI performance cause остаётся INDETERMINATE; последующие стадии CLOSE не считаются проверенными.

Owner: существующие network/Construction/Matter contracts. FABRIC остаётся research consumer. Entry points: canonicalize -> payload_hash -> Bake checksum / Construction transaction -> legacy BAKE and replay. Siblings: B0.4-A/D, COMPLEX0, CX-VIS0, R1/R2/R3, G2 cold replay. Canonical owner, физические законы, thresholds и authority не меняются.

## Выбранный repair

Восстановить общий NetworkUtils v1 byte-for-byte из baseline. Вместо глобального изменения хеширования добавить явный research-only lossless JSON envelope для R3 replay: каждый узел имеет type tag, double переносится как ровно восемь байт в hex с явно заданным порядком байтов. Обычный JSON stringify/parse применяется к этому envelope, не к голым дробным числам. Никакого округления, orbit-поиска, recompute повреждённых inner checksums, bytes_to_var или создания объектов при decode.

Это явная коррекция контракта G2-C, а не утверждение о поддержке прежнего naked numeric wire. Старый orbit-based claim остаётся опровергнутым. Новый wire profile версионирован, opt-in; существующий native replay API и canonical v1 checksums сохраняются. Потребитель вызывает отдельные export/replay transport entry points. Независимый Reviewer обязан проверить допустимость этой коррекции до freeze.

Альтернативы отклонены: очередное увеличение бюджета; округление чисел; замена golden; новый глобальный hash profile; неявная реканоникализация Construction/Matter. Они либо не решают причину, либо расширяют ownership/blast radius.

## Scope

Допустимы:
- scripts/network/contracts/network_contract_utils.gd — только точное восстановление baseline;
- scripts/research/fabric_bake0/fabric_composition_r3_compiler_v1.gd — убрать зависимость от изменяющей числа нормализации;
- scripts/research/fabric_bake0/fabric_composition_r3_canonical_bridge_v1.gd — explicit opt-in wire entry points, старые predicates сохранить;
- scripts/research/fabric_holdout_r4_g2/* — codec, bounded qualification reducer, policy;
- tests/research/fabric1/fabric_holdout_r4_g2_* — lossless/tamper/budget/compatibility tests;
- RUN_FABRIC_HOLDOUT_R4_G2_TESTS.sh и .github/workflows/fabric-holdout-r4-g2-* — exact validation при необходимости;
- docs/research/FABRIC_HOLDOUT_R4_G2_*.md и validation/fabric-holdout-r4-g2-* — work order, append-only evidence, repair map и handoff.

Bridge scope расширен только потому, что он владеет существующей research replay boundary; это не новый store/authority/persistence owner. Квалификатор не заменяет main-owned Harness и не может самостоятельно принять checkpoint.

Запрещены: G1 frozen bytes/evidence, новые физические возможности, thresholds/golden старых тестов, global policy/registry изменения, main push/merge, holdout reveal до review/freeze, удаление отрицательной истории.

## Validation и переходы

Negative controls сохранены на ddb91770. Positive controls: legacy NetworkUtils blob совпадает с baseline; B0.4-A/D и COMPLEX0 checksum проходят без изменения старых тестов; explicit wire сохраняет все биты finite double, safe integers, ключи и типы; NaN/Inf/Variant/duplicate keys/unknown tags/budget overflow/tamper отклоняются; damaged inner checksums не восстанавливаются.

Далее exact G2/R3/R2/R1 + Portable B0.4-D + Linux B0.4-D + Complex Labs + CX-VIS0 + полный B0.6-CLOSE. Performance не освобождается от gate только потому, что локальный запуск зелёный. CANCELLED/MISSING/INDETERMINATE не PASS.

Qualification reducer привязывает policy, HEAD/TREE, команды, binary/environment и полные logs hashes; missing/stale/corrupt evidence блокирует review. Его итог QUALIFIED_FOR_REVIEW не означает VERIFIED, FROZEN или ACCEPTED. Independent Reviewer/Verifier и canonical Harness остаются обязательными.

После exact PASS: fresh independent review -> production freeze -> новый независимый unseen corpus -> неизменённый frozen subject -> независимая verification -> только затем предложение acceptance. G1 остаётся EXPERIMENT_COMPLETED_FAIL / FALSIFIED. SCALE-R5 и INTEGRATION-R6 не разблокируются этим Work Order.
