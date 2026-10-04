extends SceneTree
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Gate = preload("res://scripts/research/fabric_bake0/r5_t16_no_safe_bake_runtime_v1.gd")
const Backend = preload("res://tests/research/fabric_bake0/fabric_r5_2_t16_thermal_backend.gd")
const TF = preload("res://tests/research/fabric_bake0/fabric_r5_2_t4_thermal_filter_fixture.gd")
const Full = preload("res://scripts/research/fabric_bake0/r5_t4_thermal_filter_full_reference_v1.gd")
const T1F = preload("res://tests/research/fabric_bake0/fabric_r5_2_t1_boundary_network_fixture.gd")
const T1C = preload("res://scripts/research/fabric_bake0/r5_t1_boundary_network_capsule_compiler_v1.gd")
const Authority = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const Dependencies = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")
const Measure = preload("res://scripts/research/fabric_bake0/r5_measurement_harness_v1.gd")

class MissingReconstruction extends Backend:
	func prepare_candidate(src: Dictionary, state: Dictionary, cmd: Dictionary) -> Dictionary:
		var p := super.prepare_candidate(src, state, cmd)
		if p.success: p.details.erase("reconstructed_state")
		return p

class CorruptCertificate extends Backend:
	func prepare_candidate(src: Dictionary, state: Dictionary, cmd: Dictionary) -> Dictionary:
		var p := super.prepare_candidate(src, state, cmd)
		if p.success: p.details.boundary_error_bound = NAN
		return p

class FailingCompact extends Backend:
	func execute_compact(_p: Dictionary, _s: Dictionary, _c: Dictionary) -> Dictionary:
		compact_calls += 1
		return U.failure("TEST_COMPACT_STEP_FAILURE")

var checks := 0
var failures: Array = []
var cases: Dictionary = {}
var fallback_updates := 0
var event_count := 0
var full_continuation_ticks := 0
var max_energy_residual := 0.0
var max_boundary_error := 0.0
var positive_traces: Array = []
var temporal_pairs: Array = []
var temporal_compact_pairs := 0
var temporal_full_pairs := 0
var max_temporal_output_error := 0.0
var r1_f1_gap := -1.0
var measure = Measure.new("fabric-r5-2-t16")

func check(ok: bool, label: String, extra = null) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("T16: " + label + " " + JSON.stringify(extra))

func raw_full(plan: Dictionary, state: Dictionary, cmd: Dictionary) -> Dictionary:
	# Independent orchestration of the existing source-cell reference; this path
	# does not call T16 or the adapter and cannot switch to a compact executor.
	var current := state.duplicate(true)
	var steps: int = maxi(1, int(ceil(float(cmd.dt_s) * Backend.maximum_rate(plan) / 0.5)))
	var events: Array = []
	for substep in range(steps):
		var row := Full.execute(plan, current, float(cmd.heat_input_w), float(cmd.dt_s) / float(steps), float(cmd.ambient_temperature_k))
		if not row.success: return row
		for i in range(current.cell_temperature_k.size()):
			if float(current.cell_temperature_k[i]) < float(cmd.event_threshold_k) and float(row.details.next_state.cell_temperature_k[i]) >= float(cmd.event_threshold_k):
				events.append({"kind":"temperature_threshold_crossed", "cell":i, "substep":substep})
		current = row.details.next_state
	return U.success({"next_state":current, "events":events})

