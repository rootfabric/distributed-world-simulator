extends Node3D

signal presentation_synchronized(report: Dictionary)
signal command_completed(result: Dictionary)
signal external_container_context_changed(container_id: String, screen: Dictionary)

const WorldItemTarget = preload(
	"res://scripts/runtime/networked_gameplay/i2s/canonical_world_item_target.gd"
)
const M4ItemGraphUiProjection = preload(
	"res://scripts/runtime/networked_gameplay/m5/m4_item_graph_ui_projection.gd"
)
const PlayableStateCodec = preload(
	"res://scripts/runtime/listen_host/playable_state_codec.gd"
)

const RESULT_SCHEMA := "planet_simulator.i2s_world_item_runtime_result.v1"
const REPORT_SCHEMA := "planet_simulator.i2s_world_item_runtime_report.v1"

var _world_root: Node3D
var _logical_player_id: String = ""
var _command_submitter: Callable
var _spatial_projector
var _projection = M4ItemGraphUiProjection.new()
var _presentations: Dictionary = {}
var _container_by_owner_item: Dictionary = {}
var _last_sync_report: Dictionary = {}
var _last_external_container_id: String = ""
var _configured: bool = false


func setup(
	world_root_reference: Node3D,
	logical_player_id: String,
	command_submitter: Callable,
	spatial_projector = null
) -> Dictionary:
	if _configured:
		return _failure("I2S_RUNTIME_ALREADY_CONFIGURED")
	var player_id := logical_player_id.strip_edges().to_lower()
	if world_root_reference == null:
		return _failure("I2S_WORLD_ROOT_REQUIRED")
	if player_id.is_empty():
		return _failure("I2S_PLAYER_ID_REQUIRED")
	if not command_submitter.is_valid():
		return _failure("I2S_COMMAND_SUBMITTER_REQUIRED")
	if spatial_projector != null and not spatial_projector.has_method("project_transform"):
		return _failure("I2S_SPATIAL_PROJECTOR_INVALID")
	_world_root = world_root_reference
	_logical_player_id = player_id
	_command_submitter = command_submitter
	_spatial_projector = spatial_projector
	_configured = true
	return _success({"logical_player_id": _logical_player_id})


