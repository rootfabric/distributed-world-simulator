# PROPOSAL: line-level checkpoint «ECO.EVO7 FORM/FUNCTION/FEEDBACK RESEARCH LINE R1» — CANDIDATE

**Дата:** 2026-08-24
**Ветка:** `feature/eco-evo7-fff-r1` · **Точный HEAD предлагаемого состояния:** `9cc4b93be7c8ad1e9f0c10e0d5e8b656e92cae18`
(коммиты персистенции настоящего proposal-документа и карты доказательств следуют непосредственно поверх указанного HEAD и содержат только эти два документа; финальный HEAD ветки — см. `git log`.)
**Статус:** **PROPOSAL / CANDIDATE. Настоящий документ ПРЕДЛАГАЕТ чекпоинт и НЕ принимает его.** Самопринятия нет; все перечисленные артефакты остаются CANDIDATE до независимых процедур из §5.

---

## 1. Миссия линии (summary)

Исследовательская линия ECO.EVO7 «Form / Function / Feedback» реализует шаги **FFF0–FFF6** спецификации `docs/plans/ECO_EVO7_FORM_FUNCTION_FEEDBACK_TECHNICAL_SPEC_RU.md` над research-слоём экологии растений:

- контракт-mapping PH↔EVO7 и функциональный фенотип (FFF0–FFF1);
- морфологическая эволюция на едином v1 lineage kernel без второго mutation-пути (FFF2, G4/G13);
- замкнутые петли обратной связи форма→свет→вода→почва→selection следующего поколения (FFF3–FFF6, G6–G11);
- succession lab на 6 зон с Experiment A и anti-runaway stability (FFF6);
- детерминизм/replay, кроссплатформенная бит-идентичность result_hash Linux↔Windows;
- сохранение инвариантов EVO6-WATER (`7010e307…`) и PH/P1A/P1B/P1C-регрессий через всю линию.

Каждый шаг проведён как отдельный чекпоинт CANDIDATE с независимым FINAL_REVIEW и VERIFICATION (§2 карты доказательств). Поверх FFF6 выполнен ремонт миноров R2 (калибровка потолка pinning 0.25 по кросс-seed данным, канонизация wave2-батареи раннерами `.ps1`+`.sh`, Linux-цепочка-близнец) с вердиктом независимого REVIEWER **PASS** (1 MINOR + 4 NOTE); MINOR-1 (учёт стадий агрегата) исправлен и сертифицирован прогоном 21/21. Визуальный материал G5 (единственный PARTIAL гейт-матрицы) закрыт как machine-captured evidence коммитом `7e3c0ad7`; формальная переклассификация — за свежим line-auditor'ом (§5).

Правило линии: research acceptance ≠ production authority; merge в main — отдельный human gate.

## 2. Индекс пакета доказательств (evidence package)

**Спецификация и планы:**
- `docs/plans/ECO_EVO7_FORM_FUNCTION_FEEDBACK_TECHNICAL_SPEC_RU.md`
- `docs/plans/ECO_EVO7_FFF0_CONTRACT_MAPPING_RU.md`
- `docs/plans/ECO_EVO7_FFF6_SUCCESSION_LAB_DESIGN_RU.md`
- `docs/plans/ECO_EVO7_EVIDENCE_MAP_RU.md` — карта доказательств линии (персистируется вместе с настоящим документом)

**Чекпоинты шагов:** `docs/checkpoints/2026-08-23_ECO_EVO7_FFF{0..6}_R1_RU.md`, ремонт R2: `docs/checkpoints/2026-08-24_ECO_EVO7_FFF6_R2_MINORS_RU.md`

**Независимые review/verification каждого шага:** `docs/evidence/2026-08-23_ECO_EVO7_FFF{0..6}_FINAL_REVIEW_RU.md` и `…_FFF{0..6}_VERIFICATION_RU.md`

**Линейный уровень:**
- `docs/evidence/2026-08-23_ECO_EVO7_LINE_AUDIT_GATES_RU.md` — гейт-матрица G1–G15 (14 PROVEN / 1 PARTIAL-G5), DoD §22, контроли A–D
- `docs/evidence/2026-08-23_ECO_EVO7_MULTISEED_ROBUSTNESS_RU.md` — wave1
- `docs/evidence/2026-08-23_ECO_EVO7_MULTISEED_WAVE2_RU.md` — wave2 (seeds 20260824–26)
- `docs/evidence/2026-08-24_ECO_EVO7_LINE_MINORS_REPAIR_RU.md` — R2: команды, коды выхода, логи, калибровочная таблица, поправка учёта стадий (21/21)
- `docs/evidence/2026-08-24_ECO_EVO7_G5_VISUAL_EVIDENCE_RU.md` — G5-захваты
- `docs/evidence/2026-08-24_ECO_EVO7_R2_MINORS_FINAL_REVIEW_RU.md` — персистированный отчёт независимого REVIEWER (вердикт PASS, диапазон `43f225e2..c3dd4354`)
- `docs/evidence/2026-08-24_ECO_EVO7_G5_CENTRAL_VERIFICATION_RU.md` — центральная верификация G5-захватов

