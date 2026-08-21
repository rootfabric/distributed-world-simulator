# ECO — Поправки дорожной карты ECO-R79 (Morphology Bridge / EVO4 разворот)

Статус: `RESEARCH_ONLY / LIVE_TRACKER_AMENDMENT / NO_ACCEPTANCE_AUTHORITY`.
База: `ECO-R78-2026-08-22`, ветка `feature/eco-evolutionary-ecology`, head на момент внесения: `b4d62d9e`.

## Что меняет R79

1. **Разворачивает плейсхолдер EVO4** (было: две строки `AFTER_EVO3_PLANETARY_GENERALIZATION` + цель multi-trophic) в структурированный лейн из двух треков:
   - **E4.B — Morphology Bridge EVO3→PH** (шаги B0–B7, `PROPOSED_PENDING_AUTHORIZATION`): соединение планетарной цепи EVO3 (persisted SpeciesCatalog, opportunity vectors, программы колонизации) с принятым фенотипно-визуальным наследием `ECO.PH` (PH0..PH5-S4 ACCEPTED, RESEARCH COMPLETE);
   - **E4.T — Multi-Trophic Ecosystem & Coevolution** (исходная declared goal EVO4): строится после/параллельно мосту, defense/spines-гены становятся трофическими признаками; собственная авторизация.
2. **Фиксирует правило наследия**: мост обязан переиспользовать принятые контракты PH0 (DevelopmentTraits, IndividualSeed) и PH5 (renderer profiles, тиры); параллельный визуальный компилятор запрещён; расширение PH5 core запрещено (closure boundary — новые идеи через CONV0 / CAL1-P2 / P3-PH6).
3. **Добавляет указатель на pre-design**: `docs/plans/ECO_EVO4_MORPHOLOGY_VISUAL_PREDESIGN_RU.md` (по образцу xfer1_readiness_predesign).
4. **Фиксирует зависимости**: запуск E4.B — отдельный authorization dispatch после acceptance E3.FINAL (merge PR #190); сезонные визуальные состояния — fail-closed `BLOCKED_WAIT_E36_R`; планетарная индивидуальная истина остаётся запрещённой (преемственность `e3_5_planet_wide_individual_truth_rule`).

## Чего R79 не делает

Не принимает ни один шаг E4.B (все `PROPOSED`); не трогает замороженные артефакты (`eco-evo3-roadmap.v1.json`, архитектуру E3.0, roadmap doc E3.0); не создаёт product-полномочий; не меняет принятые поверхности E3.x; не разблокирует XFER1/LIVE.

## Обоснование (сжато)

Аудит документов (см. §0 pre-design) показал: «геном→визуал» в ветке уже решён на уровне локального контура P1-эры принятым треком ECO.PH, но планетарная цепь EVO3 с ним не соединена: у persisted каталога нет developmental traits, PH потребляет окружение старой модели. Мост — минимальный честный путь к цели пользователя («вырос новый вид и отображается визуально»), при этом multi-trophic цель EVO4 сохраняется как горизонт.

## История поправок

- `ECO-R78-2026-08-22` — гейты E3.FINAL (A1–A3), политика регрессии A4, evidence binding A5, баннеры A8; E3.FINAL реализован, independent review PASS.
- `ECO-R79-2026-08-22` — настоящий документ: разворот EVO4, bridge-лейн E4.B, правило PH-наследия.
