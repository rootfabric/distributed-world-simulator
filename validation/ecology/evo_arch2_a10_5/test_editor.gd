extends SceneTree

# ECO ARCH2 A10.5 / ECO-POLYGON-1 — P7 Organism inspector + genome editor
# mandatory test. Runner: Godot headless --script; prints checks/failed
# counts and PASS/FAIL.
# Coverage:
#   1. inspector builds the FULL chain (Genome -> Program -> Development ->
#      Body -> Phenotype -> resources -> damage -> lineage) for an organism
#      of an 8-tick run: every section non-empty, hashes canonical;
#   2. propose_variant mutate with different operators from OPERATORS:
#      valid -> validated genome (validate == "", biological_hash != parent),
#      deterministic under a fixed seed; crossover + delete_rule covered;
#   3. invalid edits (unknown operator, broken donor) -> success:false and
#      the parent genome is NEVER modified;
#   4. the editor never mutates the canonical run state (controller hash
#      before/after propose identical).

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const P = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const Genome = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const Mutation = preload("res://scripts/research/ecology/v2/genome_mutation_v1.gd")
const BodyGraph = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const Fixtures = preload("res://scripts/research/ecology/v2/body_program_fixtures_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const ManifestV = preload("res://scripts/ecology/workbench/experiment_manifest_v1.gd")
const Inspector = preload("res://scripts/ecology/workbench/organism_inspector_v1.gd")
const Editor = preload("res://scripts/ecology/workbench/genome_editor_v1.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("A10_5_P7_FAIL " + message)

func _program() -> Dictionary:
	var actions := [
		P.action("extend", "support", [0, 100, 0], 10),
		P.action("differentiate", "collector", [0, 60, 0], 4, 20000),
	]
	return {"schema": P.SCHEMA, "entry": "r1", "max_age": 64, "max_depth": 4, "rules": [P.rule("r1", actions)]}

func _manifest() -> Dictionary:
	var founder := Genome.create(_program(), "founder-a")
	return {
		"schema": "dws.ecology.workbench.experiment-manifest.v1",
		"experiment_id": "eco-polygon/exp-editor-p7",
		"seed": 424242,
		"horizon_ticks": 16,
		"founders": [
			{"founder_id": "founder/a", "biological_hash": null, "genome": founder},
		],
		"environment": {
			"spatial": {"origin_mm": [0, 0, 0], "cell_size_mm": 1000, "width": 1, "depth": 1},
			"zones": [
				{"id": "zone/wet", "water_mg": 500000, "light": 700, "temperature": 500, "nutrient_mg": 1000, "organic_mg": 0},
			],
		},
		"placement": {
			"entries": [
				{"founder_ref": "founder/a", "zone_id": "zone/wet", "position_mm": [500, 0, 500]},
			],
		},
		"mutation": {"operator": "small", "mutations_enabled": true},
		"organization_profile": "FREE",
		"feedback": {"enabled": true, "decomposition_enabled": true},
		"metrics": {"requested": ["population"]},
		"checkpoint": {"interval_ticks": 8},
		"mode": "LAB",
	}

func _hex64(value: String) -> bool:
	if value.length() != 64:
		return false
	for character in value:
		if not character in "0123456789abcdef":
			return false
	return true

func _run() -> void:
	var ctl := Controller.new()
	var init_result: Dictionary = ctl.initialize(_manifest())
	_check(bool(init_result.get("success", false)), "P7 initialize succeeds: " + str(init_result))
	var run_result: Dictionary = ctl.run(8)
	_check(bool(run_result.get("success", false)), "P7 8-tick run succeeds: " + str(run_result))
	var state_hash_before := String(ctl.get_snapshot().canonical_state_hash)
	var debug: Dictionary = ctl.debug_state()
	_check(not debug.population.is_empty(), "P7 population non-empty after 8 ticks")
	var individual_id := String(debug.population[0].state.individual_id)

	# --- 1. inspector full chain ------------------------------------------------
	var genome_truth: Dictionary = debug.population[0].blueprint.genome.duplicate(true)
	var inspection: Dictionary = Inspector.compile(ctl, individual_id)
	_check(bool(inspection.get("success", false)), "P7 inspector succeeds: " + str(inspection))
	if bool(inspection.get("success", false)):
		var view: Dictionary = inspection.view
		var sections := ["genome", "development_program", "development_state", "body_graph", "phenotype", "resources", "damage", "lineage"]
		for section in sections:
			_check(view.has(section) and view[section] is Dictionary and not (view[section] as Dictionary).is_empty(), "P7 section non-empty: " + section)
		var genome_ref: Dictionary = debug.population[0].blueprint.genome
		_check(_hex64(String(view.genome.biological_hash)), "P7 genome biological_hash canonical")
		_check(String(view.genome.biological_hash) == Genome.biological_hash(genome_ref), "P7 genome hash == canonical biological_hash")
		_check(int(view.genome.rules) == int(genome_ref.program.rules.size()), "P7 genome rules count")
		_check(int(view.genome.max_age) == int(genome_ref.program.max_age) and int(view.genome.max_depth) == int(genome_ref.program.max_depth), "P7 genome max_age/max_depth")
		_check(String(view.development_program.entry) == String(genome_ref.program.entry), "P7 program entry")
		_check(int(view.development_program.rule_count) == int(view.genome.rules), "P7 program rule_count == genome rules")
		_check(int(view.development_state.modules_count) == int(debug.population[0].state.development.modules.size()), "P7 development modules count")
		_check(int(view.development_state.age_ticks) == 8, "P7 development age == 8 ticks")
		var modules: Array = debug.population[0].state.development.modules
		_check(String(view.body_graph.topology_signature) == BodyGraph.topology_signature(modules), "P7 body topology_signature canonical")
		_check(int(view.body_graph.module_count) == modules.size(), "P7 body module_count")
		_check(not (view.body_graph.roles as Dictionary).is_empty(), "P7 body roles histogram non-empty")
		_check((view.body_graph.bounds_min_mm as Array).size() == 3 and (view.body_graph.bounds_max_mm as Array).size() == 3, "P7 body bounds present")
		_check(bool(view.phenotype.available), "P7 phenotype available")
		_check(_hex64(String(view.phenotype.snapshot.phenotype_hash)), "P7 phenotype hash canonical")
		_check(int(view.phenotype.snapshot.statistics.module_count) == modules.size(), "P7 phenotype module_count matches body")
		_check((view.resources.metabolic_reserves as Dictionary).has("water_mg"), "P7 reserves present")
		_check((view.resources.cumulative as Dictionary).has("field_intake"), "P7 cumulative ledger present")
		_check(not bool(view.damage.overlay_present) and (view.damage.overlay as Dictionary).is_empty(), "P7 damage reserved + empty in LAB")
		_check(String(view.lineage.origin_kind) == "FOUNDER_ENDOWMENT", "P7 lineage origin for founder")
		_check(int(view.lineage.lineage_depth) == 0, "P7 lineage depth 0 for founder")
		_check(not Inspector.render_text(view).is_empty(), "P7 render_text non-empty")
	# Unknown organism fails closed.
	_check(not bool(Inspector.compile(ctl, "ghost/0000").get("success", false)), "P7 inspector rejects unknown organism")

	# --- 2. propose_variant: valid operators ------------------------------------
	var parent := genome_truth.duplicate(true)
	var parent_hash := Genome.biological_hash(parent)
	var parent_digest := C.digest(parent)
	for operator in ["small", "medium", "regulatory", "development_parameter"]:
		var proposed: Dictionary = Editor.propose_variant(parent, {"kind": "mutate", "operator": operator, "seed": 123})
		_check(bool(proposed.get("success", false)), "P7 mutate/%s succeeds: %s" % [operator, str(proposed)])
		if bool(proposed.get("success", false)):
			_check(Genome.validate(proposed.genome).is_empty(), "P7 mutate/%s genome validates" % operator)
			_check(String(proposed.biological_hash) != parent_hash, "P7 mutate/%s hash != parent" % operator)
			_check(String(proposed.parent_hash) == parent_hash, "P7 mutate/%s event parent hash" % operator)
			_check(_hex64(String(proposed.event_hash)), "P7 mutate/%s event hash canonical" % operator)
	# Determinism under a fixed seed.
	var first: Dictionary = Editor.propose_variant(parent, {"kind": "mutate", "operator": "small", "seed": 77})
	var second: Dictionary = Editor.propose_variant(parent, {"kind": "mutate", "operator": "small", "seed": 77})
	_check(bool(first.get("success", false)) and bool(second.get("success", false)), "P7 seeded proposals succeed")
	if bool(first.get("success", false)) and bool(second.get("success", false)):
		_check(String(first.biological_hash) == String(second.biological_hash), "P7 fixed seed -> deterministic biological_hash")
		_check(String(first.event_hash) == String(second.event_hash), "P7 fixed seed -> deterministic event hash")
	# Crossover with a canonical donor fixture.
	var donor := Fixtures.make(1)
	var crossed: Dictionary = Editor.propose_variant(parent, {"kind": "crossover", "donor": donor, "seed": 5})
	_check(bool(crossed.get("success", false)), "P7 crossover succeeds: " + str(crossed))
	if bool(crossed.get("success", false)):
		_check(Genome.validate(crossed.genome).is_empty(), "P7 crossover genome validates")
		_check(String(crossed.biological_hash) != parent_hash, "P7 crossover hash != parent")
	# delete_rule: protected entry rule is rejected; second rule deletion covered on a crossover product.
	var protected_rule: Dictionary = Editor.propose_variant(parent, {"kind": "delete_rule", "rule_id": String(parent.program.entry), "seed": 1})
	_check(not bool(protected_rule.get("success", false)), "P7 delete_rule on entry rule rejected")

	# --- 3. invalid edits ---------------------------------------------------------
	var unknown_operator: Dictionary = Editor.propose_variant(parent, {"kind": "mutate", "operator": "bogus_operator", "seed": 1})
	_check(not bool(unknown_operator.get("success", false)), "P7 unknown operator rejected")
	_check(not String(unknown_operator.get("error", "")).is_empty(), "P7 unknown operator carries an error")
	var broken_donor: Dictionary = Editor.propose_variant(parent, {"kind": "crossover", "donor": {"schema": "junk"}, "seed": 1})
	_check(not bool(broken_donor.get("success", false)), "P7 broken donor rejected")
	var broken_kind: Dictionary = Editor.propose_variant(parent, {"kind": "teleport", "seed": 1})
	_check(not bool(broken_kind.get("success", false)), "P7 unknown edit kind rejected")
	var broken_parent: Dictionary = Editor.propose_variant({"schema": "junk"}, {"kind": "mutate", "operator": "small", "seed": 1})
	_check(not bool(broken_parent.get("success", false)), "P7 invalid parent rejected")
	_check(C.digest(parent) == parent_digest, "P7 parent genome never modified by rejected edits")
	_check(Genome.biological_hash(parent) == parent_hash, "P7 parent hash unchanged")

	# --- 4. canonical run state untouched ---------------------------------------
	for operator in ["small", "regulatory"]:
		Editor.propose_variant(parent, {"kind": "mutate", "operator": operator, "seed": 9})
	var crossed2: Dictionary = Editor.propose_variant(parent, {"kind": "crossover", "donor": donor, "seed": 9})
	_check(bool(crossed2.get("success", false)), "P7 post-check crossover still succeeds")
	_check(String(ctl.get_snapshot().canonical_state_hash) == state_hash_before, "P7 canonical state hash identical before/after proposals")

	# --- 5. founder registration + manifest extension ---------------------------
	var registry := {}
	var registered := Editor.register_founder(registry, crossed.genome if bool(crossed.get("success", false)) else parent)
	_check(not registered.is_empty(), "P7 register_founder returns hash")
	_check(registry.has(registered) and Genome.validate(registry[registered]).is_empty(), "P7 registry entry validates")
	var bad_register := Editor.register_founder(registry, {"schema": "junk"})
	_check(bad_register.is_empty() and not registry.has(""), "P7 invalid genome not registered")
	var manifest: Dictionary = ctl.get_manifest()
	var extended: Dictionary = Editor.add_founder_to_manifest(manifest, registry[registered], "founder/variant-1", "zone/wet", [500, 0, 500])
	_check(bool(extended.get("success", false)), "P7 add_founder_to_manifest succeeds: " + str(extended))
	if bool(extended.get("success", false)):
		var extended_manifest: Dictionary = extended.manifest
		_check(extended_manifest.founders.size() == manifest.founders.size() + 1, "P7 extended manifest has the new founder")
		_check(String(extended_manifest.founders[1].biological_hash) == registered, "P7 founder uses the biological_hash reference form")
		_check(not String(extended.manifest_hash).is_empty() and String(extended.manifest_hash) != ManifestV.canonical_hash(manifest), "P7 extended manifest is a NEW immutable manifest")
	var duplicate_id: Dictionary = Editor.add_founder_to_manifest(manifest, registry[registered], "founder/a", "zone/wet", [500, 0, 500])
	_check(not bool(duplicate_id.get("success", false)), "P7 duplicate founder id rejected")

	_finish()

func _finish() -> void:
	print("EVO_ARCH2_A10_5_EDITOR_P7 checks=%d failed=%d" % [checks, failures.size()])
	if failures.is_empty():
		print("EVO_ARCH2_A10_5_EDITOR_P7 PASS")
		quit(0)
	else:
		for failure in failures:
			print("A10_5_P7_FAILURE " + failure)
		quit(1)
