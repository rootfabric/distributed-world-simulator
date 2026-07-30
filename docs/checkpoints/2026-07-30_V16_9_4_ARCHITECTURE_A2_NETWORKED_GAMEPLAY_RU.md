# Checkpoint v16.9.4 — A2 Networked Gameplay Architecture

## Метаданные

```text
checkpoint: v16.9.4-architecture-a2-networked-gameplay
build_id: a2-networked-gameplay-audit-freeze
base: v16.9.3-runtime-h3-dedicated-multiplayer
branch: feature/a2-networked-gameplay-architecture
scope: documentation, ADR, contract audit, test matrix, machine-readable freeze
status: accepted
```

## Зафиксировано

- canonical client → authority → replica pipeline;
- player/entity/session/ownership/authority identity model;
- command ownership и permission fences;
- movement replication и correction policy;
- inventory/contention conservation;
- reconnect/replay semantics;
- peer-to-player mapping;
- relevance одной server region;
- client capability boundary;
- change control перед B1 и N3–N6.

## Итог аудита

A2 честно разделяет frozen target и текущую implementation evidence. H1 доказывает graphical full gameplay path. H2/H3 доказывают dedicated transport, ownership, two-peer movement/contention/reconnect через headless protocol clients.

Остаются P1 gates A2-D01…D04: общий production gameplay service, shared validators, two-window graphical/full Item Graph proof и dedicated crash/restart recovery. B1 разрешён только как adapter-only этап поверх B0. N3–N6 заблокированы до закрытия gates.

## Проверка

```text
RUN_A2_NETWORKED_GAMEPLAY_AUDIT
→ editor import
→ A2 freeze manifest/source audit
→ H3 focused profile regressions (H3/H2/H1/H0/T1)
```

Дополнительно обязательны:

```text
RUN_NETWORK_CONTRACT_TESTS
RUN_WORLD_REGRESSION_TESTS
main_scene_cli_all
```

Подтверждённое покрытие кандидата:

```text
A2 focused: 11/11 tests, 617 assertions PASS
network/runtime manifest: 44 suites, 3426 assertions PASS
world manifest: 87/87 standalone tests PASS
main scene: 6/6 PASS
```

Network-результат собран из полного принятого профиля 39/39 (3168 assertions) и добавленных в A2 manifest пяти H2/H3/A2 suites (258 assertions). World-результат состоит из ранее полного 82/82 профиля и пяти новых manifest suites; все пять повторно прошли в A2 focused gate.

## Acceptance

- freeze manifest валиден и согласован с roadmap;
- H1/H2/H3 и A2 отмечены accepted; M1 является следующим этапом; B1 перенесён после A3;
- ADR-011 и audit document присутствуют;
- source evidence подтверждает declared invariants и declared debts;
- existing H3/H2/H1/H0/T1 tests зелёные;
- B1 restrictions и multi-authority blockers однозначны;
- production gameplay code не изменён.

## Post-acceptance roadmap correction

После независимой приёмки A2 утверждено решение `FULL SINGLE-SERVER MULTIPLAYER FIRST`. A2-D01…D04 закрываются этапами M1–M6; затем выполняется A3. B1/B2 перенесены после A3, N3–N6 — после B2.

## M1 closure update

Accepted `v16.10.0-runtime-m1-unified-networked-gameplay-core` свёл H1/H2/H3 к общей composition root и вынес validators из authority implementations. `A2-D01` и `A2-D02` отмечены closed by M1. `A2-D03` и `A2-D04` остаются открыты до M3–M6.


M2 candidate `v16.10.1-runtime-m2-dedicated-graphical-client` использует принятый M1 core в топологии headless dedicated + ordinary graphical client.
