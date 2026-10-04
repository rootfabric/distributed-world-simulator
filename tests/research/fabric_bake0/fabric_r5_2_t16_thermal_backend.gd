extends RefCounted
## T16 adapter to unchanged T4 compiler/runtime/full reference. No reducer lives here.
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Compiler = preload("res://scripts/research/fabric_bake0/r5_t4_thermal_filter_compiler_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/r5_t4_thermal_filter_runtime_v1.gd")
const Full = preload("res://scripts/research/fabric_bake0/r5_t4_thermal_filter_full_reference_v1.gd")
const Projector = preload("res://scripts/research/fabric_bake0/thermal_filter_state_projector_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/thermal_pack_graph_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_r5_2_t4_thermal_filter_fixture.gd")
const EPS := 2.220446049250313e-16
const MAX_FULL_SUBSTEPS := 4096
var cached_candidate: Dictionary = {}
var candidate_calls := 0
var compile_calls := 0
var compact_calls := 0
var full_calls := 0
var full_cell_updates := 0
var full_solver_calls := 0

static func make_graph(asymmetric: bool = false) -> Dictionary:
	# Bounded 8x16 falsifier. T4's original 8x64 scaling/regression stays frozen.
	var g := Fixture.make_graph(asymmetric)
	var cells: Array = []
	for cell in g.cells:
		if int(cell.lane_index) < 16: cells.append(cell)
	return Graph.create("graph/r5-t16-thermal-pack-8x16", g.material_catalog, 8, 16, cells,
		float(g.interlayer_contact_area_m2), float(g.interlayer_contact_length_m),
		float(g.ambient_surface_area_m2), float(g.ambient_wall_thickness_m))

static func source(graph: Dictionary, revision: int = 0) -> Dictionary:
	var req := Fixture.build_request(graph, revision)
	return {"graph":graph.duplicate(true), "request":req, "live":{
		"artifact_state":"READY", "invalidations":[],
		"canonical_source_frontier":req.canonical_source_frontier.duplicate(true),
		"authority_envelope":req.authority_envelope.duplicate(true),
		"dependency_set":req.dependency_set.duplicate(true),
		"graph_hash":graph.graph_hash,
		"material_catalog_hash":graph.material_catalog.catalog_hash,
		"interface_hash":preload("res://scripts/research/fabric_bake0/thermal_filter_interface_contract_v1.gd").create().interface_hash,
	}}

static func command(dt: float = 0.05) -> Dictionary:
	return {"heat_input_w":3200.0, "dt_s":dt, "ambient_temperature_k":293.15, "event_threshold_k":300.001}

static func requirements() -> Dictionary:
	return {"observables":["output_temperature_k"], "events":[], "max_boundary_error":1.0e-7, "minimum_step_margin":0.1}

static func command_valid(cmd: Dictionary) -> bool:
	return U.is_non_negative_number(cmd.get("heat_input_w")) and U.is_positive_number(cmd.get("dt_s")) and U.is_positive_number(cmd.get("ambient_temperature_k")) and U.is_positive_number(cmd.get("event_threshold_k"))

static func maximum_rate(plan: Dictionary) -> float:
	var layers := int(plan.layer_count)
	var lanes := int(plan.lane_count)
	var rate := 0.0
	for layer in range(layers):
		for lane in range(lanes):
			var g := 0.0
			if layer > 0: g += float(plan.link_conductance_w_k[(layer - 1) * lanes + lane])
			if layer + 1 < layers: g += float(plan.link_conductance_w_k[layer * lanes + lane])
			else: g += float(plan.ambient_conductance_w_k[lane])
			rate = maxf(rate, g / float(plan.capacity_j_k[layer * lanes + lane]))
	return rate

static func full_substep_policy(plan: Dictionary, cmd: Dictionary) -> Dictionary:
	# One policy for certificate eligibility AND the actual fallback integrator.
	# COMPACT remains the unchanged one-step T4 executor; >1 FULL substep is not
	# certified. Never hide discretization error inside a looser tolerance.
	var work_ratio := float(cmd.dt_s) * maximum_rate(plan) / 0.5
	if not is_finite(work_ratio) or work_ratio > float(MAX_FULL_SUBSTEPS):
		return U.failure("T16_FULL_SUBSTEP_BUDGET_EXCEEDED")
	return U.success({"substeps":maxi(1, int(ceil(work_ratio)))})

