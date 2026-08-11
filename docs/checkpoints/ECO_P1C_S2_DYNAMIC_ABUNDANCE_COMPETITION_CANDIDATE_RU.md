# ECO.P1C-S2 — Dynamic Shared-Patch Abundance Competition — CANDIDATE

## Статус

`LOCAL_FOCUSED_PASS / EXACT_WINDOWS_PENDING`.

S1 показал высокий `top1` pressure, но был статическим ranking snapshot. S2 сохраняет тот же exact founder pool и впервые ведёт biomass каждого founder во времени на каждом patch.

## Механика

- `5×5 = 25` heterogeneous patches;
- 20 founders из принятого S1;
- все founders стартуют с одинаковой biomass;
- 12 competition cycles по 3 сезона;
- growth/recruitment/mortality считает **не новый competition score**, а принятый `SinglePlantPatchSimulatorV1`;
- если сумма предложенной biomass превышает `8 kg/m²`, все founders получают один общий proportional capacity scale;
- mutation, migration и inter-patch reproduction отсутствуют.

## Local evidence

- focused `101/101`;
- fresh-process replay `5/5`;
- result `3e52c4e93fcdefba64607dd2c935ccbddba78db3f400d6a6ea51b23db766982b`;
- uniform `47f0e9c7573bf002151718a57c930d400682c3d86dbd3a8b96b8ddf48c4a01a2`;
- alternate `4706d80289b1fc9918f1758ccabdbb62a76053739f3c7bccadcd282e797d572b`;
- founder pool `77acaada39a39c54224b73f2548ebc228343e869264e45780d08419ebb6bee38`.

Heterogeneous default после 12 cycles:

- effective founders `>=1%`: `19/20`;
- `>=2%`: `15/20`;
- `>=5%`: `6/20`;
- top-1 biomass share: `0.2413`;
- top-1 patch leadership: `0.80`;
- Shannon biomass diversity: `2.5755`.

Uniform control:

- effective founders `>=1%`: `11/20`;
- один и тот же top founder на `100%` patches;
- Shannon biomass diversity `2.3647`.

Alternate seed:

- effective founders `>=1%`: `18/20`;
- top-1 biomass share `0.1905`;
- patch leadership dominance `0.48`;
- Shannon `2.6126`.

## Интерпретация

S1 pressure `~83.7% top-rank` не оказался эквивалентен глобальному takeover. В динамике default founder №14 лидирует по biomass на 80% patches, но владеет только ~24.1% общей biomass. На wet region top founder уже другой, а сама wet community значительно более равномерна.

Это позволяет двигаться дальше к post-hoc trait clustering и multi-seed/long-horizon coexistence gate, не вводя заранее названные стратегии.