func reject_case(name: String, src: Dictionary, state: Dictionary, requirements: Dictionary, cmd: Dictionary, expected_reason: String, execution: String = "FULL", backend = null) -> Dictionary:
	var b = Backend.new() if backend == null else backend
	var src_hash := Gate.binary_hash(src)
	var state_hash := Gate.binary_hash(state)
	var command_hash := Gate.binary_hash(cmd)
	var req_hash := Gate.binary_hash(requirements)
	var out := Gate.attempt(b, src, state, cmd, requirements)
	check(out.success, name + ": attempt returns controlled outcome", out)
	if not out.success: return {}
	var d: Dictionary = out.details
	check(d.status == "NO_SAFE_BAKE", name + ": refuses unsafe bake", d)
	check(d.reason == expected_reason, name + ": exact refusal reason", d.reason)
	check(d.execution == execution, name + ": explicit execution disposition", d.execution)
	check(d.artifact.is_empty(), name + ": no declined executable escapes")
	check(src_hash == Gate.binary_hash(src) and state_hash == Gate.binary_hash(state), name + ": caller source/state unchanged")
	check(command_hash == Gate.binary_hash(cmd) and req_hash == Gate.binary_hash(requirements), name + ": command/requirements unchanged")
	check(d.source_hash_before == d.source_hash_after and d.state_hash_before == d.state_hash_after, name + ": receipt input identity unchanged")
	var comp_expected := 1 if execution == "COMPACT_STEP_REFUSED" else 0
	var full_expected := 1 if execution in ["FULL", "FULL_STEP_REFUSED"] else 0
	check(b.compact_calls == comp_expected and b.full_calls == full_expected, name + ": exactly the selected physical executor called")
	check(int(d.compact_calls) == comp_expected and int(d.full_calls) == full_expected, name + ": call accounting is observed")
	var row := {"reason":d.reason, "execution":d.execution, "source_preserved":src_hash == Gate.binary_hash(src), "state_preserved":state_hash == Gate.binary_hash(state), "compact_calls":b.compact_calls, "full_calls":b.full_calls, "candidate_calls":b.candidate_calls, "compile_calls":b.compile_calls, "full_cell_updates":b.full_cell_updates, "full_solver_calls":b.full_solver_calls, "execution_error":String(d.get("execution_error", ""))}
	if execution == "FULL":
		var plan := Full.prepare(src.graph)
		check(plan.success, name + ": source remains physically executable", plan)
		var ref := raw_full(plan.details, state, cmd)
		check(ref.success, name + ": independent full reference executes", ref)
		check(Gate.binary_hash(d.physical.next_state) == Gate.binary_hash(ref.details.next_state), name + ": actual full next state is byte-identical")
		check(d.physical.events == ref.details.events, name + ": boundary event stream exact and not duplicated")
		check(Gate.binary_hash(d.physical.next_state) != state_hash, name + ": detailed state really evolves, not a frozen fallback")
		fallback_updates += int(d.physical.source_cell_updates)
		event_count += d.physical.events.size()
		max_energy_residual = maxf(max_energy_residual, absf(float(d.physical.energy_residual_j)))
		check(absf(float(d.physical.energy_residual_j)) < 1.0e-6 and b.full_solver_calls == int(d.physical.full_substeps), name + ": energy ledger balances")
		var continuation: Dictionary = d.physical.next_state
		var traces: Array = [continuation.duplicate(true)]
		# Retain and evolve all 128 actual state scalars after a declined attempt.
		# No repeated bake attempt or steady per-tick compiler is used here.
		for tick in range(8):
			var stepped := Full.execute(plan.details, continuation, 1800.0 + 13.0 * float(tick), 0.02, 294.0)
			check(stepped.success, name + ": detailed continuation %d" % tick, stepped)
			if not stepped.success: break
			continuation = stepped.details.next_state
			check(continuation.cell_temperature_k.size() == 128, name + ": all hidden state scalars retained")
			full_continuation_ticks += 1
			traces.append(continuation.duplicate(true))
		row.physical_trace_hash = U.canonical_hash(traces)
		row.events_hash = U.canonical_hash(d.physical.events)
		row.source_cell_updates = int(d.physical.source_cell_updates)
		row.full_substeps = int(d.physical.full_substeps)
	else:
		check(d.physical.is_empty(), name + ": no fabricated physical result")
		check(b.full_cell_updates == 0 and b.full_solver_calls == 0, name + ": no detailed physics advances on refusal/handoff")
		if execution == "FULL_STEP_REFUSED":
			var expected_error := "T16_FULL_STATE_SCHEMA_INVALID" if state.size() != 1 or not state.has("cell_temperature_k") else "T16_FULL_STATE_DOMAIN_INVALID"
			check(d.execution_error == expected_error, name + ": exact FULL schema/domain rejection", d)
	cases[name] = row
	return d