static func validate_full_state(plan: Dictionary, state: Dictionary) -> Dictionary:
	# T4 consumes only temperatures. Unsupported physical fields must not be
	# silently dropped from the published successor or blindly copied as physics.
	var fields: Array[String] = ["cell_temperature_k"]
	if not U.validate_exact_fields(state, fields).success:
		return U.failure("T16_FULL_STATE_SCHEMA_INVALID")
	if typeof(state.get("cell_temperature_k")) != TYPE_ARRAY or state.cell_temperature_k.size() != int(plan.source_cell_count):
		return U.failure("T16_FULL_STATE_DOMAIN_INVALID")
	for raw in state.cell_temperature_k:
		if not U.is_positive_number(raw):
			return U.failure("T16_FULL_STATE_DOMAIN_INVALID")
		if float(raw) < float(plan.min_temperature_k) or float(raw) > float(plan.max_temperature_k):
			return U.failure("T16_FULL_STATE_DOMAIN_INVALID")
	return U.success()

func validate_candidate(candidate: Dictionary, src: Dictionary) -> Dictionary:
	if not Graph.validate(src.graph).success:
		return U.failure("T16_GRAPH_INVALID")
	for field in ["capsule", "artifact", "descriptor"]:
		if typeof(candidate.get(field)) != TYPE_DICTIONARY:
			return U.failure("T16_CANDIDATE_SHAPE_INVALID")
	# Validate the actual current source, including fresh canonical frontier,
	# rather than accepting a stale `live` envelope copied from the artifact.
	var expected := source(src.graph)
	if src.live.get("graph_hash") != expected.live.graph_hash or src.live.get("material_catalog_hash") != expected.live.material_catalog_hash:
		return U.failure("T16_LIVE_GRAPH_MISMATCH")
	for field in ["canonical_source_frontier", "authority_envelope", "dependency_set"]:
		if src.live.get(field) != src.request[field]:
			return U.failure("T16_LIVE_PROVENANCE_MISMATCH")
	var rt := Runtime.new()
	return rt.prepare(candidate.capsule, candidate.artifact, candidate.descriptor, src.live)

func prepare_candidate(src: Dictionary, state: Dictionary, cmd: Dictionary) -> Dictionary:
	candidate_calls += 1
	if not command_valid(cmd):
		return U.failure("T16_COMMAND_INVALID")
	var candidate := cached_candidate.duplicate(true)
	if candidate.is_empty():
		compile_calls += 1
		var built := Compiler.compile(src.graph, src.request, "capsule/r5-t16-thermal-probe")
		if not built.success:
			return built
		candidate = built.details
	var checked := validate_candidate(candidate, src)
	if not checked.success: return checked
	var projected := Projector.project(src.graph, candidate.descriptor, state)
	if not projected.success: return projected
	var plan := Full.prepare(src.graph)
	if not plan.success: return plan
	var policy := full_substep_policy(plan.details, cmd)
	if not policy.success: return policy
	var rebuilt: Array = []
	for t in projected.details.next_state.layer_temperature_k:
		for _lane in range(int(src.graph.lane_count)): rebuilt.append(t)
	# One-step, bounded-input certificate, not a trajectory/global error claim.
	# Symmetry is certified by unchanged T4; conservatively bound arithmetic
	# roundoff of the shared explicit stencil. Near-critical coefficients are
	# rejected independently. Detailed integration substeps below the same bound.
	var max_t := float(cmd.ambient_temperature_k)
	for t in state.cell_temperature_k: max_t = maxf(max_t, absf(float(t)))
	var min_c := INF
	for c in plan.details.capacity_j_k: min_c = minf(min_c, float(c))
	var rate := maximum_rate(plan.details)
	var scale := max_t * (1.0 + 2.0 * float(cmd.dt_s) * rate) + float(cmd.heat_input_w) * float(cmd.dt_s) / min_c
	# Compare the actually derived full/lumped stencil coefficients. The bound
	# includes coefficient discrepancy AND finite-precision stencil/output sums.
	var coefficient_error := 0.0
	var d: Dictionary = candidate.descriptor
	for layer in range(int(src.graph.layer_count)):
		var cc := float(d.layer_capacity_j_k[layer])
		var cl := float(d.layer_link_conductance_w_k[layer - 1]) if layer > 0 else 0.0
		var cr := float(d.layer_link_conductance_w_k[layer]) if layer + 1 < int(src.graph.layer_count) else 0.0
		var ca := float(d.ambient_conductance_w_k) if layer + 1 == int(src.graph.layer_count) else 0.0
		for lane in range(int(src.graph.lane_count)):
			var lanes := int(src.graph.lane_count)
			var fc := float(plan.details.capacity_j_k[layer * lanes + lane])
			var fl := float(plan.details.link_conductance_w_k[(layer - 1) * lanes + lane]) if layer > 0 else 0.0
			var fr := float(plan.details.link_conductance_w_k[layer * lanes + lane]) if layer + 1 < int(src.graph.layer_count) else 0.0
			var fa := float(plan.details.ambient_conductance_w_k[lane]) if layer + 1 == int(src.graph.layer_count) else 0.0
			var error := max_t * (absf((fl + fr + fa) / fc - (cl + cr + ca) / cc) + absf(fl / fc - cl / cc) + absf(fr / fc - cr / cc))
			error += float(cmd.ambient_temperature_k) * absf(fa / fc - ca / cc)
			if layer == 0: error += float(cmd.heat_input_w) * absf(1.0 / (float(lanes) * fc) - 1.0 / cc)
			coefficient_error = maxf(coefficient_error, float(cmd.dt_s) * error)
	var arithmetic_envelope := ((float(src.graph.lane_count) + 64.0) * EPS / (1.0 - (float(src.graph.lane_count) + 64.0) * EPS)) * scale
	return U.success({
		"candidate":candidate,
		"compact_state":projected.details.next_state,
		"reconstructed_state":{"cell_temperature_k":rebuilt},
		"observables":["output_temperature_k"], "events":[],
		"boundary_error_bound":coefficient_error + arithmetic_envelope,
		"step_margin":1.0 - float(cmd.dt_s) * rate,
		"temporal_policy_matches":int(policy.details.substeps) == 1,
		"full_substeps":int(policy.details.substeps),
	})

