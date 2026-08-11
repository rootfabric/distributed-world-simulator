# ECO.P1C-S1 — Unlabeled Founder Pool and Shared-Field Competition Baseline — CANDIDATE

## Статус

`LOCAL_FOCUSED_PASS / EXACT_WINDOWS_PENDING`.

P1B доказал local adaptation одной ancestral lineage. P1C задаёт другой вопрос: может ли одна неоднородная планетарная среда поддерживать несколько конкурирующих жизненных стратегий вместо одного глобального optimum.

## S1 граница

S1 пока **не** является финальным coexistence proof. Он создаёт общий deterministic pool из 20 небольших continuous variants вокруг принятого baseline genome. Никаких `DrySpecies`, `WetPlant`, `Pioneer` или `CanopyTree` в initialization нет. У founders нет semantic strategy labels.

Каждый founder имеет отдельный provenance lineage, но во время самого S1 mutation выключена: мы сначала хотим увидеть чистую конкуренцию уже существующего continuous strategy pool.

## Competition rule

В каждом из `7×7 = 49` patches все 20 founders оцениваются через accepted P1A consequences. Retained set — 4 лучших по лексикографическому набору уже существующих biological consequences: cumulative recruitment, final biomass, final net resource balance и genome checksum как deterministic tie-break. Нового `fitness = ...` нет.

## Heterogeneous field vs uniform control

На реальной heterogeneous fixture:

- persistent founders: `15/20`;
- founders, которые хотя бы где-то стали top-1: `5`;
- winner-slot dominance: `0.2143`;
- top-1 dominance: `0.8367`;
- Shannon winner diversity: `1.9955`;
- distinct patch retained sets: `49`.

Uniform control использует **точно тот же founder pool**, но один mean environment во всех patches:

- persistent founders: `4`;
- top-1 founders: `1`;
- distinct patch retained sets: `1`;
- top-1 dominance: `1.0`.

Это сильный первый сигнал, что spatial environmental heterogeneity создаёт niche capacity для большего числа стратегий.

## Trade-offs подтверждены отдельно

Controlled pairs на accepted P1A model показывают:

- height добавляет `+0.25495` structural/maintenance cost;
- deeper root добавляет `+0.28760` root cost, помогает dry (`+0.17321 net`), но вредит floodplain (`-0.37087 net`);
- fast growth добавляет `+0.143` maintenance/allocation cost;
- высокий seed_count добавляет `+0.054` reproduction cost, но даёт `+0.00868` recruitment;
- high shade tolerance улучшает shaded gross income на `+0.25839`, но ухудшает sunny net на `-0.14132`;
- lifespan `8y` уменьшает turnover mortality относительно `2y` на `-0.01555`.

## Known pressure

В default seed один founder выигрывает top-1 примерно в `83.7%` patches. Это ниже fail-pattern `99% world domination`, но всё ещё слишком высоко для финального P1C acceptance.

Поэтому S1 не объявляет coexistence доказанным. Следующий шаг должен добавить dynamic abundance / shared-patch frequency competition и проверить, сохраняется ли несколько стратегий во времени или этот founder действительно превращается в глобальный optimum.

## Determinism

- result: `cf3bd5f417c9a49dd1c5eac0d93ea736b02ec0be25afd4945b1424a8dbde3928`;
- uniform: `1c5128666314dfeec9ed09094931be58e76253f92bf9da50379a91eeb3b68a58`;
- alternate founder seed: `bded62e12ade0285c019d0dc2e4f77d0d6cb88431df7ade605160e0f18d82f8c`;
- default founder pool: `77acaada39a39c54224b73f2548ebc228343e869264e45780d08419ebb6bee38`.

Local focused: `116/116`; fresh-process replay: `5/5`.

Следующий шаг после Windows acceptance: **P1C-S2 Dynamic Shared-Patch Abundance Competition**.
