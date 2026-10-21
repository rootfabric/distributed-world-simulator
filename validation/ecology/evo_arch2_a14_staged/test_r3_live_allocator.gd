extends SceneTree
## ECO ARCH2 A14.6 R3: actual LAB Controller and Workbench _process
## with opt-in R2 GLOBAL allocator across real host frames.
## All speculative grants, field, organisms and time remain NONCANONICAL.
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Workbench = preload("res://scripts/ecology/workbench/ecology_workbench.gd")
const LabHost = preload("res://scripts/labs/ecology/eco_arch2_polygon_lab.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")

var checks := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("ECO_A14_6_R3_LIVE_FAIL " + label)

func _manifest() -> Dictionary:
	var host = LabHost.new()
	host._build_manifest()
	var m: Dictionary = host.manifest.duplicate(true)
	host.free()
	return m

func _new_controller(manifest: Dictionary) -> Object:
	var ctrl = Controller.new()
	var started: Dictionary = ctrl.initialize(manifest, {})
	_check(bool(started.get("success", false)), "real LAB controller initialized")
	return ctrl

func _checkpoint(ctrl: Object) -> Dictionary:
	return ctrl.serialize_state()

func _parity(a: Object, b: Object, label: String) -> void:
	var x: Dictionary = _checkpoint(a)
	var y: Dictionary = _checkpoint(b)
	_check(bool(x.get("success", false)) and bool(y.get("success", false)),
		label + " both A8 checkpoints valid")
	if bool(x.get("success", false)) and bool(y.get("success", false)):
		_check(String(x.state_text) == String(y.state_text),
			label + " global canonical checkpoint bytes equal")
		_check(String(x.state_hash) == String(y.state_hash),
			label + " canonical state hash exact")

func _run() -> void:
	var m: Dictionary = _manifest()
	_check(not m.is_empty() and String(m.get("mode", "")) == "LAB",
		"production LAB manifest admitted; no WORLD_COMPAT staging")
	if m.is_empty():
		_finish()
		return
	_test_direct_controller(m)
	_test_cancel_restore_and_change(m)
	_test_compact_cursor_hash_and_immutable_resume(m)
	_test_real_frame_path(m)
	_finish()

func _test_direct_controller(m: Dictionary) -> void:
	var legacy = _new_controller(m)
	var r3 = _new_controller(m)
	var source: Dictionary = _checkpoint(r3)
	var visited := {}
	for target_tick in [1, 2, 3]:
		var done := false
		for frame in 140:
			var result: Dictionary = r3.run_staged_frame(
				1000000000, 1, 1, 1, 8388608, true, 2)
			_check(bool(result.get("success", false)),
				"LAB opt-in R3 frame tick=%d frame=%d: %s" %
				[target_tick, frame, String(result.get("error", ""))])
			if not bool(result.get("success", false)):
				return
			var telemetry: Dictionary = r3.get_staged_telemetry()
			visited[String(telemetry.get("r3_allocator_subphase", "NONE"))] = true
			_check(not result.has("state") and not result.has("grants"),
				"controller never leaks speculative A4 field or grants")
			_check(int(result.replayed_ticks) == (1 if bool(result.complete) else 0),
				"one tick publishes only after ALL global A4/A5/A6 stages")
			if bool(result.complete):
				_check(r3.tick() == target_tick and not r3.has_pending_staged_tick(),
					"complete tick closes speculative allocator and commits once")
				done = true
				break
			_check(r3.tick() == target_tick - 1 and r3.has_pending_staged_tick(),
				"partial allocator cannot advance the canonical tick")
			if target_tick == 1:
				_check(String(_checkpoint(r3).state_text) == String(source.state_text),
					"pending R2 scratch absent from A8 serialized state")
		_check(done, "LAB R3 fully advances tick %d" % target_tick)
		if not done:
			return
		_check(bool(legacy.step().get("success", false)),
			"accepted legacy A5 tick %d valid" % target_tick)
		_parity(legacy, r3, "R3 vs original A5 tick %d" % target_tick)
	var stats: Dictionary = r3.get_staged_telemetry()
	_check(int(stats.completed_ticks) == 3
		and int(stats.cancellations) == 0
		and int(stats.r3_allocator_calls) > 5,
		"host telemetry counts R2 substage calls and completed ticks")
	for phase in ["BEGIN", "NORMALIZE", "BUILD_CLAIMS", "PRIMARY", "RESIDUAL", "FINALIZE"]:
		_check(int(stats.r3_allocator_phase_stats[phase].samples) > 0,
			"real R2 A4 subphase %s observed in LAB" % phase)
	_check(visited.has("NORMALIZE") and visited.has("RESIDUAL")
		and visited.has("FINALIZE"), "frame-to-frame R2 allocator subphase visible")
	print("ECO_A14_6_R3_LIVE_JSON " + JSON.stringify({
		"kind": "three-canonical-ticks", "ticks": r3.tick(),
		"allocator_calls": int(stats.r3_allocator_calls),
		"peak_cursor_bytes": int(stats.peak_cursor_bytes),
		"cancel_count": int(stats.cancellations),
		"allocator_phase_stats": stats.r3_allocator_phase_stats,
		"checkpoint_equal": String(_checkpoint(legacy).state_text) ==
			String(_checkpoint(r3).state_text),
	}))

