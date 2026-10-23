extends SceneTree
## ECO ARCH2 A14.7 R1 — REAL native LAB GUI + renderer + input soak.
## A14.6 R3.2.3 is frozen. This test owns NO biology/allocator changes.
## Modes: --a147-preflight may run headless, --a147-gui explicitly REQUIRES
## a drawable real desktop window with a hardware rendering adapter.
const LabScene = preload("res://scenes/labs/ecology/eco_arch2_polygon_lab.tscn")
const Fixture = preload("res://validation/ecology/evo_arch2_a14_7/a147_scale_fixture.gd")
const CameraDriver = preload("res://validation/ecology/evo_arch2_a14_7/a147_camera_input_driver.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")

const SCHEMA := "dws.ecology.a14-7-r1-native-gui-soak.v1"
const SIZES := [4, 32, 96, 256]
const EXPECTED_FIRST_TICK := {
	4: "7b56b22193534e2a77c33be3e02b1cb33fc37f189e6d68b4b1535a548fc06062",
	32: "62128cea01410626cfda7556c39afb2ae110606cee229a875476143a240ed129",
	96: "23b11ab4c0454d08de1e82b93a1a5913a2bed4116e29dc2f6bcc765cfd2bb448",
	256: "f38c44896ffc8028c00b1c1f74e5b99d41f12620d60f99f7a95690b3f6419906",
}
const POST_COMMIT_FRAMES := 120
const MIN_SAMPLED_FRAMES := 240
const MAX_SAMPLE_FRAMES := 60000
const SOFTWARE_NAMES := ["llvmpipe", "softpipe", "swiftshader",
	"microsoft basic render", "gdi generic", "software rasterizer"]

var _errors: Array[String] = []
var _checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_errors.append(label)
		push_error("A147_R1_GATE_FAIL " + label)

func _args() -> Dictionary:
	var result: Dictionary = {"mode": "preflight", "population": 4,
		"seconds": 160, "ticks": 2, "require_hardware": true,
		"output": "res://a147-evidence/a147-gui.json"}
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var key: String = String(args[i])
		if key == "--a147-preflight":
			result.mode = "preflight"
		elif key == "--a147-gui":
			result.mode = "gui"
		elif key == "--a147-allow-software":
			# Diagnostic only. Explicitly excludes real hardware acceptance.
			result.require_hardware = false
		elif key in ["--a147-population", "--a147-seconds", "--a147-ticks",
				"--a147-output"]:
			if i + 1 >= args.size():
				return {}
			i += 1
			var value: String = String(args[i])
			if key == "--a147-output":
				result.output = value
			else:
				if not value.is_valid_int():
					return {}
				if key == "--a147-population":
					result.population = int(value)
				elif key == "--a147-seconds":
					result.seconds = int(value)
				else:
					result.ticks = int(value)
		else:
			return {}
		i += 1
	if not int(result.population) in SIZES or int(result.seconds) < 25 \
			or int(result.seconds) > 900 or int(result.ticks) < 1 \
			or int(result.ticks) > 4:
		return {}
	# Evidence output is restricted to an untracked project subtree.
	if not String(result.output).begins_with("res://a147-evidence/") \
			or not String(result.output).ends_with(".json") \
			or String(result.output).contains(".."):
		return {}
	return result

func _run() -> void:
	var cfg: Dictionary = _args()
	if cfg.is_empty():
		_check(false, "CLI_ARGUMENTS_INVALID")
		_finish({}, "INVALID_ARGUMENTS")
		return
	if String(cfg.mode) == "preflight":
		_preflight(int(cfg.population))
		return
	await _gui_soak(cfg)

