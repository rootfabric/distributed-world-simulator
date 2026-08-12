class_name QuaterniusFirstPersonEmbodimentLab
extends Node3D

const FirstPersonEmbodimentType = preload("res://scripts/characters/presentation/first_person_embodiment.gd")
const GrabAuthorityBridgeType = preload("res://scripts/characters/interaction/first_person_grab_authority_bridge.gd")
const HotbarNetworkAdapterType = preload("res://scripts/characters/interaction/first_person_hotbar_network_adapter.gd")
const UPPER_PROFILE_ID := "equipment.layer.upper.peasant"
const LOGICAL_PLAYER_ID := "a"
const PERF_HUD_INTERVAL_MS := 1000

var base_lab
var first_person_embodiment
var grab_authority_bridge
var hotbar_network_adapter
var fpe_setup_result: Dictionary = {}
var fpe_status_label: Label
var _last_hotbar_item_id := ""
var _last_equipment_fingerprint := ""
var _last_upper_clothing_enabled := false
var _last_fpe_status_code := ""
var _hotbar_prediction_index := -1
var _sandbox_targets: Array[RigidBody3D] = []

# FPE presentation is derived from canonical state. It does not need to rebuild
# Item Graph equipment every render frame. Canonical network projection marks
# these lanes dirty and the next process frame consumes each lane once.
var _network_projection_signal_bound := false
var _equipment_sync_dirty := true
var _hotbar_presentation_dirty := true
var _equipment_sync_runs := 0
var _hotbar_sync_runs := 0

# Lightweight local instrumentation. This measures only the FPE composition
# process cost; inherited CH9.6 diagnostic cost is reported by the research host.
var _perf_window_frames := 0
var _perf_window_total_us := 0
var _perf_window_max_us := 0
var _perf_last_average_us := 0.0
var _perf_last_max_us := 0
var _perf_last_publish_ms := 0


func _ready() -> void:
	base_lab = get_node_or_null("CH9_6BaseLab")
	_build_status_overlay()
	if base_lab == null:
		fpe_setup_result = _failure("FPE_BASE_CH9_6_LAB_REQUIRED")
		_refresh_status()
		return
	_setup_first_person_embodiment()
	_spawn_local_grab_sandbox()
	if base_lab.has_method("set_first_person_mode"):
		base_lab.call("set_first_person_mode", true)
	_refresh_status()


func _process(_delta: float) -> void:
	var started_us := Time.get_ticks_usec()
	if first_person_embodiment == null or base_lab == null:
		_record_process_cost(started_us)
		return
	if base_lab.character_gameplay_controller == null:
		_record_process_cost(started_us)
		return

	_ensure_hotbar_network_adapter()
	_bind_network_projection_signal()
	_poll_hotbar_authority()

	if _hotbar_presentation_dirty:
		_hotbar_presentation_dirty = false
		_sync_authoritative_hotbar_presentation()
	if _equipment_sync_dirty:
		_equipment_sync_dirty = false
		_sync_equipment_viewmodel()

	_record_process_cost(started_us)
	_publish_performance_window_if_due()


func _unhandled_input(event: InputEvent) -> void:
	if base_lab == null:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if base_lab.character_gameplay_controller == null or base_lab.character_gameplay_controller.inventory_open:
		return
	var hotbar_index: int = _hotbar_index_for_key(event.physical_keycode)
	if hotbar_index < 0:
		return
	var result: Dictionary = _select_hotbar_nonblocking(hotbar_index)
	_last_fpe_status_code = String(result.get("error_code", result.get("code", "OK")))
	_refresh_status()
	get_viewport().set_input_as_handled()


