extends Node

signal stream_test_completed(summary: Dictionary)

const CONFIG_PATH: String = "res://config/terrain_streaming.json"
const DEFAULT_CELL_SIZE_M: float = 512.0
const DEFAULT_PREDICTION_SECONDS: float = 6.0
const DEFAULT_MAX_PREDICTION_DISTANCE_M: float = 420.0
const DEFAULT_LONG_FRAME_THRESHOLD_MS: float = 50.0
const DEFAULT_SUMMARY_INTERVAL_SEC: float = 10.0
const DEFAULT_COMMIT_BUDGET_MS: float = 3.0
const DEFAULT_MAX_HISTORY: int = 40

var terrain
var worker_sampler
var logger

var enabled: bool = true
var stream_cell_size_m: float = DEFAULT_CELL_SIZE_M
var prediction_seconds: float = DEFAULT_PREDICTION_SECONDS
var max_prediction_distance_m: float = DEFAULT_MAX_PREDICTION_DISTANCE_M
var long_frame_threshold_ms: float = DEFAULT_LONG_FRAME_THRESHOLD_MS
var summary_interval_sec: float = DEFAULT_SUMMARY_INTERVAL_SEC
var commit_budget_ms: float = DEFAULT_COMMIT_BUDGET_MS
var max_history: int = DEFAULT_MAX_HISTORY

var result_mutex := Mutex.new()
var completed_results: Array[Dictionary] = []
var task_id: int = -1
var running_request: Dictionary = {}
var pending_request: Dictionary = {}
var latest_revision: int = 0
var cancelled_through_revision: int = 0
var active_cell_id: String = "-"
var target_cell_id: String = "-"
var state: String = "IDLE"

var commit_result: Dictionary = {}
var staging: Dictionary = {}
var commit_stage: int = -1
var rock_stage_index: int = 0
var commit_started_usec: int = 0
var commit_stage_timings: Dictionary = {}
var commit_max_stage_ms: float = 0.0

var performance_history: Array[Dictionary] = []
var max_observed_frame_ms: float = 0.0
var last_long_frame_log_msec: int = 0
var summary_accumulator: float = 0.0
var cancelled_result_count: int = 0
var completed_job_count: int = 0
var committed_surface_count: int = 0
var missed_deadline_count: int = 0
var current_test_revision: int = -1
var current_test_started_msec: int = 0
var current_test_max_frame_ms: float = 0.0
var last_test_result: String = "Не запускался"


func setup(terrain_reference, worker_sampler_reference, logger_reference = null) -> void:
	terrain = terrain_reference
	worker_sampler = worker_sampler_reference
	logger = logger_reference
	_load_config()
	set_process(true)
	_log_performance("streaming_manager_started", {
		"enabled": enabled,
		"stream_cell_size_m": stream_cell_size_m,
		"prediction_seconds": prediction_seconds,
		"max_prediction_distance_m": max_prediction_distance_m,
		"long_frame_threshold_ms": long_frame_threshold_ms,
		"commit_budget_ms": commit_budget_ms,
	})


func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return
	var config: Dictionary = parsed
	enabled = bool(config.get("enabled", enabled))
	stream_cell_size_m = maxf(32.0, float(config.get("stream_cell_size_m", stream_cell_size_m)))
	prediction_seconds = maxf(0.0, float(config.get("prediction_seconds", prediction_seconds)))
	max_prediction_distance_m = maxf(
		stream_cell_size_m * 0.25,
		float(config.get("max_prediction_distance_m", max_prediction_distance_m))
	)
	long_frame_threshold_ms = maxf(10.0, float(config.get("long_frame_threshold_ms", long_frame_threshold_ms)))
	summary_interval_sec = maxf(2.0, float(config.get("performance_summary_interval_sec", summary_interval_sec)))
	commit_budget_ms = maxf(0.5, float(config.get("main_thread_commit_budget_ms", commit_budget_ms)))
	max_history = maxi(10, int(config.get("max_performance_history", max_history)))


func is_enabled() -> bool:
	return enabled


func mark_active_surface(center_direction: Vector3) -> void:
	active_cell_id = _cell_id(center_direction)
	target_cell_id = active_cell_id
	if state == "IDLE":
		state = "ACTIVE"