**Раннеры и тесты:**
- `RUN_ECO_EVO7_FFF6_TESTS.ps1` / `RUN_ECO_EVO7_FFF6_TESTS.sh` — полная цепочка FFF6 + зависимости + wave2 + EVO6-WATER guard
- `RUN_ECO_EVO7_MULTISEED_WAVE2_TESTS.ps1` / `RUN_ECO_EVO7_MULTISEED_WAVE2_TESTS.sh`
- `RUN_ECO_EVO6_WATER_SELECTION.ps1`
- `tests/research/ecology/eco_evo7_fff{0..6}_*_acceptance.gd`, `eco_evo7_fff6_pinning_calibration_probe.gd`, `eco_evo7_multiseed_robustness_acceptance.gd`, `eco_evo7_multiseed_wave2_acceptance.gd`
- `scripts/labs/ecology/eco_evo7_form_function_feedback_lab.gd`

**Hash-якоря:** FFF6 `52995cf4bcd03578f6c0df98c0091d2cea0985bc5eb2a6706ea5a78ffedbe436`; EVO6-WATER guard `7010e30707613e2837c45c26e7b516547fc5e35ad88997f93bc62660efecaa6e`; SUCCESSION wave2 `28414a1831f26475` / `876ecd4f96e258a2` / `c047378faadb898f` (Linux == Windows).

## 3. Статус DoD §22 (9 пунктов)

| # | Пункт §22 (кратко) | Статус |
|---|---|---|
| 1 | Одинаковые предки + одинаковые мутации + разные среды → разные наследуемые стратегии | **PROVEN** |
| 2 | Различия видны геометрически при выключенном debug-color | **PARTIAL → материал закрыт**: C-mode скриншоты `7e3c0ad7` + центральная верификация; формальная переклассификация PARTIAL→PROVEN — за свежим независимым line-auditor'ом |
| 3 | Форма меняет свет/воду/почву вокруг себя | **PROVEN** |
| 4 | Изменённая среда меняет selection следующего поколения | **PROVEN** |
| 5 | Feedback ON/OFF дают разных descendants | **PROVEN** |
| 6 | Ни environment, ни renderer не переписывают genome | **PROVEN** |
| 7 | Нет второго mutation/lineage kernel | **PROVEN** |
| 8 | Deterministic replay сохраняется | **PROVEN** |
| 9 | Инварианты EVO6-WATER и ECO.PH не ломаются | **PROVEN** |

Итог: **8 PROVEN + п.2 с закрытым материалом, ожидающим аудиторской переклассификации.** Полные формулировки пунктов и доказательства — `docs/evidence/2026-08-23_ECO_EVO7_LINE_AUDIT_GATES_RU.md`, раздел B.

## 4. Что добавлено данной сборочной ролью (assembly, 2026-08-24)

- Персистация отчёта независимого REVIEWER R2 и центральной верификации G5 в durable evidence (коммит `eb10f460`).
- Механический ремонт MINOR-1: инкремент PASS_COUNT в ветке успеха wave2-стадии `RUN_ECO_EVO7_FFF6_TESTS.sh` (коммит `127f71f2`).
- Сертификационный прогон цепочки после ремонта: exit 0, агрегат `passed: 21 failed: 0`, маркер `[stage] ECO_EVO7_FFF6_REPAIR_SUITE_PASS`, hash-якоря не изменились; поправка зафиксирована в §3 `docs/evidence/2026-08-24_ECO_EVO7_LINE_MINORS_REPAIR_RU.md`.
- Сборка карты доказательств `docs/plans/ECO_EVO7_EVIDENCE_MAP_RU.md` и настоящего proposal.

## 5. Условия принятия, которые ещё НЕ выполнены (обязательны до acceptance)

1. **Свежий независимый line-auditor проход** — формальная переклассификация строки G5 гейт-матрицы и строки п.2 DoD §22 (PARTIAL→PROVEN или иное решение) на основе персистированного материала.
2. **Независимый Verifier данной сборки** — exact-head проверка новых документов, поправки MINOR-1 и сертификационного прогона 21/21.
3. **PC0 NON_RED на каноническом control-пути**, включая Windows-сторону: исполнение `.ps1`-раннеров (на Ubuntu pwsh отсутствует — честное ограничение среды) и аудит CONTROL_PROJECT.
4. **Director-маршрутизация** — перевод proposal в scheduler policy согласно harness.
5. **Human merge gate** — любой merge в main остаётся явным человеческим решением.

## 6. Заявление

Настоящий документ является **предложением** line-level checkpoint. Он не принимает чекпоинт, не изменяет статусы артефактов (все остаются CANDIDATE) и не заменяет ни одной независимой роли из §5.
