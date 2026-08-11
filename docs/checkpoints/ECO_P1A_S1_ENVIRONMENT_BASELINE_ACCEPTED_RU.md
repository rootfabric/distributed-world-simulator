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

`109 assertions, 0 failures`

Принятый environment hash:

`b862c4fc529b5fd8229355c4c38b96a429e4ef1d902d6dd86b27860d8ce51af7`

Проверки включают:

- повторяемость sample checksum;
- повторяемость полного fixture hash;
- **безусловную** проверку принятого baseline hash;
- изменение hash при смене seed;
- валидацию exact schema;
- запрет LOD injection;
- причинные различия контрольных точек;
- continuity через выбранные logical cell boundaries по X/Z;
- одинаковый canonical sample для общей координаты при разных sampling resolutions;
- отсутствие camera/network/authority/material/biome-specific ownership в research source.

## Exact Windows confirmation

После исправления fresh-worktree UID-cache preflight пользовательский exact-Windows прогон на checkout `C:\Godot\lunar-world-eco-evolutionary-ecology` выполнил полный Godot import/UID initialization и затем завершился чисто:

`ECO.P1A-S1 Environment Baseline: PASS (109 assertions)`

`ECO.P1A-S1 focused acceptance: PASS`

Environment hash совпал с принятым baseline:

`b862c4fc529b5fd8229355c4c38b96a429e4ef1d902d6dd86b27860d8ce51af7`

Предыдущие `Resource file not found: res://` / autoload errors после теста больше не воспроизводятся. Runner hygiene fix `0f91a48b09b7e1ffb3f8ddbe9e3045c28df5888e` подтверждён на чистом Windows worktree.

## Проверка опубликованного содержимого

После публикации GitHub blobs были сравнены с локально протестированными файлами через Git blob SHA-1:

- `environment_sample_v1.gd` — `7ae8cc2534940ceb3c69879f8850467ba32fea8c`;
- `synthetic_environment_fixture_v1.gd` — `ff7bcff3f825fbb0595fb57d2b85d899a7888a80`;
- `eco_p1a_s1_environment_acceptance.gd` — `afb8faa54a5ef9ac1b5d165dc23d760dab8ba056`;
- accepted manifest — `80b8d900893ddc0e80069b4d431a902a0d53fc7d`.

Опубликованное содержимое совпадает с тем, которое прошло финальный focused run.

## Ограничение проверки

ECO-файлы не подключены к production runtime, поэтому world/core full regression для этого research-only шага классифицирован как `NOT_REQUIRED_RESEARCH_ONLY_UNREFERENCED`.

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

S2 уже реализован как candidate поверх этого принятого EnvironmentSample. Его следующий gate — exact-Windows focused confirmation; после него можно открыть `P1A-S3 Diagnostic Visual Lab + Controlled Trait Probes`.