func cancel_all(reason: String) -> void:
	if not running_request.is_empty():
		cancelled_through_revision = maxi(
			cancelled_through_revision,
			int(running_request.get("generation_revision", latest_revision))
		)
	latest_revision += 1
	pending_request.clear()
	if not running_request.is_empty():
		_log_performance("terrain_job_marked_stale", {
			"reason": reason,
			"request_id": running_request.get("request_id", -1),
			"cell_id": running_request.get("cell_id", "-"),
		})
	if commit_stage >= 0:
		commit_result.clear()
		staging.clear()
		commit_stage = -1
		rock_stage_index = 0
	state = "ACTIVE"


func request_predicted_surface(
	world_position: Vector3,
	world_velocity: Vector3,
	include_collision: bool,
	include_medium: bool,
	reason: String
) -> int:
	if world_position.length_squared() < 1.0:
		return -1
	var radial_up: Vector3 = world_position.normalized()
	var tangential_velocity: Vector3 = world_velocity.slide(radial_up)
	var speed: float = tangential_velocity.length()
	var prediction_distance: float = minf(
		speed * prediction_seconds,
		max_prediction_distance_m
	)
	var predicted_position: Vector3 = world_position
	if speed > 0.05 and prediction_distance > 0.0:
		predicted_position += tangential_velocity / speed * prediction_distance
	return request_surface(
		predicted_position.normalized(),
		include_collision,
		include_medium,
		reason,
		1,
		false,
		{
			"speed_mps": speed,
			"prediction_distance_m": prediction_distance,
		}
	)


func request_surface(
	center_direction: Vector3,
	include_collision: bool,
	include_medium: bool,
	reason: String,
	priority: int = 1,
	force: bool = false,
	extra: Dictionary = {}
) -> int:
	if not enabled or worker_sampler == null:
		return -1
	var target_direction: Vector3 = _cell_center_direction(center_direction)
	var cell_id: String = _cell_id(target_direction)
	if not force:
		if cell_id == active_cell_id:
			return -1
		if not running_request.is_empty() and String(running_request.get("cell_id", "")) == cell_id:
			return int(running_request.get("request_id", -1))
		if not pending_request.is_empty() and String(pending_request.get("cell_id", "")) == cell_id:
			return int(pending_request.get("request_id", -1))
		if commit_stage >= 0 and String(commit_result.get("cell_id", "")) == cell_id:
			return int(commit_result.get("request_id", -1))

	latest_revision += 1
	var request: Dictionary = {
		"schema": "lunar.terrain_build_request.v1",
		"request_id": latest_revision,
		"generation_revision": latest_revision,
		"cell_id": cell_id,
		"center_direction": target_direction,
		"include_collision": include_collision,
		"include_medium": include_medium,
		"reason": reason,
		"priority": priority,
		"requested_ticks_usec": Time.get_ticks_usec(),
		"extra": extra.duplicate(true),
	}
	target_cell_id = cell_id
	if task_id >= 0 or commit_stage >= 0:
		if not pending_request.is_empty():
			_log_performance("terrain_pending_request_replaced", {
				"old_request_id": pending_request.get("request_id", -1),
				"old_cell_id": pending_request.get("cell_id", "-"),
				"new_request_id": request.get("request_id", -1),
				"new_cell_id": cell_id,
			})
		pending_request = request
		state = "QUEUED"
	else:
		_launch_request(request)
	return latest_revision


func run_mini_test(world_position: Vector3, forward_world: Vector3) -> Dictionary:
	if world_position.length_squared() < 1.0:
		last_test_result = "FAIL: неверная позиция"
		return {"passed": false, "summary": last_test_result}
	var up: Vector3 = world_position.normalized()
	var tangent: Vector3 = forward_world.slide(up)
	if tangent.length_squared() < 0.0001:
		tangent = _make_east(up)
	tangent = tangent.normalized()
	var target_direction: Vector3 = (
		up + tangent * (stream_cell_size_m * 1.15 / terrain.get_moon_radius())
	).normalized()
	current_test_started_msec = Time.get_ticks_msec()
	current_test_max_frame_ms = 0.0
	current_test_revision = request_surface(
		target_direction,
		true,
		false,
		"manual_streaming_mini_test",
		0,
		true,
		{"test": true}
	)
	if current_test_revision < 0:
		last_test_result = "FAIL: streaming выключен"
		return {"passed": false, "summary": last_test_result}
	last_test_result = "RUNNING: request %d" % current_test_revision
	return {
		"passed": true,
		"running": true,
		"request_id": current_test_revision,
		"summary": last_test_result,
	}


