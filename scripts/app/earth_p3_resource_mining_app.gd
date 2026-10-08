extends "res://scripts/app/earth_p1_modern_inventory_app.gd"

const ResourceMiningSnapshot = preload(
	"res://scripts/runtime/networked_gameplay/p3/resource_mining_snapshot.gd"
)
const EarthResourceSpatialResolver = preload(
	"res://scripts/runtime/networked_gameplay/p3/earth_resource_spatial_resolver.gd"
)
const ResourceMiningTarget = preload(
	"res://scripts/runtime/networked_gameplay/p3/resource_mining_target.gd"
)
const User1JourneyOverlayScript = preload(
	"res://scripts/ui/user1_journey_overlay.gd"
)

# Resource targets share the canonical P1 interaction layer with ordinary world
# items. A small priority bonus only breaks near-ties inside the same aim cone;
# a clearly aimed ordinary item/container remains selectable.
const P3_RESOURCE_FOCUS_PRIORITY_BONUS := 0.02

var _p3_resource_snapshot: Dictionary = {}
var _p3_resource_resolver
var _p3_resource_targets: Dictionary = {}
var _p3_resource_signal_connected := false
var _p3_resource_snapshot_updates := 0
var _p3_mining_attempts := 0
var _p3_mining_rejections := 0
var _p3_projection_failures := 0
var _p3_setup_error := ""
var _user1_journey_overlay


func attach_m3_multiplayer_client(runtime) -> Dictionary:
	var result: Dictionary = super.attach_m3_multiplayer_client(runtime)
	if not bool(result.get("success", false)):
		return result
	if (
		runtime == null
		or not runtime.has_signal("resource_mining_updated")
		or not runtime.has_method("get_resource_mining_snapshot")
		or (
			not runtime.has_method("execute_resource_mine_async")
			and not runtime.has_method("execute_resource_mine_blocking")
		)
	):
		_p3_setup_error = "V0_P3_RESOURCE_NETWORK_RUNTIME_REQUIRED"
		return {"success": false, "error_code": _p3_setup_error, "details": {}}
	_p3_resource_resolver = EarthResourceSpatialResolver.new()
	var resolver_setup: Dictionary = _p3_resource_resolver.setup()
	if not bool(resolver_setup.get("success", false)):
		_p3_setup_error = String(resolver_setup.get("error_code", "V0_P3_RESOURCE_RESOLVER_SETUP_FAILED"))
		return resolver_setup
	var callback := Callable(self, "_on_p3_resource_mining_updated")
	if not runtime.is_connected("resource_mining_updated", callback):
		runtime.connect("resource_mining_updated", callback)
	_p3_resource_signal_connected = true
	var initial: Dictionary = runtime.get_resource_mining_snapshot()
	if not initial.is_empty():
		var accepted := _accept_p3_resource_snapshot(initial)
		if not bool(accepted.get("success", false)):
			_p3_setup_error = String(accepted.get("error_code", "V0_P3_INITIAL_RESOURCE_SYNC_FAILED"))
			return accepted
	_p3_setup_error = ""
	var journey_setup: Dictionary = _ensure_user1_journey_overlay()
	if not bool(journey_setup.get("success", false)):
		return journey_setup
	var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
	details["v0_p3_resource_mining"] = true
	details["resource_generation"] = int(_p3_resource_snapshot.get("generation", 0))
	details["user1_journey"] = true
	result["details"] = details
	return result


func _process(delta: float) -> void:
	super._process(delta)
	_refresh_p3_resource_projection()


func prepare_for_unload() -> void:
	if _user1_journey_overlay != null and is_instance_valid(_user1_journey_overlay):
		_user1_journey_overlay.queue_free()
	_user1_journey_overlay = null
	if (
		_p3_resource_signal_connected
		and m3_multiplayer_client_runtime != null
		and is_instance_valid(m3_multiplayer_client_runtime)
	):
		var callback := Callable(self, "_on_p3_resource_mining_updated")
		if m3_multiplayer_client_runtime.is_connected("resource_mining_updated", callback):
			m3_multiplayer_client_runtime.disconnect("resource_mining_updated", callback)
	_p3_resource_signal_connected = false
	for target_value in _p3_resource_targets.values():
		if target_value != null and is_instance_valid(target_value):
			target_value.queue_free()
	_p3_resource_targets.clear()
	_p3_resource_snapshot.clear()
	_p3_resource_resolver = null
	super.prepare_for_unload()


