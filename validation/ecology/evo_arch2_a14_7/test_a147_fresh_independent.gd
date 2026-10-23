extends SceneTree
## ECO ARCH2 A14.7 R1 independent direct-child verifier.
## Does NOT call the product GUI soak script; proves actual composition,
## deterministic Input._input delivery, immutable source and native renderer
## only in --gui mode. Headless proof is explicitly NOT native GPU evidence.
const Lab = preload("res://scenes/labs/ecology/eco_arch2_polygon_lab.tscn")
const Fixture = preload("res://validation/ecology/evo_arch2_a14_7/a147_scale_fixture.gd")
const CameraInput = preload("res://validation/ecology/evo_arch2_a14_7/a147_camera_input_driver.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")

const EXPECTED_FIRST_4 := "7b56b22193534e2a77c33be3e02b1cb33fc37f189e6d68b4b1535a548fc06062"
var checks := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("A147_FRESH_VERIFIER_FAIL " + msg)

func _run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 1 or not String(args[0]) in ["--preflight", "--gui"]:
		_check(false, "EXACT_ARGUMENTS")
		_finish("INPUT")
		return
	var mode: String = String(args[0])
	if mode == "--gui":
		for i in 3:
			await process_frame
		var adapter: String = RenderingServer.get_video_adapter_name()
		var software := false
		for name in ["llvmpipe", "softpipe", "swiftshader", "microsoft basic render"]:
			if adapter.to_lower().contains(name):
				software = true
		_check(DisplayServer.get_name() != "headless" and
			DisplayServer.window_can_draw() and not adapter.is_empty() and not software,
			"INDEPENDENT_NATIVE_GUI_HARDWARE_REQUIRED")
	else:
		_check(DisplayServer.get_name() == "headless", "PREFLIGHT_MUST_BE_HEADLESS")
	if failed > 0:
		_finish("GUI_BLOCKED")
		return
	var lab: Node = Lab.instantiate()
	root.add_child(lab)
	var c: Object = lab.get("controller")
	var ui: Node = lab.get_node_or_null("EcologyWorkbench")
	var cam: Camera3D = lab.get_node_or_null("LabCamera")
	_check(c != null and ui != null and cam != null,
		"ACTUAL_LAB_CAMERA_CONTROLLER_AND_WORKBENCH")
	if failed > 0:
		_finish("SCENE")
		return
	var input: Node = CameraInput.new()
	lab.add_child(input)
	input.bind_camera(cam)
	for i in 48:
		input.inject(i)
		await process_frame
	var proof: Dictionary = input.proof()
	_check(int(proof.mouse_received) >= 10 and int(proof.key_received) >= 4
		and bool(proof.camera_moved), "GODOT_INPUT_PIPELINE_TO_ACTUAL_CAMERA")
	var fixture: Dictionary = Fixture.new().create_population(4)
	_check(not fixture.is_empty() and Runtime.validate(fixture).is_empty(),
		"CANONICAL_FOUR_ORGANISM_FIXTURE")
	if mode == "--preflight":
		print("A147_FRESH_PREFLIGHT_JSON " + JSON.stringify({
			"headless": true, "checks": checks, "failed": failed,
			"input": proof, "not_gpu_evidence": true}))
		_finish("PREFLIGHT")
		return
	var manifest: Dictionary = lab.manifest.duplicate(true)
	manifest.seed = 20261015
	manifest.mutation.mutations_enabled = false
	var initialized: Dictionary = c.initialize(manifest, {})
	_check(bool(initialized.get("success", false)), "ACTUAL_LAB_CANONICAL_OPTIONS")
	if failed > 0:
		_finish("INITIALIZE")
		return
	c._runtime = fixture.duplicate(true)
	ui._refresh_from_controller(true)
	_check(ui.organism_views.size() == 4 and ui._morphology_by_id.size() == 4,
		"ACTUAL_P3_P6_NODES_RENDERABLE")
	_check(ui.configure_staged_live(true, 1000000000, 1, 1, 64,
		8388608, true, 4096, true, true), "REAL_R323_LAB_EXPLICIT_OPTIN")
	var events: Array = []
	# command_run_to_tick() synchronously refreshes presentation state at the
	# CURRENT tick (0) before the run loop starts; that refresh is not a
	# canonical tick publication. Connect AFTER the command so exactly one
	# completed tick-1 visual publication (R3.2.3 single-emit) is observed.
	var command_ok: bool = ui.command_run_to_tick(1)
	ui.snapshot_updated.connect(func(snapshot: Dictionary) -> void:
		events.append({"tick": int(snapshot.tick),
			"hash": String(snapshot.canonical_state_hash)})
	)
	_check(command_ok, "ACTUAL_GUI_WORKBENCH_COMMAND")
	var frames := 0
	var draw_calls_peak := 0
	var last_frame := Time.get_ticks_usec()
	var worst_interval_us := 0
	var settled := 0
	var deadline_us: int = Time.get_ticks_usec() + 90000000
	while Time.get_ticks_usec() < deadline_us:
		await process_frame
		frames += 1
		var now := Time.get_ticks_usec()
		worst_interval_us = maxi(worst_interval_us, now - last_frame)
		last_frame = now
		input.inject(frames + 100)
		draw_calls_peak = maxi(draw_calls_peak,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		if int(c.tick()) == 1 and not bool(ui.get_r323_ui_telemetry().pending):
			settled += 1
		else:
			settled = 0
		if settled >= 60 and frames >= 180:
			break
	_check(int(c.tick()) == 1 and events.size() == 1 and int(events[0].tick) == 1,
		"ONE_CANONICAL_TICK_AND_ONE_COMPLETED_VISUAL_EVENT")
	_check(events.size() == 1 and String(events[0].hash) == EXPECTED_FIRST_4,
		"CANONICAL_HASH_EXACT_TO_FROZEN_R323")
	_check(draw_calls_peak > 0 and frames >= 180 and
		DisplayServer.window_can_draw(), "ACTUAL_NATIVE_GPU_DRAWCALLS_AND_FRAME_SAMPLES")
	_check(int(c.get_staged_telemetry().off_main.jobs_committed) == 1 and
		int(c.get_staged_telemetry().off_main.tasks_joined) == 1,
		"ONE_WORKER_TASK_JOINED_AND_PUBLISHED")
	print("A147_FRESH_NATIVE_RECEIPT_JSON " + JSON.stringify({
		"adapter": RenderingServer.get_video_adapter_name(),
		"draw_calls_peak": draw_calls_peak,
		"frames": frames, "worst_frame_interval_ms": float(worst_interval_us)/1000.0,
		"canonical_hash": String(c._runtime.integrity_hash),
		"input": input.proof(), "not_performance_sla": true}))
	_finish("GUI")

func _finish(mode: String) -> void:
	print("A147_FRESH_VERIFIER checks=%d failed=%d" % [checks, failed])
	print("A147_FRESH_%s %s" % [mode, "PASS" if failed == 0 else "FAIL"])
	quit(0 if failed == 0 else 1)
