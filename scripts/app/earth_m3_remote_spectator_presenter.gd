extends Node3D

const RemotePlayerPresenterScript = preload(
	"res://scripts/runtime/networked_gameplay/m3/remote_player_presenter.gd"
)

const POSITION_INTERPOLATION_SPEED := 12.0
const PLANAR_EPSILON := 0.000001

var _delegate
var _map_position: Callable
var _local_planar_position := Vector2.ZERO
var _presented_planar_position := Vector2.ZERO
var _target_planar_position := Vector2.ZERO
var earth_mapped_position := Vector3.ZERO


func setup(record: Dictionary, snapshot: Dictionary, map_position: Callable) -> Dictionary:
	if not map_position.is_valid():
		return {"success": false, "error_code": "EARTH_POSITION_MAPPER_REQUIRED"}
	_map_position = map_position
	_delegate = RemotePlayerPresenterScript.new()
	# The delegate updates yaw before this wrapper maps the interpolated planar
	# position onto the curved Earth surface.
	_delegate.process_priority = -1
	add_child(_delegate)
	var result: Dictionary = _delegate.setup(record, snapshot)
	if not bool(result.get("success", false)):
		return result
	_target_planar_position = _record_planar_position(record)
	_presented_planar_position = _target_planar_position
	_delegate.position = Vector3.ZERO
	_apply_earth_position(_presented_planar_position)
	set_process(true)
	return {"success": true, "error_code": ""}


func apply_replica(record: Dictionary, snapshot: Dictionary) -> Dictionary:
	if _delegate == null:
		return {"success": false, "error_code": "EARTH_REMOTE_NOT_READY"}
	var result: Dictionary = _delegate.apply_replica(record, false, snapshot)
	if bool(result.get("success", false)):
		_target_planar_position = _record_planar_position(record)
	return result


func set_local_planar_position(value: Vector2) -> void:
	_local_planar_position = value
	if _delegate != null:
		_apply_earth_position(_presented_planar_position)


func _process(delta: float) -> void:
	if _delegate == null:
		return
	var weight := 1.0 - exp(-POSITION_INTERPOLATION_SPEED * maxf(delta, 0.0))
	_presented_planar_position = _presented_planar_position.lerp(
		_target_planar_position,
		clampf(weight, 0.0, 1.0)
	)
	_apply_earth_position(_presented_planar_position)
	# Translation belongs to this Earth wrapper. The reusable presenter remains
	# responsible only for its derived visual state and yaw interpolation.
	_delegate.position = Vector3.ZERO


func _record_planar_position(record: Dictionary) -> Vector2:
	var planar: Dictionary = record.get("position", {})
	return Vector2(
		float(planar.get("x", 0.0)),
		float(planar.get("z", 0.0))
	)


func _apply_earth_position(planar_position: Vector2) -> void:
	var remote_position: Vector3 = _map_position.call(
		planar_position.x, planar_position.y
	)
	var local_position: Vector3 = _map_position.call(
		_local_planar_position.x, _local_planar_position.y
	)
	earth_mapped_position = remote_position
	position = remote_position - local_position
	_apply_surface_orientation(remote_position)


func _apply_surface_orientation(world_position: Vector3) -> void:
	if world_position.length_squared() < PLANAR_EPSILON:
		return
	var up := world_position.normalized()
	var east := Vector3.UP.cross(up)
	if east.length_squared() < PLANAR_EPSILON:
		east = Vector3.RIGHT.cross(up)
	east = east.normalized()
	var north := up.cross(east).normalized()
	basis = Basis(east, up, -north).orthonormalized()


func get_report() -> Dictionary:
	var report: Dictionary = _delegate.get_report() if _delegate != null else {}
	report["earth_mapped_position"] = [
		earth_mapped_position.x,
		earth_mapped_position.y,
		earth_mapped_position.z,
	]
	report["earth_planar_presented"] = [
		_presented_planar_position.x,
		_presented_planar_position.y,
	]
	report["earth_planar_target"] = [
		_target_planar_position.x,
		_target_planar_position.y,
	]
	report["input_authority"] = false
	return report
