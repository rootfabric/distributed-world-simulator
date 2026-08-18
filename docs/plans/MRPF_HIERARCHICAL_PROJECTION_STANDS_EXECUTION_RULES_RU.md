# MRPF-H — execution rules for hierarchical projection stands

**Статус:** STACKED RESEARCH ROADMAP COMPANION / H1+ EXECUTION RULES  
**Parent roadmap:** `docs/plans/MRPF_HIERARCHICAL_PROJECTION_STANDS_RU.md`  
**Recorded on:** `research/mrpf-h1-space-earth`  
**Exact H0 stack base:** `dc202f6382b8c9b2e9e3e86200b913f7fa03118b`  
**Canonical-main landing:** deferred until the active main-owned control repair no longer requires the current exact main boundary.

Этот документ уточняет исполнение H1..H7. Он не создаёт новый product checkpoint, не меняет ownership и не объявляет H0/H1 accepted.

## 1. Масштаб стендов Earth / Moon

MRPF-H проверяет прежде всего **network / authority / route / projection / replacement semantics**, а не астрономическую точность геометрии.

Поэтому H1..H7 **не обязаны работать в реальном физическом масштабе**.

Разрешён и для быстрых графических стендов предпочтителен условный/casual scale, например:

```text
Earth visual radius:      1..5 scene units
camera approach:          несколько scene units
Moon visual separation:  десятки/сотни scene units либо отдельная normalized scale
route thresholds:         специально подобранные deterministic fixture values
```

Такие значения являются test-fixture параметрами, а не canonical world constants.

Нельзя выводить из casual geometry изменения в production spatial truth, WorldAddress, реальных радиусах планет или canonical simulation scale.

## 2. Что при casual scale обязано оставаться настоящим

Упрощать разрешено геометрию и расстояния. Нельзя упрощать смысл проверяемых contracts.

Во всех H-стендах должны сохраняться:

```text
representation ancestry
source / route isolation
coarse -> fine replacement
fine -> coarse fallback
stable canonical_subject_id
source revision / replay fencing
projection publisher != authority owner
presentation != canonical truth
exactly one canonical writer там, где authority входит в сценарий
independent process failure / reconnect behavior
no duplicate representation in one replacement coverage
```

Если H5 проверяет тезис `DISTANCE ALONE MUST NOT DECIDE VISIBILITY`, реальное расстояние Earth-Moon ~384400 km не является обязательным. Стенд должен доказать **категориальную разницу** между distant celestial representation и ordinary local-dynamic interest, используя контролируемые fixture distances / angular-size / representation-class / screen-error inputs.

Реальные физические масштабы остаются полезны в отдельных spatial/architecture regression tests, но не являются acceptance prerequisite для MRPF-H networking stands.

## 3. Графический принцип

Graphical stand должен быть читаем человеком:

- один логический Earth/Moon object;
- coarse и fine representation визуально различимы;
- replacement не создаёт две планеты одновременно;
- forced source dropout визуально даёт fallback без видимого identity reset;
- HUD/diagnostics показывают source, revision, LOD/domain level и route state;
- камера/сцена могут использовать casual cinematic scale.

Graphical fidelity не должна становиться отдельным scope H1.

## 4. Framework-readiness — обязательное направление, не отдельный проект

Для H1+ применяется существующая перспективная policy:

```text
feature/sm0-two-authority-seamless-handoff-lab
@ 9acf8efb47895dff785265bcee55d51b1b33da0a

docs/control/NETWORK_FRAMEWORK_READY_DEVELOPMENT_POLICY_RU.md
```

Policy рассматривается как архитектурный donor для H-line до её будущего main-owned интегрирования.

Главный принцип:

```text
Simulator Domain
      |
      v
Simulator / Research Adapters
      |
      v
Reusable-shaped Network Runtime / Contracts
```

Разрешённое dependency direction:

```text
simulator -> network
```

Не добавлять без необходимости:

```text
network -> Earth/Moon/gameplay domain
```

## 5. Что это означает для H1..H7

Перед добавлением существенного network/distributed component его следует классифицировать:

```text
A. GENERIC NETWORK CORE
B. SIMULATOR ADAPTER
C. RESEARCH / EXPERIMENT HARNESS
D. TEST / VALIDATION INFRASTRUCTURE
```

По умолчанию H-стенды остаются **C/D research/evidence environments**.

Не переносить код в `scripts/network/` только потому, что он выглядит потенциально reusable. Новый generic core в `scripts/network/` допустим только когда это требуется текущей capability/correctness и не создаёт преждевременный framework refactor.

Для H1 выбран подход:

```text
H0 contract/composer                    existing research donor
MRPF-H1 datagram/route helper           generic-shaped research harness
SPACE/EARTH representation factory      scenario adapter / fixture
SPACE publisher process                 research process
EARTH publisher process                 research process
CLIENT graphical composer               research integration / presentation
process orchestrator                    validation infrastructure
```

## 6. Boundary для generic-shaped кода

Если алгоритму не нужно знать, что source — `EARTH`, `MOON`, `BASE` или что проект — Distributed World Simulator, он не должен кодировать эти знания внутри transport/routing primitive.

Предпочтительные поля:

```text
source_route_id
publisher_id
sequence
state_revision
payload
payload_hash
```

Earth/Moon-specific значения находятся в fixture/adapter слое.

Generic-shaped route/transport code не должен интерпретировать:

```text
Item Graph
inventory
Construction
Matter
Ecology
resource mining
recipes
Earth gameplay rules
Moon gameplay rules
UI semantics
```

## 7. Transport independence

H1 может использовать real loopback UDP как самый дешёвый process-isolation proof.

Но higher-level representation semantics не должны быть слиты с UDP API.

Research boundary должна сохранять возможность:

```text
projection / representation semantics
        |
research route envelope
        |
UDP loopback now
future ENet / other transport later
```

Это не требование немедленно создавать production transport interface.

## 8. No premature framework extraction

До отдельного formal Work Order запрещено ради H-line:

- создавать новый framework repository/package;
- массово переносить NX/SM/MRPF runtime;
- выполнять engine-neutral rewrite;
- менять принятые authority/replication contracts только ради generic API;
- создавать второй network truth / authority model;
- задерживать H1/H2/H3 capability ради архитектурной косметики.

Framework-readiness — constraint выбора дизайна, а не отдельный deliverable.

## 9. Tests

Каждый зрелый H mechanism желательно проверять двумя слоями:

```text
generic-shaped contract/process test
+
scenario graphical/integration test
```

Network/process test должен уметь формулировать predicates через route/source/revision/representation, а Earth/Moon visual assertions должны оставаться в scenario layer.

## 10. H1 explicit execution contract

H1 реализуется в casual scale, но с реальными отдельными Godot processes:

```text
SPACE publisher process
EARTH publisher process
CLIENT graphical/composer process
```

Client держит два независимых projection-source routes одновременно.

Обязательный сценарий:

```text
SPACE only -> Earth coarse
EARTH route appears -> Earth fine replaces coarse
EARTH process disappears -> coarse fallback
EARTH process restarts with newer source_revision -> fine returns
```

Обязательные invariants:

```text
one Earth canonical_subject_id
one visible Earth presentation node
no coarse+fine duplicate Earth
no stale revision resurrection
no canonical mutation
SPACE route survives EARTH dropout
EARTH transport failure is isolated
reconnect uses newer source_revision
```

## 11. H5 Moon clarification

H5 не обязан создавать 384400 km scene separation.

Он обязан доказать:

```text
celestial coarse representation may remain eligible at a very different scale
ordinary LOCAL_DYNAMIC interest may be absent
MOON direct route is optional while SPACE coarse artifact is valid
approach opens finer MOON projection without duplicate Moon identity
distance is only one visibility input
```

Для graphical evidence допускается normalised/casual orbital layout.

## 12. Reporting

Для H1+ итоговый implementer report должен отдельно указывать:

```text
Framework impact:
- generic core changed: YES/NO
- simulator adapter changed: YES/NO
- research-only code changed: YES/NO
- new simulator -> network dependency: ...
- new network -> simulator dependency: ...
```

Если появляется новый `network -> simulator gameplay` dependency, это обязательный architectural concern для post-build critique/review.
