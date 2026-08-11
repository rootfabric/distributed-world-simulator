# FirstPersonEmbodiment research prototype

Status: **RESEARCH / NON-CANONICAL / NOT A CH9.7 CLAIM**

Base checkpoint: accepted CH9.6 runtime head `e547ba52a440e72cc02c6bbe449edaf160bae7ab`.

The accepted CH9.6 branch remains frozen. This research branch exists only to test a first-person embodiment presentation on top of the accepted character, clothing, Item Graph and ENet stack. It must not be merged as a Character stage until the central control plane explicitly opens the next Character frontier.

## Goal

Add a first-person body/viewmodel layer that can eventually support:

- two independent hands;
- held tools and items;
- world-object grabbing;
- clothing visible from first person;
- local camera effects such as sway and bob;
- server-authoritative ownership of canonical items;
- remote third-person presentation without duplicating Item Graph truth.

The new layer must remain a consumer of gameplay/network state. It must never become a second item inventory, movement controller, physics authority or persistence owner.

## External source review

### RockchuckDev / Physics-Arsenal

Repository: `RockchuckDev/Physics-Arsenal`, MIT, Godot .NET 4.7.

Relevant source:

- `PlayerController.cs` — force-driven `RigidBody3D` character controller.
- `PlayerInteraction.cs` — separate left/right grab state, raycast acquisition, optional child `Grab Point`, spring-like translation and quaternion rotation toward a camera-relative target, drop on excessive separation.
- `Player.tscn` — physics player root plus camera and interaction ray.

Useful ideas:

- per-hand state instead of one global held item;
- object-defined grip point;
- orientation override at the object/grip level;
- distance-based forced release.

Rejected for direct integration:

- its movement controller, because PlanetSimulator already has accepted movement/network prediction ownership;
- direct client manipulation of canonical rigid bodies;
- scene-tree physics joints as authority truth;
- C#/.NET dependency for the current GDScript character path.

### Jeh3no / Godot-simple-FPS-weapon-system

Repository: `Jeh3no/Godot-simple-FPS-weapon-system`, MIT.

Relevant source:

- `weapon_resources_script.gd` — data-driven animation, position, tilt, sway, bob and recoil parameters.
- weapon manager / component split — presentation behavior is composed from smaller modules instead of being hard-coded into the player.

Useful ideas:

- Resource-driven viewmodel presentation parameters;
- independent sway/bob/recoil presentation;
- modular item-specific presentation behavior.

Rejected for direct integration:

- weapon/ammo ownership inside the viewmodel resource;
- FPS weapon manager as the owner of the equipped item list.

PlanetSimulator should split presentation data from gameplay data. A future `GripPresentationProfile` may contain offsets, hand pose, sway and animation hints, but the Item Graph remains the item truth.

### bukkbeek / GodotFPS-Template

Repository: `bukkbeek/GodotFPS-Template`, MIT code with additional asset-use restrictions documented by its author.

Relevant source:

- `player/player.tscn` — normal `MainCamera`, `WeaponsManager`, and a transparent `WeaponSubViewport` with its own camera/render mask.
- `common/managers/weapons_manager.gd` — a weapon rig follows the main camera by interpolating position and basis; weapon switching remains presentation-oriented.

Useful ideas:

- isolate first-person geometry from world geometry;
- optional independent viewmodel camera/FOV as a later refinement;
- smooth camera-follow presentation without touching the gameplay body.

PlanetSimulator already has a cleaner first step: `ControllablePresentationProfile.VIEWMODEL` plus distinct world/viewmodel/shadow render layers. The research prototype therefore uses the existing layer policy first. A SubViewport should be added only if independent FOV/depth/post-processing becomes necessary.

### Cogito immersive-sim template

Reviewed source from the public Cogito lineage:

- `COGITO/Components/PlayerInteractionComponent.gd` — raycast-driven interaction component, carry target, carried-object state, wieldables separated from movement.
- `COGITO/Components/Interactions/CarryableComponent.gd` — a `RigidBody3D` is pulled toward a target using velocity; it drops if separation grows too large and can lock rotation while carried.

Useful ideas:

- interaction as a component instead of player-controller responsibility;
- carry point distinct from camera origin;
- automatic release when a physical object cannot keep up;
- separate wieldable and carryable concepts.

Rejected for canonical multiplayer without modification:

- client-local rigid-body velocity as final truth;
- a single carried object state for both hands.

## Existing PlanetSimulator support discovered

The accepted character stack already contains most of the rendering infrastructure needed for first person:

1. `ControllablePresentationProfile` already defines `VIEWMODEL` and distinct render layers for world body, viewmodel and shadow proxy.
2. `ControllableViewAdapter` already hides the world body from the first-person camera while keeping it visible in third person, and can expose a dedicated `get_first_person_viewmodel_root()`.
3. `EquipmentAwareFirstPersonAdapter` can refresh layer assignments after equipment visuals are added or removed.
4. `QuaterniusCharacterLab` already owns first/third cameras and `C` toggling; no replacement controller is necessary.
5. Character equipment layouts already contain `equipment.handheld`, `hand.left`, `hand.right` channels/anchors.
6. `SelectiveGarmentSceneFactory` can isolate `Male_Peasant_Arms` from the existing clothing asset.
7. `SkinnedGarmentPoseBridge` can copy the accepted world skeleton pose into a separate skinned garment instance without moving gameplay state.
8. CH9.6 already projects server-authoritative Item Graph/equipment state into the local character presentation.

This means `FirstPersonEmbodiment` is a presentation extension, not a new character controller.

## Implemented prototype architecture

```text
CharacterBody3D                         EXISTING / gameplay owner
├── AvatarPresentation                 EXISTING / world body + clothing
├── CH7EquipmentAwareFirstPersonAdapter EXISTING
├── CameraYaw / CameraPitch            EXISTING
│   ├── FirstPersonCamera              EXISTING
│   │   ├── FirstPersonViewmodelRoot   NEW / presentation-only
│   │   │   ├── LeftHandViewmodel
│   │   │   │   └── LeftGrip
│   │   │   ├── RightHandViewmodel
│   │   │   │   └── RightGrip
│   │   │   └── optional Quaternius sleeves
│   │   └── FirstPersonInteractionRay
│   └── ThirdPersonCamera              EXISTING
└── FirstPersonEmbodiment              NEW / presentation coordinator
    └── FirstPersonEmbodimentPresentationProxy

CH9.6 network Item Graph
        ↓ canonical/replica state only
NetworkCharacterEquipmentGameplayController
        ↓
AvatarPresentation + equipment presenter
        ↓ read-only mirror
FirstPersonEmbodiment

Local grab input
        ↓
FirstPersonGrabAuthorityBridge
        ├── local sandbox object -> local prototype grab
        └── canonical item -> FAIL CLOSED until hand.grab contract exists
```

## Implemented files

- `scripts/characters/presentation/first_person_embodiment_presentation_proxy.gd`
- `scripts/characters/presentation/first_person_embodiment.gd`
- `scripts/characters/interaction/first_person_grab_authority_bridge.gd`
- `scripts/characters/lab/quaternius_first_person_embodiment_lab.gd`
- `scenes/labs/character/quaternius_first_person_embodiment_lab.tscn`
- `tests/characters/test_first_person_embodiment_contract.gd`
- `RUN_FPE_RESEARCH_TESTS.ps1`
- `PLAY_FPE_RESEARCH.ps1`

No accepted CH9.6 file is modified.

## Prototype behavior

### First-person body

The existing first-person adapter is rebound through a presentation proxy:

- `world_visual_root` resolves to the normal Quaternius avatar and equipped clothes;
- `viewmodel_visual_root` resolves to the camera-local hand rig;
- profile policy becomes `VIEWMODEL` only in this research scene;
- world avatar animation continues running;
- first-person camera does not render the world body;
- third-person camera still renders the normal character and clothing;
- existing shadow proxy policy remains available.

### Hands

The first cut provides two independent camera-local hands with independent grip roots:

- `Q` — left hand grab/release;
- `E` — right hand grab/release.

Procedural palms/forearms are deliberately simple. They prove geometry, render-layer isolation, hand independence, sway, bob and item attachment without importing a foreign FPS skeleton.

### Clothing

When the authoritative equipment snapshot contains the accepted Peasant upper-body profile:

1. the FPE reads the already projected equipment snapshot;
2. it attempts to build a viewmodel-only scene containing `Male_Peasant_Arms` using `SelectiveGarmentSceneFactory`;
3. it binds that garment to the accepted world pose skeleton with `SkinnedGarmentPoseBridge`;
4. if the real skinned sleeve path cannot initialize, it falls back to procedural sleeves instead of breaking the character or equipment presentation.

The first-person layer never equips or unequips clothes itself.

### Network-selected hand item

The research lab mirrors `get_selected_hotbar_item_id()` from the CH9.6 replica into a presentation-only object in the right grip. Keys `1..0` use the existing network hotbar selection route.

The temporary held mesh is intentionally generic. It proves the ownership flow:

```text
server Item Graph -> client replica -> selected hotbar item -> hand presentation
```

A future item presentation catalog should replace the generic box with the item's actual viewmodel scene.

### Local grab sandbox

Three floating `RigidBody3D` cubes are spawned by the research lab. They have explicit metadata `fpe_local_sandbox_grabbable=true` and are not Item Graph items. They exist only to test independent left/right grabbing immediately.

This local sandbox is not presented as multiplayer authority.

## Why canonical world grabbing is intentionally fail-closed

The accepted CH9/NX stack does not currently expose an accepted `hand.grab` ownership command for arbitrary world physics items. Making the camera script directly reparent a replicated rigid body would create a second authority system and invalidate network/persistence assumptions.

Therefore a target with `item_id` / `canonical_item_id` is rejected with:

`FPE_CANONICAL_GRAB_AUTHORITY_UNAVAILABLE`

until the server contract below is implemented in a separately authorized frontier.

## Proposed canonical hand-grab contract

### Request

```text
hand.grab
player_entity_id
hand_id                  left | right
item_id
expected_item_revision
client_tick
hit_position_world
hit_normal_world
grip_profile_id          optional
```

### Server validation

The server must validate at minimum:

- player owns the requesting session;
- item exists and is in a world/allowed relation;
- expected revision still matches;
- item is within maximum hand interaction distance;
- server-side line-of-sight / reach check passes;
- item is not already exclusively claimed by another hand/player;
- mass/size/profile allows this interaction mode;
- requested grip profile is valid for the item;
- authoritative physics zone is able to transfer or retain ownership safely.

### Accepted canonical state

The server should replicate a durable semantic hand attachment, not the client camera transform:

```text
HandAttachmentState
player_entity_id
hand_id
item_id
grip_profile_id
authority_epoch
revision
physics_owner_zone
```

The local viewmodel and remote world-body hand presentation are projections of this state.

### Release

```text
hand.release
player_entity_id
hand_id
item_id
expected_attachment_revision
release_linear_velocity
release_angular_velocity
client_tick
```

Release velocities may be client hints, but the server validates/clamps them before applying authoritative physics.

### Two-hand extension

A later `GripClaim` should allow one canonical item to contain multiple hand claims:

```text
item_id
primary_hand_claim
secondary_hand_claim
```

This supports crates, rifles, drills, ladders and cooperative two-player carrying without representing a two-hand object as two inventory items.

## Grip presentation profile

Do not copy weapon gameplay statistics into viewmodel resources. Add a presentation-only profile later:

```text
GripPresentationProfile
profile_id
primary_hand
primary_local_transform
secondary_hand
secondary_local_transform
hand_pose_id
camera_sway_profile_id
viewmodel_scene_id
world_grip_anchor_id
max_visual_lag_m
```

Item definitions may reference this presentation profile, while canonical item identity/state remains in Item Graph.

## Recommended next slices

### FPE-R1 — current prototype

- VIEWMODEL layer integration;
- two visible hands;
- camera-local sway/bob;
- independent hand roots;
- network-selected hotbar presentation;
- clothing sleeve projection;
- local sandbox grab;
- fail-closed canonical grab authority bridge.

### FPE-R2 — actual hand rig

- replace procedural palms with a reusable arm/hand skeleton;
- create hand-pose library;
- map bare skin + gloves + sleeves to viewmodel meshes;
- add IK targets for each grip;
- keep world skeleton as the remote/third-person presentation.

### FPE-R3 — item viewmodel catalog

- add item-specific first-person scenes;
- add `GripPresentationProfile`;
- support flashlight, drill, construction tool, box and weapon examples;
- add secondary-hand support.

### FPE-R4 — authorized network grab

Only after central control opens the required network/Character frontier:

- add canonical `hand.grab` / `hand.release` commands;
- server reach/LOS/revision validation;
- hand attachment state replication;
- prediction journal entry for visual hand acquisition;
- rejection rollback;
- physics ownership transfer policy.

### FPE-R5 — high-quality rendering

Only if the existing render-layer solution proves insufficient:

- independent SubViewport camera;
- separate viewmodel FOV;
- viewmodel-only post-processing;
- clipping/depth handling;
- optional arms-only shadow policy.

## Run

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git fetch origin
git switch research/first-person-embodiment-prototype
git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_FPE_RESEARCH_TESTS.ps1 -GodotPath $Godot
.\PLAY_FPE_RESEARCH.ps1 -GodotPath $Godot -ResetState
```

Controls in the graphical lab:

- `WASD` — movement;
- `Shift` — run;
- `Ctrl` — crouch;
- `Space` — jump;
- mouse — look;
- `C` — first/third person;
- `Q` — left hand grab/release;
- `E` — right hand grab/release;
- `1..0` — existing network hotbar selection;
- `Tab` — existing inventory/equipment UI.

Manual checks:

1. Start in first person and confirm both hands render while the Quaternius world body does not clip through the camera.
2. Press `C`: third person must show the original full character; first-person hands must disappear.
3. Aim at a floating cube and press `Q` or `E`; the corresponding hand must hold it independently.
4. Select different hotbar slots with `1..0`; the right-hand canonical presentation proxy must follow the network replica selection.
5. Open inventory and equip the Peasant upper item; after network convergence the first-person sleeve mode should become `REAL_QUATERNIUS` when the pose bridge succeeds, otherwise `PROCEDURAL` fallback.
6. Third-person clothing must remain correct throughout; FPE must never alter equipment ownership.
7. A real Item Graph world object with canonical item metadata must not be locally stolen by the FPS script; until the server contract exists it must fail closed.

## Merge policy

This branch is deliberately not a merge candidate yet. A useful successful result is evidence for the next centrally authorized Character/network frontier, not permission to mutate the accepted CH9.6 checkpoint.
