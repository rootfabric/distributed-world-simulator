# ECO.EVO7 Form / Function / Feedback — карта доказательств линии (line-level checkpoint proposal)

**Статус:** DRAFT / CANDIDATE — самопринятия нет; proposal подлежит независимому Reviewer/Verifier и Director-маршрутизации.
**Ветка:** `feature/eco-evo7-fff-r1` · База proposal: `9cc4b93be7c8ad1e9f0c10e0d5e8b656e92cae18` (коммиты персистенции данного документа и proposal-чекпоинта следуют непосредственно поверх базы и содержат только документацию).
**Спецификация линии:** `docs/plans/ECO_EVO7_FORM_FUNCTION_FEEDBACK_TECHNICAL_SPEC_RU.md`
**Правило:** research acceptance ≠ production authority; merge в main — отдельный harness gate.

---

## 1. Линия шагов (каждый: checkpoint CANDIDATE + независимый FINAL_REVIEW + VERIFICATION)

| Шаг | Содержание | Checkpoint | Review | Verification |
|---|---|---|---|---|
| FFF0 | Контракт-mapping аудит PH↔EVO7 | `docs/checkpoints/2026-08-23_ECO_EVO7_FFF0_R1_RU.md` | `docs/evidence/2026-08-23_ECO_EVO7_FFF0_FINAL_REVIEW_RU.md` | `docs/evidence/2026-08-23_ECO_EVO7_FFF0_VERIFICATION_RU.md` |
| FFF1 | PlantFunctionalPhenotype (G1–G3) | `docs/checkpoints/2026-08-23_ECO_EVO7_FFF1_R1_RU.md` | `docs/evidence/2026-08-23_ECO_EVO7_FFF1_FINAL_REVIEW_RU.md` | `docs/evidence/2026-08-23_ECO_EVO7_FFF1_VERIFICATION_RU.md` |
| FFF2 | Морфологическая эволюция, единый lineage kernel (G4/G5/G13) | `docs/checkpoints/2026-08-23_ECO_EVO7_FFF2_R1_RU.md` | `docs/evidence/2026-08-23_ECO_EVO7_FFF2_FINAL_REVIEW_RU.md` | `docs/evidence/2026-08-23_ECO_EVO7_FFF2_VERIFICATION_RU.md` |
| FFF3 | Световая петля (G6/G7/G10/G12) | `docs/checkpoints/2026-08-23_ECO_EVO7_FFF3_R1_RU.md` | `docs/evidence/2026-08-23_ECO_EVO7_FFF3_FINAL_REVIEW_RU.md` | `docs/evidence/2026-08-23_ECO_EVO7_FFF3_VERIFICATION_RU.md` |
| FFF4 | Вода + текстура почвы (G8/G9) | `docs/checkpoints/2026-08-23_ECO_EVO7_FFF4_R1_RU.md` | `docs/evidence/2026-08-23_ECO_EVO7_FFF4_FINAL_REVIEW_RU.md` | `docs/evidence/2026-08-23_ECO_EVO7_FFF4_VERIFICATION_RU.md` |
| FFF5 | Почвенная память / litter legacy (Experiment D) | `docs/checkpoints/2026-08-23_ECO_EVO7_FFF5_R1_RU.md` | `docs/evidence/2026-08-23_ECO_EVO7_FFF5_FINAL_REVIEW_RU.md` | `docs/evidence/2026-08-23_ECO_EVO7_FFF5_VERIFICATION_RU.md` |
| FFF6 | Succession lab, 6 зон, Experiment A (G5 visual / G11 preview) | `docs/checkpoints/2026-08-23_ECO_EVO7_FFF6_R1_RU.md`; ремонт R2: `docs/checkpoints/2026-08-24_ECO_EVO7_FFF6_R2_MINORS_RU.md` | `docs/evidence/2026-08-23_ECO_EVO7_FFF6_FINAL_REVIEW_RU.md` | `docs/evidence/2026-08-23_ECO_EVO7_FFF6_VERIFICATION_RU.md` |

## 2. Сквозные доказательства линии

- **Гейт-матрица G1–G15** (итог аудита: 14 PROVEN / 1 PARTIAL-G5): `docs/evidence/2026-08-23_ECO_EVO7_LINE_AUDIT_GATES_RU.md`
- **DoD §22: 8 PROVEN / 1 PARTIAL (п.2 — визуальный evidence)** — там же. Материал п.2 закрыт коммитом `7e3c0ad7` (см. §4); формальная переклассификация строки — за свежим независимым line-auditor'ом.
- **Мульти-seed robustness wave1:** `docs/evidence/2026-08-23_ECO_EVO7_MULTISEED_ROBUSTNESS_RU.md`
- **Мульти-seed wave2** (seeds 20260824–26, направления 3/3): `docs/evidence/2026-08-23_ECO_EVO7_MULTISEED_WAVE2_RU.md`
- **Регрессионные якоря:** EVO6-WATER `result_hash 7010e307…` неизменен через линию (guard в обоих раннерах цепочки); P1A/P1B-S1 (5834 assertions)/P1C-S4/PH0/PH2 хэши стабильны.

### Кроссплатформенные hash-якоря (Linux == Windows в печатаемых значениях)

