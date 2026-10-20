extends SceneTree
## ECO A14.6 R2: adversarial exact staged GLOBAL A4 allocation proof.
## The original Field.allocate_demands is the independent resource-owner
## reference and NO speculative cursor is a valid A5/Runtime checkpoint.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const Ports = preload("res://scripts/research/ecology/v2/organism_environment_ports_v1.gd")
const R2 = preload("res://scripts/research/ecology/v2/a4_staged_global_allocator_probe_v1.gd")

var checks := 0
var failures := 0
var records := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ECO_A14_6_R2_ALLOC_FAIL " + label)

func _new_field(width: int = 2, depth: int = 1,
		stock: int = 5) -> Dictionary:
	return Field.create("a146r2.probe", 1, [0, 0, 0], 1000,
		width, depth, F.stock(stock), F.stock(1000), F.signals())

func _d(id: String, organism: String, resource: String, amount: int,
		x: int, z: int = 500, extent: int = 0) -> Dictionary:
	return Ports.demand(id, organism, resource, amount,
		[x, 0, z], extent)

func _run() -> void:
	_tests_rounding_and_residual()
	_tests_state_and_integrity()
	_tests_stress()
	_finish()

func _run_all(f: Dictionary, demands: Array,
		quota: int, label: String, cap_bytes: int = 8388608) -> Dictionary:
	var initial_field: String = C.encode(f)
	var initial_demands: String = C.encode(demands)
	var direct: Dictionary = Field.allocate_demands(f, demands,
		String(f.owner_token), int(f.owner_epoch), int(f.revision))
	_check(bool(direct.get("success", false)), label + " reference A4 success")
	if not bool(direct.get("success", false)):
		return {}
	var begin: Dictionary = R2.begin(f, demands, String(f.owner_token),
		int(f.owner_epoch), int(f.revision), cap_bytes)
	_check(bool(begin.get("success", false))
		and String(begin.get("phase", "")) == "NORMALIZE",
		label + " bounded begin")
	if not bool(begin.get("success", false)):
		return {}
	var cursor: Dictionary = begin.cursor
	var phases := {"NORMALIZE": 0, "BUILD_CLAIMS": 0,
		"PRIMARY": 0, "RESIDUAL": 0, "FINALIZE": 0}
	var answer: Dictionary = {}
	var max_cursor_bytes := C.encode(cursor).to_utf8_buffer().size()
	var iterations := 0
	for i in 120:
		var current_phase: String = String(cursor.phase)
		if not phases.has(current_phase):
			_check(false, label + " invalid stage")
			break
		phases[current_phase] += 1
		var original_cursor: String = C.encode(cursor)
		var progressed: Dictionary = R2.resume(f, demands, String(f.owner_token),
			int(f.owner_epoch), int(f.revision), cursor, quota, cap_bytes)
		iterations += 1
		_check(bool(progressed.get("success", false)),
			label + " stage %s call %d: %s" % [
				current_phase, i, String(progressed.get("error", ""))])
		if not bool(progressed.get("success", false)):
			break
		_check(C.encode(f) == initial_field
			and C.encode(demands) == initial_demands
			and C.encode(cursor) == original_cursor,
			label + " source, demand and supplied cursor immutable")
		if bool(progressed.get("complete", false)):
			answer = progressed
			break
		_check(not progressed.has("state") and not progressed.has("grants")
			and progressed.has("cursor") and
			not bool(progressed.get("complete", true)),
			label + " incomplete stage never publishes A4 state or grants")
		var next_cursor: Dictionary = progressed.cursor
		var size: int = C.encode(next_cursor).to_utf8_buffer().size()
		_check(size > 0 and size <= cap_bytes, label + " cursor bounded bytes")
		max_cursor_bytes = maxi(max_cursor_bytes, size)
		cursor = next_cursor
	_check(not answer.is_empty(), label + " eventual global completion")
	if answer.is_empty():
		return {}
	_check(phases.NORMALIZE >= 1 and phases.BUILD_CLAIMS >= 1
		and phases.PRIMARY >= 1 and phases.RESIDUAL >= 1
		and phases.FINALIZE == 1, label + " all five stages observed once final")
	_check(C.encode(answer.state) == C.encode(direct.state)
		and C.encode(answer.grants) == C.encode(direct.grants),
		label + " full field and grants byte-identical original A4")
	_check(String(answer.state_hash) == String(direct.state_hash)
		and String(answer.grants_hash) == C.digest(direct.grants)
		and int(answer.revision) == int(direct.revision),
		label + " global hashes, owner revision and grants exact")
	_check(F.validate_state(answer.state).is_empty()
		and bool(answer.reference_equal),
		label + " final field sealed, conservative and original verified")
	_check(C.encode(f) == initial_field and C.encode(demands) == initial_demands,
		label + " canonical source and all demands never mutated")
	records += 1
	print("ECO_A14_6_R2_ALLOC_PROFILE_JSON " + JSON.stringify({
		"scenario": label, "demand_count": demands.size(),
		"phase_calls": phases, "resume_calls": iterations,
		"peak_cursor_bytes": max_cursor_bytes,
		"grants_hash": String(answer.grants_hash),
		"state_hash": String(answer.state_hash),
		"reference_equal": bool(answer.reference_equal),
	}))
	return answer

