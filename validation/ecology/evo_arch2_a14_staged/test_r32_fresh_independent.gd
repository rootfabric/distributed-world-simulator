extends SceneTree
## Fresh independent A14.6 R3.2 native async LAB falsifier. Test-only.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Host = preload("res://scripts/labs/ecology/eco_arch2_polygon_lab.gd")
const Worker = preload("res://scripts/ecology/workbench/off_main_r3_session_v1.gd")
const MAX_POLLS := 1500
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _assert(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ECO_A14_6_R32_FRESH_FAIL " + label)

func _controller(manifest: Dictionary) -> Object:
	var c = Controller.new()
	var r: Dictionary = c.initialize(manifest, {})
	_assert(bool(r.get("success", false)), "trusted LAB controller initialized")
	return c

func _run() -> void:
	var host = Host.new()
	host._build_manifest()
	var manifest: Dictionary = host.manifest.duplicate(true)
	host.free()
	_assert(String(manifest.get("mode", "")) == "LAB", "LAB-only host manifest")
	if String(manifest.get("mode", "")) == "LAB":
		await _complete_and_compare(manifest)
		await _cancel_and_reap(manifest)
		await _stale_completed_source(manifest)
	print("ECO_ARCH2_A14_6_R32_INDEPENDENT checks=%d failed=%d" %
		[checks, failures])
	print("ECO_ARCH2_A14_6_R32_INDEPENDENT " +
		("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)

func _complete_and_compare(manifest: Dictionary) -> void:
	var c: Object = _controller(manifest)
	var reference: Object = _controller(manifest)
	var source: Dictionary = c.debug_state().runtime
	var before: String = C.encode(source)
	var opts: Dictionary = c._canonical_step_options()
	_assert(bool(opts.get("success", false)), "versioned canonical options")
	if not bool(opts.get("success", false)):
		return
	var advanced: Dictionary = reference.step()
	_assert(bool(advanced.get("success", false)), "accepted serial reference")
	var session = Worker.new()
	var begun: Dictionary = session.advance(source, opts.options, 8, 4096, 8388608)
	_assert(bool(begun.get("success", false)) and session.has_pending()
		and not begun.has("state"), "worker begins without publishing")
	var result: Dictionary = {}
	for i in MAX_POLLS:
		var outcome: Dictionary = session.advance(
			source, opts.options, 8, 4096, 8388608)
		_assert(bool(outcome.get("success", false)), "pending worker poll %d" % i)
		if not bool(outcome.get("success", false)):
			break
		if bool(outcome.get("complete", false)):
			result = outcome
			break
		_assert(not outcome.has("state") and not outcome.has("grants"),
			"no global A4 grants or biology before complete")
		await create_timer(0.02).timeout
	_assert(not result.is_empty(), "complete global worker result")
	if result.is_empty():
		session.cancel()
		return
	_assert(C.encode(result.state) == C.encode(reference.debug_state().runtime)
		and Runtime.state_hash(result.state) ==
			Runtime.state_hash(reference.debug_state().runtime),
		"A5/A4/A6 state bytes/hash equal independent serial reference")
	_assert(C.encode(source) == before and c.tick() == 0,
		"worker never mutated source canonical frontier")
	var s: Dictionary = session.status()
	_assert(int(s.jobs_started) == 1 and int(s.jobs_committed) == 1
		and int(s.tasks_joined) == 1 and int(s.jobs_failed) == 0,
		"one worker, one join, one atomic commit")

func _cancel_and_reap(manifest: Dictionary) -> void:
	var c: Object = _controller(manifest)
	var source: Dictionary = c.debug_state().runtime
	var original: String = C.encode(source)
	var opts: Dictionary = c._canonical_step_options()
	_assert(bool(opts.get("success", false)), "cancel test options")
	if not bool(opts.get("success", false)):
		return
	var s = Worker.new()
	var begun: Dictionary = s.advance(source, opts.options, 8, 4096, 8388608)
	_assert(bool(begun.get("success", false)) and not begun.has("state"),
		"cancelled worker was host-private")
	_assert(s.cancel() and not s.has_pending(),
		"cancellation blocks stale generation publication")
	var drained := false
	for i in MAX_POLLS:
		if s.reap_discarded():
			drained = true
			break
		await create_timer(0.02).timeout
	_assert(drained and not s.is_draining(),
		"abandoned job eventually reaped without canonical adoption")
	var stats: Dictionary = s.status()
	_assert(int(stats.jobs_abandoned) == 1
		and int(stats.tasks_joined) == 1
		and int(stats.jobs_committed) == 0,
		"cancelled task joined exactly once, zero commits")
	_assert(C.encode(source) == original and c.tick() == 0,
		"cancelled A4 scratch cannot change canonical truth")

func _stale_completed_source(manifest: Dictionary) -> void:
	var c: Object = _controller(manifest)
	var source: Dictionary = c.debug_state().runtime
	var opts: Dictionary = c._canonical_step_options()
	_assert(bool(opts.get("success", false)), "stale test options")
	if not bool(opts.get("success", false)):
		return
	var s = Worker.new()
	var first: Dictionary = s.advance(source, opts.options, 8, 4096, 8388608)
	_assert(bool(first.get("success", false)), "stale-bound CPU task begins")
	var ready := false
	for i in MAX_POLLS:
		if WorkerThreadPool.is_task_completed(s._task_id):
			ready = true
			break
		await create_timer(0.02).timeout
	_assert(ready, "worker ended before stale-source falsifier")
	if not ready:
		s.cancel()
		return
	# Mutate only a DETACHED caller copy after worker has completed:
	# never race shared dictionaries across threads.
	var moved: Dictionary = source.duplicate(true)
	moved.tick = int(moved.tick) + 1
	var rejected: Dictionary = s.advance(
		moved, opts.options, 8, 4096, 8388608)
	_assert(not bool(rejected.get("success", false))
		and String(rejected.get("error", "")) == "R3_ASYNC_SOURCE_CHANGED",
		"stale source prevents publication after worker finished")
	_assert(not rejected.has("state") and not rejected.has("grants")
		and int(s.status().jobs_committed) == 0
		and int(s.status().tasks_joined) == 1,
		"failed stale worker joined with zero canonical commits")
