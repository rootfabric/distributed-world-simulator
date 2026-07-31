# Checkpoint C6 — Mobile Construct

**Дата:** 2026-07-31
**Статус:** IMPLEMENTED CANDIDATE
**База:** принятый C5 fix1, C4 base commit `b985cde`
**Рекомендуемая ветка:** `feature/c6-mobile-construct`

## Цель

Сделать первый mobile construct, чьи возможности выводятся из реальных частей, bonds, provider quorum и зависимостей питания/управления, а не из имени prefab или монолитного robot script.

## Реализовано

- строгий `ConstructionMobileSubsystemDefinition`;
- вычисляемый `ConstructionMobileSubsystemState`;
- checksum-pinned `ConstructionMobileProfile`;
- deterministic compiler;
- profile store и persistence;
- checksum-pinned mobile command;
- command authorizer и generic mobile agent;
- rover fixture с power/control/drive/sensor graph;
- damage, degraded operation, immobilization и repair flow.

## Контрольный rover

```text
chassis
├── battery      → POWER
├── controller   → CONTROL depends POWER
├── wheel ×4     → DRIVE quorum 2/4 depends POWER + CONTROL
└── sensor array → SENSOR depends POWER + CONTROL
```

Поведение:

```text
intact:          MOBILE, max speed 8 m/s
one wheel lost: DEGRADED, max speed 6 m/s
three lost:     IMMOBILE, scan remains
sensor lost:    MOBILE, scan removed
controller lost: dependent drive/sensor OFFLINE
battery lost:   all dependent subsystems OFFLINE
repair:         full profile restored at newer revision
```

## Проверки

```text
C6 contracts:    PASS — 92 assertions
C6 integration:  PASS — 126 assertions
C6 total:        PASS — 218 assertions
C1 compatibility: PASS — 66 assertions
C2A compatibility: PASS — 137 assertions
C3 compatibility: PASS — 194 assertions
C4 compatibility: PASS — 268 assertions
C5 compatibility: PASS — 204 assertions
Editor parse:     PASS
```

## Ограничения C6

C6 не исполняет физическое перемещение и не изменяет network/spatial authority. `ConstructionMobileCommandAuthorizer` только проверяет доступность действия и закрепляет его за текущим profile checksum. Реальный runtime command endpoint должен быть отдельным этапом после принятия контрактов.

## Gate принятия

```text
C1/C2A/C2B/C3/C4/C5 compatibility PASS
C6 focused PASS — 218 assertions
Network N0–M4 PASS
World regression PASS — 113/113 tests, 116 steps
Main-scene CLI PASS — 6/6
git diff --check PASS
```
