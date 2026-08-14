extends Node3D

const RemotePlayerPresenterScript = preload(
	"res://scripts/runtime/networked_gameplay/m3/remote_player_presenter.gd"
)

const VISUAL_VERTICAL_OFFSET_M := -0.85
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
	# The reusable presenter owns server-tick buffering/interpolation. Run it
	# first; this wrapper consumes its sampled planar position afterwards.
	_delegate.process_priority = -1
	add_child(_delegate)
	var result: Dictionary = _delegate.setup(record, snapshot)
	if not bool(result.get("success", false)):
		return result
	_capture_delegate_positions()
	_apply_earth_position(_presented_planar_position)
	_apply_delegate_visual_offset()
	set_process(true)
	return {"success": true, "error_code": ""}


func apply_replica(record: Dictionary, snapshot: Dictionary) -> Dictionary:
	if _delegate == null:
		return {"success": false, "error_code": "EARTH_REMOTE_NOT_READY"}
	var result: Dictionary = _delegate.apply_replica(record, false, snapshot)
	if bool(result.get("success", false)):
		_target_planar_position = Vector2(
			_delegate.target_position.x,
			_delegate.target_position.z
		)
	return result


func set_local_planar_position(value: Vector2) -> void:
	_local_planar_position = value
	if _delegate != null:
		_apply_earth_position(_presented_planar_position)


func _process(_delta: float) -> void:
	if _delegate == null:
		return
	# RemotePlayerPresenter has already sampled RemoteSnapshotInterpolator during
	# its earlier process priority. Read that authoritative derived sample before
	# replacing the delegate translation with the local visual body offset.
	_capture_delegate_positions()
	_apply_earth_position(_presented_planar_position)
	_apply_delegate_visual_offset()


func _capture_delegate_positions() -> void:
	if _delegate == null:
		return
	_presented_planar_position = Vector2(
		_delegate.position.x,
		_delegate.position.z
	)
	_target_planar_position = Vector2(
		_delegate.target_position.x,
		_delegate.target_position.z
	)


func _apply_delegate_visual_offset() -> void:
	if _delegate != null:
		# The Earth mapper places the observer origin at eye height. Lower only the
		# remote capsule visual so its feet sit on the generated terrain.
		_delegate.position = Vector3(0.0, VISUAL_VERTICAL_OFFSET_M, 0.0)


func _apply_earth_position(planar_position: Vector2) -> void:
	var remote_position: Vector3 = _map_position.call(
		planar_position.x,
		planar_position.y
	)
	var local_position: Vector3 = _map_position.call(
		_local_planar_position.x,
		_local_planar_position.y
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
	# The delegate node itself is intentionally recentered under this wrapper,
	# so expose its logical interpolated planar position rather than that local
	# visual offset in the public derived-presentation report.
	report["position"] = [
		_presented_planar_position.x,
		0.0,
		_presented_planar_position.y,
	]
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
	report["earth_visual_vertical_offset_m"] = VISUAL_VERTICAL_OFFSET_M
	report["input_authority"] = false
	return report