func _setup_first_person_embodiment() -> void:
	if (
		base_lab.player == null
		or base_lab.avatar == null
		or base_lab.first_person_adapter == null
		or base_lab.presentation_profile == null
		or base_lab.first_person_camera == null
	):
		fpe_setup_result = _failure("FPE_BASE_PRESENTATION_NOT_READY")
		return

	grab_authority_bridge = GrabAuthorityBridgeType.new()
	# CH9.6 has canonical network item/equipment authority but no accepted
	# hand.grab world-physics command. Canonical targets therefore fail closed;
	# local sandbox bodies remain available for testing hand UX.
	grab_authority_bridge.setup(Callable(), true)

	var source_skeleton: Skeleton3D = null
	if base_lab.layered_rig_adapter != null and base_lab.layered_rig_adapter.has_method("resolve_pose_skeleton"):
		var skeleton_value: Variant = base_lab.layered_rig_adapter.call("resolve_pose_skeleton", base_lab.avatar)
		if skeleton_value is Skeleton3D:
			source_skeleton = skeleton_value as Skeleton3D

	first_person_embodiment = FirstPersonEmbodimentType.new()
	first_person_embodiment.name = "FirstPersonEmbodiment"
	base_lab.player.add_child(first_person_embodiment)
	fpe_setup_result = first_person_embodiment.setup(
		base_lab.player,
		base_lab.avatar,
		base_lab.first_person_adapter,
		base_lab.presentation_profile,
		base_lab.first_person_camera,
		base_lab.third_person_camera,
		grab_authority_bridge,
		source_skeleton
	)
	if not bool(fpe_setup_result.get("success", false)):
		push_error("FPE prototype setup failed: %s" % JSON.stringify(fpe_setup_result))
		return
	if first_person_embodiment.interaction_raycast != null:
		first_person_embodiment.interaction_raycast.add_exception(base_lab.player)
	first_person_embodiment.interaction_result_changed.connect(_on_fpe_interaction_result_changed)
	first_person_embodiment.grab_state_changed.connect(_on_fpe_grab_state_changed)


func _ensure_hotbar_network_adapter() -> bool:
	if hotbar_network_adapter != null:
		return true
	if base_lab == null or not bool(base_lab.network_ready) or base_lab.network_client == null:
		return false
	var candidate = HotbarNetworkAdapterType.new()
	var setup_result: Dictionary = candidate.setup(base_lab.network_client, LOGICAL_PLAYER_ID)
	if not bool(setup_result.get("success", false)):
		_last_fpe_status_code = String(setup_result.get("error_code", "FPE_HOTBAR_ADAPTER_SETUP_FAILED"))
		return false
	hotbar_network_adapter = candidate
	_hotbar_presentation_dirty = true
	return true


func _bind_network_projection_signal() -> void:
	if _network_projection_signal_bound or base_lab == null or base_lab.network_bridge == null:
		return
	if not base_lab.network_bridge.has_signal("projected_item_graph_updated"):
		return
	var callback := Callable(self, "_on_base_projected_item_graph_updated")
	if not base_lab.network_bridge.is_connected("projected_item_graph_updated", callback):
		base_lab.network_bridge.connect("projected_item_graph_updated", callback)
	_network_projection_signal_bound = true
	_equipment_sync_dirty = true
	_hotbar_presentation_dirty = true


func _on_base_projected_item_graph_updated(_snapshot: Dictionary) -> void:
	# Base CH9.6 also consumes this signal to install the canonical replica. Defer
	# the FPE dirty mark so our next-frame presentation read happens after every
	# synchronous signal handler has finished applying that replica.
	call_deferred("_mark_canonical_projection_dirty")


func _mark_canonical_projection_dirty() -> void:
	_equipment_sync_dirty = true
	_hotbar_presentation_dirty = true


func _select_hotbar_nonblocking(index: int) -> Dictionary:
	if not _ensure_hotbar_network_adapter():
		return _failure("FPE_HOTBAR_NETWORK_NOT_READY")
	var controller = base_lab.character_gameplay_controller
	if controller == null:
		return _failure("FPE_HOTBAR_CONTROLLER_NOT_READY")

	var canonical_index: int = hotbar_network_adapter.canonical_selected_index()
	if int(controller.selected_hotbar_index) == index and canonical_index == index:
		return {
			"success": true,
			"code": "OK",
			"details": {"changed": false, "selected_hotbar_index": index},
		}

	var submitted: Dictionary = hotbar_network_adapter.submit(index)
	if not bool(submitted.get("success", false)):
		return submitted

	# Presentation prediction only. Do not call controller._refresh_ui(): that
	# rebuilds the full inventory/equipment screen. Only the persistent hotbar is
	# needed for immediate feedback while server authority is pending.
	controller.selected_hotbar_index = index
	_refresh_persistent_hotbar_only()
	_hotbar_prediction_index = index
	_last_hotbar_item_id = ""
	_hotbar_presentation_dirty = true
	return submitted


