# CH5 fix1 / CH6 — Controllable Entity Presentation

## Goal

CH5 proved that collapsing only the humanoid `Head` bone is not a robust first-person solution. The camera can still intersect the neck, chest, shoulders, hair, equipment, or any future geometry. CH5 fix1 therefore switches the default local first-person policy to camera-layer suppression: the controlled entity's world model keeps existing and updating, but the local first-person camera does not render it.

CH6 generalizes that solution so presentation is not coupled to a human body, Quaternius, a skeleton, or even an animated mesh. The same controlled-entity slot can later present a humanoid, drone, animal, cyborg, vehicle-like shell, or another avatar family.

## Separation of responsibilities

A controlled entity is composed from independent concerns:

- **Gameplay body / authority** — collision, authoritative transform, network identity, damage, inventory ownership and persistence.
- **Controller profile** — how input or AI intent becomes movement. A humanoid controller, flying drone controller, animal locomotion controller, EVA controller, etc. belong here.
- **Presentation profile** — what the entity looks like to cameras and which first-person policy it uses.
- **Presenter** — model/animation-specific code. Quaternius is only one presenter implementation.

No presentation adapter may call `Input`, `move_and_slide`, own a `CharacterBody3D`, or become authoritative for movement.

## New generic contract

`ControllablePresentationProfile` is a data resource. Important fields:

- `profile_id` — stable presentation profile identifier.
- `entity_kind` — descriptive family such as `humanoid`, `drone`, `animal`, `cyborg`.
- `first_person_policy` — rendering policy, independent from movement type.
- `world_render_layer_index` — dedicated world-model rendering layer.
- `viewmodel_render_layer_index` — reserved local first-person viewmodel layer.
- `keep_world_animation_active` — documents that first-person hiding must not stop the world presentation update loop.
- `allow_shadow_from_hidden_world_model` — the world model stays present so the normal world/light pipeline may keep its shadow contribution.

`ControllableViewAdapter` is model-agnostic. It recursively discovers `VisualInstance3D` nodes, moves them to the profile's dedicated world layer, removes that layer from the local first-person camera and keeps it enabled for the third-person/world camera.

The adapter contains no Quaternius, `Skeleton3D`, bone or head assumptions.

## Optional presenter methods

A future presenter can be plugged in through duck typing. None of these methods own gameplay state.

```gdscript
func get_world_visual_root() -> Node:
    return world_visual_root

func get_first_person_viewmodel_root() -> Node:
    return first_person_viewmodel_root # or null

func create_presentation_profile() -> Resource:
    return profile
```

If `get_world_visual_root()` is absent, the presenter node itself is treated as the world visual root. If `create_presentation_profile()` is absent, a generic profile is used. This keeps simple models cheap to integrate.

## First-person policies

### `HIDE_WORLD_MODEL`

Default CH5 fix1 policy. The world model remains visible globally and continues animation, but the local first-person camera excludes its render layer. This is the recommended policy for the current humanoid, drones and most future bodies until a dedicated FP viewmodel is worth the cost.

### `SHOW_WORLD_MODEL`

The local first-person camera renders the world model. This is available for unusual entities where camera/body intersection cannot happen, for example some cockpit-like or remote camera bodies.

### `LEGACY_HEAD_MASK`

Compatibility mode retained by `FullBodyFirstPersonAdapter`. It keeps the old Quaternius head-bone/fallback-head masking behavior for regression coverage. It is not the recommended production policy.

### `VIEWMODEL`

Reserved forward path. The world model is hidden from the first-person camera and a separate viewmodel layer is enabled. This is where dedicated hands, weapons, tools, manipulator arms, drone HUD geometry, etc. can be connected later without changing the controlled-entity contract.

## Humanoid example

The CH5/CH6 lab uses:

```text
controller archetype: humanoid walking/running
presenter: QuaterniusAvatarPresenter
presentation profile: quaternius_humanoid
entity kind: humanoid
FP policy: HIDE_WORLD_MODEL
```

The Quaternius world model remains animated in first person. Only the local FP camera stops rendering it. Third person sees the complete body.

## Drone example

The CH6 fixture intentionally has no skeleton and no head:

```text
controller archetype: future flying/drone controller
presenter: drone presenter
presentation profile: test_drone
entity kind: drone
FP policy: HIDE_WORLD_MODEL
```

The same `ControllableViewAdapter` discovers the drone body and four rotor meshes and applies the same local-camera suppression. This proves that first-person presentation is not tied to humanoid anatomy.

A future production drone needs only:

1. a drone movement/controller profile;
2. a drone presenter scene/script;
3. a `ControllablePresentationProfile`;
4. optional `get_world_visual_root()` / `get_first_person_viewmodel_root()` methods.

Network identity, inventory ownership and authority can remain attached to the controlled gameplay entity instead of to a specific human mesh.

## Render-layer rule

CH6 defaults to render layer 20 for the controlled world presentation and reserves layer 19 for a future first-person viewmodel. These are profile fields, not hard-coded architectural constants. Production integration should reserve/document the chosen layers centrally before multiple camera systems depend on them.

The adapter stores original `VisualInstance3D.layers` and camera `cull_mask` values and restores them when unbound.

## Acceptance criteria

CH5 fix1 is accepted when the real Quaternius graphical lab shows no own chest/head/shoulder geometry in first person, while third person still shows the complete animated character. Root motion remains disabled.

CH6 candidate is accepted when the generic adapter test passes for the non-humanoid drone fixture, proving there are no skeleton/head/Quaternius dependencies, and the CH4/CH5 regressions remain green.

## Deferred work

This stage does not integrate the new presentation host into production `LunarPlayer` yet. That should be a separate small integration stage after the graphical lab is accepted, so network prediction, inventory and current merge stabilization remain isolated from presentation experiments.

Directional locomotion, dedicated first-person hands/weapons, drone flight control and animal locomotion are separate future stages. The CH6 contract is designed so those additions do not require another rewrite of first-person visibility.