# P1's fallback only knows about canonical world-item presentations. P3 adds a
# second presentation family on the same collision layer, so resolve the union
# here rather than allowing a nearby restored/persisted world item to make the
# resource node practically unreachable.
func _resolve_i2s_focus_target():
	if earth_explorer == null:
		return null
	var camera := earth_explorer.get_camera() as Camera3D
	if camera == null:
		return null
	var origin := camera.global_position
	var forward := -camera.global_basis.z.normalized()
	var candidates: Dictionary = {}

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
			candidates[collider.get_instance_id()] = collider

	if _i2s_world_runtime != null and is_instance_valid(_i2s_world_runtime):
		for item_id in _i2s_world_runtime.get_presentation_item_ids():
			var target = _i2s_world_runtime.get_presentation(item_id)
			if target != null and is_instance_valid(target):
				candidates[target.get_instance_id()] = target
	for resource_target_value in _p3_resource_targets.values():
		if resource_target_value != null and is_instance_valid(resource_target_value):
			candidates[resource_target_value.get_instance_id()] = resource_target_value

	var best_target = null
	var best_score := -INF
	for target_value in candidates.values():
		var target = target_value
		var score := _p3_interaction_focus_score(
			origin,
			forward,
			target,
			_is_p3_resource_focus_target(target)
		)
		if score > best_score:
			best_score = score
			best_target = target
	return best_target


func _p3_interaction_focus_score(
	origin: Vector3,
	forward: Vector3,
	target,
	resource_priority: bool
) -> float:
	if target == null or not is_instance_valid(target) or not target is Node3D:
		return -INF
	var offset: Vector3 = target.global_position - origin
	var distance := offset.length()
	if distance <= 0.001 or distance > I2S_INTERACTION_RANGE_M:
		return -INF
	var alignment := forward.normalized().dot(offset / distance)
	if alignment < I2S_FOCUS_DOT_MIN:
		return -INF
	return (
		alignment
		- distance * 0.002
		+ (P3_RESOURCE_FOCUS_PRIORITY_BONUS if resource_priority else 0.0)
	)


func _is_p3_resource_focus_target(target) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	for resource_target_value in _p3_resource_targets.values():
		if resource_target_value == target:
			return true
	return false


func _on_p3_resource_mining_updated(snapshot: Dictionary) -> void:
	var accepted := _accept_p3_resource_snapshot(snapshot)
	if not bool(accepted.get("success", false)):
		_p3_setup_error = String(accepted.get("error_code", "V0_P3_RESOURCE_SYNC_REJECTED"))


func _accept_p3_resource_snapshot(snapshot: Dictionary) -> Dictionary:
	var validation := ResourceMiningSnapshot.validate(snapshot)
	if not bool(validation.get("success", false)):
		return validation
	_p3_resource_snapshot = snapshot.duplicate(true)
	_p3_resource_snapshot_updates += 1
	var wanted: Dictionary = {}
	for node_value in snapshot.get("nodes", []):
		if not node_value is Dictionary:
			continue
		var node: Dictionary = node_value
		var node_id := String(node.get("resource_node_id", "")).strip_edges().to_lower()
		if node_id.is_empty():
			continue
		wanted[node_id] = true
		var target = _p3_resource_targets.get(node_id)
		if target == null or not is_instance_valid(target):
			target = ResourceMiningTarget.new()
			add_child(target)
			var target_setup: Dictionary = target.setup(
				node,
				Callable(self, "_mine_p3_resource")
			)
			if not bool(target_setup.get("success", false)):
				target.queue_free()
				continue
			_p3_resource_targets[node_id] = target
		else:
			target.apply_resource_record(node)
	for existing_id_value in _p3_resource_targets.keys().duplicate():
		var existing_id := String(existing_id_value)
		if wanted.has(existing_id):
			continue
		var target = _p3_resource_targets.get(existing_id)
		if target != null and is_instance_valid(target):
			target.queue_free()
		_p3_resource_targets.erase(existing_id)
	_refresh_p3_resource_projection()
	return {"success": true, "error_code": "", "details": {"target_count": _p3_resource_targets.size()}}


