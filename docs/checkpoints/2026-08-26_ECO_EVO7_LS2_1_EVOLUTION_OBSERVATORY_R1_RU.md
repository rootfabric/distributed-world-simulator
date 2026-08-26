# ECO.EVO7 LS2.1 — Evolution Observatory R1 — CANDIDATE

Base LS2: `f5c38bde45ae78a8242f8e423d04711ac615499e`.

LS2.1 — измерительный checkpoint поверх LS1/LS2. Биологические формулы, selection и mutation policy не перенастраиваются. Добавляется только read-only наблюдаемость причин и динамики эволюции.

## Наблюдаемые метрики

Для каждого поколения и каждой live-зоны observatory фиксирует:
- lineage richness, Shannon entropy, dominant fraction;
- first fixation generation;
- mean + population variance для fitness, LAI, root depth, root/shoot и height;
- разложение fitness: water-limited resource, establishment, water match, shade adaptation, drought cost;
- realized photosynthetic gain и maintenance cost;
- reconstruction/balance error между компонентами и фактическим shadow fitness.

История хранится только в RAM и детерминированно хэшируется. Polygon показывает текущие observatory-метрики, не получает mutation/reproduction authority и не пишет в world/ecology/persistence/network/XFER.

## Causality / authority boundary

- canonical reproduction остаётся только в LS1 через `LineageExtension.reproduce_bundle`;
- observatory не содержит mutation/reproduction call site;
- biome/scenario labels не участвуют в fitness или mutation identity;
- production Earth остаётся read-only источником среды;
- все production/XFER authority остаются OFF.

## Implementer-side exact Godot evidence

Engine: `4.7.1.stable.double.custom_build.a13da4feb`.

- Live World Shadow baseline: PASS 45 assertions;
- live runtime smoke: PASS 19 assertions;
- LS1: PASS 48 assertions;
- LS2: PASS 51 assertions;
- LS2.1 Evolution Observatory: PASS 89 assertions;
- headless polygon smoke: PASS, generation 0→1, 36 plants, observatory history 2.

LS2.1 — research/integration shadow candidate. Это не FFF7/XFER acceptance и не production ecology authority. Fresh independent Reviewer/Verifier gates остаются отдельными.