func _refresh_persistent_hotbar_only() -> void:
	if base_lab == null or base_lab.character_gameplay_controller == null:
		return
	var inventory_ui = base_lab.character_gameplay_controller.inventory_ui
	if inventory_ui != null and inventory_ui.has_method("_refresh_persistent_hotbar"):
		inventory_ui.call("_refresh_persistent_hotbar")


func _poll_hotbar_authority() -> void:
	if hotbar_network_adapter == null or not hotbar_network_adapter.has_pending():
		return
	var polled: Dictionary = hotbar_network_adapter.poll()
	var details: Dictionary = Dictionary(polled.get("details", {}))
	if bool(polled.get("success", false)):
		if bool(details.get("confirmed", false)):
			_hotbar_prediction_index = -1
			_last_fpe_status_code = "HOTBAR_AUTHORITY_CONFIRMED"
			_hotbar_presentation_dirty = true
			_refresh_status()
		return
	if not bool(details.get("rollback_required", false)):
		return
	var canonical_index := int(details.get("canonical_selected_hotbar_index", -1))
	if canonical_index >= 0 and base_lab.character_gameplay_controller != null:
		base_lab.character_gameplay_controller.selected_hotbar_index = canonical_index
		_refresh_persistent_hotbar_only()
		_last_hotbar_item_id = ""
		_hotbar_presentation_dirty = true
	_hotbar_prediction_index = -1
	_last_fpe_status_code = String(polled.get("error_code", "FPE_HOTBAR_AUTHORITY_CONFIRM_TIMEOUT"))
	_refresh_status()


func _sync_authoritative_hotbar_presentation() -> void:
	if not bool(base_lab.network_ready):
		_hotbar_presentation_dirty = true
		return
	_hotbar_sync_runs += 1
	var selected_item_id: String = String(base_lab.character_gameplay_controller.get_selected_hotbar_item_id())
	if selected_item_id == _last_hotbar_item_id:
		return
	_last_hotbar_item_id = selected_item_id
	if selected_item_id.is_empty():
		first_person_embodiment.clear_authoritative_hand_item("right")
		return
	var item: Variant = base_lab.character_gameplay_controller.get_item(selected_item_id)
	if item == null:
		first_person_embodiment.clear_authoritative_hand_item("right")
		return
	var definition: Variant = base_lab.character_gameplay_controller.get_definition(String(item.definition_id))
	var display_name := String(item.definition_id)
	var item_color := Color(0.65, 0.68, 0.72, 1.0)
	if definition != null:
		display_name = String(definition.display_name)
		item_color = _metadata_color(definition.metadata, item_color)
	first_person_embodiment.set_authoritative_hand_item(
		"right",
		selected_item_id,
		display_name,
		item_color
	)


func _sync_equipment_viewmodel() -> void:
	if base_lab.item_graph_equipment_source == null:
		_equipment_sync_dirty = true
		return
	_equipment_sync_runs += 1
	# get_snapshot() performs a full Item Graph equipment refresh. This is now
	# intentionally reached only after initial binding or a canonical projection,
	# never from every render frame.
	var snapshot: Variant = base_lab.item_graph_equipment_source.get_snapshot()
	if snapshot == null:
		return
	var fingerprint: String = String(snapshot.fingerprint())
	if fingerprint == _last_equipment_fingerprint:
		return
	_last_equipment_fingerprint = fingerprint

	var upper_enabled := false
	var sleeve_color := Color(0.46, 0.25, 0.18, 1.0)
	for raw_entry in snapshot.entries():
		if raw_entry == null or String(raw_entry.profile_id) != UPPER_PROFILE_ID:
			continue
		upper_enabled = true
		var item: Variant = base_lab.character_gameplay_controller.get_item(String(raw_entry.item_id))
		if item != null:
			var definition: Variant = base_lab.character_gameplay_controller.get_definition(String(item.definition_id))
			if definition != null:
				sleeve_color = _metadata_color(definition.metadata, sleeve_color)
		break
	_last_upper_clothing_enabled = upper_enabled
	var clothing_result: Dictionary = first_person_embodiment.set_upper_clothing_enabled(
		upper_enabled,
		sleeve_color
	)
	if not bool(clothing_result.get("success", false)):
		_last_fpe_status_code = String(clothing_result.get("error_code", "FPE_CLOTHING_SYNC_FAILED"))


