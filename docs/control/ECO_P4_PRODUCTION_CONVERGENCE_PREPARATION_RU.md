# ECO P4 — подготовка production convergence на current `main`

Статус: `CONTROL-ONLY PREPARATION / READY FOR INDEPENDENT REVIEW / RUNTIME TRANSFER NOT AUTHORIZED`.

## Точная база

Новая ветка:

```text
control/eco-p4-production-convergence-prep-r1
```

создана **не от старой ECO lineage**, а от exact canonical `main`:

```text
main = 09714b6f2681e3b5cf3f2f9e28416cf9a7378304
registry generation = 79
architecture = GLOBAL-P0-2026-08-12-R3-REFRESH-R1
```

Это следует правилу проекта: после длинной accepted lineage новый production frontier строится от current canonical main, а не продолжает старый стек.

## Почему нельзя просто merge старую ECO-ветку

Финальный accepted/evidence head старой ветки:

```text
feature/eco-evolutionary-ecology
HEAD = f0e16195f1331f238bbacab2768e5d72ec01d1a3
```

На момент подготовки topology относительно current `main`:

```text
ahead  = 594 commits
behind = 220 commits
merge-base = 790fd79f8055fefa19cf9d7263441fc9f4326ebd
```

Поэтому whole-branch merge/rebase не является convergence strategy.

Дополнительно исходный ECO passport остаётся историческим R2 `RESEARCH_DESIGN_FRONTIER`, имеет `runtime_paths=[]` и прямо запрещает владение `AUTHORITY_FOUNDATION`, `PERSISTENCE_DURABILITY`, `WORLD_QUERY_FABRIC`, `WORLD_LIFECYCLE_FABRIC`, `WORLD_WORK_BUDGET` и `NETWORK_REPLICATION_POLICY`.

Следовательно, P4 branch-local runtime evidence можно сохранять и анализировать, но оно **не является разрешением** перенести P4.4/P4.5 в current main как новые canonical persistence/authority foundations.

## Зафиксированная P4 evidence

Branch-local P4 lifecycle завершён:

```text
acceptance manifest blob =
fa0c1b3540f1efe1a8509a7551542e12fb353bcd

manifest_hash =
02d8804eb102e45eea5999744e09d4b159c22439798415b7637d0cce66596b06

P4.7 exact tested HEAD =
cb5f6c69bfb0299770e09d3acff41a8fbf8aa61c

Godot =
4.7.1.stable.double.custom_build.a13da4feb

soak_hash =
d7cee96abd82c09afab50873bb07271d112684ccad3be4127a995ff8501cd2fe

final_interest_hash =
62d28c383697a01c5b96ec6e9c72b3e71a8fbf5e51a76ddeccacae3885decd2e
```

Эта evidence остаётся provenance source для convergence и не переписывается.

## Минимальный dependency closure

P4 production layer имеет только шесть собственных kernel-файлов. Их рекурсивная ecology dependency chain замыкается на восьми P3 research kernels:

```text
P4 region state
  -> P3.8 ecosystem persistence
     -> P3.7 multi-niche coexistence
        -> P3.6 disturbance/succession
           -> P3.5 seasonal world
              -> P3.4 environmental gradient
                 -> P3.3 spatial dispersal
                    -> P3.2 density/carrying capacity
                       -> P3.1 resource competition
```

Полный exact path/blob manifest записан в:

```text
validation/ecology/eco-p4-production-convergence-preparation.json
```

Его dependency-closure hash:

```text
0764c06f6f15ba1b92a0cacb58ecc168a7513c82d210d9ad14cefc239fc3ef8c
```

## Что можно переносить, а что требует adapter/replacement

### P4.1 Region State

`PORT_CANDIDATE_ECOLOGY_DOMAIN_STATE_ONLY`.

Можно сохранять как ecology-domain state semantics, если он не становится владельцем spatial/authority/lifecycle foundation.

### P4.2 Deterministic Clock

`PORT_CANDIDATE_DOMAIN_TIME_ADAPTER_REQUIRED`.

Локальная deterministic ecology time semantics полезна, но production-вариант должен подключаться к canonical TF/domain-time boundary, а не создавать независимую global time truth.

### P4.3 Offline Catch-up

`PORT_CANDIDATE_WORLD_WORK_BUDGET_AND_LIFECYCLE_ADAPTER_REQUIRED`.

Алгоритм bounded catch-up переносим как ecology policy, но решение *когда/сколько работы выполнять* должно согласовываться с canonical LIFE/WB, а не становиться отдельным production scheduler.

### P4.4 Region Persistence

`DO_NOT_PORT_AS_DURABILITY_OWNER`.

Snapshot/codec и ecology validation могут быть переиспользованы, но durability/save/recovery должны находиться за canonical `R3_M0_MW` persistence boundary. Нельзя переносить этот модуль как второй durability foundation.

### P4.5 Region Ownership / Handoff

`DO_NOT_PORT_AS_AUTHORITY_OWNER`.

Epoch/CAS/handoff invariants полезны как evidence, но production ownership/handoff должен использовать или адаптироваться к canonical AUTHORITY leases/epochs/routing. Прямой перенос как отдельный authority registry запрещён.

### P4.6 Client Read Model

`PORT_CANDIDATE_DERIVED_READ_MODEL_ONLY`.

Можно переносить как derived projection/cache. Он не должен владеть canonical ecology/world state.

### P4.7 Soak

Переносится как regression scenario **после** current-main adapter rewrite. Старые frozen hashes остаются provenance evidence; новые convergence hashes будут новой evidence, а не заменой старых.

## Risk boundary

Сам этот branch — control-only и не меняет runtime.

Будущий runtime convergence имеет minimum risk:

```text
CRITICAL
```

потому что затрагивает:

```text
persistence semantics
authority / ownership epochs
cross-server handoff
public state contracts
architecture ownership boundaries
```

По risk-policy нужны:

```text
Implementer
Independent Reviewer
Verifier
Director
Human
```

до production promotion.

## Concurrency gate

Текущий Harness H0.2 допускает максимум одного autonomous runtime mutation worker до H0.3. Поэтому ECO convergence **не должен** открывать второй параллельный runtime mutation frontier.

Этот preparation branch намеренно содержит:

```text
runtime_paths = []
production runtime delta = 0
```

## Следующий gate

Independent reviewer должен проверить только этот пакет:

1. exact main base и source provenance;
2. dependency closure;
3. отсутствие whole-lineage merge;
4. P4.1–P4.6 portability classification;
5. что P4.4 не объявляется durability owner;
6. что P4.5 не объявляется authority owner;
7. что P4.6 остаётся derived;
8. что single-runtime-worker gate fail-closed;
9. что никакой runtime код не перенесён этим PR.

После reviewer PASS следующий шаг — **main-owned CRITICAL convergence Work Order / Human decision**, и только затем fresh-main runtime branch с минимальным переносом.

## Non-goals

Этот этап НЕ:

- merge старой ECO-ветки;
- меняет registry generation;
- объявляет ECO production canonical;
- переносит runtime kernels;
- меняет `project.godot`;
- создаёт authority/persistence/query/lifecycle/work-budget foundation;
- конкурирует с текущим NX/V0 runtime worker.