| Якорь | Значение | Источник фиксации |
|---|---|---|
| FFF6 succession lab, seed 20260823 | `52995cf4bcd03578f6c0df98c0091d2cea0985bc5eb2a6706ea5a78ffedbe436` | инвариантен через Windows-R1 → Linux-R1/R2 → все G5-захваты (`docs/evidence/2026-08-24_ECO_EVO7_G5_CENTRAL_VERIFICATION_RU.md`) |
| EVO6-WATER evolution guard | `7010e30707613e2837c45c26e7b516547fc5e35ad88997f93bc62660efecaa6e` | константа-стража в `RUN_ECO_EVO7_FFF6_TESTS.ps1/.sh`, бит-идентична прогонам обеих ОС |
| SUCCESSION wave2, seed 20260824 | `28414a1831f26475` | Linux-батарея побитово совпала с Windows-evidence (`…_MULTISEED_WAVE2_RU.md`) |
| SUCCESSION wave2, seed 20260825 | `876ecd4f96e258a2` | там же |
| SUCCESSION wave2, seed 20260826 | `c047378faadb898f` | там же |

## 3. Ремонт миноров R2 (2026-08-24) + независимый REVIEW PASS

**Коммиты ремонта:** `30ccb97d` (fix(eco): калибровка потолка pinning 0.25 по кросс-seed данным — NOTE-2), `cf543e76` (test(eco): канонизация wave2-батареи раннерами `.ps1`+`.sh` + Linux-близнец цепочки), `c3dd4354` (chore(eco): чекпоинт и evidence ремонта), `29c62c65` (chore(eco): верификация закрытия MINOR-1 коммитом c0a70efc и зеркалирование в Linux-цепочке).
Документы: `docs/checkpoints/2026-08-24_ECO_EVO7_FFF6_R2_MINORS_RU.md` + `docs/evidence/2026-08-24_ECO_EVO7_LINE_MINORS_REPAIR_RU.md`.

**Сертификационные прогоны `RUN_ECO_EVO7_FFF6_TESTS.sh`:**

| Прогон | Результат |
|---|---|
| #9 (после ремонта, 2026-08-24, 601 с) | exit 0, `passed: 20 failed: 0`, маркер `[stage] ECO_EVO7_FFF6_REPAIR_SUITE_PASS` |
| #10 (сертификация итоговых байтов, 586 с) | exit 0, идентично #9 |
| Сертификация после учёта MINOR-1 (assembly-роль, `2026-08-24`, ≈583 c по стенному времени лога) | exit 0, агрегат `passed: 21 failed: 0` (21 стадия = 21 учтённая), тот же финальный маркер; result-hash якоря не изменились (FFF6 `52995cf4…`, guard `7010e307…`) |

Прогоны #9/#10 печатали «passed: 20» при фактически 21 исполняемой стадии — дефект учёта MINOR-1 (не fail-closed); исправлен assembly-коммитом `127f71f2`, поправка задокументирована в §3 evidence-дока ремонта.

**Независимый REVIEWER:** вердикт **PASS** на точном HEAD `c3dd4354e155586b5d96d0b606cd7e4e1849af81` (диапазон `43f225e2..c3dd4354`); находки: 1 MINOR (учёт стадий — см. выше) + 4 NOTE (BLOCKER/MAJOR отсутствуют). Персистированный отчёт: `docs/evidence/2026-08-24_ECO_EVO7_R2_MINORS_FINAL_REVIEW_RU.md`. Коммиты `29c62c65` и `7e3c0ad7` лежат вне отрецензированного диапазона (зафиксировано в шапке отчёта).

## 4. G5 визуальный материал (закрытие ограничения №1 FFF6)

- Коммит `7e3c0ad7`: C-mode скриншоты лабы (wide + close) при нейтральном сером материале мешей растений, `result_hash=52995cf4bcd03578…` инвариантен stdout во всех прогонах.
- Финальные артефакты: `artifacts/evo7_fff6_lab_cmode_wide.png` sha256 `539d37ecff21f278856e6d25a9c49c79a3a6a497f2465c85b4ae4d24efcab51b`; `artifacts/evo7_fff6_lab_cmode_close.png` sha256 `40d7c441148d92c1c25ff796b3c9581e1f2330c8ee1de2f9863ca36c09019097`.
- Центральная верификация (визуальная инспекция read_image): `docs/evidence/2026-08-24_ECO_EVO7_G5_CENTRAL_VERIFICATION_RU.md`.
- **Честная оговорка:** материал DoD п.2/G5 закрыт как machine-captured evidence, однако формальная переклассификация строки G5 (и строки п.2 DoD §22) PARTIAL→PROVEN принадлежит свежей независимой line-auditor роли, не реализатору и не сборке.

## 5. Открытые позиции перед proposal

- [ ] Свежий независимый line-auditor проход: переклассификация G5 / DoD п.2 на основе персистированного материала.
- [ ] Независимый Verifier данной сборки (exact-head проверка новых документов и сертификационного прогона 21/21).
- [ ] Windows-сторона: исполнение `.ps1`-раннеров (на Ubuntu pwsh отсутствует) + PC0/CONTROL_PROJECT аудит на каноническом control-пути.
- [ ] Director proposal → human gate на merge/acceptance остаётся за владельцем.

## 6. Явно отложенное (не долги линии)

- FFF7 Scale/XFER readiness: water bucket-pruning, N≥1000, profiling/LOD/persistence boundary/write authority — только после research acceptance.
- Полная fitness-декомпозиция §11; benefit-сторона structural_investment; пластичность новых осей; water-use coupling rsr (хвост E-4).
- Nutrient availability §10; groundwater canonical authority — отдельное архитектурное решение.
