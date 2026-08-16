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

var _p3_resource_snapshot: Dictionary = {}
var _p3_resource_resolver
var _p3_resource_targets: Dictionary = {}
var _p3_resource_signal_connected := false
var _p3_resource_snapshot_updates := 0
var _p3_mining_attempts := 0
var _p3_mining_rejections := 0
var _p3_projection_failures := 0
var _p3_setup_error := ""


func attach_m3_multiplayer_client(runtime) -> Dictionary:
	var result: Dictionary = super.attach_m3_multiplayer_client(runtime)
	if not bool(result.get("success", false)):
		return result
	if (
		runtime == null
		or not runtime.has_signal("resource_mining_updated")
		or not runtime.has_method("get_resource_mining_snapshot")
		or not runtime.has_method("execute_resource_mine_blocking")
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
	var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
	details["v0_p3_resource_mining"] = true
	details["resource_generation"] = int(_p3_resource_snapshot.get("generation", 0))
	result["details"] = details
	return result


func _process(delta: float) -> void:
	super._process(delta)
	_refresh_p3_resource_projection()


func prepare_for_unload() -> void:
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
		or not m3_multiplayer_client_runtime.has_method("execute_resource_mine_blocking")
	):
		_p3_mining_rejections += 1
		return {"success": false, "error_code": "V0_P3_RESOURCE_NETWORK_RUNTIME_REQUIRED", "details": {}}
	var result: Dictionary = m3_multiplayer_client_runtime.execute_resource_mine_blocking(
		resource_node_id,
		1
	)
	if not bool(result.get("success", false)):
		_p3_mining_rejections += 1
	return result


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


func create_m3_graphical_client_report() -> Dictionary:
	var report: Dictionary = super.create_m3_graphical_client_report()
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
