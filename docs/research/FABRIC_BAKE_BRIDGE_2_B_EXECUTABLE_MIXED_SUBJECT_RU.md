# FABRIC-BAKE BRIDGE-2-B — Executable Mixed Subject

**Статус:** IMPLEMENTED CANDIDATE / LOCAL EXACT DOUBLE PASS / NOT YET BRIDGE-2 CLOSED.  
**Предшественник:** BRIDGE-2-A Mixed Representation Ownership Contract.  
**Production:** не авторизован.

## 1. Цель

BRIDGE-2-A доказал ownership grammar, но его representations были только ownership
records. BRIDGE-2-B заменяет каждый ACTIVE_EXECUTION slot реальным executable witness,
не вводя общий scheduler и не забирая работу у BRIDGE-2-C.

Ключевой вопрос:

```text
можно ли собрать один canonical subject
+
реальные FULL / STRUCTURAL_BAKE / CONTACT_BAKE / DYNAMIC_ROM / HYBRID_BAKE executables
+
один CanonicalSourceFrontier
+
один AuthorityEnvelope
без второго state/authority universe?
```

## 2. Canonical subject

Основа — существующий COMPLEX0 fixture на 500 canonical parts.

Все пять executable witnesses обязаны ссылаться на один и тот же:

```text
frontier:
1d9d5b8e1f6ff0ad53a5ee5fd4d5107adb08d63edd4586624d77838cbad3ea73

authority_epoch_binding:
fa900764fe8f6b38b08951136ec68d2bb259152847cd8722ff8ff6e128dea643

execution owner:
server/complex0
```

Mixed subject хранит compact execution identities и hashes. Он не копирует canonical
Construction/Matter state и не становится persistent state owner.

## 3. Реальные executable witnesses

### FULL

Используется B0.4-A FULL reference model, но его source binding перекомпилируется на
канонический COMPLEX0 frontier/authority.

Он реально исполняет один шаг:

```text
step_index 0 → 1
time 0.00 → 0.01 s
```

FULL намеренно не притворяется PhysicalBakeArtifact:

```text
physical_artifact_checksum = ""
```

### STRUCTURAL_BAKE

Реальный BRIDGE-1 lifecycle:

```text
COMPLEX0 canonical source
→ PhysicalSourceView
→ structural aggregate
→ PhysicalBakeArtifact
→ Lifecycle.execute
```

Artifact checksum:

```text
36eea27c321efb623eb7364597cffe29cf92d43397f6af8116d4510ee5696173
```

### CONTACT_BAKE

Реальный B0.3 contact/wrench artifact компилируется поверх того же BRIDGE-1 parent и
проходит BakeExecutionGate + executable support query.

Artifact checksum:

```text
05d0547081182fb5bfd9e250094e5c21efdb005a1f80652b0c58aa18f026405f
```

Его parent artifact checksum обязан совпадать со STRUCTURAL_BAKE artifact.

### DYNAMIC_ROM

Реальный B0.4 chain:

```text
FULL model
→ ROMCompiler
→ RuntimeCertification
→ DynamicROM PhysicalBakeArtifact
→ ExecutionArtifact
→ ACTIVE execution session
```

Physical artifact:

```text
8bf556b7b02bd9faf1b1dbc629fae65abbf35456577301b428aecc7231814e05
```

Execution artifact identity:

```text
c063cec2d0d3f717736c3cdff781010162a5d0044421f9bfbb7ca7573e7db65b
```

### HYBRID_BAKE

Реальный B0.5-A executable mode/package создаётся поверх того же B0.4 physical bundle.

Package identity:

```text
d63a90b1fad436c7b421412fcb43db01b4d82af75c882575a9d7f7e881e6fa52
```

Важный invariant:

```text
HYBRID_BAKE underlying PhysicalBakeArtifact
==
DYNAMIC_ROM PhysicalBakeArtifact
```

То есть hybrid wrapper не создаёт вторую physical truth.

## 4. Mixed subject manifest

Добавлен:

```text
mixed_representation_executable_subject_v1.gd
```

Manifest entry содержит только:

- representation id/kind;
- region id;
- ACTIVE_EXECUTION role;
- exact frontier/authority binding;
- witness kind;
- PhysicalBakeArtifact checksum, если representation reduced;
- executable identity hash;
- runtime state/session hash;
- underlying artifact checksum;
- deterministic witness hash.

Subject identity:

```text
3687aced4eaaed0a42eaee2470348792242c138a5c6ba4880c4157d488751dd9
```

## 5. Fail-closed cases

Acceptance обязательно отклоняет:

- реальный executable FULL model с чужого canonical frontier;
- witness, помещённый в region, где он не ACTIVE owner по BRIDGE-2-A;
- duplicate representation witness;
- tampered entry frontier;
- missing representation witness;
- FULL, который пытается выдать себя за bake artifact;
- reduced representation без real PhysicalBakeArtifact checksum;
- manifest/source/authority/ownership hash mismatch.

## 6. Determinism

Reverse witness presentation:

```text
same subject_hash
same sorted executable entries
```

Порядок caller input не меняет mixed identity.

## 7. Exact local evidence

Engine:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Results:

```text
BRIDGE-2-B Executable Mixed Subject:
57/57 PASS

Playground:
PASS

BRIDGE-2-A regression:
71/71 PASS
```

Local log SHA-256:

```text
acceptance:
342bcdf79c9b54262876edcd40e8073264aa3111cb3f1497d9083a233cc699f2

playground:
881d17597f94ca0b1f5a2d83b5387f6cd32a2f360a8e8e1e60fb41033e706181

B2-A regression:
7f6a44af2e1b0d88cf4cca6bdb969968a1350b65ffe73cadfe37c88a76442131
```

Final GitHub exact subject/replay is recorded in validation after source-carrier replay.

## 8. Не доказывает

BRIDGE-2-B пока **не** заявляет:

- общий simultaneous event scheduler;
- cross-representation event delivery;
- event handoff between active artifacts;
- invalidation/refinement ordering after mutation;
- shared time advancement across all representations;
- deterministic mixed physical replay after event;
- COMPLEX1B;
- BRIDGE-2 CLOSED;
- production acceptance.

Это намеренно остаётся BRIDGE-2-C/D/E.

## 9. Следующий checkpoint

```text
BRIDGE-2-A ✅ ownership
        ↓
BRIDGE-2-B ✅ executable mixed subject candidate
        ↓
★ BRIDGE-2-C — Cross-Representation Event Routing ★
        ↓
BRIDGE-2-D — Invalidation / Refinement Ordering
        ↓
BRIDGE-2-E — Deterministic Mixed Replay
        ↓
BRIDGE-2-F / COMPLEX1B
```
