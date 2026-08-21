# ECO EVO3 E3.FINAL — AUTHORIZED

Статус: `RESEARCH_ONLY / AUTHORIZED_NOT_STARTED`.

## Точная идентификация

- Базовое принятое состояние: `5fc9895` (E3.8 ACCEPTED, merge `847ea24b7e010e6db2d8221ed7c2706083edc6c4`, PR #188, дерево идентично проверенному HEAD `7a6bb752d17c4fb3a8db992d492a88eaa2315c11`).
- Поправки роадмапа ECO-R78 (гейты A1–A3 для E3.FINAL, политика регрессии A4, привязка evidence A5): независимый fresh Reviewer по диапазону `5fc9895..a52634a` — **VERDICT: PASS** (замечания MEDIUM/LOW по гигиене записей устранены отдельным repair-коммитом; на принятые решения и хеш-артефакты не влияют).
- Авторизация: Director mandate на автономное выполнение плана ветки до этапа 4 включительно; настоящий control-коммит выполняет отдельную авторизацию E3.FINAL, требуемую `next_gate` контракта E3.8 (`E3_FINAL_PLANETARY_ECOLOGY_COMPILER_CHALLENGE_REQUIRES_SEPARATE_AUTHORIZATION`) и живым трекером.

## Что авторизуется

Реализация `ECO.EVO3/E3.FINAL Planetary Ecology Compiler Challenge` как нового driver-owned слоя (новые файлы) поверх нетронутых принятых модулей E3.1–E3.7:

1. Precommit-пакет ДО первой компиляции: 4 byte-frozen unseen-планеты (мультиосевые производные alpha-01 в namespace `eco-evo3-final/unseen/*`), 3 варианта persisted SpeciesCatalog (baseline принятый / extended 12 видов / mono 1 вид), sealed outcome-prediction commitments (12 комбинаций), execution envelope ceiling.
2. Компиляция 12 комбинаций (планета × каталог) через переиспользуемые ядра без retuning: E3.2 `_build` → E3.3 `_build` → E3.4 core `build_colonization_program` (новые runtime-контракты, пороги приняты 60000/150000) + манифесты E3.5 `_derive_core` / E3.6 `_compile_envelopes`.
3. Полный гейт-пакет: fresh-process determinism ×2, sealed commitment verification после заморозки программ, envelope-таблица против ceiling, post-build critique, Evidence Map, независимые Reviewer и Verifier, PC0-аудит, Director acceptance.

## Границы

Никаких canonical G/ENV/MAT/WQ/SD/TF, species taxonomy, individual entity, persistence, transaction, network, XFER1, asset-scatter или production полномочий. Расхождение sealed prediction с результатом сохраняется как falsification evidence и не проваливает компиляцию. E3.6-R остаётся `CONDITIONAL_BLOCKED_WAIT_OWNER_TEMPORAL_EVIDENCE`. XFER1 остаётся `BLOCKED_WAIT_CANONICAL_G_ENV_MAT_WQ_SD_TF`.

## Frontier

`ECO.EVO3/E3.FINAL = AUTHORIZED_NOT_STARTED` → precommit freeze следующим коммитом.