func _launch_request(request: Dictionary) -> void:
	running_request = request
	state = "GENERATING"
	target_cell_id = String(request.get("cell_id", "-"))
	_log_performance("terrain_job_started", {
		"request_id": request.get("request_id", -1),
		"cell_id": target_cell_id,
		"reason": request.get("reason", ""),
		"include_collision": request.get("include_collision", false),
		"include_medium": request.get("include_medium", false),
		"extra": request.get("extra", {}),
	})
	task_id = WorkerThreadPool.add_task(
		_execute_job.bind(request.duplicate(true)),
		false,
		"Lunar terrain %s" % target_cell_id
	)


func _execute_job(request: Dictionary) -> void:
	var result: Dictionary = worker_sampler.build_streaming_payload(request)
	result_mutex.lock()
	completed_results.append(result)
	result_mutex.unlock()


func _process(delta: float) -> void:
	_monitor_frame(delta)
	_drain_completed_results()
	if commit_stage >= 0:
		_advance_commit_one_stage()
	elif task_id < 0 and not pending_request.is_empty():
		var next_request: Dictionary = pending_request
		pending_request = {}
		_launch_request(next_request)
	summary_accumulator += delta
	if summary_accumulator >= summary_interval_sec:
		summary_accumulator = 0.0
		_log_performance("terrain_streaming_summary", create_snapshot())


func _monitor_frame(delta: float) -> void:
	var frame_ms: float = delta * 1000.0
	max_observed_frame_ms = maxf(max_observed_frame_ms, frame_ms)
	if current_test_revision >= 0:
		current_test_max_frame_ms = maxf(current_test_max_frame_ms, frame_ms)
	if frame_ms < long_frame_threshold_ms:
		return
	var now_msec: int = Time.get_ticks_msec()
	if now_msec - last_long_frame_log_msec < 350:
		return
	last_long_frame_log_msec = now_msec
	_log_performance("long_frame_detected", {
		"frame_ms": frame_ms,
		"threshold_ms": long_frame_threshold_ms,
		"state": state,
		"commit_stage": _commit_stage_name(commit_stage),
		"active_cell_id": active_cell_id,
		"target_cell_id": target_cell_id,
		"running_request_id": running_request.get("request_id", -1),
		"pending_request_id": pending_request.get("request_id", -1),
	})


func _drain_completed_results() -> void:
	var local_results: Array[Dictionary] = []
	result_mutex.lock()
	if not completed_results.is_empty():
		local_results = completed_results.duplicate(false)
		completed_results.clear()
	result_mutex.unlock()
	for result in local_results:
		if task_id >= 0:
			# The worker enqueues the result immediately before returning. Waiting here
			# normally lasts only a few microseconds and releases pool task metadata.
			WorkerThreadPool.wait_for_task_completion(task_id)
		task_id = -1
		running_request = {}
		completed_job_count += 1
		var revision: int = int(result.get("generation_revision", -1))
		if revision <= cancelled_through_revision:
			cancelled_result_count += 1
			_log_performance("terrain_job_discarded_cancelled", {
				"request_id": result.get("request_id", -1),
				"generation_revision": revision,
				"cancelled_through_revision": cancelled_through_revision,
				"cell_id": result.get("cell_id", "-"),
				"background_timings_ms": result.get("timings_ms", {}),
			})
			state = "ACTIVE"
			continue
		var wall_since_request_ms: float = float(
			Time.get_ticks_usec() - int(result.get("requested_ticks_usec", Time.get_ticks_usec()))
		) / 1000.0
		_log_performance("terrain_job_cpu_ready", {
			"request_id": result.get("request_id", -1),
			"cell_id": result.get("cell_id", "-"),
			"background_timings_ms": result.get("timings_ms", {}),
			"local_vertex_count": result.get("local_vertex_count", 0),
			"local_triangle_count": result.get("local_triangle_count", 0),
			"rock_instance_count": result.get("rock_instance_count", 0),
			"wall_since_request_ms": wall_since_request_ms,
		})
		_begin_commit(result)


