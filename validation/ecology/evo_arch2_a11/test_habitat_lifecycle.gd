extends SceneTree

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Body = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const Program = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const Genome = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const Session = preload("res://scripts/ecology/habitat/persistent_habitat_session_v1.gd")
const Preset = preload("res://scripts/ecology/habitat/habitat_preset_v1.gd")
const Manifest = preload("res://scripts/ecology/workbench/experiment_manifest_v1.gd")
const Protocol = preload("res://scripts/research/ecology/v2/observatory_protocol_v1.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("A11_LIFE_FAIL " + message)

func _run() -> void:
	_evolution()
	_starvation()
	_long_bounded()
	print("EVO_ARCH2_A11_LIFECYCLE checks=%d failed=%d" % [checks, failures.size()])
	print("EVO_ARCH2_A11_LIFECYCLE " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func _evolution() -> void:
	var session := Session.new()
	check(session.start(Preset.create()).success, "FREE evolving habitat starts")
	var initial: Dictionary = session.controller.debug_state()
	var initial_account: Dictionary = initial.runtime.accounting.initial.duplicate(true)
	var population0: int = initial.population.size()
	var ticks := 0
	while ticks < 40 and (ticks < 8 or session.controller.debug_state().population.size() == population0):
		var stepped: Dictionary = session.controller.step()
		if not stepped.success:
			check(false, "evolution canonical step: " + str(stepped))
			return
		ticks += 1
	var state: Dictionary = session.controller.debug_state()
	check(state.population.size() > population0, "real reproduction, not injected child")
	check(int(state.field.cells[0].stocks.water_mg) < int(initial.field.cells[0].stocks.water_mg), "resource consumption in same canonical field")
	check(state.population[0].state.development.modules.size() > initial.population[0].state.development.modules.size(), "growth creates canonical body modules")
	var genomes := {}
	for entry in state.population:
		genomes[String(entry.state.individual_id)] = Genome.biological_hash(entry.blueprint.genome)
	var inherited := 0
	for entry in state.population:
		if String(entry.state.origin_kind) != "PARENT_TRANSFER": continue
		var parent_id := String(entry.state.origin_receipt.parent_id)
		var receipt: Dictionary = entry.state.get("mutation_receipt", {})
		if not receipt.is_empty() and String(receipt.receipt.child_genome_hash) == String(genomes[String(entry.state.individual_id)]) \
				and genomes.has(parent_id) and genomes[parent_id] != genomes[String(entry.state.individual_id)]:
			inherited += 1
	check(inherited > 0, "canonical replay-proven mutation really inherited")
	check(state.runtime.accounting.initial == initial_account, "birth preserves genesis account")
	var saved: Dictionary = session.export_bundle()
	check(saved.success, "evolved lineage fits explicit checkpoint transport domain")
	if saved.success:
		var other := Session.new()
		check(other.restore_bundle(saved.text, saved.sha256).success, "evolved lineage restores without regeneration")
		check(other.controller.get_snapshot().canonical_state_hash == session.controller.get_snapshot().canonical_state_hash, "evolution checkpoint exact")

## Canonical starvation fixture. Built as one explicit literal (the same
## construction class as the accepted A10.5 S11 death scenario) instead of
## partially mutating HabitatPreset.create(): a field-style assignment such as
## `manifest.genesis = {...}` inserts a StringName key, `C.keys()` still accepts
## it, but canonical_value_v1.encode() rejects any non-String key. The manifest
## then validates as NONCANONICAL_MANIFEST and start() fails closed long before
## any starvation semantics are exercised. Literal String keys keep the fixture
## canonically encodable; the acceptance predicate is unchanged.
func _starvation() -> void:
	var endowment := Body.stock(0)
	endowment.material_mg = 1000
	var manifest := {
		"schema": Manifest.SCHEMA,
		"experiment_id": "eco/a11/starvation-death/v1",
		"seed": 20260912,
		"horizon_ticks": 16,
		"founders": [{"founder_id": "founder/a", "biological_hash": null, "genome": Protocol.ancestor()}],
		"environment": {
			"spatial": {"origin_mm": [0, 0, 0], "cell_size_mm": 1000, "width": 1, "depth": 1},
			"zones": [{"id": "wet", "water_mg": 0, "light": 0, "temperature": 100, "nutrient_mg": 0, "organic_mg": 0}],
		},
		"placement": {"entries": [{"founder_ref": "founder/a", "zone_id": "wet", "position_mm": [500, 0, 500]}]},
		"mutation": {"operator": "small", "mutations_enabled": false},
		"organization_profile": "FREE",
		"feedback": {"enabled": true, "decomposition_enabled": true},
		"metrics": {"requested": ["population", "resources", "lineage"]},
		"checkpoint": {"interval_ticks": 16},
		"mode": "LAB",
		"genesis": {"founder_endowment": endowment},
	}
	check(Manifest.validate(manifest).is_empty(), "canonical starvation manifest: " + Manifest.validate(manifest))
	var session := Session.new()
	# The primary failure must stay visible: without this guard the secondary
	# `debug_state` call on a Nil controller masked the real start() error.
	var started: Dictionary = session.start(manifest)
	check(bool(started.get("success", false)), "explicit zero-water/energy founder input: " + str(started))
	if not bool(started.get("success", false)):
		return
	var limit := int(session.controller.debug_state().population[0].blueprint.life_history.survival.starvation_limit_ticks)
	check(session.controller.run(limit).success, "canonical starvation horizon reached")
	var state: Dictionary = session.controller.debug_state()
	check(not state.population[0].state.alive, "real starvation death")
	check(state.feedback.frame.corpses.size() == 1, "one canonical corpse")
	check(int(state.feedback.frame.returned.organic_mg) > 0 and int(state.feedback.frame.mineralized_mg) > 0, "corpse return and mineralization on same field")
	var saved: Dictionary = session.export_bundle()
	check(saved.success, "dead organism and feedback checkpoint")
	if saved.success:
		var restored := Session.new()
		check(restored.restore_bundle(saved.text, saved.sha256).success, "death/feedback restore")
		check(restored.controller.debug_state().feedback == state.feedback, "no repeated corpse return on restore")

func _long_bounded() -> void:
	# A declared non-reproductive genotype isolates persistent long-duration
	# execution from population scaling. Evolution is proven separately above;
	# this is NOT a claim of 256-tick unconstrained multi-generation scaling.
	var manifest := Preset.create(11, 256)
	var genome := Genome.create({"schema": Program.SCHEMA, "entry": "r1", "max_age": 64, "max_depth": 2,
		"rules": [Program.rule("r1", [Program.action("extend", "support", [0, 100, 0], 10),
			Program.action("differentiate", "collector", [0, 60, 0], 4, 20000)])]}, "long-lived-a11")
	check(not genome.is_empty(), "bounded long-run genotype validates canonically")
	manifest.founders = [{"founder_id": "founder/a", "biological_hash": null, "genome": genome}]
	manifest.placement.entries = [{"founder_ref": "founder/a", "zone_id": "wet", "position_mm": [500, 0, 500]}]
	var original := Session.new()
	check(original.start(manifest).success, "bounded long-running habitat starts")
	check(original.controller.run(128).success, "128 canonical ticks with no new solver/cap changes")
	var saved: Dictionary = original.export_bundle()
	check(saved.success, "long-run midpoint checkpoint")
	if not saved.success: return
	var resumed := Session.new()
	check(resumed.restore_bundle(saved.text, saved.sha256).success, "long-run midpoint restored")
	check(original.controller.run(128).success, "uninterrupted trajectory reaches 256")
	check(resumed.controller.run(128).success, "resumed trajectory reaches 256")
	check(original.controller.get_snapshot().canonical_state_hash == resumed.controller.get_snapshot().canonical_state_hash, "256-tick continuation equality")
	check(int(resumed.controller.get_metrics().alive) == 1, "organism still alive at declared horizon")
	check(int(resumed.controller.get_metrics().population_size) == 1, "non-reproductive genotype does not hide population culling")
	var before: String = resumed.controller.get_snapshot().canonical_state_hash
	var past: Dictionary = resumed.controller.step()
	check(not past.success and past.error == "CONTROLLER_HORIZON", "declared horizon fails closed")
	check(resumed.controller.get_snapshot().canonical_state_hash == before, "horizon rejection leaves state intact")
