extends SceneTree
## A14.6 R3.2.3 FRESH independent verifier: product tests not imported.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Workbench = preload("res://scripts/ecology/workbench/ecology_workbench.gd")
const OffMain = preload("res://scripts/ecology/workbench/off_main_r3_session_v1.gd")
const Host = preload("res://scripts/labs/ecology/eco_arch2_polygon_lab.gd")

var checks := 0
var fails := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		push_error("ECO_R323_FRESH_FAIL " + label)

func _manifest() -> Dictionary:
	var host = Host.new()
	host._build_manifest()
	var m: Dictionary = host.manifest.duplicate(true)
	host.free()
	return m

func _controller(m: Dictionary) -> Object:
	var c = Controller.new()
	_check(bool(c.initialize(m, {}).get("success", false)), "actual LAB init")
	return c

func _workbench(c: Object, events: Array) -> Node:
	var b = Workbench.new()
	b.controller = c
	b._status_bar = Label.new()
	b.running = true
	b.ticks_per_second = 1.0
	b.pending_target = {"kind": "tick", "value": 1}
	b.snapshot_updated.connect(func(s: Dictionary) -> void:
		events.append(s)
	)
	_check(b.configure_staged_live(true, 1000000000, 1, 1, 8, 8388608,
		true, 4096, true, true), "explicit LAB R323 opt-in")
	return b

func _await_commit(c: Object, b: Node) -> bool:
	for i in 1000:
		b._process(1.0 if i == 0 else 0.0)
		if int(c.tick()) == 1:
			return true
		await create_timer(0.02).timeout
	return false

func _dispose(b: Node) -> void:
	b._status_bar.free()
	b.free()

func _run() -> void:
	var m: Dictionary = _manifest()
	_check(String(m.get("mode", "")) == "LAB", "real LAB not WORLD_COMPAT")
	var defaults = Workbench.new()
	_check(not defaults.staged_r323_presentation_enabled \
		and not defaults.staged_r3_off_main_enabled and not defaults.staged_live_enabled,
		"R323 and accepted offmain are OFF by default")
	_check(not defaults.configure_staged_live(true, 30000, 1, 1,
		8, 8388608, true, 16, false, true),
		"no R323 without R3 allocator AND worker")
	defaults.free()
	await _test_commit_exact(m)
	await _test_stale_restore(m)
	await _test_human_optout(m)
	_test_direct_forgery(m)
	print("ECO_ARCH2_A14_6_R323_FRESH_VERIFIER checks=%d failed=%d" % [checks, fails])
	print("ECO_ARCH2_A14_6_R323_FRESH_VERIFIER " + ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)

func _test_commit_exact(m: Dictionary) -> void:
	var c = _controller(m)
	var serial = _controller(m)
	var events: Array = []
	var b = _workbench(c, events)
	var committed: bool = await _await_commit(c, b)
	_check(committed and b.get_r323_ui_telemetry().pending,
		"one complete canonical tick before staged visuals")
	_check(events.is_empty(), "no partial snapshot_updated during worker")
	_check(bool(serial.step().get("success", false)) \
		and String(c.serialize_state().state_text) == String(serial.serialize_state().state_text),
		"canonical tick and A8 bytes exact before visual completion")
	var fast: Dictionary = c.get_r323_snapshot()
	var slow: Dictionary = c.get_snapshot()
	_check(bool(fast.get("success", false)) and C.encode(fast) == C.encode(slow),
		"independent cached snapshot equals original full projection")
	for i in 100:
		if not bool(b.get_r323_ui_telemetry().pending):
			break
		b._process(0.0)
	_check(not b.get_r323_ui_telemetry().pending and int(b.get_r323_ui_telemetry().completed) == 1 \
		and int(b.get_r323_ui_telemetry().fallbacks) == 0,
		"bounded GUI finish with no full snapshot fallback")
	_check(events.size() == 1 and int(events[0].tick) == 1 \
		and String(events[0].canonical_state_hash) == String(c._runtime.integrity_hash),
		"exactly one immutable completed snapshot event")
	b._process(0.0)
	_check(events.size() == 1, "no duplicate event after stop at tick")
	_dispose(b)

func _test_stale_restore(m: Dictionary) -> void:
	var c = _controller(m)
	var anchor: Dictionary = c.serialize_state()
	var events: Array = []
	var b = _workbench(c, events)
	var committed: bool = await _await_commit(c, b)
	_check(committed and b.get_r323_ui_telemetry().pending,
		"UI queue pending after canonical tick for restore")
	if not committed:
		_dispose(b)
		return
	var restored: Dictionary = c.load_state(String(anchor.state_text),
		String(anchor.manifest_hash), String(anchor.state_checksum))
	_check(bool(restored.get("success", false)) and int(c.tick()) == 0,
		"externally anchored restore supersedes pending UI")
	b._process(0.0)
	_check(not b.get_r323_ui_telemetry().pending \
		and int(b.get_r323_ui_telemetry().abandoned) == 1 \
		and String(b.get_r323_ui_telemetry().last_error) == "R323_PRESENTATION_STALE",
		"restore invalidates stale GUI job and reconciles current state")
	_check(events.size() == 1 and int(events[0].tick) == 0 \
		and String(events[0].canonical_state_hash) == String(c._runtime.integrity_hash),
		"stale tick 1 never signaled after restore")
	_check(String(c.serialize_state().state_text) == String(anchor.state_text),
		"presentation has no write into canonical checkpoint")
	_dispose(b)

func _test_human_optout(m: Dictionary) -> void:
	var c = _controller(m)
	var events: Array = []
	var b = _workbench(c, events)
	var committed: bool = await _await_commit(c, b)
	_check(committed and b.get_r323_ui_telemetry().pending,
		"mode switch sees unfinished R323 presentation")
	if not committed:
		_dispose(b)
		return
	_check(b.configure_staged_live(false) \
		and not b.get_r323_ui_telemetry().pending \
		and not b.staged_r323_presentation_enabled,
		"manual R323 opt-out cancels UI-only queue")
	_check(events.size() == 1 and int(events[0].tick) == 1 \
		and int(c.tick()) == 1,
		"manual switch draws fully committed canonical tick only")
	_dispose(b)

func _test_direct_forgery(m: Dictionary) -> void:
	var c = _controller(m)
	var direct = OffMain.new()
	var state: Dictionary = c.debug_state().runtime
	var opts: Dictionary = c._canonical_step_options().options
	var denied: Dictionary = direct.advance(state, opts, 8, 4096, 8388608,
		null, null, -1, m)
	_check(not bool(denied.get("success", true)) \
		and String(denied.get("error", "")) == "R323_SNAPSHOT_REQUIRES_CONTROLLER_LEASE",
		"untrusted caller cannot forge projection without Controller lease")
	_check(int(direct.status().jobs_started) == 0,
		"forged snapshot task not dispatched")
