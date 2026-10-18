extends SceneTree
## Fresh independently authored ECO A14.6 R1 resource dependency falsifier.
## No new A4/A5 allocation or biology executable code is installed.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const Ports = preload("res://scripts/research/ecology/v2/organism_environment_ports_v1.gd")
const Graph = preload("res://scripts/research/ecology/v2/a5_allocation_frontier_probe_v1.gd")
const Fine = preload("res://scripts/research/ecology/v2/a5_fine_latency_profiler_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Lab = preload("res://scripts/labs/ecology/eco_arch2_polygon_lab.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _assert(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ECO_A14_6_INDEPENDENT_FAIL " + why)

func _run() -> void:
	_direct_a4_residual_probe()
	_actual_live_lab_a5()
	print("ECO_ARCH2_A14_6_INDEPENDENT checks=%d failed=%d" % [checks, failures])
	print("ECO_ARCH2_A14_6_INDEPENDENT " + ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)

func _direct_a4_residual_probe() -> void:
	var starting: Dictionary = Field.create("a14-6.independent", 0,
		[0, 0, 0], 1000, 3, 1, F.stock(0), F.stock(1000), F.signals())
	_assert(not starting.is_empty(), "versioned 3-cell field")
	if starting.is_empty():
		return
	var edit: Dictionary = Field.apply_effects(starting, [
		Ports.effect("independent-seed", "soil", "deposit", "water_mg",
			10, [2500, 0, 500], 0, "A14_6_INDEPENDENT"),
	], String(starting.owner_token), int(starting.owner_epoch),
		int(starting.revision))
	_assert(bool(edit.get("success", false)), "sealed A4 seed")
	if not bool(edit.get("success", false)):
		return
	var field: Dictionary = edit.state
	var original: String = C.encode(field)
	var ds: Array = [
		# Three covered cells, 2 mg total: third primary fraction ZERO.
		# First two cells empty; only third cell can satisfy residual.
		Ports.demand("a-cross", "org-a", "water_mg", 2, [1500, 0, 500], 1100),
		Ports.demand("b-local", "org-b", "water_mg", 1, [2500, 0, 500], 0),
		Ports.demand("c-nutrient", "org-c", "nutrient_mg", 1, [2500, 0, 500], 0),
	]
	var witness: Dictionary = Graph.analyze(field, ds)
	_assert(bool(witness.get("success", false)), "new graph accepts adversarial real field")
	if not bool(witness.get("success", false)):
		return
	_assert(int(witness.plan.component_count) == 2
		and int(witness.plan.max_component_demands) == 2,
		"both water requests connected through zero-primary residual edge")
	_assert(int(witness.plan.residual_claim_links) == 5
		and int(witness.plan.zero_primary_links) == 1,
		"all three primary and zero residual coverage links retained")
	_assert(int(witness.plan.cross_cell_demands) == 1
		and int(witness.plan.max_cells_per_demand) == 3,
		"single global spanning demand conservatively classified")
	var ids: Array = []
	for component in witness.plan.components:
		if String(component.resource) == "water_mg":
			ids = component.request_ids
	_assert(C.encode(ids) == C.encode(["a-cross", "b-local"]),
		"canonical component member list includes zero-primary partner")
	var shuffled: Array = [ds[2], ds[0], ds[1]]
	var swapped: Dictionary = Graph.analyze(field, shuffled)
	_assert(bool(swapped.get("success", false))
		and String(swapped.plan_hash) == String(witness.plan_hash),
		"field+sorted-demand graph stable under input permutation")
	var a4: Dictionary = Field.allocate_demands(
		field, ds, String(field.owner_token),
		int(field.owner_epoch), int(field.revision))
	_assert(bool(a4.get("success", false)), "original A4 global allocator succeeds")
	if bool(a4.get("success", false)):
		var grants := {}
		for g in a4.grants:
			grants[String(g.request_id)] = int(g.granted)
		_assert(int(grants.get("a-cross", -1)) == 2
			and int(grants.get("b-local", -1)) == 1,
			"original A4 residual genuinely grants from zero-primary linked cell")
		_assert(int(a4.state.cells[2].stocks.water_mg) == 7
			and F.validate_state(a4.state).is_empty(),
			"A4 ledger/conservation and global revision remain canonical")
		var shuffled_a4: Dictionary = Field.allocate_demands(
			field, shuffled, String(field.owner_token),
			int(field.owner_epoch), int(field.revision))
		_assert(bool(shuffled_a4.get("success", false))
			and C.encode(shuffled_a4.state) == C.encode(a4.state)
			and C.encode(shuffled_a4.grants) == C.encode(a4.grants),
			"original allocator independent of diagnostic input ordering")
	var rejected: Dictionary = field.duplicate(true)
	rejected.cells[2].stocks.water_mg += 1
	_assert(not bool(Graph.analyze(rejected, ds).get("success", false)),
		"mutated cell state fails full field admission")
	_assert(not bool(Graph.analyze(field, [ds[0], ds[0]]).get("success", false)),
		"duplicate request fails closed")
	_assert(not bool(Graph.analyze(field, [
		Ports.demand("far", "org-a", "water_mg", 1, [9999999, 0, 500], 0)
	]).get("success", false)), "out-of-range demand fails closed")
	_assert(C.encode(field) == original,
		"all graphs and reference allocation leave source unchanged")

func _actual_live_lab_a5() -> void:
	var host = Lab.new()
	host._build_manifest()
	var manifest: Dictionary = host.manifest.duplicate(true)
	host.free()
	var ctrl = Controller.new()
	var admission: Dictionary = ctrl.initialize(manifest, {})
	_assert(bool(admission.get("success", false)), "real shipped LAB controller starts")
	if not bool(admission.get("success", false)):
		return
	var state: Dictionary = ctrl.debug_state().runtime
	var opts: Dictionary = ctrl._canonical_step_options()
	_assert(bool(opts.get("success", false)), "manifest-only canonical step options")
	if not bool(opts.get("success", false)):
		return
	var snapshot: Dictionary = ctrl.serialize_state()
	var raw_runtime: String = C.encode(state)
	var profiled: Dictionary = Fine.profile_tick(state, opts.options, 64)
	_assert(bool(profiled.get("success", false)), "LAB A5 real stage profiler returns proof")
	if not bool(profiled.get("success", false)):
		push_error("A14_6_INDEPENDENT_LATENCY_ERROR " + String(profiled.get("error", "?")))
		return
	var profile: Dictionary = profiled.profile
	_assert(int(profile.global_allocation_calls) == 1
		and int(profile.committed_tick) == 1,
		"one ALL-population global ALLOCATE then complete staged tick")
	_assert(bool(profile.source_unchanged) and bool(profile.checkpoint_equal),
		"source and A8 serialized bytes remain exact")
	_assert(profile.phase_samples.size() == 2 * int(profile.worksets) + 1,
		"real PREPARE/ADVANCE worksets measured separately")
	_assert(String(profile.canonical_hash).length() == 64
		and String(profile.frontier_hash).length() == 64
		and int(profile.max_cursor_bytes) > 0,
		"canonical and A4 topology result hashes bounded")
	_assert(C.encode(state) == raw_runtime
		and ctrl.tick() == 0
		and String(ctrl.serialize_state().state_text) == String(snapshot.state_text),
		"diagnostic execution never commits to live LAB controller")
	_assert(not profiled.has("state"),
		"profile returns diagnostics only; never authoritative field/population")
