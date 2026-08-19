# MRPF-H0 Repair Map R1 — representation identity rebind

**Ветка:** `research/mrpf-h0-contracts`  
**Risk:** `MEDIUM`  
**State:** `FIX_REQUIRED` before H0 review

## Finding

Первый Godot implementation run прошёл `71 assertions`, но bounded post-build critique обнаружил contract defect, не покрытый исходным тестом.

`representation_id` проверял stale/same-revision mutation, однако higher `source_revision` мог сохранить тот же ID и одновременно заменить `source_domain_id`, `source_authority_id` или `publisher_id` при совместимом replacement-group contract.

## Affected module

```text
scripts/runtime/seamless/mrpf/mrpf_h0_hierarchical_composer.gd
```

## Canonical owner

Isolated MRPF research representation contract only. Production canonical gameplay/authority owners не затронуты.

## Entry points

```text
accept_representation(value)
```

## Callers / siblings

Focused caller:

```text
tests/runtime/seamless/mrpf/test_mrpf_h0_hierarchical_projection.gd
```

Sibling semantics checked:

```text
exact replay
same-revision mutation
stale revision
replacement-group binding
coarse fallback
```

## Root cause

Revision fence был связан с mutable payload identity, но не существовал отдельный immutable binding для самого `representation_id`.

## Canonical fix location

В `accept_representation()` при уже известном `representation_id` сравнивать immutable identity projection:

```text
canonical_subject_id
source_domain_id
source_authority_id
publisher_id
representation_class
lod_level
coverage_scope
reference_frame_id
replacement_group_id
domain_level
```

Разрешены изменения только versioned payload/revision fields, например `source_revision`, `content_hash`, `valid_from_revision`, checksum.

Mismatch должен fail closed:

```text
MRPF_H0_REPRESENTATION_IDENTITY_REBIND
```

## Missing test

Добавить higher-revision attempt того же `representation_id` от forged publisher/source и доказать reject без изменения выбранной representation.

## Why this is root fix

Fix привязывает stable representation identity к immutable source/coverage semantics в единственном ingestion entry point. Это предотвращает не только конкретный test case, но весь класс higher-revision source hijack/rebind. Symptom-level special casing конкретного publisher не требуется.