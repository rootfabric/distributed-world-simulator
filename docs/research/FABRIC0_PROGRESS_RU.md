# FABRIC0 — журнал исследовательского прогресса

## FABRIC0.1 — Compositional scalar playground

**Durable branch:** `research/fabric0-compositional-world-fabric-r1`  
**Historical research head:** `2306ad446f7b6f0ee13b0986e38df3ee6d274dee`  
**PR:** `#317` (Draft)  
**Evidence:** `validation/fabric0-compositional-world-fabric-v1-validation.json`  
**Result:** `PASS_RESEARCH_ONLY`, 44 assertions.

Закрыто:

- typed domains;
- generic source/gain/transducer/threshold/gate/integrator/sink;
- switchable function;
- breakable topology;
- reusable feedback pattern;
- tank + heater;
- proximity door;
- deterministic replay.

## FABRIC0.2 — Inline switch + coupled rotational wall

**Historical research head:** `6852d9f04c4403dda83f81895176be8a90eaaca1`  
**Evidence:** `validation/fabric0-compositional-world-fabric-v2-validation.json`  
**Result:** exact double-Godot `70/70 PASS`.

Закрыто:

- Switch стал самостоятельным inline Element;
- battery -> Switch -> lamp реально включает и выключает lamp element;
- тот же Switch переиспользуется в torque domain;
- generic rotational_inertia и viscous_load;
- coupled cycle speed -> reaction torque -> inertia;
- inertia сохраняет движение после отключения drive;
- local discrete work/kinetic-energy identity;
- rotational deterministic replay.

## FABRIC0.3 — Conservation Cell

**Parent research head:** `6852d9f04c4403dda83f81895176be8a90eaaca1`  
**Implementation start commit:** `ee7a643f3efec07804bbff96590616c7adcb7478`  
**Evidence commit:** `93ac63d1f2680380d629993e50e26435a9868bf8`  
**Design:** `docs/research/FABRIC0_3_CONSERVATION_CELL_RU.md`  
**Evidence:** `validation/fabric0-compositional-world-fabric-v3-validation.json`  
**Result:** `PASS_RESEARCH_ONLY`.

Validation:

- FABRIC0.3 focused acceptance: `119/119 PASS`;
- FABRIC0.3 playground: `FABRIC0_3_CONSERVATION_PLAYGROUND_PASS`;
- error scan: CLEAN;
- editor parse/compile scan: CLEAN;
- previous FABRIC0.2 regression: `70/70 PASS`.

Новая архитектурная форма:

- physical ports больше не обязаны иметь causal input/output direction;
- active bond topology автоматически компилируется в Conservation Cells;
- domain объявляет пару `common_quantity × balance_quantity = power`;
- внутри cell common quantity одинакова;
- balance quantities суммируются в ноль;
- local constitutive laws stamp-ятся в equation island;
- ideal common constraints получают неизвестную реакцию через Lagrange multiplier;
- source/sink role определяется знаком solved balance, а не типом устройства;
- multi-cell coupler переносит interaction между cells;
- topology split/merge перекомпилирует equations и после восстановления topology возвращает тот же canonical state hash.

Ключевые опыты:

1. Two-source cell:
   `common=5`, balances `+14,+1,-15`, power `+70,+5,-75`.
2. Topology mutation:
   `1 cell -> 2 cells -> 1 cell`, canonical state restored.
3. Role reversal:
   weak source при `common=8` получает balance `-4` и становится consumer без смены класса.
4. Ideal constraint:
   `common=10`, реакция ideal port `+30`.
5. Impossible physics:
   conflicting ideal constraints -> `CONSTRAINT_CONFLICT`.
6. Floating physics:
   unconstrained difference network -> `SINGULAR_FLOATING_ISLAND`.
7. Two-cell bridge:
   `9.6 -> 4.8`, coupler absorbed power `23.04`.
8. Cross-domain reuse:
   rotational domain использует те же cell semantics:
   `omega=6.666666...`, torque `+6.666666.../-6.666666...`.

Главный вывод:

> topology теперь не просто соединяет вычислительные элементы — topology компилируется в физические уравнения.

Production promotion по-прежнему не заявляется. Текущий numerical backend линейный и dense; units пока metadata; dynamic storage, nonlinear laws, sparse solve и cross-domain power-preserving transforms остаются следующими research gates.

### Следующая фундаментальная граница

`FABRIC0.4 POWER MAP`:

соединить два разных conservation domains универсальным power-preserving multi-port law:

`electrical-like <-> rotational`

с требованием:

`P_left + P_right + P_loss = 0`

и собрать motor-like machine без kernel-класса Motor.