func _begin_commit(result: Dictionary) -> void:
	commit_result = result
	staging = {
		"local_mesh": null,
		"local_instance": null,
		"medium_annulus_mesh": null,
		"medium_annulus_instance": null,
		"medium_full_mesh": null,
		"medium_full_instance": null,
		"collision_body": null,
		"rock_instances": [],
	}
	commit_stage = 0
	rock_stage_index = 0
	commit_started_usec = Time.get_ticks_usec()
	commit_stage_timings = {}
	commit_max_stage_ms = 0.0
	state = "COMMITTING"


func _advance_commit_one_stage() -> void:
	var stage_name: String = _commit_stage_name(commit_stage)
	var request_id: int = int(commit_result.get("request_id", -1))
	var cell_id: String = String(commit_result.get("cell_id", "-"))
	var started_usec: int = Time.get_ticks_usec()
	var should_finish: bool = false
	match commit_stage:
		0:
			staging["local_mesh"] = terrain.streaming_create_mesh(
				commit_result.get("local_mesh_data", {}),
				"local"
			)
			staging["local_instance"] = terrain.streaming_create_mesh_instance(
				"LocalHighDetail",
				staging["local_mesh"]
			)
			if staging["local_mesh"] == null or staging["local_instance"] == null:
				_fail_commit("local_mesh_creation_failed")
				return
			commit_stage = 1
		1:
			if bool(commit_result.get("include_medium", false)):
				staging["medium_annulus_mesh"] = terrain.streaming_create_mesh(
					commit_result.get("medium_annulus_data", {}),
					"regional"
				)
				staging["medium_annulus_instance"] = terrain.streaming_create_mesh_instance(
					"MediumAnnulus",
					staging["medium_annulus_mesh"]
				)
				if staging["medium_annulus_instance"] == null:
					_fail_commit("medium_annulus_creation_failed")
					return
			commit_stage = 2
		2:
			if bool(commit_result.get("include_medium", false)):
				staging["medium_full_mesh"] = terrain.streaming_create_mesh(
					commit_result.get("medium_full_data", {}),
					"regional"
				)
				staging["medium_full_instance"] = terrain.streaming_create_mesh_instance(
					"MediumFull",
					staging["medium_full_mesh"]
				)
				if staging["medium_full_instance"] == null:
					_fail_commit("medium_full_creation_failed")
					return
			commit_stage = 3
		3:
			if bool(commit_result.get("include_collision", false)):
				staging["collision_body"] = terrain.streaming_create_collision_body(
					staging.get("local_mesh")
				)
				if staging["collision_body"] == null:
					_fail_commit("collision_shape_creation_failed")
					return
			commit_stage = 4
		4:
			var layers: Array = commit_result.get("rock_layers", [])
			if rock_stage_index < layers.size():
				var rock_instance = terrain.streaming_create_rock_instance(
					layers[rock_stage_index]
				)
				if rock_instance != null:
					var staged_rocks: Array = staging.get("rock_instances", [])
					staged_rocks.append(rock_instance)
					staging["rock_instances"] = staged_rocks
				rock_stage_index += 1
			else:
				commit_stage = 5
		5:
			terrain.streaming_apply_swap(commit_result, staging)
			should_finish = true
		_:
			should_finish = true

	var elapsed_ms: float = float(Time.get_ticks_usec() - started_usec) / 1000.0
	commit_stage_timings[stage_name] = float(commit_stage_timings.get(stage_name, 0.0)) + elapsed_ms
	commit_max_stage_ms = maxf(commit_max_stage_ms, elapsed_ms)
	_log_performance("terrain_commit_stage", {
		"request_id": request_id,
		"cell_id": cell_id,
		"stage": stage_name,
		"duration_ms": elapsed_ms,
		"budget_ms": commit_budget_ms,
		"over_budget": elapsed_ms > commit_budget_ms,
		"rock_stage_index": rock_stage_index,
	})
	if should_finish:
		_finish_commit()


