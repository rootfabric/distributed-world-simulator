# Дорожная карта универсального человекоподобного персонажа

**Дата решения:** 3 августа 2026 года  
**Репозиторий:** `rootfabric/distributed-world-simulator`  
**Ветка:** `feature/ch0-universal-character-presentation-roadmap`  
**База ветки:** `main @ 69bd7fc7fde2bc0824b0d608451ecd310397b8d2`  
**Связанный merge-план:** `agent/three-domain-integration-merge-plan @ 9742f8acf342dbc9712b8f2371e8f009c3d2cfc1`  
**Статус:** documentation and isolated foundation branch; не предназначена для прямого merge в `main` после начала трёхдоменной интеграции.

## 1. Назначение

Цель ветки — подготовить замену текущего условного персонажа на сменный человекоподобный персонаж с анимациями, сетевым отображением, экипировкой и поддержкой нескольких моделей, не связывая gameplay и authoritative simulation с конкретным `MeshInstance3D`, `Skeleton3D`, именами костей или именами анимаций.

Целевая формула:

```text
Player canonical state
+ movement/network state
+ CharacterDefinition
+ CharacterPresentationAdapter
= сменный визуальный персонаж
```

Персонаж не является отдельным authoritative доменом. Он является клиентским presentation-слоем над уже существующими player, movement, inventory и interaction contracts.

## 2. Текущее состояние

### 2.1 Общая runtime-композиция

`main.tscn` содержит только `SimulatorApp`. `scripts/app/simulator_app.gd` создаёт runtime и presentation nodes программно, выбирая offline/listen-host/game-client/dedicated-server режимы.

Существующая архитектура уже содержит полезную границу:

```text
SimulationKernel
PresentationHost
M3DedicatedServerRuntime
M3GraphicalClientRuntime
```

Dedicated server не должен загружать модели, скелеты, материалы, анимации и GPU-ресурсы персонажей.

### 2.2 Удалённый игрок

Текущий файл:

```text
scripts/runtime/networked_gameplay/m3/remote_player_presenter.gd
```

Удалённый игрок сейчас:

- создаёт `CapsuleMesh` радиусом `0.35` и высотой `1.8`;
- создаёт собственный `SpotLight3D`;
- получает `position`, `velocity`, `orientation_yaw`, `flashlight_enabled` и `state_revision`;
- интерполирует позицию с `interpolation_rate = 12.0`;
- не имеет input authority.

Это presentation-only реализация, но она жёстко создаёт конкретную геометрию внутри presenter и не имеет общего интерфейса с локальным игроком.

### 2.3 Локальный игрок

Локальный игровой путь связан с текущей сценой игрока, камерой, вводом, interaction ray, предметами в руках и отправкой movement intent в graphical client runtime.

Критический недостаток текущего состояния:

```text
local player presentation != remote player presentation
```

Прямая замена только локального меша приведёт к двум независимым реализациям анимаций, экипировки, фонаря, сокетов и внешнего вида.

### 2.4 Сетевая ветка уже меняет player runtime

`feature/nx3-fixed-tick-authoritative-simulation` меняет:

```text
scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd
scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd
scripts/runtime/networked_gameplay/services/player_movement_service.gd
scripts/app/simulator_app.gd
scripts/items/presentation/item_gameplay_controller.gd
```

Далее NX4–NX6 должны добавить prediction/reconciliation, remote interpolation и predicted item interactions. Поэтому текущая character-ветка не должна независимо переписывать M3 runtime или окончательно подключать модель к сетевому игроку.

## 3. Архитектурное решение

### 3.1 Player simulation не зависит от модели

Целевая структура:

```text
PlayerActor
├── PlayerMotor
├── PlayerNetworkProxy
├── PlayerPresentationHost
│   └── CharacterPresentationAdapter
├── CameraRig
└── InteractionRig
```

Для удалённого игрока:

```text
RemotePlayerPresenter
├── interpolated player state
└── PlayerPresentationHost
    └── CharacterPresentationAdapter
```

Один и тот же `PlayerPresentationHost` используется для локального и удалённого персонажа.

### 3.2 CharacterDefinition

Каждый доступный персонаж описывается стабильным ресурсом:

```text
character_id
presentation_scene
animation_profile
body_profile
socket_profile
first_person_profile
default_appearance
asset_revision
```

Сеть и persistence хранят только стабильные IDs и канонические appearance parameters. Пути `res://...` не должны приходить от клиента по сети.

### 3.3 CharacterPresentationAdapter

Базовый интерфейс presentation implementation:

```gdscript
class_name CharacterPresentationAdapter
extends Node3D

func configure(definition, appearance, is_local_player: bool) -> Dictionary:
    return {"success": true, "error_code": "", "details": {}}

func apply_motion_state(state) -> void:
    pass

func apply_action_state(state) -> void:
    pass

func apply_equipment_state(state) -> void:
    pass

func get_socket(socket_id: StringName) -> Node3D:
    return null

func set_first_person_mode(enabled: bool) -> void:
    pass
```