func _tests_rounding_and_residual() -> void:
	var field: Dictionary = _new_field(2, 1, 5)
	var original: String = C.encode(field)
	var competing: Array = [
		_d("z-large", "org-z", "water_mg", 10, 500),
		_d("a-large", "org-a", "water_mg", 7, 500),
		_d("b-smaller", "org-b", "water_mg", 3, 500),
		_d("independent", "org-c", "nutrient_mg", 2, 1500),
	]
	var truth: Dictionary = _run_all(field, competing, 1,
		"same-cell-pro-rata-rounding")
	_check(not truth.is_empty(), "primary pro-rata rounding proof complete")
	var reverse: Array = competing.duplicate(true)
	reverse.reverse()
	var shuffled: Dictionary = _run_all(field, reverse, 2,
		"permuted-primary-rounding")
	if not truth.is_empty() and not shuffled.is_empty():
		_check(C.encode(shuffled.state) == C.encode(truth.state)
			and C.encode(shuffled.grants) == C.encode(truth.grants),
			"different source order and quotas preserve exact resource grants")
	_check(C.encode(field) == original, "all rounding probes preserve original field")

	var starved: Dictionary = _new_field(2, 1, 0)
	var deposited: Dictionary = Field.apply_effects(starved, [
		Ports.effect("r2-seed-water", "soil", "deposit", "water_mg", 5,
			[1500, 0, 500], 0, "R2_EVIDENCE")
	], String(starved.owner_token), int(starved.owner_epoch),
		int(starved.revision))
	_check(bool(deposited.get("success", false)), "canonical A4 zero-primary seed")
	if not bool(deposited.get("success", false)):
		return
	var shared: Array = [
		_d("cross", "org-x", "water_mg", 1, 1000, 500, 600),
		_d("local", "org-l", "water_mg", 1, 1500),
		_d("nutrient", "org-n", "nutrient_mg", 1, 1500),
	]
	var proven: Dictionary = _run_all(deposited.state, shared, 1,
		"zero-primary-residual-cross-cell")
	if not proven.is_empty():
		var grant_by_id := {}
		for grant in proven.grants:
			grant_by_id[String(grant.request_id)] = int(grant.granted)
		_check(int(grant_by_id.get("cross", -1)) == 1
			and int(grant_by_id.get("local", -1)) == 1,
			"ZERO primary second-cell link still receives residual global grant")
		_check(int(proven.state.cells[1].stocks.water_mg) == 3,
			"ledger and source water preserved under double pro-rata")
	var two_resources: Array = [
		_d("n1", "org-n", "nutrient_mg", 4, 500),
		_d("w1", "org-w", "water_mg", 3, 1500),
		_d("o1", "org-o", "organic_mg", 2, 1500),
		_d("wide", "org-wide", "water_mg", 12, 1000, 500, 600),
	]
	_run_all(_new_field(2, 1, 5), two_resources, 2,
		"disjoint-resource-and-cross-cell")

