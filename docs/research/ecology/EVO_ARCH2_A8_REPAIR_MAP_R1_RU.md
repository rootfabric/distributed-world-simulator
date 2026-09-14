# EVO ARCH2 A8 — Repair Map R1

Основание: fresh whole-A8 review PR #630, exact reviewed HEAD `695904f7cf5adab5c8466ad37c4dccba8a79df63`, P1 comment `3999708328`.

## Дефект

`SnapshotStore._load()` доверяет синтаксически корректному `CURRENT`. Если после уже подтверждённого A→B commit pointer будет восстановлен к более старому валидному tip (включая `000...0`), внутренние immutable records/blobs сами по себе не доказывают, какой cut был последним подтверждённым. Неанкерованный restart мог принять старую lineage и тем самым нарушить A8 no-silent-owner-rollback.

Нельзя исправлять это правилом «ZERO + любые blobs/records = corruption»: crash до pointer commit законно оставляет orphan blobs/records при прежнем tip, включая ZERO до первого commit. Такие orphans не являются опубликованным состоянием.

## Canonical fix location

Исправление находится в boundary самого local durable store и его caller contract, а не в биологии A7/A8 и не в canonical network handoff.

- Public `load` требует **внешний durable anchor** `{tip, sequence, snapshot_sha256}`.
- Anchor представляет последний подтверждённый caller-ом durable checkpoint и хранится вне store directory / его mutable CURRENT.
- Current допустим, только если он равен anchor или является его проверенным descendant в полной immutable chain. Более старый tip, alternate branch или valid ZERO после подтверждённого commit fail closed.
- `commit` принимает exact expected anchor, а не один tip string: текущий durable head должен совпасть с ним полностью перед публикацией нового snapshot.
- При ambiguous acknowledgement caller выполняет `load(last_acknowledged_anchor)`: новый descendant допустим и становится новым anchor; rollback ниже anchor запрещён.
- Потеря external anchor — fail closed (`EXTERNAL_DURABLE_ANCHOR_REQUIRED`), не повод считать store пустым.

Store не делает anchor глобальной authority, distributed consensus или security credential. Для A8 integration test anchor сохраняется в отдельной caller-owned durable directory и fsync-ится после каждого acknowledgement. Production crash journal / replicated consensus остаются за границей A8.

## Negative / positive controls

Обязательные новые falsifiers:

1. acknowledged sequence N → `CURRENT=ZERO` → anchored load rejects;
2. acknowledged N → `CURRENT` valid previous tip N-1 → rejects;
3. acknowledged N → `CURRENT` alternate orphan descendant от N-1 → rejects;
4. ambiguous crash после pointer replace: anchor N-1 → current N descendant accepted, затем caller advances anchor;
5. crash до pointer replace: anchor N-1 → old current N-1 accepted despite orphan blob/record;
6. malformed/missing/type-confused anchor rejects;
7. commit with stale/incomplete anchor rejects without pointer change;
8. concurrent CAS still one commit/one conflict with exact anchors;
9. full real-Godot semantic replay remains before/after durable storage.

Accepted A0-A7, network handoff, registry/scheduler/project.godot remain byte-identical. Old exact run/review evidence for `695904f7...` becomes historical after Repair R1. Fresh exact Linux + fresh whole-A8 review are required on the new frozen HEAD.
