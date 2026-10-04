extends Node3D

const RemotePlayerPresenterScript = preload(
	"res://scripts/runtime/networked_gameplay/m3/remote_player_presenter.gd"
)
const EarthSurfaceRenderProjectorScript = preload(
	"res://scripts/app/earth_surface_render_projector.gd"
)
const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")

const VISUAL_VERTICAL_OFFSET_M := -0.85
const PLANAR_EPSILON := 0.000001

var _delegate
var _map_position: Callable
var _local_planar_position := Vector2.ZERO
var _local_vertical_offset_m := 0.0
var _presented_planar_position := Vector2.ZERO
var _presented_vertical_offset_m := 0.0
var _target_planar_position := Vector2.ZERO
var _target_vertical_offset_m := 0.0
var earth_mapped_position := Vector3.ZERO
var _render_frame_ready := false
var _render_projection_updates := 0
var _last_render_origin_world := Vector3.ZERO
var _last_snapshot_arrival_ms := -1
var _max_snapshot_interval_ms := 0
var _render_frames := 0
var _long_render_frames := 0
var _max_render_delta_ms := 0.0
# These are presentation-stage observations, NOT raw network packet timestamps.
var _presenter_arrivals := 0
var _last_presenter_arrival_ms := -1
var _max_presenter_arrival_interval_ms := 0
var _accepted_presenter_samples := 0
var _duplicate_presenter_samples := 0
var _stale_presenter_samples := 0
var _rejected_presenter_samples := 0
var _last_snapshot_context: Dictionary = {}
var _sample_mode_time_ms: Dictionary = {}


func setup(record: Dictionary, snapshot: Dictionary, map_position: Callable) -> Dictionary:
	if not map_position.is_valid():
		return {"success": false, "error_code": "EARTH_POSITION_MAPPER_REQUIRED"}
	var normalized := _normalize_snapshot_context(snapshot)
	if not bool(normalized.get("success", false)):
		return normalized
	_map_position = map_position
	# NX5 samples once per render frame. Applying engine physics interpolation
	# to the same floating-origin transforms would interpolate them a second
	# time. Limit the exception to this derived visual subtree, not world physics.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_delegate = RemotePlayerPresenterScript.new()
	_delegate.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Sample before the wrapper, then project using the current Earth origin.
	_delegate.process_priority = -1
	process_priority = 1
	add_child(_delegate)
	var context: Dictionary = normalized.get("context", {})
	var result: Dictionary = _delegate.setup(record, context)
	if not bool(result.get("success", false)):
		return result
	_last_snapshot_context = context.duplicate(true)
	_record_presenter_arrival()
	_last_snapshot_arrival_ms = Time.get_ticks_msec()
	_accepted_presenter_samples += 1
	_capture_delegate_positions()
	_apply_earth_position()
	_apply_delegate_visual_offset()
	set_process(true)
	return {"success": true, "error_code": ""}


func apply_replica(record: Dictionary, snapshot: Dictionary) -> Dictionary:
	if _delegate == null:
		return {"success": false, "error_code": "EARTH_REMOTE_NOT_READY"}
	_record_presenter_arrival()
	var normalized := _normalize_snapshot_context(snapshot)
	if not bool(normalized.get("success", false)):
		_rejected_presenter_samples += 1
		return normalized
	var context: Dictionary = normalized.get("context", {})
	var result: Dictionary = _delegate.apply_replica(record, false, context)
	if bool(result.get("success", false)):
		var details: Dictionary = result.get("details", {})
		if bool(details.get("stale", false)):
			_stale_presenter_samples += 1
		else:
			_last_snapshot_context = context.duplicate(true)
		_target_planar_position = Vector2(
			_delegate.target_position.x,
			_delegate.target_position.z
		)
		_target_vertical_offset_m = maxf(_delegate.target_position.y, 0.0)
		if bool(details.get("duplicate", false)):
			_duplicate_presenter_samples += 1
		if bool(details.get("accepted", false)):
			_accepted_presenter_samples += 1
			var now_ms := Time.get_ticks_msec()
			if _last_snapshot_arrival_ms >= 0:
				_max_snapshot_interval_ms = maxi(
					_max_snapshot_interval_ms, now_ms - _last_snapshot_arrival_ms
				)
			_last_snapshot_arrival_ms = now_ms
	else:
		_rejected_presenter_samples += 1
	return result


