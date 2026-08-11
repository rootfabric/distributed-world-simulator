# Project Convergence — 2026-08-11

**Проект:** Distributed World Simulator  
**Architecture baseline:** `GLOBAL-P0-2026-08-10-R2`  
**Control plane:** `PC0-2026-08-10-R1` + directional-watch hardening  
**Canonical operational owner:** `main`  
**Назначение:** остановить повторное расхождение веток, синхронизировать реальные acceptance-факты с PC0 и задать один порядок продолжения разработки.

---

## 1. Главный вывод синхронизации

Проект не имеет одного общего runtime-blocker. Есть несколько разных типов незавершённости, которые раньше смешивались в один цвет:

```text
MANUAL ACCEPTANCE
  G8.6
  CH9.6

MAIN CONVERGENCE
  C22 / TS0.3

ACCEPTED HANDOFF EVIDENCE
  T1B.0 ... T1B.4

CLEAN PREPARATION FRONTIER
  NX.C0

ARCHITECTURE CANDIDATE REFRESH
  GLOBAL-P0 R3
```

Ключевое правило после этой синхронизации:

```text
accepted old lineage
        !=
new production frontier base
```

Старая длинная ветка может оставаться доказательством принятого поведения, но новая major runtime-работа по умолчанию начинается от **текущего canonical main**.

Исключение допускается только когда stacked dependency специально зарегистрирован в PC0 и является частью одного ещё не завершённого source-acceptance train.

---

## 2. Фактическое состояние программ

### G — World Generation

```text
stage:       G8.6 Geomorphology Visual Lab
status:      AUTOMATED_ACCEPTED_MANUAL_GRAPHICAL_PENDING
runtime:     a9ca1f8b723e4edc5ebff40db26e41283d464597
blocker:     G8_6_MANUAL_GRAPHICAL_ACCEPTANCE_REQUIRED
next:        manual graphical -> G8.6 ACCEPTED -> G8 Full Acceptance
```

Автоматический gate закрыт. Нового runtime-кода до graphical gate не добавлять.

После G8 Full Acceptance ветку G8 заморозить как evidence. **G9 не открывать до canonical R3/MAT0 gate**, потому что geology должна использовать общий `MaterialDefinitionId`, а не создавать свою материал-онтологию.

### T — Construction Composition

```text
T1B.0  ACCEPTED
T1B.1  ACCEPTED
T1B.2  ACCEPTED
T1B.3  ACCEPTED
T1B.4  ACCEPTED

stage:   T1B Aggregate Handoff Complete
status:  SOURCE_ACCEPTED_HANDOFF_COMPLETE
next:    no T1B.5
```

T1B больше не является местом новой разработки. Она остаётся consumer evidence для dependency revalidation, но не должна генерировать новые production changes.

Следующий Construction runtime frontier — только `T2.0`, после C22 + TS0.4 + PC0 convergence.

### TS / C22 — Construction Scale / Proxy Convergence

```text
source implementation:  ACCEPTED
PR #59:                 open, non-mergeable
main drift from C22 base: control / architecture / docs only
status now:             SOURCE_ACCEPTED_MAIN_CONVERGENCE_REFRESH_REQUIRED
```

Source acceptance не отменяется. Но старую ветку больше нельзя считать `MERGE_READY`, пока она не приведена к текущему main.

Правильный следующий шаг — свежий current-main convergence refresh с тем же C22 production diff.

### CH — Character Presentation

```text
stage:       CH9.6 Playable Network Equipment Lab
status:      WINDOWS_AUTOMATED_ACCEPTED_GRAPHICAL_PENDING
runtime:     7b2269b39952b8201714a7078a62b8f97057325c
tested:      4cdafddce7cd6b5fa7ff45a06ae00f06320464ab
blocker:     CH9_6_GRAPHICAL_USER_OBSERVATION_PENDING
```

Windows automated gate уже закрыт. До graphical acceptance никакой CH9.7/CH10 не открывать.

### NX — Network / Realtime

```text
frontier:  feature/nx-m7-owner-authority-convergence
stage:     NX.C0 Owner Authority Convergence Preparation
runtime:   none
health:    GREEN preparation
```