func _test_cancel_restore_and_change(m: Dictionary) -> void:
	var baseline = _new_controller(m)
	var actual = _new_controller(m)
	var before: Dictionary = _checkpoint(actual)
	var first: Dictionary = actual.run_staged_frame(1, 1, 1, 1,
		8388608, true, 2)
	_check(bool(first.get("success", false))
		and actual.has_pending_staged_tick()
		and actual.tick() == 0,
		"small soft budget defers R3 without partial commit")
	_check(String(_checkpoint(actual).state_text) == String(before.state_text),
		"pending speculative cursor absent from persisted checkpoint")
	# Explicit change of allocator mode in an ACTIVE tick is denied and
	# cancels speculation; it cannot silently swap authority/algorithm.
	var changed: Dictionary = actual.run_staged_frame(
		1000000000, 1, 1, 1, 8388608, false, 2)
	_check(not bool(changed.get("success", false))
		and String(changed.get("error", "")).contains("ALLOCATOR_MODE_CHANGED")
		and not actual.has_pending_staged_tick(), "mode switch fails closed")
	_check(actual.tick() == 0 and
		String(_checkpoint(actual).state_text) == String(before.state_text),
		"mode guard leaves committed Runtime untouched")
	var resumed: Dictionary = actual.run_staged_frame(1, 1, 1, 1,
		8388608, true, 2)
	_check(bool(resumed.get("success", false)) and actual.has_pending_staged_tick(),
		"new R3 speculation starts after rejected mode switch")
	var paused: Dictionary = actual.pause()
	_check(bool(paused.get("success", false))
		and not actual.has_pending_staged_tick()
		and actual.tick() == 0, "PAUSE destroys nested R2 scratch")
	_check(String(_checkpoint(actual).state_text) == String(before.state_text),
		"PAUSE does not mutate global Field/organisms/checkpoint")
	_check(bool(actual.step().get("success", false)) and
		bool(baseline.step().get("success", false)),
		"original canonical tick works after R3 cancellation")
	_parity(baseline, actual, "cancellation then original exact")

	var committed: Dictionary = _checkpoint(actual)
	var pending: Dictionary = actual.run_staged_frame(1, 1, 1, 1,
		8388608, true, 2)
	_check(bool(pending.get("success", false))
		and actual.has_pending_staged_tick(), "R3 speculative next tick pending")
	var restored: Dictionary = actual.load_state(
		String(committed.state_text), String(committed.manifest_hash),
		String(committed.state_checksum))
	_check(bool(restored.get("success", false))
		and not actual.has_pending_staged_tick()
		and actual.tick() == 1, "trusted restore drops nested A4 cursor")
	_check(int(actual.get_staged_telemetry().r3_allocator_calls) == 0,
		"restore resets host-only R3 timing/cursor telemetry")
	_parity(baseline, actual, "after trusted restore")

	var cap_controller = _new_controller(m)
	var rejected: Dictionary = cap_controller.run_staged_frame(
		1000000000, 1, 1, 1, 1024, true, 2)
	_check(not bool(rejected.get("success", false))
		and not cap_controller.has_pending_staged_tick()
		and cap_controller.tick() == 0,
		"small transient cursor cap refuses before any canonical mutation")