func _mine_p3_resource(resource_node_id: String) -> Dictionary:
	_p3_mining_attempts += 1
	if (
		m3_multiplayer_client_runtime == null
		or not is_instance_valid(m3_multiplayer_client_runtime)
	):
		_p3_mining_rejections += 1
		return {"success": false, "error_code": "V0_P3_RESOURCE_NETWORK_RUNTIME_REQUIRED", "details": {}}

	# Product/human path is asynchronous so mining cannot freeze render,
	# interpolation or local prediction while waiting for the server.
	if m3_multiplayer_client_runtime.has_method("execute_resource_mine_async"):
		if not _live2_mining_tool_is_equipped():
			var equip_result: Dictionary = ensure_live2_mining_tool_equipped_async({
				"kind": "mine_after_equip",
				"resource_node_id": resource_node_id,
				"pending_text": "Экипируем инструмент перед добычей…",
				"success_text": "Инструмент экипирован · начинаем добычу…",
				"error_prefix": "Экипировка перед добычей",
			})
			if not bool(equip_result.get("success", false)):
				_p3_mining_rejections += 1
				return equip_result
			if not bool(equip_result.get("already_equipped", false)):
				return equip_result
		return _submit_p3_resource_mine_async(resource_node_id)

	# Blocking compatibility seam retained only for legacy deterministic probes.
	if not m3_multiplayer_client_runtime.has_method("execute_resource_mine_blocking"):
		_p3_mining_rejections += 1
		return {"success": false, "error_code": "V0_P3_RESOURCE_NETWORK_RUNTIME_REQUIRED", "details": {}}
	var equip_result: Dictionary = ensure_live2_mining_tool_equipped()
	if not bool(equip_result.get("success", false)):
		_p3_mining_rejections += 1
		return equip_result
	var result: Dictionary = m3_multiplayer_client_runtime.execute_resource_mine_blocking(
		resource_node_id,
		1
	)
	if not bool(result.get("success", false)):
		_p3_mining_rejections += 1
		_show_live2_action_feedback(
			"Добыча: %s" % String(result.get("error_code", "UNKNOWN")),
			false
		)
		return result
	_show_live2_action_feedback("Руда добыта · материал добавлен в инвентарь", true)
	return result


func _submit_p3_resource_mine_async(resource_node_id: String) -> Dictionary:
	var sent: Dictionary = m3_multiplayer_client_runtime.execute_resource_mine_async(
		resource_node_id,
		1
	)
	if not bool(sent.get("success", false)):
		_p3_mining_rejections += 1
		_show_live2_action_feedback(
			"Добыча: %s" % String(sent.get("error_code", "SEND_FAILED")),
			false
		)
		return sent
	var operation_id := String(sent.get("details", {}).get(
		"operation_id",
		sent.get("operation_id", "")
	))
	if operation_id.is_empty():
		_p3_mining_rejections += 1
		return {"success": false, "error_code": "ASYNC_OPERATION_ID_MISSING"}
	_track_live2_async_action(operation_id, {
		"kind": "resource_mine",
		"resource_node_id": resource_node_id,
		"pending_text": "Добываем руду…",
		"success_text": "Руда добыта · материал добавлен в инвентарь",
		"error_prefix": "Добыча",
	})
	_show_live2_action_feedback("Добываем руду…", true, 2200)
	return {
		"success": true,
		"operation_id": operation_id,
		"pending": true,
		"output": "Добываем руду…",
	}


func _handle_live2_async_command_extension(
	result: Dictionary,
	context: Dictionary
) -> void:
	super._handle_live2_async_command_extension(result, context)
	var kind := String(context.get("kind", ""))
	if kind == "mine_after_equip":
		if String(result.get("status", "")) == "SUCCEEDED":
			_submit_p3_resource_mine_async(String(context.get("resource_node_id", "")))
		else:
			_p3_mining_rejections += 1
		return
	if kind == "resource_mine" and String(result.get("status", "")) != "SUCCEEDED":
		_p3_mining_rejections += 1


