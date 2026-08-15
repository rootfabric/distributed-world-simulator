extends Area3D

const INTERACTABLE_GROUP: StringName = &"world_interactable"
const INTERACTION_COLLISION_LAYER := 1 << 19
const RESULT_SCHEMA := "planet_simulator.i2s_world_item_target_result.v1"

var canonical_item_id: String = ""
var canonical_definition_id: String = ""
var canonical_quantity: int = 0
var external_container_id: String = ""
var _runtime
var _mesh_instance: MeshInstance3D
var _collision_shape: CollisionShape3D


func setup(runtime_reference, item_record: Dictionary, container_id: String = "") -> Dictionary:
	if runtime_reference == null or not runtime_reference.has_method("interact_world_item"):
		return _failure("I2S_INTERACTION_RUNTIME_REQUIRED")
	_runtime = runtime_reference
	# Presentation hit testing must never become gameplay collision. An Area3D
	# on a dedicated high layer lets the client ray-query it without blocking the
	# CharacterBody or changing any canonical physics/authority surface.
	collision_layer = INTERACTION_COLLISION_LAYER
	collision_mask = 0
	monitoring = false
	if not is_in_group(INTERACTABLE_GROUP):
		add_to_group(INTERACTABLE_GROUP)
	_ensure_nodes()
	return apply_canonical_record(item_record, container_id)


func apply_canonical_record(item_record: Dictionary, container_id: String = "") -> Dictionary:
	var next_item_id := String(item_record.get("item_id", "")).strip_edges().to_lower()
	var definition_id := String(item_record.get("definition_id", "")).strip_edges()
	var quantity := int(item_record.get("quantity", 0))
	if next_item_id.is_empty() or definition_id.is_empty() or quantity < 1:
		return _failure("I2S_INVALID_CANONICAL_ITEM_RECORD")
	if not canonical_item_id.is_empty() and canonical_item_id != next_item_id:
		return _failure("I2S_PRESENTATION_IDENTITY_MISMATCH")
	canonical_item_id = next_item_id
	canonical_definition_id = definition_id
	canonical_quantity = quantity
	external_container_id = container_id.strip_edges().to_lower()
	name = "CanonicalWorldItem_%s" % canonical_item_id.replace("/", "_")
	_apply_primitive_shape()
	return _success({
		"item_id": canonical_item_id,
		"container_id": external_container_id,
	})


func get_canonical_item_id() -> String:
	return canonical_item_id


func get_external_container_id() -> String:
	return external_container_id


func get_interaction_descriptor(_actor = null) -> Dictionary:
	var is_container := not external_container_id.is_empty()
	return {
		"id": "i2s/%s" % canonical_item_id,
		"type": "external_container" if is_container else "world_item",
		"canonical_item_id": canonical_item_id,
		"container_id": external_container_id,
		"definition_id": canonical_definition_id,
		"quantity": canonical_quantity,
		"prompt": "Открыть контейнер" if is_container else "Подобрать",
	}


func interact(_actor = null, context: Dictionary = {}) -> Dictionary:
	if _runtime == null or not is_instance_valid(_runtime):
		return _failure("I2S_INTERACTION_RUNTIME_UNAVAILABLE")
	if canonical_item_id.is_empty():
		return _failure("I2S_PRESENTATION_IDENTITY_MISSING")
	return _runtime.interact_world_item(canonical_item_id, context)


func set_interaction_focus(focused: bool) -> void:
	if _mesh_instance != null:
		_mesh_instance.scale = Vector3.ONE * (1.08 if focused else 1.0)


func _ensure_nodes() -> void:
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "Presentation"
		add_child(_mesh_instance)
	if _collision_shape == null:
		_collision_shape = CollisionShape3D.new()
		_collision_shape.name = "InteractionCollision"
		add_child(_collision_shape)


func _apply_primitive_shape() -> void:
	_ensure_nodes()
	if canonical_definition_id == "item/crate":
		var crate_mesh := BoxMesh.new()
		crate_mesh.size = Vector3(0.9, 0.7, 0.9)
		_mesh_instance.mesh = crate_mesh
		var crate_shape := BoxShape3D.new()
		crate_shape.size = crate_mesh.size
		_collision_shape.shape = crate_shape
		_apply_material(Color(0.52, 0.31, 0.13), false)
		return
	if canonical_definition_id == "item/beacon":
		var beacon_mesh := CylinderMesh.new()
		beacon_mesh.top_radius = 0.12
		beacon_mesh.bottom_radius = 0.18
		beacon_mesh.height = 0.42
		_mesh_instance.mesh = beacon_mesh
		var beacon_shape := CylinderShape3D.new()
		beacon_shape.radius = 0.18
		beacon_shape.height = 0.42
		_collision_shape.shape = beacon_shape
		_apply_material(Color(0.15, 0.78, 0.95), true)
		return
	if canonical_definition_id == "item/ore":
		var ore_mesh := SphereMesh.new()
		ore_mesh.radius = 0.25
		ore_mesh.height = 0.5
		_mesh_instance.mesh = ore_mesh
		var ore_shape := SphereShape3D.new()
		ore_shape.radius = 0.25
		_collision_shape.shape = ore_shape
		_apply_material(Color(0.55, 0.43, 0.28), false)
		return
	var item_mesh := SphereMesh.new()
	item_mesh.radius = 0.22
	item_mesh.height = 0.44
	_mesh_instance.mesh = item_mesh
	var item_shape := SphereShape3D.new()
	item_shape.radius = 0.22
	_collision_shape.shape = item_shape
	_apply_material(Color(0.58, 0.72, 0.58), false)


func _apply_material(color: Color, emissive: bool) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.15
	material.roughness = 0.55
	material.emission_enabled = emissive
	material.emission = color
	_mesh_instance.material_override = material


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
