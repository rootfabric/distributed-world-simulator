extends SceneTree
## A14.7 R2F P2 — true multi-tick original A13 vs owned E3+Stage B/C
## with mutation/reproduction enabled, zero-resource and zero-demand
## frontiers, FULL Runtime/A8 parity at EACH canonical tick.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Lifecycle = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const Blueprint = preload("res://scripts/research/ecology/v2/organism_blueprint_v1.gd")
const FieldContract = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const Feedback = preload("res://scripts/research/ecology/v2/persistent_environmental_feedback_v1.gd")
const Checkpoint = preload("res://scripts/research/ecology/v2/ecology_runtime_checkpoint_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Fixture = preload("res://validation/ecology/evo_arch2_a14_7/a147_scale_fixture.gd")
const Lab = preload("res://scripts/labs/ecology/eco_arch2_polygon_lab.gd")
const MODES := ["scale", "repro", "no-demand", "zero-stock"]
const POLL_LIMIT := 12000
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, name: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("A147_R2F_MULTI_FAIL " + name)

func _manifest() -> Dictionary:
	var h = Lab.new()
	h._build_manifest()
	var m: Dictionary = h.manifest.duplicate(true)
	h.free()
	m.seed = 20261006
	m.mutation.mutations_enabled = true
	m.mutation.operator = "module_parameter"
	return m

func _make_source(mode: String, n: int) -> Dictionary:
	var accepted: Dictionary = Fixture.new().create_population(n)
	if accepted.is_empty():
		return {}
	if mode == "scale":
		return accepted
	var members: Array = accepted.population.duplicate(true)
	var field: Dictionary = accepted.field.duplicate(true)
	if mode == "repro":
		# Same proven reproductive life policy used in A13 Fidelity.
		var reference_bp: Dictionary = Fixture.new()._stable_blueprint()
		var policy: Dictionary = reference_bp.life_history.duplicate(true)
		policy.reproduction.maturity_ticks = 2
		policy.reproduction.interval_ticks = 2
		policy.reproduction.endowment = {
			"material_mg": 100, "water_mg": 100, "energy_mj": 100,
		}
		policy.reproduction.fee_energy_mj = 0
		var bp: Dictionary = Blueprint.create(reference_bp.genome, policy)
		_check(not bp.is_empty(), "valid reproductive blueprint")
		if bp.is_empty(): return {}
		members = []
		for i in n:
			var individual: Dictionary = Lifecycle.individual(
				bp, "r2f-reproductive-%03d" % i,
				accepted.population[i].state.position_mm,
				{"material_mg": 100000, "water_mg": 100000,
				"energy_mj": 100000})
			_check(not individual.is_empty(), "reproductive founder valid")
			if individual.is_empty(): return {}
			members.append(individual)
	elif mode == "no-demand":
		# Valid canonical DEAD_INERT organisms cannot demand any resource.
		for member in members:
			member.state.alive = false
			member.state.starvation_ticks = int(
				member.blueprint.life_history.survival.starvation_limit_ticks)
			member.state.age_ticks = int(member.state.starvation_ticks)
	elif mode == "zero-stock":
		field = Field.create(String(accepted.field.owner_token),
			int(accepted.field.owner_epoch), [0, 0, 0], 1000, 8, 8,
			FieldContract.stock(0), FieldContract.stock(FieldContract.MAX_CELL_STOCK),
			FieldContract.signals(1000, 500, 0, 0))
		_check(not field.is_empty(), "valid resource-starved field")
		if field.is_empty(): return {}
	var created: Dictionary = Runtime.create(
		"eco/a147-r2f-" + mode, field, members,
		Feedback.default_policy(), false)
	_check(bool(created.get("success", false)),
		"canonical source " + mode + ": " + String(created.get("error", "")))
	return created.state if bool(created.get("success", false)) else {}

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 4 or String(args[0]) != "--mode" \
			or not String(args[1]) in MODES or String(args[2]) != "--population" \
			or not String(args[3]) in ["4", "32", "96", "256"]:
		_check(false, "mode and population CLI required")
		_finish()
		return
	var mode: String = String(args[1])
	var n: int = int(args[3])
	if mode != "scale" and n != 4:
		_check(false, "non-scale requires canonical n4")
		_finish()
		return
	var num_ticks: int = 8 if mode == "repro" else (2 if mode == "scale" else 1)
	var source: Dictionary = _make_source(mode,n)
	_check(not source.is_empty() and Runtime.validate(source).is_empty(),
		"re-sealed original source valid")
	if source.is_empty():
		_finish()
		return
	var source_before: String = C.encode(source)
	var c = Controller.new()
	var manifest: Dictionary = _manifest()
	var init: Dictionary = c.initialize(manifest,{})
	_check(bool(init.get("success", false)), "real mutation-enabled LAB initialized")
	if not bool(init.get("success", false)):
		_finish()
		return
	c._runtime = source.duplicate(true)
	var opts: Dictionary = c._canonical_step_options().options
	_check(bool(opts.mutations_enabled) and String(opts.operator) == "module_parameter",
		"full real mutation/reproduction admission enabled")
	var reference: Dictionary = source.duplicate(true)
	var hash_chain: Array = []
	var revision_chain: Array = []
	var population_chain: Array = []
	var worker_wall: Array = []
	var checkpoint_exact := true
	var owner_unchanged := true
	var did_progress := false
	var initial_population: int = source.population.size()
	# Verify original A5 PREPARE has the expected demand frontier.
	var staged: Dictionary = Lifecycle.staged_begin(
		source.field, source.population, String(source.field.owner_token),
		int(source.field.owner_epoch),int(source.field.revision),4,64,true)
	_check(bool(staged.get("success", false)), "authentic R3 A5 PREPARE")
	var seen_demands := -1
	var allocation_demands: Array = []
	if bool(staged.get("success", false)):
		var cursor: Dictionary = staged.cursor
		for j in 128:
			if String(cursor.phase) == "ALLOCATE":
				seen_demands = cursor.demands.size()
				allocation_demands = cursor.demands.duplicate(true)
				break
			var p: Dictionary = Lifecycle.staged_resume(
				cursor,source.field,source.population,16,4096,8388608,4)
			if not bool(p.get("success", false)):
				_check(false,"A5 real demand preparation:"+String(p.get("error","?")))
				break
			cursor = p.cursor
	_check((mode == "no-demand" and seen_demands == 0) \
		or (mode != "no-demand" and seen_demands > 0),
		"correct original no-demand/nonempty-demand frontier")
	if mode == "zero-stock" and seen_demands > 0:
		var allocated: Dictionary = Field.allocate_demands(
			source.field,allocation_demands,String(source.field.owner_token),
			int(source.field.owner_epoch),int(source.field.revision))
		_check(bool(allocated.get("success",false)),
			"canonical original allocation in saturated resource-starved field")
		if bool(allocated.get("success",false)):
			var no_grants: bool = true
			for g in allocated.grants:
				no_grants = no_grants and int(g.granted) == 0
			_check(no_grants,"zero field stock yields exactly zero grants")
	for t in num_ticks:
		var previous: String = C.encode(reference)
		var original: Dictionary = Runtime.step_spatial_parallel_advance(
			reference,opts,4,64,4,4)
		_check(bool(original.get("success", false)),
			"original full A13 tick %d: %s" % [t + 1, String(original.get("error","?"))])
		if not bool(original.get("success", false)): break
		_check(C.encode(reference) == previous, "previous source not mutated")
		var completed := false
		for poll_index in POLL_LIMIT:
			var response: Dictionary = c.run_staged_frame(
				1000000000,1,1,64,8388608,true,4096,
				true,false,true,true,16,4)
			if not bool(response.get("success", false)):
				_check(false,"E3 composed tick failed: "+String(response.get("error","?")))
				break
			if bool(response.get("complete", false)):
				completed = true
				break
			_check(c.tick() == int(reference.tick),
				"canonical tick never advances before worker commits")
			await create_timer(0.02).timeout
		_check(completed,"E3 whole worker tick %d completes" % (t+1))
		if not completed:
			c.cancel_staged_tick()
			break
		var current: Dictionary = c.debug_state().runtime
		var baseline: Dictionary = original.state
		_check(C.encode(current) == C.encode(baseline) \
			and Runtime.state_hash(current) == Runtime.state_hash(baseline) \
			and int(current.tick) == t+1,
			"whole Runtime bytes/hash including grants/outbox exact at tick %d" % (t+1))
		var ck_anchor: String = C.digest({
			"schema":"dws.ecology.a147-r2f-multi.v1", "mode":mode,
			"population":n,"tick":t+1})
		var cp_ref: Dictionary = Checkpoint.create(ck_anchor,baseline)
		var cp_new: Dictionary = Checkpoint.create(ck_anchor,current)
		var same_cp: bool = not cp_ref.is_empty() and not cp_new.is_empty() \
			and Checkpoint.serialize(cp_ref) == Checkpoint.serialize(cp_new)
		checkpoint_exact = checkpoint_exact and same_cp
		_check(same_cp,"complete serialized A8 equal after each tick")
		owner_unchanged = owner_unchanged \
			and String(current.field.owner_token) == String(source.field.owner_token) \
			and int(current.field.owner_epoch) == int(source.field.owner_epoch)
		_check(int(current.field.revision) >= int(reference.field.revision),
			"field owner revision monotonically advances or remains unchanged")
		if int(current.field.revision) > int(reference.field.revision):
			did_progress = true
		var st: Dictionary = c.get_staged_telemetry().off_main
		_check(bool(st.last_worker_r2e2_owned_fast) \
			and bool(st.last_worker_r2e3_original_a4) \
			and int(st.last_worker_worksets_per_resume) == 16 \
			and int(st.last_r2c_parallel_workset_workers) == 4 \
			and int(st.last_worker_phase_profile.get(
				"r2e3_original_global_a4_barriers",-1)) == 1 \
			and int(st.last_worker_source_validate_wall_us) > 0 \
			and int(st.last_worker_candidate_validate_wall_us) > 0,
			"exactly one E3 global A4, full final source and candidate validation")
		worker_wall.append(int(st.last_worker_wall_us))
		hash_chain.append(Runtime.state_hash(current))
		revision_chain.append(int(current.field.revision))
		population_chain.append(current.population.size())
		reference = baseline
	_check(C.encode(source) == source_before,
		"unchanged detached original fixture across all ticks")
	_check(owner_unchanged and checkpoint_exact and hash_chain.size() == num_ticks,
		"all owner generations and A8 checkpoint receipts accounted for")
	if mode == "repro":
		_check(reference.population.size() > initial_population,
			"actual reproduction occurred under enabled mutation policy")
	if mode == "scale" or mode == "repro":
		_check(did_progress,"field revision advanced under real resource grants")
	print("A147_R2F_MULTI_JSON " + JSON.stringify({
		"schema":"dws.ecology.a147-r2f-multitick-exact.v1",
		"mode":mode,"population":n,"ticks":num_ticks,
		"mutation_enabled":bool(opts.mutations_enabled),
		"reproduction_observed":reference.population.size()>initial_population,
		"no_demand":seen_demands==0,
		"source_unchanged":C.encode(source)==source_before,
		"checkpoint_every_tick":checkpoint_exact,
		"owner_unchanged":owner_unchanged,
		"field_revision_chain":revision_chain,
		"population_chain":population_chain,
		"hash_chain":hash_chain,
		"worker_wall_us":worker_wall,
		"single_global_a4":true,
		"no_partial_publication":true,
	}))
	_finish()

func _finish() -> void:
	print("A147_R2F_MULTI checks=%d failed=%d" % [checks,failures])
	print("A147_R2F_MULTI " + ("PASS" if failures==0 else "FAIL"))
	quit(0 if failures==0 else 1)
