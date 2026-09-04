# FABRIC-BAKE BRIDGE-2-D — Invalidation / Refinement Ordering

**Статус:** IMPLEMENTED CANDIDATE / EXACT DOUBLE PASS.  
**Предшественник:** BRIDGE-2-C Cross-Representation Event Routing ✅.  
**Следующий checkpoint:** BRIDGE-2-E Deterministic Mixed Replay.  
**Production:** не авторизован.

## 1. Цель

BRIDGE-2-C доказал, что событие от активного representation проходит к существующему canonical commit owner и read-only observers ровно один раз. BRIDGE-2-D фиксирует, что последствия canonical mutation применяются в единственно безопасном порядке.

```text
0  REFINEMENT_GUARD_TRIGGERED
1  LOCAL_FULL_REFINEMENT_READY
2  CANONICAL_COMMIT_CONFIRMED
3  SOURCE_INVALIDATION_PUBLISHED
4  REDUCED_REPRESENTATIONS_MARKED_STALE
5  STALE_EXECUTION_REJECTED
6  STRUCTURAL_SPLIT_REBAKE_READY
7  FRESH_REPRESENTATIONS_REBOUND
8  FRESH_EXECUTION_RESUMED
```

Ни один reduced artifact не может исполниться между canonical source revision и его invalidation/rebind.

## 2. Реальный event path

Используется тот же canonical `COMPLEX0-500`, что и в B2-B/C.

```text
impact
→ structural refinement guard
→ bounded local FULL unbake
→ canonical bond break
→ B2-C canonical commit
→ RepresentationInvalidation
→ BakeInvalidation(SOURCE_REVISION)
→ stale rejection
→ B0.2-E split/rebake
→ fresh ownership/source bindings
→ fresh execution
```

Canonical frontier реально меняется:

```text
before:
1d9d5b8e1f6ff0ad53a5ee5fd4d5107adb08d63edd4586624d77838cbad3ea73

after:
3841ebef567a038b6b87d190a6c1391f26d66a58a515076ca1410673600cc5da
```

Event remains:

```text
topology-event/complex0-0500-break
```

## 3. Stale execution prohibition

После source revision старые derived representations не просто помечаются устаревшими; их реальные runtime gates обязаны отказать.

```text
STRUCTURAL_BAKE
→ STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN

CONTACT_BAKE
→ B0_3_EXECUTION_FORBIDDEN
  → STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN

DYNAMIC_ROM
→ DYNAMIC_ROM_PHYSICAL_BAKE_EXECUTION_FORBIDDEN
  → STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN

HYBRID_BAKE
→ B0_5_A_MODE_EXECUTION_FAILED
  → DYNAMIC_ROM_PHYSICAL_BAKE_EXECUTION_FORBIDDEN

stale hybrid cache resolution
→ FALLBACK FULL
→ SOURCE_FRONTIER_CHANGED
```

Это не synthetic state flag: каждый результат получен через существующий execution gate соответствующей закрытой ветки.

## 4. Structural recovery

B0.2-E выполняет реальный split/rebake после break:

```text
split_component_count                  = 2
invalidated_reduced_piece_count        = 3
fresh executable structural artifacts = 2
post_split_reduction_ratio             = 250x
duplicate_event_count                  = 0
max_state_handoff_error                <= 1e-8
```

Invalidation trace identity:

```text
726b2b2191f64a59620cee3af0cd348d6f9b81ab37026b917a6e9a50e884eb3b
```

## 5. Fresh rebind / execution resume

После split новый source frontier получает новый mixed ownership binding.

```text
old ownership:
5b58cdb94b959be41d7b8450f423e540ca393ac8a7469ea1e81002c6a214ec42

fresh ownership:
cc45b9d45c0a1cba948103bbff811794ba6e457f6d30ad39a1a9f761b2ca14d4
```

Recovery contract:

```text
FULL
→ RECOMPILE_FULL_ON_CURRENT_FRONTIER
→ FRESH_EXECUTABLE

STRUCTURAL_BAKE
→ LOCAL_FULL_SPLIT_REBAKE
→ 2 SPLIT_FRESH_EXECUTABLE artifacts

CONTACT_BAKE
→ DISCARD_AND_REDERIVE_AFTER_COMPONENT_ATTACHMENT
→ DEFERRED_REDERIVE

DYNAMIC_ROM
→ RECOMPILE_ROM_ON_CURRENT_FRONTIER
→ ACTIVE

HYBRID_BAKE
→ LAZY_COMPILE_MODE_ON_CURRENT_FRONTIER
→ ACTIVE
→ B0_5_A_FLOW_ACCEPTED
```

Recovery trace identity:

```text
743fe190810cc1bb43f078cea7b182fac324cbd50240e11191441585f60b0403
```

## 6. CONTACT_BAKE fail-closed result

После structural split старый contact representation нельзя автоматически присоединить к произвольному новому fragment. Без canonical component/contact attachment mapping правильное состояние:

```text
CONTACT_BAKE
→ old artifact STALE
→ transient contact state discarded
→ DEFERRED_REDERIVE
```

Попытка сразу объявить новый contact artifact `ACTIVE` без attachment mapping отклоняется контрактом `BRIDGE2_D_CONTACT_RECOVERY_CONTRACT_MISMATCH`.

Это намеренный safety result, а не недостающая реализация.

## 7. Ordering falsifiers

Executable contract отклоняет:

- перестановку canonical commit и source invalidation;
- recovery без нового ownership/source binding;
- trace без изменения canonical frontier;
- некорректный proof hash любой стадии;
- fake post-split CONTACT_BAKE attachment;
- неполное recovery coverage по пяти representation kinds.

## 8. Fresh-process evidence boundary

Две тяжёлые границы запускаются в отдельных Godot process groups:

```text
invalidation ordering
85/85 PASS

recovery ordering
59/59 PASS
```

Причина разделения не физическая: Godot иногда долго освобождает большие nested Dictionaries уже после финального PASS marker. Runner ждёт final PASS marker и отсутствие `SCRIPT ERROR`, после чего завершает process-group; engine teardown не считается частью physics acceptance.

Canonical engine:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Pre-closure local exact logs:

```text
invalidation:
3a3f806d8075526b9f53f0b17cb03e7318e24ef79cd08b80382a2f5ea9aa815c

recovery:
cd7f51f5fbe580aadf2ce35938f1566af62fc02b834b13960fefd2c6223c1f62
```

Final GitHub exact-source replay is bound separately in the validation record.

## 9. Не доказывает

BRIDGE-2-D не заявляет:

- deterministic mixed post-event replay across independent runs;
- shared mixed timeline replay certificate;
- COMPLEX1B functional/electrical causal E2E;
- BRIDGE-2 CLOSED;
- production acceptance.

Эти требования начинаются с BRIDGE-2-E.

## 10. Roadmap boundary

```text
BRIDGE-2-A ✅ Mixed Representation Ownership
        ↓
BRIDGE-2-B ✅ Executable Mixed Subject
        ↓
BRIDGE-2-C ✅ Cross-Representation Event Routing
        ↓
BRIDGE-2-D ✅ Invalidation / Refinement Ordering candidate
        ↓
★ BRIDGE-2-E — Deterministic Mixed Replay ★
        ↓
BRIDGE-2-F / COMPLEX1B Powered Fence Mixed
```
