extends Area3D

const INTERACTABLE_GROUP: StringName = &"world_interactable"
const INTERACTION_COLLISION_LAYER := 1 << 19
const RESULT_SCHEMA := "planet_simulator.v0_p3_resource_target_result.v1"

var resource_node_id := ""
var remaining_units := 0
var initial_units := 0
var _mine_callback: Callable
var _mesh_instance: MeshInstance3D
var _collision_shape: CollisionShape3D
var _material: StandardMaterial3D


func setup(node: Dictionary, mine_callback: Callable) -> Dictionary:
	if not mine_callback.is_valid():
		return _failure("V0_P3_MINING_CALLBACK_REQUIRED")
	_mine_callback = mine_callback
	collision_layer = INTERACTION_COLLISION_LAYER
	collision_mask = 0
	monitoring = false
	if not is_in_group(INTERACTABLE_GROUP):
		add_to_group(INTERACTABLE_GROUP)
	_ensure_nodes()
	return apply_resource_record(node)


func apply_resource_record(node: Dictionary) -> Dictionary:
	var next_id := String(node.get("resource_node_id", "")).strip_edges().to_lower()
	var next_remaining := int(node.get("remaining_units", -1))
	if next_id.is_empty() or next_remaining < 0:
		return _failure("V0_P3_INVALID_RESOURCE_RECORD")
	if not resource_node_id.is_empty() and resource_node_id != next_id:
		return _failure("V0_P3_RESOURCE_IDENTITY_MISMATCH")
	resource_node_id = next_id
	remaining_units = next_remaining
	if initial_units < remaining_units:
		initial_units = remaining_units
	if initial_units < 1:
		initial_units = maxi(remaining_units, 1)
	name = "ResourceNode_%s" % resource_node_id.replace("/", "_")
	_update_depletion_visual()
	return _success({
		"resource_node_id": resource_node_id,
		"remaining_units": remaining_units,
	})


func get_interaction_descriptor(_actor = null) -> Dictionary:
	return {
		"id": "resource-target/%s" % resource_node_id,
		"type": "resource_node",
		"resource_node_id": resource_node_id,
		"definition_id": "item/ore",
		"quantity": remaining_units,
		"prompt": "Добыть руду",
	}


func interact(_actor = null, _context: Dictionary = {}) -> Dictionary:
	if resource_node_id.is_empty():
		return _failure("V0_P3_RESOURCE_IDENTITY_MISSING")
	if remaining_units <= 0:
		return _failure("RESOURCE_DEPLETED")
	if not _mine_callback.is_valid():
		return _failure("V0_P3_MINING_RUNTIME_UNAVAILABLE")
	return _mine_callback.call(resource_node_id)


func set_interaction_focus(focused: bool) -> void:
	if _mesh_instance != null:
		_mesh_instance.scale = Vector3.ONE * (1.08 if focused else 1.0)
	if _material != null:
		_material.emission_enabled = focused
		_material.emission = Color(0.72, 0.48, 0.18) if focused else Color.BLACK
		_material.emission_energy_multiplier = 1.4 if focused else 0.0


func _ensure_nodes() -> void:
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "OreBody"
		var ore_mesh := SphereMesh.new()
		ore_mesh.radius = 0.72
		ore_mesh.height = 1.05
		ore_mesh.radial_segments = 12
		ore_mesh.rings = 6
		_mesh_instance.mesh = ore_mesh
		_mesh_instance.scale = Vector3(1.15, 0.78, 0.9)
		_material = StandardMaterial3D.new()
		_material.albedo_color = Color(0.38, 0.31, 0.23)
		_material.metallic = 0.22
		_material.roughness = 0.82
		_mesh_instance.material_override = _material
		add_child(_mesh_instance)
	if _collision_shape == null:
		_collision_shape = CollisionShape3D.new()
		_collision_shape.name = "InteractionCollision"
		var shape := SphereShape3D.new()
		shape.radius = 0.9
		_collision_shape.shape = shape
		add_child(_collision_shape)


func _update_depletion_visual() -> void:
	_ensure_nodes()
	var depleted := remaining_units <= 0
	visible = not depleted
	collision_layer = 0 if depleted else INTERACTION_COLLISION_LAYER
	_collision_shape.disabled = depleted
	if depleted:
		return
	var fraction := clampf(float(remaining_units) / float(maxi(initial_units, 1)), 0.0, 1.0)
	var depletion_scale := 0.45 + 0.55 * fraction
	_mesh_instance.scale = Vector3(1.15, 0.78, 0.9) * depletion_scale


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