Legacy M7/FIX lineage остаётся research/validation evidence и не является production merge source.

NX.C1 начинается только после интеграции directional-watch hardening в main и от свежей current-main базы.

### GLOBAL-P0 R3

R3 architecture candidate остаётся полезным и концептуально согласованным, но его operational guards были устаревшими.

До promotion требуется:

```text
current-main refresh
+ current PC0 frontier guards
+ architecture revision transition policy
+ PC0 non-RED
```

Wave A (`IAM`, `MAT`, `WT`, `WQ`) создаётся только после этого от **одного canonical R3 base**.

---

## 3. Исправления control plane

### 3.1 Directional watched-dependency audit

Старый PC0 умел видеть:

```text
main changed watched dependency -> branch warning
branch A and branch B changed same file -> overlap warning
```

Но не видел:

```text
branch A changed X
branch B did not change X
branch B watches X
```

Добавлен второй механический gate:

```text
producer.scope_changed_files
          ∩
consumer.watched_paths
          ↓
        YELLOW

producer.scope_changed_files
          ∩
consumer.critical_watched_paths
          ↓
         RED
```

Это особенно важно для будущего NX.C1:

```text
NX changes network protocol/runtime dependency
          ↓
T / CH / other consumer watches it
          ↓
targeted revalidation becomes explicit
```

### 3.2 Accepted handoff is consumer-only

`SOURCE_ACCEPTED_HANDOFF_COMPLETE` подавляется как active producer в directional audit.

То есть T1B:

```text
не создаёт новые warnings просто потому, что исторически имеет большой diff

но

остаётся consumer и может потребовать revalidation,
если новый active producer меняет её watched dependency
```

### 3.3 Registry/passport mirror

Byte-equivalence длинных human-readable `progress_note`, `purpose`, `next_stage` больше не считается correctness gate.

Механически зеркалируются только:

```text
branch
program
role
current_stage
stage_status
blockers
health_declared
```

Human prose остаётся в dashboard, но небольшое редакционное расхождение больше не создаёт ложный YELLOW.

### 3.4 Validation tested-head schema

G8 passport теперь, помимо детальных G-specific acceptance heads, объявляет стандартные:

```text
tested_heads.runtime
tested_heads.focused
tested_heads.full_regression
```

Поэтому PC0 может реально проверять freshness принятого G8 runtime.

### 3.5 T1B World Query ownership

T1B не является owner World Query Fabric.

R2 canonical ownership:

```text
WORLD_QUERY_FABRIC -> P1_FUTURE
```

T1B только потребляет внешний interest/query projection. Passport приведён к этой декларации, чтобы accepted handoff не получал ложный ownership RED.

---

## 4. Canonical continuation rule

После текущей синхронизации действует следующий branch rule.

### Нельзя

```text
accepted old branch
      ↓
ещё 5-10 FIX/stage layers
      ↓
новый production architecture
```

### Нужно

```text
accepted evidence
      +
current canonical main
      ↓
fresh convergence frontier
      ↓
minimal capability transfer
      ↓
focused validation
      ↓
full regression
      ↓
composition validation
      ↓
merge / handoff
```

Это правило уже применено к NX и теперь должно применяться к C22 refresh, TS0.4, T2.0 и будущим post-G8/post-CH9.6 major frontiers.

---

## 5. Construction convergence train

### Step C0 — C22 current-main refresh

Создать свежую ветку от тогдашнего `main`.

Перенести **только принятый C22 production diff**:

```text
scripts/construction/proxies/
  construction_proxy_streaming_controller.gd
  construction_proxy_incremental_local_rebuilder.gd
  construction_proxy_artifact_merger.gd
  construction_proxy_array_mesh_backend.gd

related tests / runner / validation
```

Нельзя переносить старые control/roadmap копии как источник project state.

### Step C1 — Equivalence gate

Нужно доказать:

```text
old accepted C22 production files
        == semantic diff ==
fresh convergence C22 production files
```

Допускаются только изменения, необходимые из-за реального current-main runtime conflict. Если такие появятся, source acceptance считается evidence, но новый runtime обязан пройти полный retest.