func temporal_policy_campaign(src: Dictionary, plan: Dictionary, state: Dictionary, requirements: Dictionary, candidate: Dictionary) -> void:
	# The reference is the actual selected FULL adapter, not a one-step surrogate.
	# Independent event oracle uses the unchanged source-cell solver directly.
	var rate := Backend.maximum_rate(plan)
	var ratios: Array = [0.01, 0.25, 0.49, 0.5 - 1.0e-8, 0.5, 0.5 + 1.0e-8, 0.6, 0.75, 0.85, 0.9, 0.95]
	for variant in range(2):
		for ratio in ratios:
			var detailed := state.duplicate(true)
			if variant == 1:
				for layer in range(8):
					for lane in range(16): detailed.cell_temperature_k[layer * 16 + lane] = 295.0 + 0.75 * float(layer)
			var c := Backend.command(float(ratio) / rate)
			c.heat_input_w = 0.0 if variant == 0 else 3200.0
			var observed := requirements.duplicate(true)
			observed.events = ["temperature_threshold_crossed"]
			var compact_backend := Backend.new()
			compact_backend.cached_candidate = candidate
			var full_backend := Backend.new()
			full_backend.cached_candidate = candidate
			var before := Gate.binary_hash([src, detailed, c, requirements, observed])
			var x := Gate.attempt(compact_backend, src, detailed, c, requirements)
			var y := Gate.attempt(full_backend, src, detailed, c, observed)
			var label := "temporal pair %d ratio %.8f" % [variant, float(ratio)]
			check(x.success and y.success, label + ": controlled attempts", {"x":x, "y":y})
			if not x.success or not y.success: continue
			var eligible: bool = float(c.dt_s) * rate <= 0.5
			check(x.details.execution == ("COMPACT" if eligible else "FULL"), label + ": policy disposition", x)
			check(x.details.status == ("BAKE_READY" if eligible else "NO_SAFE_BAKE"), label + ": safe eligibility")
			check(y.details.execution == "FULL" and y.details.reason == "UNRESOLVED_HIDDEN_EVENT", label + ": real observed FULL", y)
			check(compact_backend.compact_calls == int(eligible) and compact_backend.full_calls == int(not eligible) and full_backend.compact_calls == 0 and full_backend.full_calls == 1, label + ": one executor per attempt")
			check(before == Gate.binary_hash([src, detailed, c, requirements, observed]), label + ": all inputs preserved")
			if x.details.physical.is_empty() or y.details.physical.is_empty():
				check(false, label + ": actual physical result required"); continue
			var gap := absf(float(x.details.physical.output_temperature_k) - float(y.details.physical.output_temperature_k))
			max_temporal_output_error = maxf(max_temporal_output_error, gap)
			check(gap <= float(requirements.max_boundary_error), label + ": actual FULL stays within unchanged error budget", gap)
			var ref := raw_full(plan, detailed, c)
			check(ref.success and ref.details.events == y.details.physical.events, label + ": actual FULL events exact and once")
			check(ref.success and Gate.binary_hash(ref.details.next_state) == Gate.binary_hash(y.details.physical.next_state), label + ": actual FULL state reference exact")
			var substeps: int = maxi(1, int(ceil(float(c.dt_s) * rate / 0.5)))
			check(int(y.details.physical.full_substeps) == substeps and full_backend.full_cell_updates == substeps * 128, label + ": real substep work")
			if eligible:
				temporal_compact_pairs += 1
				var probe := Backend.new().prepare_candidate(src, detailed, c)
				check(probe.success and gap <= float(probe.details.boundary_error_bound), label + ": certificate bounds ACTUAL FULL discrepancy", gap)
				check(int(x.details.physical.runtime_source_cell_traversals) == 0, label + ": compact source traversals remain zero")
			else:
				temporal_full_pairs += 1
				check(x.details.reason in ["T16_TEMPORAL_POLICY_UNSUPPORTED", "NEAR_CRITICAL_DYNAMICS"], label + ": explicit policy or margin refusal", x.details.reason)
				check(x.details.physical == y.details.physical and x.details.artifact.is_empty(), label + ": observation does not change detailed physics/events")
			if variant == 0 and float(ratio) == 0.75:
				r1_f1_gap = gap
				check(x.details.reason == "T16_TEMPORAL_POLICY_UNSUPPORTED" and gap == 0.0, "R1 F1 0.8297819 K discrepancy eliminated without tolerance change")
			temporal_pairs.append({"variant":variant, "ratio":ratio, "execution":x.details.execution, "gap_k":gap, "physical":x.details.physical, "events":y.details.physical.events})
	check(temporal_pairs.size() == 22 and temporal_compact_pairs == 10 and temporal_full_pairs == 12, "temporal boundary campaign covers compact and refused intervals")

