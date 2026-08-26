# ECO.EVO7 LS2 — Live Ecology Polygon R1 — CANDIDATE

LS2 — presentation-only полигон поверх LS1 RAM-only live evolution session.

## Что видно

- 3 детерминированные live-зоны одного регионального участка `ProceduralEarthWorld`;
- 12 растений в каждой зоне (36 visual plants);
- геометрия: высота, размер/плотность кроны и глубина корня из текущего LS1 phenotype;
- HUD: generation, moisture, sunlight, water satisfaction, fitness, LAI, root depth, dominant lineage;
- controls: Start/Pause, +1, +10, +100, Reset same seed, Evolution ON/OFF.

`+100` ставится в очередь и исполняется поколение-за-поколением, поэтому UI не делает один длинный блокирующий вызов.

## Authority boundary

Полигон не вызывает mutation API напрямую — mutation остаётся только внутри LS1 через canonical `LineageExtension.reproduce_bundle`. LS2 не имеет world/ecology/persistence/network/XFER writes. Production Earth используется только как источник live environment data.

Это shadow/integration candidate. Он не является FFF7/XFER acceptance и не активирует production ecology authority.
