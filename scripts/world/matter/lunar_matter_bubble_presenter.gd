extends Node3D

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const MesherScript = preload("res://scripts/world/matter/meshing/matter_tetrahedral_mesher.gd")
const MeshDataScript = preload("res://scripts/world/matter/meshing/matter_brick_mesh_data.gd")
const ResourceFactoryScript = preload(
	"res://scripts/world/matter/meshing/matter_mesh_resource_factory.gd"
)

var _configured := false
var _bubble = null
var _moon_world = null
var _with_collision := true
var _material: Material = null
var _presenters_by_address_id: Dictionary = {}


func configure(
	bubble,
	moon_world,
	with_collision: bool = true,
	material: Material = null
) -> Dictionary:
	if _configured:
		return MatterUtilsScript.failure("P7_LUNAR_MATTER_PRESENTER_ALREADY_CONFIGURED")
	if bubble == null or not bubble.has_method("materialize_presentation_level") 		or not bubble.has_method("grid_profile") 		or moon_world == null or not moon_world.has_method("world_to_render"):
		return MatterUtilsScript.failure("P7_LUNAR_MATTER_PRESENTER_DEPENDENCY_INVALID")
	_bubble = bubble
	_moon_world = moon_world
	_with_collision = with_collision
	_material = material if material != null 		else ResourceFactoryScript.create_vertex_color_material()
	_configured = true
	set_process(true)
	return rebuild_all()


func rebuild_all() -> Dictionary:
	if not _configured:
		return MatterUtilsScript.failure("P7_LUNAR_MATTER_PRESENTER_NOT_CONFIGURED")
	_clear_presenters()
	var snapshots: Array = _bubble.materialize_presentation_level()
	var built := 0
	var empty := 0
	for snapshot_value in snapshots:
		var snapshot: Dictionary = snapshot_value
		var result := _build_snapshot_presenter(snapshot)
		if not bool(result.get("success", false)):
			return result
		if String(result.get("details", {}).get("status", "")) == "EMPTY":
			empty += 1
		else:
			built += 1
	return MatterUtilsScript.success({
		"snapshot_count": snapshots.size(),
		"presenter_count": built,
		"empty_count": empty,
		"collision_enabled": _with_collision,
	})


func rebuild_address(address: Dictionary) -> Dictionary:
	if not _configured:
		return MatterUtilsScript.failure("P7_LUNAR_MATTER_PRESENTER_NOT_CONFIGURED")
	var store = _bubble.snapshot_store()
	if store == null or not store.has(address):
		return MatterUtilsScript.failure("P7_LUNAR_MATTER_SNAPSHOT_NOT_MATERIALIZED")
	var address_id := String(address.get("address_id", ""))
	_remove_presenter(address_id)
	return _build_snapshot_presenter(store.get_snapshot(address))


func presenter_count() -> int:
	return _presenters_by_address_id.size()


func contract_report() -> Dictionary:
	return {
		"configured": _configured,
		"presenter_count": presenter_count(),
		"collision_enabled": _with_collision,
		"geometry_source": "MATTER_SNAPSHOT",
		"collision_source": "SAME_MATTER_MESH",
		"canonical_state_owned": false,
	}


func _process(_delta: float) -> void:
	if not _configured:
		return
	for address_id in _presenters_by_address_id.keys():
		var presenter = _presenters_by_address_id[address_id]
		if presenter == null or not is_instance_valid(presenter):
			continue
		var origin_value = presenter.get_meta("p7_body_fixed_origin_m", [])
		if typeof(origin_value) != TYPE_ARRAY or Array(origin_value).size() != 3:
			continue
		presenter.position = _moon_world.world_to_render(_vector3(origin_value))


func _build_snapshot_presenter(snapshot: Dictionary) -> Dictionary:
	var grid := _bubble.grid_profile()
	var mesh_data: Dictionary = MesherScript.build_mesh_data(snapshot, grid)
	var validation := MeshDataScript.validate(mesh_data)
	if not bool(validation.get("success", false)):
		return validation
	if String(mesh_data["status"]) == MeshDataScript.STATUS_EMPTY:
		return MatterUtilsScript.success({"status": "EMPTY"})
	var presenter := ResourceFactoryScript.create_presenter(
		mesh_data, _material, _with_collision
	)
	if presenter == null:
		return MatterUtilsScript.failure("P7_LUNAR_MATTER_PRESENTER_BUILD_FAILED")
	var address_id := String(snapshot["address"]["address_id"])
	var origin: Vector3 = mesh_data["origin_body_local_m"]
	presenter.set_meta("p7_body_fixed_origin_m", [origin.x, origin.y, origin.z])
	presenter.set_meta("p7_matter_address_id", address_id)
	presenter.position = _moon_world.world_to_render(origin)
	add_child(presenter)
	_presenters_by_address_id[address_id] = presenter
	return MatterUtilsScript.success({
		"status": "BUILT",
		"address_id": address_id,
		"triangle_count": int(mesh_data["triangle_count"]),
	})


func _remove_presenter(address_id: String) -> void:
	if not _presenters_by_address_id.has(address_id):
		return
	var presenter = _presenters_by_address_id[address_id]
	_presenters_by_address_id.erase(address_id)
	if presenter != null and is_instance_valid(presenter):
		presenter.queue_free()


func _clear_presenters() -> void:
	for address_id in _presenters_by_address_id.keys():
		var presenter = _presenters_by_address_id[address_id]
		if presenter != null and is_instance_valid(presenter):
			presenter.queue_free()
	_presenters_by_address_id.clear()


static func _vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