func _initialize() -> void:
	measure.begin_stage("source_and_positive")
	var graph := Backend.make_graph()
	var src := Backend.source(graph)
	var plan := Full.prepare(graph)
	check(plan.success, "source thermal full plan", plan)
	if not plan.success: quit(1); return
	var state := Full.initial_state(plan.details, 300.0)
	var cmd := Backend.command()
	var requirements := Backend.requirements()
	var base_hash := Gate.binary_hash([src, state, cmd, requirements])
	var good = Backend.new()
	var ready := Gate.attempt(good, src, state, cmd, requirements)
	check(ready.success, "safe positive attempt", ready)
	if not ready.success or ready.details.status != "BAKE_READY":
		check(false, "safe reducer is not blanket-disabled", ready)
		finish(); return
	check(ready.details.execution == "COMPACT", "safe positive selects compact")
	check(good.compact_calls == 1 and good.full_calls == 0, "safe path never runs full physics")
	check(not ready.details.artifact.is_empty(), "safe path publishes validated artifact only")
	check(ready.details.physical.next_state.layer_temperature_k.size() == 8, "safe path retains compact eight-state result")
	check(int(ready.details.physical.runtime_source_cell_traversals) == 0, "native compact tick traverses zero cells")
	check(base_hash == Gate.binary_hash([src, state, cmd, requirements]), "safe attempt preserves caller inputs")
	# Many states on the certified manifold exercise the arithmetic envelope,
	# not just one initial-value coincidence. Canonical source is reused unchanged.
	var candidate: Dictionary = ready.details.artifact
	for k in range(8):
		var varied := state.duplicate(true)
		for layer in range(8):
			for lane in range(16): varied.cell_temperature_k[layer * 16 + lane] = 295.0 + float(layer) * 0.75 + float(k) * 0.1
		var c := Backend.command(0.01 + 0.02 * float(k))
		var b := Backend.new()
		b.cached_candidate = candidate
		var probe := b.prepare_candidate(src, varied, c)
		check(probe.success, "positive certificate probe %d" % k, probe)
		var run := Gate.attempt(b, src, varied, c, requirements)
		check(run.success and run.details.status == "BAKE_READY", "positive manifold variant %d" % k, run)
		var ref := Backend.new().execute_full(src, varied, c)
		check(ref.success, "positive full reference %d" % k, ref)
		if not run.success or not ref.success: continue
		var error := absf(float(run.details.physical.output_temperature_k) - float(ref.details.output_temperature_k))
		max_boundary_error = maxf(max_boundary_error, error)
		check(error <= float(probe.details.boundary_error_bound), "declared boundary envelope bounds observed error %d" % k, {"error":error, "bound":probe.details.boundary_error_bound})
		positive_traces.append(run.details.physical.next_state)
	temporal_policy_campaign(src, plan.details, state, requirements, candidate)
	measure.end_stage("source_and_positive")
	measure.begin_stage("refusal_and_full_continuation")

	var hidden := state.duplicate(true)
	hidden.cell_temperature_k[9] = 304.0
	hidden.cell_temperature_k[10] = 296.0
	check(float(hidden.cell_temperature_k[9]) + float(hidden.cell_temperature_k[10]) == 600.0, "hidden mode has same naive layer mean but different source state")
	reject_case("hidden_mode", src, hidden, requirements, cmd, "THERMAL_STATE_NOT_IN_REDUCTION_MANIFOLD")
	var tiny := state.duplicate(true)
	tiny.cell_temperature_k[9] = 300.0 + 1.0e-9
	reject_case("lossy_reconstruction", src, tiny, requirements, cmd, "RECONSTRUCTION_NOT_EXACT")
	reject_case("missing_reconstruction", src, state, requirements, cmd, "RECONSTRUCTION_UNAVAILABLE", "FULL", MissingReconstruction.new())
	var obs := requirements.duplicate(true)
	obs.observables = ["unrepresented_boundary_sensor"]
	reject_case("insufficient_observability", src, state, obs, cmd, "INSUFFICIENT_OBSERVABILITY")
	var events := requirements.duplicate(true)
	events.events = ["temperature_threshold_crossed"]
	var event_result := reject_case("hidden_event", src, state, events, cmd, "UNRESOLVED_HIDDEN_EVENT")
	check(event_result.physical.events.size() == 16, "FULL preserves 16 actual per-cell threshold crossings exactly once")
	var impossible_error := requirements.duplicate(true)
	impossible_error.max_boundary_error = 0.0
	reject_case("unsafe_error_budget", src, state, impossible_error, cmd, "UNSAFE_ERROR_ENVELOPE")
	reject_case("nonfinite_error_certificate", src, state, requirements, cmd, "UNSAFE_ERROR_ENVELOPE", "FULL", CorruptCertificate.new())
	var critical_command := Backend.command(0.95 / Backend.maximum_rate(plan.details))
	var critical := reject_case("near_critical_step", src, state, requirements, critical_command, "NEAR_CRITICAL_DYNAMICS")
	check(int(critical.physical.full_substeps) == 2, "near-critical compact step becomes two real detailed substeps")
	var asymmetric := Backend.source(Backend.make_graph(true), 1)
	reject_case("unsupported_reduction_topology", asymmetric, state, requirements, cmd, "THERMAL_PACK_LAYER_SYMMETRY_BROKEN")
	var stale = Backend.new()
	stale.cached_candidate = candidate
	reject_case("stale_frontier", Backend.source(graph, 1), state, requirements, cmd, "THERMAL_FILTER_RUNTIME_FRONTIER_MISMATCH", "FULL", stale)
	var damaged_stale = Backend.new()
	damaged_stale.cached_candidate = candidate
	reject_case("source_mutation_stale_capsule", asymmetric, state, requirements, cmd, "THERMAL_FILTER_RUNTIME_FRONTIER_MISMATCH", "FULL", damaged_stale)
	var bad_capsule = Backend.new()
	bad_capsule.cached_candidate = candidate.duplicate(true)
	bad_capsule.cached_candidate.capsule.checksum = "0".repeat(64)
	reject_case("corrupt_capsule", src, state, requirements, cmd, "BAKE_CHECKSUM_MISMATCH", "FULL", bad_capsule)
	var invalidated := src.duplicate(true)
	invalidated.live.artifact_state = "STALE"
	reject_case("physical_stale", invalidated, state, requirements, cmd, "THERMAL_FILTER_RUNTIME_ARTIFACT_NOT_READY")
	var cross := src.duplicate(true)
	var a: Dictionary = cross.request.authority_envelope
	var recs: Array = a.source_authority_frontier.duplicate(true)
	recs[0].owner_id = "server/other-owner"
	cross.request.authority_envelope = Authority.create(a.execution_owner, recs, a.mutable_source_ids)
	reject_case("cross_authority", cross, state, requirements, cmd, "AUTHORITY_ENVELOPE_CROSSED", "CANONICAL_HANDOFF_REQUIRED")
	var epoch := src.duplicate(true)
	recs = epoch.request.authority_envelope.source_authority_frontier.duplicate(true)
	recs[0].authority_epoch = 16
	epoch.request.authority_envelope = Authority.create(a.execution_owner, recs, a.mutable_source_ids)
	reject_case("authority_epoch_mismatch", epoch, state, requirements, cmd, "T16_AUTHORITY_EPOCH_MISMATCH", "CANONICAL_HANDOFF_REQUIRED")
	var wrong_source := src.duplicate(true)
	wrong_source.graph.graph_hash = "0".repeat(64)
	reject_case("canonical_source_mismatch", wrong_source, state, requirements, cmd, "T16_CANONICAL_SOURCE_HASH_MISMATCH", "CANONICAL_HANDOFF_REQUIRED")
	# F2 siblings: change ONLY current live truth; request remains old and valid.
	var live_cross := src.duplicate(true)
	recs = a.source_authority_frontier.duplicate(true)
	recs[0].owner_id = "server/other-owner"
	live_cross.live.authority_envelope = Authority.create(a.execution_owner, recs, a.mutable_source_ids)
	reject_case("live_cross_authority", live_cross, state, requirements, cmd, "AUTHORITY_ENVELOPE_CROSSED", "CANONICAL_HANDOFF_REQUIRED")
	var live_epoch := src.duplicate(true)
	recs = a.source_authority_frontier.duplicate(true)
	recs[0].authority_epoch = 16
	live_epoch.live.authority_envelope = Authority.create(a.execution_owner, recs, a.mutable_source_ids)
	reject_case("live_epoch_mismatch", live_epoch, state, requirements, cmd, "T16_AUTHORITY_EPOCH_MISMATCH", "CANONICAL_HANDOFF_REQUIRED")
	var live_advanced := src.duplicate(true)
	live_advanced.live.canonical_source_frontier = Backend.source(graph, 1).live.canonical_source_frontier
	reject_case("live_frontier_advanced", live_advanced, state, requirements, cmd, "T16_LIVE_PROVENANCE_MISMATCH", "CANONICAL_HANDOFF_REQUIRED")
	var live_missing := src.duplicate(true)
	live_missing.live = {}
	reject_case("live_missing", live_missing, state, requirements, cmd, "T16_LIVE_PROVENANCE_MISSING", "CANONICAL_HANDOFF_REQUIRED")
	var live_missing_owner := src.duplicate(true)
	live_missing_owner.live.erase("authority_envelope")
	reject_case("live_missing_authority", live_missing_owner, state, requirements, cmd, "T16_LIVE_PROVENANCE_MISSING", "CANONICAL_HANDOFF_REQUIRED")
	var live_deps := src.duplicate(true)
	live_deps.live.dependency_set = Dependencies.create([{"dependency_id":"dependency/t16-revised", "dependency_hash":"a".repeat(64)}])
	reject_case("live_dependency_mismatch", live_deps, state, requirements, cmd, "T16_LIVE_PROVENANCE_MISMATCH", "CANONICAL_HANDOFF_REQUIRED")
	var live_graph := src.duplicate(true)
	live_graph.live.graph_hash = "0".repeat(64)
	reject_case("live_graph_mismatch", live_graph, state, requirements, cmd, "T16_LIVE_GRAPH_MISMATCH", "CANONICAL_HANDOFF_REQUIRED")
	var live_material := src.duplicate(true)
	live_material.live.material_catalog_hash = "0".repeat(64)
	reject_case("live_material_mismatch", live_material, state, requirements, cmd, "T16_LIVE_MATERIAL_MISMATCH", "CANONICAL_HANDOFF_REQUIRED")
	var live_new_owner := src.duplicate(true)
	recs = a.source_authority_frontier.duplicate(true)
	for record in recs: record.owner_id = "server/new-owner"
	live_new_owner.live.authority_envelope = Authority.create("server/new-owner", recs, a.mutable_source_ids)
	reject_case("live_owner_changed", live_new_owner, state, requirements, cmd, "T16_LIVE_PROVENANCE_MISMATCH", "CANONICAL_HANDOFF_REQUIRED")
	# F3: unsupported extra fields must not be silently truncated by the native
	# detailed solver. Existing source kernels remain unmodified.
	var extended := state.duplicate(true)
	extended.hidden_reservoir = {"energy_j":12.5, "revision":1}
	reject_case("extended_full_state", src, extended, requirements, cmd, "RECONSTRUCTION_NOT_EXACT", "FULL_STEP_REFUSED")
	var wrong_array := {"cell_temperature_k":"not-an-array"}
	reject_case("full_wrong_array", src, wrong_array, requirements, cmd, "THERMAL_STATE_PROJECTOR_STATE_INVALID", "FULL_STEP_REFUSED")
	var short_state := state.duplicate(true)
	short_state.cell_temperature_k.pop_back()
	reject_case("full_wrong_count", src, short_state, requirements, cmd, "THERMAL_STATE_PROJECTOR_STATE_INVALID", "FULL_STEP_REFUSED")
	var nonfinite_state := state.duplicate(true)
	nonfinite_state.cell_temperature_k[0] = NAN
	reject_case("full_nonfinite_state", src, nonfinite_state, requirements, cmd, "THERMAL_STATE_PROJECTOR_STATE_INVALID", "FULL_STEP_REFUSED")
	var outside_domain := state.duplicate(true)
	outside_domain.cell_temperature_k[0] = float(plan.details.max_temperature_k) + 1.0
	reject_case("full_out_of_domain", src, outside_domain, requirements, cmd, "THERMAL_STATE_PROJECTOR_TEMPERATURE_OUT_OF_DOMAIN", "FULL_STEP_REFUSED")
	reject_case("missing_full_state", src, {}, requirements, cmd, "THERMAL_STATE_PROJECTOR_STATE_INVALID", "FULL_STEP_REFUSED")
	reject_case("compact_step_failure", src, state, requirements, cmd, "T16_COMPACT_STEP_REFUSED", "COMPACT_STEP_REFUSED", FailingCompact.new())
	# A rejected attempt consumes no canonical ID / registry binding. An unchanged
	# caller state can retry with a corrected contract, without resetting physics.
	var corrected := Gate.attempt(Backend.new(), src, state, cmd, requirements)
	check(corrected.success and corrected.details.status == "BAKE_READY", "corrected retry after rejection succeeds")
	check(base_hash == Gate.binary_hash([src, state, cmd, requirements]), "all adversaries leave baseline input byte-exact")
	# Invalid physical state is not magically made executable by refusing BAKE.
	var invalid_state := state.duplicate(true)
	invalid_state.cell_temperature_k[0] = -1.0
	reject_case("invalid_physical_state", src, invalid_state, requirements, cmd, "THERMAL_STATE_PROJECTOR_STATE_INVALID", "FULL_STEP_REFUSED")
	var invalid_req := requirements.duplicate(true)
	invalid_req.max_boundary_error = -1.0
	var unused := Backend.new()
	var invalid_request := Gate.attempt(unused, src, state, cmd, invalid_req)
	check(not invalid_request.success and invalid_request.error_code == "T16_REQUIREMENTS_INVALID", "malformed protocol request rejected")
	check(unused.candidate_calls == 0 and unused.full_calls == 0 and unused.compact_calls == 0, "invalid protocol request executes nothing")
	measure.end_stage("refusal_and_full_continuation")
	measure.begin_stage("singular_existing_reducer")
	var singular := T1F.build(0, true)
	var before := Gate.binary_hash(singular)
	var reduced := T1C.compile(singular.graph, singular.request, "capsule/r5-t16-singular")
	check(reduced.get("status") == "NO_SAFE_BAKE" and reduced.get("reason") == "RANK_DEFICIENCY", "existing T1 singular reducer refuses", reduced)
	check(reduced.get("artifact", {}).is_empty(), "singular refusal exposes no artifact")
	check(Gate.binary_hash(singular) == before, "singular refusal preserves canonical component graph")
	cases.singular_elimination = {"reason":String(reduced.get("reason", "")), "execution":"FULL_SOLVER_DIAGNOSTIC_REQUIRED", "artifact_empty":reduced.get("artifact", {}).is_empty()}
	measure.end_stage("singular_existing_reducer")
	finish()

