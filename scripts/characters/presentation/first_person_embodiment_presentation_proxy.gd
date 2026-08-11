class_name FirstPersonEmbodimentPresentationProxy
extends Node

var world_presentation: Node
var viewmodel_root: Node3D
var custom_shadow_proxy_root: Node


func setup(
	p_world_presentation: Node,
	p_viewmodel_root: Node3D,
	p_custom_shadow_proxy_root: Node = null
) -> Dictionary:
	if p_world_presentation == null:
		return _failure("FPE_WORLD_PRESENTATION_REQUIRED")
	if p_viewmodel_root == null:
		return _failure("FPE_VIEWMODEL_ROOT_REQUIRED")
	world_presentation = p_world_presentation
	viewmodel_root = p_viewmodel_root
	custom_shadow_proxy_root = p_custom_shadow_proxy_root
	return _success(create_report())


func get_world_visual_root() -> Node:
	if world_presentation == null:
		return null
	if world_presentation.has_method("get_world_visual_root"):
		var candidate = world_presentation.call("get_world_visual_root")
		if candidate is Node:
			return candidate
	return world_presentation


func get_first_person_viewmodel_root() -> Node:
	return viewmodel_root if viewmodel_root != null and is_instance_valid(viewmodel_root) else null


func get_first_person_shadow_proxy_root() -> Node:
	if custom_shadow_proxy_root != null and is_instance_valid(custom_shadow_proxy_root):
		return custom_shadow_proxy_root
	if world_presentation != null and world_presentation.has_method("get_first_person_shadow_proxy_root"):
		var candidate = world_presentation.call("get_first_person_shadow_proxy_root")
		if candidate is Node:
			return candidate
	return null


func create_report() -> Dictionary:
	return {
		"schema": "planet_simulator.first_person_embodiment_presentation_proxy.v1",
		"world_presentation_bound": world_presentation != null,
		"world_visual_root_present": get_world_visual_root() != null,
		"viewmodel_root_present": get_first_person_viewmodel_root() != null,
		"custom_shadow_proxy_present": get_first_person_shadow_proxy_root() != null,
		"moves_gameplay_body": false,
		"reads_input": false,
		"owns_network_state": false,
		"owns_item_state": false,
	}


func _success(details: Dictionary = {}) -> Dictionary:
	return {
		"success": true,
		"error_code": "",
		"details": details.duplicate(true),
	}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"details": details.duplicate(true),
	}