func _tests_state_and_integrity() -> void:
	var field: Dictionary = _new_field(2, 1, 5)
	var demands: Array = [_d("a", "org-a", "water_mg", 3, 500),
		_d("b", "org-b", "water_mg", 3, 500)]
	var original: String = C.encode(field)
	var b: Dictionary = R2.begin(field, demands, String(field.owner_token),
		int(field.owner_epoch), int(field.revision))
	_check(bool(b.get("success", false)), "host transient cursor starts")
	if not bool(b.get("success", false)):
		return
	var cursor: Dictionary = b.cursor
	var frozen_cursor := C.encode(cursor)
	var tampered: Dictionary = cursor.duplicate(true)
	tampered.working_field.cells[0].stocks.water_mg = 999
	_check(String(R2.resume(field, demands, String(field.owner_token),
		int(field.owner_epoch), int(field.revision), tampered).get("error", ""))
		== "A14_6_R2_CURSOR_CHECKSUM",
		"nested cursor payload corruption caught BEFORE resource write")
	var old_schema: Dictionary = cursor.duplicate(true)
	old_schema.schema = "dws.ecology.a14-6-r2-staged-global-a4.v0"
	_check(String(R2.resume(field, demands, String(field.owner_token),
		int(field.owner_epoch), int(field.revision), old_schema).get("error", ""))
		== "A14_6_R2_CURSOR_SCHEMA",
		"old in-flight cursor rejected on version change")
	var changed: Array = demands.duplicate(true)
	changed[0].amount = 4
	_check(String(R2.resume(field, changed, String(field.owner_token),
		int(field.owner_epoch), int(field.revision), cursor).get("error", ""))
		== "A14_6_R2_SOURCE_CHANGED",
		"changed demands cannot resume speculative work")
	_check(String(R2.resume(field, demands, "other",
		int(field.owner_epoch), int(field.revision), cursor).get("error", ""))
		== "A14_6_R2_STALE_OWNER",
		"world owner change rejected")
	_check(String(R2.resume(field, demands, String(field.owner_token),
		int(field.owner_epoch) + 1, int(field.revision), cursor).get("error", ""))
		== "A14_6_R2_STALE_OWNER_EPOCH",
		"owner epoch change rejected")
	_check(String(R2.resume(field, demands, String(field.owner_token),
		int(field.owner_epoch), int(field.revision) + 1, cursor).get("error", ""))
		== "A14_6_R2_STALE_REVISION",
		"field revision change rejected")
	var corrupt_field: Dictionary = field.duplicate(true)
	corrupt_field.cells[0].stocks.water_mg += 1
	_check(not bool(R2.resume(corrupt_field, demands, String(field.owner_token),
		int(field.owner_epoch), int(field.revision), cursor).get("success", false)),
		"tampered canonical field fails closed")
	_check(not bool(R2.resume(field, demands, String(field.owner_token),
		int(field.owner_epoch), int(field.revision), cursor, 0).get("success", false)),
		"zero quota cannot execute speculative staged work")
	_check(not bool(R2.begin(field, demands, String(field.owner_token),
		int(field.owner_epoch), int(field.revision), 1024).get("success", false)),
		"tight cursor memory cap fails before any partial field publication")
	_check(not bool(R2.begin(field, [], String(field.owner_token),
		int(field.owner_epoch), int(field.revision)).get("success", false)),
		"empty demand batch rejected exactly as A4")
	# Actual fail-closed duplicate and invalid input after BEGIN.
	var duplicates: Array = [demands[0], demands[0].duplicate(true)]
	var db: Dictionary = R2.begin(field, duplicates,
		String(field.owner_token), int(field.owner_epoch), int(field.revision))
	if bool(db.get("success", false)):
		var rejection: Dictionary = R2.resume(field, duplicates, String(field.owner_token),
			int(field.owner_epoch), int(field.revision), db.cursor, 2)
		_check(String(rejection.get("error", "")) == "A14_6_R2_DUPLICATE_REQUEST",
			"duplicate source request IDs rejected before claim generation")
	var invalid: Array = [_d("bad id", "org", "water_mg", 1, 500)]
	var ib: Dictionary = R2.begin(field, invalid,
		String(field.owner_token), int(field.owner_epoch), int(field.revision))
	if bool(ib.get("success", false)):
		_check(String(R2.resume(field, invalid, String(field.owner_token),
			int(field.owner_epoch), int(field.revision), ib.cursor).get("error", ""))
			.begins_with("A14_6_R2_DEMAND:"),
			"malformed source demand rejected during normalization")
	_check(C.encode(cursor) == frozen_cursor and C.encode(field) == original,
		"all rejections leave trusted source/cursor bytes unchanged")
	# Cancellation is only dropping host-local speculative cursor. Restart
	# from unchanged A4 field/demands yields identical complete grants.
	var pending: Dictionary = R2.resume(field, demands, String(field.owner_token),
		int(field.owner_epoch), int(field.revision), cursor, 1)
	_check(bool(pending.get("success", false)) and not bool(pending.complete),
		"owned speculative cursor can be safely abandoned")
	pending = {}
	var resumed: Dictionary = _run_all(field, demands, 1, "cancel-restart-exact")
	_check(not resumed.is_empty() and C.encode(field) == original,
		"host-only cancel leaves exact restart capability")

func _tests_stress() -> void:
	var field: Dictionary = _new_field(8, 8, 100)
	var ds: Array = []
	for i in 256:
		var x := (i % 8) * 1000 + 500
		var z := (int(i / 8) % 8) * 1000 + 500
		var id := "r2org-%03d" % i
		ds.append(_d("water-%03d" % i, id, "water_mg", 9, x, z))
		ds.append(_d("nut-%03d" % i, id, "nutrient_mg", 15, x, z))
		ds.append(_d("org-%03d" % i, id, "organic_mg", 7, x, z))
	var stressed: Dictionary = _run_all(field, ds, 256,
		"256-population-768-demand-proof", 16777216)
	_check(not stressed.is_empty()
		and stressed.grants.size() == 768,
		"full current A12 256 scale and 768 explicit A4 requests proven")

func _finish() -> void:
	_check(records == 6, "all six reference-exact profile scenarios completed")
	print("ECO_ARCH2_A14_6_R2_ALLOC checks=%d failed=%d profiles=%d" %
		[checks, failures, records])
	print("ECO_ARCH2_A14_6_R2_ALLOC " + ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
