# ECO.PH1 — Deterministic GrowthGraph Skeleton Lab — ACCEPTED

Статус: `ACCEPTED`.

Exact Windows evidence на checkout `5bb956fdc06104fdd2e7326207d954154b9a1e35`:

- focused `128/128`;
- visual headless smoke `10/10`;
- fresh-process restart `4/4`;
- base graph hash `6470722b770afee48def9ee06cc44a36640734abc9fc362a2fed6eb648779451`.

Graphical gate: `PASS_BY_USER_OBSERVATION`. Интерактивное Godot-окно открылось; переключение probes работает; BASE и ANGLE_NARROW визуально дают разные front/top skeleton projections. Текущий renderer принят как **debug-grade skeleton visualization**, а не как конечная графика растения.

Архитектурная фиксация будущей сложности: `GrowthGraph -> PlantRenderDescription -> RendererProfile -> LOD`. Branch tubes, instanced foliage, canopy approximation, full procedural representation и impostor/billboard должны быть сменными consumers одного GrowthGraph и не иметь права менять ecology/genome/GrowthGraph truth hashes.

Никаких canonical `TREE/BUSH/GRASS` типов или отдельных Tree/Bush/Grass generators не вводится.

Решение: `ECO.PH1 ACCEPTED -> ECO.PH2 Environment-Coupled Development / Plasticity OPEN`.
