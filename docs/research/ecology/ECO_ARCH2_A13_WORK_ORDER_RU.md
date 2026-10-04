# ECO ARCH2 A13 — Population Scaling Architecture / Work Order R1

Статус: implementation candidate.

База:
99b7b0233a0d2658cba22440b97107d7d48f0ec4
(A12 merged main)

## Цель

A13 начинает переход от просто большего лимита к масштабируемой архитектуре исполнения.

R1 не повышает population ceiling выше A12=256 и не вводит approximate biology.
R1 создаёт deterministic exact worksets: один canonical population tick можно разбить на bounded execution worksets без изменения resource competition, mutation, reproduction, checkpoint bytes или canonical hashes.

## Главный invariant

НЕЛЬЗЯ независимо тикать каждый workset.

A5 остаётся:

1. prepare/sample/demand по worksets;
2. один GLOBAL resource allocation для всей популяции;
3. advance организмов по тем же worksets;
4. merge в canonical id order.

Таким образом workset — только execution partition, а не новый biology owner.

## R1 scope

- versioned population_workset_plan_v1.gd;
- deterministic sorted membership;
- default workset size = 64;
- exact coverage, no duplicate/no skipped member;
- A5 default execution идёт через worksets;
- explicit A5 scheduled execution для sizes 1..256;
- shared EcologyRuntime.step_scheduled();
- scheduler settings не входят в canonical state/checkpoint;
- tampered workset plan fails closed;
- 256-organism A5 exact equivalence: size 1 / 64 / 256;
- dynamic reproduction+mutation exact equivalence across workset sizes;
- identical runtime hashes and checkpoint bytes;
- A12 + A11 exact regressions на том же subject.

## Не входит в R1

- parallel threads;
- sleeping populations;
- asynchronous worksets;
- aggregate/cohort biological dynamics;
- separate per-workset field ownership;
- changing resource allocation order;
- raising population cap above 256.

Следующие A13 increments могут добавлять spatial worksets, sleeping/active scheduling, bounded parallel prepare/advance и fidelity-aware execution только при сохранении R1 exact-equivalence gate.
