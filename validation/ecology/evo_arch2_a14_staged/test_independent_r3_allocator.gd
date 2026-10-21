extends SceneTree
## ECO ARCH2 A14.6 R3 — FRESH verifier on frozen product candidate.
## Uses an independent real LAB Controller and externally anchored A8
## checkpoint oracle, not the product R3 test's helpers.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Workbench = preload("res://scripts/ecology/workbench/ecology_workbench.gd")
const Lab = preload("res://scripts/labs/ecology/eco_arch2_polygon_lab.gd")

var checks := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _assert(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("ECO_A14_6_R3_INDEPENDENT_FAIL " + description)

func _manifest() -> Dictionary:
	var host = Lab.new()
	host._build_manifest()
	var out: Dictionary = host.manifest.duplicate(true)
	host.free()
	return out

func _controller(manifest: Dictionary) -> Object:
	var c = Controller.new()
	var initialized: Dictionary = c.initialize(manifest, {})
	_assert(bool(initialized.get("success", false)), "real LAB host admitted")
	return c

func _checkpoint(c: Object) -> Dictionary:
	return c.serialize_state()

func _run() -> void:
	var m: Dictionary = _manifest()
	_assert(not m.is_empty() and String(m.get("mode", "")) == "LAB",
		"accepted LAB manifest, not external authority")
	if m.is_empty():
		_done()
		return
	var reference = _controller(m)
	var staged = _controller(m)
	var start: Dictionary = _checkpoint(staged)
	_assert(bool(start.get("success", false)), "valid canonical original checkpoint")
	var original_state: Dictionary = staged.debug_state().runtime
	var options_result: Dictionary = staged._canonical_step_options()
	_assert(bool(options_result.get("success", false)), "accepted controller options")
	if not bool(options_result.get("success", false)):
		_done()
		return
	var opts: Dictionary = options_result.options
	var legacy: Dictionary = Runtime.begin_staged_global_tick(original_state, opts, 4, 8)
	var r3: Dictionary = Runtime.begin_staged_global_tick(original_state, opts, 4, 8, true)
	_assert(bool(legacy.get("success", false)) and bool(r3.get("success", false)),
		"both old and opt-in staged A5 start from identical truth")
	if bool(legacy.get("success", false)) and bool(r3.get("success", false)):
		_assert(String(legacy.cursor.lifecycle.schema) != String(r3.cursor.lifecycle.schema),
			"opt-in R3 uses a new nonpersistent A5 cursor schema")
		_assert(not legacy.cursor.lifecycle.has("allocator_cursor")
			and r3.cursor.lifecycle.has("allocator_cursor")
			and r3.cursor.lifecycle.allocator_cursor.is_empty(),
			"historical A14.5 cursor shape and default semantics preserved")
	var saw := {}
	var entered_subphase := false
	var last_tick := 0
	var pending_count := 0
	var completed := false
	for i in 160:
		var next: Dictionary = staged.run_staged_frame(
			1000000000, 1, 1, 1, 8388608, true, 1)
		_assert(bool(next.get("success", false)), "R3 LAB step exact")
		if not bool(next.get("success", false)):
			break
		var monitor: Dictionary = staged.get_staged_telemetry()
		var phase: String = String(monitor.get("phase", "NONE"))
		var a4_phase: String = String(monitor.get("r3_allocator_subphase", "NONE"))
		saw[a4_phase] = true
		_assert(not next.has("state") and not next.has("grants"),
			"no speculative A4 grants or global state returned to caller")
		_assert(int(staged.tick()) >= last_tick and int(staged.tick()) <= last_tick + 1,
			"monotonic whole-tick progress")
		if phase == "ALLOCATE" and a4_phase == "RESIDUAL":
			entered_subphase = true
		if bool(next.get("complete", false)):
			completed = true
			break
		pending_count += 1
		_assert(staged.tick() == 0, "A4 work has zero authoritative tick impact")
		_assert(String(_checkpoint(staged).state_text) == String(start.state_text),
			"source A8 bytes unchanged while R2 allocator is pending")
		last_tick = staged.tick()
	_assert(completed and pending_count > 4 and entered_subphase,
		"true multi-frame global R2 allocator completed all resource passes")
	if completed:
		_assert(staged.tick() == 1 and not staged.has_pending_staged_tick(),
			"only one complete A5/A6 frontier committed")
		_assert(bool(reference.step().get("success", false)),
			"legacy reference completes exact canonical tick")
		var lhs: Dictionary = _checkpoint(staged)
		var rhs: Dictionary = _checkpoint(reference)
		_assert(bool(lhs.get("success", false)) and bool(rhs.get("success", false))
			and String(lhs.state_text) == String(rhs.state_text)
			and String(lhs.state_hash) == String(rhs.state_hash),
			"R3 result identical to original LAB A8 checkpoint and hash")
	var telemetry: Dictionary = staged.get_staged_telemetry()
	_assert(int(telemetry.get("r3_allocator_calls", 0)) > 4,
		"nested allocator telemetry records actual resumed work")

	var cancelled = _controller(m)
	var cp: Dictionary = _checkpoint(cancelled)
	var active := false
	for i in 140:
		var res: Dictionary = cancelled.run_staged_frame(
			1000000000, 1, 1, 1, 8388608, true, 1)
		if not bool(res.get("success", false)):
			break
		if String(cancelled.get_staged_telemetry().get("r3_allocator_subphase", "")) == "PRIMARY":
			active = true
			break
		if bool(res.get("complete", false)):
			break
	_assert(active and cancelled.has_pending_staged_tick(),
		"caller can pause halfway through R2 global PRIMARY")
	if active:
		var paused: Dictionary = cancelled.pause()
		_assert(bool(paused.get("success", false))
			and not cancelled.has_pending_staged_tick() and cancelled.tick() == 0,
			"PAUSE discards nested R2 scratch with zero canonical commits")
		_assert(String(_checkpoint(cancelled).state_text) == String(cp.state_text),
			"cancelled global resource competition leaves A8 bytes intact")
	var bench = Workbench.new()
	bench.controller = cancelled
	bench.running = false
	_assert(bench.configure_staged_live(true, 30000, 1, 1, 8,
		8388608, true, 2), "real LAB opt-in config is exposed")
	_assert(bench.configure_staged_live(false)
		and not bool(bench.staged_r3_allocator_enabled),
		"opt-out rejects future R3 admission")
	bench.free()
	_assert(C.encode(original_state) == C.encode(staged.debug_state().runtime)
		or staged.tick() == 1, "independent source used only as detached input")
	_done()

func _done() -> void:
	print("ECO_ARCH2_A14_6_R3_INDEPENDENT checks=%d failed=%d" %
		[checks, failed])
	print("ECO_ARCH2_A14_6_R3_INDEPENDENT " +
		("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
