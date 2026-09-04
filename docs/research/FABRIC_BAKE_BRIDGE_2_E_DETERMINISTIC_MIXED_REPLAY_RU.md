# FABRIC-BAKE BRIDGE-2-E — Deterministic Mixed Replay

**Статус:** IMPLEMENTED CANDIDATE / EXACT DOUBLE PASS.  
**Предшественник:** BRIDGE-2-D Invalidation / Refinement Ordering ✅.  
**Следующий checkpoint:** BRIDGE-2-F / COMPLEX1B Powered Fence Mixed.  
**Production:** не авторизован.

## 1. Цель

BRIDGE-2-D доказал безопасный порядок одного mixed lifecycle. BRIDGE-2-E отвечает на следующий вопрос: повторяется ли этот lifecycle детерминированно в независимых процессах, без зависимости от allocator/history предыдущего запуска?

Доказательная граница состоит из четырёх fresh-process captures:

```text
run A: invalidation
run B: invalidation
run A: recovery
run B: recovery
```

После этого lightweight acceptance композирует два полных replay certificate и требует их полного совпадения.

## 2. Что входит в replay identity

Invalidation capsule замораживает:

```text
event id / sequence / hash
route hash
commit hash
previous/current canonical frontier
old mixed subject / ownership
B2-D ordering trace
stale rejection set
BakeInvalidation identities
B0.2-E transaction checksum
split component identities
fresh structural PhysicalBakeArtifact identities
post-split reduced state hashes
execution-gate hashes
deterministic diagnostics
```

Recovery capsule замораживает:

```text
current canonical frontier
old/fresh ownership contract
B2-D recovery trace
FULL fresh model identity
2 structural split artifact identities
DYNAMIC_ROM fresh artifact + session
HYBRID_BAKE fresh package + session
all five recovery records
final recovery state
```

Full certificate связывает обе половины одним event/frontier/ownership boundary.

## 3. Fresh-process requirement

Два replay run не выполняются последовательно в одном Godot process. Каждый heavy capture получает отдельный process group. Это исключает из доказательства:

- allocator history;
- retained Dictionaries предыдущего mixed subject;
- Godot engine teardown latency;
- accidental session/static contamination.

PASS marker является semantic boundary. После него process group может быть завершён runner'ом, потому что engine teardown не является physical replay state.

## 4. Реальный deterministic result

Pre-publication exact-double result:

```text
invalidation A capsule:
729d79e62a9a48fc31144edd4770c7bf23d8c76df9abf2e18e3c97956cc25a75

invalidation B capsule:
729d79e62a9a48fc31144edd4770c7bf23d8c76df9abf2e18e3c97956cc25a75

recovery A capsule:
6e5b45c59ed2288cb4e4a63bb6df8cfd108bb36a8242f6de240525d5d0b5f84d

recovery B capsule:
6e5b45c59ed2288cb4e4a63bb6df8cfd108bb36a8242f6de240525d5d0b5f84d
```

Full replay certificate:

```text
c96be0141b394aa34ea9a7bb56801ac97ca3a50427d7f8764113d94c0b4ef34c
```

Final mixed state:

```text
ae4d1739e99f71929dcb5dd096eef4bce6de034e5a2846848a3ca38552d31d86
```

Acceptance:

```text
46/46 PASS
```

## 5. Конкретные deterministic identities

```text
route:
a620534b901839ba3a4ef79722fe0c108bcf696d286c75d15f5bad0131e4f423

commit:
977d0cff6559437d1b06e0dcd7a76c6f9c1825a8be011d97d39761ed560a6ce0

frontier:
1d9d5b8e1f6ff0ad53a5ee5fd4d5107adb08d63edd4586624d77838cbad3ea73
→
3841ebef567a038b6b87d190a6c1391f26d66a58a515076ca1410673600cc5da

B0.2-E transaction:
a606954658e0ab87eca2cb1b6ff2280b4ad7ebd56f125e3fbad3767e103ed828

stale set:
91c1c81e03440fb493366e5e6db6d76f1e4f9068ada09e40c86d59840329fb6f

split identity:
d5c4438702f2a50806245dee6ab5a197833f385c3eca95953af666a2b2f3f31d

fresh execution identity:
fb76c21837cf749d09513641aca6fd1e47e3f9514ab3af3223a1dff139513ba3
```

Structural split artifacts in both independent runs:

```text
cbb0ad19330ae490abc1e479329466d183fa4d8ec3813b51f33e8ad76dc6cf1a
fe1c53df921dd10dff3f39caadb0712fbe9a1217da9e7aaa09190ff299c00421
```

## 6. Replay falsifiers

Acceptance intentionally proves that replay is not merely “both runs PASS”. It rejects:

- different route identity;
- different structural split artifact identity;
- invalid invalidation/recovery linkage;
- different fresh execution identity;
- any field-level difference in the full certificate.

A structurally valid capsule with a different route still fails `compare_replays()` with `BRIDGE2_E_REPLAY_MISMATCH`.

A changed split artifact cannot even compose with the recovery half and fails `BRIDGE2_E_STRUCTURAL_RECOVERY_LINK_MISMATCH`.

## 7. CONTACT_BAKE semantics remain fail-closed

Determinism does not weaken B2-D's contact result:

```text
CONTACT_BAKE
→ STALE
→ DEFERRED_REDERIVE
```

Both independent recovery capsules must contain the same empty fresh contact identity set until canonical component/contact attachment mapping exists.

## 8. Exact engine

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Final GitHub exact-source replay is recorded separately in the validation record after implementation HEAD is frozen.

## 9. Что B2-E не доказывает

BRIDGE-2-E не заявляет:

- functional/electrical causal equivalence with COMPLEX1A;
- powered-fence mixed E2E;
- redundant power-path behavior;
- BRIDGE-2 CLOSED;
- production acceptance.

Это уже задача BRIDGE-2-F / COMPLEX1B.

## 10. Roadmap boundary

```text
BRIDGE-2-A ✅ ownership
BRIDGE-2-B ✅ executable mixed subject
BRIDGE-2-C ✅ event routing
BRIDGE-2-D ✅ invalidation/refinement ordering
BRIDGE-2-E ✅ deterministic mixed replay candidate
        ↓
★ BRIDGE-2-F / COMPLEX1B — Powered Fence Mixed E2E ★
```