func _refresh_p3_resource_projection() -> void:
	if (
		_p3_resource_snapshot.is_empty()
		or _p3_resource_resolver == null
		or _i2s_spatial_projector == null
	):
		return
	for node_value in _p3_resource_snapshot.get("nodes", []):
		if not node_value is Dictionary:
			continue
		var node: Dictionary = node_value
		var node_id := String(node.get("resource_node_id", ""))
		var target = _p3_resource_targets.get(node_id)
		if target == null or not is_instance_valid(target):
			continue
		var resolved: Dictionary = _p3_resource_resolver.resolve_planar(
			Dictionary(node.get("spatial", {}))
		)
		if not bool(resolved.get("success", false)):
			_p3_projection_failures += 1
			continue
		var planar: Dictionary = Dictionary(
			resolved.get("details", {}).get("planar_position", {})
		)
		var canonical_transform := Transform3D(
			Basis.IDENTITY,
			Vector3(
				float(planar.get("x", 0.0)),
				float(planar.get("y", 0.0)) + 0.52,
				float(planar.get("z", 0.0))
			)
		)
		var projected: Dictionary = _i2s_spatial_projector.project_transform(canonical_transform)
		var transform_value = projected.get("details", {}).get("transform") if bool(projected.get("success", false)) else null
		if typeof(transform_value) != TYPE_TRANSFORM3D:
			_p3_projection_failures += 1
			continue
		target.transform = transform_value


func _ensure_user1_journey_overlay() -> Dictionary:
	if _user1_journey_overlay != null and is_instance_valid(_user1_journey_overlay):
		return {"success": true, "error_code": "", "details": {"reused": true}}
	_user1_journey_overlay = User1JourneyOverlayScript.new()
	_user1_journey_overlay.name = "USER1Journey"
	add_child(_user1_journey_overlay)
	var setup_result: Dictionary = _user1_journey_overlay.setup(
		Callable(self, "create_user1_journey_state")
	)
	if not bool(setup_result.get("success", false)):
		_user1_journey_overlay.queue_free()
		_user1_journey_overlay = null
		return setup_result
	return {"success": true, "error_code": "", "details": {"ui": "USER1_JOURNEY"}}


