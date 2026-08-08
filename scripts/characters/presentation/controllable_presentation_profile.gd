class_name ControllablePresentationProfile
extends Resource


enum FirstPersonPolicy {
	HIDE_WORLD_MODEL,
	SHOW_WORLD_MODEL,
	LEGACY_HEAD_MASK,
	VIEWMODEL,
}


enum FirstPersonShadowPolicy {
	NONE,
	WORLD_PROXY,
	CUSTOM_PROXY,
}


@export var profile_id: StringName = &"generic"
@export var entity_kind: StringName = &"generic"
@export_enum("HIDE_WORLD_MODEL", "SHOW_WORLD_MODEL", "LEGACY_HEAD_MASK", "VIEWMODEL") var first_person_policy: int = FirstPersonPolicy.HIDE_WORLD_MODEL
@export_enum("NONE", "WORLD_PROXY", "CUSTOM_PROXY") var first_person_shadow_policy: int = FirstPersonShadowPolicy.WORLD_PROXY
@export_range(1, 20, 1) var world_render_layer_index := 20
@export_range(1, 20, 1) var viewmodel_render_layer_index := 19
@export_range(1, 20, 1) var shadow_render_layer_index := 18
@export var keep_world_animation_active := true
@export var allow_shadow_from_hidden_world_model := true


func world_render_layer_mask() -> int:
	return 1 << (clampi(world_render_layer_index, 1, 20) - 1)


func viewmodel_render_layer_mask() -> int:
	return 1 << (clampi(viewmodel_render_layer_index, 1, 20) - 1)


func shadow_render_layer_mask() -> int:
	return 1 << (clampi(shadow_render_layer_index, 1, 20) - 1)


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


func shadow_policy_name() -> String:
	match first_person_shadow_policy:
		FirstPersonShadowPolicy.NONE:
			return "NONE"
		FirstPersonShadowPolicy.WORLD_PROXY:
			return "WORLD_PROXY"
		FirstPersonShadowPolicy.CUSTOM_PROXY:
			return "CUSTOM_PROXY"
		_:
			return "UNKNOWN"


func shadow_preservation_enabled() -> bool:
	return (
		allow_shadow_from_hidden_world_model
		and first_person_shadow_policy != FirstPersonShadowPolicy.NONE
	)


func render_layers_are_distinct() -> bool:
	var world_mask := world_render_layer_mask()
	var viewmodel_mask := viewmodel_render_layer_mask()
	if world_mask == viewmodel_mask:
		return false
	if not shadow_preservation_enabled():
		return true
	var shadow_mask := shadow_render_layer_mask()
	return shadow_mask != world_mask and shadow_mask != viewmodel_mask


func create_report() -> Dictionary:
	return {
		"schema": "planet_simulator.controllable_presentation_profile.v2",
		"profile_id": String(profile_id),
		"entity_kind": String(entity_kind),
		"first_person_policy": policy_name(),
		"first_person_shadow_policy": shadow_policy_name(),
		"world_render_layer_index": world_render_layer_index,
		"world_render_layer_mask": world_render_layer_mask(),
		"viewmodel_render_layer_index": viewmodel_render_layer_index,
		"viewmodel_render_layer_mask": viewmodel_render_layer_mask(),
		"shadow_render_layer_index": shadow_render_layer_index,
		"shadow_render_layer_mask": shadow_render_layer_mask(),
		"keep_world_animation_active": keep_world_animation_active,
		"allow_shadow_from_hidden_world_model": allow_shadow_from_hidden_world_model,
		"shadow_preservation_enabled": shadow_preservation_enabled(),
		"render_layers_distinct": render_layers_are_distinct(),
	}
