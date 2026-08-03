# INT0 — композиция NX6 и RL3/MW10

**Дата:** 2026-08-03  
**Ветка:** `merge/int0-rl3-mw10`  
**Статус:** `COMPOSED CANDIDATE — RUNTIME GATE REQUIRED`

## Входные головы

```text
integration base with NX6:
796f0b3708ce6f36ca3692145d4fe718a02d01ff

accepted RL3 head:
89ff51b3ee5f66f6548f8b97e271062daf09b5cf

conflict-neutralization commit:
c2e7c1e91993add2dd7aa9387519a391dfbb91ce

RL3/MW10 staging merge:
515b179d276c59df1624fe640eb04464410bf974
```

RL3 head уже содержит MW10, MW9 fix3, RL2, RL1 и RL0. MW10 отдельно не merge-ится.

## Реальные конфликты

Трёхстороннее сравнение от общего предка
`e12e8a1c8bc949180ab9041fa4db308baf3dd11e` выявило шесть файлов,
которые менялись обеими линиями:

```text
AGENTS.md
NETWORK_ROADMAP_RU.md
PROJECT_MANIFEST.txt
README_RU.md
scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd
tests/runtime/test_m3_graphical_multiplayer_contracts.gd
```

Все остальные Matter/Representation files перенесены byte-exact из accepted RL3.

## Runtime-композиция

NX6 остаётся владельцем:

- transport boundary и channel policy;
- compatibility handshake;
- network condition simulation;
- fixed-tick authoritative movement;
- client prediction и reconciliation;
- remote interpolation;
- Item Graph delta/snapshot resync;
- predicted item interaction lifecycle.

Исходный NX6 client runtime сохранён без изменения как:

```text
scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_nx6.gd
```

Production path `m3_graphical_client_runtime.gd` стал узким INT0 adapter поверх этой базы. Adapter добавляет только bounded recovery для ситуации:

```text
GAMEPLAY_DELTA
→ MULTIPLAYER_DELTA_BASE_MISMATCH
→ pending replica resync
→ authoritative GAMEPLAY_SNAPSHOT
→ clear pending state
```

Mismatch не становится sticky terminal error. Он не меняет authority, не принимает client-authored state и не обходит checksum/revision fences replica store.

Добавлена bounded telemetry:

```text
pending_replica_resync
delta_base_mismatches
snapshot_resyncs
```

## Документация

Четыре агрегирующих файла оставлены на NX6-версии во время staging, чтобы не заменять их целиком вариантом RL3:

```text
AGENTS.md
NETWORK_ROADMAP_RU.md
PROJECT_MANIFEST.txt
README_RU.md
```

Полная RL3/MW10 документация уже присутствует в отдельных architecture, roadmap, checkpoint и validation files. Консолидированный текст агрегаторов будет собран отдельным INT0 documentation commit после C24, когда известны все три домена.

## Focused gate

```text
RUN_INT0_RL3_MW10_COMPOSITION_TESTS.ps1
RUN_INT0_RL3_MW10_COMPOSITION_TESTS.sh
```

Focused contract проверяет:

- production wrapper наследует exact NX6 base;
- delta-base mismatch переводит runtime только в bounded pending resync;
- authoritative snapshot снимает pending state;
- telemetry присутствует;
- client не создаёт authority;
- NX6 prediction и Item Graph replication остаются в base;
- replica store сохраняет exact revision fence;
- merge markers отсутствуют.

## Обязательный gate перед integration merge

```text
Editor import
INT0 focused composition contract
NX0–NX6 regression
M7 playable contracts
M7 graphical multiprocess
M7 recovery
MW0–MW10 regression
MW9 fix3 race/recovery
MW8 98/98
RL0–RL3 regression
Dedicated server + two clients
Reconnect/full-resync
Network condition profiles
World regression
Main-scene CLI
git diff --check
conflict markers = 0
remaining Godot/Xvfb = 0
```

В connector-окружении Godot и полный runtime gate не запускались. До их выполнения поставка остаётся `COMPOSED CANDIDATE`, а не `ACCEPTED`.