func create_user1_journey_state() -> Dictionary:
	var player_id := ""
	var ownership_epoch := 0
	var position: Dictionary = {"x": 0.0, "y": 0.0, "z": 0.0}
	var gameplay_snapshot: Dictionary = {}
	var construction: Dictionary = {}
	var product_seam: Dictionary = {}
	if m3_multiplayer_client_runtime != null:
		if m3_multiplayer_client_runtime.has_method("get_local_player_id"):
			player_id = String(m3_multiplayer_client_runtime.get_local_player_id())
		if m3_multiplayer_client_runtime.has_method("get_local_player_record"):
			var player: Dictionary = m3_multiplayer_client_runtime.get_local_player_record()
			ownership_epoch = int(player.get("ownership_epoch", 0))
			var position_value = player.get("position", {})
			if position_value is Dictionary:
				position = Dictionary(position_value).duplicate(true)
		if m3_multiplayer_client_runtime.has_method("get_snapshot"):
			gameplay_snapshot = m3_multiplayer_client_runtime.get_snapshot()
		if m3_multiplayer_client_runtime.has_method("get_construction_bundle"):
			construction = m3_multiplayer_client_runtime.get_construction_bundle()
		if m3_multiplayer_client_runtime.has_method("get_product_seam_state"):
			product_seam = m3_multiplayer_client_runtime.get_product_seam_state()

	var inventory_ore_quantity := 0
	var world_item_count := 0
	var open_container_id := ""
	var shared_container_item_count := 0
	if not _m4_item_graph_snapshot.is_empty():
		for item_value in _m4_item_graph_snapshot.get("items", []):
			if not item_value is Dictionary:
				continue
			var item: Dictionary = item_value
			var location_value = item.get("location", {})
			if not location_value is Dictionary:
				continue
			var location: Dictionary = location_value
			var kind := String(location.get("kind", ""))
			if kind == "WORLD":
				world_item_count += 1
			if (
				String(item.get("definition_id", "")) == "item/ore"
				and kind == "INVENTORY"
				and String(location.get("player_id", "")) == player_id
			):
				inventory_ore_quantity += int(item.get("quantity", 0))
		var open_containers_value = _m4_item_graph_snapshot.get("open_containers", {})
		if open_containers_value is Dictionary:
			open_container_id = String(
				Dictionary(open_containers_value).get(player_id, "")
			)
		for container_value in _m4_item_graph_snapshot.get("containers", []):
			if not container_value is Dictionary:
				continue
			var container: Dictionary = container_value
			if String(container.get("container_id", "")) == "container/shared/crate/1":
				shared_container_item_count = Array(container.get("slots", [])).size()
				break

	var nearest_resource_distance_m := INF
	if _p3_resource_resolver != null and not _p3_resource_snapshot.is_empty():
		var player_x := float(position.get("x", 0.0))
		var player_z := float(position.get("z", 0.0))
		for node_value in _p3_resource_snapshot.get("nodes", []):
			if not node_value is Dictionary:
				continue
			var node: Dictionary = node_value
			var resolved: Dictionary = _p3_resource_resolver.resolve_planar(
				Dictionary(node.get("spatial", {}))
			)
			if not bool(resolved.get("success", false)):
				continue
			var planar: Dictionary = Dictionary(
				resolved.get("details", {}).get("planar_position", {})
			)
			var dx := float(planar.get("x", 0.0)) - player_x
			var dz := float(planar.get("z", 0.0)) - player_z
			nearest_resource_distance_m = minf(
				nearest_resource_distance_m,
				sqrt(dx * dx + dz * dz)
			)

	return {
		"schema": User1JourneyOverlayScript.STATE_SCHEMA,
		"connection_state": _live2_connection_state,
		"player_id": player_id,
		"ownership_epoch": ownership_epoch,
		"position": position.duplicate(true),
		"region_id": String(
			product_seam.get(
				"region_id",
				gameplay_snapshot.get("region_id", "")
			)
		),
		"seam_active_authority_id": String(
			product_seam.get("active_authority_id", "")
		),
		"seam_authority_epoch": int(product_seam.get("authority_epoch", 0)),
		"seam_crossings": int(product_seam.get("crossings", 0)),
		"seam_roundtrips": int(product_seam.get("roundtrips", -1)),
		"remote_player_count": _m3_remote_presenters.size(),
		"nearest_resource_distance_m": nearest_resource_distance_m,
		"resource_generation": int(_p3_resource_snapshot.get("generation", -1)),
		"mining_tool_equipped": _live2_mining_tool_is_equipped(),
		"inventory_ore_quantity": inventory_ore_quantity,
		"item_graph_revision": int(_m4_item_graph_snapshot.get("revision", -1)),
		"world_item_count": world_item_count,
		"open_container_id": open_container_id,
		"shared_container_item_count": shared_container_item_count,
		"construction_generation": int(construction.get("server_generation", -1)),
		"construct_count": Array(construction.get("constructs", [])).size(),
		"inventory_visible": is_mvp_inventory_visible(),
		"build_mode": _live2_build_mode,
	}


func create_m3_graphical_client_report() -> Dictionary:
	var report: Dictionary = super.create_m3_graphical_client_report()
	report["user1_journey"] = (
		_user1_journey_overlay.get_report()
		if _user1_journey_overlay != null and is_instance_valid(_user1_journey_overlay)
		else {}
	)
	report["v0_p3"] = {
		"checkpoint": "V0-P3-R1",
		"ready": (
			_p3_resource_resolver != null
			and _p3_setup_error.is_empty()
		),
		"setup_error": _p3_setup_error,
		"resource_generation": int(_p3_resource_snapshot.get("generation", 0)),
		"resource_checksum": String(_p3_resource_snapshot.get("checksum", "")),
		"resource_target_count": _p3_resource_targets.size(),
		"resource_snapshot_updates": _p3_resource_snapshot_updates,
		"mining_attempts": _p3_mining_attempts,
		"mining_rejections": _p3_mining_rejections,
		"projection_failures": _p3_projection_failures,
	}
	return report