Конкретные модели Quaternius, KayKit, собственный humanoid или технический dummy реализуют один контракт.

### 3.4 Семантические анимации

Gameplay не использует импортированные имена анимаций. Он работает с семантическими IDs:

```text
locomotion/idle
locomotion/walk
locomotion/run
locomotion/strafe_left
locomotion/strafe_right
locomotion/jump_start
locomotion/fall
locomotion/land
stance/stand
stance/crouch
action/pickup
action/drop
action/use
action/place
action/repair
pose/empty
pose/tool
pose/two_handed
```

`CharacterAnimationProfile` сопоставляет семантический ID с ресурсом конкретного rig.

### 3.5 Физическое тело отдельно от визуального

`CharacterBodyProfile` задаёт разрешённую сервером физическую форму:

```text
body_profile_id
standing_height
crouching_height
capsule_radius
eye_height
step_height
mass
movement_profile_id
```

В первой поставке мужская, женская и техническая humanoid-модели используют один `human_standard` profile. Масштаб меша не изменяет authoritative capsule.

### 3.6 Сокеты

Единые semantic sockets:

```text
head
hand_left
hand_right
chest
back
hip
tool_primary
tool_secondary
flashlight
```

Каждая модель сопоставляет socket с костью или `Marker3D`. Отсутствующий socket обязан давать контролируемый fallback, а не crash.

## 4. Граница автономного развития

### 4.1 Разрешено без merge с тремя активными ветками

Ветка может независимо развиваться до checkpoint:

```text
CH3 ACCEPTED — Isolated Universal Character Presentation Foundation
```

Разрешённый объём:

```text
CH0 — audit and roadmap
CH1 — presentation contracts and registry
CH2 — humanoid asset import and validation lab
CH3 — isolated PlayerPresentationHost and semantic AnimationTree
```

На этом уровне изменения должны оставаться преимущественно additive:

```text
scripts/characters/**
scenes/labs/character/**
resources/characters/**
config/characters/**
tests/characters/**
docs/characters/**
docs/plans/**
RUN_CHARACTER_*_TESTS.*
```

Разрешается минимальный compatibility adapter вокруг legacy presentation только в отдельной laboratory scene. Нельзя переключать production/local/remote player runtime на новый host.

### 4.2 Жёсткая остановка

До синхронизации запрещено начинать production wiring этапа CH4:

```text
CH4 — Local and Remote Runtime Integration
```

В частности, до sync нельзя независимо изменять:

```text
scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd
scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd
scripts/runtime/networked_gameplay/m3/remote_player_presenter.gd
scripts/runtime/host_client/multiplayer_gameplay_replica_store.gd
scripts/runtime/networked_gameplay/contracts/player_state_*.gd
scripts/app/simulator_app.gd
scripts/items/presentation/item_gameplay_controller.gd
RUN_WORLD_REGRESSION_TESTS.ps1
PROJECT_MANIFEST.txt
README_RU.md
AGENTS.md
```

Причина: эти файлы уже принадлежат зоне конфликтов NX3–NX6, RL3, C24 и будущих INT0/INT1 adapters.

## 5. Связь с планом трёхдоменной интеграции

Merge-план фиксирует остановки:

```text
Construction / Items: C24 ACCEPTED
Network:              NX6 ACCEPTED
Matter / Surface:     MW10 + RL3 ACCEPTED
```

После этого создаётся:

```text
integration/c24-nx6-mw10-rl3
```

Порядок:

```text
main
→ NX6
→ MW10 + RL3
→ C24
→ INT0
→ INT1 runtime decomposition
```

Character-ветка не становится четвёртым независимым domain merge. Она должна подключаться как presentation adapter поверх интегрированной player runtime.

## 6. Точки синхронизации

### SYNC-A — наблюдение без merge

Пока разрабатываются CH0–CH3, после каждого принятого upstream checkpoint выполнять только impact review:

```text
NX4 accepted
NX5 accepted
NX6 accepted
MW10 accepted
RL3 accepted
C24 accepted
```

На character-ветке фиксируется:

```text
upstream branch
upstream head SHA
changed overlapping files
contract changes
required follow-up
```

Не выполнять регулярные merge/rebase каждого upstream branch: это превратит character-ветку в скрытую интеграционную ветку.

### SYNC-B — обязательная синхронизация после INT1

Основная точка переноса:

```text
INT0 ACCEPTED
→ INT1 Runtime Decomposition ACCEPTED
→ rebase/merge CH3 foundation onto integration branch
```

INT1 должен создать или стабилизировать:

```text
GraphicalClientRuntime
└── PlayerRealtimeAdapter
```

После этого character presentation подключается к `PlayerRealtimeAdapter`, а не напрямую к монолитному M3 runtime.

### SYNC-C — сетевые presentation contracts после INT2

CH5, который добавляет networked character identity, appearance, stance и action state, следует выполнять после:

```text
INT2 Unified Traffic Classes ACCEPTED
```

Рекомендуемые logical messages:

```text
PLAYER_PRESENTATION_DESCRIPTOR
PLAYER_PRESENTATION_STATE
PLAYER_ACTION_EVENT
```

Они используют общий traffic policy, но не передают bone transforms или AnimationTree state.

### SYNC-D — equipment and construction interaction

CH6 выполняется после наличия:

```text
NX6 predicted item interactions
C24 item/construction composition
INT1 adapters
```

Причина: предмет в руке, pickup/drop/place/repair и construction tool poses должны использовать единый action/equipment contract, а не отдельную локальную анимационную ветку.

### SYNC-E — production relevance and LOD

Character LOD, animation throttling, remote visibility и per-client character relevance включаются после:

```text
INT6 Unified Interest and Streaming
```

До INT6 можно иметь локальный distance policy для лаборатории, но нельзя объявлять его production interest authority.

## 7. Этапы исполнения

## CH0 — Baseline Audit and Roadmap

Работы:

- зафиксировать текущую local player scene hierarchy;
- зафиксировать M3 remote presenter contract;
- найти прямые зависимости от конкретных mesh/node paths;
- описать camera, flashlight, held item и interaction ownership;
- определить список запрещённых production runtime files до sync;
- добавить roadmap и branch checkpoint.

Acceptance:

```text
Documentation consistency PASS
No gameplay files changed
Branch based on recorded main SHA
Autonomous boundary recorded
Mandatory sync point recorded
```

## CH1 — Presentation Contracts and Registry

Добавить:

```text
scripts/characters/contracts/character_definition.gd
scripts/characters/contracts/character_body_profile.gd
scripts/characters/contracts/character_animation_profile.gd
scripts/characters/contracts/character_socket_profile.gd
scripts/characters/contracts/character_appearance.gd
scripts/characters/contracts/character_motion_state.gd
scripts/characters/contracts/character_action_state.gd
scripts/characters/presentation/character_presentation_adapter.gd
scripts/characters/registry/character_registry.gd
```

Требования:

- fail-closed validation;
- stable IDs;
- duplicate rejection;
- fallback definition;
- no runtime node or RID in serialized contracts;
- no arbitrary resource path from network payload;
- headless-safe contract tests.

Acceptance:

```text
Character contract tests PASS
Registry tests PASS
Serialization roundtrip PASS
Presentation-object rejection PASS
Headless load PASS
```

## CH2 — Humanoid Import and Validation Lab

Добавить первый humanoid pack и технический dummy.

Минимальные определения:

```text
human/quaternius/male
human/quaternius/female
human/test_dummy
```

Лаборатория проверяет:

- scale in meters;
- `-Z` forward convention;
- `SkeletonProfileHumanoid` mapping;
- animation import;
- material loading;
- socket mapping;
- first-person visibility policy;
- repeated import stability;
- double precision Godot 4.7.1 compatibility.

Минимальные анимации:

```text
idle
walk
run
strafe_left
strafe_right
jump_start
fall
land
pickup
use
```

Acceptance:

```text
Editor import PASS
Character lab PASS
All three definitions instantiate
Required semantic animations resolved
Required sockets resolved or controlled fallback
No asset loaded by dedicated headless contract test
```

## CH3 — Isolated Presentation Host and Animation State

Добавить:

```text
PlayerPresentationHost
LegacyCharacterPresentationAdapter
HumanoidCharacterPresentationAdapter
semantic AnimationTree
motion/action state driver
```

Ограничение: только laboratory fixture; production M3/local player runtime не переключается.

Animation state определяется по фактическому state, не по `Input`:

```text
velocity
grounded
stance
locomotion_mode
facing_yaw
aim_yaw
aim_pitch
action_id
action_sequence
action_started_tick
```

Acceptance:

```text
Same state produces same semantic animation
Local and simulated-remote fixtures use same host
Network jitter fixture does not flap idle/walk
Repeated action_sequence replays distinct actions
Missing animation uses deterministic fallback
CH3 independent acceptance PASS
```

После CH3 ветка замораживается для production wiring до SYNC-B.

## CH4 — Local and Remote Runtime Integration

База: интеграционная ветка после INT1.

Работы:

- подключить `PlayerPresentationHost` к `PlayerRealtimeAdapter`;
- заменить CapsuleMesh creation внутри remote presenter;
- использовать один host для local и remote paths;
- оставить camera, collision, input и interaction вне imported character scene;
- сохранить authoritative movement и NX5 interpolation;
- исключить presentation resources из dedicated server.

