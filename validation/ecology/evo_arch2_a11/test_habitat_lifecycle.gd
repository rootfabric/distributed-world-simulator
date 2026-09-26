extends SceneTree

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Body = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const Program = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const Genome = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const Session = preload("res://scripts/ecology/habitat/persistent_habitat_session_v1.gd")
const Preset = preload("res://scripts/ecology/habitat/habitat_preset_v1.gd")

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

func _starvation() -> void:
	var manifest := Preset.create(20260912, 16)
	manifest.environment.spatial.width = 1
	manifest.environment.zones = [{"id": "wet", "water_mg": 0, "light": 0, "temperature": 100, "nutrient_mg": 0, "organic_mg": 0}]
	manifest.placement.entries = [{"founder_ref": "founder/a", "zone_id": "wet", "position_mm": [500, 0, 500]}]
	manifest.mutation.mutations_enabled = false
	var endowment := Body.stock(0)
	endowment.material_mg = 1000
	manifest.genesis = {"founder_endowment": endowment}
	var session := Session.new()
	check(session.start(manifest).success, "explicit zero-water/energy founder input")
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
}