func execute_compact(probe: Dictionary, src: Dictionary, cmd: Dictionary) -> Dictionary:
	compact_calls += 1
	var c: Dictionary = probe.candidate
	var rt := Runtime.new()
	var ready := rt.prepare(c.capsule, c.artifact, c.descriptor, src.live)
	if not ready.success: return ready
	return rt.execute(src.live, probe.compact_state, float(cmd.heat_input_w), float(cmd.dt_s), float(cmd.ambient_temperature_k))

func execute_full(src: Dictionary, state: Dictionary, cmd: Dictionary) -> Dictionary:
	full_calls += 1
	if not command_valid(cmd): return U.failure("T16_COMMAND_INVALID")
	var prepared := Full.prepare(src.graph)
	if not prepared.success: return prepared
	var plan: Dictionary = prepared.details
	var checked := validate_full_state(plan, state)
	if not checked.success: return checked
	var policy := full_substep_policy(plan, cmd)
	if not policy.success: return policy
	var substeps := int(policy.details.substeps)
	var current := state.duplicate(true)
	var energy := 0.0
	var exchange := 0.0
	var residual := 0.0
	var events: Array = []
	var output := 0.0
	for substep in range(substeps):
		full_solver_calls += 1
		var step := Full.execute(plan, current, float(cmd.heat_input_w), float(cmd.dt_s) / float(substeps), float(cmd.ambient_temperature_k))
		if not step.success: return step
		for i in range(int(plan.source_cell_count)):
			if float(current.cell_temperature_k[i]) < float(cmd.event_threshold_k) and float(step.details.next_state.cell_temperature_k[i]) >= float(cmd.event_threshold_k):
				events.append({"kind":"temperature_threshold_crossed", "cell":i, "substep":substep})
		full_cell_updates += int(step.details.source_cell_traversals)
		current = step.details.next_state
		energy += float(step.details.state_energy_delta_j)
		exchange += float(step.details.ambient_exchange_j)
		residual += float(step.details.energy_residual_j)
		output = float(step.details.output_temperature_k)
	return U.success({"next_state":current, "output_temperature_k":output,
		"state_energy_delta_j":energy, "ambient_exchange_j":exchange, "energy_residual_j":residual,
		"events":events, "full_substeps":substeps, "source_cell_updates":substeps * int(plan.source_cell_count)})
