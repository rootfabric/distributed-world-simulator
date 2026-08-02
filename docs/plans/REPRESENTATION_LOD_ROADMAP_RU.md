# Representation LOD Roadmap — интеграция в Mutable Worlds и Construction

**Принятая база:** RL1 Matter summary pyramid and dirty propagation.
**Текущий этап:** MW9 Durable Distributed Handoff and Crash Recovery.
**Архитектура:** `docs/architecture/REPRESENTATION_LOD_FABRIC_RU.md`.

## 1. Оптимальный порядок после MW8

```text
MW8  regional authority handoff — ACCEPTED
 ↓
RL0  unified representation contracts — ACCEPTED
 ↓
RL1  Matter summary pyramid and dirty propagation — ACCEPTED
 ↓
MW9  durable distributed handoff and crash recovery — CURRENT CANDIDATE
 ↓
MW10 cross-region matter transactions
 ↓
RL2  Matter multiresolution meshing and cross-level transitions
 ↓
RL3  representation-aware interest and network artifact streaming
 ↓
RL4  Construction C18 HLOD backend
 ↓
RL5  shared cache, background builders and handoff cache warming
 ↓
RL6  visual/network/scale acceptance
 ↓
MW11 deposition and matter-backed construction
 ↓
MW12 fracture and detached bodies
 ↓
MW13 industrial regional persistence
 ↓
MW14 production service transport
 ↓
MI0–MI4 Moon/planet integration
 ↓
MP0–MP4 tools, production, construction and agents
```

## 2. Почему RL0 и RL1 идут сейчас

До MW9 необходимо зафиксировать identity и dependency semantics artifacts. Иначе durable authority directory и regional persistence придётся проектировать без понимания:

- какие summaries принадлежат region;
- что можно потерять при crash;
- что переносится как cache;
- как source revision инвалидирует proxy;
- как target после handoff понимает, что artifact stale.

RL1 создаёт только summary pyramid и dirty propagation. Он не усложняет mesh и network.

## 3. Почему RL2 и RL3 идут после MW10

Multiresolution meshing и network delivery должны опираться на устойчивые правила:

- single-owner lease после crash;
- cross-region mutation ordering;
- source revision frontier нескольких regions;
- deterministic invalidation при distributed commit.

Иначе proxy, пересекающий серверную границу, может быть собран из несовместимых revisions.

## 4. Почему Construction HLOD не объединяется с Matter mesher

RL4 использует C18 activity/LOD policy, но добавляет реальный backend:

- part clustering;
- internal-face removal;
- mesh merge;
- decimation;
- collision proxy;
- impostor.

Matter RL2 использует SDF/downsample/isosurface/transition cells. Общими остаются contracts, cache, scheduler, screen error и invalidation.

## 5. Этапы

### RL0 — Unified Representation Contracts

Результат:

- versioned cross-domain DTO;
- content-addressed manifest;
- exact source binding;
- geometric/screen error budgets;
- capability fences;
- deterministic coarsest-acceptable selection;
- dependency hash;
- cache lifecycle;
- invalidation contract.

Без SceneTree, Mesh, Image, RID и production world changes.

### RL1 — Matter Summary Pyramid

Реализованный candidate:

- region-scoped parent-child cells поверх MW8 authority-region;
- min/max SDF и occupancy range;
- matter/vacuum/surface presence;
- deterministic material occupancy summary;
- immediate dependency hash и transitive descendant revision hash;
- mutation dirty ancestor propagation только до region root;
- handoff invalidation loaded subtree с восстановлением missing ancestors;
- bounded atomic fine-to-coarse rebuild queue;
- content-addressed persistence manifests с полным cell binding;
- focused handoff, rollback, same-revision и capacity tests.

RL1 не строит coarse SDF samples или meshes. Этап принят; durable lifecycle реализуется в MW9.

### MW9 — Durable Distributed Handoff

Реализованный candidate:

- atomic active/previous authority checkpoint;
- logical-tick lease timeout, renewal и expired claim;
- exact full-object fencing token;
- append-only transfer journal;
- canonical package bytes и internal checksum binding;
- irreversible durable commit decision;
- deterministic restart rule: commit decided, otherwise abort;
- optional RL1 summary manifest как rebuildable cache hint;
- fail-closed MW8 runtime adapter и terminal reconciliation;
- split-brain и multi-process crash tests.

Representation cache остаётся необязательным и восстанавливаемым. После acceptance следующий этап — MW10.

### MW10 — Cross-region Transactions

- deterministic region ordering;
- prepare/commit/rollback;
- distributed mass ledger;
- exact replay;
- invalidation emitted only after global commit.

### RL2 — Matter Multiresolution Meshing

- coarse SDF levels;
- regional/macro meshes;
- large-mutation visibility;
- transition meshes;
- collision promotion;
- local ancestor rebuild.

### RL3 — Network Artifact Streaming

- representation-aware MW7 subscription;
- artifact manifests;
- content-addressed transfer;
- progressive coarse-first loading;
- cancellation;
- per-client memory/bandwidth budgets;
- reconnect and cache reuse.

### RL4 — Construction HLOD Backend

- real C18 `SIMPLIFIED` and `IMPOSTOR` artifacts;
- cluster/section/construct hierarchy;
- semantic anchors outside merged mesh;
- incremental rebuild;
- station 10k-part fixture.

### RL5 — Shared Cache and Scheduler

- worker-thread data build;
- main-thread Godot resource commit;
- build priorities;
- cancellation and deduplication;
- memory/disk eviction;
- stale-while-rebuild;
- MW8 target cache warming.

### RL6 — Acceptance

- asteroid approach from orbit to tunnel interior;
- no detail flood at distance;
- no cracks between LODs;
- bounded network bytes;
- station 10k parts;
- one-part edit has bounded rebuild fan-out;
- rapid observer movement and zoom;
- server handoff during progressive loading;
- cache loss and rebuild equivalence.

## 6. Integration gates

### Before Moon MI0

Required:

```text
RL0 PASS
RL1 PASS
MW9 PASS
MW10 PASS
RL2 PASS
RL3 PASS
```

### Before large production stations

Required:

```text
C18 policy accepted
RL0 PASS
RL4 PASS
RL5 PASS
RL6 scale fixture PASS
```

## 7. Неизменяемые правила

- mesh не является world state;
- artifact cache не участвует в mass ledger;
- source revision/hash задаёт provenance;
- stale artifact не используется для close collision;
- coarse proxy может временно отображаться до rebuild;
- server handoff не блокируется отсутствием artifact;
- Matter и Construction не разделяют geometry algorithm;
- production Moon не меняется до MI gate.