func _normalize_snapshot_context(snapshot: Dictionary) -> Dictionary:
	# PlayerStateSnapshot's canonical wire field is "revision". NX5's compact
	# context uses "snapshot_revision". Passing the raw envelope to the delegate
	# previously caused its legacy fallback to invent time from state_revision:
	# the delegate's parent is this wrapper, not the app that owns the runtime.
	# Never let a production Earth snapshot use that synthetic fallback clock.
	if snapshot.has("revision") and snapshot.has("snapshot_revision"):
		if snapshot["revision"] != snapshot["snapshot_revision"]:
			return {"success": false, "error_code": "EARTH_REMOTE_AMBIGUOUS_SNAPSHOT_REVISION"}
	var revision_value = snapshot.get("snapshot_revision", snapshot.get("revision", -1))
	var tick_value = snapshot.get("server_tick", -1)
	var epoch_value = snapshot.get("authority_epoch", 0)
	for value in [revision_value, tick_value, epoch_value]:
		if not NetworkUtils.is_json_integer(value):
			return {"success": false, "error_code": "EARTH_REMOTE_INVALID_SNAPSHOT_CLOCK"}
	if int(revision_value) < 0 or int(tick_value) < 0 or int(epoch_value) < 1:
		return {"success": false, "error_code": "EARTH_REMOTE_INVALID_SNAPSHOT_CLOCK"}
	return {
		"success": true,
		"error_code": "",
		"context": {
			"server_tick": int(tick_value),
			"snapshot_revision": int(revision_value),
			"authority_epoch": int(epoch_value),
		},
	}


func _record_presenter_arrival() -> void:
	var now_ms := Time.get_ticks_msec()
	if _last_presenter_arrival_ms >= 0:
		_max_presenter_arrival_interval_ms = maxi(
			_max_presenter_arrival_interval_ms, now_ms - _last_presenter_arrival_ms
		)
	_last_presenter_arrival_ms = now_ms
	_presenter_arrivals += 1


func set_local_planar_position(value: Vector2) -> void:
	_local_planar_position = value
	if _delegate != null:
		_apply_earth_position()


func set_local_vertical_offset(value: float) -> void:
	_local_vertical_offset_m = maxf(value, 0.0)
	if _delegate != null:
		_apply_earth_position()


func _process(delta: float) -> void:
	if _delegate == null:
		return
	_render_frames += 1
	_max_render_delta_ms = maxf(_max_render_delta_ms, maxf(delta, 0.0) * 1000.0)
	if delta > 0.1:
		_long_render_frames += 1
	# Weight by elapsed render time, not the number of frames. This makes
	# 60fps/144fps/240fps measurements comparable without tuning smoothing.
	var sample_mode := String(_delegate._last_mode)
	_sample_mode_time_ms[sample_mode] = (
		float(_sample_mode_time_ms.get(sample_mode, 0.0)) + maxf(delta, 0.0) * 1000.0
	)
	_capture_delegate_positions()
	_apply_earth_position()
	_apply_delegate_visual_offset()


func _capture_delegate_positions() -> void:
	if _delegate == null:
		return
	# Never read back the visual offset written in the preceding frame as a
	# logical network position. The sample remains valid even if the delegate
	# did not advance (pause, missing packet, manual projection or zero delta).
	var sampled: Vector3 = _delegate.get_presented_position()
	_presented_planar_position = Vector2(sampled.x, sampled.z)
	_presented_vertical_offset_m = maxf(sampled.y, 0.0)
	_target_planar_position = Vector2(
		_delegate.target_position.x,
		_delegate.target_position.z
	)
	_target_vertical_offset_m = maxf(_delegate.target_position.y, 0.0)


func _apply_delegate_visual_offset() -> void:
	if _delegate != null:
		_delegate.position = Vector3(0.0, VISUAL_VERTICAL_OFFSET_M, 0.0)