func finish() -> void:
	var result := {"schema":"fabric.t16.result.v1", "checks":checks, "failures":failures,
		"cases":cases, "case_count":cases.size(), "source_cells":128, "compact_states":8,
		"positive_variants":positive_traces.size(), "positive_trace_hash":U.canonical_hash(positive_traces),
		"full_continuation_ticks":full_continuation_ticks, "fallback_source_cell_updates":fallback_updates,
		"full_events_observed":event_count, "max_energy_residual_j":max_energy_residual,
		"max_positive_boundary_error_k":max_boundary_error,
		"repair_r2":{"temporal_pairs":temporal_pairs.size(), "temporal_compact_pairs":temporal_compact_pairs,
			"temporal_full_pairs":temporal_full_pairs, "max_temporal_output_error_k":max_temporal_output_error,
			"r1_f1_discrepancy_k":r1_f1_gap, "temporal_trace_hash":U.canonical_hash(temporal_pairs)}}
	measure.set_counter("case_count", cases.size())
	measure.set_counter("fallback_source_cell_updates", fallback_updates)
	var measured := measure.finish({"case_count":cases.size(), "positive_trace_hash":U.canonical_hash(positive_traces), "full_continuation_ticks":full_continuation_ticks}, {"scope":"negotiation plus one selected physical step; not a steady-state scaling campaign"})
	check(measured.success and U.is_lower_hex_64(String(measured.details.deterministic_hash)), "R5.0 measurement has a valid deterministic identity")
	result.checks = checks
	result.failures = failures
	print("FABRIC_R5_2_T16_RESULT=" + JSON.stringify(result, "", true, true))
	print("FABRIC_R5_2_T16_MEASUREMENT=" + JSON.stringify(measured, "", true, true))
	print("FABRIC R5.2 T16 NO SAFE BAKE: " + ("PASS" if failures.is_empty() else "FAIL") + " (%d assertions)" % checks)
	quit(0 if failures.is_empty() else 1)
