extends SceneTree
const X = preload("res://tests/research/ecology/v2/arch2_a6_fixtures.gd")
const A6 = X.A6
const B = X.B
const LS = X.LS
const R = X.R
const C = X.C
var passed := 0
var failed := 0

func _init() -> void:
	_deep_lineage_and_light_energy()
	print("EVO_ARCH2_A6_LINEAGE assertions=%d failed=%d" % [passed + failed, failed])
	quit(0 if failed == 0 else 1)

func _check(v: bool, name: String) -> void:
	if v: passed += 1
	else: failed += 1; push_error("FAIL:" + name)

func _blueprint() -> Dictionary:
	var actions: Array = [X.P.action("differentiate", "collector", [0, 10, 0], 1, 50000), X.P.action("differentiate", "reproductive", [0, 10, 0], 1), X.P.action("retire")]
	var genome := X.G.create({"schema": X.P.SCHEMA, "entry": "start", "max_age": 8, "max_depth": 1, "rules": [X.P.rule("start", actions, "start")]}, "A6 funded deep lineage")
	var p := X.policy()
	p.uptake.basal_water_mg = 5000; p.uptake.basal_nutrient_mg = 5000; p.uptake.basal_organic_mg = 5000
	p.growth.transfer_permille = 100; p.growth.max_transfer = B.stock(5000)
	p.reproduction.maturity_ticks = 2; p.reproduction.interval_ticks = 10
	p.reproduction.endowment = B.stock(10000); p.reproduction.fee_energy_mj = 0
	return X.BP.create(genome, p)

func _child(entry: Dictionary, blueprint: Dictionary) -> Dictionary:
	var f := X.field(X.F.stock(900000))
	var current := entry
	for _i in 3:
		var next := R.step_population(f, [current], f.owner_token, f.owner_epoch, f.revision)
		if not next.success: return {}
		current = next.population[0]; f = next.field
		if next.propagules.size() == 1:
			return R.materialize_propagule(next.propagules[0], blueprint, current.state)
	return {}

func _deep_lineage_and_light_energy() -> void:
	var bp := _blueprint()
	var current := R.individual(bp, "a6.lineage", [500, 0, 500], B.stock(10000))
	var all_ok := not current.is_empty()
	for _i in LS.MAX_PARENT_PROOF_DEPTH:
		current = _child(current, bp)
		if current.is_empty(): all_ok = false; break
	_check(all_ok, "paid_lineage_through_a5_depth_cap")
	if not all_ok: return
	_check(not LS.serialize(current.state, bp).is_empty(), "deep_a5_state_valid_before_composition")
	var made := A6.create("deep.feedback", X.field(X.F.stock(900000)), [current], A6.default_policy())
	_check(made.success, "a6_envelope_does_not_shorten_a5_lineage_cap")
	if not made.success: return
	var s: Dictionary = made.state
	_check(s.frame.population[0] is String, "a5_provenance_kept_as_canonical_payload")
	for _i in 3:
		var next := X.step(s)
		if not next.success:
			print("A6_LINEAGE_FAILURE ", next.error)
			all_ok = false; break
		s = next.state
	_check(all_ok, "deep_lineage_lifecycle_and_photosynthesis_advance")
	if not all_ok: return
	var e := X.entry(s, current.state.individual_id)
	_check(e.state.resource_ledger.external_energy_mj > current.state.resource_ledger.external_energy_mj, "real_collector_produces_explicit_external_energy")
	var accounts := A6.balance(s)
	_check(not accounts.has("error") and accounts.external.energy_mj > 0, "global_balance_tracks_new_light_energy")
	_check(accounts.initial.energy_mj + accounts.external.energy_mj == accounts.current.energy_mj + accounts.sinks.energy_mj, "global_energy_sources_equal_remaining_plus_sinks")
	_check(s.frame.propagules.size() == 1, "depth_eight_parent_paid_output_preserved_without_materialization")
	var receipt: Dictionary = s.frame.propagules[0]
	var paid := LS.deserialize(receipt.parent_payload)
	_check(R.materialize_propagule(receipt.propagule, paid.blueprint, paid.state).is_empty(), "outbox_does_not_bypass_a5_ninth_generation_materialization_limit")
	var text := A6.serialize(s)
	var restored := A6.deserialize(text, s.genesis_hash, s.frame.step)
	_check(not restored.is_empty() and restored.integrity_hash == s.integrity_hash, "deep_parent_and_paid_seed_restart_exact")
	print("A6_ENERGY_WITNESS ", C.encode(accounts))
