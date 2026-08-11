# ECO.P1A-S1 — Environment Contracts + Deterministic Fixture — ACCEPTED

## Решение

`ECO.P1A-S1` принят как **research-only focused baseline**.

Он доказывает первую необходимую часть `ECO.P1A Environmental Causality Baseline`: окружающая среда может запрашиваться по координате детерминированно, без biome labels, без зависимости от LOD/camera и без владения production G/Matter/authority foundations.

## Что реализовано

- `EnvironmentSampleV1` с точной схемой, checksum и validation.
- Synthetic fixture `4 km × 4 km`, логическая сетка `128 × 128`.
- Пять полей:
  - `temperature_c`;
  - `soil_moisture`;
  - `sunlight`;
  - `nutrients`;
  - `flood_frequency`.
- Восемь контрольных точек: river bank, floodplain, wet lowland, lower/sunny/shaded slope, plateau, dry ridge.
- Stable fixture hash поверх всех `128 × 128` canonical samples.
- Focused headless acceptance test и Windows PowerShell runner.

## Focused evidence

Проверено на:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`

Результат:

`108 assertions, 0 failures`

Принятый environment hash:

`b862c4fc529b5fd8229355c4c38b96a429e4ef1d902d6dd86b27860d8ce51af7`

Проверки включают:

- повторяемость sample checksum;
- повторяемость полного fixture hash;
- изменение hash при смене seed;
- валидацию exact schema;
- запрет LOD injection;
- причинные различия контрольных точек;
- continuity через выбранные logical cell boundaries по X/Z;
- одинаковый canonical sample для общей координаты при разных sampling resolutions;
- отсутствие camera/network/authority/material/biome-specific ownership в research source.

## Ограничение проверки

Execution container не имел прямого DNS-доступа к GitHub, поэтому полный repository checkout не мог быть клонирован. Focused test запускался в минимальном Godot checkout, собранном из exact ECO source/config/test файлов, на предоставленном Godot double binary. ECO-файлы не подключены к production runtime, поэтому world/core full regression для этого research-only шага классифицирован как `NOT_REQUIRED_RESEARCH_ONLY_UNREFERENCED`.

Перед финальным handoff опубликованные GitHub-файлы повторно сверяются с локально протестированными версиями.

## Что этот checkpoint пока НЕ доказывает

Он не доказывает:

- рост растения;
- resource economics;
- biomass stability;
- trade-offs traits;
- mutation/evolution;
- population truth;
- visual ecology lab.

## Следующий шаг

`ECO.P1A-S2 — Single-Plant Resource Model`.

На том же принятом EnvironmentSample вводится один фиксированный plant genome. Следующий эксперимент должен показать причинный energy/resource balance и получить favourable / marginal / unsustainable зоны без evolution и без hardcoded biome roles.
