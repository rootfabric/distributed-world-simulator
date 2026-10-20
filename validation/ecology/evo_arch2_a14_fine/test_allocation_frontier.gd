extends SceneTree
## ECO ARCH2 A14.6 R1: independent adversarial graph and A4 exactness.
## The frontier is READ ONLY and MUST never allocate or own biology.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const Ports = preload("res://scripts/research/ecology/v2/organism_environment_ports_v1.gd")
const Probe = preload("res://scripts/research/ecology/v2/a5_allocation_frontier_probe_v1.gd")

var checks := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, name: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("ECO_A14_6_FRONTIER_FAIL " + name)

func _field(width: int = 2, depth: int = 1) -> Dictionary:
	return Field.create(
		"a14-6.probe", 0, [0, 0, 0], 1000, width, depth,
		F.stock(0), F.stock(1000), F.signals())

func _d(id: String, organism: String, res: String, amount: int,
		px: int, pz: int = 500, radius: int = 0) -> Dictionary:
	return Ports.demand(id, organism, res, amount, [px, 0, pz], radius)

func _run() -> void:
	_permutation_and_unions()
	_zero_primary_residual()
	_falsifiers()
	_finish()

func _permutation_and_unions() -> void:
	var f: Dictionary = _field(2, 2)
	_check(not f.is_empty(), "field initialized")
	var demands := [
		_d("w0", "org0", "water_mg", 10, 500),
		_d("w1", "org1", "water_mg", 20, 500),
		_d("w2", "org2", "water_mg", 5, 1500),
		_d("n0", "org3", "nutrient_mg", 7, 500),
	]
	var before := C.encode(f)
	var direct: Dictionary = Probe.analyze(f, demands)
	_check(bool(direct.get("success", false)), "unions accepted")
	if not bool(direct.get("success", false)):
		return
	_check(int(direct.plan.component_count) == 3,
		"two same-cell water IDs union; other water and nutrient independent")
	_check(int(direct.plan.max_component_demands) == 2
		and int(direct.plan.residual_bucket_count) == 3,
		"component and bucket cardinalities")
	var reverse: Array = demands.duplicate(true)
	reverse.reverse()
	var permuted: Dictionary = Probe.analyze(f, reverse)
	_check(bool(permuted.get("success", false))
		and String(permuted.plan_hash) == String(direct.plan_hash)
		and C.encode(permuted.plan) == C.encode(direct.plan),
		"input permutation cannot change graph bytes/hash")
	_check(C.encode(f) == before, "field remains unchanged after probe")
	_check(int(direct.plan.zero_primary_links) == 0
		and int(direct.plan.residual_claim_links) == 4,
		"all primary claims positive in small control")
	_check(String(direct.plan.schema) == Probe.SCHEMA, "versioned diagnostic schema")

