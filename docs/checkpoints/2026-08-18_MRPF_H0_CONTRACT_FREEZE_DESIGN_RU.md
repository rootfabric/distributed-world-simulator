# MRPF-H0 — Contract Freeze / Offline Hierarchical Composer

**Дата:** 2026-08-18  
**Ветка:** `research/mrpf-h0-contracts`  
**Risk:** `MEDIUM`  
**Статус:** DESIGN BRIEF / IMPLEMENTATION AUTHORIZED BY USER / NOT ACCEPTED

## Problem statement

Будущий hierarchical projection fabric должен уметь сводить `SPACE -> EARTH -> SURFACE -> BASE` representations без duplicate presentation truth и без превращения derived view в canonical state. До сетевых процессов H1+ необходимо заморозить детерминированные representation/replacement contracts.

## Current behavior

SM0 P10 доказал multi-source read-only composition и source fencing, но не формализовал hierarchical coverage/replacement semantics между ancestor/finer layers. MRPF-H roadmap требует H0 до H1-H5.

## Desired behavior

Pure GDScript offline model должен доказать:

```text
SPACE < EARTH < SURFACE < BASE
```

по specificity, при этом:

- stable `canonical_subject_id` сохраняется сквозь LOD/source layers;
- representation имеет source/revision/class/LOD/coverage/reference-frame/hash identity;
- более specific ready layer атомарно заменяет менее specific layer только внутри того же `replacement_group_id`/coverage;
- stale source revision отклоняется;
- same-revision mutation отклоняется;
- exact replay idempotent;
- removal/unavailability fine layer немедленно раскрывает валидный coarse fallback;
- composer exposes presentation only and has no canonical mutation path;
- same inputs produce same composed view hash.

## Alternatives considered

1. Переиспользовать SM0 P10 composer напрямую — отклонено: он donor evidence и не знает hierarchical coverage/replacement contract.
2. Сразу делать process/network H1 — отклонено: replacement ambiguity должна быть снята offline до transport complexity.
3. Встроить H0 в production presentation owner — отклонено: H0 остаётся isolated research donor до post-P6 convergence.

## Selected design

Два self-contained research modules:

```text
mrpf_h0_projection_contract.gd
mrpf_h0_hierarchical_composer.gd
```

Contract валидирует immutable representation DTO и вычисляет deterministic checksum. Composer хранит latest accepted representation per `representation_id`, fence'ит `source_revision`, выполняет deterministic replacement by `replacement_group_id`, выбирая максимальную specificity (`SPACE=0, EARTH=1, SURFACE=2, BASE=3`) и затем стабильный tie-break по `representation_id`.

Unavailability/removal не уничтожает coarse candidates; composition пересчитывает selected view и возвращает fallback.

## Canonical owners affected

```text
canonical gameplay truth: NO CHANGE
authority ownership: NO CHANGE
network protocol: NO CHANGE
persistence: NO CHANGE
Item Graph: NO CHANGE
Construction: NO CHANGE
```

Новый код расположен только в isolated `scripts/runtime/seamless/mrpf/**` + focused tests/runners.

## Dependencies

- MRPF main-owned plan;
- MRPF-H roadmap;
- donor semantics: SM0 P10 read-only projection, RL3 coarse-to-fine representation;
- Godot 4.7.1 double.

## Non-goals

- sockets/processes;
- `ClientConnectionSet`;
- authority handoff;
- Earth/Moon real rendering;
- HLOD generation;
- visibility policy;
- production integration.

## Risks

- ambiguous overlap/replacement semantics;
- hash instability due unordered Dictionary serialization;
- accidental presentation-to-canonical API;
- same-revision mutation acceptance.

## Validation plan

Focused headless Godot test must prove at least:

```text
contract validation
invalid hierarchy/coverage rejection
exact replay idempotence
stale revision rejection
same-revision mutation rejection
SPACE-only composition
EARTH replaces SPACE
SURFACE replaces EARTH
BASE replaces SURFACE
fine removal reveals SURFACE/EARTH/SPACE fallback in order
unrelated replacement groups compose simultaneously
stable subject identity
deterministic output hash across insertion order
presentation_only=true
canonical_state_generated=false
mutation request rejected
```

Target marker:

```text
MRPF H0 hierarchical projection contracts: PASS (... assertions)
```

## Acceptance boundary

Implementer runtime PASS is evidence only. `MRPF-H0 ACCEPTED` requires fresh independent Reviewer + Verifier according to MEDIUM risk routing. No merge to product V0 is authorized by this work.