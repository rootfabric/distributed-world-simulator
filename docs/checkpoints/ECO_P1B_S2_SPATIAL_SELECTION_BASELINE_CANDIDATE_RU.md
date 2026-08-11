# ECO.P1B-S2 — Spatial Selection Baseline — CANDIDATE

## Статус

`LOCAL_FOCUSED_PASS / EXACT_WINDOWS_PENDING`.

S1 доказал deterministic mutation и inheritance. S2 впервые включает **selection**, но ещё не делает полноценную population ecology: это контролируемые spatial selection chambers поверх accepted P1A truth.

## Главный causal test

В четыре contrasting environment samples (`floodplain`, `sunny_slope`, `shaded_slope`, `dry_ridge`) подаётся один и тот же ancestor и один и тот же deterministic mutation stream.

На первом поколении mutation candidate pool имеет один hash во всех четырёх средах:

`9e4b8eba9d7d6bf915de209814e6edba823f30675c6f2aefa6a209fff135f2fd`.

После этого selected populations уже разные. Значит первичное расхождение не может быть создано site-specific mutation.

## Selection без нового fitness score

S2 не вводит формулу `fitness = ...`.

Для каждого candidate вызывается accepted `PlantResourceModelV1` на environment sample. В следующее поколение проходят candidates с большим `net_resource_balance`; exact ties разрешаются deterministic lineage checksum.

После отбора accepted `SinglePlantPatchSimulatorV1` измеряет biomass/recruitment. Поэтому selection и наблюдаемая biological consequence остаются привязаны к P1A resource truth.

`seed_dispersal_distance_m` на этом шаге не мутирует: его benefit появится только вместе с migration/dispersal. Иначе модель выбрала бы короткий dispersal просто потому, что P1A уже содержит его cost, но S2 ещё не содержит benefit.

## Baseline

- 4 diagnostic environments;
- 16 generations;
- 12 selected individuals на environment;
- 3 offspring на parent;
- 16-season P1A biomass observation;
- одна ancestral lineage.

Default result hash:

`a48df039415162a2e2b75fb9badc12ae35fd0cac9f459ae2ba9df88ab1280e80`.

Second-seed result hash:

`507bcc108d458b685d97b96268d18e307f3cdc36ae0530a75801cddf2e6b8521`.

## Что произошло

Default seed после 16 поколений:

- floodplain root depth примерно `0.85 -> 0.14 m`;
- dry ridge root depth примерно `0.85 -> 1.04 m`;
- floodplain water preference примерно `0.58 -> 0.65`;
- dry ridge water preference примерно `0.58 -> 0.33`;
- shaded slope shade tolerance примерно `0.45 -> 0.56`;
- sunny slope shade tolerance примерно `0.45 -> 0.39`.

Trait divergence:

- water preference `~0.318`;
- root depth `~0.904 m`;
- shade tolerance `~0.195`.

Dry ridge и shaded slope стартуют с отрицательного mean resource balance, но к generation 16 становятся положительными и получают nonzero recruitment.

## Native-environment cross-check

Финальные четыре populations перекрёстно оцениваются во всех четырёх environments. В каждой колонке именно locally selected population имеет лучший accepted net resource balance.

Это сильнее простого утверждения «traits стали разными»: сформировавшиеся differences имеют local resource consequence.

## Второй seed

Второй lineage/mutation seed создаёт другой result hash и другие конкретные genomes, но повторяет феномен:

- dry roots глубже wet roots;
- wet/dry water preference расходится;
- shaded population имеет более высокую shade tolerance, чем sunny;
- каждая native population снова лучшая в собственной среде.

## Local tests

- focused S2: `364/364`;
- fresh-process replay: `6/6`;
- P1A-S1/S2/S3/S4 и P1B-S1 regressions остаются зелёными.

## Граница

Это ещё не migration, не competition между spatial populations и не species formation. Site names используются только как diagnostic coordinates. Никаких biome-specific rules или predefined species нет.

После exact-Windows acceptance можно переходить к следующему P1B шагу: population patches/региональная divergence во времени, где selection уже работает не в независимых chambers, а через spatial population state.