### Step C2 — Focused Windows gate

Повторить:

```text
C22 incremental local rebuild
C22 graphical
C24 proxy mesh backend contracts
```

### Step C3 — Full world/core regression

Обязателен полный regression на точном refreshed head.

### Step C4 — MERGE_READY

Только после C1-C3:

```text
SOURCE_ACCEPTED_MAIN_CONVERGENCE_REFRESH_REQUIRED
        ↓
SOURCE_ACCEPTED_MERGE_READY
```

Сам merge требует отдельной явной команды.

### Step C5 — post-merge

После merge:

```text
PC0
MAIN_INTEGRATED = true
retire C22 convergence frontier
```

### Step C6 — TS0.4

Создать **fresh main-based**:

```text
TS0.4 — 1M Research Ceiling
```

Измерять:

```text
build / ingest time
incremental rebuild time
memory
artifact count/cache reuse
far-shell cost
streaming/representation cost
hot sections
main-thread budget
```

Классификация:

```text
PASSABLE
DEGRADED
CURRENT_CEILING_EXCEEDED
```

Не пытаться любой ценой «сделать миллион зелёным». Задача TS0.4 — получить честный ceiling и bottleneck telemetry.

### Step C7 — T2.0 activation

T2.0 разрешается только после:

```text
C22 MAIN_INTEGRATED
+
T1A.7/T1B accepted scale/composition evidence
+
TS0.4 classification
+
PC0 convergence
```

T2.0 создаётся от актуального main и использует T1B как semantic evidence, а не как бесконечно продолжаемый stacked branch.

---

## 6. Network convergence train

### N0 — PC0 hardening canonical

Сначала directional-watch gate должен находиться в `main`.

### N1 — fresh NX.C1 base

Не продолжать нынешний NX.C0 runtime поверх старой базы после существенного движения main.

Разрешено:

```text
NX.C0 = preparation evidence
fresh current-main NX.C1 = runtime implementation
```

### N2 — minimal runtime transfer

Только:

```text
MovementAuthorityProfile
owner movement service
client/server locomotion composition
remote snapshot interpolation presentation
same-revision item optimistic rollback
```

Не переносить:

```text
legacy FIX ladder
render _process -> CharacterBody3D writes
unbounded relative client_tick scheduler
```

### N3 — mandatory gates

```text
editor import
owner authority focused
render/physics single-writer
item rollback/drop/pickup
client_tick fuzz if scheduler metadata touched
full world/core regression
two-client process
LOCAL movement + items
impaired network
reconnect / ownership_epoch
directional dependency revalidation for affected consumers
```

---

## 7. G continuation

Текущий G action не кодовый.

Сначала manual gate:

```text
G source/resolved -> visible change, Truth hash stable
1..7 -> all semantic views meaningful
W/S -> LOD/stride/grid changes, samples=561 + hash stable
X -> PX/PZ seam, no crack
F -> canonical river follows channel/bank/floodplain
```

После PASS:

```text
G8.6 ACCEPTED
G8 Full Acceptance
PC0
freeze G8 evidence
```

Следом **не G9 напрямую**.

Правильная зависимость:

```text
R3 canonical
   ↓
MAT0 identity/registry
   ↓
G9 Layered Geology
```

G9 может иметь разные geology/provider recipes для разных планет, но material identity должна быть общей для G/Matter/Item/Construction.

---

## 8. CH continuation

Текущий CH action тоже не кодовый.

На preserved `4cdafddc`:

```text
run 1 with ResetState
READY
UI equip upper/lower/feet
visual presenter update
unequip removes mesh
movement/jump/crouch
normal close

run 2 without ResetState
automatic equipment recovery before new drag
post-recovery unequip removes mesh
```

После PASS:

```text
CH9.6 ACCEPTED
post-acceptance PC0
freeze playable equipment vertical slice
```

Следующий major CH frontier создаётся от current main/convergence base, а не продолжением длинной CH lineage без global integration review.

---

## 9. R3 architecture train

R3 foundations остаются стратегически правильным следующим global architecture revision:

