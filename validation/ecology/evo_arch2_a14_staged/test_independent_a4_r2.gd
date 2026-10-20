extends SceneTree
## ECO A14.6 R2 — fresh verifier, separate test carrier on frozen product.
## Reconstruct a three-cell adversarial resource contest; the third cell
## can fund cross-cell request only through the SECOND residual pro-rata.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const Ports = preload("res://scripts/research/ecology/v2/organism_environment_ports_v1.gd")
const Candidate = preload("res://scripts/research/ecology/v2/a4_staged_global_allocator_probe_v1.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ECO_A14_6_R2_INDEPENDENT_FAIL " + label)

func _run() -> void:
	var source: Dictionary = Field.create("r2.independent", 0, [0, 0, 0],
		1000, 3, 1, F.stock(0), F.stock(1000), F.signals())
	check(not source.is_empty(), "independent 3-cell field")
	if source.is_empty():
		_finish()
		return
	var fill: Dictionary = Field.apply_effects(source, [
		Ports.effect("indep-fill", "soil", "deposit", "water_mg", 10,
			[2500, 0, 500], 0, "INDEPENDENT_EXACT"),
	], String(source.owner_token), int(source.owner_epoch), int(source.revision))
	check(bool(fill.get("success", false)), "canonical A4 owner-write filling")
	if not bool(fill.get("success", false)):
		_finish()
		return
	source = fill.state
	var demands: Array = [
		Ports.demand("a-cross", "org-a", "water_mg", 2, [1500, 0, 500], 1100),
		Ports.demand("b-local", "org-b", "water_mg", 1, [2500, 0, 500], 0),
		Ports.demand("c-nut", "org-c", "nutrient_mg", 1, [2500, 0, 500], 0),
	]
	var before: String = C.encode(source)
	var demand_before: String = C.encode(demands)
	var original: Dictionary = Field.allocate_demands(source, demands,
		String(source.owner_token), int(source.owner_epoch), int(source.revision))
	check(bool(original.get("success", false)), "accepted global A4 reference")
	if not bool(original.get("success", false)):
		_finish()
		return
	var begun: Dictionary = Candidate.begin(source, demands,
		String(source.owner_token), int(source.owner_epoch), int(source.revision))
	check(bool(begun.get("success", false)), "frozen product staged begin")
	if not bool(begun.get("success", false)):
		_finish()
		return
	var cursor: Dictionary = begun.cursor
	var dirty: Dictionary = cursor.duplicate(true)
	dirty.working_field.cells[2].stocks.water_mg = 9
	var reject: Dictionary = Candidate.resume(source, demands,
		String(source.owner_token), int(source.owner_epoch),
		int(source.revision), dirty, 1)
	check(String(reject.get("error", "")) == "A14_6_R2_CURSOR_CHECKSUM",
		"nested scratch corruption rejected before a partial grant")
	var moved: Array = demands.duplicate(true)
	moved[0].amount = 3
	reject = Candidate.resume(source, moved, String(source.owner_token),
		int(source.owner_epoch), int(source.revision), cursor, 1)
	check(String(reject.get("error", "")) == "A14_6_R2_SOURCE_CHANGED",
		"changed global demand frontier rejected")
	reject = Candidate.resume(source, demands, String(source.owner_token),
		int(source.owner_epoch) + 1, int(source.revision), cursor, 1)
	check(String(reject.get("error", "")) == "A14_6_R2_STALE_OWNER_EPOCH",
		"wrong owner epoch rejected")
	check(not bool(Candidate.begin(source, demands, String(source.owner_token),
		int(source.owner_epoch), int(source.revision), 1024)
		.get("success", false)), "tiny speculative memory cap rejects")
	check(C.encode(source) == before and C.encode(demands) == demand_before,
		"all negative controls preserve original field/demands")

	# Abandon one valid NORMALIZE cursor. A NEW begin from the trusted
	# source, not its unfinished scratch, must reproduce accepted A4.
	var partial: Dictionary = Candidate.resume(source, demands,
		String(source.owner_token), int(source.owner_epoch),
		int(source.revision), cursor, 1)
	check(bool(partial.get("success", false)) and
		not bool(partial.get("complete", true)),
		"bounded NORMALIZE call publishes no state")
	check(not partial.has("state") and not partial.has("grants"),
		"partial resources cannot appear as authoritative grants")
	partial = {}
	begun = Candidate.begin(source, demands, String(source.owner_token),
		int(source.owner_epoch), int(source.revision))
	check(bool(begun.get("success", false)), "safe begin after cancellation")
	cursor = begun.cursor
	var seen := {"NORMALIZE": false, "BUILD_CLAIMS": false,
		"PRIMARY": false, "RESIDUAL": false, "FINALIZE": false}
	var final: Dictionary = {}
	for attempt in 50:
		var phase: String = String(cursor.phase)
		check(seen.has(phase), "known finite phase")
		if not seen.has(phase):
			break
		seen[phase] = true
		var old_bytes: String = C.encode(cursor)
		var progressed: Dictionary = Candidate.resume(source, demands,
			String(source.owner_token), int(source.owner_epoch),
			int(source.revision), cursor, 1)
		check(bool(progressed.get("success", false)),
			"detached phase completes: %s %s" %
				[phase, String(progressed.get("error", ""))])
		if not bool(progressed.get("success", false)):
			break
		check(C.encode(cursor) == old_bytes and
			C.encode(source) == before, "source and caller cursor immutable")
		if bool(progressed.get("complete", false)):
			final = progressed
			break
		check(not progressed.has("state") and not progressed.has("grants"),
			"pending stages never publish authoritative bytes")
		cursor = progressed.cursor
	check(not final.is_empty() and bool(final.get("reference_equal", false)),
		"proof barrier accepted independent global A4 result")
	if not final.is_empty():
		check(seen.values().all(func(value: bool) -> bool: return value),
			"all five global barriers exercised")
		check(C.encode(final.state) == C.encode(original.state)
			and C.encode(final.grants) == C.encode(original.grants),
			"full field and sorted A4 grants exactly equal canonical reference")
		check(String(final.state_hash) == String(original.state_hash)
			and F.validate_state(final.state).is_empty(),
			"state hash and resource conservation identical")
		var per_request := {}
		for grant in final.grants:
			per_request[String(grant.request_id)] = int(grant.granted)
		check(int(per_request.get("a-cross", -1)) == 2
			and int(per_request.get("b-local", -1)) == 1
			and int(final.state.cells[2].stocks.water_mg) == 7,
			"zero-primary residual grant retained on last cell")
		check(C.encode(source) == before and C.encode(demands) == demand_before,
			"full proof never mutated canonical source")
	_finish()

func _finish() -> void:
	print("ECO_ARCH2_A14_6_R2_INDEPENDENT checks=%d failed=%d" %
		[checks, failures])
	print("ECO_ARCH2_A14_6_R2_INDEPENDENT " + ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