func _preflight(population: int) -> void:
	var source: Dictionary = Fixture.new().create_population(population)
	_check(not source.is_empty() and source.population.size() == population,
		"TEST_FIXTURE_CONSTRUCTED")
	if not source.is_empty():
		_check(Runtime.validate(source).is_empty(), "CANONICAL_FIXTURE_VALID")
		_check(String(source.integrity_hash).length() == 64,
			"CANONICAL_FIXTURE_HASH")
	var root_scene: Node = LabScene.instantiate()
	root.add_child(root_scene)
	_check(root_scene.get("controller") != null \
		and root_scene.get_node_or_null("EcologyWorkbench") != null \
		and root_scene.get_node_or_null("LabCamera") is Camera3D,
		"ACTUAL_LAB_SCENE_COMPOSES")
	root_scene.queue_free()
	print("A147_PREFLIGHT_JSON " + JSON.stringify({
		"schema": SCHEMA, "mode": "headless-contract-only",
		"population": population, "checks": _checks,
		"failed": _errors.size(), "not_gui_evidence": true,
	}))
	_finish({}, "PREFLIGHT")

func _gui_soak(cfg: Dictionary) -> void:
	# Never silently substitute a headless mock or virtual offscreen
	# viewport for native GUI/GPU evidence.
	for ignored in 3:
		await process_frame
	var display_name: String = DisplayServer.get_name()
	var adapter_name: String = RenderingServer.get_video_adapter_name()
	var adapter_vendor: String = RenderingServer.get_video_adapter_vendor()
	var window_drawable: bool = DisplayServer.window_can_draw()
	var software := false
	for token in SOFTWARE_NAMES:
		if adapter_name.to_lower().contains(token):
			software = true
	_check(display_name != "headless" and window_drawable,
		"A147_GUI_DISPLAY_UNAVAILABLE")
	_check(not adapter_name.is_empty(), "A147_RENDER_ADAPTER_UNAVAILABLE")
	if bool(cfg.require_hardware):
		_check(not software, "A147_SOFTWARE_ADAPTER_NOT_HARDWARE")
	if not _errors.is_empty():
		_finish({"display": display_name, "adapter": adapter_name,
			"window_drawable": window_drawable}, "GUI_BLOCKED")
		return

	var fixture: Dictionary = Fixture.new().create_population(int(cfg.population))
	_check(not fixture.is_empty() \
		and fixture.population.size() == int(cfg.population),
		"EXACT_4_32_96_256_FIXTURE")
	if fixture.is_empty():
		_finish({}, "FIXTURE_FAIL")
		return
	var lab: Node = LabScene.instantiate()
	root.add_child(lab) # FULL P3 LAB host, camera, controls and real P6 scene.
	var controller: Object = lab.get("controller")
	var bench: Node = lab.get_node_or_null("EcologyWorkbench")
	var camera: Camera3D = lab.get_node_or_null("LabCamera") as Camera3D
	_check(controller != null and bench != null and camera != null,
		"REAL_LAB_SCENE_CONTROLLER_UI_CAMERA")
	if not _errors.is_empty():
		_finish({}, "SCENE_FAIL")
		return
	camera.position = Vector3(40.0, 67.0, 92.0)
	camera.look_at(Vector3(40.0, 0.0, 40.0), Vector3.UP)
	var driver: Node = CameraDriver.new()
	lab.add_child(driver)
	driver.bind_camera(camera)

	# Same options/fixture as R3.2.3 exact profiles. Inject test-only
	# BEFORE any worker lease. No user-facing 256 founder manifest change.
	var manifest: Dictionary = lab.manifest.duplicate(true)
	manifest.seed = 20261015
	manifest.mutation.mutations_enabled = false
	var initialized: Dictionary = controller.initialize(manifest, {})
	_check(bool(initialized.get("success", false)), "CANONICAL_LAB_INITIALIZED")
	if not _errors.is_empty():
		_finish({}, "INITIALIZATION_FAILED")
		return
	controller._runtime = fixture.duplicate(true)
	var startup_started: int = Time.get_ticks_usec()
	# Warm-up: real geometry prepopulation is intentionally OUTSIDE the
	# steady-state FPS sample. We record the (possibly slow) cold build.
	bench.morphology_enabled = true
	bench.morphology_lod = "HIGH"
	bench._refresh_from_controller(true)
	var startup_us: int = Time.get_ticks_usec() - startup_started
	_check(bench.organism_views.size() == int(cfg.population),
		"REAL_UI_INITIAL_POPULATION")
	_check(bench._marker_by_id.size() == int(cfg.population) \
		and bench._morphology_by_id.size() == int(cfg.population),
		"REAL_UI_INITIAL_P3_P6")
	var optin: bool = bench.configure_staged_live(true, 1000000000, 1, 1,
		64, 8388608, true, 4096, true, true)
	_check(optin, "A147_REAL_UI_R323_EXPLICIT_OPT_IN")
	if not _errors.is_empty():
		_finish({}, "UI_SETUP_FAILED")
		return
	bench.ticks_per_second = 1.0
	var command_start_us: int = Time.get_ticks_usec()
	var accepted: bool = bench.command_run_to_tick(int(cfg.ticks))
	var command_wall_us: int = Time.get_ticks_usec() - command_start_us
	_check(accepted, "REAL_LAB_RUN_TO_TICK_COMMAND")

	var delivered: Array = []
	var delivered_at: Dictionary = {}
	bench.snapshot_updated.connect(func(snapshot: Dictionary) -> void:
		var t: int = int(snapshot.get("tick", -1))
		if t > 0:
			delivered.append({
				"tick": t,
				"hash": String(snapshot.get("canonical_state_hash", "")),
				"at_us": Time.get_ticks_usec(),
			})
			delivered_at[t] = Time.get_ticks_usec()
	)
	# Wait for actual rendered frames, not a simulated _process() loop.
	for i in 30:
		await process_frame
	var intervals_us: Array[int] = []
	var frame_rows: Array = []
	var last_us: int = Time.get_ticks_usec()
	var start_us: int = last_us
	var next_tick := 1
	var commits_at: Dictionary = {}
	var first_tick_hash := ""
	var memory_first: int = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var memory_peak: int = memory_first
	var max_draw_calls := 0
	var max_debt_ticks := 0
	var last_debt_ticks := 0
	var pending_frames := 0
	var UI_pending_frames := 0
	var window_drawable_samples := 0
	var post_frames := 0
	var timed_out := false
	var complete := false

	for frame in MAX_SAMPLE_FRAMES:
		await process_frame
		var now_us: int = Time.get_ticks_usec()
		var delta_us: int = maxi(0, now_us - last_us)
		last_us = now_us
		intervals_us.append(delta_us)
		driver.inject(frame)
		var current_tick: int = int(controller.tick())
		if current_tick >= next_tick:
			if current_tick != next_tick:
				_check(false, "NONATOMIC_TICK_ADVANCE")
			commits_at[next_tick] = now_us
			if next_tick == 1:
				first_tick_hash = String(controller._runtime.integrity_hash)
			next_tick = current_tick + 1
		var projection: Dictionary = bench.get_r323_ui_telemetry()
		if bool(projection.get("pending", false)):
			UI_pending_frames += 1
		if controller.has_pending_staged_tick():
			pending_frames += 1
		var backlog: int = maxi(0, int(bench._elapsed * bench.ticks_per_second))
		max_debt_ticks = maxi(max_debt_ticks, backlog)
		last_debt_ticks = backlog
		var draw_calls: int = int(Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		max_draw_calls = maxi(max_draw_calls, draw_calls)
		if DisplayServer.window_can_draw():
			window_drawable_samples += 1
		if frame % 10 == 0:
			memory_peak = maxi(memory_peak, int(
				Performance.get_monitor(Performance.MEMORY_STATIC)))
		frame_rows.append({
			"frame": frame, "elapsed_ms": float(now_us - start_us) / 1000.0,
			"interval_us": delta_us, "canonical_tick": current_tick,
			"ui_pending": bool(projection.get("pending", false)),
			"debt_ticks": backlog, "draw_calls": draw_calls,
		})
		if current_tick >= int(cfg.ticks) \
				and not bool(projection.get("pending", false)) \
				and delivered.size() >= int(cfg.ticks):
			post_frames += 1
		else:
			post_frames = 0
		if post_frames >= POST_COMMIT_FRAMES \
				and intervals_us.size() >= MIN_SAMPLED_FRAMES:
			complete = true
			break
		if now_us - start_us > int(cfg.seconds) * 1000000:
			timed_out = true
			break

	var final_tick: int = int(controller.tick())
	var gpu_proof: Dictionary = driver.proof()
	var memory_last: int = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var status: Dictionary = bench.get_r323_ui_telemetry()
	var worker: Dictionary = controller.get_staged_telemetry().off_main
	_check(not timed_out and complete, "SOAK_TARGET_AND_SETTLE_COMPLETED")
	_check(final_tick == int(cfg.ticks), "EXACT_REQUESTED_CANONICAL_TICKS")
	_check(first_tick_hash == String(EXPECTED_FIRST_TICK[int(cfg.population)]),
		"FIRST_TICK_EXACT_ACCEPTED_R323_CANONICAL_HASH")
	_check(delivered.size() == int(cfg.ticks), "EXACTLY_ONE_UI_SNAPSHOT_PER_TICK")
	var publication_order_ok := true
	var max_visual_lag_ms := 0.0
	for row in delivered:
		var tick_value: int = int(row.tick)
		if not commits_at.has(tick_value) \
				or int(row.at_us) < int(commits_at[tick_value]):
			publication_order_ok = false
		else:
			max_visual_lag_ms = maxf(max_visual_lag_ms,
				float(int(row.at_us) - int(commits_at[tick_value])) / 1000.0)
	_check(publication_order_ok, "UI_NEVER_PUBLISHES_UNCOMMITTED_TICK")
	_check(int(status.get("fallbacks", -1)) == 0 and
		int(status.get("completed", -1)) == int(cfg.ticks),
		"R323_NO_LEGACY_FALLBACK_AND_ALL_UI_COMPLETED")
	_check(int(worker.get("jobs_committed", -1)) == int(cfg.ticks) \
		and int(worker.get("tasks_joined", -1)) == int(cfg.ticks) \
		and int(worker.get("jobs_failed", -1)) == 0,
		"ONE_WORKER_JOIN_AND_FULL_COMMIT_PER_TICK")
	_check(bool(gpu_proof.get("camera_moved", false)) \
		and int(gpu_proof.get("mouse_received", 0)) >= 10 \
		and int(gpu_proof.get("key_received", 0)) >= 4,
		"REAL_SCENETREE_INPUT_MOVES_LAB_CAMERA")
	_check(max_draw_calls > 0 and window_drawable_samples > 0,
		"REAL_DRAW_CALLS_AND_DRAWABLE_WINDOW")

	# A checkpoint read is deliberately outside the frame-time sample.
	# The original A8 path remains the authoritative serialization.
	var checkpoint: Dictionary = controller.serialize_state()
	_check(bool(checkpoint.get("success", false)) and
		int(checkpoint.get("tick", -1)) == final_tick,
		"A8_CANONICAL_CHECKPOINT_AVAILABLE")
	var snapshot_hash: String = String(controller._runtime.integrity_hash)
	var observed_hash: String = Runtime.state_hash(controller._runtime)
	_check(snapshot_hash == observed_hash and not snapshot_hash.is_empty(),
		"FINAL_CANONICAL_RUNTIME_FULLY_VALID")
	var quality: Dictionary = _intervals(intervals_us)
	var report: Dictionary = {
		"schema": SCHEMA, "mode": "native-gui", "population": int(cfg.population),
		"requested_ticks": int(cfg.ticks), "committed_ticks": final_tick,
		"rendering_display": display_name, "rendering_adapter": adapter_name,
		"adapter_vendor": adapter_vendor, "drawable_window": window_drawable,
		"hardware_required": bool(cfg.require_hardware),
		"software_adapter_detected": software,
		"p3_p6_actual_lab_scene": true, "real_input": gpu_proof,
		"renderer_draw_calls_peak": max_draw_calls,
		"frames": intervals_us.size(), "sample_wall_seconds":
			float(last_us - start_us) / 1000000.0,
		"frame_interval_ms": quality,
		"frame_under_25ms_ratio": _within(intervals_us, 25000),
		"frame_over_50ms": _above(intervals_us, 50000),
		"startup_cold_geometry_wall_ms": float(startup_us) / 1000.0,
		"command_run_wall_ms": float(command_wall_us) / 1000.0,
		"completed_visual_snapshots": delivered,
		"max_commit_to_visual_ms": max_visual_lag_ms,
		"max_backlog_ticks": max_debt_ticks, "last_backlog_ticks": last_debt_ticks,
		"worker_pending_frames": pending_frames,
		"presentation_pending_frames": UI_pending_frames,
		"presentation_peak_pump_us": int(status.get("peak_pump_us", 0)),
		"presentation_peak_begin_us": int(status.get("peak_begin_us", 0)),
		"worker_last_wall_us": int(worker.get("last_worker_wall_us", 0)),
		"static_memory_bytes": {
			"first": memory_first, "peak": memory_peak, "last": memory_last,
			"delta": memory_last - memory_first,
		},
		"canonical_hash": snapshot_hash, "first_tick_hash": first_tick_hash,
		"a8_checkpoint_hash": String(checkpoint.get("state_hash", "")),
		"renderer_real_gpu_claim": bool(cfg.require_hardware) and not software,
		"hard_frame_deadline_claim": false,
		"production_activation_claim": false, "sample_single_run": true,
		"completed": complete, "timed_out": timed_out,
		"checks": _checks, "failed": _errors.size(),
		"errors": _errors.duplicate(), "frame_samples": frame_rows,
	}
	_save(report, String(cfg.output))
	print("A147_R1_GUI_PROFILE_JSON " + JSON.stringify(_without_samples(report)))
	_finish(report, "GUI")

func _intervals(values: Array[int]) -> Dictionary:
	if values.is_empty():
		return {"p50": -1.0, "p95": -1.0, "p99": -1.0, "max": -1.0}
	var ordered: Array[int] = values.duplicate()
	ordered.sort()
	return {"p50": float(_rank(ordered, 0.50)) / 1000.0,
		"p95": float(_rank(ordered, 0.95)) / 1000.0,
		"p99": float(_rank(ordered, 0.99)) / 1000.0,
		"max": float(ordered.back()) / 1000.0}

func _rank(ordered: Array[int], fraction: float) -> int:
	return int(ordered[clampi(int(ceil(fraction * ordered.size())) - 1,
		0, ordered.size() - 1)])

func _within(values: Array[int], threshold_us: int) -> float:
	if values.is_empty():
		return 0.0
	var count := 0
	for v in values:
		if v <= threshold_us:
			count += 1
	return float(count) / float(values.size())

func _above(values: Array[int], threshold_us: int) -> int:
	var count := 0
	for v in values:
		if v > threshold_us:
			count += 1
	return count

func _without_samples(report: Dictionary) -> Dictionary:
	var reduced: Dictionary = report.duplicate(false)
	reduced.erase("frame_samples")
	return reduced

func _save(report: Dictionary, path: String) -> void:
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://a147-evidence"))
	_check(directory_error == OK, "EVIDENCE_OUTPUT_DIRECTORY")
	if directory_error != OK:
		return
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_check(f != null, "EVIDENCE_OUTPUT_FILE")
	if f == null:
		return
	f.store_string(JSON.stringify(report) + "\n")
	f.flush()
	f.close()

func _finish(payload: Dictionary, mode: String) -> void:
	print("A147_R1_EXECUTION checks=%d failed=%d mode=%s" % [
		_checks, _errors.size(), mode])
	var success: bool = _errors.is_empty()
	if success and mode == "PREFLIGHT":
		print("A147_R1_PREFLIGHT PASS")
	elif success and mode == "GUI":
		print("A147_R1_NATIVE_GUI PASS")
	else:
		print("A147_R1_%s FAIL" % mode)
	quit(0 if success else 1)
