extends SceneTree
## FRESH, independently-authored A14.7 R2E verifier, direct child of frozen
## product HEAD. Checks EVERY sealed intermediate cursor, not just final hash.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const A5 = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const FrozenA5 = preload("res://validation/ecology/evo_arch2_a14_7/a147_r2e_frozen_a5_reference.gd")
const OffMain = preload("res://scripts/ecology/workbench/off_main_r3_session_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Host = preload("res://scripts/labs/ecology/eco_arch2_polygon_lab.gd")
const Fixture = preload("res://validation/ecology/evo_arch2_a14_7/a147_scale_fixture.gd")

var checks := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("R2E_INDEPENDENT_FAIL " + label)

func _options() -> Dictionary:
	var lab = Host.new()
	lab._build_manifest()
	var manifest: Dictionary = lab.manifest.duplicate(true)
	lab.free()
	manifest.seed = 20261015
	manifest.mutation.mutations_enabled = false
	var ctrl = Controller.new()
	var result: Dictionary = ctrl.initialize(manifest, {})
	_check(bool(result.get("success", false)), "real LAB Controller options")
	return ctrl._canonical_step_options().options \
		if bool(result.get("success", false)) else {}

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2 or String(args[0]) != "--population" \
			or not String(args[1]) in ["32", "96"]:
		_check(false, "32/96 independent exact scale required")
		_finish()
		return
	var n: int = int(args[1])
	var source: Dictionary = Fixture.new().create_population(n)
	_check(not source.is_empty() and source.population.size() == n,
		"real canonical source fixture")
	if source.is_empty():
		_finish()
		return
	var frozen_input_bytes: String = C.encode(source)
	var field: Dictionary = source.field
	var population: Array = source.population
	var old_start: Dictionary = FrozenA5.staged_begin(
		field, population, String(field.owner_token),
		int(field.owner_epoch), int(field.revision), 4, 64, true)
	var new_start: Dictionary = A5.staged_begin(
		field, population, String(field.owner_token),
		int(field.owner_epoch), int(field.revision), 4, 64, true)
	_check(bool(old_start.get("success", false)) and
		bool(new_start.get("success", false)),
		"old/new staged A5 starts exact frozen global field")
	if not bool(old_start.get("success", false)) or not bool(new_start.get("success", false)):
		_finish()
		return
	var old_cursor: Dictionary = old_start.cursor
	var new_cursor: Dictionary = new_start.cursor
	_check(C.encode(old_cursor) == C.encode(new_cursor),
		"first cursor exact full canonical bytes")
	var checked_tamper := false
	var checked_source_tamper := false
	var calls := 0
	var phases: Array = []
	var last_old: Dictionary = {}
	var last_new: Dictionary = {}
	for i in 4096:
		var before_old: String = C.encode(old_cursor)
		var before_new: String = C.encode(new_cursor)
		_check(before_old == before_new,
			"old/new cursor exact at resume %d" % i)
		if before_old != before_new:
			break
		var phase: String = String(old_cursor.phase)
		if phases.is_empty() or String(phases.back()) != phase:
			phases.append(phase)
		# The explicit R2E profiling parameter must not alter cursor bytes.
		var old_step: Dictionary = FrozenA5.staged_resume(
			old_cursor, field, population, 16, 4096, 8388608, 4)
		var new_step: Dictionary = A5.staged_resume(
			new_cursor, field, population, 16, 4096, 8388608, 4, true)
		calls += 1
		_check(C.encode(old_cursor) == before_old and
			C.encode(new_cursor) == before_new,
			"all earlier nested cursor/field aliases immutable after resume")
		_check(bool(old_step.get("success", false)) and
			bool(new_step.get("success", false)),
			"both owners complete exact incremental step")
		if not bool(old_step.get("success", false)) or \
				not bool(new_step.get("success", false)):
			break
		var metrics: Dictionary = new_step.get("r2e_profile", {})
		_check(metrics.has("cursor_verify_us") and
			metrics.has("source_digest_us") and
			metrics.has("cow_copy_us"),
			"every R2E call preserved full source and checksum profile")
		if bool(old_step.get("complete", false)):
			_check(bool(new_step.get("complete", false)),
				"old and new complete at exactly same generation")
			last_old = old_step
			last_new = new_step
			break
		_check(not bool(new_step.get("complete", false)),
			"new cannot canonically commit earlier")
		_check(C.encode(old_step.cursor) == C.encode(new_step.cursor),
			"every intermediate R3 signed cursor byte-identical to frozen")
		_check(not new_step.has("field") and not new_step.has("population") \
			and not new_step.has("state") and not new_step.has("grants"),
			"no partial field/grants/state published before global A4")
		if not checked_tamper and phase == "PREPARE" and \
				new_step.cursor.demands.size() > 0:
			var corrupted: Dictionary = new_step.cursor.duplicate(true)
			corrupted.demands[0].amount = int(corrupted.demands[0].amount) + 1
			var rejected: Dictionary = A5.staged_resume(
				corrupted, field, population, 16, 4096, 8388608, 4, true)
			_check(not bool(rejected.get("success", true)) and
				String(rejected.get("error", "")) == "A5_STAGED_CURSOR_CHECKSUM",
				"R2E strict deep demand tamper must reject before A4")
			checked_tamper = true
		if not checked_source_tamper and phase == "PREPARE":
			var mutated: Array = population.duplicate(true)
			mutated[0].state.age_ticks = int(mutated[0].state.age_ticks) + 1
			var rejected_state: Dictionary = A5.staged_resume(
				new_step.cursor, field, mutated, 16, 4096, 8388608, 4, true)
			_check(not bool(rejected_state.get("success", true)) and
				String(rejected_state.get("error", "")) == "A5_STAGED_SOURCE_CHANGED",
				"R2E strict deeply changed source rejected despite matching header")
			checked_source_tamper = true
		old_cursor = old_step.cursor
		new_cursor = new_step.cursor
	_check(not last_old.is_empty() and not last_new.is_empty() and
		checked_tamper and checked_source_tamper,
		"full frozen/new tick and hostile nested falsifiers completed")
	if last_old.is_empty() or last_new.is_empty():
		_finish()
		return
	_check(phases == ["PREPARE", "ALLOCATE", "ADVANCE"],
		"original global phase ordering unchanged")
	_check(C.encode(last_old.field) == C.encode(last_new.field) \
		and C.encode(last_old.population) == C.encode(last_new.population) \
		and C.encode(last_old.propagules) == C.encode(last_new.propagules),
		"complete canonical global field/organism/propagule byte equality")
	_check(C.encode(source) == frozen_input_bytes,
		"original source field/population left untouched")
	# Host-level live mutation after completed, before admission still
	# triggers full final Runtime.validate even with r2e_profile=true.
	await _check_late_untrusted_mutation(source)
	print("A147_R2E_FRESH_JSON " + JSON.stringify({
		"schema": "dws.ecology.a147-r2e-fresh-verifier.v1",
		"population": n, "calls": calls, "phases": phases,
		"every_cursor_exact": true, "full_source_validation": true,
		"tamper_falsifier": checked_tamper, "source_falsifier": checked_source_tamper,
		"same_full_global_field": C.encode(last_old.field) == C.encode(last_new.field),
		"same_full_population": C.encode(last_old.population) == C.encode(last_new.population),
		"source_unchanged": C.encode(source) == frozen_input_bytes,
	}))
	_finish()

func _check_late_untrusted_mutation(source: Dictionary) -> void:
	var opts: Dictionary = _options()
	if opts.is_empty():
		return
	var external: Dictionary = source.duplicate(true)
	var job = OffMain.new()
	var begun: Dictionary = job.advance(external, opts,
		64, 4096, 8388608, null, null, -1, {}, 16, 4, true)
	_check(bool(begun.get("success", false)), "untrusted R2E worker starts")
	if not bool(begun.get("success", false)):
		return
	var completed := false
	for i in 12000:
		if WorkerThreadPool.is_task_completed(job._task_id):
			completed = true
			break
		await create_timer(0.02).timeout
	_check(completed, "worker completed before late source mutation")
	if not completed:
		job.cancel()
		return
	# Header source hash/tick deliberately NOT updated.
	external.population[0].state.age_ticks = int(external.population[0].state.age_ticks) + 1
	var denied: Dictionary = job.advance(external, opts,
		64, 4096, 8388608, null, null, -1, {}, 16, 4, true)
	_check(not bool(denied.get("success", true)) \
		and String(denied.get("error", "")).begins_with("R3_ASYNC_SOURCE_INVALID:"),
		"late untrusted nested mutation rejected by unchanged FULL Runtime.validate")
	_check(int(job.status().jobs_committed) == 0 and
		int(job.status().tasks_joined) == 1,
		"late untrusted source never committed and worker joined")

func _finish() -> void:
	print("A147_R2E_FRESH checks=%d failed=%d" % [checks, failed])
	print("A147_R2E_FRESH " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
