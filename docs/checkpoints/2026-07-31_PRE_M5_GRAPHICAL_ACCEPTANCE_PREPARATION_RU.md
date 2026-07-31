# Checkpoint candidate — pre-M5 graphical acceptance preparation

```text
checkpoint: v16.10.3-pre-m5-graphical-acceptance-preparation
build_id: pre-m5-ui-replica-command-boundary
base: main @ 2879fdb
branch: feature/m5-graphical-multiplayer-acceptance
status: candidate
runtime base: v16.10.3-domain-m4-canonical-shared-gameplay
```

## Назначение

Подготовить M5 без локальной мутации Item Graph и без topology-specific fork:
read-only projection, UI command adapter, transient cursor/pending state,
networked inventory shell и изолированную process environment.

## Acceptance подготовки

- M4 snapshot валидируется по schema/checksum/revision;
- projection не изменяет исходный snapshot;
- UI fields не попадают в wire payload;
- UI отправляет команды только через `execute_item_command_blocking`;
- cursor/pending overlay имеет `canonical_mutation_count = 0`;
- external container видим только по authoritative open session;
- playground создаёт networked inventory shell только для graphical client;
- MCP runtime disabled или получает уникальный port;
- M4/M3/UI/A2/roadmap regressions остаются зелёными.

Полный M5 graphical acceptance не входит в этот checkpoint.

## Проверенная evidence

```text
editor import:  PASS
focused:        13/13 scripts, 939 assertions PASS
network/runtime: 55/55 suites, 4149 assertions PASS
world:          100/100 standalone tests PASS
main scene:     6/6 PASS
```

World manifest совпадает с автоматическим discovery без `tests/**/fixtures`.
