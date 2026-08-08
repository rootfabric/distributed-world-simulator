# CH5 fix1 / CH6 — Controllable Entity Presentation

## Goal

CH5 proved that collapsing only the humanoid `Head` bone is not a robust first-person solution. The camera can still intersect the neck, chest, shoulders, hair, equipment, or any future geometry. CH5 fix1 therefore switches the default local first-person policy to camera-layer suppression: the controlled entity's world model keeps existing and updating, but the local first-person camera does not render it.

CH6 generalizes that solution so presentation is not coupled to a human body, Quaternius, a skeleton, or even an animated mesh. The same controlled-entity slot can later present a humanoid, drone, animal, cyborg, vehicle-like shell, or another avatar family.

CH6 fix1 adds **Shadow Preservation**. Hiding the world model from the local first-person camera must not make the controlled entity lose its world shadow.

## Separation of responsibilities

A controlled entity is composed from independent concerns:

- **Gameplay body / authority** — collision, authoritative transform, network identity, damage, inventory ownership and persistence.
- **Controller profile** — how input or AI intent becomes movement. A humanoid controller, flying drone controller, animal locomotion controller, EVA controller, etc. belong here.
- **Presentation profile** — what the entity looks like to cameras and which first-person/shadow policy it uses.
- **Presenter** — model/animation-specific code. Quaternius is only one presenter implementation.

No presentation adapter may call `Input`, `move_and_slide`, own a `CharacterBody3D`, or become authoritative for movement.

## Generic presentation profile

`ControllablePresentationProfile` is a data resource. Important fields:

- `profile_id` — stable presentation profile identifier.
- `entity_kind` — descriptive family such as `humanoid`, `drone`, `animal`, `cyborg`.
- `first_person_policy` — rendering policy, independent from movement type.
- `first_person_shadow_policy` — how first-person shadow preservation is provided.
- `world_render_layer_index` — dedicated world-model rendering layer.
- `viewmodel_render_layer_index` — reserved local first-person viewmodel layer.
- `shadow_render_layer_index` — dedicated shadow-only proxy layer.
- `keep_world_animation_active` — first-person hiding must not stop the world presentation update loop.
- `allow_shadow_from_hidden_world_model` — compatibility/feature switch for shadow preservation.

Default CH6 fix1 layer allocation is:

```text
20 — world model
19 — optional first-person viewmodel
18 — first-person shadow-only proxy
```

The three layers must remain distinct while shadow preservation is enabled. They are profile fields rather than anatomy- or Quaternius-specific constants.

## ControllableViewAdapter

`ControllableViewAdapter` remains model-agnostic. It recursively discovers `VisualInstance3D` nodes, moves them to the profile's dedicated world layer, removes that layer from the local first-person camera and keeps it enabled for the third-person/world camera.

For shadow preservation it owns a separate `ControllableShadowProxy` presentation component. The adapter itself still contains no Quaternius, `Skeleton3D`, bone or head assumptions.

## First-person policies

### `HIDE_WORLD_MODEL`

Default policy. The world model remains alive and animated but the local first-person camera excludes its render layer. This is recommended for the current humanoid, drones and most future controlled bodies.

### `SHOW_WORLD_MODEL`

The local first-person camera renders the world model. Useful for entities where camera/body intersection cannot happen.

### `LEGACY_HEAD_MASK`

Compatibility mode retained by `FullBodyFirstPersonAdapter`. It keeps the old Quaternius head-bone/fallback-head behavior for regression coverage only.

### `VIEWMODEL`

The world model is hidden from the first-person camera and a separate viewmodel layer is enabled. Dedicated hands, weapons, tools, manipulator arms or vehicle-specific first-person geometry can be added here later.

## Shadow policies

### `NONE`

No first-person shadow proxy is created. Use this for entities that intentionally should not cast their own local first-person shadow.

### `WORLD_PROXY`

Default CH6 fix1 path.

The adapter finds shadow-casting `MeshInstance3D` nodes under the world visual root and creates lightweight shadow-only counterparts. Each generated proxy:

- reuses the exact same `Mesh` resource rather than duplicating geometry;
- reuses the source `Skin` resource when present;
- resolves and binds the same `Skeleton3D` when the source mesh is skinned;
- copies material overrides needed for the same silhouette/cutout behavior;
- tracks the source mesh `global_transform`, so transform-driven drone rotors or other articulated parts are supported without requiring a skeleton;
- uses `GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY`;
- lives on the dedicated shadow layer;
- is active only while the locally controlled camera is in a first-person policy that hides the world body.

