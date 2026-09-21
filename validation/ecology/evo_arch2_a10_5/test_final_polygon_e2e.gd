extends SceneTree

# ECO ARCH2 A10.5 / ECO-POLYGON-1 — P13 FINAL END-TO-END acceptance (§31
# minimal user scenario, headless automation of every automatable step).
# Runner: Godot headless --script; prints checks/failed counts and PASS/FAIL.
#
# Steps (roadmap R2 §7, automated headless; each step = assertions):
#  S1  create experiment, OrganizationProfile=FREE (no curated archetype);
#  S2  two canonical founders;
#  S3  structural variant through the genome editor (canonical A3 only);
#  S4  WET/DRY/DARK zones;
#  S5  placement: same founders -> different zones + different founders ->
#      one zone (PlacementPlan generators);
#  S6  run simulation (per-tick loop with observatory);
#  S7  growth (development modules advanced);
#  S8  resource consumption (field stocks decreased);
#  S9  reproduction (birth event through the metrics timeline);
#  S10 inherited mutation: receipt-backed admission, at least one REALLY
#      inherited mutated genome; no fallback status exists (repair R2);
#  S11 real Polygon-controller starvation death -> corpse return ->
#      mineralization on THE single canonical field (repair R2);
#  S12 unknown BodyGraph topology through the generic realizer (all-roles
#      program + an invented unknown role module);
#  S13 full inspector chain (genome -> ... -> lineage);
#  S14 checkpoint;
#  S15 branch A advance;
#  S16 restore;
#  S17 branch B with an environment patch (different history);
#  S18 replay of the original branch -> identical hash;
#  S19 SOFT organization profile -> canonical A3 DEVELOPMENT_BIAS;
#      VISUAL_ONLY rendering remains non-causal;
#  S20 batch of 3 seeds -> complete report, no cherry-picking;
#  S21 WORLD-COMPAT scenario: region handoff (ACTIVE->WARM->COMMITTED->new
#      ACTIVE) + damage overlay through the polygon world adapter.

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const P = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const Genome = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const Body = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const Protocol = preload("res://scripts/research/ecology/v2/observatory_protocol_v1.gd")
const Fixtures = preload("res://scripts/research/ecology/v2/body_program_fixtures_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Manifest = preload("res://scripts/ecology/workbench/experiment_manifest_v1.gd")
const GenomeEditor = preload("res://scripts/ecology/workbench/genome_editor_v1.gd")
const PlacementPlan = preload("res://scripts/ecology/workbench/placement_plan_v1.gd")
const EnvironmentPatch = preload("res://scripts/ecology/workbench/environment_patch_v1.gd")
const ExperimentBranch = preload("res://scripts/ecology/workbench/experiment_branch_v1.gd")
const Metrics = preload("res://scripts/ecology/workbench/experiment_metrics_v1.gd")
const Batch = preload("res://scripts/ecology/workbench/batch_runner_v1.gd")
const Profile = preload("res://scripts/ecology/workbench/organization_profile_v1.gd")
const Inspector = preload("res://scripts/ecology/workbench/organism_inspector_v1.gd")
const Descriptor = preload("res://scripts/ecology/workbench/morphology_descriptor_v1.gd")
const Realizer = preload("res://scripts/ecology/workbench/generic_morphology_realizer_v1.gd")
const Adapter = preload("res://scripts/ecology/workbench/polygon_world_adapter_v1.gd")
# WORLD-COMPAT fixtures (A10 contracts + handoff/damage machinery).
const Region = preload("res://scripts/network/contracts/authority_region_descriptor.gd")
const Catalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const Composition = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const MatterBatch = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")
const Machine = preload("res://scripts/network/handoff/handoff_state_machine.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const ConstructSnapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const DamageRequest = preload("res://scripts/construction/damage/construction_damage_request.gd")
const DamageRecord = preload("res://scripts/construction/damage/construction_damage_record.gd")
const RepairPlan = preload("res://scripts/construction/damage/construction_repair_plan.gd")

const WATER_STOCK_MG := 500000

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("A10_5_P13_E2E_FAIL " + message)

# --- fixtures ---------------------------------------------------------------------

func _manifest_3zones(seed: int, founders: Array, entries: Array) -> Dictionary:
	return {
		"schema": Manifest.SCHEMA,
		"experiment_id": "eco-polygon/exp-p13-e2e",
		"seed": seed,
		"horizon_ticks": 64,
		"founders": founders,
		"environment": {
			"spatial": {"origin_mm": [0, 0, 0], "cell_size_mm": 1000, "width": 3, "depth": 1},
			"zones": [
				{"id": "wet", "water_mg": 800000, "light": 800, "temperature": 500, "nutrient_mg": 2000, "organic_mg": 0},
				{"id": "dry", "water_mg": 200000, "light": 900, "temperature": 600, "nutrient_mg": 300, "organic_mg": 0},
				{"id": "dark", "water_mg": 100000, "light": 100, "temperature": 450, "nutrient_mg": 100, "organic_mg": 0},
			],
		},
		"placement": {"entries": entries},
		"mutation": {"operator": "small", "mutations_enabled": true},
		"organization_profile": "FREE",
		"feedback": {"enabled": true, "decomposition_enabled": true},
		"metrics": {"requested": ["population"]},
		"checkpoint": {"interval_ticks": 16},
		"mode": "LAB",
	}

func _two_founders() -> Array:
	return [
		{"founder_id": "founder/a", "biological_hash": null, "genome": Protocol.ancestor()},
		{"founder_id": "founder/b", "biological_hash": null, "genome": Fixtures.make(1)},
	]

func _stock_sum(controller: Object, resource: String) -> int:
	var total := 0
	for cell in controller.debug_state().field.cells:
		total += int(cell.stocks[resource])
	return total

func _alive_count(controller: Object) -> int:
	var count := 0
	for entry in controller.debug_state().population:
		if bool(entry.state.alive):
			count += 1
	return count

# --- S1+S2: experiment FREE with two founders -------------------------------------

func _scenario_setup() -> Dictionary:
	var controller := Controller.new()
	var manifest := _manifest_3zones(20260912, _two_founders(), [
		{"founder_ref": "founder/a", "zone_id": "wet", "position_mm": [500, 0, 500]},
		{"founder_ref": "founder/b", "zone_id": "dry", "position_mm": [1500, 0, 500]},
	])
	var init_result: Dictionary = controller.initialize(manifest, {})
	_check(bool(init_result.get("success", false)), "S1 experiment created (FREE): " + str(init_result))
	_check(String(controller.status()) == "READY", "S1 controller READY before the first tick")
	var profile: Dictionary = Profile.preset("FREE")
	_check(String(profile.rule_class) == "VISUAL_ONLY", "S1 FREE profile carries no development bias (no curated archetype)")
	_check(Profile.apply_development_bias(profile).get("status", "") == "NOT_APPLICABLE", "S1 FREE profile has no development semantics")
	var debug: Dictionary = controller.debug_state()
	_check(debug.population.size() == 2, "S2 two founders planted")
	var hashes := []
	for entry in debug.population:
		hashes.append(Genome.biological_hash(entry.blueprint.genome))
	_check(hashes.size() == 2 and String(hashes[0]) != String(hashes[1]), "S2 founders are distinct canonical genomes")
	return {"controller": controller, "manifest": manifest, "registry": {}}

# --- S3: structural variant through the genome editor ------------------------------

func _scenario_variant(state: Dictionary) -> void:
	var controller: Object = state.controller
	var genome: Dictionary = Inspector.genome_of(controller, String(controller.debug_state().population[0].state.individual_id))
	_check(not genome.is_empty(), "S3 editor reads the founder genome read-only")
	var proposed: Dictionary = GenomeEditor.propose_variant(genome, {"kind": "mutate", "operator": "small", "seed": 77})
	_check(bool(proposed.get("success", false)), "S3 structural variant proposed through canonical A3 mutate: " + str(proposed.get("error", "")))
	if not bool(proposed.get("success", false)):
		return
	_check(String(proposed.biological_hash) != String(proposed.parent_hash), "S3 variant genome hash differs from the parent")
	var registry: Dictionary = state.registry
	var hash := GenomeEditor.register_founder(registry, proposed.genome)
	_check(not hash.is_empty(), "S3 variant registered in the founder registry")
	var added: Dictionary = GenomeEditor.add_founder_to_manifest(state.manifest, proposed.genome, "founder/c", "dark", [2500, 0, 500])
	_check(bool(added.get("success", false)), "S3 immutable manifest with the variant founder: " + str(added.get("error", "")))
	if not bool(added.get("success", false)):
		return
	_check(String(added.manifest_hash) != String(Manifest.canonical_hash(state.manifest)), "S3 variant manifest is a NEW immutable manifest")
	var reinit: Dictionary = controller.initialize(added.manifest, registry)
	_check(bool(reinit.get("success", false)), "S3 controller re-initialized with 3 founders: " + str(reinit.get("error", "")))
	_check(controller.debug_state().population.size() == 3, "S3 population now carries the variant founder")
	state.manifest = added.manifest

# --- S4+S5: zones + placement generators -------------------------------------------

func _scenario_placement(state: Dictionary) -> void:
	var manifest: Dictionary = state.manifest
	var zone_ids := []
	for zone in manifest.environment.zones:
		zone_ids.append(String(zone.id))
		_check(not PlacementPlan.zone_cells(manifest.environment, String(zone.id)).is_empty(), "S4 zone %s maps to at least one cell" % String(zone.id))
	_check(zone_ids == ["wet", "dry", "dark"], "S4 WET/DRY/DARK zones present")
	# Same founders -> different zones: every founder replicated into every zone.
	var same: Dictionary = PlacementPlan.generate(manifest, "same_founders_different_zones")
	_check(bool(same.get("success", false)), "S5 same_founders_different_zones generates: " + str(same.get("error", "")))
	var zone_seen := {}
	for entry in same.entries:
		zone_seen[String(entry.zone_id)] = true
	_check(zone_seen.keys().size() == 3, "S5 same founders spread across all 3 zones")
	# Different founders -> one zone: all founders in the dark zone.
	var diff: Dictionary = PlacementPlan.generate(manifest, "different_founders_same_zone", {"zone_id": "dark"})
	_check(bool(diff.get("success", false)), "S5 different_founders_same_zone generates")
	var one_zone := true
	for entry in diff.entries:
		if String(entry.zone_id) != "dark":
			one_zone = false
	_check(one_zone and diff.entries.size() == manifest.founders.size(), "S5 different founders share ONE zone")
	# Apply the zone-contrast layout as the experiment placement.
	manifest.placement.entries = same.entries
	var replant: Dictionary = state.controller.initialize(manifest, state.registry)
	_check(bool(replant.get("success", false)), "S5 controller re-initialized from the generated placement")
	_check(state.controller.debug_state().population.size() == same.entries.size(), "S5 population matches the generated entries (%d)" % same.entries.size())
	state.manifest = manifest

# --- S6..S10: run, growth, consumption, reproduction, inherited mutation -------------

func _scenario_run_and_observe(state: Dictionary) -> void:
	var controller: Object = state.controller
	var observer := Metrics.new()
	observer.begin(controller.get_manifest())
	observer.observe(controller)  # tick-0 baseline
	var tick0_debug: Dictionary = controller.debug_state()
	var founder_genomes := {}
	for entry in tick0_debug.population:
		founder_genomes[String(entry.state.individual_id)] = Genome.biological_hash(entry.blueprint.genome)
	var first_id := String(tick0_debug.population[0].state.individual_id)
	var modules_tick0 := int(tick0_debug.population[0].state.development.modules.size())
	var water_tick0 := _stock_sum(controller, "water_mg")
	var population0: int = tick0_debug.population.size()
	# S6 run: step until a birth happens (at least 8 ticks, bounded by 40).
	var ticks := 0
	while ticks < 40 and (ticks < 8 or controller.debug_state().population.size() == population0):
		var step_result: Dictionary = controller.step()
		if not bool(step_result.get("success", false)):
			_check(false, "S6 tick failed: " + str(step_result.get("error", "")))
			return
		observer.observe(controller)
		ticks += 1
	_check(ticks >= 8, "S6 simulation ran (at least 8 ticks, got %d)" % ticks)
	# S7 growth: modules of the tracked organism advanced.
	var modules_now := -1
	for entry in controller.debug_state().population:
		if String(entry.state.individual_id) == first_id:
			modules_now = int(entry.state.development.modules.size())
	_check(modules_now > modules_tick0 or modules_now >= 3, "S7 growth observed (modules %d -> %d)" % [modules_tick0, modules_now])
	# S8 consumption: field water stocks decreased.
	var water_now := _stock_sum(controller, "water_mg")
	_check(water_now < water_tick0, "S8 resource consumption: field water decreased (%d -> %d)" % [water_tick0, water_now])
	# S9/S10 reproduction + REAL inherited mutation (repair R2): births happen
	# through receipt-backed canonical admission; every mutated child differs
	# from its parent genome and carries the sealed receipt binding. The
	# silent parent-blueprint fallback no longer exists, so there is no
	# "applied: false" mutation event and no unapplied lineage mutation.
	var births := 0
	var mutations := 0
	var unapplied_mutations := 0
	for event in observer.timeline:
		if String(event.kind) == "birth":
			births += 1
		elif String(event.kind) == "mutation":
			mutations += 1
			if not bool(event.detail.get("applied", false)):
				unapplied_mutations += 1
	_check(births >= 1, "S9 reproduction: at least one birth/propagule event (births=%d)" % births)
	_check(mutations >= 1, "S10 mutation events recorded (mutations=%d)" % mutations)
	_check(unapplied_mutations == 0, "S10 NO unapplied/fallback mutation events exist (unapplied=%d)" % unapplied_mutations)
	var inherited := 0
	var receipt_bound := 0
	for entry in controller.debug_state().population:
		if String(entry.state.origin_kind) != "PARENT_TRANSFER":
			continue
		var parent_id := String(entry.state.origin_receipt.parent_id)
		var parent_hash := ""
		if founder_genomes.has(parent_id):
			parent_hash = String(founder_genomes[parent_id])
		else:
			for other in controller.debug_state().population:
				if String(other.state.individual_id) == parent_id:
					parent_hash = Genome.biological_hash(other.blueprint.genome)
					break
		var child_hash := Genome.biological_hash(entry.blueprint.genome)
		var record: Dictionary = entry.state.get("mutation_receipt", {})
		if not record.is_empty() and String(record.receipt.child_genome_hash) == child_hash:
			receipt_bound += 1
			if not parent_hash.is_empty() and child_hash != parent_hash:
				inherited += 1
	_check(receipt_bound >= 1, "S10 receipt-backed children present in the lineage (bound=%d)" % receipt_bound)
	_check(inherited >= 1, "S10 at least one REALLY INHERITED mutated genome (child genome != parent genome, inherited=%d)" % inherited)

# --- S11: real death -> corpse return -> decomposition (repair R2) -------------------
# The manifest now owns an explicit founder endowment input. This lets the
# Polygon controller exercise the same canonical starvation/death path as the
# reusable runtime instead of proving death unreachable behind a fixed 200k
# endowment.

func _scenario_death_decomposition() -> void:
	var controller := Controller.new()
	var endowment := Body.stock(0)
	# Preserve material for a real corpse while providing no water/energy for
	# maintenance. The organism starves canonically; the material must return
	# through A6 as organic matter and then mineralize on the SAME field.
	endowment.material_mg = 1000
	var manifest := {
		"schema": Manifest.SCHEMA,
		"experiment_id": "eco-polygon/exp-p13-death",
		"seed": 20260912,
		"horizon_ticks": 16,
		"founders": [{"founder_id": "founder/a", "biological_hash": null, "genome": Protocol.ancestor()}],
		"environment": {
			"spatial": {"origin_mm": [0, 0, 0], "cell_size_mm": 1000, "width": 1, "depth": 1},
			"zones": [{"id": "void", "water_mg": 0, "light": 0, "temperature": 100, "nutrient_mg": 0, "organic_mg": 0}],
		},
		"placement": {"entries": [{"founder_ref": "founder/a", "zone_id": "void", "position_mm": [500, 0, 500]}]},
		"mutation": {"operator": "small", "mutations_enabled": false},
		"organization_profile": "FREE",
		"feedback": {"enabled": true, "decomposition_enabled": true},
		"metrics": {"requested": ["population"]},
		"checkpoint": {"interval_ticks": 16},
		"mode": "LAB",
		"genesis": {"founder_endowment": endowment},
	}
	_check(Manifest.validate(manifest).is_empty(), "S11 low-endowment death manifest validates")
	_check(bool(controller.initialize(manifest, {}).get("success", false)), "S11 low-endowment Polygon experiment initializes")
	var starvation_limit := int(controller.debug_state().population[0].blueprint.life_history.survival.starvation_limit_ticks)
	var run: Dictionary = controller.run(starvation_limit)
	_check(bool(run.get("success", false)), "S11 controller reaches canonical starvation limit")
	var debug: Dictionary = controller.debug_state()
	_check(_alive_count(controller) == 0, "S11 founder dies inside the real Polygon controller")
	_check(debug.feedback.frame.corpses.size() == 1, "S11 A6 registers exactly one corpse on the controller trajectory")
	_check(int(debug.feedback.frame.returned.organic_mg) > 0, "S11 corpse material returned to canonical field as organic matter")
	_check(int(debug.feedback.frame.mineralized_mg) > 0, "S11 corpse-derived organic matter mineralized on the same field")
	_check(_stock_sum(controller, "nutrient_mg") > 0, "S11 canonical field contains corpse-derived mineral nutrient")
	_check(String(controller.get_snapshot().canonical_state_hash) == String(debug.runtime.integrity_hash), "S11 presentation/checkpoint identity is the same sealed runtime state")

# --- S12+S13: unknown topology via the generic realizer + full inspector ------------

func _scenario_realizer_inspector() -> Object:
	var controller := Controller.new()
	var manifest := {
		"schema": Manifest.SCHEMA,
		"experiment_id": "eco-polygon/exp-p13-topology",
		"seed": 20260912,
		"horizon_ticks": 16,
		"founders": [{"founder_id": "founder/t", "biological_hash": null, "genome": Fixtures.make(3)}],
		"environment": {
			"spatial": {"origin_mm": [0, 0, 0], "cell_size_mm": 1000, "width": 1, "depth": 1},
			"zones": [{"id": "wet", "water_mg": 800000, "light": 800, "temperature": 500, "nutrient_mg": 2000, "organic_mg": 0}],
		},
		"placement": {"entries": [{"founder_ref": "founder/t", "zone_id": "wet", "position_mm": [500, 0, 500]}]},
		"mutation": {"operator": "small", "mutations_enabled": false},
		"organization_profile": "FREE",
		"feedback": {"enabled": true, "decomposition_enabled": true},
		"metrics": {"requested": ["population"]},
		"checkpoint": {"interval_ticks": 16},
		"mode": "LAB",
	}
	_check(bool(controller.initialize(manifest, {}).get("success", false)), "S12 all-roles topology experiment initializes")
	_check(bool(controller.run(12).get("success", false)), "S12 topology run(12) succeeds")
	var debug: Dictionary = controller.debug_state()
	_check(not debug.population.is_empty(), "S12 organism present")
	if debug.population.is_empty():
		return controller
	var state: Dictionary = debug.population[0].state
	var modules: Array = state.development.modules
	var roles := {}
	for module in modules:
		roles[String(module.role)] = true
	_check(modules.size() >= 3 and roles.size() >= 3, "S12 all-roles program built a multi-role topology (modules=%d roles=%d)" % [modules.size(), roles.size()])
	var descriptor: Dictionary = Descriptor.compile(modules, String(state.individual_id), state.position_mm)
	_check(not descriptor.is_empty(), "S12 morphology descriptor compiles from the canonical modules")
	var realized: Dictionary = Realizer.realize(descriptor, {"lod": "HIGH"})
	_check(int(realized.get("primitive_count", 0)) >= modules.size(), "S12 generic realizer covers every module (primitives=%d modules=%d)" % [int(realized.get("primitive_count", 0)), modules.size()])
	var covered := {}
	for primitive in realized.primitives:
		covered[String(primitive.module_id)] = true
	var all_covered := true
	for module in modules:
		if not covered.has(String(module.id)):
			all_covered = false
	_check(all_covered, "S12 every canonical module id appears in the primitive manifest")
	# Invented UNKNOWN role: the universal fallback must still cover it.
	var unknown_descriptor: Dictionary = descriptor.duplicate(true)
	unknown_descriptor.modules.append({
		"id": "mod/exotic", "parent": String(modules[0].id), "role": "exotic_organ", "role_class": "unknown",
		"position_mm": [0, 0, 0], "start_mm": [0, 0, 0], "end_mm": [120, 0, 0], "size_mm": [120, 4, 4],
		"radius_mm": 2, "area_mm2": 0, "reach_mm": 0,
	})
	var realized_unknown: Dictionary = Realizer.realize(unknown_descriptor, {"lod": "MEDIUM"})
	var unknown_covered := false
	for primitive in realized_unknown.primitives:
		if String(primitive.module_id) == "mod/exotic":
			unknown_covered = true
	_check(unknown_covered and int(realized_unknown.primitive_count) >= int(realized.primitive_count), "S12 unknown role module still realized by the universal fallback")
	# S13 full inspector chain.
	var inspected: Dictionary = Inspector.compile(controller, String(state.individual_id))
	_check(bool(inspected.get("success", false)), "S13 inspector compiles")
	if bool(inspected.get("success", false)):
		var view: Dictionary = inspected.view
		_check(view.has_all(["genome", "development_program", "development_state", "body_graph", "phenotype", "resources", "damage", "lineage"]), "S13 inspector covers the full chain genome->lineage")
		_check(bool(view.phenotype.get("available", false)), "S13 phenotype snapshot available")
		_check(not bool(view.damage.get("overlay_present", false)), "S13 LAB damage section keeps the explicit empty shape")
		var text := Inspector.render_text(view)
		for marker in ["GENOME", "PROGRAM", "DEVELOPMENT", "BODY", "PHENOTYPE", "RESERVES", "DAMAGE", "LINEAGE"]:
			_check(text.contains(marker), "S13 inspector render shows %s" % marker)
	return controller

# --- S14..S18: checkpoint / advance / restore / fork / replay -------------------------

func _scenario_branches(state: Dictionary) -> void:
	var controller: Object = state.controller
	var registry: Dictionary = state.registry
	var manager := ExperimentBranch.new()
	_check(bool(manager.setup(controller, registry).get("success", false)), "S14 branch manager bound to the experiment controller")
	var checkpoint_result: Dictionary = manager.create_checkpoint("", {"source": "p13-e2e"}, {})
	_check(bool(checkpoint_result.get("success", false)), "S14 checkpoint created")
	if not bool(checkpoint_result.get("success", false)):
		return
	var checkpoint: Dictionary = checkpoint_result.checkpoint
	var checkpoint_tick := int(checkpoint.tick)
	_check(String(ExperimentBranch.validate_checkpoint(checkpoint)).is_empty(), "S14 checkpoint validates (id bound to manifest+tick+state hash)")
	# S15 branch A advance: continue the ORIGINAL branch.
	var advance: Dictionary = controller.run(8)
	_check(bool(advance.get("success", false)), "S15 branch A advanced 8 ticks: " + str(advance.get("error", "")))
	var hash_a := String(controller.get_snapshot().canonical_state_hash)
	# S17 branch B: fork from the SAME checkpoint with an environment patch.
	var patch: Dictionary = EnvironmentPatch.patch("dry", "water_mg", 600000)
	var forked: Dictionary = manager.fork(checkpoint, patch, "branch/env-dry-wet")
	_check(bool(forked.get("success", false)), "S17 fork with env patch succeeds: " + str(forked.get("error", "")))
	var hash_b := ""
	if bool(forked.get("success", false)):
		var branch_controller: Object = forked.controller
		var branch_advance: Dictionary = branch_controller.run(8)
		_check(bool(branch_advance.get("success", false)), "S17 branch B advanced 8 ticks")
		hash_b = String(branch_controller.get_snapshot().canonical_state_hash)
		_check(String(forked.manifest_hash) != String(checkpoint.manifest_hash), "S17 branch B carries a different manifest hash (patched environment)")
	_check(not hash_b.is_empty() and hash_b != hash_a, "S17 branch B final hash differs from branch A (different history)")
	# S16 restore the checkpoint into the main controller.
	var restored: Dictionary = manager.restore(checkpoint)
	_check(bool(restored.get("success", false)), "S16 checkpoint restored into the original controller")
	_check(int(controller.get_snapshot().tick) == checkpoint_tick, "S16 controller back at the checkpoint tick (%d)" % checkpoint_tick)
	# S18 replay: identical checkpoint + manifest + commands -> identical hash.
	var checkpoint_anchor := manager.trusted_checkpoint_anchor(String(checkpoint.checkpoint_id))
	_check(checkpoint_anchor == C.digest(checkpoint), "S18 branch manager exposes the caller-owned checkpoint anchor")
	var replay: Dictionary = ExperimentBranch.replay(checkpoint, controller.get_manifest(), registry, [8], checkpoint_anchor)
	_check(bool(replay.get("success", false)), "S18 replay succeeds: " + str(replay.get("error", "")))
	if bool(replay.get("success", false)):
		_check(String(replay.canonical_state_hash) == hash_a, "S18 replay of the original branch reproduces the identical hash")
		_check(int(replay.tick) == checkpoint_tick + 8, "S18 replay reached the same tick")

# --- S19: canonical DEVELOPMENT_BIAS + visual non-causality -------------------------

func _scenario_profiles(topology_controller: Object) -> void:
	var soft: Dictionary = Profile.preset("SOFT")
	var bias_result: Dictionary = Profile.apply_development_bias(soft)
	_check(bool(bias_result.get("success", false)) and bool(bias_result.get("applied", false)), "S19 SOFT development bias is admitted through the canonical A3 hook")
	_check(String(bias_result.get("status", "")) == Profile.APPLIED_STATUS, "S19 SOFT bias reports APPLIED_CANONICAL_BIAS")
	_check(String(bias_result.get("bias_hash", "")).length() == 64, "S19 canonical bias carries a sealed provenance hash")
	# Rendering through a visual profile is still presentation-only and cannot
	# mutate a running canonical state.
	var debug: Dictionary = topology_controller.debug_state()
	if debug.population.is_empty():
		_check(false, "S19 organism available for the visual-profile render")
		return
	var state: Dictionary = debug.population[0].state
	var descriptor: Dictionary = Descriptor.compile(state.development.modules, String(state.individual_id), state.position_mm)
	var hash_before := String(topology_controller.get_snapshot().canonical_state_hash)
	var counts := {}
	for mode in ["FREE", "SOFT", "NMS_LIKE"]:
		var visual: Dictionary = Profile.visual_profile(Profile.preset(mode))
		var realized: Dictionary = Realizer.realize(descriptor, visual)
		counts[mode] = int(realized.primitive_count)
	_check(int(counts["FREE"]) == int(counts["SOFT"]) and int(counts["FREE"]) == int(counts["NMS_LIKE"]), "S19 visual profiles preserve morphology coverage")
	_check(String(topology_controller.get_snapshot().canonical_state_hash) == hash_before, "S19 visual realization leaves canonical_state_hash unchanged")
	# And the bias modes are executable controller inputs, not workbench-only
	# stubs. A short run must remain canonical-valid.
	for mode in ["SOFT", "EARTH_LIKE", "NMS_LIKE"]:
		var biased_manifest := _wc_manifest(4)
		biased_manifest.mode = "LAB"
		biased_manifest.environment.zones[0].water_mg = WATER_STOCK_MG
		biased_manifest.organization_profile = mode
		var ctl := Controller.new()
		_check(bool(ctl.initialize(biased_manifest, {}).get("success", false)), "S19 %s controller initializes with canonical bias" % mode)
		_check(bool(ctl.run(4).get("success", false)), "S19 %s controller executes canonical biased ticks" % mode)

# --- S20: batch of 3 seeds ---------------------------------------------------------------

func _scenario_batch(state: Dictionary) -> void:
	var runner := Batch.new()
	# Batch manifests must be self-contained: inline the registry-referenced
	# variant founder genome (genome instead of biological_hash reference).
	var base: Dictionary = (state.manifest as Dictionary).duplicate(true)
	for founder in base.founders:
		if founder.genome == null:
			founder.genome = (state.registry as Dictionary)[founder.biological_hash]
			founder.biological_hash = null
	var plan: Dictionary = Batch.seeds_1_to_n(base, 3)
	plan.horizon_ticks = 8
	var batch: Dictionary = runner.run_batch(plan)
	_check(bool(batch.get("success", false)), "S20 batch of 3 seeds runs")
	var results: Array = batch.results
	_check(results.size() == 3, "S20 ALL 3 seed results reported (no cherry-picking)")
	var completed := 0
	var hashes := []
	for result in results:
		if String(result.status) == "COMPLETED":
			completed += 1
		hashes.append(String(result.final_state_hash))
	_check(completed == 3, "S20 all batch results COMPLETED")
	_check(not String(batch.report_hash).is_empty(), "S20 batch report carries a canonical report hash")
	var report: String = runner.build_report(results)
	_check(not report.is_empty(), "S20 canonical report text produced")

# --- S21: WORLD-COMPAT handoff + damage ---------------------------------------------------

func _wc_manifest(horizon: int) -> Dictionary:
	var founder := Genome.create({
		"schema": P.SCHEMA, "entry": "r1", "max_age": 64, "max_depth": 2,
		"rules": [P.rule("r1", [
			P.action("extend", "support", [0, 100, 0], 10),
			P.action("differentiate", "collector", [0, 60, 0], 4, 20000),
		])],
	}, "founder-p13")
	return {
		"schema": Manifest.SCHEMA,
		"experiment_id": "eco-polygon/exp-p13-wc",
		"seed": 777,
		"horizon_ticks": horizon,
		"founders": [{"founder_id": "founder/a", "biological_hash": null, "genome": founder}],
		"environment": {
			"spatial": {"origin_mm": [0, 0, 0], "cell_size_mm": 1000, "width": 1, "depth": 1},
			"zones": [{"id": "zone/wet", "water_mg": 0, "light": 700, "temperature": 500, "nutrient_mg": 0, "organic_mg": 0}],
		},
		"placement": {"entries": [{"founder_ref": "founder/a", "zone_id": "zone/wet", "position_mm": [500, 0, 500]}]},
		"mutation": {"operator": "small", "mutations_enabled": true},
		"organization_profile": "FREE",
		"feedback": {"enabled": true, "decomposition_enabled": true},
		"metrics": {"requested": ["population"]},
		"checkpoint": {"interval_ticks": 16},
		"mode": "WORLD_COMPAT",
	}

func _region(owner: String, epoch: int, lifecycle: String) -> Dictionary:
	return Region.create(
		"region/a", "u", "i", "surface",
		"octree", 7, {"kind": "GLOBAL_SPACE", "partition_prefix": "", "chunk_ids": []},
		owner, epoch, lifecycle, 10
	)

func _water_batch() -> Dictionary:
	return MatterBatch.create({
		"batch_id": "batch/p13-water",
		"container_id": "container/p13",
		"source_body_id": "body/moon",
		"source_operation_id": "operation/p13",
		"total_mass_kg": float(WATER_STOCK_MG) / 1000000.0,
		"bulk_volume_m3": 0.000001,
		"composition": Composition.create([{"material_id": "matter/water-ice", "mass_fraction": 1.0}]),
		"temperature_k": 273.15,
	})

func _scenario_world_compat() -> void:
	var manifest := _wc_manifest(32)
	var adapter := Adapter.new()
	var configured: Dictionary = adapter.configure(manifest, {
		"region": _region("node/a", 1, "ACTIVE"),
		"entity_id": "organism/p13",
		"owner_id": "node/a",
		"catalog": Catalog.default_catalog(),
		"map_id": "eco-map/p13",
		"mapping_entries": [{"material_id": "matter/water-ice", "resource": "water_mg"}],
	})
	_check(bool(configured.get("success", false)), "S21 world adapter configured over an ACTIVE region: " + str(configured.get("error", "")))
	var wc := Controller.new()
	wc.attach_world_authority(adapter)
	var init_result: Dictionary = wc.initialize(manifest, {})
	_check(bool(init_result.get("success", false)), "S21 WORLD_COMPAT controller initializes (fail-closed deps satisfied)")
	var water := _water_batch()
	_check(bool(adapter.add_batch(water, String(water.checksum)).get("success", false)), "S21 explicit matter batch admitted")
	_check(bool(adapter.apply_environment(wc).get("success", false)), "S21 world stocks applied through the canonical owner-write bridge")
	_check(bool(wc.run(4).get("success", false)), "S21 live ecology ticks under world authority")
	var checkpoint: Dictionary = wc.serialize_state()
	_check(bool(checkpoint.get("success", false)), "S21 checkpoint identity through the seam (controller serialize_state)")
	# Handoff: ACTIVE A -> WARM target -> machine -> COMMITTED -> new ACTIVE B.
	var prepared: Dictionary = adapter.prepare_region_handoff(_region("node/b", 2, "WARM"), int(adapter.cursor().clock) + 100)
	_check(bool(prepared.get("success", false)), "S21 WARM handoff ticket prepared")
	if not bool(prepared.get("success", false)):
		return
	var machine := Machine.new()
	_check(bool(machine.setup(prepared.ticket).get("success", false)), "S21 handoff state machine setup")
	var tick := int(prepared.ticket.created_at_tick) + 1
	for state in ["PREPARING", "FROZEN", "SNAPSHOT_READY", "TARGET_PREPARED", "COMMITTED"]:
		var context := {"tick": tick}
		if state == "SNAPSHOT_READY":
			context["snapshot_id"] = "p13." + String(checkpoint.get("state_hash", "")).substr(0, 16)
			context["snapshot_hash"] = String(checkpoint.get("state_hash", ""))
		var transition: Dictionary = machine.transition(state, context)
		_check(bool(transition.get("success", false)), "S21 handoff transition " + state)
		tick += 1
	var commit: Dictionary = adapter.commit_region_handoff(_region("node/b", 2, "ACTIVE"), machine.ticket)
	_check(bool(commit.get("success", false)), "S21 committed handoff admitted; authority switched to the new owner")
	if not bool(commit.get("success", false)):
		return
	_check(String(adapter.cursor().owner_id) == "node/b" and int(adapter.cursor().owner_epoch) == 2, "S21 cursor moved to the new owner/epoch")
	_check(bool(wc.run(2).get("success", false)), "S21 ecology continues after the seam handoff")
	# Damage overlay through the adapter.
	var debug: Dictionary = wc.debug_state()
	if debug.population.is_empty():
		_check(false, "S21 organism present for damage")
		return
	var individual_id := String(debug.population[0].state.individual_id)
	var modules: Array = debug.population[0].state.development.modules
	if modules.size() < 3:
		_check(false, "S21 body grew enough modules for damage (modules=%d)" % modules.size())
		return
	var topology_before := Body.topology_signature(modules)
	var parts := [
		Part.create("part/support", "item/support", "BIO_PROXY", "support", 1.0, [0.0, 0.5, 0.0]),
		Part.create("part/leaf", "item/leaf", "BIO_PROXY", "collector", 0.2, [0.25, 1.25, 0.0]),
	]
	var source_snapshot := ConstructSnapshot.create("construct/p13", "item/p13-root", 1, "OPERATIONAL", parts, [], {})
	var part_to_module := {"part/support": String(modules[1].id), "part/leaf": String(modules[2].id)}
	var request := DamageRequest.create("damage/p13", "construct/p13", source_snapshot.checksum, "part/leaf", [], [], {"part/support": "DESTROYED"})
	var target_snapshot := ConstructSnapshot.create("construct/p13", "item/p13-root", 2, "DAMAGED", [parts[0]], [], {})
	var repair := RepairPlan.create("repair/p13", "damage/p13", target_snapshot, [], [], [], [], request.checksum)
	var record := DamageRecord.create("damage/p13", request.checksum, "d".repeat(64), repair, [], 5)
	_check(bool(DamageRecord.validate(record).get("success", false)), "S21 trusted DamageRecord fixture valid")
	var registered: Dictionary = adapter.register_damage(wc, individual_id, request, record, source_snapshot, part_to_module, String(record.checksum))
	_check(bool(registered.get("success", false)), "S21 damage registered through the world adapter: " + str(registered.get("error", "")))
	if not bool(registered.get("success", false)):
		return
	var applied: Dictionary = adapter.apply_damage(individual_id)
	_check(bool(applied.get("success", false)), "S21 damage applied to the overlay")
	if bool(applied.get("success", false)):
		_check(int(applied.overlay.revision) == 1, "S21 overlay revision advanced exactly once")
		var effective: Dictionary = adapter.effective_function(individual_id)
		_check(int(effective.active_module_count) < modules.size(), "S21 effective active modules reduced after damage")
	var modules_after: Array = wc.debug_state().population[0].state.development.modules
	_check(Body.topology_signature(modules_after) == topology_before, "S21 historical BodyGraph topology unchanged by the overlay")
	var inspected: Dictionary = Inspector.compile(wc, individual_id, adapter)
	_check(bool(inspected.get("success", false)), "S21 inspector compiles with the world adapter")
	if bool(inspected.get("success", false)):
		var damage: Dictionary = inspected.view.damage
		_check(bool(damage.get("overlay_present", false)) and String(damage.historical.topology_signature) == topology_before, "S21 inspector shows historical/overlay/effective layers with immutable topology")

# --- driver ------------------------------------------------------------------------------

func _run() -> void:
	var state := _scenario_setup()
	if failures.is_empty():
		_scenario_variant(state)
	if failures.is_empty():
		_scenario_placement(state)
	if failures.is_empty():
		_scenario_run_and_observe(state)
	_scenario_death_decomposition()
	var topology_controller := _scenario_realizer_inspector()
	if failures.is_empty():
		_scenario_branches(state)
	_scenario_profiles(topology_controller)
	if failures.is_empty():
		_scenario_batch(state)
	_scenario_world_compat()
	_finish()

func _finish() -> void:
	print("EVO_ARCH2_A10_5_FINAL_E2E_P13 checks=%d failed=%d" % [checks, failures.size()])
	if failures.is_empty():
		print("EVO_ARCH2_A10_5_FINAL_E2E_P13 PASS")
		quit(0)
	else:
		for failure in failures:
			print("A10_5_P13_E2E_FAILURE " + failure)
		quit(1)
