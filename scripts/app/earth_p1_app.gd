extends "res://scripts/app/earth_mvp_app.gd"

# V0-P1 keeps M3/NX4 movement and M4 Item Graph authority unchanged. This
# runtime only projects canonical WORLD item records into the moving Earth
# render frame and routes interaction back through the existing M4 command path.

const CanonicalWorldItemRuntimeScript = preload(
	"res://scripts/runtime/networked_gameplay/i2s/canonical_world_item_runtime.gd"
)
const EarthItemSpatialProjectorScript = preload(
	"res://scripts/runtime/networked_gameplay/i2s/earth_item_spatial_projector.gd"
)

const I2S_INTERACTION_RANGE_M := 5.0
const I2S_FOCUS_DOT_MIN := 0.94
const I2S_INTERACTION_COLLISION_LAYER := 1 << 19

var _i2s_world_runtime
var _i2s_spatial_projector
var _i2s_focus_target
var _i2s_prompt_layer: CanvasLayer
var _i2s_prompt_root: Control
var _i2s_prompt_label: Label
var _i2s_setup_error := ""
var _i2s_sync_rejections := 0
var _i2s_interactions := 0
var _i2s_interaction_rejections := 0
var _i2s_spatial_refresh_failures := 0


func attach_m3_multiplayer_client(runtime) -> Dictionary:
	var result: Dictionary = super.attach_m3_multiplayer_client(runtime)
	if not bool(result.get("success", false)):
		return result
	var i2s_setup := _ensure_i2s_runtime(runtime)
	if not bool(i2s_setup.get("success", false)):
		return i2s_setup
	var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
	details["v0_p1_world_items"] = true
	details["i2s_presentation_count"] = (
		_i2s_world_runtime.get_presentation_item_ids().size()
		if _i2s_world_runtime != null
		else 0
	)
	result["details"] = details
	return result


func register_runtime_commands(registry, owner_id: String) -> void:
	super.register_runtime_commands(registry, owner_id)
	_register_command(registry, owner_id, {
		"id": "player.interact",
		"description": "Взаимодействовать с каноническим предметом или контейнером перед игроком.",
		"usage": "player.interact",
		"category": "player",
	}, Callable(self, "_command_i2s_player_interact"))
	_register_command(registry, owner_id, {
		"id": "container.close",
		"description": "Закрыть открытый канонический внешний контейнер.",
		"usage": "container.close",
		"category": "inventory",
	}, Callable(self, "_command_i2s_close_container"))
	_register_command(registry, owner_id, {
		"id": "world.items.status",
		"description": "Показать состояние V0-P1 world-item presentation.",
		"usage": "world.items.status",
		"category": "diagnostics",
	}, Callable(self, "_command_i2s_status"))


func _process(delta: float) -> void:
	super._process(delta)
	if _i2s_world_runtime == null or not is_instance_valid(_i2s_world_runtime):
		return
	# Earth updates render_origin in super._process(). Reproject afterwards so
	# presentation follows the floating frame without mutating canonical state.
	var refreshed: Dictionary = _i2s_world_runtime.refresh_spatial_projection()
	if not bool(refreshed.get("success", false)):
		_i2s_spatial_refresh_failures += 1
	_refresh_i2s_focus()


func _on_m4_item_graph_updated(snapshot: Dictionary) -> void:
	super._on_m4_item_graph_updated(snapshot)
	if _i2s_world_runtime == null or not is_instance_valid(_i2s_world_runtime):
		return
	var accepted: Dictionary = _i2s_world_runtime.accept_snapshot(snapshot)
	if not bool(accepted.get("success", false)):
		_i2s_sync_rejections += 1


func prepare_for_unload() -> void:
	_clear_i2s_focus()
	if _i2s_world_runtime != null and is_instance_valid(_i2s_world_runtime):
		_i2s_world_runtime.clear_presentations()
	super.prepare_for_unload()