func _test_compact_cursor_hash_and_immutable_resume(m: Dictionary) -> void:
	# R3 nested R2 scratch is sealed independently. A5's compact envelope
	# binds its checksum, and R2 STILL validates every nested byte before
	# any global grant can advance. Old A14.5 v1 never uses this checksum.
	var ctrl = _new_controller(m)
	var state: Dictionary = ctrl.debug_state().runtime
	var opts: Dictionary = ctrl._canonical_step_options()
	_check(bool(opts.get("success", false)),
		"real LAB exposes accepted canonical step options")
	if not bool(opts.get("success", false)):
		return
	var source_bytes: String = C.encode(state)
	var begin: Dictionary = Runtime.begin_staged_global_tick(
		state, opts.options, 4, 1, true)
	_check(bool(begin.get("success", false)), "R3 compact cursor begin")
	if not bool(begin.get("success", false)):
		return
	var cursor: Dictionary = begin.cursor
	for i in 64:
		if String(cursor.lifecycle.phase) == "ALLOCATE":
			break
		var prepared: Dictionary = Runtime.resume_staged_global_tick(
			state, opts.options, cursor, 1, 1)
		_check(bool(prepared.get("success", false))
			and not bool(prepared.get("complete", true)),
			"R3 PREPARE preserves original global source")
		if not bool(prepared.get("success", false)):
			return
		cursor = prepared.cursor
	_check(String(cursor.lifecycle.phase) == "ALLOCATE",
		"real A5 reaches complete global ALLOCATE frontier")
	if String(cursor.lifecycle.phase) != "ALLOCATE":
		return
	var started: Dictionary = Runtime.resume_staged_global_tick(
		state, opts.options, cursor, 1, 1)
	_check(bool(started.get("success", false))
		and not bool(started.get("complete", true))
		and not started.cursor.lifecycle.allocator_cursor.is_empty(),
		"R2 detached cursor sealed inside R3 A5 envelope")
	if not bool(started.get("success", false)):
		return
	cursor = started.cursor
	var original: String = C.encode(cursor)
	# Change R2 scratch WITHOUT changing its own checksum: A5 compact
	# outer checksum still matches, but the mandatory R2 digest rejects.
	var nested: Dictionary = cursor.duplicate(true)
	nested.lifecycle.allocator_cursor.working_field.cells[0].stocks.water_mg += 1
	var denied: Dictionary = Runtime.resume_staged_global_tick(
		state, opts.options, nested, 1, 1)
	_check(not bool(denied.get("success", false)) and
		String(denied.get("error", "")).contains("A14_6_R2_CURSOR_CHECKSUM"),
		"tampered nested A4 scratch rejected by full R2 integrity digest")
	# A new inner checksum changes the digest bound by outer A5. Nothing
	# can silently rebind a new global grants frontier between frames.
	var wrong_hash: Dictionary = cursor.duplicate(true)
	wrong_hash.lifecycle.allocator_cursor.checksum = "0".repeat(64)
	denied = Runtime.resume_staged_global_tick(
		state, opts.options, wrong_hash, 1, 1)
	_check(not bool(denied.get("success", false)) and
		String(denied.get("error", "")).contains("A5_STAGED_CURSOR_CHECKSUM"),
		"R3 A5 compact envelope detects replaced R2 nested checksum")
	# R3 ALLOCATE now shallow-copies only the A5 envelope and transfers
	# an independently detached R2 result. Neither caller cursor nor
	# authoritative biological state may be mutated by a resume.
	var resumed_a: Dictionary = Runtime.resume_staged_global_tick(
		state, opts.options, cursor, 1, 1)
	var resumed_b: Dictionary = Runtime.resume_staged_global_tick(
		state, opts.options, cursor, 1, 1)
	_check(bool(resumed_a.get("success", false))
		and bool(resumed_b.get("success", false))
		and C.encode(resumed_a) == C.encode(resumed_b),
		"repeat R3 ALLOCATE resume is deterministic and separately owned")
	_check(C.encode(cursor) == original and C.encode(state) == source_bytes,
		"shallow R3 envelope never modifies original nested cursor or Runtime")
	_check(ctrl.tick() == 0 and not ctrl.has_pending_staged_tick(),
		"raw detached diagnostics never publish into the LAB controller")