func _finish_commit() -> void:
	var result_copy: Dictionary = commit_result
	var total_commit_ms: float = float(Time.get_ticks_usec() - commit_started_usec) / 1000.0
	active_cell_id = String(result_copy.get("cell_id", active_cell_id))
	target_cell_id = active_cell_id
	committed_surface_count += 1
	state = "ACTIVE"
	var commit_cpu_sum_ms: float = 0.0
	for timing_value in commit_stage_timings.values():
		commit_cpu_sum_ms += float(timing_value)
	var request_to_swap_ms: float = float(
		Time.get_ticks_usec() - int(result_copy.get("requested_ticks_usec", Time.get_ticks_usec()))
	) / 1000.0
	var summary: Dictionary = {
		"request_id": result_copy.get("request_id", -1),
		"cell_id": active_cell_id,
		"reason": result_copy.get("reason", ""),
		"background_timings_ms": result_copy.get("timings_ms", {}),
		"commit_stage_timings_ms": commit_stage_timings.duplicate(true),
		"total_commit_ms": total_commit_ms,
		"commit_cpu_sum_ms": commit_cpu_sum_ms,
		"request_to_swap_ms": request_to_swap_ms,
		"max_commit_stage_ms": commit_max_stage_ms,
		"max_observed_frame_ms": max_observed_frame_ms,
		"test_max_frame_ms": current_test_max_frame_ms,
		"local_vertex_count": result_copy.get("local_vertex_count", 0),
		"local_triangle_count": result_copy.get("local_triangle_count", 0),
		"rock_instance_count": result_copy.get("rock_instance_count", 0),
	}
	_record_history(summary)
	_log_performance("terrain_surface_swapped", summary)
	var completed_revision: int = int(result_copy.get("generation_revision", -1))
	commit_result = {}
	staging = {}
	commit_stage = -1
	rock_stage_index = 0
	if completed_revision == current_test_revision:
		var test_duration_ms: int = Time.get_ticks_msec() - current_test_started_msec
		last_test_result = (
			"PASS: background %.1f ms, commit max %.1f ms, frame max %.1f ms"
			% [
				float(summary.get("background_timings_ms", {}).get("total_background_ms", 0.0)),
				commit_max_stage_ms,
				current_test_max_frame_ms,
			]
		)
		var test_summary: Dictionary = summary.duplicate(true)
		test_summary["passed"] = true
		test_summary["duration_ms"] = test_duration_ms
		test_summary["summary"] = last_test_result
		stream_test_completed.emit(test_summary)
		current_test_revision = -1


func _fail_commit(reason: String) -> void:
	var request_id: int = int(commit_result.get("request_id", -1))
	var cell_id: String = String(commit_result.get("cell_id", "-"))
	_log_performance("terrain_commit_failed", {
		"request_id": request_id,
		"cell_id": cell_id,
		"reason": reason,
		"commit_stage": _commit_stage_name(commit_stage),
		"background_timings_ms": commit_result.get("timings_ms", {}),
	})
	if request_id == current_test_revision:
		last_test_result = "FAIL: %s" % reason
		stream_test_completed.emit({
			"passed": false,
			"request_id": request_id,
			"cell_id": cell_id,
			"reason": reason,
			"summary": last_test_result,
		})
		current_test_revision = -1
	commit_result = {}
	staging = {}
	commit_stage = -1
	rock_stage_index = 0
	state = "ACTIVE"


func _record_history(entry: Dictionary) -> void:
	performance_history.append(entry.duplicate(true))
	while performance_history.size() > max_history:
		performance_history.pop_front()


func _commit_stage_name(stage: int) -> String:
	match stage:
		0:
			return "local_mesh_resource"
		1:
			return "medium_annulus_resource"
		2:
			return "medium_full_resource"
		3:
			return "collision_shape"
		4:
			return "rock_layer_%d" % rock_stage_index
		5:
			return "atomic_swap"
		_:
			return "idle"


