# EVO ARCH2 A10 — R3 production seam binding

Дата: 2026-09-18. Work Order `EVO-ARCH2-A10-20260918-R3`, HIGH.
Parent: A10-R2 `71d6c832b67e52ba1eb031ce6ddecc8a195bb163`.
R1 world binding parent in ancestry: `cf63b8263c98847daf91d841892bd00761640754`.

## Цель

Доказать реальную композицию A8 ecology seam с production Network/Region contract без нового authority owner.

R3 использует:
- неизменный `snapshot_seam_v1.gd` как A8 ecology state/handoff consumer;
- production `AuthorityRegionDescriptor`;
- production `HandoffTicket` и `handoff_state_machine.gd`;
- A10-R1 `world_binding_v1.gd` как admission к production Region owner/epoch.

## Семантика

Перед handoff:
- A8 cursor принадлежит source Region owner/epoch;
- target Region обязан описывать тот же logical region/space/selector;
- target owner отличается;
- target epoch строго больше source epoch;
- target lifecycle для подготовки — WARM или ACTIVE; `WARM` не даёт права исполнения и допускается только как preparation state.

Bridge формирует только production HandoffTicket. Он не переносит biology сам и не имеет собственной state machine.

После реальной последовательности A8:

`REQUESTED → PREPARING → FROZEN → SNAPSHOT_READY → TARGET_PREPARED → COMMITTED`

должно быть:
- A8 cursor owner/epoch = target Region owner/epoch;
- old source descriptor больше не допускает cursor;
- ACTIVE target descriptor допускает cursor; WARM target descriptor до commit обязан быть отвергнут R1 admission;
- `ecology_payload` byte-identical до/после handoff;
- ticket identity/revision/snapshot hash проходит production machine, не локальную копию протокола.

## Stop/fail closed

Reject:
- другой region id;
- другой universe/instance/space;
- другой partition scheme/revision/selector;
- target owner == source owner;
- target epoch <= source epoch;
- target DORMANT/UNLOADING;
- stale source cursor;
- не-COMMITTED ticket при post-handoff admission.

## Не входит

R3 не меняет biological tick, Matter, Construction, A8/A9 source, Region owner contracts или network state machine.
