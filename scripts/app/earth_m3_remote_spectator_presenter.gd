extends Node3D

const RemotePlayerPresenterScript = preload(
	"res://scripts/runtime/networked_gameplay/m3/remote_player_presenter.gd"
)

var _delegate
var _map_position: Callable
var _planar_position := Vector2.ZERO
var earth_mapped_position := Vector3.ZERO


func setup(record: Dictionary, snapshot: Dictionary, map_position: Callable) -> Dictionary:
	if not map_position.is_valid():
		return {"success": false, "error_code": "EARTH_POSITION_MAPPER_REQUIRED"}
	_map_position = map_position
	_delegate = RemotePlayerPresenterScript.new()
	_delegate.process_priority = -1
	add_child(_delegate)
	var result: Dictionary = _delegate.setup(record, snapshot)
	if not bool(result.get("success", false)):
		return result
	_apply_earth_position(record)
	set_process(true)
	return {"success": true, "error_code": ""}


func apply_replica(record: Dictionary, snapshot: Dictionary) -> Dictionary:
	if _delegate == null:
		return {"success": false, "error_code": "EARTH_REMOTE_NOT_READY"}
	var result: Dictionary = _delegate.apply_replica(record, false, snapshot)
	if bool(result.get("success", false)):
		_apply_earth_position(record)
	return result


func set_local_planar_position(value: Vector2) -> void:
	_planar_position = value
	if _delegate != null:
		_apply_earth_position({
			"position": {
				"x": _delegate.target_position.x,
				"z": _delegate.target_position.z,
			},
		})


func _process(_delta: float) -> void:
	if _delegate != null:
		# The reusable M3 presenter interpolates its own planar transform.  It is a
		# child here; the Earth wrapper owns the actual render-space transform.
		_delegate.position = Vector3.ZERO


func _apply_earth_position(record: Dictionary) -> void:
	var planar: Dictionary = record.get("position", {})
	var remote_position: Vector3 = _map_position.call(
		float(planar.get("x", 0.0)), float(planar.get("z", 0.0))
	)
	var local_position: Vector3 = _map_position.call(
		_planar_position.x, _planar_position.y
	)
	earth_mapped_position = remote_position
	position = remote_position - local_position
	if _delegate != null:
		_delegate.position = Vector3.ZERO


func get_report() -> Dictionary:
	var report: Dictionary = _delegate.get_report() if _delegate != null else {}
	report["earth_mapped_position"] = [
		earth_mapped_position.x,
		earth_mapped_position.y,
		earth_mapped_position.z,
	]
	report["input_authority"] = false
	return report
