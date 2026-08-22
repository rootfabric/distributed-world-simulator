# ECO.EVO4 — Волна 3: гейты пластичности (B3) и разнообразия (B4)

Статус: `RESEARCH_ONLY / GATES_PASS / NO_ACCEPTANCE_CLAIM`.
Дата: 2026-08-22. База: ветка после B0.5-спайка и верифицированной волны 2.

## E4.B3 — Sealed plasticity gate: PASS 16/16

Паттерн seal → verify (по образцу E3.FINAL):

1. **Seal** (`evo4_b3_plasticity_gate_v1.py seal`): 16 предрегистрированных направлений (2 вида × 8 проб: LIGHT_LOW/HIGH, SOIL_DRY/WET, NUTRIENT_POOR/RICH, DISTURBANCE_STRESS/STUNT) записаны в `evo4_b3_sealed_predictions.v1.json`, digest привязан в `.seal.json` + SHA входного B1-артефакта.
2. **Verify**: печать вскрыта и сверена (`seal_ok=True`); компилятор B2 проиграл базовые/возмущённые условия через принятый point-sampling контракт; знаки дельт метрик (height/crown/branch_prob scales, stress_index, effective max_height) сошлись с предрегистрированными во всех 16 случаях.
3. **Детерминизм**: двойной прогон verify → result-артефакт байт-в-байт идентичен.

Честность: направления — объявленные ожидания контракта `evo4-b2-plasticity-v0`; гейт доказывает консистентность пайплайна, межвидовую согласованность и детерминизм, а не слепой прогноз.

## E4.B4 — Diversity + fingerprint gate: PASS

`evo4_b4_diversity_fingerprint_gate_v1.py` по effective traits из B2 (8 полей, нормировка PH0-bounds):

- **Coverage**: дисперсия датасета 0.007402 ≥ порога 0.005 — коллапса нет;
- **Silhouette fingerprint**: межвидовое расстояние центроидов alpha-late↔beta = 0.4836 при требовании > 0.0830 (маржа ×1.5 к внутривидовому разбросу) — запас ×5.8;
- **Кросс-слойная когерентность**: архетипы листа, выведенные python-зеркалом GDScript-рецепта хеширования, дают 2 различных идентичности видов (needle / lanceolate) — рендер-слой и питон-слой согласованы.

## Plasticity preview (визуал)

`scenes/labs/ecology/eco_evo4_b3_plasticity_preview_lab.tscn`: один геном `genome/e22-beta` в трёх условиях (BASELINE / LIGHT_HIGH / DISTURBANCE_HIGH), эффективные traits из гейта → богатый рендер B0.5. Прогон PASS; подписи условий с высотой/кроной прямо в кадре; `artifacts/evo4_b3_plasticity_preview.png` (7011 уникальных цветов).

## Артефакты волны

- `validation/ecology/evo4_b3_sealed_predictions.v1.json` + `.seal.json`
- `validation/ecology/evo4_b3_plasticity_gate_result.v1.json`
- `validation/ecology/evo4_b3_preview_subjects.v1.json`
- `validation/ecology/evo4_b4_diversity_gate_result.v1.json`
- Скриншоты вне Git по правилу artifacts/.

Трекер: E4.B3 → `GATES_PASS_SEALED_16_16`, E4.B4 → `GATES_PASS`. Волна 4 (materialization региона + scale/perf probe) — следующий dispatch.
