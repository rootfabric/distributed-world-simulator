# EVO ARCH2 A10 — R3 production seam binding

Дата: 2026-09-18. Work Order `EVO-ARCH2-A10-20260918-R3`, HIGH.

## Цель

Доказать реальную композицию A8 ecology seam с production Network/Region contract без нового authority owner.

R3 использует неизменные `snapshot_seam_v1.gd`, production `AuthorityRegionDescriptor`, `HandoffTicket` / `handoff_state_machine.gd` и A10-R1 admission.

## Семантика

Перед handoff source cursor обязан проходить ACTIVE R1 admission. Target обязан описывать тот же spatial region, другой owner и больший epoch. **Preparation target обязан быть строго WARM.** ACTIVE target до commit отвергается, чтобы не существовали два одновременно ACTIVE descriptor.

Bridge создаёт production HandoffTicket и не переносит biology сам.

После `REQUESTED → PREPARING → FROZEN → SNAPSHOT_READY → TARGET_PREPARED → COMMITTED`:
- old source descriptor отвергается;
- новый ACTIVE target descriptor допускает cursor;
- WARM descriptor никогда не даёт ECO execution;
- biology bytes/ecology_step не меняются самим handoff.

Reject: другой region/space/selector, same owner, non-increasing epoch, ACTIVE/DORMANT/UNLOADING preparation target, stale source cursor, non-COMMITTED ticket для post-handoff admission.

R3 не меняет production Region/network owners или state machine.
