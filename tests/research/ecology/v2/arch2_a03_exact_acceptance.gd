extends SceneTree
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const E = preload("res://scripts/research/ecology/v2/environment_fixture_v1.gd")
const F = preload("res://scripts/research/ecology/v2/body_program_fixtures_v1.gd")
const G = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const H = preload("res://scripts/research/ecology/v2/phenotype_snapshot_v1.gd")
const K = preload("res://scripts/research/ecology/v2/development_interpreter_v1.gd")
const M = preload("res://scripts/research/ecology/v2/genome_mutation_v1.gd")
const S = preload("res://scripts/research/ecology/v2/organism_state_v1.gd")
const Model = preload("res://scripts/labs/ecology/evo_morphology_lab_v2_model.gd")
const Renderer = preload("res://scripts/labs/ecology/evo_morphology_lab_v2_renderer.gd")
var passed := 0
var failed := 0

func _init() -> void:
	_contract_and_family_tests()
	_slice_restart_and_budget_tests()
	_mutation_tests()
	_lab_tests()
	_reviewer_repair_tests()
	print("EVO_ARCH2_A03_EXACT assertions=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(value: bool, name: String) -> void:
	if value: passed += 1
	else: failed += 1; push_error("FAIL:" + name)

func _run(g: Dictionary, ticks: int = 8, slice_ops: int = 4096) -> Dictionary:
	var s := S.create(g)
	var env := E.create()
	for _tick in ticks:
		var opened := K.begin_tick(s, g, env, B.stock(), s.grant_seq + 1)
		if not opened.success: return {}
		s = opened.state
		var done := false
		for _slice in 4096:
			var r := K.advance(s, g, slice_ops)
			if not r.success: return {}
			s = r.state
			if r.status == "BUDGET_BLOCKED": return {}
			if r.status == "TICK_COMPLETE": done = true; break
			if r.status != "RUNNING": return {}
		if not done: return {}
	return s

func _contract_and_family_tests() -> void:
	var topology := {}
	for i in F.NAMES.size():
		var g := F.make(i)
		_check(not g.is_empty(), "family_genome_%d" % i)
		_check(G.validate(g).is_empty(), "family_validate_%d" % i)
		var roundtrip := G.deserialize(G.serialize(g))
		_check(not roundtrip.is_empty() and G.biological_hash(roundtrip) == G.biological_hash(g), "genome_roundtrip_%d" % i)
		var s := _run(g)
		_check(not s.is_empty() and S.validate(s, g).is_empty(), "family_state_%d" % i)
		var p := H.compile(s, g)
		_check(not p.is_empty() and p.representation_hash == C.digest(p.representation), "phenotype_source_%d" % i)
		topology[p.topology_hash] = true
		_check(p.statistics.module_count == s.modules.size(), "module_count_%d" % i)
		if i == 0: _check(p.statistics.branching_nodes > 0, "recursive_branching")
		if i == 2: _check(int(p.module_roles.get("attachment", 0)) > 0 and int(p.module_roles.get("absorber", 0)) > 0, "spreading_reanchor")
		if i == 3: _check(int(p.module_roles.get("attachment", 0)) >= 2, "radial_colony_anchors")
		if i == 4: _check(int(p.module_roles.get("attachment", 0)) > 0, "supported_climbing")
		if i == 5: _check(int(p.module_roles.get("collector", 0)) >= 2, "planar_collectors")
	_check(topology.size() >= 4, "body_family_diversity")

func _slice_restart_and_budget_tests() -> void:
	var g := F.make(0)
	var fast := _run(g, 6, 4096)
	var slow := _run(g, 6, 1)
	_check(not fast.is_empty() and C.digest(fast) == C.digest(slow), "slice_invariance")
	var text := S.serialize(fast, g)
	var restored := S.deserialize(text)
	_check(not restored.is_empty(), "state_deserialize")
	_check(C.digest(restored.state) == C.digest(fast), "restart_state_exact")
	_check(G.biological_hash(restored.genome) == G.biological_hash(g), "restart_genome_exact")
	_check(S.validate(fast, g).is_empty(), "resource_conservation_validator")
	var budget_genome := F.make(2)
	var tiny := S.create(budget_genome)
	tiny.limits.modules = 1
	var opened := K.begin_tick(tiny, budget_genome, E.create(), B.stock(), 1)
	var block := K.advance(opened.state, budget_genome, 4096)
	_check(block.success and block.status == "BUDGET_BLOCKED" and block.reason == "MODULE_CAPACITY", "explicit_budget_block")
	_check(not block.state.frame.is_empty() and block.state.tick == tiny.tick, "blocked_tick_remains_open")
	var resized := K.resize_capacity(block.state, budget_genome, 64, 32)
	_check(resized.success, "capacity_resume_contract")

func _mutation_tests() -> void:
	var parent := F.make(0)
	var parent_hash := G.biological_hash(parent)
	var parent_topology: String = String(H.compile(_run(parent), parent).topology_hash)
	var small_valid := 0
	for seed in 100:
		var r := M.mutate(parent, seed, "small")
		if r.success and G.validate(r.genome).is_empty(): small_valid += 1
	_check(small_valid == 100, "small_mutation_validity")
	var neutral := M.mutate(parent, 7, "none")
	_check(neutral.success and G.biological_hash(neutral.genome) == parent_hash, "neutral_control")
	var structural_valid := 0
	var topology_changed := 0
	for seed in 40:
		var r := M.mutate(parent, 1000 + seed, "insert")
		if not r.success: continue
		structural_valid += 1
		var s := _run(r.genome)
		if not s.is_empty() and H.compile(s, r.genome).topology_hash != parent_topology: topology_changed += 1
	_check(structural_valid > 0, "structural_mutation_valid")
	_check(topology_changed > 0, "structural_topology_change")
	var duplicate := M.mutate(parent, 2026, "duplicate")
	_check(duplicate.success and duplicate.event.detail.activation == "DISABLED_NEUTRAL_MOTIF", "safe_duplication")
	var activated := M.mutate(duplicate.genome, 2027, "activate")
	_check(activated.success, "explicit_activation")
	var donor := F.make(5)
	var cross := M.crossover(parent, donor, 33)
	_check(cross.success and G.validate(cross.genome).is_empty(), "typed_crossover")
	_check(String(cross.event.detail.mode).contains("NOT_SEXUAL_REPRODUCTION"), "crossover_scope_label")

func _lab_tests() -> void:
	var model := Model.new()
	_check(model.reset(0), "lab_reset")
	_check(model.step(4), "lab_step")
	var before := model.hashes()
	var export := model.export_genome()
	_check(not export.is_empty() and model.import_genome(export), "lab_import_export")
	_check(model.hashes().genome == before.genome, "lab_genome_roundtrip")
	var dark := model.environment_preview(650, 50)
	var light := model.environment_preview(650, 700)
	_check(not dark.is_empty() and not light.is_empty() and dark.phenotype_hash != light.phenotype_hash, "environmental_comparison")
	var gallery := model.generate(100, 20260906)
	_check(gallery.accepted >= 60, "generate_100_accepted")
	_check(gallery.topology_signatures > 1, "generate_100_topology_diversity")
	_check(gallery.viability == "NOT_PROVEN_BY_CONTRACT_VALIDITY", "viability_truth_label")
	var mutation := model.mutate("insert", 77)
	_check(mutation.success and model.lineage.size() == 2, "generation_lineage")
	var renderer := Renderer.new()
	var p := model.phenotype(); renderer.set_phenotype(p)
	_check(renderer.snapshot.phenotype_hash == p.phenotype_hash, "renderer_consumes_phenotype")
	_check(not renderer.snapshot.has("genome"), "renderer_no_genome_truth")
	renderer.free()

func _reviewer_repair_tests() -> void:
	# RM-02: BUDGET_BLOCKED is an open tick, never a successful completed tick.
	var model := Model.new()
	_check(model.reset(1), "repair_budget_fixture_reset")
	model.state.limits.modules = 1
	var before_tick: int = model.state.tick
	_check(not model.step(1), "repair_budget_block_returns_false")
	_check(model.last_status == "BUDGET_BLOCKED" and model.last_block_reason == "MODULE_CAPACITY", "repair_budget_status_surface")
	_check(not model.state.frame.is_empty() and model.state.tick == before_tick, "repair_budget_frame_preserved")
	_check(model.resize_capacity(64, 32), "repair_budget_resize")
	_check(model.step(1), "repair_budget_resume_same_tick")
	_check(model.last_status == "TICK_COMPLETE" and model.state.frame.is_empty() and model.state.tick == before_tick + 1, "repair_budget_resume_completed")
	var blocked_preview := model.environment_preview(650, 700, 2, 1, 32)
	_check(blocked_preview.is_empty(), "repair_preview_rejects_incomplete_tick")
	var blocked_gallery := model.generate(10, 9123, 1, 32)
	_check(blocked_gallery.accepted == 0 and blocked_gallery.blocked > 0 and blocked_gallery.accepted + blocked_gallery.rejected == 10, "repair_gallery_rejects_blocked_candidates")

	# RM-03: import creates a new diagnostic ancestry root and clears derived data.
	_check(model.reset(0), "repair_import_fixture_reset")
	var prior_mutation := model.mutate("small", 41)
	var prior_gallery := model.generate(10, 42)
	_check(prior_mutation.success and model.generation == 1 and model.lineage.size() == 2, "repair_import_preexisting_lineage")
	_check(prior_gallery.accepted > 0 and model.gallery.size() > 0, "repair_import_preexisting_gallery")
	var imported := F.make(5)
	var imported_hash := G.biological_hash(imported)
	_check(model.import_genome(G.serialize(imported)), "repair_import_success")
	_check(model.family == Model.IMPORTED_FAMILY and model.generation == 0, "repair_import_identity_reset")
	_check(model.lineage.size() == 1 and model.lineage[0].hash == imported_hash and model.lineage[0].source == "IMPORT", "repair_import_new_root")
	_check(model.gallery.is_empty() and model.hashes().genome == imported_hash, "repair_import_derived_data_cleared")
	var child := model.mutate("small", 43)
	_check(child.success and model.lineage.size() == 2 and child.event.parent_hash == imported_hash, "repair_import_next_child_descends_from_import")
