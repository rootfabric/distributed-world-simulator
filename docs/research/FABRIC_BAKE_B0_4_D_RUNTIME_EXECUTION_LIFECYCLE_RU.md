# FABRIC-BAKE B0.4-D — Runtime Execution / Lifecycle

## Статус

```text
IMPLEMENTATION CANDIDATE
B0.4-A/B/C CONTRACTS PRESERVED
CANONICAL PHYSICAL SOURCE OWNERSHIP PRESERVED
INDEPENDENT EXACT-HEAD DOUBLE VERIFICATION REQUIRED FOR CLOSED
NOT PRODUCTION ACCEPTED
```

## Цель

B0.4-D превращает сертифицированный B0.4-C ROM из validation-only представления в управляемое runtime-представление. D не меняет математический reduction B0.4-B и не ослабляет residual/error contract B0.4-C.

Каноническая цепочка:

```text
canonical PhysicalSource
        ↓
B0.4-A Dynamic Full Model
        ↓
B0.4-B immutable ROM descriptor + reduction binding
        ↓
B0.4-C runtime certification
        ↓
B0.4-D execution artifact
        ↓
CREATED → CERTIFIED → READY → ACTIVE
                              │
                              ├─ source drift ─────────→ STALE
                              └─ runtime safety exit ──→ INVALID
```

`STALE` и `INVALID` являются terminal для конкретной execution session. Возврат в `ACTIVE` возможен только через новый artifact/session после rebuild/reduce или через безопасный handoff.

## Execution artifact

`dynamic_rom_execution_artifact_v1.gd` связывает без мутации:

- exact FULL model hash;
- canonical source-binding checksum;
- boundary contract hash;
- immutable B0.4-B descriptor;
- immutable B0.4-B reduction binding;
- B0.4-C certification hash;
- state reconstruction / error / guard / monitor prerequisites;
- recovery policy.

Важно: `dynamic_rom_artifact_binding_v1.gd` из B0.4-B остаётся `execution_ready=false`. D не переписывает старый контракт и создаёт отдельный certified execution artifact.

## Governed execution

`dynamic_rom_execution_runtime_v1.gd` выполняет каждый accepted step только после:

1. exact artifact/full/ROM/certification binding check;
2. `ACTIVE` lifecycle gate;
3. active runtime monitor gate;
4. candidate ROM step;
5. B0.4-C residual estimator;
6. unified `RomRuntimeCertificate`;
7. ValidatedDomain / ErrorEnvelope / RefinementGuard evaluation.

Candidate state коммитится только после всех gate. Rejected candidate никогда не становится новым accepted ROM state.

Production runtime не требует параллельного FULL shadow solve.

## Invalidation

### STALE

Source-binding revision mismatch немедленно переводит session:

```text
ACTIVE → STALE
recovery = REBUILD_REQUIRED
```

Даже если следующий вызов снова передаст старый source checksum, session не реактивируется.

### INVALID

Residual, constraint, validity, error-envelope, refinement или runtime-monitor exit переводят:

```text
ACTIVE → INVALID
```

После этого low-level ROM execution запрещён до создания новой session.

## Recovery

B0.4-D формирует deterministic recovery action:

```text
source drift                  → REBUILD_REQUIRED
local refinement available   → LOCAL_UNBAKE_REQUIRED (B0.2-D)
otherwise                    → FULL_FALLBACK
```

Recovery payload явно фиксирует:

```text
canonical_state_owner = PHYSICAL_SOURCE
rom_state_role        = DERIVED_HANDOFF_ONLY
```

B0.4-D не забирает ownership у Construction/Matter/PhysicalSource.

## FULL handoff / rebuild

При invalidation используется только последний accepted ROM state. Rejected candidate не участвует в handoff.

ROM → FULL reconstruction создаёт deterministic full-state handoff. Новый artifact generation может проецировать этот FULL state обратно в ROM только если C-norm projection error находится внутри frozen handoff tolerance. Произвольный FULL state вне сертифицированного ROM subspace fail-closed и не может silently resume approximate execution.

## B0.2-D integration

D не дублирует structural local-unbake solver. Он выдаёт совместимый recovery request:

```text
LOCAL_UNBAKE_REQUIRED
region_id = <triggered region>
local_unbake_contract = B0.2-D
```

Фактическая materialization локального FULL-региона остаётся ответственностью B0.2-D / последующего hybrid execution слоя.

## Acceptance scope

Focused D acceptance проверяет:

- immutable execution artifact binding;
- полный lifecycle `CREATED → CERTIFIED → READY → ACTIVE`;
- невозможность перескочить lifecycle gate;
- реальные governed ROM steps с per-step C certificate;
- deterministic twin sessions;
- immediate source STALE;
- sticky STALE / INVALID;
- refinement → B0.2-D local-unbake request;
- residual and constraint invalidation;
- rejected-candidate non-commit;
- FULL handoff from last accepted state;
- fresh build-generation restart;
- ROM→FULL→ROM continuity;
- fail-closed projection outside certified subspace;
- foreign certification/artifact/session tamper rejection.

## Non-claims

B0.4-D не означает:

- production acceptance;
- готовый B0.5 hybrid scheduler;
- автоматическое исполнение B0.2-D structural local-unbake внутри dynamic ROM runtime;
- разрешение любого FULL state проецировать в существующий ROM;
- ownership canonical state внутри ROM.

После независимого закрытия B0.4-D следующий архитектурный checkpoint — `FABRIC SYNC-3`, затем `B0.5-A Executable Hybrid Bake`.
