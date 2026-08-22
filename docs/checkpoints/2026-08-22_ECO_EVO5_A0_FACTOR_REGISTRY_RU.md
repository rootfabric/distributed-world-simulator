# ECO.EVO5/A0 — Реестр факторов среды (Site Context)

Статус: `RESEARCH_ONLY / PASS`. Дата: 2026-08-22. Коммит `40dc667f`.

## Контракт

`effective_conditions(site) = base_sample ⊕ Σ modifiers`:

- модификаторы — чистые функции ТОЛЬКО от объявленных входов;
- канонический порядок применения — сортировка по factor_id;
- дельты — целые ppm с clamp [0, 1000000]; температура — подписанные milli_c;
- **fail-closed**: фактор действует только если все его объявленные входы присутствуют в site_features (никаких выдуманных дефолтов);
- расширение = данные: `register_factor(name, inputs, apply)` без правки кода (тест «ash_fall»), дубликаты отклоняются;
- будущий генератор поверхности эммитит факторы данными: `{cavity_depth_m, slope_deg, mineral_deposit: {type, richness}, ...}`.

## Факторы v1

slope (>25° → свет−/влага−), aspect_north (температура±), cavity_shade (свет−−/влага+/инверсия T), snow_cover (T−−/влага+), water_proximity (<8м → влага++/питание+), rock (микротень−/якорь+ establishment_bonus_ppm), mineral_deposit (**mineral_richness_ppm** из richness; поле `type` зарезервировано под expression_requirements генов фазы A).

## Гейты и доказательства

- тесты `tests/research/ecology/test_evo5_factor_registry.py`: **9/9 OK** (детерминизм двойного счёта, независимость порядка вставки, clamp-края, data-only регистрация, fail-closed отказы);
- демо `evo5_a05_broken_plot_demo_v1.py`: **PASS sites=6 divergence=220000 ppm** по свету (равнина/склоны/овраг/рудный хребет/снег); артефакт `validation/ecology/evo5_a05_broken_plot_contexts.v1.json` с провенансом applied_factors на сайт.

Честность: mineral_type/expression_requirements потребляются блоком Genes-v1 фазы A; population truth не вводилась; принятые ядра не тронуты.
