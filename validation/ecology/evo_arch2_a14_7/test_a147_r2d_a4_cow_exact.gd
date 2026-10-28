extends SceneTree
## ECO A14.7 R2 Stage D — immutable cursor COW/seal and full A4 original
## exact proof, using an actual unmodified FROZEN R2C A4 source script.
## The benchmark copies nothing out of Runtime into canonical output.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const Lifecycle = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const A4 = preload("res://scripts/research/ecology/v2/a4_staged_global_allocator_probe_v1.gd")
const Frozen = preload("res://validation/ecology/evo_arch2_a14_7/a147_r2d_frozen_a4_reference.gd")
const Fixture = preload("res://validation/ecology/evo_arch2_a14_7/a147_scale_fixture.gd")

const SIZES := [4, 32, 96, 256]
const CAP := 8388608
const QUOTA := 4096
var checks := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("A147_R2D_FAIL " + label)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or String(args[0]) != "--population" \
			or not String(args[1]) in ["4", "32", "96", "256"]:
		_check(false, "exact 4/32/96/256 population argument required")
		_finish()
		return
	var n := int(args[1])
	var source: Dictionary = Fixture.new().create_population(n)
	_check(not source.is_empty() and source.population.size() == n,
		"frozen original canonical population created")
	if source.is_empty():
		_finish()
		return
	var state_before: String = C.encode(source)
	var field: Dictionary = source.field
	var population: Array = source.population
	# Generate precisely the SAME A5 canonical demands as the accepted
	# single-owner Staged A4 path. A5 is not changed in R2D.
	var starter: Dictionary = Lifecycle.staged_begin(
		field, population, String(field.owner_token),
		int(field.owner_epoch), int(field.revision), 4, 64, true)
	_check(bool(starter.get("success", false)), "unchanged staged A5 begin")
	if not bool(starter.get("success", false)):
		_finish()
		return
	var lifecycle: Dictionary = starter.cursor
	for i in 128:
		if String(lifecycle.phase) == "ALLOCATE":
			break
		_check(String(lifecycle.phase) == "PREPARE",
				"no A4 before full global PREPARE frontier")
		var result: Dictionary = Lifecycle.staged_resume(
			lifecycle, field, population, 16, QUOTA, CAP, 1)
		if not bool(result.get("success", false)):
			_check(false, "unchanged PREPARE:" + String(result.get("error", "?")))
			_finish()
			return
		lifecycle = result.cursor
	_check(String(lifecycle.phase) == "ALLOCATE" \
		and lifecycle.demands.size() > 0,
		"full ORIGINAL global A4 demand batch ready")
	if String(lifecycle.phase) != "ALLOCATE" or lifecycle.demands.is_empty():
		_finish()
		return
	var demands: Array = lifecycle.demands.duplicate(true)
	var original_demands: String = C.encode(demands)
	_test_seal_boundaries()
	var ref_started_us: int = Time.get_ticks_usec()
	var reference: Dictionary = Field.allocate_demands(
		field, demands, String(field.owner_token),
		int(field.owner_epoch), int(field.revision))
	var reference_wall_us: int = Time.get_ticks_usec() - ref_started_us
	_check(bool(reference.get("success", false)), "one ORIGINAL global A4 authority")
	if not bool(reference.get("success", false)):
		_finish()
		return
	var old: Dictionary = _exercise(Frozen, field, demands, "FROZEN_R2C")
	var revised: Dictionary = _exercise(A4, field, demands, "R2D")
	if old.is_empty() or revised.is_empty():
		_finish()
		return
	for row in [old, revised]:
		var response: Dictionary = row.final
		_check(bool(response.get("reference_equal", false)) \
			and String(response.state_hash) == String(reference.state_hash),
			"ORIGINAL A4 reference equality maintained")
		_check(C.encode(response.state) == C.encode(reference.state) \
			and C.encode(response.grants) == C.encode(reference.grants) \
			and int(response.revision) == int(reference.revision) \
			and String(response.grants_hash) == C.digest(reference.grants),
			"complete FIELD+GRANTS+ledger+revision bytes EXACT original")
	_check(C.encode(old.final.state) == C.encode(revised.final.state) \
		and C.encode(old.final.grants) == C.encode(revised.final.grants),
		"frozen old source and optimized full A4 serialized bytes identical")
	_check(old.step_count == revised.step_count and old.step_count > 0 \
		and C.encode(old.phases) == C.encode(revised.phases),
		"R2D never drops/reorders original R2 A4 cursor phases")
	_check(C.encode(source) == state_before and C.encode(demands) == original_demands,
		"global source field and original demand array never mutated")
	print("A147_R2D_A4_COMPARE_JSON " + JSON.stringify({
		"schema": "dws.ecology.a147-r2d-a4-phase-cow-proof.v1",
		"population": n, "cursor_cap": CAP,
		"frozen_a4_wall_us": int(old.wall_us),
		"r2d_a4_wall_us": int(revised.wall_us),
		"speedup_ratio": float(old.wall_us) / maxf(1.0, float(revised.wall_us)),
		"original_authority_wall_us": reference_wall_us,
		"old_steps": old.step_count, "new_steps": revised.step_count,
		"old_phase_sequence": old.phases,
		"new_phase_sequence": revised.phases,
		"old_peak_cursor_bytes": old.peak_cursor_bytes,
		"new_peak_cursor_bytes": revised.peak_cursor_bytes,
		"full_grants_field_ledger_revision_equal": true,
		"old_full_cursor_immutability": bool(old.cursor_immutable),
		"new_full_cursor_immutability": bool(revised.cursor_immutable),
		"single_global_a4_reference_kept": true,
		"untrusted_cursor_checksum_validation_kept": true,
		"source_unchanged": C.encode(source) == state_before,
		"same_biology": true, "hard_one_second_sla_claim": false,
	}))
	_finish()

