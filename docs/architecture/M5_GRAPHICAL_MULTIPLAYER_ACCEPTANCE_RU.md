# M5 — Graphical Multiplayer Acceptance

## Статус

```text
checkpoint: v16.10.4-testing-m5-graphical-multiplayer-acceptance
build_id: m5-ui-driven-graphical-multiplayer-acceptance
base: v16.10.3-pre-m5-graphical-acceptance-preparation
runtime base: v16.10.3-domain-m4-canonical-shared-gameplay
status: candidate
```

M5 завершает пользовательскую single-server multiplayer vertical: один headless dedicated server и два одновременно работающих обычных графических Godot-клиента используют реальные InputMap и inventory widgets, но единственный authoritative gameplay path остаётся на dedicated server.

## Канонический путь UI

```text
inventory/hotbar widgets
→ M5InventoryUiBridge
→ M4ItemCommandAdapter
→ ITEM_COMMAND over ENet
→ NetworkedGameplayService
→ canonical Item Graph mutation
→ targeted CommandResult + Item Graph snapshot
→ M4ItemGraphUiProjection
→ inventory/hotbar widgets
```

UI не содержит authoritative или domain references. Cursor, drag preview и pending operation — только transient client overlay. Они не входят в checksum и не переживают reconnect.

## Автоматизированная топология

```text
Process 1: headless dedicated server
Process 2: graphical client A, phase 1
Process 3: graphical client B
Process 4: graphical client A, reconnect phase 2
```

На Linux клиенты запускаются в X11/Xvfb с `gl_compatibility`; `--headless` для клиентов запрещён. Каждый процесс имеет отдельные `HOME`, `APPDATA`, `LOCALAPPDATA` и `XDG_*`. MCP runtime bridge отключён, поэтому процессы не конкурируют за порт.

## Acceptance-сценарий

1. A и B подключаются, получают independent ownership и видят remote presenters.
2. Оба двигаются через реальные InputMap actions.
3. Inventory открывается через Tab и строится из replica state.
4. A и B через inventory cells одновременно пытаются взять один beacon.
5. Ровно один получает `SUCCEEDED`, второй — `ITEM_ALREADY_CLAIMED`.
6. Победитель через UI выполняет hotbar assignment, container round-trip, mount/detach, drop, repick и повторное hotbar assignment.
7. A подбирает ore, оставляет предмет на transient cursor и отключается.
8. B продолжает authoritative движение и удаляет remote presenter A.
9. Новый graphical process A подключается к той же player entity с ownership epoch `2`.
10. Canonical ore inventory восстановлен, transient cursor отсутствует.
11. Server, A и B фиксируют одинаковые player-state и Item Graph checksums до graceful leave.
12. Все процессы завершаются без ObjectDB/resource leak и MCP port collision markers.

## Закрываемая граница

M5 закрывает `A2-D03`: два настоящих graphical clients, presentation interpolation, canonical Item Graph, UI-driven shared gameplay, contention, disconnect/reconnect и checksum convergence доказаны одним воспроизводимым process-test.

## Не входит в M5

Crash/restart dedicated server и durable recovery относятся к M6. M5 доказывает reconnect внутри одной жизни authority, но не восстановление после потери server process.