func _ensure_i2s_runtime(runtime) -> Dictionary:
	if _i2s_world_runtime != null and is_instance_valid(_i2s_world_runtime):
		return {"success": true, "error_code": "", "details": {"reused": true}}
	if runtime == null or not runtime.has_method("get_local_player_id"):
		_i2s_setup_error = "V0_P1_NETWORK_RUNTIME_REQUIRED"
		return {"success": false, "error_code": _i2s_setup_error, "details": {}}
	if earth_world == null or earth_explorer == null:
		_i2s_setup_error = "V0_P1_EARTH_RUNTIME_REQUIRED"
		return {"success": false, "error_code": _i2s_setup_error, "details": {}}

	_i2s_spatial_projector = EarthItemSpatialProjectorScript.new()
	var projector_setup: Dictionary = _i2s_spatial_projector.setup(
		earth_world,
		_mvp_surface_anchor_direction
	)
	if not bool(projector_setup.get("success", false)):
		_i2s_setup_error = String(projector_setup.get("error_code", "V0_P1_PROJECTOR_SETUP_FAILED"))
		_i2s_spatial_projector = null
		return projector_setup

	_i2s_world_runtime = CanonicalWorldItemRuntimeScript.new()
	_i2s_world_runtime.name = "V0P1CanonicalWorldItems"
	add_child(_i2s_world_runtime)
	var setup_result: Dictionary = _i2s_world_runtime.setup(
		self,
		String(runtime.get_local_player_id()),
		Callable(self, "m4_execute_item_command"),
		_i2s_spatial_projector
	)
	if not bool(setup_result.get("success", false)):
		_i2s_setup_error = String(setup_result.get("error_code", "V0_P1_I2S_SETUP_FAILED"))
		_i2s_world_runtime.queue_free()
		_i2s_world_runtime = null
		_i2s_spatial_projector = null
		return setup_result
	_i2s_world_runtime.external_container_context_changed.connect(
		_on_i2s_external_container_context_changed
	)
	_ensure_i2s_prompt()
	var initial_sync: Dictionary = _i2s_world_runtime.accept_snapshot(_m4_item_graph_snapshot)
	if not bool(initial_sync.get("success", false)):
		_i2s_setup_error = String(initial_sync.get("error_code", "V0_P1_INITIAL_SYNC_FAILED"))
		return initial_sync
	_i2s_setup_error = ""
	return {
		"success": true,
		"error_code": "",
		"details": {
			"presentation_count": _i2s_world_runtime.get_presentation_item_ids().size(),
			"canonical_truth": "SERVER_M4_ITEM_GRAPH",
		},
	}


func _command_i2s_player_interact(_arguments: Array[String]) -> Dictionary:
	if _mvp_inventory_visible:
		return {"success": false, "output": "Закройте инвентарь перед взаимодействием"}
	if _i2s_world_runtime == null or not is_instance_valid(_i2s_world_runtime):
		return {"success": false, "output": "V0-P1 world items ещё не готовы"}
	var target = _resolve_i2s_focus_target()
	if target == null or not is_instance_valid(target):
		return {"success": false, "output": "Нет предмета или контейнера в зоне взаимодействия"}
	var descriptor: Dictionary = target.get_interaction_descriptor(earth_explorer)
	var result: Dictionary = target.interact(earth_explorer, {
		"source": "player.interact",
		"descriptor": descriptor.duplicate(true),
	})
	_i2s_interactions += 1
	if not bool(result.get("success", false)):
		_i2s_interaction_rejections += 1
		return _mvp_command_result(result, "")
	if String(descriptor.get("type", "")) == "external_container":
		_set_mvp_inventory_visible(true)
	var action_text := String(descriptor.get("prompt", "Взаимодействие"))
	return _mvp_command_result(result, "%s: %s" % [
		action_text,
		_display_name_for_definition(String(descriptor.get("definition_id", ""))),
	])


func _command_i2s_close_container(_arguments: Array[String]) -> Dictionary:
	if _i2s_world_runtime == null or not is_instance_valid(_i2s_world_runtime):
		return {"success": false, "output": "V0-P1 world items ещё не готовы"}
	var result: Dictionary = _i2s_world_runtime.close_external_container()
	return _mvp_command_result(result, "Контейнер закрыт")


func _command_i2s_status(_arguments: Array[String]) -> Dictionary:
	var report := create_m3_graphical_client_report()
	return {
		"success": true,
		"output": JSON.stringify(report.get("v0_p1", {}), "  "),
		"v0_p1": report.get("v0_p1", {}),
	}


func _on_i2s_external_container_context_changed(
	container_id: String,
	_screen: Dictionary
) -> void:
	# The existing M5 bridge independently derives the same external-container
	# identity from authoritative open_containers. P1 only opens its window.
	if not container_id.is_empty():
		_set_mvp_inventory_visible(true)


func _refresh_i2s_focus() -> void:
	if _mvp_inventory_visible or _mvp_spectator_enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_clear_i2s_focus()
		return
	_set_i2s_focus_target(_resolve_i2s_focus_target())


