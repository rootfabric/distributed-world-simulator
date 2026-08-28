# ECO EVO7 / LS3.6 — Rule Workbench R1

## Назначение

LS3.6 — интерактивная research-лаборатория поверх принятых LS3.0–LS3.5.
Она управляет разрешёнными входами эксперимента, шагает ecology только через публичные API и публикует read-only projection/observability.

LS3.6 не является новым biology/selection/mutation authority.

## Causal boundary

```text
world_seed -> deterministic physical patch selector on real Earth
                         |
environment_seed/recipe -> LS3.1 physical EnvironmentField
                         |
                         v
             accepted LS3.4 ecology
                         |
                         +-> existing LS2.1 Observatory spatial extension
                         |
                         +-> LS3.5 post-hoc classifier
                         |
                         v
                 UI / overlays

NO DIRECT EDGE:
Workbench/UI -> genome / mutation / fitness / dispersal / recruitment / competition internals
LS3.5 label -> ecology
```

## ExperimentSpec R1

Публично разрешены только:

- `world_seed`;
- `environment_seed`;
- `environment_recipe`;
- `evolution_enabled`;
- `competition_enabled`;
- environment overlay selector;
- population/lineage overlay selector;
- emergent-biome overlay selector.

Founder / placement / evolution seeds фиксированы внутри R1 Workbench и не являются пользовательскими controls. Это сохраняет одинаковую исходную наследственность при physical counterfactuals.

Любой дополнительный/скрытый control field fail-closes.

## World seed

Production `ProceduralEarthWorld` не имеет runtime setter для terrain seed. LS3.6 не изменяет production config.

`world_seed` детерминированно выбирает центр 32x32 physical patch на реальной Earth вокруг frozen land anchor. Поэтому:

- same world seed -> exact same physical patch hash;
- different world seed -> другой физический patch;
- founder hereditary pool остаётся тем же.

## Environment controls

R1 recipes остаются frozen LS3.1 recipes:

- `WATER_GRADIENT_STRONG`;
- `RELIEF_DRAINAGE_STRONG`;
- `MIXED_PHYSICAL_HETEROGENEITY`.

`environment_seed` меняет только deterministic stochastic structure EnvironmentField.

Physical controls применяются как controlled reset. Live-edit существующей population запрещён.

## Transport controls

- Start;
- Pause;
- Reset same seeds;
- `+1`;
- `+10`;
- `+100`.

Start/Pause управляют только automatic `tick()`.
Manual stepping остаётся explicit.

Allowed step counts R1: `[1, 10, 100]`. Другие значения fail-close.

## Evolution / Competition toggles

Evolution OFF запрещает generation advance.

Competition toggle не может изменять current-generation LS3.3:

- mutation candidate identity;
- dispersal identity;
- recruitment identity.

Competition влияет только на post-recruitment selection, как принято LS3.4.

LS3.5 classification доступна только после валидного post-competition поколения.

## Spatial Observatory

Не создаётся второй metrics stack.

Существующий `eco_evo7_evolution_observatory_v1.gd` получает spatial extension:

- `setup_spatial()`;
- `record_spatial_snapshot()`;
- `get_spatial_latest()`;
- `get_spatial_history()`;
- `validate_spatial_entry()`.

Legacy LS2.1 zone API остаётся неизменным.

Spatial metrics:

- population count;
- occupied cells / occupancy fraction;
- lineage richness;
- Shannon entropy;
- dominant fraction;
- LAI mean/variance;
- root depth mean/variance;
- root-shoot mean/variance;
- height mean/variance;
- water satisfaction mean/variance;
- realized resource balance mean/variance;
- LS3.5 class counts;
- mean cover / continuity / fragmentation.

Spatial entry имеет отдельный `SPATIAL_REVISION = ECO.EVO7-LS3.6.1` и полный deterministic evidence hash.

## Overlay surface

Environment selectors:

- soil moisture;
- surface water fraction;
- temperature;
- elevation;
- incident light;
- drainage.

Population selectors:

- occupancy;
- lineage richness.

Biome selectors:

- emergent biome;
- base biome.

Overlay selection исключён из causal Workbench identity и не меняет ecology state/hash.

## Interactive lab

Scene:

`res://scenes/labs/ecology/eco_evo7_ls36_rule_workbench_lab.tscn`

Lab является тонким UI facade над public Workbench API.

Экран содержит:

- world/environment seeds;
- recipe selector;
- Apply physical controls + reset;
- Start/Pause/Reset;
- +1/+10/+100;
- Evolution/Competition toggles;
- три overlay selectors;
- display-group buttons;
- generation/population/lineage/entropy/class metrics;
- 32x32 diagnostic overlay grid.

UI не читает и не редактирует genomes/records напрямую.

## Authority boundary

```text
world_write                 = false
ecology_direct_write        = false
genome_edit                 = false
mutation_authority          = false
classifier_to_ecology_edge  = false
persistence_write           = false
network_replication_write   = false
renderer_write              = false
```

`renderer_write=false` означает отсутствие production renderer authority. Research UI строит только локальные read-only projection nodes.

## Acceptance R1

Обязательные доказательства:

1. Workbench starts generation 0 / paused.
2. Same-seed reset replays exact patch/environment/heredity/ecology.
3. Recipe changes environment, not patch or founder heredity.
4. World seed changes patch, not founder heredity.
5. Environment seed changes field, not patch or founder heredity.
6. Start/Pause controls automatic tick exactly.
7. Evolution OFF blocks generation advance and preserves ecology state.
8. Competition ON/OFF preserves candidate/dispersal/recruitment hashes.
9. +10 == ten +1 for ecology/classification/spatial Observatory/Workbench identities.
10. +100 is a first-class allowed control using the same deterministic loop.
11. Unsupported step count fails closed.
12. Overlay selector changes do not alter ecology state or causal Workbench hash.
13. All projections cover exactly 1024 cells when source stage exists.
14. Hidden desired-biome controls and invalid recipes fail closed.
15. Workbench snapshot authority/control/source tamper fails closed even after Workbench rehash.
16. Spatial Observatory stale-classification source binding fails closed.
17. Spatial metric tamper fails full entry hash validation.
18. Interactive lab instantiates all frozen R1 controls and one 32x32 grid.
19. Interactive lab display switching is non-causal.
20. Interactive lab +1 facade advances the same public Workbench controller.
21. Causal source audit proves no genome/mutation/dispersal/recruitment shortcut and no LS3.5->LS3.3/LS3.4 edge.
22. Full inherited chain remains green on exact double Godot.

## Stop boundary

LS3.6 does not implement LS3.FINAL multi-environment challenge acceptance itself.
After LS3.6 closure, LS3.FINAL may use Workbench controls to run the frozen same-flora multi-environment proof.