func accept_snapshot(snapshot: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("I2S_RUNTIME_NOT_CONFIGURED")
	var accepted: Dictionary = _projection.accept_snapshot(snapshot)
	if not bool(accepted.get("success", false)):
		return _failure(
			"I2S_CANONICAL_SNAPSHOT_REJECTED",
			{"canonical_error_code": String(accepted.get("error_code", ""))}
		)
	var canonical_snapshot: Dictionary = _projection.get_snapshot()
	_rebuild_container_owner_index(canonical_snapshot)
	var wanted: Dictionary = {}
	var created: Array[String] = []
	var updated: Array[String] = []
	var removed: Array[String] = []
	var unprojectable: Array[String] = []

	for item_value in canonical_snapshot.get("items", []):
		if not item_value is Dictionary:
			continue
		var item: Dictionary = item_value
		var item_id := String(item.get("item_id", "")).strip_edges().to_lower()
		if item_id.is_empty():
			continue
		var location_value = item.get("location", {})
		if not location_value is Dictionary or String(location_value.get("kind", "")) != "WORLD":
			continue
		wanted[item_id] = true
		var transform_value = item.get("transform", {})
		if (
			not transform_value is Dictionary
			or not bool(PlayableStateCodec.validate_transform_dto(Dictionary(transform_value)).get("success", false))
		):
			unprojectable.append(item_id)
			_remove_presentation(item_id, removed)
			continue
		var canonical_transform := PlayableStateCodec.transform_from_dto(Dictionary(transform_value))
		var projected := _project_transform(canonical_transform)
		if not bool(projected.get("success", false)):
			unprojectable.append(item_id)
			_remove_presentation(item_id, removed)
			continue
		var presentation_transform = projected.get("details", {}).get("transform")
		if typeof(presentation_transform) != TYPE_TRANSFORM3D:
			unprojectable.append(item_id)
			_remove_presentation(item_id, removed)
			continue
		var container_id := String(_container_by_owner_item.get(item_id, ""))
		var target = _presentations.get(item_id)
		if target == null or not is_instance_valid(target):
			target = WorldItemTarget.new()
			_world_root.add_child(target)
			var target_setup: Dictionary = target.setup(self, item, container_id)
			if not bool(target_setup.get("success", false)):
				_world_root.remove_child(target)
				target.queue_free()
				unprojectable.append(item_id)
				continue
			_presentations[item_id] = target
			created.append(item_id)
		else:
			var target_update: Dictionary = target.apply_canonical_record(item, container_id)
			if not bool(target_update.get("success", false)):
				unprojectable.append(item_id)
				_remove_presentation(item_id, removed)
				continue
			updated.append(item_id)
		target.transform = presentation_transform

	for presented_id_value in _presentations.keys().duplicate():
		var presented_id := String(presented_id_value)
		if not wanted.has(presented_id):
			_remove_presentation(presented_id, removed)

	created.sort()
	updated.sort()
	removed.sort()
	unprojectable.sort()
	_last_sync_report = {
		"schema": REPORT_SCHEMA,
		"success": unprojectable.is_empty(),
		"canonical_revision": int(canonical_snapshot.get("revision", -1)),
		"canonical_checksum": String(canonical_snapshot.get("checksum", "")),
		"presentation_count": _presentations.size(),
		"created": created,
		"updated": updated,
		"removed": removed,
		"unprojectable_world_items": unprojectable,
		"snapshot_replay": bool(accepted.get("details", {}).get("replay", accepted.get("replay", false))),
	}
	_emit_external_context_if_changed()
	presentation_synchronized.emit(_last_sync_report.duplicate(true))
	if not unprojectable.is_empty():
		return _failure(
			"I2S_WORLD_SPATIAL_STATE_INCOMPLETE",
			{"report": _last_sync_report.duplicate(true)}
		)
	return _success({"report": _last_sync_report.duplicate(true)})


# Earth uses a moving render origin. Canonical Item Graph transforms remain in
# server tangent-plane/world coordinates, so presentation transforms must be
# reprojected after the render origin changes even when the Item Graph revision
# itself did not change.
func refresh_spatial_projection() -> Dictionary:
	if not _configured:
		return _failure("I2S_RUNTIME_NOT_CONFIGURED")
	var snapshot := _projection.get_snapshot()
	if snapshot.is_empty():
		return _failure("I2S_CANONICAL_SNAPSHOT_MISSING")
	var updated := 0
	var failures: Array[String] = []
	for item_value in snapshot.get("items", []):
		if not item_value is Dictionary:
			continue
		var item: Dictionary = item_value
		var item_id := String(item.get("item_id", "")).strip_edges().to_lower()
		if String(item.get("location", {}).get("kind", "")) != "WORLD":
			continue
		var target = _presentations.get(item_id)
		if target == null or not is_instance_valid(target):
			continue
		var transform_value = item.get("transform", {})
		if (
			not transform_value is Dictionary
			or not bool(PlayableStateCodec.validate_transform_dto(Dictionary(transform_value)).get("success", false))
		):
			failures.append(item_id)
			continue
		var canonical_transform := PlayableStateCodec.transform_from_dto(Dictionary(transform_value))
		var projected := _project_transform(canonical_transform)
		var presentation_transform = projected.get("details", {}).get("transform") if bool(projected.get("success", false)) else null
		if typeof(presentation_transform) != TYPE_TRANSFORM3D:
			failures.append(item_id)
			continue
		target.transform = presentation_transform
		updated += 1
	if not failures.is_empty():
		failures.sort()
		return _failure("I2S_SPATIAL_REFRESH_FAILED", {"item_ids": failures, "updated": updated})
	return _success({"updated": updated})


func interact_world_item(item_id: String, _interaction_context: Dictionary = {}) -> Dictionary:
	var canonical_id := item_id.strip_edges().to_lower()
	var item := _item_by_id(canonical_id)
	if item.is_empty() or String(item.get("location", {}).get("kind", "")) != "WORLD":
		return _failure("I2S_STALE_WORLD_INTERACTION", {"item_id": canonical_id})
	var transform_value = item.get("transform", {})
	if (
		not transform_value is Dictionary
		or not bool(PlayableStateCodec.validate_transform_dto(Dictionary(transform_value)).get("success", false))
	):
		return _failure("I2S_WORLD_ITEM_SPATIAL_STATE_MISSING", {"item_id": canonical_id})
	var container_id := String(_container_by_owner_item.get(canonical_id, ""))
	if not container_id.is_empty():
		return open_external_container(container_id)
	return _submit_command("item.pickup", {"item_id": canonical_id})


func drop_item(item_id: String, quantity: int = -1) -> Dictionary:
	var canonical_id := item_id.strip_edges().to_lower()
	var item := _item_by_id(canonical_id)
	var location: Dictionary = Dictionary(item.get("location", {})) if not item.is_empty() else {}
	if (
		item.is_empty()
		or String(location.get("kind", "")) != "INVENTORY"
		or String(location.get("player_id", "")).strip_edges().to_lower() != _logical_player_id
	):
		return _failure("I2S_STALE_INVENTORY_INTERACTION", {"item_id": canonical_id})
	return _submit_command("item.drop", {
		"item_id": canonical_id,
		"quantity": quantity,
	})


func open_external_container(container_id: String) -> Dictionary:
	var canonical_container_id := container_id.strip_edges().to_lower()
	var container := _container_by_id(canonical_container_id)
	if container.is_empty():
		return _failure("I2S_STALE_CONTAINER_INTERACTION", {"container_id": canonical_container_id})
	var owner_item_id := String(container.get("owner_item_id", "")).strip_edges().to_lower()
	var owner_item := _item_by_id(owner_item_id)
	if owner_item.is_empty() or String(owner_item.get("location", {}).get("kind", "")) != "WORLD":
		return _failure("I2S_STALE_CONTAINER_INTERACTION", {"container_id": canonical_container_id})
	return _submit_command("container.open", {"container_id": canonical_container_id})


func close_external_container() -> Dictionary:
	var container_id := _authoritative_external_container_id()
	if container_id.is_empty():
		return _failure("I2S_EXTERNAL_CONTAINER_NOT_OPEN")
	return _submit_command("container.close", {"container_id": container_id})


func transfer_item(
	item_id: String,
	quantity: int = -1,
	target_container_id: String = "",
	target_slot_index: int = -1,
	target_item_id: String = ""
) -> Dictionary:
	var canonical_id := item_id.strip_edges().to_lower()
	var item := _item_by_id(canonical_id)
	if item.is_empty() or not _is_locally_accessible_item(item):
		return _failure("I2S_STALE_TRANSFER_INTERACTION", {"item_id": canonical_id})
	var resolved_target := target_container_id.strip_edges().to_lower()
	if resolved_target.is_empty():
		resolved_target = "inventory/%s" % _logical_player_id
	return _submit_command("item.transfer", {
		"item_id": canonical_id,
		"quantity": quantity,
		"target_container_id": resolved_target,
		"target_slot_index": target_slot_index,
		"target_item_id": target_item_id.strip_edges().to_lower(),
	})


func build_player_container_screen(
	selected_item_id: String = "",
	transient_overlay: Dictionary = {}
) -> Dictionary:
	return _projection.build_screen(
		_logical_player_id,
		_authoritative_external_container_id(),
		selected_item_id.strip_edges().to_lower(),
		transient_overlay
	)


func get_presentation_item_ids() -> Array[String]:
	var result: Array[String] = []
	for item_id_value in _presentations.keys():
		result.append(String(item_id_value))
	result.sort()
	return result


func has_presentation(item_id: String) -> bool:
	var canonical_id := item_id.strip_edges().to_lower()
	var target = _presentations.get(canonical_id)
	return target != null and is_instance_valid(target)


func get_presentation(item_id: String):
	var canonical_id := item_id.strip_edges().to_lower()
	var target = _presentations.get(canonical_id)
	return target if target != null and is_instance_valid(target) else null


func get_canonical_snapshot() -> Dictionary:
	return _projection.get_snapshot()


func get_report() -> Dictionary:
	return _last_sync_report.duplicate(true)


func clear_presentations() -> void:
	for item_id_value in _presentations.keys().duplicate():
		var sink: Array[String] = []
		_remove_presentation(String(item_id_value), sink)
	_last_sync_report = {}


func _submit_command(command_type: String, payload: Dictionary) -> Dictionary:
	if not _configured or not _command_submitter.is_valid():
		return _failure("I2S_COMMAND_SUBMITTER_UNAVAILABLE")
	var raw_result = _command_submitter.call(command_type, payload.duplicate(true), "")
	if not raw_result is Dictionary:
		return _failure("I2S_COMMAND_RESULT_INVALID", {"command_type": command_type})
	var result: Dictionary = Dictionary(raw_result).duplicate(true)
	if bool(result.get("success", false)):
		var snapshot_value = result.get("snapshot", {})
		if snapshot_value is Dictionary and not Dictionary(snapshot_value).is_empty():
			result["i2s_snapshot_accept"] = accept_snapshot(Dictionary(snapshot_value))
	command_completed.emit(result.duplicate(true))
	return result


func _project_transform(canonical_transform: Transform3D) -> Dictionary:
	if _spatial_projector == null:
		return _success({"transform": canonical_transform})
	var raw_result = _spatial_projector.call("project_transform", canonical_transform)
	if not raw_result is Dictionary:
		return _failure("I2S_SPATIAL_PROJECTION_RESULT_INVALID")
	return Dictionary(raw_result).duplicate(true)


func _rebuild_container_owner_index(snapshot: Dictionary) -> void:
	_container_by_owner_item.clear()
	for container_value in snapshot.get("containers", []):
		if not container_value is Dictionary:
			continue
		var container: Dictionary = container_value
		var container_id := String(container.get("container_id", "")).strip_edges().to_lower()
		var owner_item_id := String(container.get("owner_item_id", "")).strip_edges().to_lower()
		if not container_id.is_empty() and not owner_item_id.is_empty():
			_container_by_owner_item[owner_item_id] = container_id


func _remove_presentation(item_id: String, removed: Array[String]) -> void:
	var target = _presentations.get(item_id)
	if target == null:
		return
	_presentations.erase(item_id)
	if is_instance_valid(target):
		if target.get_parent() != null:
			target.get_parent().remove_child(target)
		target.queue_free()
	if item_id not in removed:
		removed.append(item_id)


func _item_by_id(item_id: String) -> Dictionary:
	var snapshot := _projection.get_snapshot()
	for item_value in snapshot.get("items", []):
		if item_value is Dictionary and String(item_value.get("item_id", "")) == item_id:
			return Dictionary(item_value).duplicate(true)
	return {}


func _container_by_id(container_id: String) -> Dictionary:
	var snapshot := _projection.get_snapshot()
	for container_value in snapshot.get("containers", []):
		if (
			container_value is Dictionary
			and String(container_value.get("container_id", "")) == container_id
		):
			return Dictionary(container_value).duplicate(true)
	return {}


func _authoritative_external_container_id() -> String:
	var snapshot := _projection.get_snapshot()
	return String(
		Dictionary(snapshot.get("open_containers", {})).get(_logical_player_id, "")
	).strip_edges().to_lower()


func _is_locally_accessible_item(item: Dictionary) -> bool:
	var location_value = item.get("location", {})
	if not location_value is Dictionary:
		return false
	var location: Dictionary = location_value
	match String(location.get("kind", "")):
		"INVENTORY":
			return String(location.get("player_id", "")).strip_edges().to_lower() == _logical_player_id
		"CONTAINER":
			var container_id := String(location.get("container_id", "")).strip_edges().to_lower()
			return not container_id.is_empty() and container_id == _authoritative_external_container_id()
		_:
			return false


func _emit_external_context_if_changed() -> void:
	var container_id := _authoritative_external_container_id()
	if container_id == _last_external_container_id:
		return
	_last_external_container_id = container_id
	external_container_context_changed.emit(
		container_id,
		build_player_container_screen()
	)


func _success(details: Dictionary = {}) -> Dictionary:
	return {
		"schema": RESULT_SCHEMA,
		"success": true,
		"error_code": "",
		"details": details.duplicate(true),
	}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"schema": RESULT_SCHEMA,
		"success": false,
		"error_code": error_code,
		"details": details.duplicate(true),
	}
