# FABRIC COMPLEX2-B — Compliant / Spring Response Envelope

**Статус:** ✅ EXACT VERIFIED  
**Ветка:** `feature/fabric-complex2-modular-machine-r1`  
**PR:** #534  
**Physical implementation subject:** `b1f4338b273f0889486553b18bea93d39127bba6`  
**Final verification subject:** `57204de250cd05af76dbff4a42827a983d056ebb`  
**Evidence:** `validation/FABRIC_COMPLEX2_B_COMPLIANT_RESPONSE_EXACT_EVIDENCE.md`

## Задача

COMPLEX2-A уже доказал, что одна 2000-part modular machine может одновременно использовать five-kind BRIDGE-2 mixed execution, contact, detach, representation swap и несколько topology events.

COMPLEX2-B добавляет следующий физический слой: **реальную податливость**, а не декоративное смещение visual node.

Целевой объект — compliant module:

```text
module/complex2-20
```

Он уже существовал в COMPLEX2-A как moving subsystem kind `COMPLIANT` внутри HYBRID region. B не создаёт нового authority owner, а расширяет внутренний backend существующего `HYBRID_BAKE`.

## Ownership boundary

Closed BRIDGE-2 остаётся неизменным:

```text
FULL
STRUCTURAL_BAKE
CONTACT_BAKE
DYNAMIC_ROM
HYBRID_BAKE
```

Всего по-прежнему ровно пять execution regions.

COMPLEX2-B не создаёт шестой `SPRING` region и не превращает 80 compliant parts в 80 competing owners.

Внутри существующего HYBRID owner:

```text
80 canonical compliant part states
80 canonical spring/damper fibers
        ↓ coherent reduction
1 reduced compliance state q
```

То есть complexity растёт внутри representation backend, а ownership topology остаётся закрытым BRIDGE-2 contract.

## Constitutive model

Используется Kelvin-Voigt envelope:

```text
F = K q + C q_dot
```

где:

```text
q      compliant deflection
q_dot  compliant velocity
K      aggregate stiffness
C      aggregate damping
```

Exact compiled parameters:

```text
K = 720 N/m
C = 116 N*s/m
```

Это aggregate result 80 canonical fibers, а не произвольные constants только для visual scene.

## FULL reference против HYBRID reduced backend

FULL reference на каждом step явно суммирует response всех 80 fibers.

Reduced backend использует compiled `K` и `C`.

Acceptance требует:

```text
max |q_FULL - q_HYBRID| <= 1e-12
```

Exact result:

```text
4.996003610813204e-16
```

Поэтому `HYBRID_BAKE` не просто выглядит как FULL, а воспроизводит тот же сертифицированный coherent response внутри заданного envelope.

## Projection / reconstruction

Используются существующие FABRIC-BAKE contracts:

```text
BakeStateMapping
ReconstructionDescriptor
PhysicalBakeArtifact
```

Проверяется round trip:

```text
FULL(80)
  ↓ projection
REDUCED(1)
  ↓ reconstruction
FULL(80)
```

С continuity/reconstruction bounds `<= 1e-12`.

Новый compliant backend identity вкладывается в существующий COMPLEX2-A HYBRID backend identity. Это сохраняет provenance: B расширяет A, а не заменяет его новой несвязанной моделью.

## Load / hold / release experiment

Стенд проходит несколько фаз нагрузки, включая 80 N hold и release.

Exact metrics:

```text
peak |q|  = 0.095426442 m
final |q| = 0.004284087 m
```

После release section возвращается близко к neutral state, а stored energy монотонно уменьшается.

## Energy accounting

Acceptance проверяет:

```text
energy balance residual <= 1e-10
dissipated energy >= -tolerance
total dissipated energy > 0
stored energy monotonically decreases after release
```

Exact max energy residual:

```text
0
```

Это отличает реальный damped compliance от визуальной анимации пружины.

## Fail-closed refinement boundary

One-mode coherent bake нельзя использовать вне области, которую он действительно представляет.

Три обязательных guards:

```text
COMPLEX2B_REFINEMENT_REQUIRED_FORCE
COMPLEX2B_REFINEMENT_REQUIRED_DEFLECTION
COMPLEX2B_COHERENT_MODE_VIOLATION
```

То есть слишком большая сила/деформация или non-coherent FULL state должны потребовать refinement, а не молча продолжить reduced execution.

Это важный мост к будущему `B0.6 Adaptive Physical Fidelity`.

## Parent COMPLEX2 integration

COMPLEX2-B не является отдельной spring-demo сценой. Acceptance строит parent `COMPLEX2-A` machine, заменяет только HYBRID adapter на extended compliant backend и проверяет:

```text
parent machine = 2000 canonical parts
registry kinds = same exact five
HYBRID state owner ID unchanged
HYBRID source slice unchanged
extended PhysicalBakeArtifact valid
extended mixed step == FULL reference
parent COMPLEX2-A mixed/FULL bound preserved
parent representation-swap handoff preserved = 0
```

## Visual lab

Scene:

```text
res://scenes/labs/fabric/complex2b_compliant_response_lab.tscn
```

Основные visual stages:

```text
BASELINE
LOAD_80
RELEASE
REFINEMENT_GUARD
```

Visual layer — read-only observer. Он не решает spring physics и не является источником canonical state.

Scene load/instantiate входит прямо в exact acceptance.

## Exact result

Final verification subject:

```text
HEAD 57204de250cd05af76dbff4a42827a983d056ebb
TREE 475d8d66a89b677da4ec131cc9595844bab244b8
```

Canonical attached Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
SHA256 bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Acceptance:

```text
FABRIC COMPLEX2-B Compliant Response Acceptance: PASS (65 assertions)
```

Integrated hash from two independent exact invocations:

```text
af5779bddc65a504c9ec14612b3dc62341032e4ed770a885c2df679dcbcd6795
```

Project Control: SUCCESS.

## Что это открывает

COMPLEX2-B закрывает compliant/spring envelope, но весь COMPLEX2 остаётся OPEN.

Следующий checkpoint:

```text
COMPLEX2-C — Articulated + Rotating Coupled Motion
```

После него остаются independent structural failure, settle/rebake/re-impact, scale/perf и final COMPLEX2 closure.

`FABRIC0.19` по результатам B всё ещё **NOT AUTHORIZED**: новый generic primitive не потребовался. Существующие ownership, reconstruction, artifact и mixed-execution contracts выразили compliant case без изменения foundation semantics.
