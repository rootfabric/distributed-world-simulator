extends SceneTree
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const L = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const Ports = preload("res://scripts/research/ecology/v2/organism_environment_ports_v1.gd")
const Adapter = preload("res://scripts/research/ecology/v2/field_environment_adapter_v1.gd")
const E = preload("res://scripts/research/ecology/v2/environment_fixture_v1.gd")
const Fixtures = preload("res://scripts/research/ecology/v2/body_program_fixtures_v1.gd")
const S = preload("res://scripts/research/ecology/v2/organism_state_v1.gd")
const K = preload("res://scripts/research/ecology/v2/development_interpreter_v1.gd")
const H = preload("res://scripts/research/ecology/v2/phenotype_snapshot_v1.gd")
var passed := 0
var failed := 0

func _init() -> void:
	_contract_and_locality()
	_conservative_exchange()
	_ownership_and_scale()
	_development_bridge()
	print("EVO_ARCH2_A4_EXACT assertions=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(value: bool, name: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error("FAIL:" + name)

func _field(stock: int = 500, capacity: int = 1000, width: int = 4, depth: int = 4) -> Dictionary:
	return L.create("research.patch", 7, [0, 0, 0], 1000, width, depth, F.stock(stock), F.stock(capacity), F.signals())

func _req(id: String, pos: Array, extent: int = 0) -> Dictionary:
	return Ports.sample_request(id, pos, extent)

func _run(genome: Dictionary, env: Dictionary) -> Dictionary:
	var state := S.create(genome)
	for _tick in 3:
		var opened := K.begin_tick(state, genome, env, B.stock(1000000), state.grant_seq + 1)
		if not opened.success:
			return {}
		state = opened.state
		for _slice in 4096:
			var result := K.advance(state, genome, 4096)
			if not result.success or result.status == "BUDGET_BLOCKED":
				return {}
			state = result.state
			if result.status == "TICK_COMPLETE":
				break
	return state

func _contract_and_locality() -> void:
	var field := _field()
	_check(F.validate_state(field).is_empty(), "field_valid")
	_check(field.cells.size() == 16 and field.cells[5].id == "c0005" and field.cells[5].x == 1 and field.cells[5].z == 1, "stable_row_major_address")
	var text := F.serialize(field)
	var restored := F.deserialize(text)
	_check(not restored.is_empty() and C.digest(restored) == C.digest(field), "canonical_roundtrip")
	var tampered := field.duplicate(true)
	tampered.cells[0].stocks.water_mg += 1
	_check(F.validate_state(tampered) == "FIELD_CELL_0", "ledger_tamper_rejected")
	var one := L.sample(field, _req("org", [500, 0, 500]))
	_check(one.success and one.visited_cells == 1 and one.sample.channels.water == 500, "point_sample_local")
	_check(one.sample.source.field_hash == L.state_hash(field) and F.validate_sample(one.sample).is_empty(), "sample_provenance")
	var near := L.sample(field, _req("org", [1500, 0, 1500], 900))
	_check(near.success and near.visited_cells == 9, "bounded_extent_sample")
	var large := L.create("research.large", 1, [0, 0, 0], 1000, 64, 64, F.stock(1), F.stock(10), F.signals())
	var precise := L.sample(large, _req("org", [32500, 0, 32500]))
	_check(large.cells.size() == 4096 and precise.success and precise.visited_cells == 1, "large_field_query_locality")
	var unreachable := L.create("research.unreachable", 1, [0, 0, 0], 1000000, 64, 64, F.stock(1), F.stock(10), F.signals())
	_check(unreachable.is_empty(), "unreachable_footprint_rejected")
	var boundary := L.create("research.boundary", 1, [-10000000, 0, 0], 1000000, 20, 1, F.stock(1), F.stock(10), F.signals())
	_check(not boundary.is_empty() and F.validate_state(boundary).is_empty(), "exact_port_boundary_footprint_accepted")


func _conservative_exchange() -> void:
	var field := _field(100, 1000, 1, 1)
	var a := Ports.demand("a", "org.a", "water_mg", 70, [500, 0, 500], 0)
	var b := Ports.demand("b", "org.b", "water_mg", 70, [500, 0, 500], 0)
	_check(Ports.validate_demand(a).is_empty(), "typed_demand")
	var forward := L.allocate_demands(field, [b, a], field.owner_token, field.owner_epoch, field.revision)
	var reverse := L.allocate_demands(field, [a, b], field.owner_token, field.owner_epoch, field.revision)
	_check(forward.success and forward.grants[0].granted == 50 and forward.grants[1].granted == 50, "pro_rata_no_overdraft")
	_check(forward.state.cells[0].stocks.water_mg == 0 and forward.state.ledger.outputs.water_mg == 100, "allocation_ledger")
	_check(F.validate_state(forward.state).is_empty(), "allocation_conservation")
	_check(reverse.success and reverse.state_hash == forward.state_hash and reverse.grants == forward.grants, "input_order_independent")
	var uneven := L.create("research.uneven", 1, [0, 0, 0], 1000, 2, 1, F.stock(0), F.stock(1000), F.signals())
	var fill_second := Ports.effect("fill.second", "abiotic", "deposit", "water_mg", 150, [1500, 0, 500], 0, "TEST_INPUT")
	var filled := L.apply_effects(uneven, [fill_second], uneven.owner_token, uneven.owner_epoch, uneven.revision)
	var ra := Ports.demand("a", "org.a", "water_mg", 100, [1000, 0, 500], 1000)
	var rb := Ports.demand("b", "org.b", "water_mg", 100, [1000, 0, 500], 1000)
	var fair_forward := L.allocate_demands(filled.state, [ra, rb], filled.state.owner_token, filled.state.owner_epoch, filled.state.revision)
	var fair_reverse := L.allocate_demands(filled.state, [rb, ra], filled.state.owner_token, filled.state.owner_epoch, filled.state.revision)
	_check(fair_forward.success and fair_forward.grants[0].granted == 75 and fair_forward.grants[1].granted == 75, "residual_stock_stays_pro_rata")
	_check(fair_reverse.success and fair_reverse.grants == fair_forward.grants and fair_reverse.state_hash == fair_forward.state_hash, "residual_pro_rata_order_independent")
	var dep := Ports.effect("deposit", "org", "deposit", "organic_mg", 120, [500, 0, 500], 0)
	_check(Ports.validate_effect(dep).is_empty(), "typed_effect")
	var deposited := L.apply_effects(field, [dep], field.owner_token, field.owner_epoch, field.revision)
	_check(deposited.success and deposited.state.ledger.inputs.organic_mg == 120, "deposit_input_ledger")
	var sink := Ports.effect("sink", "abiotic", "sink", "water_mg", 40, [500, 0, 500], 0, "EXPLICIT_ABIOTIC_SINK")
	var sunk := L.apply_effects(deposited.state, [sink], deposited.state.owner_token, deposited.state.owner_epoch, deposited.state.revision)
	_check(sunk.success and sunk.state.ledger.sinks.water_mg == 40 and F.validate_state(sunk.state).is_empty(), "sink_conservation")

func _ownership_and_scale() -> void:
	var field := _field()
	var d := Ports.demand("d", "org", "water_mg", 10, [500, 0, 500], 0)
	_check(L.allocate_demands(field, [d], "other", field.owner_epoch, field.revision).error == "STALE_OWNER", "stale_owner_rejected")
	_check(L.allocate_demands(field, [d], field.owner_token, field.owner_epoch + 1, field.revision).error == "STALE_OWNER_EPOCH", "stale_epoch_rejected")
	_check(L.allocate_demands(field, [d], field.owner_token, field.owner_epoch, field.revision + 1).error == "STALE_REVISION", "stale_revision_rejected")
	var signal_change := L.set_cell_signals(field, 0, 0, F.signals(111, 444, 22, 33), field.owner_token, field.owner_epoch, field.revision)
	var here := L.sample(signal_change.state, _req("here", [500, 0, 500]))
	var there := L.sample(signal_change.state, _req("there", [1500, 0, 500]))
	_check(here.sample.channels.light == 111 and there.sample.channels.light == 700, "signal_locality")
	var stress := L.create("research.stress", 3, [0, 0, 0], 1000, 32, 32, F.stock(1000), F.stock(2000), F.signals())
	var demands: Array = []
	for i in 1000:
		var x := i % 32
		var z := int(i / 32) % 32
		demands.append(Ports.demand("stress.%04d" % i, "org.%04d" % i, "water_mg", 10, [x * 1000 + 500, 0, z * 1000 + 500], 0))
	var s1 := L.allocate_demands(stress, demands, stress.owner_token, stress.owner_epoch, stress.revision)
	var reversed := demands.duplicate(true)
	reversed.reverse()
	var s2 := L.allocate_demands(stress, reversed, stress.owner_token, stress.owner_epoch, stress.revision)
	_check(s1.success and s1.grants.size() == 1000 and s1.state.ledger.outputs.water_mg == 10000, "stress_1000_demands")
	_check(F.validate_state(s1.state).is_empty() and s2.success and s1.state_hash == s2.state_hash, "stress_conservation_and_order")
	_check(L.sample(s1.state, _req("probe", [500, 0, 500])).visited_cells == 1, "stress_query_stays_local")

func _development_bridge() -> void:
	var dry := _field(100, 1000, 1, 1)
	var wet := _field(900, 1000, 1, 1)
	var dry_env := Adapter.sample_for_development(dry, "org", [500, 0, 500], 0)
	var wet_env := Adapter.sample_for_development(wet, "org", [500, 0, 500], 0)
	_check(E.validate(dry_env).is_empty() and E.validate(wet_env).is_empty(), "a2_sample_bridge")
	_check(dry_env.channels.water == 100 and wet_env.channels.water == 900, "field_water_channel")
	var genome := Fixtures.make(0)
	var dry_state := _run(genome, dry_env)
	var wet_state := _run(genome, wet_env)
	_check(not dry_state.is_empty() and not wet_state.is_empty(), "field_driven_development")
	var dry_p := H.compile(dry_state, genome)
	var wet_p := H.compile(wet_state, genome)
	_check(int(dry_p.module_roles.get("absorber", 0)) > int(wet_p.module_roles.get("absorber", 0)), "same_genome_different_field_phenotype")
	_check(Ports.sampling_extent_mm(dry_p) > 0, "phenotype_extent_for_sampling")