func _apply_earth_position() -> void:
	var remote_base: Vector3 = _map_position.call(
		_presented_planar_position.x,
		_presented_planar_position.y
	)
	var remote_position := remote_base
	if remote_base.length_squared() > PLANAR_EPSILON:
		remote_position += remote_base.normalized() * _presented_vertical_offset_m
	earth_mapped_position = remote_position

	var render_frame: Dictionary = _resolve_earth_render_frame()
	if not render_frame.is_empty():
		var canonical_anchor := EarthSurfaceRenderProjectorScript.create_surface_anchor(
			remote_base,
			_presented_vertical_offset_m
		)
		var render_origin_world: Vector3 = render_frame["render_origin_world"]
		var earth_fixed_to_render: Basis = render_frame["earth_fixed_to_render"]
		var projected := EarthSurfaceRenderProjectorScript.project_anchor(
			canonical_anchor,
			render_origin_world,
			earth_fixed_to_render
		)
		position = projected.origin
		basis = projected.basis
		_render_frame_ready = true
		_last_render_origin_world = render_origin_world
		_render_projection_updates += 1
		return

	# Isolated-presenter compatibility path; production uses the shared frame.
	var local_base: Vector3 = _map_position.call(
		_local_planar_position.x,
		_local_planar_position.y
	)
	var local_position := local_base
	if local_base.length_squared() > PLANAR_EPSILON:
		local_position += local_base.normalized() * _local_vertical_offset_m
	position = remote_position - local_position
	_apply_surface_orientation(remote_position)
	_render_frame_ready = false


func _resolve_earth_render_frame() -> Dictionary:
	var host := get_parent()
	if host == null:
		return {}
	var world = host.get("earth_world")
	if world == null or not is_instance_valid(world):
		return {}
	if not world.has_method("get_render_origin"):
		return {}
	return {
		"render_origin_world": world.get_render_origin(),
		"earth_fixed_to_render": world.basis,
	}


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
	report["position"] = [
		_presented_planar_position.x,
		_presented_vertical_offset_m,
		_presented_planar_position.y,
	]
	report["earth_mapped_position"] = [earth_mapped_position.x, earth_mapped_position.y, earth_mapped_position.z]
	report["earth_planar_presented"] = [_presented_planar_position.x, _presented_planar_position.y]
	report["earth_planar_target"] = [_target_planar_position.x, _target_planar_position.y]
	report["earth_vertical_presented_m"] = _presented_vertical_offset_m
	report["earth_vertical_target_m"] = _target_vertical_offset_m
	report["earth_local_vertical_offset_m"] = _local_vertical_offset_m
	report["earth_visual_vertical_offset_m"] = VISUAL_VERTICAL_OFFSET_M
	report["render_frame_ready"] = _render_frame_ready
	report["render_projection_updates"] = _render_projection_updates
	report["render_origin_world"] = [_last_render_origin_world.x, _last_render_origin_world.y, _last_render_origin_world.z]
	report["spatial_projection"] = (
		"EARTH_FIXED_TO_SHARED_RENDER_FRAME"
		if _render_frame_ready
		else "LEGACY_LOCAL_PLAYER_RELATIVE"
	)
	report["input_authority"] = false
	report["presentation_owner"] = "NX5_RENDER_SAMPLE"
	# Keep the legacy field, but make its measurement boundary explicit.
	report["max_snapshot_interval_ms"] = _max_snapshot_interval_ms
	report["max_accepted_sample_interval_ms"] = _max_snapshot_interval_ms
	report["max_presenter_arrival_interval_ms"] = _max_presenter_arrival_interval_ms
	report["snapshot_clock_source"] = "CANONICAL_SNAPSHOT_CONTEXT"
	report["snapshot_clock_context"] = _last_snapshot_context.duplicate(true)
	report["presenter_arrivals"] = _presenter_arrivals
	report["accepted_presenter_samples"] = _accepted_presenter_samples
	report["duplicate_presenter_samples"] = _duplicate_presenter_samples
	report["stale_presenter_samples"] = _stale_presenter_samples
	report["rejected_presenter_samples"] = _rejected_presenter_samples
	report["sample_mode_time_ms"] = _sample_mode_time_ms.duplicate(true)
	report["render_frames"] = _render_frames
	report["long_render_frames"] = _long_render_frames
	report["max_render_delta_ms"] = _max_render_delta_ms
	return report
