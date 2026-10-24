extends SceneTree
## FRESH independent R2D test, direct child of frozen product HEAD.
## Calls actual A5 and global A4 PUBLIC functions (does not use R2D's
## product test nor the frozen legacy test copy).
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Lifecycle = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const A4 = preload("res://scripts/research/ecology/v2/a4_staged_global_allocator_probe_v1.gd")
const Fixture = preload("res://validation/ecology/evo_arch2_a14_7/a147_scale_fixture.gd")

const CAP := 8388608
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("A147_R2D_INDEPENDENT_FAIL " + label)

func _run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or String(args[0]) != "--population" \
			or not String(args[1]) in ["32", "96"]:
		_check(false, "invalid independent population")
		_finish()
		return
	var n: int = int(args[1])
	var state: Dictionary = Fixture.new().create_population(n)
	_check(not state.is_empty(), "valid stable founder field")
	if state.is_empty():
		_finish()
		return
	var snapshot_before: String = C.encode(state)
	var source_field: Dictionary = state.field
	var source_population: Array = state.population
	var initial: Dictionary = Lifecycle.staged_begin(
		source_field, source_population, String(source_field.owner_token),
		int(source_field.owner_epoch), int(source_field.revision), 4, 64, true)
	_check(bool(initial.get("success", false)), "strict A5 starts")
	if not bool(initial.get("success", false)):
		_finish()
		return
	var lifecycle: Dictionary = initial.cursor
	for i in 128:
		if String(lifecycle.phase) == "ALLOCATE":
			break
		var progressed: Dictionary = Lifecycle.staged_resume(
			lifecycle, source_field, source_population, 16, 4096, CAP, 1)
		_check(bool(progressed.get("success", false)), "strict PREPARE")
		if not bool(progressed.get("success", false)):
			_finish()
			return
		lifecycle = progressed.cursor
	_check(String(lifecycle.phase) == "ALLOCATE" and
		lifecycle.demands.size() > 0, "A4 start ONLY after all original demands")
	if String(lifecycle.phase) != "ALLOCATE":
		_finish()
		return
	var demands: Array = lifecycle.demands.duplicate(true)
	var original_demands: String = C.encode(demands)
	var original: Dictionary = Field.allocate_demands(
		source_field, demands, String(source_field.owner_token),
		int(source_field.owner_epoch), int(source_field.revision))
	_check(bool(original.get("success", false)), "original A4 sole authority")
	if not bool(original.get("success", false)):
		_finish()
		return
	var begun: Dictionary = A4.begin(
		source_field, demands, String(source_field.owner_token),
		int(source_field.owner_epoch), int(source_field.revision), CAP)
	_check(bool(begun.get("success", false)), "R2D detached staging accepted")
	if not bool(begun.get("success", false)):
		_finish()
		return
	var cursor: Dictionary = begun.cursor
	# Falsifier A: mutate nested sealed field stock without fixing checksum.
	var tamper: Dictionary = cursor.duplicate(true)
	tamper.working_field.cells[0].stocks.water_mg += 1
	var denied: Dictionary = A4.resume(
		source_field, demands, String(source_field.owner_token),
		int(source_field.owner_epoch), int(source_field.revision), tamper,
		4096, CAP)
	_check(not bool(denied.get("success", true)) and
		String(denied.get("error", "")).contains("CURSOR_CHECKSUM"),
		"adversarial nested field alias tamper cannot bypass SHA256")
	# Falsifier B: change a demand without changing source/cursor.
	var altered: Array = demands.duplicate(true)
	altered[0].amount = int(altered[0].amount) + 1
	var wrong_demand: Dictionary = A4.resume(
		source_field, altered, String(source_field.owner_token),
		int(source_field.owner_epoch), int(source_field.revision), cursor,
		4096, CAP)
	_check(not bool(wrong_demand.get("success", true)) and
		String(wrong_demand.get("error", "")).contains("SOURCE_CHANGED"),
		"altered demand cannot reuse already sealed A4 cursor")
	# Falsifier C: stale owner revision.
	var changed_revision: Dictionary = A4.resume(
		source_field, demands, String(source_field.owner_token),
		int(source_field.owner_epoch), int(source_field.revision) + 1, cursor,
		4096, CAP)
	_check(not bool(changed_revision.get("success", true)) and
		String(changed_revision.get("error", "")).contains("STALE_REVISION"),
		"owner revision admission has not been weakened")
	var phase_order: Array = []
	var steps := 0
	var original_cursor_bytes_unchanged := true
	var result: Dictionary = {}
	for i in 512:
		var phase: String = String(cursor.phase)
		if phase_order.is_empty() or String(phase_order.back()) != phase:
			phase_order.append(phase)
		var cursor_bytes: String = C.encode(cursor)
		var advanced: Dictionary = A4.resume(
			source_field, demands, String(source_field.owner_token),
			int(source_field.owner_epoch), int(source_field.revision), cursor,
			4096, CAP)
		original_cursor_bytes_unchanged = original_cursor_bytes_unchanged and \
			C.encode(cursor) == cursor_bytes
		steps += 1
		if not bool(advanced.get("success", false)):
			_check(false, "A4 R2D stage:" + String(advanced.get("error", "?")))
			break
		if bool(advanced.get("complete", false)):
			result = advanced
			break
		_check(advanced.has("cursor") and not advanced.has("grants") and
			not advanced.has("state"), "no partial global grants published")
		cursor = advanced.cursor
	_check(not result.is_empty(), "global A4 finishes")
	if result.is_empty():
		_finish()
		return
	_check(phase_order == ["NORMALIZE", "BUILD_CLAIMS", "PRIMARY",
		"RESIDUAL", "FINALIZE"], "historical deterministic global stage ordering")
	_check(original_cursor_bytes_unchanged, "all previous cursors deeply immutable")
	_check(bool(result.reference_equal) and
		C.encode(result.state) == C.encode(original.state) and
		C.encode(result.grants) == C.encode(original.grants) and
		String(result.state_hash) == String(original.state_hash),
		"original A4 field/grant/revision/ledger exact bytes and SHA")
	_check(C.encode(state) == snapshot_before and
		C.encode(demands) == original_demands, "source and original demand untouched")
	print("A147_R2D_INDEPENDENT_JSON " + JSON.stringify({
		"schema": "dws.ecology.a147-r2d-independent-a4.v1",
		"population": n, "phase_order": phase_order, "steps": steps,
		"exact_a4_state": C.encode(result.state) == C.encode(original.state),
		"exact_a4_grants": C.encode(result.grants) == C.encode(original.grants),
		"cursor_input_immutable": original_cursor_bytes_unchanged,
		"frozen_source_unchanged": C.encode(state) == snapshot_before,
		"single_original_global_reference": true,
	}))
	_finish()

func _finish() -> void:
	print("A147_R2D_INDEPENDENT checks=%d failed=%d" % [checks, failures])
	print("A147_R2D_INDEPENDENT " + ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
