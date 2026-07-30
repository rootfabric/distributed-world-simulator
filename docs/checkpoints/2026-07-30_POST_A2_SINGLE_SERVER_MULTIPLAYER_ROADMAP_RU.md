# Checkpoint v16.9.5-roadmap-single-server-multiplayer-first

## Метаданные

```text
checkpoint: v16.9.5-roadmap-single-server-multiplayer-first
build_id: post-a2-single-server-multiplayer-first
base: v16.9.4-architecture-a2-networked-gameplay
branch: feature/post-a2-single-server-multiplayer-roadmap
scope: documentation, roadmap dependencies, machine-readable strategy, contract gate
status: accepted
strategy: FULL_SINGLE_SERVER_MULTIPLAYER_FIRST
```

## Решение

После принятия A2 основной поток разработки переносится с B1 на завершение полноценного односерверного graphical multiplayer.

```text
A2 → M1 → M2 → M3 → M4 → M5 → M6 → A3 → B1 → B2 → N3 → N4 → N5 → N6
```

Причина: A2-D01…D04 являются прямыми препятствиями для production multiplayer, а NATS не закрывает graphical client, общий gameplay service, canonical Item Graph contention или dedicated recovery.

## Зафиксированные зависимости

- M1 закрывает A2-D01 и A2-D02;
- M2 требует M1;
- M3 требует M2;
- M4 требует M3, M1 и M0;
- M5 требует M4 и N2 process harness;
- M6 требует M5, R3.1 и M0;
- A3 требует принятия M1–M6;
- B1 требует A3 и остаётся чистым B0 adapter;
- B2 следует после B1;
- N3 требует A3 и B2;
- N4–N6 остаются последовательными.

## Machine-readable sources

- `config/network/network-roadmap.v1.json` revision 21;
- `config/network/networked-gameplay-architecture.v1.json` revision 3;
- `config/network/single-server-multiplayer-roadmap.v1.json` revision 2.

## Acceptance checkpoint

- A2 отмечен accepted;
- M1 является единственным next stage;
- B1 помечен deferred after A3;
- N3–N6 заблокированы до A3/B2;
- точный M1–M6/A3 scope и acceptance записаны;
- ENet остаётся graphical realtime transport;
- NATS ограничен server-to-server communication;
- runtime gameplay files не изменены;
- roadmap contract test и full manifests зелёные.

## M1 implementation update

M1 принят как checkpoint `v16.10.0-runtime-m1-unified-networked-gameplay-core`. Общий service и validators закрывают A2-D01/D02; M2 становится следующим этапом после независимой приёмки M1.


M2 candidate `v16.10.1-runtime-m2-dedicated-graphical-client` использует принятый M1 core в топологии headless dedicated + ordinary graphical client.