func _spawn_local_grab_sandbox() -> void:
	for index in range(3):
		var body := RigidBody3D.new()
		body.name = "FPELocalGrabTarget%d" % (index + 1)
		body.position = Vector3((float(index) - 1.0) * 0.62, 1.50, -2.15)
		body.gravity_scale = 0.0
		body.linear_damp = 3.0
		body.angular_damp = 4.0
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta("fpe_local_sandbox_grabbable", true)
		body.set_meta("fpe_demo_target", true)
		add_child(body)

		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.32, 0.32, 0.32)
		collision.shape = shape
		body.add_child(collision)

		var visual := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.32, 0.32, 0.32)
		visual.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = [
			Color(0.35, 0.62, 0.86, 1.0),
			Color(0.82, 0.55, 0.25, 1.0),
			Color(0.42, 0.72, 0.42, 1.0),
		][index]
		material.roughness = 0.75
		visual.material_override = material
		body.add_child(visual)
		_sandbox_targets.append(body)


func _build_status_overlay() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "FPEStatusCanvas"
	canvas.layer = 100
	add_child(canvas)
	fpe_status_label = Label.new()
	fpe_status_label.name = "FPEStatusLabel"
	fpe_status_label.position = Vector2(430.0, 12.0)
	fpe_status_label.size = Vector2(520.0, 220.0)
	fpe_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fpe_status_label.add_theme_font_size_override("font_size", 13)
	fpe_status_label.add_theme_constant_override("outline_size", 3)
	canvas.add_child(fpe_status_label)


func _record_process_cost(started_us: int) -> void:
	var elapsed_us := maxi(Time.get_ticks_usec() - started_us, 0)
	_perf_window_frames += 1
	_perf_window_total_us += elapsed_us
	_perf_window_max_us = maxi(_perf_window_max_us, elapsed_us)


func _publish_performance_window_if_due() -> void:
	var now_ms := Time.get_ticks_msec()
	if now_ms - _perf_last_publish_ms < PERF_HUD_INTERVAL_MS:
		return
	_perf_last_publish_ms = now_ms
	_perf_last_average_us = (
		float(_perf_window_total_us) / float(_perf_window_frames)
		if _perf_window_frames > 0 else 0.0
	)
	_perf_last_max_us = _perf_window_max_us
	_perf_window_frames = 0
	_perf_window_total_us = 0
	_perf_window_max_us = 0
	_refresh_status()


func _metadata_color(metadata_value: Variant, fallback: Color) -> Color:
	if not metadata_value is Dictionary:
		return fallback
	var raw_color: Variant = Dictionary(metadata_value).get("icon_color")
	if raw_color is Color:
		return raw_color as Color
	if raw_color is Array and raw_color.size() >= 3:
		return Color(
			float(raw_color[0]),
			float(raw_color[1]),
			float(raw_color[2]),
			float(raw_color[3]) if raw_color.size() >= 4 else 1.0
		)
	return fallback


func _hotbar_index_for_key(keycode: Key) -> int:
	match keycode:
		KEY_1:
			return 0
		KEY_2:
			return 1
		KEY_3:
			return 2
		KEY_4:
			return 3
		KEY_5:
			return 4
		KEY_6:
			return 5
		KEY_7:
			return 6
		KEY_8:
			return 7
		KEY_9:
			return 8
		KEY_0:
			return 9
	return -1


func _on_fpe_interaction_result_changed(result: Dictionary) -> void:
	_last_fpe_status_code = String(result.get("error_code", "OK"))
	_refresh_status()


func _on_fpe_grab_state_changed(_hand_id: String, _occupied: bool, _target_path: String) -> void:
	_refresh_status()


