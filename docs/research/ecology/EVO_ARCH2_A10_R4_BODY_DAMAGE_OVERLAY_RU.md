# EVO ARCH2 A10 — R4 persistent body damage overlay

Дата: 2026-09-18. Work Order `EVO-ARCH2-A10-20260918-R4`, HIGH.
Parent: A10-R3 `d387bece70a563729c974793ddeac806e421c9cf`.

## Проблема

R1 уже переводит exact C9 Construction damage в ECO body-module event, но сам event ещё не является устойчивым world state. Нельзя менять принятую A5 schema на месте: её resource conservation предполагает, что текущий список modules равен исторически оплаченному development state.

Поэтому R4 вводит **additive world damage overlay** поверх неизменного biological state.

## Binding

`body_construction_binding_v1.gd` связывает:
- exact valid BodyGraph;
- exact valid source ConstructSnapshot;
- explicit one-to-one `part_id → module_id` map.

Binding хранит:
- `body_hash`;
- `construct_id`;
- `source_snapshot_checksum`;
- mapping;
- mapped/unmapped module IDs;
- явный scope `PARTIAL_PHYSICAL_PROXY`.

Непокрытые модули не объявляются физически представленными.

## Persistent overlay

Genesis overlay пустой и привязан к exact binding.

Применение A10-R1 damage event:
- проверяет event seal;
- требует совпадение construct/source snapshot/body hash;
- требует точное совпадение event part/module с binding;
- `DEGRADED` помечает mapped module degraded;
- `DESTROYED` помечает direct module destroyed и делает его descendants structurally disabled;
- повтор того же `damage_id` с тем же event hash идемпотентен;
- тот же `damage_id` с другими bytes — conflict.

Overlay имеет revision, applied damage receipts и собственный checksum; он сериализуем как обычный canonical Dictionary. При восстановлении checksum из самого файла недостаточен: `admit_overlay()` требует caller-owned external expected checksum. Кроме того, `disabled_modules` обязан точно равняться structural closure всех `destroyed_modules` по BodyGraph, поэтому пересчитанный локальный checksum не может узаконить произвольное отключение ветвей.

## Effective function

R4 не переписывает A5 state. Вместо этого из `BodyGraph + overlay` строится effective functional projection:
- active module count;
- collector area;
- absorber reach;
- support/transport material proxy;
- degraded/destroyed/disabled IDs.

Это даёт A11 честный вход для world-bound lifecycle/presentation: физически уничтоженная ветвь уже не должна считаться активным collector, даже если immutable historical A5 state хранит факт, что она когда-то была выращена и оплачена.

## Не входит

- возврат destroyed tissue в Matter;
- лечение/repair биологического модуля;
- изменение A5 resource ledger;
- окончательная A11 lifecycle loop.
