# ECO.EVO4 — Волна 4: материализация региона (B6) и scale/perf probe (B7)

Статус: `RESEARCH_ONLY / PASS / NO_ACCEPTANCE_CLAIM`. Дата: 2026-08-22.

## E4.B6 — Region materialization: PASS

Источник — **принятая** программа E3.FINAL (`eco-evo3-e3-final-unseen-world-program.generated.json`), комбинация **polar-plateau-04 / extended_r1**: 9 колонизованных видов × 11 патчей.

- Экспортёр `evo4_b6_region_materialization_exporter_v1.py`: каждый ESTABLISHED-патч каждого COLONIZED-вида → популяция 10 экземпляров; сид/позиция/yaw/scale ключуются от `(genome_checksum | stable_spatial_key | instance_index)`; когортный возраст = min(lifespan, 1 + score_ppm/1e5); манифест самодостаточен (species_traits внутри), sha256 `7becec7e119f73b2…`, **990 экземпляров / 9 видов**.
- Геномы расширенного каталога деривируются правилом v0 (тот же контракт, что B1) на лету.
- Лаба `eco_evo4_b6_region_lab.gd`: библиотека 72 визуальных вариантов (9×8), каждый вариант собирается один раз через rich-presenter B0.5 и раздаётся как MultiMesh-трансформации (ветви/листва/цвета делят индексы); обзорная камера, туман, тёплый свет. Прогон **PASS**.

## E4.B7 — Scale/perf probe: PASS с большим запасом

Окно 90 кадров после 30 кадровой прогрева (RTX 4060, OpenGL):

```
avg_fps=165.3  avg_ms=6.05  worst_ms=6.245
draw_calls=653 primitives=849298
```

Бюджет-вход для CONV0-A/WQ-WB: ~1000 богатых инстансов держат >160 FPS; узкое место — draw calls (653), не вершины. Результат записан машиной: `validation/ecology/evo4_b7_scale_probe_result.v1.json`.

## Артефакты

- `validation/ecology/evo4_b6_region_manifest.v1.json`
- `validation/ecology/evo4_b7_scale_probe_result.v1.json`
- Скриншот: `artifacts/evo4_b6_region_materialization.png` (1910 уникальных цветов при дальнем обзоре — ожидаемо для панорамы)

Трекер: B6 → `PASS_REGION_MATERIALIZED`, B7 → `PASS_165FPS_990I`. Лейн E4.B закрыт полностью (B0–B7). Следующий шаг по плану — предизайн **E4.T multi-trophic & coevolution**.
