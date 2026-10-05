# V0-UX0 R1 — Product Shell

## Статус

IMPLEMENTATION CANDIDATE.

Base main:

`9518d1cd6ea4b2cc61323f0c684d6905f24f367f`

Branch:

`feature/v0-ux0-product-shell-r1`

## Цель

Убрать обязательный ручной CLI из обычного local/LAN product flow, не создавая новых
network, gameplay или persistence owners.

UX0 R1 реализует:

```text
launch app with no user CLI
        ↓
UX0 Product Shell
        ↓
+----------+-----------+-----------+
| Continue | Host World| Join World|
+----------+-----------+-----------+
        ↓         ↓           ↓
 existing   dedicated-server  game-client
 LIVE.3     + game-client     process
 slot       processes
        \         |          /
         +--------LaunchOptions
                    ↓
               SimulatorApp
                    ↓
              existing M3/M4
```

## Product Shell

Default product entry with no user arguments opens:

- Continue;
- Host World;
- Join World;
- Settings;
- Developer;
- Exit.

Explicit runtime CLI remains supported and bypasses the shell.

### Host World

R1 exposes:

- World: Earth;
- Player name;
- UDP port;
- persistence slot.

The shell launches a dedicated server process with:

- `--role=dedicated-server`;
- `--network-mvp`;
- `--world=earth`;
- `--server-port=<port>`;
- `--instance-id=<slot>`.

It does **not** pass a new persistence root. The existing LIVE.3 resolver maps the
instance slot into the accepted product recovery namespace.

After server launch, the shell launches a normal game-client process for the selected
player.

### Join World

R1 exposes:

- server address;
- port;
- player name.

The client receives no persistence root and no hosted instance slot.

### Continue

The shell stores only local launcher preferences under:

`user://v0-live/product-shell.json`

Stored data:

- default player name;
- default port;
- last server address;
- last hosted world;
- last persistence slot;
- last mode.

This is not gameplay state and is not a canonical persistence owner.

Continue reuses the last hosted slot. If the local UDP port is already occupied, it
assumes the local dedicated server is already running and launches only the client;
otherwise it starts the server first and then the client.

## Minimal product HUD

The existing LIVE.2 overlay is extended with read-only product information:

- connection / reconnect state;
- logical player;
- ownership epoch;
- inventory item count;
- selected hotbar item;
- mining-tool state;
- build-mode state;
- short interaction/input hint.

The HUD reads replicated/runtime state only. It cannot mutate canonical truth except
through the already accepted user commands.

## Architectural constraints

UX0 R1 must not create:

- another Item Graph;
- another Construction owner/store;
- another resource owner;
- another persistence repository;
- client-side gameplay truth;
- a second reconnect mechanism;
- a new network transport.

The shell is configuration/process orchestration only.

## Exact acceptance

Required focused checks:

1. no user CLI opens Product Shell;
2. explicit runtime CLI bypasses Product Shell;
3. real `main.tscn` Product Shell entry constructs successfully;
4. Host builds dedicated-server network-MVP args and maps slot to `instance-id`;
5. Join builds game-client network-MVP args without persistence ownership;
6. launcher preferences normalize and persist only local UX state;
7. cold Godot import has no parse/script/compile errors;
8. existing LaunchOptions tests remain green;
9. LIVE.2 reliability/automation focused regressions remain green;
10. tracked source clean and no Godot process leak.

## R1 non-goals

- final inventory visual polish;
- build ghost rotation polish;
- LAN discovery;
- server browser;
- accounts/auth;
- public Internet matchmaking;
- updater/launcher executable;
- packaged build distribution.

Those belong to UX0 R2 / USER1 / DEMO1.
