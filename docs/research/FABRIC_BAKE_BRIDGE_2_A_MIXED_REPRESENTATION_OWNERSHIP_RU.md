# FABRIC-BAKE BRIDGE-2-A — Mixed Representation Ownership Contract

**Статус:** IMPLEMENTED CANDIDATE / EXACT DOUBLE PASS / NOT YET BRIDGE-2 CLOSED.  
**Предшественник:** FABRIC.SYNC4 ✅ CLOSED.  
**Назначение:** заморозить ownership boundary до первого реального mixed executable subject.  
**Production:** не авторизован.

## 1. Зачем нужен BRIDGE-2-A

После B0.4/B0.5-A и COMPLEX0 уже существуют несколько корректных derived физических
представлений, но сам факт их существования ещё не доказывает, что их можно безопасно
смешать внутри одной canonical системы.

Главный риск:

```text
same canonical region
        ↓
FULL thinks it owns event
+
STRUCTURAL_BAKE thinks it owns event
+
HYBRID/ROM independently commits transition
        ↓
duplicate physical event / duplicate canonical mutation
```

BRIDGE-2-A вводит только ownership contract. Он **не** реализует BRIDGE-2-B mixed
execution, BRIDGE-2-C routing или BRIDGE-2-D invalidation ordering.

## 2. Неподвижная truth boundary

```text
Construction / Matter
= canonical semantic truth

FULL
STRUCTURAL_BAKE
CONTACT_BAKE
DYNAMIC_ROM
HYBRID_BAKE
= derived executable representations
```

Каждая mixed representation запись обязана иметь:

```text
derived_only = true
canonical_write_authorized = false
source_frontier_hash = exact canonical frontier
authority_epoch_binding = exact existing AuthorityEnvelope binding
```

Никакого нового revision clock, authority epoch или canonical registry BRIDGE-2-A не
создаёт.

## 3. Region ownership

Контракт допускает несколько представлений, наблюдающих один canonical region, но ровно
одно из них может иметь роль:

```text
ACTIVE_EXECUTION
```

Остальные:

```text
OBSERVER
```

Например:

```text
region/impact
├── FULL             ACTIVE_EXECUTION
├── STRUCTURAL_BAKE  OBSERVER
└── CONTACT_BAKE     OBSERVER
```

Две ACTIVE_EXECUTION записи на один region дают fail-closed:

```text
BRIDGE2_A_MULTIPLE_ACTIVE_REGION_OWNERS
```

Region без active owner также запрещён:

```text
BRIDGE2_A_REGION_ACTIVE_OWNER_REQUIRED
```

## 4. Event ownership

BRIDGE-2-A различает две вещи:

```text
evaluator
!=
canonical commit owner
```

Derived representation может определить физический факт, но не получает от этого право
самостоятельно изменить Construction/Matter.

### Canonical mutation

```text
impact
→ FULL active evaluator
→ canonical break fact
→ commit_owner = existing AuthorityEnvelope.execution_owner
→ source revision remains EXTERNAL_CANONICAL_AUTHORITY_ONLY
```

Для fixture это:

```text
evaluator:
representation/full-impact

commit owner:
server/complex0
```

FULL при этом остаётся:

```text
canonical_write_authorized = false
```

То есть physical evaluator передаёт факт существующему canonical mutation owner; он не
становится вторым Construction authority.

### Derived physical event

Hybrid transition, который не меняет canonical Construction/Matter:

```text
HYBRID_BAKE active evaluator
→ FABRIC physical JUMP
→ commit_owner = FABRIC_PHYSICAL_EVENT
→ NO_CANONICAL_REVISION
```

Это сохраняет B0.5-A event ownership semantics.

## 5. Exactly-once boundary

Event request принимает уже committed event IDs как внешний ledger view.

Если тот же event уже зафиксирован:

```text
BRIDGE2_A_EVENT_ALREADY_COMMITTED
```

BRIDGE-2-A пока не создаёт новый persistent ledger. Это намеренно: B2-C должен связать
ownership resolution с реальным cross-representation event routing, не создавая второй
canonical event store.

## 6. Первый executable fixture

Fixture использует реальный 500-part COMPLEX0 canonical Construction/Matter frontier и
его существующий `AuthorityEnvelope`.

Mixed ownership map:

```text
region/impact
→ FULL active
→ STRUCTURAL_BAKE observer
→ CONTACT_BAKE observer

region/stable-structure
→ STRUCTURAL_BAKE active
→ FULL observer

region/contact
→ CONTACT_BAKE active
→ FULL observer

region/dynamic
→ DYNAMIC_ROM active
→ FULL observer

region/hybrid
→ HYBRID_BAKE active
→ DYNAMIC_ROM observer
```

Это ещё не означает, что все пять representation artifacts одновременно исполняют
реальную физику. Оно означает, что BRIDGE-2 теперь имеет executable ownership grammar,
на которую B2-B может посадить реальные artifacts.

## 7. Обязательные falsifiers

Acceptance покрывает:

- все пять representation kinds derived-only;
- попытку derived canonical write;
- два active owner на одном region;
- отсутствие active owner;
- чужой canonical frontier;
- чужой authority binding;
- неизвестный representation kind;
- event candidate вне region;
- event candidate set без active evaluator;
- повторный physical event;
- cross-authority mutable execution;
- deterministic reverse-input contract identity;
- deterministic event resolution identity.

Cross-authority rejection переиспользует существующий код:

```text
AUTHORITY_ENVELOPE_CROSSED
```

Нового authority universe не добавлено.

## 8. Exact evidence

Canonical engine:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Focused result:

```text
BRIDGE-2-A Mixed Representation Ownership Acceptance
71/71 PASS

contract hash:
5b58cdb94b959be41d7b8450f423e540ca393ac8a7469ea1e81002c6a214ec42

Playground:
PASS
```

Predecessor focused regression run in the same worktree:

```text
BRIDGE-1 Physical Source Lifecycle
146/146 PASS
```

The standalone B0.5-A acceptance was not reclassified based on a long local wall-clock
run; B0.5-A remains the byte-unchanged closed predecessor recorded by SYNC4.

## 9. Что BRIDGE-2-A НЕ доказывает

Не заявлять:

- mixed representation runtime execution;
- cross-representation state handoff;
- event delivery between real artifacts;
- invalidation/refinement ordering;
- mixed deterministic replay of physical state;
- COMPLEX1B;
- BRIDGE-2 CLOSED;
- production acceptance.

## 10. Следующий checkpoint

```text
BRIDGE-2-A
Mixed Representation Ownership Contract
        ✅ IMPLEMENTED CANDIDATE
        ↓
BRIDGE-2-B
Executable Mixed Subject
        ↓
BRIDGE-2-C
Cross-Representation Event Routing
        ↓
BRIDGE-2-D
Invalidation / Refinement Ordering
        ↓
BRIDGE-2-E
Deterministic Mixed Replay
        ↓
BRIDGE-2-F / COMPLEX1B
Powered Fence Mixed End-to-End
```
