# ECO VIS1.7 — подтверждение и переход к VIS1.8A

Дата: 2026-08-16

Ветка: `feature/eco-vis1-visual-proving-ground`

Точный подтверждённый VIS1.7 / integration base: `42df7f1e7e95bb03bb82cd7b390f48695cc106d1`

## Подтверждённый результат VIS1.7

VIS1.7 проверен пользователем на Windows exact double build Godot `4.7.1.stable.double.custom_build.a13da4feb`.

Наблюдаемое поведение соответствует контракту этапа:

- стрелки Left/Right меняют generation;
- при смене generation меняется PH5-форма representative plants: ветвление, количество/расположение foliage и общая морфология;
- количество representative plants и их placement в VIS1.7 намеренно остаются фиксированными;
- Space запускает дискретное перелистывание поколений, а не continuous morph animation, поэтому на дальней камере изменение может быть визуально слабым;
- canonical VIS1.2 spatial snapshot, biomass и patch layout остаются read-only.

Следовательно, отсутствие изменения count/placement в VIS1.7 не является дефектом. Это сознательная граница этапа: VIS1.7 проверяет temporal lineage/genome -> phenotype -> PH5 geometry при фиксированном representative field.

## Решение для следующего этапа

Следующий этап фиксируется как **VIS1.8A — Population Turnover Field**.

Цель VIS1.8A: сделать дискретную смену поколений заметной и добавить derived population turnover, не объявляя его canonical ecology truth.

VIS1.8A должен добавлять:

1. fitness-ranked survival существующих representatives;
2. mortality части representatives;
3. recruitment новых representatives от surviving parents;
4. реальное наследование genome/lineage через существующий `PlantMutationLineageKernel`;
5. dispersal новых recruits относительно позиции parent;
6. изменение representative count и placement между generation;
7. сохранение source biomass: сумма `represented_biomass_kg` каждого generation должна оставаться равной read-only VIS1.2 biomass;
8. HUD-счётчики `births / deaths / survivors / cumulative births / cumulative deaths`;
9. визуально заметное состояние autoplay: title показывает `PLAY/PAUSE`, generation, representative count и `+births/-deaths`;
10. derived markers: newborn highlight и death-location marker текущего transition.

## Архитектурная граница VIS1.8A

VIS1.8A остаётся лабораторной derived projection:

- `canonical_population_truth = OFF`;
- `canonical_timeline_truth = OFF`;
- VIS1.2 snapshot не мутируется;
- VIS1.2 source biomass не изменяется;
- turnover меняет количество **визуальных representatives**, а не утверждает новое canonical число физических растений;
- recruitment наследует parent genome/lineage, но turnover-параметры и target representative count являются lab policy;
- межpatch-миграция пока не вводится: recruitment остаётся в пределах patch field radius;
- continuous fade/morph transition не входит в VIS1.8A и может быть отдельным presentation polish этапом.

## Проверяемые инварианты VIS1.8A

- generation 0 начинается с 53 representatives из VIS1.7;
- generation > 0 имеет births, deaths и survivors;
- `next_count = survivors + births`;
- `deaths = previous_count - survivors`;
- identities/placement меняются между поколениями;
- recruits имеют parent identity и descendant lineage;
- represented biomass каждого generation точно восстанавливает 11.000 kg source biomass текущего VIS1.2 fixture;
- rewind `0 -> N` воспроизводит тот же field/turnover hash;
- canonical VIS1.2 snapshot до/после turnover идентичен;
- PH5 branches/foliage и VIS1.4 LOD сохраняются.

Статус после реализации: `IMPLEMENTED_CANDIDATE` до Windows exact-build gate и визуальной проверки.