The proxy therefore contributes to shadow rendering without becoming visible geometry in the first-person image.

This is intentionally a presentation-only duplicate. Collision, network identity, physics, inventory ownership, root motion and movement authority are never duplicated.

### `CUSTOM_PROXY`

Escape hatch for unusual presenters that should supply their own shadow geometry: procedural bodies, highly complex vehicles, MultiMesh-based entities, special LOD silhouettes, etc.

A presenter may expose:

```gdscript
func get_first_person_shadow_proxy_root() -> Node:
    return first_person_shadow_proxy_root
```

The custom root must be separate from the normal world visual root. The adapter places its `GeometryInstance3D` nodes on the shadow layer, switches them to `SHADOWS_ONLY`, activates them only in first person and restores their original state on unbind.

## Optional presenter methods

A future presenter can be plugged in through duck typing. None of these methods own gameplay state.

```gdscript
func get_world_visual_root() -> Node:
    return world_visual_root

func get_first_person_viewmodel_root() -> Node:
    return first_person_viewmodel_root # or null

func get_first_person_shadow_proxy_root() -> Node:
    return custom_shadow_proxy_root # optional, for CUSTOM_PROXY only

func create_presentation_profile() -> Resource:
    return profile
```

If `get_world_visual_root()` is absent, the presenter node itself is treated as the world visual root. If `create_presentation_profile()` is absent, a generic profile is used. This keeps simple models cheap to integrate.

## Humanoid example

The CH5/CH6 lab uses:

```text
controller archetype: humanoid walking/running
presenter: QuaterniusAvatarPresenter
presentation profile: quaternius_humanoid
entity kind: humanoid
FP policy: HIDE_WORLD_MODEL
shadow policy: WORLD_PROXY
```

The Quaternius world model remains animated in first person, but the local FP camera does not render it. The generated shadow-only skinned mesh uses the same Skeleton3D pose, so the floor/world should still receive the animated character shadow.

## Drone example

The CH6 fixture intentionally has no skeleton and no head:

```text
controller archetype: future flying/drone controller
presenter: drone presenter
presentation profile: test_drone
entity kind: drone
FP policy: HIDE_WORLD_MODEL
shadow policy: WORLD_PROXY
```

The same adapter discovers the body plus four rotor meshes. Five shadow proxies reuse those five Mesh resources and follow source transforms. No humanoid anatomy is required.

A future production drone needs only:

1. a drone movement/controller profile;
2. a drone presenter scene/script;
3. a `ControllablePresentationProfile`;
4. optional world/viewmodel/custom-shadow presenter methods.

Network identity, inventory ownership and authority remain attached to the controlled gameplay entity instead of to a specific human mesh.

## Runtime cost

`WORLD_PROXY` is intentionally limited to the locally controlled first-person presentation. The original mesh resources and skeleton are shared; no second animation graph and no second physics body are created. The main extra cost is an additional shadow draw for the local controlled entity while first person is active.

Third person disables the generated shadow proxy and returns to the normal world-model shadow path.

## Restore contract

The adapter stores original world/viewmodel render layers and camera cull masks and restores them when unbound. `CUSTOM_PROXY` additionally restores its original visibility, layer and `cast_shadow` state. Generated `WORLD_PROXY` nodes are destroyed on unbind/rebind.

## Acceptance criteria

CH6 fix1 is accepted when all of the following are true:

- CH4/CH5 presentation regressions remain green;
- generic non-humanoid drone test passes without Quaternius or Skeleton3D assumptions in `ControllableViewAdapter`;
- each shadow-casting drone MeshInstance3D receives one `SHADOWS_ONLY` proxy using the same Mesh resource;
- proxy layer is separate from world and viewmodel layers;
- proxy is inactive in third person and active in first person;
- real Quaternius creates at least one skinned proxy bound to its animated Skeleton3D;
- graphical first-person view contains no own body geometry but the animated body shadow remains visible on the floor/world;
- third person still shows the complete animated body and normal shadow;
- repeated first/third-person switching does not leave duplicate shadows or visible proxy geometry;
- root motion remains disabled.

## Deferred work

This stage still does not integrate the presentation host into production `LunarPlayer`. That remains a separate integration stage after graphical acceptance so network prediction, inventory and current merge stabilization stay isolated from presentation work.

Dedicated first-person hands/weapons, drone flight control, animal locomotion, shadow LODs and special procedural shadow proxies are future stages. The CH6 contract is designed so these additions do not require another rewrite of first-person visibility.