func _zero_primary_residual() -> void:
	var f: Dictionary = _field()
	var seeded := Field.apply_effects(f, [
		Ports.effect("seed-water", "soil", "deposit", "water_mg", 5,
			[1500, 0, 500], 0, "A14_6_DIAGNOSTIC_SEED")
	], String(f.owner_token), int(f.owner_epoch), int(f.revision))
	_check(bool(seeded.get("success", false)), "seed one cell with canonical A4 owner write")
	if not bool(seeded.get("success", false)):
		return
	f = seeded.state
	var demands := [
		# Single 1 mg claim spans two cells: base=0, remainder=1.
		# The first cell is EMPTY; the second link has primary weight ZERO
		# yet the residual pass must still grant from the second cell.
		_d("cross", "orgA", "water_mg", 1, 1000, 500, 600),
		_d("local", "orgB", "water_mg", 1, 1500),
		_d("nutrient", "orgC", "nutrient_mg", 1, 1500),
	]
	var origin: String = C.encode(f)
	var result: Dictionary = Probe.analyze(f, demands)
	_check(bool(result.get("success", false)), "zero-primary input accepted")
	if not bool(result.get("success", false)):
		return
	_check(result.plan.component_count == 2
		and int(result.plan.max_component_demands) == 2,
		"water cross-cell and water local join via residual; nutrient isolated")
	_check(int(result.plan.primary_claim_links) == 3
		and int(result.plan.zero_primary_links) == 1
		and int(result.plan.residual_claim_links) == 4,
		"zero-primary link counted conservatively")
	var union_verified := false
	for comp in result.plan.components:
		if String(comp.resource) == "water_mg":
			union_verified = C.encode(comp.request_ids) == C.encode(["cross", "local"])
	_check(union_verified, "component IDs ordered and include zero-primary edge")
	# Reference TRUE original allocator, NEVER the diagnostic graph,
	# supplies the witness that the residual-pass edge matters physically.
	var alloc: Dictionary = Field.allocate_demands(f, demands,
		String(f.owner_token), int(f.owner_epoch), int(f.revision))
	_check(bool(alloc.get("success", false)), "canonical A4 allocates resource")
	if bool(alloc.get("success", false)):
		var grants := {}
		for grant in alloc.grants:
			grants[String(grant.request_id)] = int(grant.granted)
		_check(int(grants.get("cross", -1)) == 1
			and int(grants.get("local", -1)) == 1,
			"cross-cell demand receives residual grant from cell with zero primary claim")
		_check(int(alloc.state.cells[1].stocks.water_mg) == 3,
			"canonical cell/ledger conserve initial 5 mg")
		var reversed: Array = demands.duplicate(true)
		reversed.reverse()
		var independent: Dictionary = Field.allocate_demands(f, reversed,
			String(f.owner_token), int(f.owner_epoch), int(f.revision))
		_check(bool(independent.get("success", false))
			and C.encode(alloc.state) == C.encode(independent.state)
			and C.encode(alloc.grants) == C.encode(independent.grants),
			"A4 result exact under demand permutation")
	_check(C.encode(f) == origin, "diagnostic and original allocation never mutate caller state")

func _falsifiers() -> void:
	var f: Dictionary = _field()
	var d: Dictionary = _d("valid", "org", "water_mg", 1, 500)
	var state_before := C.encode(f)
	var bad: Dictionary = f.duplicate(true)
	bad.cells[0].stocks.water_mg += 1
	var tampered := Probe.analyze(bad, [d])
	_check(not bool(tampered.get("success", false))
		and String(tampered.get("error", "")).begins_with("A14_6_FIELD"),
		"tampered field integrity fails closed")
	var duplicates := Probe.analyze(f, [d, d.duplicate(true)])
	_check(not bool(duplicates.get("success", false))
		and String(duplicates.get("error", "")) == "A14_6_DUPLICATE_REQUEST",
		"duplicate request rejected")
	var invalid := Probe.analyze(f, [_d("bad id", "org", "water_mg", 1, 500)])
	_check(not bool(invalid.get("success", false))
		and String(invalid.get("error", "")).begins_with("A14_6_DEMAND"),
		"malformed demand ID rejected")
	var outside := Probe.analyze(f, [_d("outside", "org", "water_mg", 1, 9999000)])
	_check(not bool(outside.get("success", false))
		and String(outside.get("error", "")) == "A14_6_OUT_OF_BOUNDS",
		"valid far-away demand is outside bounded field")
	var over_count: Array = []
	for i in F.MAX_BATCH + 1:
		over_count.append(d)
	var overflow := Probe.analyze(f, over_count)
	_check(not bool(overflow.get("success", false))
		and String(overflow.get("error", "")) == "A14_6_DEMAND_BATCH",
		"batch over current A4 limit is refused")
	var empty: Dictionary = Probe.analyze(f, [])
	_check(bool(empty.get("success", false))
		and int(empty.plan.component_count) == 0
		and int(empty.plan.demand_count) == 0,
		"zero-demand topology is valid diagnostic, never allocation")
	_check(C.encode(f) == state_before, "all rejected probes leave source unchanged")

func _finish() -> void:
	print("ECO_ARCH2_A14_6_FRONTIER checks=%d failed=%d" % [checks, failed])
	print("ECO_ARCH2_A14_6_FRONTIER " + ("PASS" if failed == 0 else "FAIL"))
	quit(0 if failed == 0 else 1)
