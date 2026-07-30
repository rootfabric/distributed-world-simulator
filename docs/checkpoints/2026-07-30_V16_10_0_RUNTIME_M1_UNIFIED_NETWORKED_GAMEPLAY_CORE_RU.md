# Checkpoint v16.10.0 — M1 Unified Networked Gameplay Core

## Метаданные

```text
checkpoint: v16.10.0-runtime-m1-unified-networked-gameplay-core
build_id: m1-unified-networked-gameplay-core
base: v16.9.5-roadmap-single-server-multiplayer-first
branch: feature/m1-unified-networked-gameplay-core
status: candidate
```

## Реализовано

- единый `NetworkedGameplayService` для H1 и H3;
- общий `PlayerOwnershipService` для H2/H3;
- `PlayerRegistry`, `PlayerMovementService`, `ItemGraphService`;
- отдельные `ContainerInteractionService` и `MountInteractionService`;
- общий `CommandResultRouter` и `ReplicationPublisher`;
- десять versioned wire contracts и validators;
- H1/H2/H3 compatibility adapters без независимого operation/player state;
- одинаковый canonical state для LOOPBACK и ENET topology adapters;
- runtime descriptor и application checkpoint обновлены до M1.

## Долги A2

```text
A2-D01 CLOSED by M1
A2-D02 CLOSED by M1
A2-D03 OPEN  → M3/M4/M5
A2-D04 OPEN  → M6
```

## Проверки

Focused gate:

```text
RUN_M1_UNIFIED_NETWORKED_GAMEPLAY_TESTS
→ editor import
→ M1 contracts and convergence
→ H1/H2/H3 compatibility
→ real H2/H3/T1 ENet processes
→ A2 and post-A2 roadmap gates
```

Дополнительно обязательны полный network/runtime regression, полный world regression и main-scene smoke.

## Acceptance

- H1 loopback и H3 ENet используют один service implementation;
- H2 использует общий ownership service;
- десять validators независимы от authority implementations;
- одинаковый сценарий LOOPBACK/ENET сходится к одинаковому checksum;
- H1–H3 regressions проходят без topology-specific domain fork;
- direct client authority references остаются равны нулю;
- M2 зафиксирован следующим этапом.

## Результаты локальной проверки кандидата

```text
Editor import:                         PASS
Focused M1 gate:                      14/14 scripts, 874 assertions PASS
Network/runtime regression:           47/47 suites, 3683 assertions PASS
World standalone manifest:            89/90 direct PASS
Main scene playground:                 6/6 PASS
Clean-process world CLI matrix:        moon 5/5, earth 6/6, earth_moon 8/8,
                                       item_lab 5/5, playground 6/6 PASS
JSON validation:                       40 files, 0 errors
GDScript UID coverage:                 411/411, 0 duplicate UID
Wire validator authority dependencies: 0
git diff --check:                      PASS
```

`test_world_boot_matrix.gd` не сообщил assertion failure, но монолитный процесс не завершился
в пределах увеличенного внешнего лимита из-за последовательной тяжёлой загрузки и выгрузки
всех миров в одном Godot-процессе. Те же пять миров отдельно загружены чистыми процессами и
прошли свои реальные runtime test suites. Это ограничение поставочного окружения должно быть
повторно проверено при независимой приёмке; оно не скрывается как прямой `90/90` результат.