func get_first_person_embodiment_debug_snapshot() -> Dictionary:
	return {
		"schema": "planet_simulator.quaternius_first_person_embodiment_lab.v4",
		"composition_mode": "THROTTLED_CH9_6_RESEARCH_HOST",
		"base_lab_present": base_lab != null,
		"setup": fpe_setup_result.duplicate(true),
		"network_ready": bool(base_lab.network_ready) if base_lab != null else false,
		"selected_hotbar_item_id": _last_hotbar_item_id,
		"hotbar_prediction_index": _hotbar_prediction_index,
		"hotbar_network": hotbar_network_adapter.get_report() if hotbar_network_adapter != null else {},
		"equipment_fingerprint": _last_equipment_fingerprint,
		"upper_clothing_enabled": _last_upper_clothing_enabled,
		"embodiment": first_person_embodiment.create_report() if first_person_embodiment != null else {},
		"grab_authority": grab_authority_bridge.create_report() if grab_authority_bridge != null else {},
		"sandbox_target_count": _sandbox_targets.size(),
		"canonical_world_grab_contract": "PENDING_SEPARATE_AUTHORITY_FRONTIER",
		"performance": {
			"fpe_process_average_us": _perf_last_average_us,
			"fpe_process_max_us": _perf_last_max_us,
			"equipment_sync_runs": _equipment_sync_runs,
			"hotbar_sync_runs": _hotbar_sync_runs,
			"equipment_sync_dirty": _equipment_sync_dirty,
			"hotbar_presentation_dirty": _hotbar_presentation_dirty,
			"network_projection_signal_bound": _network_projection_signal_bound,
			"base_status": base_lab.get_fpe_status_performance_report() if base_lab != null and base_lab.has_method("get_fpe_status_performance_report") else {},
		},
	}


func _refresh_status() -> void:
	if fpe_status_label == null:
		return
	var embodiment_report: Dictionary = first_person_embodiment.create_report() if first_person_embodiment != null else {}
	var grab_report: Dictionary = grab_authority_bridge.create_report() if grab_authority_bridge != null else {}
	var hotbar_pending := hotbar_network_adapter != null and hotbar_network_adapter.has_pending()
	var sleeve_mode := "REAL_QUATERNIUS" if bool(embodiment_report.get("real_quaternius_sleeves_ready", false)) else "PROCEDURAL" if _last_upper_clothing_enabled else "OFF"
	var network_state := "READY" if base_lab != null and bool(base_lab.network_ready) else "BOOTSTRAPPING"
	var hotbar_state := "PENDING" if hotbar_pending else "READY" if hotbar_network_adapter != null else "BOOTSTRAP"
	var base_perf: Dictionary = base_lab.get_fpe_status_performance_report() if base_lab != null and base_lab.has_method("get_fpe_status_performance_report") else {}
	var text := (
		"FPE research — FirstPersonEmbodiment"
		+ "\nC 1/3 person | Q left | E right | 1..0 hotbar"
		+ "\nnetwork: %s | hotbar: NONBLOCKING/%s | sleeves: %s"
		+ "\nselected: %s | world grab: %s | sandbox: %s"
		+ "\nperf FPE avg/max: %.3f / %.3f ms | sync eq/hotbar: %d / %d"
		+ "\nbase HUD executed/skipped: %d / %d | max %.3f ms"
		+ "\nlast: %s"
	) % [
		network_state,
		hotbar_state,
		sleeve_mode,
		_last_hotbar_item_id if not _last_hotbar_item_id.is_empty() else "EMPTY",
		"READY" if bool(grab_report.get("canonical_grab_authority_ready", false)) else "FAIL_CLOSED",
		"ON" if bool(grab_report.get("local_sandbox_enabled", false)) else "OFF",
		_perf_last_average_us / 1000.0,
		float(_perf_last_max_us) / 1000.0,
		_equipment_sync_runs,
		_hotbar_sync_runs,
		int(base_perf.get("executed", 0)),
		int(base_perf.get("skipped", 0)),
		float(base_perf.get("max_us", 0)) / 1000.0,
		_last_fpe_status_code if not _last_fpe_status_code.is_empty() else "OK",
	]
	if fpe_status_label.text != text:
		fpe_status_label.text = text


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"details": details.duplicate(true),
	}
