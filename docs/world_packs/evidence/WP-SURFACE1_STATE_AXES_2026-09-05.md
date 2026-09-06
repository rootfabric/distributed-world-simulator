# WP-SURFACE1 — Evidence: FIDELITY_AND_EXPOSURE_STATES (2026-09-05)

Track: WP-SURFACE1, branch `work/world-packs-surface1-families-r1`.
Implementation head: `43776f1ff22a118fa4bd3ea96b9830ccb7239e66` (tested_head).

## Что сделано

- `config/world_packs/library/surfaces/state_axes.v1.json` (`dws.world_packs.surface_state_axes.v1`):
  - ось `exposure`: buried / sheltered / exposed / abraded (default exposed);
  - ось `fidelity`: casual / survey / engineering (default casual);
  - `family_conditions` — словарь допустимых presentation-состояний per family
    (regolith: default/fresh/weathered; basalt: +fracture; sand: default/fresh/wind_worked; ice: default/fresh/weathered).
  Все оси presentation-only: физическое состояние, strata depth и Matter-свойства не кодируются.
- Обновлены варианты всех четырёх surface-дескрипторов: явные `exposure` и `fidelity`, состояния приведены к словарю семейства.
- `tests/world_packs/surface_library/test_state_axes.py`: 6 тестов (2 live-инварианта + 4 негативных: состояние вне словаря, неизвестный exposure, неизвестный fidelity tier, отсутствие словаря семейства).

## Validation (на implementation head 43776f1f)

- `python -m pytest tests/world_packs/surface_library -q` → 24 passed.

## Границы

- Изменены только allowed paths WP-SURFACE1. Matter/strata/physical material не тронуты.
- Следующий milestone: RECIPE_FRAGMENT_COMPOSITION.