Acceptance:

```text
Local player uses selected CharacterDefinition
Remote players use same presentation contract
NX0–NX6 regression PASS
No input authority on remote presentation
Presentation does not mutate canonical player state
Headless server does not instantiate character scenes
```

## CH5 — Replicated Character Identity and Action State

База: после INT2.

Надёжно при join/change:

```text
character_definition_id
body_profile_id
appearance
appearance_revision
asset_revision
```

В player state/delta:

```text
locomotion_mode
stance
grounded
facing_yaw
aim_yaw
aim_pitch
equipment_pose
```

Разовые события:

```text
action_id
action_sequence
action_started_tick
```

Не передавать:

```text
bone transforms
AnimationTree parameters
raw animation names
playback position every tick
resource paths
```

Acceptance:

```text
Two clients can use different models
Late join restores appearance
Reconnect restores appearance
Unknown definition uses fallback
Packet loss cannot leave terminal action stuck
Persistence contains IDs, not presentation nodes
```

## CH6 — Camera, Equipment and Interaction Poses

Работы:

- first-person hide-head policy;
- body shadow preservation;
- semantic equipment sockets;
- flashlight socket plus camera aim policy;
- held item replication;
- pickup/drop/use/place/repair overlays;
- upper-body aim layer;
- missing socket fallback.

Acceptance:

```text
Remote client sees flashlight and held item
First-person camera is not occluded by head
Body continues casting shadow
NX6 pickup/drop rollback restores presentation
Construction placement ghost remains local until confirmation
Equipment changes do not recreate player entity
```

## CH7 — Production Hardening

Работы:

- character asset manifest and checksums;
- fallback on missing/corrupt assets;
- bounded animation update budget;
- remote animation throttling;
- character LOD integration after INT6;
- reconnect/restart tests;
- network condition tests;
- memory leak and repeated swap tests;
- full regression runners.

Acceptance:

```text
Editor import PASS
Character focused suites PASS
NX0–NX6 PASS
INT0–required-current-stage PASS
World regression PASS
Main scene PASS
Dedicated server PASS
Two graphical clients PASS
Reconnect and late join PASS
Repeated model swap bounded
Git diff check PASS
```

## 8. Правила ведения ветки

1. Ветка создана от зафиксированного `main`, а не от одной из трёх domain branches.
2. До CH3 изменения преимущественно additive.
3. Не merge-ить NX, C и MW/RL branches внутрь character branch по отдельности.
4. Не переписывать историю и не использовать force-push.
5. Каждый stage имеет отдельный commit/checkpoint и machine-readable validation manifest.
6. После CH3 разрешены только fixes внутри isolated foundation до SYNC-B.
7. Production wiring начинается на новой ветке от интеграционной базы после INT1.
8. Старую pre-integration ветку не merge-ить целиком стратегией `ours/theirs`.
9. Переносить CH0–CH3 как проверенные additive commits или контролируемый cherry-pick/rebase.
10. Все конфликты в M3/runtime files разрешать через adapters.

## 9. Предлагаемые ветки этапов

До интеграции:

```text
feature/ch0-universal-character-presentation-roadmap
feature/ch1-character-presentation-contracts
feature/ch2-humanoid-import-lab
feature/ch3-isolated-character-presentation-host
```

После INT1:

```text
feature/ch4-integrated-player-presentation
feature/ch5-networked-character-identity
feature/ch6-character-equipment-camera
feature/ch7-character-production-hardening
```

CH4 создаётся от актуального integration head, а не продолжается напрямую от старого `main` head без синхронизации.

## 10. Рекомендуемая последовательность

```text
NOW
CH0 documentation
→ CH1 contracts
→ CH2 import/lab
→ CH3 isolated host
→ FREEZE

THREE-DOMAIN WORK
NX6 + MW10/RL3 + C24
→ INT0
→ INT1

CHARACTER SYNC
port CH0–CH3 foundation
→ CH4 local/remote integration
→ INT2
→ CH5 networked identity/actions
→ CH6 equipment/interactions
→ INT6
→ CH7 hardening/LOD
```

## 11. Неподвижные правила

- сервер остаётся источником истины;
- модель и AnimationTree не являются canonical state;
- физическое тело не определяется масштабом mesh;
- local и remote player используют один presentation contract;
- gameplay не знает импортированные имена костей и анимаций;
- сеть передаёт semantic state, а не bone transforms;
- dedicated server не загружает character assets;
- неизвестный character ID не разрывает сессию, а выбирает fallback;
- смена модели не меняет player entity, inventory или ownership;
- presentation smoothing не изменяет authoritative transform;
- production runtime integration выполняется только после INT1;
- character relevance/LOD подключается к общему interest system после INT6.
