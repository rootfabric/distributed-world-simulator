# SM0 — capability donor summary (сводка для post-P6 решения по V0-SM1)

**Статус:** EXECUTION FACTS / DONOR EVIDENCE SUMMARY — не является self-acceptance и не разрешает merge  
**Ветка:** `feature/sm0-two-authority-seamless-handoff-lab` (PR #102, draft/open)  
**Дата фиксации:** 2026-08-24  
**Составил:** review/verification-only lane SM0 (sync + verification + documentation)  
**Связанные main-owned документы:** `config/control/harness/v0-product-train-policy.v1.json` (`V0_POST_P6_SEAMLESS_INSERTION_GATE`), `docs/plans/V0_POST_P6_SEAMLESS_INTEGRATION_RU.md`, `docs/control/NETWORK_FRAMEWORK_READY_DEVELOPMENT_POLICY_RU.md`

---

## 1. Назначение документа

Этот документ сводит в одном месте, что именно доказала лаборатория SM0
(two-authority seamless handoff), на каком exact head зафиксировано evidence,
какие предикаты VERIFIED, а какие остаются PENDING, и как это следует учитывать
в обязательном решении `ACTIVATE_V0_SM1` / `DEFER_V0_SM1_WITH_EXPLICIT_HUMAN_DECISION`
после приёмки product P6.

Документ составлен по правилам donor rule: SM0 — research/evidence environment,
semantic donor будущего reusable network runtime; он не является production base
и не создаёт второй network/gameplay truth.

## 2. Границы head'ов

```text
Синхронизация ветки 2026-08-24 (этот lane):
  old HEAD : 282051075502b8dc1a72860f9da1aeaee0826909 (behind origin на 18 коммитов, ahead 0)
  new HEAD : 56821fc80dfef65ab07949f19200d24b44329dbf (fast-forward, 2026-08-21T23:55:43+10:00)

Exact Windows-runtime-validated FINAL carrier:
  b5966ef113b73e3156488805057ce9b464362d89 (2026-08-17T23:27:55+10:00)
```

Коммиты после validated carrier `b5966ef1..56821fc8` — только документация и
scoped AGENTS-гайды (`docs/**`, `scripts/network/AGENTS.md`,
`scripts/runtime/seamless/sm0/AGENTS.md`). Runtime-код и тесты после carrier
не менялись, поэтому Windows FINAL evidence остаётся привязанным к текущей
implementation boundary.

## 3. Что доказывает SM0

Лестница P3–P11 + FINAL исполнена внутри лаборатории (см. раздел 12
`docs/plans/V0_SM0_EXPERIMENTAL_MULTISERVER_ROADMAP_RU.md`):

```text
P3/P3.1   two-authority correctness + controlled WAN latency matrix
P4        prewarmed fast handoff (убирает один PREPARE RTT из crossing path)
P5        two players / two authorities / mutual foreign projections
P6        projection pivot during handoff (ghost <-> canonical без respawn)
P7/P7.1   three-authority routing A -> B -> C -> B -> A (+canonical transfer)
P8/P8.1/P8.1.1  nested authority island, reference-frame repair,
          stationary passenger proof (локальная позиция игрока неизменна
          при смене outer authority)
P9        foreign world item boundary: прямая мутация чужого item запрещена,
          interaction routed to current owner, WORLD -> SHIP transfer
          сохраняет item identity, rollback/abort fail-closed
P10       multi-authority view composition + representation LOD:
          3 projection source, per-source epoch/sequence/checksum fencing,
          dropout изолирован, presentation artifact не становится canonical
P11       simultaneous crossings + deterministic fault matrix +
          process-isolated soak (120 iterations, 3 отдельных Godot process)
FINAL     integrated closure gate: один канонический прогон связывает
          P8.1/P8.1.1/canonical handoffs/P9/P10/P11
```

Инварианты, доказанные на всех слоях: ровно один active writer на aggregate;
стабильные logical/player entity identity; монотонный authority epoch;
foreign replica read-only; replay/epoch/revision fencing fail-closed;
handoff не требует reconnect/respawn.

## 4. Предикаты VERIFIED

### 4.1 Windows runtime acceptance (канонический FINAL evidence)

Источник: `docs/checkpoints/2026-08-17_V0_SM0_FINAL_INTEGRATED_CLOSURE_RU.md`.

```text
VERIFIED  FINAL integrated closure PASS @ b5966ef113b73e3156488805057ce9b464362d89
          Godot 4.7.1.stable.double.custom_build.a13da4feb, Windows runtime
          canonical   : 20/20 A<->B authority handoffs; player_identity_changes=0
                        invariant_violation_count=0; unexpected_error_count=0;
                        epoch 1 -> 21
          reference   : P8.1 33 assertions + P8.1.1 14 assertions
          inherited   : P9 full foreign-item boundary gate PASS
                        P10 multi-authority composition gate PASS
          fault       : P11 deterministic matrix PASS (68 assertions)
          soak        : P11 process-isolated simultaneous crossings PASS
                        (120 iterations / 2052 assertions, 3 authority process)
          control     : Project Control на carrier b5966ef1 — SUCCESS, run #855
          статус      : WINDOWS RUNTIME VALIDATED / READY FOR INDEPENDENT CLOSURE REVIEW
```

### 4.2 Linux headless re-verification свежего head (этот lane, 2026-08-24)

Прогоны выполнены на `HEAD = 56821fc80dfef65ab07949f19200d24b44329dbf`,
Godot `4.7.1.stable.double.custom_build.a13da4feb`, headless, worktree чист до/после,
exit code 0 у всех трёх гейтов:

```text
VERIFIED  RUN_V0_SM0_P8_1_1_STATIONARY_PASSENGER.sh  PASS
          focused: P8 96 + P8.1 33 + P8.1.1 14 assertions;
          multi-process сценарий A/C/B + nested + observer;
          local move = 0, max player/deck-marker XZ error = 0.0;
          артефакты: artifacts/runtime/sm0-p8-1-1-20260824-124540-3914178/

VERIFIED  RUN_V0_SM0_P9_FOREIGN_ITEM_BOUNDARY.sh     PASS
          inherited P8 96; focused P9 103; process-isolated P9 55 assertions
          (3 distinct Godot authority processes); transfer WORLD -> SHIP ->
          WORLD со стабильным item id; rollback/abort fail-closed;
          артефакты: artifacts/runtime/sm0-p9-20260824-124634-3917222/

VERIFIED  RUN_V0_SM0_P10_MULTI_AUTHORITY_VIEW.sh      PASS
          inherited полный P9 gate; focused P10 91; process-isolated P10 52
          assertions (LOCAL B + FOREIGN A/C -> одна presentation view);
          per-source fencing, LOD, dropout isolation подтверждены;
          артефакты: artifacts/runtime/sm0-p10-20260824-124721-3919737/
```

## 5. Предикаты PENDING (честно)

```text
PENDING   Linux headless прогон P11 fault matrix + 120-iteration soak
          на свежем head — в этом lane НЕ запускался (ожидаемо тяжелее
          бюджета дешёвого прогона); каноническим evidence остаётся
          Windows PASS @ b5966ef1 (раздел 4.1).

PENDING   Канонический FULL FINAL acceptance (RUN_V0_SM0_ACCEPTANCE.ps1 -Final)
          на Linux headless невоспроизводим как есть: canonical wrapper —
          PowerShell/Windows. Свежий full-FINAL прогон вне Windows не выполнялся.

PENDING   Независимый closure review PR #102 и решение о merge — human gate,
          self-acceptance запрещён; этот документ его не заменяет.

PENDING   Открытые пробелы лаборатории (roadmap раздел 12, не блокируют
          closure review): stop-and-wait movement клиента стенда (сходимость
          с NX4/NX5 не закрыта); inventory fingerprint отсутствует в transfer
          carrier; отказ лидера лабораторной directory во время commit не
          покрыт; cross-zone item mutation forwarding (server-mediated) не
          реализован — P9 доказал только read-only boundary.
```

## 6. Значение для post-P6 решения (POST_P6_GATE)

Main-owned policy (`v0-product-train-policy.v1.json`, узел
`V0_POST_P6_SEAMLESS_INSERTION_GATE`) требует после приёмки P6 явного решения:

```text
ACTIVATE_V0_SM1                            -> V0_SM1_SEAMLESS_PRODUCT_INTEGRATION
DEFER_V0_SM1_WITH_EXPLICIT_HUMAN_DECISION  -> V0_P7_BOUNDED_TERRAIN_MUTATION
```

Что этот summary даёт для того решения:

1. **Evidence зрелость подтверждена.** Полная лестница P3–P11 имеет
   machine-readable evidence; FINAL closure прошёл единым каноническим
   прогоном на exact carrier, а ключевые слои (P8.1.1/P9/P10) дополнительно
   воспроизведены headless на Linux для свежего head `56821fc8`. Это снижает
   риск «evidence есть, но не воспроизводится».
2. **Donor-направление определено.** Переносится semantics, а не код:
   authority handoff contract (stable identity, monotonic epoch, retirement
   proof, replay fencing); generic N-route client topology с ровно одним
   `ACTIVE_AUTHORITY` и pivot `PROJECTION -> WARM -> ACTIVE` без reconnect;
   nested/reference-frame continuity (P8); foreign item boundary rules (P9),
   привязываемые к canonical M4 Item Graph; multi-source projection composer
   с per-source fencing (P10 + MRPF); fault/soak дисциплина (P11).
3. **Запрет переноса lab-truth.** Не переносить как canonical owners: SM0
   synthetic item authority store, лабораторную directory как production
   World Directory, fixture world state, debug ship/deck presentation,
   приватные persistence/network registry semantics.
4. **Аргументы за ACTIVATE_V0_SM1:** доказанная capability закрывает главный
   технический риск seamless-вставки именно на «чистой» границе после P6
   (до terrain mutation и mobile constructs); откладка означает, что P7/P8
   будут строиться поверх single-server модели, а затем потребуют более
   дорогой переделки.
5. **Аргументы за DEFER (честно):** activation predicates требуют принятый
   P6 baseline (5 clean E2E repeats + 30-minute two-client soak),
   независимый closure PASS SM0, MRPF-P6 donor (либо explicit defer в Design
   Brief), PC0 NON_RED, CRITICAL-risk routing и явное human approval — то
   есть решение легитимно только после фактической приёмки P6; до этого
   момента данные SM0 являются необходимым, но недостаточным условием.
6. **Правило решения.** Любое из двух решений фиксируется durable main-owned
   control/evidence записью; chat-сообщение решением не является.

## 7. Сводка статуса одной строкой

SM0 — зрелый, воспроизводимо верифицированный capability donor для seamless
multi-authority V0: Windows FINAL closure PASS @ `b5966ef1` (run #855 SUCCESS),
свежий head `56821fc8` повторно зелёный headless на Linux по слоям
P8.1.1/P9/P10 (exit 0, маркеры подтверждены), P11-Linux/FULL-FINAL-Linux —
PENDING, merge и ACTIVATE/DEFER — человеческие gates после приёмки P6.