func _resolve_i2s_focus_target():
	if (
		_i2s_world_runtime == null
		or not is_instance_valid(_i2s_world_runtime)
		or earth_explorer == null
	):
		return null
	var camera := earth_explorer.get_camera() as Camera3D
	if camera == null:
		return null
	var origin := camera.global_position
	var forward := -camera.global_basis.z.normalized()
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + forward * I2S_INTERACTION_RANGE_M
	)
	query.collision_mask = I2S_INTERACTION_COLLISION_LAYER
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider = hit.get("collider")
		if (
			collider != null
			and is_instance_valid(collider)
			and collider.is_in_group(&"world_interactable")
		):
			return collider

	# Primitive MVP targets are intentionally small. A bounded aim-cone fallback
	# keeps interaction usable while the authoritative server still performs its
	# own range/ray validation before mutating Item Graph state.
	var best_target = null
	var best_score := -INF
	for item_id in _i2s_world_runtime.get_presentation_item_ids():
		var target = _i2s_world_runtime.get_presentation(item_id)
		if target == null or not is_instance_valid(target):
			continue
		var offset: Vector3 = target.global_position - origin
		var distance := offset.length()
		if distance <= 0.001 or distance > I2S_INTERACTION_RANGE_M:
			continue
		var alignment := forward.dot(offset / distance)
		if alignment < I2S_FOCUS_DOT_MIN:
			continue
		var score := alignment - distance * 0.002
		if score > best_score:
			best_score = score
			best_target = target
	return best_target


func _set_i2s_focus_target(target) -> void:
	if _i2s_focus_target == target:
		_update_i2s_prompt(target)
		return
	if _i2s_focus_target != null and is_instance_valid(_i2s_focus_target):
		_i2s_focus_target.set_interaction_focus(false)
	_i2s_focus_target = target
	if _i2s_focus_target != null and is_instance_valid(_i2s_focus_target):
		_i2s_focus_target.set_interaction_focus(true)
	_update_i2s_prompt(_i2s_focus_target)


func _clear_i2s_focus() -> void:
	_set_i2s_focus_target(null)


func _ensure_i2s_prompt() -> void:
	if _i2s_prompt_layer != null and is_instance_valid(_i2s_prompt_layer):
		return
	_i2s_prompt_layer = CanvasLayer.new()
	_i2s_prompt_layer.name = "V0P1InteractionPrompt"
	_i2s_prompt_layer.layer = 30
	add_child(_i2s_prompt_layer)
	_i2s_prompt_root = Control.new()
	_i2s_prompt_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_i2s_prompt_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_i2s_prompt_layer.add_child(_i2s_prompt_root)
	_i2s_prompt_label = Label.new()
	_i2s_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_i2s_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_i2s_prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_i2s_prompt_label.offset_left = -300.0
	_i2s_prompt_label.offset_right = 300.0
	_i2s_prompt_label.offset_top = -120.0
	_i2s_prompt_label.offset_bottom = -72.0
	_i2s_prompt_label.add_theme_font_size_override("font_size", 20)
	_i2s_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_i2s_prompt_label.visible = false
	_i2s_prompt_root.add_child(_i2s_prompt_label)


func _update_i2s_prompt(target) -> void:
	if _i2s_prompt_label == null:
		return
	if target == null or not is_instance_valid(target):
		_i2s_prompt_label.visible = false
		_i2s_prompt_label.text = ""
		return
	var descriptor: Dictionary = target.get_interaction_descriptor(earth_explorer)
	var prompt := String(descriptor.get("prompt", "Взаимодействовать"))
	var definition_name := _display_name_for_definition(
		String(descriptor.get("definition_id", ""))
	)
	var quantity := int(descriptor.get("quantity", 1))
	_i2s_prompt_label.text = "E — %s · %s%s" % [
		prompt,
		definition_name,
		" ×%d" % quantity if quantity > 1 else "",
	]
	_i2s_prompt_label.visible = true


func _display_name_for_definition(definition_id: String) -> String:
	match definition_id:
		"item/beacon":
			return "Маяк"
		"item/ore":
			return "Руда"
		"item/crate":
			return "Контейнер"
		"item/mount-base":
			return "Основание"
		_:
			return definition_id if not definition_id.is_empty() else "Предмет"


func create_m3_graphical_client_report() -> Dictionary:
	var report: Dictionary = super.create_m3_graphical_client_report()
	report["v0_p1"] = {
		"checkpoint": "V0-P1",
		"ready": _i2s_world_runtime != null and is_instance_valid(_i2s_world_runtime),
		"setup_error": _i2s_setup_error,
		"presentation_item_ids": (
			_i2s_world_runtime.get_presentation_item_ids()
			if _i2s_world_runtime != null and is_instance_valid(_i2s_world_runtime)
			else []
		),
		"runtime": (
			_i2s_world_runtime.get_report()
			if _i2s_world_runtime != null and is_instance_valid(_i2s_world_runtime)
			else {}
		),
		"sync_rejections": _i2s_sync_rejections,
		"interactions": _i2s_interactions,
		"interaction_rejections": _i2s_interaction_rejections,
		"spatial_refresh_failures": _i2s_spatial_refresh_failures,
		"canonical_truth": "SERVER_M4_ITEM_GRAPH",
		"mutation_owner": "DEDICATED_SERVER",
	}
	return report