```text
IAM / AUTHZ
RF / TF / SD
MAT
WT
WQ
LIFE
WB
COMPAT / SEC
```

Но promotion делается только после refresh.

### R3.0 — refresh

Свежий R3 change-set должен быть построен поверх current main после PC0 hardening.

### R3.1 — frontier guards

На момент promotion machine-readable guards должны отражать фактическое состояние, а не старые stages.

### R3.2 — revision transition

Нельзя делать:

```text
main architecture = R3
        ↓
все accepted R2 evidence branches внезапно RED
```

Нужно различить:

```text
ACTIVE_NEW_RUNTIME_FRONTIER
  must match canonical R3

FROZEN_ACCEPTED_EVIDENCE
  may remain R2 and is not a new implementation base

CONVERGENCE_FRONTIER
  must adopt R3 before adding new runtime after promotion
```

Это правило должно быть механизировано в PC0 одновременно с R3 promotion.

### R3.3 — Wave A

Только после canonical R3:

```text
one R3 base
   ├─ IAM0/IAM1
   ├─ MAT0
   ├─ WT0
   └─ WQ0/WQ1
```

Все четыре ветки регистрируются в PC0 до начала runtime и получают непересекающийся foundation ownership.

---

## 10. Что можно делать параллельно прямо сейчас

Параллельность разрешена, если work не меняет один и тот же foundation.

```text
A. G8.6 manual graphical acceptance
B. CH9.6 manual graphical acceptance
C. control-plane convergence/hardening
D. C22 refresh preparation
E. R3 refresh preparation (без promotion и Wave A runtime)
```

После control hardening:

```text
F. C22 refreshed implementation + tests
G. NX.C1 fresh-base implementation
H. R3 current-main refresh
```

Но:

```text
TS0.4 waits for C22 MAIN_INTEGRATED
T2.0 waits for TS0.4 + PC0
G9 waits for R3/MAT0
Wave A waits for canonical R3
```

---

## 11. Что запрещено до следующего convergence checkpoint

Не делать:

```text
T1B.5
G9 before MAT0/R3
CH9.7 merely to avoid graphical acceptance
legacy N direct merge
legacy FIX7 physics writes
NX.C1 on stale base
TS0.4 before C22 main integration
T2.0 before TS0.4 classification
R3 promotion from stale candidate ancestry
Wave A branches from different architecture bases
```

---

## 12. Definition of synchronized project

Проект считается синхронизированным для следующей волны, когда одновременно выполнено:

```text
PC0 directional watch is canonical
registry/passports have no operational mirror drift
T1B ownership conflict is gone
G tested-head freshness is machine-readable
CH central state matches its accepted Windows evidence
C22 is either refreshed MERGE_READY or MAIN_INTEGRATED
NX runtime work starts from a fresh main base
R3 candidate is refreshed before promotion
all new major frontiers are registered before runtime work
```

После этого branch autonomy остаётся, но branch divergence больше не означает architecture divergence.

---

## 13. Короткий порядок следующих действий

```text
1. Integrate this PC0/control convergence change-set into main.
2. Run CONTROL_PROJECT.ps1 -NoFailOnRed and inspect both standard + directional reports.
3. Finish G8.6 manual graphical gate.
4. Finish CH9.6 manual graphical gate.
5. Build fresh current-main C22 convergence refresh; retest.
6. Explicitly merge C22 only after refreshed MERGE_READY.
7. Run post-merge PC0; mark C22 MAIN_INTEGRATED.
8. Start fresh main-based TS0.4 1M ceiling.
9. In parallel after step 1, refresh NX.C1 from current main and implement minimal owner-authority runtime.
10. Refresh R3 from current main; implement revision-transition rule; promote only on non-RED PC0.
11. After R3 canonical, start IAM/MAT/WT/WQ Wave A from one base.
12. After TS0.4 convergence, activate T2.0 Real Heterogeneous Base / Station.
13. After MAT0, activate G9 Layered Geology.
```

Это и есть текущий canonical correction plan. Любая новая major ветка, не вписывающаяся в этот порядок, сначала должна изменить main-owned registry/architecture gate, а не самостоятельно объявить новый frontier.