func create_snapshot() -> Dictionary:
	return {
		"schema": "lunar.terrain_streaming_snapshot.v1",
		"enabled": enabled,
		"state": state,
		"active_cell_id": active_cell_id,
		"target_cell_id": target_cell_id,
		"running_request": _request_snapshot(running_request),
		"pending_request": _request_snapshot(pending_request),
		"commit_stage": _commit_stage_name(commit_stage),
		"rock_stage_index": rock_stage_index,
		"completed_job_count": completed_job_count,
		"committed_surface_count": committed_surface_count,
		"cancelled_result_count": cancelled_result_count,
		"cancelled_through_revision": cancelled_through_revision,
		"missed_deadline_count": missed_deadline_count,
		"max_observed_frame_ms": max_observed_frame_ms,
		"last_test_result": last_test_result,
		"performance_history": performance_history.duplicate(true),
		"config": {
			"stream_cell_size_m": stream_cell_size_m,
			"prediction_seconds": prediction_seconds,
			"max_prediction_distance_m": max_prediction_distance_m,
			"long_frame_threshold_ms": long_frame_threshold_ms,
			"commit_budget_ms": commit_budget_ms,
		},
	}


func get_runtime_summary() -> String:
	var running_id: int = int(running_request.get("request_id", -1))
	var pending_id: int = int(pending_request.get("request_id", -1))
	return "%s | %s → %s | job=%d pending=%d | frame max %.1f ms" % [
		state,
		active_cell_id,
		target_cell_id,
		running_id,
		pending_id,
		max_observed_frame_ms,
	]


func get_last_test_result() -> String:
	return last_test_result


func get_cell_descriptor(direction: Vector3) -> Dictionary:
	var center_direction: Vector3 = _cell_center_direction(direction)
	return {
		"cell_id": _cell_id(center_direction),
		"center_direction": center_direction,
		"cell_size_m": stream_cell_size_m,
	}


func _request_snapshot(request: Dictionary) -> Dictionary:
	if request.is_empty():
		return {}
	return {
		"request_id": request.get("request_id", -1),
		"cell_id": request.get("cell_id", "-"),
		"reason": request.get("reason", ""),
		"include_collision": request.get("include_collision", false),
		"include_medium": request.get("include_medium", false),
		"extra": request.get("extra", {}),
	}


func _cell_id(direction_value: Vector3) -> String:
	var direction: Vector3 = direction_value.normalized()
	var cell_angle: float = stream_cell_size_m / terrain.get_moon_radius()
	var latitude: float = asin(clampf(direction.y, -1.0, 1.0))
	var longitude: float = atan2(direction.z, direction.x)
	var lat_cell: int = floori(latitude / cell_angle)
	var lon_cell: int = floori(longitude / cell_angle)
	return "terrain/%d/%d" % [lat_cell, lon_cell]


func _cell_center_direction(direction_value: Vector3) -> Vector3:
	var direction: Vector3 = direction_value.normalized()
	var cell_angle: float = stream_cell_size_m / terrain.get_moon_radius()
	var latitude: float = asin(clampf(direction.y, -1.0, 1.0))
	var longitude: float = atan2(direction.z, direction.x)
	var lat_cell: int = floori(latitude / cell_angle)
	var lon_cell: int = floori(longitude / cell_angle)
	var center_latitude: float = (float(lat_cell) + 0.5) * cell_angle
	var center_longitude: float = (float(lon_cell) + 0.5) * cell_angle
	var horizontal: float = cos(center_latitude)
	return Vector3(
		horizontal * cos(center_longitude),
		sin(center_latitude),
		horizontal * sin(center_longitude)
	).normalized()


func _make_east(direction: Vector3) -> Vector3:
	var reference: Vector3 = Vector3.UP
	if absf(direction.dot(reference)) > 0.94:
		reference = Vector3.RIGHT
	return reference.cross(direction).normalized()


func _exit_tree() -> void:
	if task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(task_id)
		task_id = -1
	if worker_sampler != null and is_instance_valid(worker_sampler):
		worker_sampler.free()
	worker_sampler = null


func _log_performance(event_name: String, data: Dictionary) -> void:
	if logger == null:
		return
	if logger.has_method("performance"):
		logger.performance(event_name, data)
	else:
		logger.info("terrain_performance", event_name, data)