func _test_real_frame_path(m: Dictionary) -> void:
	var old = _new_controller(m)
	var actual = _new_controller(m)
	var bench = Workbench.new()
	bench.controller = actual
	bench.ticks_per_second = 1.0
	bench.running = true
	bench.pending_target = {"kind": "tick", "value": 3}
	_check(bench.configure_staged_live(true, 1000000000, 1, 1, 1,
		8388608, true, 4), "real LAB Workbench opt-in R3 session")
	var prior := 0
	var incomplete_frames := 0
	var complete := false
	var witnessed_allocator := false
	for frame in 300:
		bench._process(3.0 if frame == 0 else 0.0)
		var now_tick: int = int(actual.tick())
		_check(now_tick >= prior and now_tick <= prior + 1,
			"real LAB _process never publishes more than one full tick/frame")
		if now_tick == prior:
			incomplete_frames += 1
			if String(actual.get_staged_telemetry().phase) == "ALLOCATE":
				witnessed_allocator = true
		prior = now_tick
		if now_tick == 3 and not bench.running:
			complete = true
			break
	_check(complete and witnessed_allocator and incomplete_frames > 3,
		"LAB main _process actually resumes across ALLOCATE substeps")
	_check(actual.tick() == 3 and not actual.has_pending_staged_tick(),
		"no staged data at end of three owed LAB ticks")
	_check(float(bench._elapsed) < 0.001,
		"simulation debt consumed only after three complete commits")
	_check(bool(old.run_to_tick(3).get("success", false)),
		"accepted original LAB reference advances three ticks")
	_parity(old, actual, "actual GUI frame path exact to legacy ecology")
	bench.free()

	var cancel = _new_controller(m)
	var cancel_bench = Workbench.new()
	cancel_bench.controller = cancel
	cancel_bench.ticks_per_second = 1.0
	cancel_bench.pending_target = {"kind": "tick", "value": 1}
	cancel_bench.running = true
	_check(cancel_bench.configure_staged_live(true, 1, 1, 1, 1,
		8388608, true, 1), "short-budget R3 LAB configured")
	cancel_bench._process(1.0)
	_check(cancel.has_pending_staged_tick() and cancel.tick() == 0,
		"speculative R3 tick exists across UI frames")
	_check(cancel_bench.configure_staged_live(false)
		and not cancel.has_pending_staged_tick()
		and cancel.tick() == 0
		and float(cancel_bench._elapsed) >= 1.0,
		"UI opt-out discards nested R2 scratch but preserves owed logical tick")
	cancel_bench.free()

func _finish() -> void:
	print("ECO_ARCH2_A14_6_R3_LIVE checks=%d failed=%d" % [checks, failed])
	print("ECO_ARCH2_A14_6_R3_LIVE " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