func _test_seal_boundaries() -> void:
	# A cursor with Unicode and nested keys exercises canonical UTF8 length.
	# R2D's 64-byte checksum length arithmetic MUST agree with 2-pass OLD.
	var sample: Dictionary = {"checksum": "", "name": "Δ🌍 metadata",
		"nested": [{"id": "a", "v": 23}, {"b": true, "s": "└──►"}],
		"unimportant": ["x", 2, null]}
	var big_cap := 16777216
	var old: Dictionary = Frozen._seal_cursor(sample.duplicate(true), big_cap)
	var revised: Dictionary = A4._seal_cursor(sample.duplicate(true), big_cap)
	_check(not old.is_empty() and C.encode(old) == C.encode(revised) \
		and String(old.checksum) == String(revised.checksum),
		"single encode SHA256 EXACT frozen double-encode even with Unicode")
	if old.is_empty():
		return
	var actual_bytes: int = C.encode(old).to_utf8_buffer().size()
	for cap in [actual_bytes - 1, actual_bytes, actual_bytes + 1, 1024]:
		var historical: Dictionary = Frozen._seal_cursor(sample.duplicate(true), cap)
		var current: Dictionary = A4._seal_cursor(sample.duplicate(true), cap)
		_check(C.encode(historical) == C.encode(current) \
			and historical.is_empty() == current.is_empty(),
			"byte-exact cap boundary n=%d" % cap)
	_check(C.encode(sample) == C.encode({"checksum":"","name":"Δ🌍 metadata",
		"nested":[{"id":"a","v":23},{"b":true,"s":"└──►"}],
		"unimportant":["x",2,null]}), "frozen seal input was detached")

func _exercise(backend: Script, field: Dictionary, demands: Array,
		label: String) -> Dictionary:
	var wall_start: int = Time.get_ticks_usec()
	var spawned: Dictionary = backend.begin(
		field, demands, String(field.owner_token),
		int(field.owner_epoch), int(field.revision), CAP)
	_check(bool(spawned.get("success", false)), label + " A4 begin accepted")
	if not bool(spawned.get("success", false)):
		return {}
	var cursor: Dictionary = spawned.cursor
	# Same nested tamper must be rejected before touching field or grants.
	var corrupted: Dictionary = cursor.duplicate(true)
	corrupted.index = int(corrupted.index) + 1
	var rejected: Dictionary = backend.resume(
		field, demands, String(field.owner_token),
		int(field.owner_epoch), int(field.revision), corrupted, QUOTA, CAP)
	_check(not bool(rejected.get("success", true)) \
		and String(rejected.get("error", "")).contains("CURSOR_CHECKSUM"),
		label + " still rejects forged cursor index")
	var phases: Array = []
	var count := 0
	var peak_bytes := 0
	var immutable := true
	var finished: Dictionary = {}
	for iteration in 512:
		var phase: String = String(cursor.phase)
		if phases.is_empty() or String(phases.back()) != phase:
			phases.append(phase)
		var original_cursor: String = C.encode(cursor)
		peak_bytes = maxi(peak_bytes, original_cursor.to_utf8_buffer().size())
		var result: Dictionary = backend.resume(
			field, demands, String(field.owner_token), int(field.owner_epoch),
			int(field.revision), cursor, QUOTA, CAP)
		immutable = immutable and C.encode(cursor) == original_cursor
		count += 1
		if not bool(result.get("success", false)):
			_check(false, label + " A4 resume error:" +
				String(result.get("error", "?")))
			break
		if bool(result.get("complete", false)):
			finished = result
			break
		_check(not result.has("state") and not result.has("grants") \
			and result.has("cursor"),
			label + " no partially canonical state or grant exposure")
		cursor = result.cursor
	var elapsed_us: int = maxi(0, Time.get_ticks_usec() - wall_start)
	_check(not finished.is_empty() and immutable \
		and phases == ["NORMALIZE", "BUILD_CLAIMS", "PRIMARY", "RESIDUAL", "FINALIZE"],
		label + " all five global A4 stages exact and COW input preserved")
	return {"final": finished, "wall_us": elapsed_us,
		"step_count": count, "phases": phases,
		"peak_cursor_bytes": peak_bytes, "cursor_immutable": immutable} \
		if not finished.is_empty() else {}

func _finish() -> void:
	print("A147_R2D_A4 checks=%d failed=%d" % [checks, failed])
	print("A147_R2D_A4 " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
