extends SceneTree

const Interpolator = preload("res://scripts/network/interpolation/remote_snapshot_interpolator.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_configuration_contract()
	_test_basic_interpolation_and_yaw_wrap()
	_test_duplicate_conflict_and_out_of_order()
	_test_bounded_extrapolation_and_hold()
	_test_discontinuity_and_authority_reset()
	_test_bounded_timeline()
	_test_deterministic_jitter_loss_and_render_rates()
	_finish()


func _test_configuration_contract() -> void:
	var interpolator = Interpolator.new()
	_assert(not bool(interpolator.advance(0.01).get("success", true)), "advance before configure rejected")
	_assert(not bool(interpolator.configure({"tick_rate_hz": 0.0}).get("success", true)), "zero tick rate rejected")
	interpolator = Interpolator.new()
	_assert(not bool(interpolator.configure({"interpolation_delay_ticks": -1.0}).get("success", true)), "negative delay rejected")
	interpolator = Interpolator.new()
	_assert(not bool(interpolator.configure({"max_extrapolation_ticks": -1.0}).get("success", true)), "negative extrapolation rejected")
	interpolator = Interpolator.new()
	_assert(not bool(interpolator.configure({"max_snapshots": 1}).get("success", true)), "undersized timeline rejected")
	interpolator = Interpolator.new()
	_assert(not bool(interpolator.configure({"max_snapshots": 4097}).get("success", true)), "oversized timeline rejected")
	interpolator = Interpolator.new()
	_assert(not bool(interpolator.configure({"teleport_distance_m": 0.0}).get("success", true)), "zero teleport threshold rejected")
	interpolator = Interpolator.new()
	_assert(not bool(interpolator.configure({"max_implied_speed_mps": 0.0}).get("success", true)), "zero speed fence rejected")
	interpolator = Interpolator.new()
	var configured: Dictionary = interpolator.configure()
	_assert(bool(configured.get("success", false)), "default configuration accepted")
	_assert(not bool(interpolator.configure().get("success", true)), "reconfiguration rejected")
	var config: Dictionary = interpolator.get_config()
	_assert(is_equal_approx(float(config.get("tick_rate_hz", 0.0)), 60.0), "default tick rate")
	_assert(is_equal_approx(float(config.get("interpolation_delay_ms", 0.0)), 100.0), "default delay is 100ms")
	_assert(is_equal_approx(float(config.get("max_extrapolation_ms", 0.0)), 100.0), "default extrapolation is 100ms")
	_assert(int(config.get("max_snapshots", 0)) == 32, "default buffer bounded")
	_assert(not bool(interpolator.push_snapshot({}, 0, 0, 1).get("success", true)), "invalid record rejected")
	_assert(not bool(interpolator.push_snapshot(_record(), -1, 0, 1).get("success", true)), "negative server tick rejected")
	_assert(not bool(interpolator.push_snapshot(_record(), 0, -1, 1).get("success", true)), "negative snapshot revision rejected")
	_assert(not bool(interpolator.push_snapshot(_record(), 0, 0, 0).get("success", true)), "invalid authority epoch rejected")
	var disconnected := _record()
	disconnected["connected"] = false
	_assert(not bool(interpolator.push_snapshot(disconnected, 0, 0, 1).get("success", true)), "disconnected record rejected")
	_assert(not bool(interpolator.sample_at_render_tick(NAN).get("success", true)), "NaN render tick rejected")
	_assert(not bool(interpolator.advance(-0.1).get("success", true)), "negative delta rejected")


func _test_basic_interpolation_and_yaw_wrap() -> void:
	var interpolator = _configured({"interpolation_delay_ticks": 0.0})
	var first := _record(Vector3(0.0, 1.0, 0.0), Vector3(10.0, 0.0, 0.0), deg_to_rad(170.0), false, 1)
	var second := _record(Vector3(1.0, 1.0, 0.0), Vector3(10.0, 0.0, 0.0), deg_to_rad(-170.0), true, 2)
	_assert(bool(interpolator.push_snapshot(first, 100, 10, 1).get("success", false)), "first snapshot accepted")
	_assert(bool(interpolator.push_snapshot(second, 106, 11, 1).get("success", false)), "second snapshot accepted")
	var midpoint: Dictionary = interpolator.sample_at_render_tick(103.0)
	_assert(bool(midpoint.get("success", false)), "midpoint sample succeeds")
	var details: Dictionary = midpoint.get("details", {})
	_assert(String(details.get("mode", "")) == "INTERPOLATE", "midpoint interpolates")
	_assert((details.get("position", Vector3.ZERO) as Vector3).is_equal_approx(Vector3(0.5, 1.0, 0.0)), "midpoint position")
	_assert((details.get("velocity", Vector3.ZERO) as Vector3).is_equal_approx(Vector3(10.0, 0.0, 0.0)), "midpoint velocity")
	_assert(absf(absf(float(details.get("orientation_yaw", 0.0))) - PI) < 0.00001, "yaw uses shortest wrapped path")
	_assert(bool(details.get("flashlight_enabled", false)), "discrete flashlight switches at midpoint")
	_assert(int(details.get("source_tick", -1)) == 100, "source tick reported")
	_assert(int(details.get("target_tick", -1)) == 106, "target tick reported")
	_assert(is_equal_approx(float(details.get("alpha", -1.0)), 0.5), "interpolation alpha")
	var first_exact: Dictionary = interpolator.sample_at_render_tick(100.0)
	_assert((first_exact.get("details", {}).get("position", Vector3.ONE) as Vector3).is_equal_approx(Vector3(0.0, 1.0, 0.0)), "first endpoint exact")
	var second_exact: Dictionary = interpolator.sample_at_render_tick(106.0)
	_assert((second_exact.get("details", {}).get("position", Vector3.ZERO) as Vector3).is_equal_approx(Vector3(1.0, 1.0, 0.0)), "second endpoint exact")
	var report: Dictionary = interpolator.get_report()
	_assert(int(report.get("interpolation_samples", 0)) == 2, "interpolation telemetry")
	_assert(int(report.get("buffer_size", 0)) == 2, "buffer size telemetry")
	_assert(String(report.get("logical_player_id", "")) == "b", "identity telemetry")


func _test_duplicate_conflict_and_out_of_order() -> void:
	var interpolator = _configured({"interpolation_delay_ticks": 0.0})
	var tick_12 := _record(Vector3(1.2, 0.0, 0.0), Vector3(6.0, 0.0, 0.0), 0.0, false, 3)
	var tick_10 := _record(Vector3(1.0, 0.0, 0.0), Vector3(6.0, 0.0, 0.0), 0.0, false, 2)
	var tick_11 := _record(Vector3(1.1, 0.0, 0.0), Vector3(6.0, 0.0, 0.0), 0.0, false, 2)
	_assert(bool(interpolator.push_snapshot(tick_12, 12, 12, 1).get("success", false)), "latest first accepted")
	var out_of_order: Dictionary = interpolator.push_snapshot(tick_10, 10, 10, 1)
	_assert(bool(out_of_order.get("success", false)), "older out-of-order accepted")
	_assert(bool(out_of_order.get("details", {}).get("out_of_order", false)), "out-of-order reported")
	_assert(bool(interpolator.push_snapshot(tick_11, 11, 11, 1).get("success", false)), "middle out-of-order accepted")
	var timeline: Array[Dictionary] = interpolator.get_timeline_for_testing()
	_assert(timeline.size() == 3, "three timeline entries")
	_assert(int(timeline[0].get("server_tick", -1)) == 10, "timeline sorted first")
	_assert(int(timeline[1].get("server_tick", -1)) == 11, "timeline sorted middle")
	_assert(int(timeline[2].get("server_tick", -1)) == 12, "timeline sorted last")
	var duplicate: Dictionary = interpolator.push_snapshot(tick_11, 11, 11, 1)
	_assert(bool(duplicate.get("success", false)), "exact duplicate is nonfatal")
	_assert(bool(duplicate.get("details", {}).get("duplicate", false)), "duplicate reported")
	var outer_revision_duplicate: Dictionary = interpolator.push_snapshot(tick_11, 11, 99, 1)
	_assert(bool(outer_revision_duplicate.get("success", false)), "same player state with newer outer revision is nonfatal")
	_assert(bool(outer_revision_duplicate.get("details", {}).get("duplicate", false)), "outer-only revision update is duplicate")
	_assert(int(interpolator.get_timeline_for_testing()[1].get("snapshot_revision", 0)) == 99, "duplicate retains newest outer revision")
	var replacement := tick_11.duplicate(true)
	replacement["position"] = {"x": 1.15, "y": 0.0, "z": 0.0}
	replacement["orientation_yaw"] = 0.25
	replacement["flashlight_enabled"] = true
	replacement["state_revision"] = 3
	var replacement_result: Dictionary = interpolator.push_snapshot(
		replacement,
		11,
		100,
		1
	)
	_assert(
		bool(replacement_result.get("success", false)),
		"newer same-tick authoritative revision replaces state"
	)
	_assert(
		bool(replacement_result.get("details", {}).get(
			"same_tick_replacement", false
		)),
		"same-tick replacement reported"
	)
	var replaced_timeline: Array[Dictionary] = (
		interpolator.get_timeline_for_testing()
	)
	_assert(
		int(replaced_timeline[1].get("snapshot_revision", 0)) == 100,
		"replacement stores newest outer revision"
	)
	_assert(
		(replaced_timeline[1].get(
			"position", Vector3.ZERO
		) as Vector3).is_equal_approx(Vector3(1.15, 0.0, 0.0)),
		"replacement stores changed authoritative position"
	)
	_assert(
		bool(replaced_timeline[1].get("flashlight_enabled", false)),
		"replacement stores same-tick presentation state"
	)
	var conflict := replacement.duplicate(true)
	conflict["position"] = {"x": 9.0, "y": 0.0, "z": 0.0}
	_assert(
		String(interpolator.push_snapshot(
			conflict, 11, 100, 1
		).get("error_code", "")) == "CONFLICTING_REMOTE_SNAPSHOT_TICK",
		"same tuple with conflicting state rejected"
	)
	var stale_same_tick := replacement.duplicate(true)
	stale_same_tick["position"] = {"x": -9.0, "y": 0.0, "z": 0.0}
	var stale_same_tick_result: Dictionary = interpolator.push_snapshot(
		stale_same_tick,
		11,
		99,
		1
	)
	_assert(
		bool(stale_same_tick_result.get("success", false)),
		"older same-tick outer revision is a nonfatal stale packet"
	)
	_assert(
		bool(stale_same_tick_result.get("details", {}).get("stale", false)),
		"older same-tick outer revision reported stale"
	)
	_assert(
		(interpolator.get_timeline_for_testing()[1].get(
			"position", Vector3.ZERO
		) as Vector3).is_equal_approx(Vector3(1.15, 0.0, 0.0)),
		"stale same-tick packet cannot replace authoritative state"
	)
	var foreign := tick_11.duplicate(true)
	foreign["logical_player_id"] = "c"
	foreign["player_entity_id"] = "player/c"
	_assert(String(interpolator.push_snapshot(foreign, 13, 13, 1).get("error_code", "")) == "REMOTE_PLAYER_IDENTITY_MISMATCH", "foreign identity rejected")
	var stale_epoch := tick_11.duplicate(true)
	stale_epoch["ownership_epoch"] = 1
	var illegal_session := tick_12.duplicate(true)
	illegal_session["transport_session_id"] = "transport-session/m3/b/illegal"
	_assert(String(interpolator.push_snapshot(illegal_session, 19, 19, 1).get("error_code", "")) == "REMOTE_SESSION_CHANGED_WITHOUT_EPOCH", "session change requires epoch advance")
	var new_epoch := tick_12.duplicate(true)
	new_epoch["ownership_epoch"] = 2
	new_epoch["transport_session_id"] = "transport-session/m3/b/2"
	_assert(bool(interpolator.push_snapshot(new_epoch, 20, 20, 2).get("success", false)), "new epoch resets")
	_assert(String(interpolator.push_snapshot(stale_epoch, 21, 21, 1).get("error_code", "")) == "STALE_REMOTE_AUTHORITY_EPOCH", "stale epoch rejected")
	var report: Dictionary = interpolator.get_report()
	_assert(int(report.get("duplicates_suppressed", 0)) == 2, "duplicate telemetry")
	_assert(int(report.get("same_tick_replacements", 0)) == 1, "same-tick replacement telemetry")
	_assert(int(report.get("same_tick_stale_dropped", 0)) == 1, "same-tick stale telemetry")
	_assert(int(report.get("conflicts_rejected", 0)) == 3, "conflict telemetry")
	_assert(int(report.get("stale_dropped", 0)) == 2, "stale telemetry")
	_assert(int(report.get("identity_resets", 0)) == 1, "identity reset telemetry")


func _test_bounded_extrapolation_and_hold() -> void:
	var interpolator = _configured({
		"interpolation_delay_ticks": 0.0,
		"max_extrapolation_ticks": 6.0,
	})
	_assert(bool(interpolator.push_snapshot(_record(Vector3.ZERO, Vector3(3.0, 0.0, 0.0)), 50, 1, 1).get("success", false)), "extrapolation source accepted")
	var extrapolated: Dictionary = interpolator.sample_at_render_tick(53.0)
	_assert(String(extrapolated.get("details", {}).get("mode", "")) == "BUFFERING", "single snapshot initially buffers")
	_assert(bool(interpolator.push_snapshot(_record(Vector3(0.15, 0.0, 0.0), Vector3(3.0, 0.0, 0.0), 0.0, false, 2), 53, 2, 1).get("success", false)), "second source accepted")
	extrapolated = interpolator.sample_at_render_tick(56.0)
	_assert(String(extrapolated.get("details", {}).get("mode", "")) == "EXTRAPOLATE", "inside horizon extrapolates")
	_assert((extrapolated.get("details", {}).get("position", Vector3.ZERO) as Vector3).is_equal_approx(Vector3(0.3, 0.0, 0.0)), "velocity extrapolation uses tick duration")
	_assert(is_equal_approx(float(extrapolated.get("details", {}).get("extrapolation_ticks", 0.0)), 3.0), "extrapolation ticks reported")
	var edge: Dictionary = interpolator.sample_at_render_tick(59.0)
	_assert(String(edge.get("details", {}).get("mode", "")) == "EXTRAPOLATE", "horizon edge extrapolates")
	_assert((edge.get("details", {}).get("position", Vector3.ZERO) as Vector3).is_equal_approx(Vector3(0.45, 0.0, 0.0)), "horizon edge position")
	var held: Dictionary = interpolator.sample_at_render_tick(60.0)
	_assert(String(held.get("details", {}).get("mode", "")) == "HOLD_EXTRAPOLATION_LIMIT", "past horizon holds")
	_assert((held.get("details", {}).get("position", Vector3.ZERO) as Vector3).is_equal_approx(Vector3(0.15, 0.0, 0.0)), "hold never drifts beyond authoritative endpoint")
	var report: Dictionary = interpolator.get_report()
	_assert(int(report.get("extrapolation_samples", 0)) == 2, "extrapolation telemetry")
	_assert(int(report.get("hold_samples", 0)) == 1, "hold telemetry")


func _test_discontinuity_and_authority_reset() -> void:
	var interpolator = _configured({
		"interpolation_delay_ticks": 0.0,
		"teleport_distance_m": 4.0,
		"max_implied_speed_mps": 1000.0,
	})
	_assert(bool(interpolator.push_snapshot(_record(Vector3.ZERO, Vector3.ZERO), 100, 1, 1).get("success", false)), "pre-teleport accepted")
	_assert(bool(interpolator.push_snapshot(_record(Vector3(20.0, 0.0, 0.0), Vector3.ZERO, 0.0, true, 2), 106, 2, 1).get("success", false)), "teleport accepted")
	var before: Dictionary = interpolator.sample_at_render_tick(103.0)
	_assert(String(before.get("details", {}).get("mode", "")) == "HOLD_BEFORE_DISCONTINUITY", "does not interpolate through teleport")
	_assert((before.get("details", {}).get("position", Vector3.ONE) as Vector3).is_equal_approx(Vector3.ZERO), "pre-teleport state held")
	var at_jump: Dictionary = interpolator.sample_at_render_tick(106.0)
	_assert(String(at_jump.get("details", {}).get("mode", "")) == "SNAP_DISCONTINUITY", "teleport snaps at authoritative tick")
	_assert((at_jump.get("details", {}).get("position", Vector3.ZERO) as Vector3).is_equal_approx(Vector3(20.0, 0.0, 0.0)), "teleport target exact")
	_assert(int(interpolator.get_report().get("teleport_segments", 0)) == 1, "teleport telemetry")

	var next_session := _record(Vector3(30.0, 0.0, 0.0), Vector3.ZERO, 0.0, false, 1)
	next_session["ownership_epoch"] = 2
	next_session["transport_session_id"] = "transport-session/m3/b/reconnect"
	var reset_result: Dictionary = interpolator.push_snapshot(next_session, 200, 1, 2)
	_assert(bool(reset_result.get("success", false)), "reconnect accepted")
	_assert(String(reset_result.get("details", {}).get("reset_reason", "")) == "AUTHORITY_OR_SESSION_CHANGED", "reconnect reset reported")
	_assert(int(interpolator.get_report().get("buffer_size", 0)) == 1, "old epoch timeline discarded")
	var after_reset: Dictionary = interpolator.sample_at_render_tick(200.0)
	_assert((after_reset.get("details", {}).get("position", Vector3.ZERO) as Vector3).is_equal_approx(Vector3(30.0, 0.0, 0.0)), "new authority baseline used")


func _test_bounded_timeline() -> void:
	var interpolator = _configured({
		"interpolation_delay_ticks": 0.0,
		"max_snapshots": 8,
		"teleport_distance_m": 1000.0,
		"max_implied_speed_mps": 1000.0,
	})
	for tick in range(100):
		var record := _record(Vector3(float(tick) * 0.01, 0.0, 0.0), Vector3(0.6, 0.0, 0.0), 0.0, false, tick + 1)
		_assert(bool(interpolator.push_snapshot(record, tick, tick, 1).get("success", false)), "bounded insert %d" % tick)
		_assert(int(interpolator.get_report().get("buffer_size", 99)) <= 8, "bounded size %d" % tick)
	var timeline: Array[Dictionary] = interpolator.get_timeline_for_testing()
	_assert(timeline.size() == 8, "timeline at configured capacity")
	_assert(int(timeline[0].get("server_tick", -1)) == 92, "oldest entry pruned deterministically")
	_assert(int(timeline[7].get("server_tick", -1)) == 99, "latest entry retained")
	_assert(int(interpolator.get_report().get("overflow_pruned", 0)) == 92, "overflow telemetry exact")
	var too_old := _record(Vector3.ZERO, Vector3.ZERO, 0.0, false, 1)
	_assert(String(interpolator.push_snapshot(too_old, 1, 1000, 1).get("error_code", "")) == "STALE_REMOTE_SNAPSHOT_TICK", "packet older than bounded window rejected")
	_assert(int(interpolator.get_timeline_for_testing()[0].get("server_tick", -1)) == 92, "stale packet cannot churn bounded timeline")


func _test_deterministic_jitter_loss_and_render_rates() -> void:
	for fps in [30, 60, 144]:
		_run_render_profile(int(fps))


func _run_render_profile(fps: int) -> void:
	var interpolator = _configured({
		"interpolation_delay_ticks": 6.0,
		"max_extrapolation_ticks": 6.0,
		"max_snapshots": 32,
		"teleport_distance_m": 1000.0,
		"max_implied_speed_mps": 1000.0,
	})
	var arrivals: Array[Dictionary] = []
	var velocity := Vector3(2.5, 0.0, -1.25)
	for server_tick in range(0, 361, 3):
		if server_tick > 0 and server_tick % 21 == 0:
			continue
		var jitter_index: int = (server_tick / 3) % 5
		var jitter_ticks: int = int([2, 0, 4, 1, 3][jitter_index])
		arrivals.append({
			"arrival_tick": server_tick + 4 + jitter_ticks,
			"server_tick": server_tick,
			"record": _record(
				velocity * (float(server_tick) / 60.0),
				velocity,
				float(server_tick) * 0.01,
				(server_tick / 30) % 2 == 1,
				server_tick + 1
			),
		})
	arrivals.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if int(left.get("arrival_tick", 0)) == int(right.get("arrival_tick", 0)):
			return int(left.get("server_tick", 0)) > int(right.get("server_tick", 0))
		return int(left.get("arrival_tick", 0)) < int(right.get("arrival_tick", 0))
	)
	var next_arrival := 0
	var local_tick := 0.0
	var delta := 1.0 / float(fps)
	var successful_samples := 0
	var maximum_error := 0.0
	for frame in range(int(6.0 * float(fps))):
		local_tick += delta * 60.0
		while next_arrival < arrivals.size() and float(arrivals[next_arrival].get("arrival_tick", 0)) <= local_tick:
			var event: Dictionary = arrivals[next_arrival]
			var server_tick := int(event.get("server_tick", 0))
			var accepted: Dictionary = interpolator.push_snapshot(event.get("record", {}), server_tick, server_tick, 1)
			_assert(bool(accepted.get("success", false)), "profile %d arrival %d" % [fps, server_tick])
			next_arrival += 1
		var sampled: Dictionary = interpolator.advance(delta)
		if not bool(sampled.get("success", false)):
			continue
		var details: Dictionary = sampled.get("details", {})
		var mode := String(details.get("mode", ""))
		_assert(mode in ["BUFFERING", "INTERPOLATE", "EXTRAPOLATE", "HOLD_EXTRAPOLATION_LIMIT", "HOLD_BEFORE_DISCONTINUITY", "SNAP_DISCONTINUITY"], "profile %d valid mode frame %d" % [fps, frame])
		var position: Vector3 = details.get("position", Vector3.ZERO)
		_assert(not is_nan(position.x) and not is_inf(position.x), "profile %d finite x frame %d" % [fps, frame])
		_assert(not is_nan(position.z) and not is_inf(position.z), "profile %d finite z frame %d" % [fps, frame])
		if mode in ["INTERPOLATE", "EXTRAPOLATE"] and float(details.get("render_tick", 0.0)) >= 12.0:
			var expected := velocity * (float(details.get("render_tick", 0.0)) / 60.0)
			var error := position.distance_to(expected)
			maximum_error = maxf(maximum_error, error)
			_assert(error < 0.00001, "profile %d exact constant-velocity path frame %d" % [fps, frame])
			successful_samples += 1
	_assert(successful_samples > fps * 4, "profile %d has sustained interpolation samples" % fps)
	_assert(maximum_error < 0.00001, "profile %d maximum path error bounded" % fps)
	var report: Dictionary = interpolator.get_report()
	_assert(int(report.get("buffer_size", 0)) <= 32, "profile %d buffer bounded" % fps)
	_assert(int(report.get("snapshots_inserted", 0)) > 90, "profile %d receives long stream" % fps)
	_assert(int(report.get("interpolation_samples", 0)) > 0, "profile %d interpolation exercised" % fps)
	_assert(int(report.get("teleport_segments", -1)) == 0, "profile %d no false teleports" % fps)


func _configured(options: Dictionary = {}) -> RefCounted:
	var interpolator = Interpolator.new()
	var result: Dictionary = interpolator.configure(options)
	_assert(bool(result.get("success", false)), "interpolator configured")
	return interpolator


func _record(
	position: Vector3 = Vector3.ZERO,
	velocity: Vector3 = Vector3.ZERO,
	yaw: float = 0.0,
	flashlight: bool = false,
	state_revision: int = 1
) -> Dictionary:
	return {
		"logical_player_id": "b",
		"player_entity_id": "player/b",
		"transport_session_id": "transport-session/m3/b/nx5",
		"ownership_epoch": 1,
		"connected": true,
		"position": {"x": position.x, "y": position.y, "z": position.z},
		"velocity": {"x": velocity.x, "y": velocity.y, "z": velocity.z},
		"inventory": [],
		"last_input_sequence": maxi(0, state_revision),
		"state_revision": maxi(1, state_revision),
		"orientation_yaw": wrapf(yaw, -PI, PI),
		"flashlight_enabled": flashlight,
	}


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("NX5 remote snapshot interpolation: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("NX5 remote snapshot interpolation: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
