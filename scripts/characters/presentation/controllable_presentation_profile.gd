class_name ControllablePresentationProfile
extends Resource


enum FirstPersonPolicy {
	HIDE_WORLD_MODEL,
	SHOW_WORLD_MODEL,
	LEGACY_HEAD_MASK,
	VIEWMODEL,
}


@export var profile_id: StringName = &"generic"
@export var entity_kind: StringName = &"generic"
@export_enum("HIDE_WORLD_MODEL", "SHOW_WORLD_MODEL", "LEGACY_HEAD_MASK", "VIEWMODEL") var first_person_policy: int = FirstPersonPolicy.HIDE_WORLD_MODEL
@export_range(1, 20, 1) var world_render_layer_index := 20
@export_range(1, 20, 1) var viewmodel_render_layer_index := 19
@export var keep_world_animation_active := true
@export var allow_shadow_from_hidden_world_model := true


func world_render_layer_mask() -> int:
	return 1 << (clampi(world_render_layer_index, 1, 20) - 1)


func viewmodel_render_layer_mask() -> int:
	return 1 << (clampi(viewmodel_render_layer_index, 1, 20) - 1)


func policy_name() -> String:
	match first_person_policy:
		FirstPersonPolicy.HIDE_WORLD_MODEL:
			return "HIDE_WORLD_MODEL"
		FirstPersonPolicy.SHOW_WORLD_MODEL:
			return "SHOW_WORLD_MODEL"
		FirstPersonPolicy.LEGACY_HEAD_MASK:
			return "LEGACY_HEAD_MASK"
		FirstPersonPolicy.VIEWMODEL:
			return "VIEWMODEL"
		_:
			return "UNKNOWN"


func create_report() -> Dictionary:
	return {
		"schema": "planet_simulator.controllable_presentation_profile.v1",
		"profile_id": String(profile_id),
		"entity_kind": String(entity_kind),
		"first_person_policy": policy_name(),
		"world_render_layer_index": world_render_layer_index,
		"world_render_layer_mask": world_render_layer_mask(),
		"viewmodel_render_layer_index": viewmodel_render_layer_index,
		"viewmodel_render_layer_mask": viewmodel_render_layer_mask(),
		"keep_world_animation_active": keep_world_animation_active,
		"allow_shadow_from_hidden_world_model": allow_shadow_from_hidden_world_model,
	}
