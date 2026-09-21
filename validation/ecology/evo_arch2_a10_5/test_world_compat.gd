extends SceneTree

# ECO ARCH2 A10.5 / ECO-POLYGON-1 — P12 WORLD_COMPAT E2E validation (§23-§25).
# Runner: Godot headless --script; prints checks/failed counts and PASS/FAIL.
#
# Scenarios:
#   E  LAB vs WORLD_COMPAT semantic equivalence (§23): identical genome/lifecycle,
#      identical environment inputs (matter mapping admits the same stocks),
#      8 ticks; organisms alive in both; equal biological_hash + development
#      outcomes; matter accounting conserves exactly the LAB-declared totals.
#   A  ACTIVE-only execution (§23/§24): non-ACTIVE region -> fail-closed tick,
#      state unchanged; WORLD_COMPAT initialize without authority deps fails.
#   M  Explicit-only matter mapping (§23): unmapped resources are not guessed;
#      unknown material entry -> configure fail; tampered batch checksum anchor
#      -> rejected.
#   H  Region handoff E2E (§24): ACTIVE A -> WARM prep ticket -> COMMITTED ->
#      new ACTIVE; old owner rejected after commit; ecology continues with the
#      same organisms (ids, biological_hash, lineage_depth); checkpoint
#      identity through the seam (controller serialize_state, P8); production
#      ecology_region_ownership_v1 handoff line composed alongside.
#   D  Damage overlay (§25): external trusted DamageRecord -> binding + overlay;
#      historical topology_signature unchanged; effective_function differs;
#      inspector shows the three layers separately; tampered record checksum
#      -> rejected.

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const P = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const Genome = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const OrganismState = preload("res://scripts/research/ecology/v2/organism_state_v1.gd")
const Body = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Adapter = preload("res://scripts/ecology/workbench/polygon_world_adapter_v1.gd")
const Inspector = preload("res://scripts/ecology/workbench/organism_inspector_v1.gd")
const WorldBinding = preload("res://scripts/research/ecology/v2/world_binding_v1.gd")
const SeamBinding = preload("res://scripts/research/ecology/v2/world_seam_binding_v1.gd")
const Machine = preload("res://scripts/network/handoff/handoff_state_machine.gd")
const Ticket = preload("res://scripts/network/contracts/handoff_ticket.gd")
const Region = preload("res://scripts/network/contracts/authority_region_descriptor.gd")
const Catalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const Composition = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const Batch = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")
const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const Cell = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")
const Brick = preload("res://scripts/simulation/matter/contracts/matter_brick_address.gd")
const Sample = preload("res://scripts/simulation/matter/contracts/matter_sample.gd")
const Query = preload("res://scripts/simulation/matter/query/matter_query_result.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const DamageRequest = preload("res://scripts/construction/damage/construction_damage_request.gd")
const DamageRecord = preload("res://scripts/construction/damage/construction_damage_record.gd")
const RepairPlan = preload("res://scripts/construction/damage/construction_repair_plan.gd")
# Production P4.x ownership line fixtures.
const Competition = preload("res://scripts/research/ecology/plant_resource_competition_v1.gd")
const Density = preload("res://scripts/research/ecology/plant_density_carrying_capacity_v1.gd")
const Dispersal = preload("res://scripts/research/ecology/plant_spatial_dispersal_v1.gd")
const EnvGradient = preload("res://scripts/research/ecology/plant_environmental_gradient_v1.gd")
const Seasonal = preload("res://scripts/research/ecology/plant_seasonal_world_v1.gd")
const Disturbance = preload("res://scripts/research/ecology/plant_disturbance_succession_v1.gd")
const Coexistence = preload("res://scripts/research/ecology/plant_multi_niche_coexistence_v1.gd")
const RegionState = preload("res://scripts/ecology/production/ecology_region_state_v1.gd")
const EcologyClock = preload("res://scripts/ecology/production/ecology_clock_v1.gd")
const OfflineCatchup = preload("res://scripts/ecology/production/ecology_offline_catchup_v1.gd")
const ProductionPersistence = preload("res://scripts/ecology/production/ecology_region_persistence_v1.gd")
const Ownership = preload("res://scripts/ecology/production/ecology_region_ownership_v1.gd")

const WATER_STOCK_MG := 500000

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("A10_5_P12_FAIL " + message)

# --- fixtures -------------------------------------------------------------------

func _manifest(mode: String, horizon: int) -> Dictionary:
	var founder := Genome.create({
		"schema": P.SCHEMA, "entry": "r1", "max_age": 64, "max_depth": 2,
		"rules": [P.rule("r1", [
			P.action("extend", "support", [0, 100, 0], 10),
			P.action("differentiate", "collector", [0, 60, 0], 4, 20000),
		])],
	}, "founder-a")
	var stocks := {"water_mg": WATER_STOCK_MG if mode == "LAB" else 0, "light": 700, "temperature": 500, "nutrient_mg": 0, "organic_mg": 0}
	return {
		"schema": "dws.ecology.workbench.experiment-manifest.v1",
		"experiment_id": "eco-polygon/exp-p12-" + mode.to_lower(),
		"seed": 777,
		"horizon_ticks": horizon,
		"founders": [{"founder_id": "founder/a", "biological_hash": null, "genome": founder}],
		"environment": {
			"spatial": {"origin_mm": [0, 0, 0], "cell_size_mm": 1000, "width": 1, "depth": 1},
			"zones": [{"id": "zone/wet"}.merged(stocks)],
		},
		"placement": {"entries": [{"founder_ref": "founder/a", "zone_id": "zone/wet", "position_mm": [500, 0, 500]}]},
		"mutation": {"operator": "small", "mutations_enabled": true},
		"organization_profile": "FREE",
		"feedback": {"enabled": true, "decomposition_enabled": true},
		"metrics": {"requested": ["population"]},
		"checkpoint": {"interval_ticks": 16},
		"mode": mode,
	}

func _region(owner: String, epoch: int, lifecycle: String) -> Dictionary:
	# universe/instance/space ids deliberately match the canonical
	# SimulationCellAddress segment alphabet (no slashes) so a Matter query
	# cell can reference the same space (world_binding space equality check).
	return Region.create(
		"region/a", "u", "i", "surface",
		"octree", 7, {"kind": "GLOBAL_SPACE", "partition_prefix": "", "chunk_ids": []},
		owner, epoch, lifecycle, 10
	)

func _adapter(manifest: Dictionary, region: Dictionary, mapping_entries: Array) -> Object:
	var catalog := Catalog.default_catalog()
	var adapter := Adapter.new()
	var configured: Dictionary = adapter.configure(manifest, {
		"region": region,
		"entity_id": "organism/wc-p12",
		"owner_id": String(region.owner_node_id),
		"catalog": catalog,
		"map_id": "eco-map/p12-fixture",
		"mapping_entries": mapping_entries,
	})
	_check(bool(configured.get("success", false)), "adapter configure succeeds: " + str(configured))
	return adapter

func _water_batch() -> Dictionary:
	return _water_batch_amount("batch/p12-water", WATER_STOCK_MG)

func _water_batch_amount(batch_id: String, mass_mg: int) -> Dictionary:
	return Batch.create({
		"batch_id": batch_id,
		"container_id": "container/p12",
		"source_body_id": "body/moon",
		"source_operation_id": "operation/p12",
		"total_mass_kg": float(mass_mg) / 1000000.0,
		"bulk_volume_m3": 0.000001,
		"composition": Composition.create([{"material_id": "matter/water-ice", "mass_fraction": 1.0}]),
		"temperature_k": 273.15,
	})

func _field_total(controller: Object, resource: String) -> int:
	var total := 0
	for cell in controller.debug_state().field.cells:
		total += int(cell.stocks[resource])
	return total

func _wc_controller(manifest: Dictionary, adapter: Object) -> Object:
	var controller := Controller.new()
	var attached: Dictionary = controller.attach_world_authority(adapter)
	_check(bool(attached.get("success", false)), "controller attaches world authority")
	var init_result: Dictionary = controller.initialize(manifest)
	_check(bool(init_result.get("success", false)), "WORLD_COMPAT controller initialize succeeds: " + str(init_result))
	return controller

func _matter_query() -> Dictionary:
	var cell := Cell.create("u", "i", "surface", "grid", 1, "root")
	var brick := Brick.create(cell, 0, 0, 0, 0)
	var sample := Sample.create(-0.25, 1.0, 1350.0, Composition.create([
		{"material_id": "matter/regolith-loose", "mass_fraction": 0.8},
		{"material_id": "matter/water-ice", "mass_fraction": 0.2},
	]), 0.9, 289.5, 0.35, ["matter-state/solid"])
	return Query.create({
		"query_id": "matter-query/p12", "body_id": "body/moon", "body_frame_id": "frame/moon",
		"body_definition_hash": "a".repeat(64), "grid_profile_hash": "b".repeat(64),
		"generator_version": "1.0.0", "generator_seed": 7,
		"local_position_m": Vector3(12.5, -0.25, 8.0), "requested_level": 0,
		"source": "MATERIALIZED_BRICK", "cell_address": cell, "brick_address": brick,
		"sample_lattice_index": [0, 0, 0], "state_revision": 11, "sample": sample,
	})

func _semantic_fingerprint(controller: Object) -> Dictionary:
	# Semantic (non-hash) equivalence fingerprint: per-organism biological hash
	# + development module count. Hashes (owner_token/field revisions) may
	# legitimately differ between LAB and WORLD_COMPAT authority sources.
	var debug: Dictionary = controller.debug_state()
	var by_id := {}
	for entry in debug.population:
		by_id[String(entry.state.individual_id)] = {
			"biological_hash": OrganismState.biological_hash(entry.state.development),
			"module_count": int(entry.state.development.modules.size()),
			"alive": bool(entry.state.alive),
		}
	return by_id

func _alive_count(controller: Object) -> int:
	var count := 0
	for entry in controller.debug_state().population:
		if bool(entry.state.alive):
			count += 1
	return count

func _presentation(controller: Object) -> Dictionary:
	var by_id := {}
	for entry in controller.get_snapshot().presentation:
		by_id[String(entry.individual_id)] = entry.duplicate(true)
	return by_id

# --- Scenario E: LAB vs WORLD_COMPAT semantic equivalence (§23) ------------------

func _scenario_equivalence() -> void:
	var water_entries := [{"material_id": "matter/water-ice", "resource": "water_mg"}]
	var lab := Controller.new()
	var lab_init: Dictionary = lab.initialize(_manifest("LAB", 16))
	_check(bool(lab_init.get("success", false)), "E LAB initialize succeeds: " + str(lab_init))
	var lab_run: Dictionary = lab.run(8)
	_check(bool(lab_run.get("success", false)), "E LAB run(8) succeeds: " + str(lab_run))

	var adapter := _adapter(_manifest("WORLD_COMPAT", 16), _region("node/a", 1, "ACTIVE"), water_entries)
	var wc := _wc_controller(_manifest("WORLD_COMPAT", 16), adapter)
	var bound: Dictionary = adapter.bind_site(_matter_query())
	_check(bool(bound.get("success", false)) and String(bound.get("binding_hash", "")).length() == 64, "E matter site binding sealed (provenance only)")
	var added: Dictionary = adapter.add_batch(_water_batch(), String(_water_batch().checksum))
	_check(bool(added.get("success", false)), "E explicit water batch admitted: " + str(added))
	if bool(added.get("success", false)):
		var admission: Dictionary = added.admission
		_check(int(admission.total_mass_mg) == WATER_STOCK_MG, "E matter accounting total equals LAB zone water exactly")
		_check(int(admission.resources.water_mg) == WATER_STOCK_MG, "E mapped water equals LAB zone water")
		_check(int(admission.resources.nutrient_mg) == 0 and int(admission.resources.organic_mg) == 0, "E nutrient/organic are not guessed from a water batch")
	var applied: Dictionary = adapter.apply_environment(wc)
	_check(bool(applied.get("success", false)), "E world environment applied through canonical owner-write bridge: " + str(applied))
	var wc_run: Dictionary = wc.run(8)
	_check(bool(wc_run.get("success", false)), "E WORLD_COMPAT run(8) succeeds: " + str(wc_run))

	if not bool(lab_run.get("success", false)) or not bool(wc_run.get("success", false)):
		return
	_check(_alive_count(lab) >= 1, "E LAB organisms alive after 8 ticks")
	_check(_alive_count(wc) >= 1, "E WORLD_COMPAT organisms alive after 8 ticks")
	var lab_print := _semantic_fingerprint(lab)
	var wc_print := _semantic_fingerprint(wc)
	_check(lab_print.keys() == wc_print.keys(), "E identical individual_ids across modes")
	for individual_id in lab_print.keys():
		_check(String(lab_print[individual_id].biological_hash) == String(wc_print[individual_id].biological_hash), "E biological_hash equal: " + individual_id)
		_check(int(lab_print[individual_id].module_count) == int(wc_print[individual_id].module_count), "E development module counts equal: " + individual_id)
		_check(bool(wc_print[individual_id].alive) == bool(lab_print[individual_id].alive), "E alive outcome equal: " + individual_id)
	var observe: Dictionary = adapter.observe_world()
	_check(bool(observe.get("configured", false)) and String(observe.lifecycle_state) == "ACTIVE", "E observe_world reports ACTIVE region")
	_check(int(observe.admitted_resources.water_mg) == WATER_STOCK_MG, "E observe_world reports admitted water total")

# --- Scenario A: ACTIVE-only + fail-closed authority deps (§23/§24) --------------

func _scenario_active_only() -> void:
	var manifest := _manifest("WORLD_COMPAT", 16)
	# Fail-closed: no authority attached.
	var bare := Controller.new()
	var bare_init: Dictionary = bare.initialize(manifest)
	_check(not bool(bare_init.get("success", false)) and String(bare_init.get("error", "")) == "CONTROLLER_WORLD_AUTHORITY_REQUIRED", "A initialize without world authority fails closed")
	# LAB mode does not need (and cannot use) the WORLD stocks bridge.
	var lab := Controller.new()
	_check(bool(lab.initialize(_manifest("LAB", 2)).get("success", false)), "A LAB initialize still works")
	var lab_stocks: Dictionary = lab.apply_world_stocks({"water_mg": 1}, "probe")
	_check(not bool(lab_stocks.get("success", false)) and String(lab_stocks.get("error", "")) == "CONTROLLER_WORLD_STOCKS_LAB", "A LAB field cannot be written through the world bridge")

	var adapter := _adapter(manifest, _region("node/a", 1, "ACTIVE"), [])
	var wc := _wc_controller(manifest, adapter)
	_check(bool(wc.run(2).get("success", false)), "A ACTIVE region ticks proceed")
	var before: Dictionary = wc.debug_state()
	var hash_before := String(wc.get_snapshot().canonical_state_hash)
	# World-side lifecycle change: region becomes WARM (handoff preparation).
	var warm := _region("node/a", 1, "WARM")
	_check(bool(adapter.set_region(warm).get("success", false)), "A adapter tracks WARM region descriptor")
	var rejected: Dictionary = wc.step()
	_check(not bool(rejected.get("success", false)) and String(rejected.get("error", "")).contains("A10_REGION_NOT_EXECUTABLE"), "A WARM region tick fails closed: " + str(rejected))
	_check(String(wc.status()) == "FAILED", "A controller is FAILED after rejection")
	_check(wc.debug_state() == before, "A rejected tick leaves state unchanged")
	_check(String(wc.get_snapshot().get("canonical_state_hash", "")) == hash_before or not bool(wc.get_snapshot().get("success", false)), "A rejected tick leaves snapshot identity unchanged")

# --- Scenario M: explicit-only matter mapping (§23) -------------------------------

func _scenario_explicit_mapping() -> void:
	var manifest := _manifest("WORLD_COMPAT", 4)
	var catalog := Catalog.default_catalog()
	# Unmapped resources are not guessed.
	var adapter := _adapter(manifest, _region("node/a", 1, "ACTIVE"), [{"material_id": "matter/water-ice", "resource": "water_mg"}])
	var mixed := Batch.create({
		"batch_id": "batch/p12-mixed", "container_id": "container/p12", "source_body_id": "body/moon",
		"source_operation_id": "operation/p12", "total_mass_kg": 0.001, "bulk_volume_m3": 0.000001,
		"composition": Composition.create([
			{"material_id": "matter/regolith-loose", "mass_fraction": 0.75},
			{"material_id": "matter/water-ice", "mass_fraction": 0.25},
		]),
		"temperature_k": 273.15,
	})
	var admitted: Dictionary = adapter.add_batch(mixed, String(mixed.checksum))
	_check(bool(admitted.get("success", false)), "M mixed batch admitted through explicit mapping")
	if bool(admitted.get("success", false)):
		var a: Dictionary = admitted.admission
		_check(int(a.resources.water_mg) == 250, "M only explicitly mapped water counted")
		_check(int(a.resources.nutrient_mg) == 0 and int(a.resources.organic_mg) == 0, "M nutrient/organic grants absent (not guessed)")
		_check(a.unmapped_materials.size() == 1 and String(a.unmapped_materials[0].material_id) == "matter/regolith-loose", "M regolith stays explicitly unmapped")
		_check(int(a.mapped_mass_mg) + int(a.unmapped_mass_mg) == int(a.total_mass_mg), "M mass conservation holds")
	# Unknown material entry -> explicit configure failure.
	var bad := Adapter.new()
	var bad_configured: Dictionary = bad.configure(manifest, {
		"region": _region("node/a", 1, "ACTIVE"), "entity_id": "organism/wc-p12",
		"owner_id": "node/a", "catalog": catalog,
		"mapping_entries": [{"material_id": "matter/not-in-catalog", "resource": "nutrient_mg"}],
	})
	_check(not bool(bad_configured.get("success", false)) and String(bad_configured.get("error", "")) == "ADAPTER_MAPPING_INVALID", "M unknown material entry fails configure")
	# Tampered batch (schema-valid rehash, stale trusted anchor) -> rejected.
	var rehashed := mixed.duplicate(true)
	rehashed.temperature_k = 274.15
	rehashed.checksum = MatterUtils.compute_checksum(rehashed)
	var tampered: Dictionary = adapter.add_batch(rehashed, String(mixed.checksum))
	_check(not bool(tampered.get("success", false)) and String(tampered.get("error", "")) == "A10_R2_BATCH_EXTERNAL_ANCHOR", "M tampered batch rejected on trusted anchor")
	# WORLD_COMPAT manifests declaring zone stocks are dual truth -> rejected.
	var dual := _manifest("WORLD_COMPAT", 4)
	var zone: Dictionary = dual.environment.zones[0]
	zone.water_mg = 10
	var dual_ctl := Controller.new()
	var dual_adapter := Adapter.new()
	_check(bool(dual_adapter.configure(dual, {
		"region": _region("node/a", 1, "ACTIVE"), "entity_id": "organism/wc-p12",
		"owner_id": "node/a", "catalog": catalog, "mapping_entries": [],
	}).get("success", false)), "M dual-truth adapter configured")
	dual_ctl.attach_world_authority(dual_adapter)
	var dual_init: Dictionary = dual_ctl.initialize(dual)
	_check(not bool(dual_init.get("success", false)) and String(dual_init.get("error", "")).contains("ADAPTER_ZONE_STOCK_DUAL_TRUTH"), "M WORLD_COMPAT zone stocks rejected as dual truth")

	# Multi-batch delta-only: the second apply deposits ONLY the second batch,
	# never the cumulative first+second total.
	var delta_adapter := _adapter(manifest, _region("node/a", 1, "ACTIVE"), [{"material_id": "matter/water-ice", "resource": "water_mg"}])
	var delta_ctl := _wc_controller(manifest, delta_adapter)
	var b1 := _water_batch_amount("batch/p12-delta-a", 1000)
	var b2 := _water_batch_amount("batch/p12-delta-b", 250)
	_check(bool(delta_adapter.add_batch(b1, String(b1.checksum)).get("success", false)), "M delta batch A admitted")
	var first_apply: Dictionary = delta_adapter.apply_environment(delta_ctl)
	_check(bool(first_apply.get("success", false)), "M delta batch A applied")
	var after_first := _field_total(delta_ctl, "water_mg")
	_check(after_first == 1000, "M first batch deposits exactly 1000 mg")
	_check(bool(delta_adapter.add_batch(b2, String(b2.checksum)).get("success", false)), "M delta batch B admitted")
	var second_apply: Dictionary = delta_adapter.apply_environment(delta_ctl)
	_check(bool(second_apply.get("success", false)), "M delta batch B applied")
	var after_second := _field_total(delta_ctl, "water_mg")
	_check(after_second - after_first == 250, "M second apply deposits only the new 250 mg delta")
	_check(int(delta_adapter.observe_world().admitted_resources.water_mg) == 1250, "M cumulative admitted observation is 1250 mg without redeposit")
	var no_pending: Dictionary = delta_adapter.apply_environment(delta_ctl)
	_check(bool(no_pending.get("success", false)) and not bool(no_pending.get("applied", true)), "M third apply with no new batch is a no-op")
	_check(_field_total(delta_ctl, "water_mg") == 1250, "M no-op apply leaves field mass unchanged")

	# Multi-cell total stock has no canonical spatial allocation witness.
	# It must fail closed instead of multiplying one batch by cell count.
	var multi := _manifest("WORLD_COMPAT", 4)
	multi.environment.spatial.width = 2
	multi.placement.entries[0].position_mm = [500, 0, 500]
	var multi_adapter := _adapter(multi, _region("node/a", 1, "ACTIVE"), [{"material_id": "matter/water-ice", "resource": "water_mg"}])
	var multi_ctl := _wc_controller(multi, multi_adapter)
	var mb := _water_batch_amount("batch/p12-multicell", 500)
	_check(bool(multi_adapter.add_batch(mb, String(mb.checksum)).get("success", false)), "M multi-cell batch admitted at mapping layer")
	var multi_apply: Dictionary = multi_adapter.apply_environment(multi_ctl)
	_check(not bool(multi_apply.get("success", false)) and String(multi_apply.get("error", "")).contains("SPATIAL_ALLOCATION_REQUIRED"), "M multi-cell total batch fails closed without allocation witness")
	_check(_field_total(multi_ctl, "water_mg") == 0, "M multi-cell failure deposits zero mass")
	_check(int(multi_adapter.observe_world().admitted_resources.water_mg) == 0, "M failed multi-cell write is not committed into admitted-resource bookkeeping")

# --- Scenario H: region handoff E2E (§24) -----------------------------------------

func _scenario_handoff() -> void:
	var manifest := _manifest("WORLD_COMPAT", 32)
	var region_a_active := _region("node/a", 1, "ACTIVE")
	var region_b_warm := _region("node/b", 2, "WARM")
	var region_b_active := _region("node/b", 2, "ACTIVE")
	var adapter := _adapter(manifest, region_a_active, [])
	var wc := _wc_controller(manifest, adapter)
	_check(bool(wc.run(4).get("success", false)), "H live ecology ticks in ACTIVE region A")
	var before_ids: Dictionary = _presentation(wc)
	var before_print := _semantic_fingerprint(wc)

	# Checkpoint identity anchor: controller serialize_state (P8). The A8
	# snapshot_seam ecology payload is bound to the A7 observatory treatment
	# model and cannot carry controller state (documented canonical fit).
	var checkpoint: Dictionary = wc.serialize_state()
	_check(bool(checkpoint.get("success", false)), "H controller checkpoint serialized")

	# WARM handoff preparation.
	var prepared: Dictionary = adapter.prepare_region_handoff(region_b_warm, int(adapter.cursor().clock) + 100)
	_check(bool(prepared.get("success", false)), "H prepare_region_handoff (WARM target) succeeds: " + str(prepared))
	if not bool(prepared.get("success", false)):
		return
	var ticket: Dictionary = prepared.ticket
	_check(String(ticket.state) == "REQUESTED", "H prepared ticket is REQUESTED")
	# Premature commit is rejected.
	var premature: Dictionary = SeamBinding.admit_committed(adapter.cursor(), region_b_active, ticket)
	_check(not bool(premature.get("success", false)) and String(premature.get("error", "")) == "A10_R3_TICKET_NOT_COMMITTED", "H REQUESTED ticket cannot authorize commit")

	# Drive the production handoff state machine to COMMITTED.
	var machine := Machine.new()
	_check(bool(machine.setup(ticket).get("success", false)), "H handoff machine setup")
	var snapshot_hash := String(checkpoint.get("state_hash", ""))
	var snapshot_id := "p12." + snapshot_hash.substr(0, 16)
	var tick := int(ticket.created_at_tick) + 1
	for state in ["PREPARING", "FROZEN", "SNAPSHOT_READY", "TARGET_PREPARED", "COMMITTED"]:
		var context := {"tick": tick}
		if state == "SNAPSHOT_READY":
			context["snapshot_id"] = snapshot_id
			context["snapshot_hash"] = snapshot_hash
		var step_result: Dictionary = machine.transition(state, context)
		_check(bool(step_result.get("success", false)), "H handoff transition " + state + ": " + str(step_result.get("error_code", "")))
		tick += 1
	var committed_ticket: Dictionary = machine.ticket
	_check(String(committed_ticket.state) == "COMMITTED" and bool(Ticket.validate(committed_ticket).get("success", false)), "H ticket reaches canonical COMMITTED")

	# Post-commit: authority switches to the new ACTIVE region.
	var commit_result: Dictionary = adapter.commit_region_handoff(region_b_active, committed_ticket)
	_check(bool(commit_result.get("success", false)), "H commit_region_handoff admits committed ticket: " + str(commit_result))
	if not bool(commit_result.get("success", false)):
		return
	var new_cursor: Dictionary = adapter.cursor()
	_check(String(new_cursor.owner_id) == "node/b" and int(new_cursor.owner_epoch) == 2, "H cursor moved to new owner/epoch")

	# Old owner rejected after commit.
	var old_cursor := new_cursor.duplicate(true)
	old_cursor.owner_id = "node/a"
	old_cursor.owner_epoch = 1
	var old_vs_new: Dictionary = WorldBinding.admit_cursor(old_cursor, region_b_active)
	_check(not bool(old_vs_new.get("success", false)) and String(old_vs_new.get("error", "")) == "A10_CURSOR_OWNER_MISMATCH", "H old owner cursor rejected against new region")
	var new_vs_old: Dictionary = WorldBinding.admit_cursor(new_cursor, region_a_active)
	_check(not bool(new_vs_old.get("success", false)) and String(new_vs_old.get("error", "")) == "A10_CURSOR_OWNER_MISMATCH", "H new cursor rejected against superseded old region")

	# Ecology continues with the same organisms.
	var continued: Dictionary = wc.run(2)
	_check(bool(continued.get("success", false)), "H ecology continues after commit: " + str(continued))
	var after_ids: Dictionary = _presentation(wc)
	_check(after_ids.keys() == before_ids.keys(), "H individual_ids preserved across seam")
	var after_print := _semantic_fingerprint(wc)
	for individual_id in before_print.keys():
		_check(String(after_print[individual_id].biological_hash) == String(before_print[individual_id].biological_hash), "H biological_hash preserved across seam: " + individual_id)
		_check(int(after_ids[individual_id].lineage_depth) == int(before_ids[individual_id].lineage_depth), "H lineage_depth preserved: " + individual_id)

	# Checkpoint identity: restore into a fresh controller bound to the new
	# authority and continue.
	# Persist AFTER the committed handoff so the shared checkpoint contains the
	# exact current WORLD_COMPAT authority state (region B + cursor).
	var post_checkpoint: Dictionary = wc.serialize_state()
	_check(bool(post_checkpoint.get("success", false)), "H post-handoff WORLD_COMPAT checkpoint serialized")
	var adapter2 := _adapter(manifest, region_b_active, [])
	var wc2 := _wc_controller(manifest, adapter2)
	var no_anchor: Dictionary = wc2.load_state(String(post_checkpoint.get("state_text", "")), String(post_checkpoint.get("manifest_hash", "")))
	_check(not bool(no_anchor.get("success", false)), "H WORLD_COMPAT restore rejects missing caller-owned state anchor")
	var restored: Dictionary = wc2.load_state(String(post_checkpoint.get("state_text", "")), String(post_checkpoint.get("manifest_hash", "")), String(post_checkpoint.get("state_checksum", "")))
	_check(bool(restored.get("success", false)), "H checkpoint restores runtime + WORLD_COMPAT authority state: " + str(restored))
	if bool(restored.get("success", false)):
		_check(int(wc2.get_snapshot().tick) == int(post_checkpoint.get("tick", -1)), "H checkpoint tick preserved")
		_check(adapter2.cursor() == adapter.cursor(), "H cursor/authority bookkeeping restored exactly")
		_check(String(adapter2.region().owner_node_id) == "node/b" and int(adapter2.region().authority_epoch) == 2, "H restored adapter remains on committed owner B/epoch 2")
		_check(bool(wc2.run(1).get("success", false)), "H restored controller continues ticking under restored owner B")

	# Production ecology_region_ownership_v1 handoff line composed alongside.
	var catchup := _completed_catchup()
	var snapshot := ProductionPersistence.create_snapshot(catchup)
	_check(not snapshot.is_empty(), "H production region snapshot fixture valid")
	var source_owner := Ownership.create_ownership(snapshot, "server-node-a", 0)
	_check(not source_owner.is_empty(), "H production source ownership created")
	var package_result: Dictionary = Adapter.production_prepare_handoff(source_owner, "server-node-b")
	_check(bool(package_result.get("success", false)), "H production handoff package prepared")
	if bool(package_result.get("success", false)):
		var accepted: Dictionary = Adapter.production_accept_handoff(source_owner, package_result.package, "server-node-b")
		_check(bool(accepted.get("success", false)), "H production handoff accepted by target server")
		if bool(accepted.get("success", false)):
			_check(String(accepted.ownership.owner_server_id) == "server-node-b" and int(accepted.ownership.ownership_epoch) == 1, "H production target ownership fenced at next epoch")
			_check(Ownership.accept_handoff(accepted.ownership, package_result.package, "server-node-b").is_empty(), "H replayed production handoff rejected against new owner (old owner fenced)")
			_check(not Ownership.authorize(accepted.ownership, "server-node-a", 0, String(source_owner.ownership_hash), String(source_owner.snapshot_hash)), "H old production owner cannot authorize the new ownership")

# --- Scenario D: damage overlay (§25) ----------------------------------------------

func _scenario_damage() -> void:
	var manifest := _manifest("WORLD_COMPAT", 64)
	var adapter := _adapter(manifest, _region("node/a", 1, "ACTIVE"), [{"material_id": "matter/water-ice", "resource": "water_mg"}])
	var wc := _wc_controller(manifest, adapter)
	var water := _water_batch()
	_check(bool(adapter.add_batch(water, String(water.checksum)).get("success", false)), "D world water stocks admitted")
	_check(bool(adapter.apply_environment(wc).get("success", false)), "D world environment applied")
	_check(bool(wc.run(48).get("success", false)), "D WORLD_COMPAT ecology advances before damage")
	var debug: Dictionary = wc.debug_state()
	_check(debug.population.size() >= 1, "D population present")
	if debug.population.is_empty():
		return
	var individual_id := String(debug.population[0].state.individual_id)
	var modules: Array = debug.population[0].state.development.modules
	_check(modules.size() >= 3, "D body grew at least support+collector modules (modules=%d)" % modules.size())
	if modules.size() < 3:
		return
	var topology_before := Body.topology_signature(modules)
	var body_digest_before := C.digest(modules)

	# External trusted damage anchor fixtures over a construction snapshot.
	var parts := [
		Part.create("part/support", "item/support", "BIO_PROXY", "support", 1.0, [0.0, 0.5, 0.0]),
		Part.create("part/leaf", "item/leaf", "BIO_PROXY", "collector", 0.2, [0.25, 1.25, 0.0]),
	]
	var source_snapshot := Snapshot.create("construct/p12", "item/p12-root", 1, "OPERATIONAL", parts, [], {})
	_check(bool(Snapshot.validate(source_snapshot).get("success", false)), "D construction source snapshot valid")
	var part_to_module := {"part/support": String(modules[1].id), "part/leaf": String(modules[2].id)}
	var request := DamageRequest.create("damage/p12", "construct/p12", source_snapshot.checksum, "part/leaf", [], [], {"part/support": "DESTROYED"})
	_check(bool(DamageRequest.validate(request).get("success", false)), "D damage request fixture valid")
	var target_snapshot := Snapshot.create("construct/p12", "item/p12-root", 2, "DAMAGED", [parts[0]], [], {})
	var repair := RepairPlan.create("repair/p12", "damage/p12", target_snapshot, [], [], [], [], request.checksum)
	_check(bool(RepairPlan.validate(repair).get("success", false)), "D repair plan fixture valid")
	var record := DamageRecord.create("damage/p12", request.checksum, "d".repeat(64), repair, [], 5)
	_check(bool(DamageRecord.validate(record).get("success", false)), "D applied DamageRecord fixture valid")

	# Tampered record checksum anchor -> rejected before any binding.
	var rehashed := record.duplicate(true)
	rehashed.applied_generation = 6
	rehashed.checksum = DamageRecord.compute_checksum(rehashed)
	var tampered: Dictionary = adapter.register_damage(wc, individual_id, request, rehashed, source_snapshot, part_to_module, String(record.checksum))
	_check(not bool(tampered.get("success", false)) and String(tampered.get("error", "")) == "A10_DAMAGE_RECORD_ANCHOR", "D tampered DamageRecord rejected on trusted anchor")

	# Register + apply the trusted record.
	var registered: Dictionary = adapter.register_damage(wc, individual_id, request, record, source_snapshot, part_to_module, String(record.checksum))
	_check(bool(registered.get("success", false)), "D trusted DamageRecord registered: " + str(registered))
	if not bool(registered.get("success", false)):
		return
	# The event anchor is stored separately from the event. A fully rehashed
	# exported adapter state with event.binding_hash changed must still fail
	# import because the trusted anchor is caller-owned state, not derived from
	# the event being checked.
	var exported: Dictionary = adapter.export_state()
	_check(not exported.is_empty(), "D adapter WORLD state exports after damage registration")
	if not exported.is_empty():
		var tampered_world := exported.duplicate(true)
		var damage_row: Dictionary = tampered_world.damage[individual_id]
		damage_row.event.binding_hash = "e".repeat(64)
		tampered_world.checksum = ""
		var checksum_payload := tampered_world.duplicate(true)
		checksum_payload.checksum = ""
		tampered_world.checksum = C.digest(checksum_payload)
		var tampered_hash := C.digest(tampered_world)
		var import_tampered: Dictionary = adapter.import_state(tampered_world, tampered_hash)
		_check(not bool(import_tampered.get("success", false)) and String(import_tampered.get("error", "")).contains("DAMAGE_EVENT_ANCHOR"), "D rehashed event cannot replace separately stored trusted binding anchor")
	var effective_before: Dictionary = adapter.effective_function(individual_id)
	_check(int(effective_before.active_module_count) == modules.size(), "D pre-damage body fully active")
	var applied: Dictionary = adapter.apply_damage(individual_id)
	_check(bool(applied.get("success", false)) and not bool(applied.get("replay", false)), "D damage applied to overlay")
	if bool(applied.get("success", false)):
		var overlay: Dictionary = applied.overlay
		_check(int(overlay.revision) == 1, "D overlay revision advanced exactly once")
		_check(overlay.destroyed_modules == [String(modules[1].id)], "D destroyed module recorded")
		_check(overlay.disabled_modules.has(String(modules[2].id)), "D descendant module disabled by closure")
	var effective_after: Dictionary = adapter.effective_function(individual_id)
	_check(not effective_after.is_empty(), "D effective_function available after damage")
	_check(int(effective_after.active_module_count) < int(effective_before.active_module_count), "D effective active module count differs")
	_check(String(effective_after.functional_hash) != String(effective_before.functional_hash), "D functional_hash differs after damage")
	# Historical BodyGraph untouched.
	_check(Body.topology_signature(wc.debug_state().population[0].state.development.modules) == topology_before, "D historical topology_signature unchanged")
	_check(C.digest(wc.debug_state().population[0].state.development.modules) == body_digest_before, "D historical BodyGraph bytes unchanged")
	# Idempotent replay.
	var replay: Dictionary = adapter.apply_damage(individual_id)
	_check(bool(replay.get("success", false)) and bool(replay.get("replay", false)), "D damage replay is idempotent")

	# Inspector shows the three layers separately.
	var inspected: Dictionary = Inspector.compile(wc, individual_id, adapter)
	_check(bool(inspected.get("success", false)), "D inspector compiles with world adapter")
	if bool(inspected.get("success", false)):
		var damage: Dictionary = inspected.view.damage
		_check(bool(damage.get("overlay_present", false)), "D inspector damage overlay present")
		_check(String(damage.historical.topology_signature) == topology_before, "D inspector layer 1: historical topology")
		_check(int(damage.overlay.revision) == 1, "D inspector layer 2: damage overlay")
		_check(int(damage.effective.active_module_count) == int(effective_after.active_module_count), "D inspector layer 3: effective active modules")
		var text := Inspector.render_text(inspected.view)
		_check(text.contains("HISTORICAL") and text.contains("OVERLAY") and text.contains("EFFECTIVE"), "D inspector renders three separate layers")
	# LAB-shaped damage section without adapter.
	var lab_view: Dictionary = Inspector.compile_from_debug(wc.debug_state(), individual_id)
	_check(not bool(lab_view.view.damage.overlay_present), "D without adapter the damage section keeps the explicit empty shape")

# --- production fixture chain (P3.7 -> P4.4 snapshot) ------------------------------

const Persistence = preload("res://scripts/research/ecology/plant_ecosystem_persistence_v1.gd")

func _completed_catchup() -> Dictionary:
	var p3_initial := Persistence.initialize(_initial_p3_7_result())
	var region := RegionState.create_region_state("planet-01:region_0007", 42.5, p3_initial)
	var clock := EcologyClock.create_clock(region, 1.0)
	var catchup := OfflineCatchup.create(region, 47.9, clock)
	return OfflineCatchup.advance_batch(catchup, 5)

func _initial_p3_7_result() -> Dictionary:
	var parent := _disturbance_result()
	var niches := _niches()
	var community := Coexistence.community_from_parent(parent, niches)
	var skewed := _skew_community(community, 0.05, 0.95)
	return Coexistence.step(parent, skewed, niches, {"stabilization_fraction": 0.5})

func _niches() -> Array:
	return [{"id":"alpha","temperature_optimum_c":10.0,"temperature_breadth_c":12.0,"moisture_optimum":0.8,"moisture_breadth":0.5,"light_optimum":0.5,"light_breadth":0.5,"nutrients_optimum":0.9,"nutrients_breadth":0.7},{"id":"beta","temperature_optimum_c":15.0,"temperature_breadth_c":12.0,"moisture_optimum":0.65,"moisture_breadth":0.5,"light_optimum":0.85,"light_breadth":0.5,"nutrients_optimum":0.4,"nutrients_breadth":0.7}]

func _skew_community(base: Array, alpha_share: float, beta_share: float) -> Array:
	var out := []
	for patch_value in base:
		var patch: Dictionary = patch_value
		var total := 0.0
		for plant_value in patch["plants"]:
			total += float(plant_value["biomass_kg"])
		out.append({"id":String(patch["id"]),"plant_order":PackedStringArray(["alpha","beta"]),"plants":[{"id":"alpha","biomass_kg":total*alpha_share},{"id":"beta","biomass_kg":total*beta_share}]})
	return out

func _disturbance_result() -> Dictionary:
	return Disturbance.apply(_seasonal(0.0), _disturbance(0.8, 1.0, 0.0, 0.0), _traits(), 2.0)

func _traits() -> Array:
	return [{"id":"alpha","heat_resistance":0.9,"flood_resistance":0.2,"drought_resistance":0.2,"recovery_rate":0.4,"pioneer_capacity":0.2},{"id":"beta","heat_resistance":0.2,"flood_resistance":0.8,"drought_resistance":0.8,"recovery_rate":0.9,"pioneer_capacity":0.9}]

func _disturbance(s: float, h: float, f: float, d: float) -> Dictionary:
	return {"severity":s,"heat_pressure":h,"flood_pressure":f,"drought_pressure":d,"recovery_time_scale_years":2.0}

func _seasonal(t: float) -> Dictionary:
	return Seasonal.evaluate(_environment(), t, _season_config())

func _season_config() -> Dictionary:
	return {"cycle":{"period_years":1.0,"epoch_year":0.0,"phase_x_slope":0.0,"phase_y_slope":0.125,"phase_altitude_slope":0.0},"temperature_c":{"amplitude":10.0,"phase_offset":0.0},"moisture":{"amplitude":0.2,"phase_offset":0.25},"light":{"amplitude":0.1,"phase_offset":0.5},"nutrients":{"amplitude":0.15,"phase_offset":0.75}}

func _environment() -> Dictionary:
	return EnvGradient.apply(_spatial(0.2), [{"id":"C","x":4.0,"y":2.0,"altitude":200.0},{"id":"A","x":0.0,"y":0.0,"altitude":0.0},{"id":"B","x":2.0,"y":0.0,"altitude":100.0}], _environment_config())

func _environment_config() -> Dictionary:
	return {"origin":{"x":0.0,"y":0.0,"altitude":0.0},"temperature_c":_channel(20.0,-1.0,0.5,-0.01,-50.0,50.0),"moisture":_channel(0.8,-0.05,0.025,-0.001,0.0,1.0),"light":_channel(0.4,0.05,0.025,0.001,0.0,1.0),"nutrients":_channel(0.9,-0.05,-0.025,-0.0005,0.0,1.0)}

func _channel(b: float, x: float, y: float, z: float, mn: float, mx: float) -> Dictionary:
	return {"base":b,"x_slope":x,"y_slope":y,"altitude_slope":z,"min":mn,"max":mx}

func _spatial(fraction: float) -> Dictionary:
	var a := _density([{"id":"alpha","biomass_kg":6.0},{"id":"beta","biomass_kg":4.0}],10.0)
	var b := _density([{"id":"beta","biomass_kg":2.0}],2.0)
	var c := _density([],10.0)
	return Dispersal.disperse([{"id":"C","density_result":c,"boundary_export_fraction":0.0},{"id":"A","density_result":a,"boundary_export_fraction":0.25},{"id":"B","density_result":b,"boundary_export_fraction":0.0}],[{"from":"A","to":"C","weight":1.0},{"from":"A","to":"B","weight":3.0}],{"dispersal_fraction":fraction})

func _density(plants: Array, capacity: float) -> Dictionary:
	var competitors := []
	for plant in plants:
		competitors.append({"id":String(plant["id"]),"demand":_resources(1.0),"capture_efficiency":_resources(1.0)})
	return Density.step(Competition.compete(_resources(100.0), competitors), {"area_m2":capacity,"reference_capacity_kg_m2":1.0,"minimum_capacity_fraction":0.25,"max_recovery_fraction":0.25,"max_decline_fraction":0.6}, plants)

func _resources(value: float) -> Dictionary:
	return {"light":value,"water":value,"nutrients":value}

# --- driver ------------------------------------------------------------------------

func _run() -> void:
	_scenario_equivalence()
	_scenario_active_only()
	_scenario_explicit_mapping()
	_scenario_handoff()
	_scenario_damage()
	_finish()

func _finish() -> void:
	print("EVO_ARCH2_A10_5_WORLD_COMPAT checks=%d failed=%d" % [checks, failures.size()])
	if failures.is_empty():
		print("EVO_ARCH2_A10_5_WORLD_COMPAT PASS")
		quit(0)
	else:
		for failure in failures:
			print("A10_5_P12_FAILURE " + failure)
		quit(1)
