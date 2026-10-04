extends RefCounted
## T16 bounded negotiation + ONE physical step, not a per-tick compiler.
## Backend is a trusted in-process research adapter over existing reducers.
## Source/state stay caller-owned. There is no registry, revision or event owner.
## A declined candidate is never returned or executed; FULL is not a success
## substitute when state, authority or the detailed solver are unavailable.
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const Authority = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const Dependencies = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")

const SCHEMA := "planet_simulator.fabric_t16_attempt.v1"
const REQUIREMENTS: Array[String] = ["observables", "events", "max_boundary_error", "minimum_step_margin"]

static func binary_hash(value) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(var_to_bytes(value))
	return h.finish().hex_encode()

static func _requirements_valid(r: Dictionary) -> bool:
	if not U.validate_exact_fields(r, REQUIREMENTS).success:
		return false
	for field in ["observables", "events"]:
		if not U.validate_sorted_unique_strings(r.get(field), field == "events").success:
			return false
	return U.is_non_negative_number(r.get("max_boundary_error")) and U.is_positive_number(r.get("minimum_step_margin")) and float(r.minimum_step_margin) < 1.0

static func _provenance_gate(envelope: Dictionary, graph: Dictionary, missing_code: String) -> Dictionary:
	for field in ["canonical_source_frontier", "authority_envelope", "dependency_set"]:
		if typeof(envelope.get(field)) != TYPE_DICTIONARY:
			return U.failure(missing_code)
	var checked := Frontier.validate(envelope.canonical_source_frontier)
	if not checked.success:
		return checked
	checked = Authority.validate_b0_safety(envelope.authority_envelope)
	if not checked.success:
		return checked
	checked = Dependencies.validate(envelope.dependency_set)
	if not checked.success:
		return checked
	# Both request and current live provenance must bind the supplied graph.
	# Neither is a new authority owner: reuse canonical records/epochs verbatim.
	var graph_bound := false
	var matter_bound: bool = not graph.has("material_catalog")
	for record in envelope.canonical_source_frontier.sources:
		if record.source_domain == "CONSTRUCTION" and record.source_hash == graph.get("graph_hash"):
			graph_bound = true
		if record.source_domain == "MATTER" and record.source_hash == graph.get("material_catalog", {}).get("catalog_hash"):
			matter_bound = true
	if not graph_bound or not matter_bound:
		return U.failure("T16_CANONICAL_SOURCE_HASH_MISMATCH")
	var records: Array = envelope.authority_envelope.source_authority_frontier
	if records.size() != envelope.canonical_source_frontier.sources.size():
		return U.failure("T16_AUTHORITY_SOURCE_COVERAGE_MISMATCH")
	for record in envelope.canonical_source_frontier.sources:
		if Authority.authority_epoch_for(envelope.authority_envelope, String(record.source_domain), String(record.source_id)) != int(record.authority_epoch):
			return U.failure("T16_AUTHORITY_EPOCH_MISMATCH")
	return U.success()

static func _source_gate(source: Dictionary) -> Dictionary:
	for field in ["graph", "request", "live"]:
		if typeof(source.get(field)) != TYPE_DICTIONARY:
			return U.failure("T16_SOURCE_SHAPE_INVALID")
	if source.graph.has("material_catalog") and typeof(source.graph.material_catalog) != TYPE_DICTIONARY:
		return U.failure("T16_SOURCE_SHAPE_INVALID")
	var checked := _provenance_gate(source.request, source.graph, "T16_SOURCE_PROVENANCE_MISSING")
	if not checked.success:
		return checked
	checked = _provenance_gate(source.live, source.graph, "T16_LIVE_PROVENANCE_MISSING")
	if not checked.success:
		return checked
	# Stale CURRENT source is a handoff, not permission to run FULL on an old
	# graph. Only an obsolete candidate with fresh matched source may fall back.
	for field in ["canonical_source_frontier", "authority_envelope", "dependency_set"]:
		if source.live[field] != source.request[field]:
			return U.failure("T16_LIVE_PROVENANCE_MISMATCH")
	if not U.is_lower_hex_64(source.live.get("graph_hash")) or source.live.graph_hash != source.graph.get("graph_hash"):
		return U.failure("T16_LIVE_GRAPH_MISMATCH")
	if source.graph.has("material_catalog"):
		if not U.is_lower_hex_64(source.live.get("material_catalog_hash")) or source.live.material_catalog_hash != source.graph.material_catalog.get("catalog_hash"):
			return U.failure("T16_LIVE_MATERIAL_MISMATCH")
	return U.success()

static func _refusal(reason: String, cause: Dictionary = {}) -> Dictionary:
	return {"status":"NO_SAFE_BAKE", "reason":reason, "cause":cause.duplicate(true), "artifact":{}}

static func _decide(backend, source: Dictionary, state: Dictionary, command: Dictionary, requirements: Dictionary) -> Dictionary:
	# All candidate work belongs to a disposable probe, not a live family.
	var probe: Dictionary = backend.prepare_candidate(source.duplicate(true), state.duplicate(true), command.duplicate(true))
	if not bool(probe.get("success", false)):
		return _refusal(String(probe.get("error_code", "T16_CANDIDATE_REJECTED")), probe.get("details", {}))
	if typeof(probe.get("details")) != TYPE_DICTIONARY:
		return _refusal("T16_CERTIFICATE_SHAPE_INVALID")
	var p: Dictionary = probe.details
	for field in ["reconstructed_state", "compact_state", "candidate"]:
		if typeof(p.get(field)) != TYPE_DICTIONARY:
			return _refusal("RECONSTRUCTION_UNAVAILABLE")
	# An approximate projection is not permission to erase hidden physical state.
	# T16's handoff is EXACT; lossy state projection remains unsupported.
	if binary_hash(p.reconstructed_state) != binary_hash(state):
		return _refusal("RECONSTRUCTION_NOT_EXACT")
	for field in ["observables", "events"]:
		if not U.validate_sorted_unique_strings(p.get(field), field == "events").success:
			return _refusal("T16_CERTIFICATE_SHAPE_INVALID")
		for needed in requirements[field]:
			if not p[field].has(needed):
				return _refusal("INSUFFICIENT_OBSERVABILITY" if field == "observables" else "UNRESOLVED_HIDDEN_EVENT", {"missing":needed})
	if not U.is_non_negative_number(p.get("boundary_error_bound")) or float(p.boundary_error_bound) > float(requirements.max_boundary_error):
		return _refusal("UNSAFE_ERROR_ENVELOPE")
	if not U.is_finite_number(p.get("step_margin")) or float(p.step_margin) < float(requirements.minimum_step_margin):
		return _refusal("NEAR_CRITICAL_DYNAMICS")
	# A one-step error certificate cannot certify a different detailed temporal
	# discretization. This fact is derived by the trusted adapter's shared policy.
	if typeof(p.get("temporal_policy_matches")) != TYPE_BOOL or not p.temporal_policy_matches:
		return _refusal("T16_TEMPORAL_POLICY_UNSUPPORTED")
	# The adapter must validate the actual artifact/descriptor/source binding,
	# not a test flag. This second gate also catches a stale cached candidate.
	var checked: Dictionary = backend.validate_candidate(p.candidate, source.duplicate(true))
	if not checked.success:
		return _refusal(String(checked.get("error_code", "T16_CANDIDATE_INVALID")))
	return {"status":"BAKE_READY", "reason":"", "probe":p}

static func attempt(backend, source: Dictionary, full_state: Dictionary, command: Dictionary, requirements: Dictionary) -> Dictionary:
	if backend == null:
		return U.failure("T16_BACKEND_MISSING")
	for method in ["prepare_candidate", "validate_candidate", "execute_compact", "execute_full"]:
		if not backend.has_method(method):
			return U.failure("T16_BACKEND_CONTRACT_INVALID", {"method":method})
	if not _requirements_valid(requirements):
		return U.failure("T16_REQUIREMENTS_INVALID")
	var source_before := binary_hash(source)
	var state_before := binary_hash(full_state)
	var gate := _source_gate(source)
	# FULL is not an authority bypass. Invalid provenance requires the canonical
	# owner to supply a valid source/handoff; no physical executor is invoked.
	if not gate.success:
		return U.success({
			"schema":SCHEMA, "status":"NO_SAFE_BAKE", "reason":String(gate.error_code),
			"execution":"CANONICAL_HANDOFF_REQUIRED", "artifact":{}, "physical":{},
			"source_hash_before":source_before, "source_hash_after":binary_hash(source),
			"state_hash_before":state_before, "state_hash_after":binary_hash(full_state),
			"compact_calls":0, "full_calls":0,
		})
	var decision := _decide(backend, source, full_state, command, requirements)
	var compact := String(decision.status) == "BAKE_READY"
	var stepped: Dictionary
	if compact:
		stepped = backend.execute_compact(decision.probe, source.duplicate(true), command.duplicate(true))
	else:
		stepped = backend.execute_full(source.duplicate(true), full_state.duplicate(true), command.duplicate(true))
	# A compact-step failure must not trigger a second physical executor. There
	# may already be events or numerical work: return a required handoff instead.
	var execution := "COMPACT" if compact else "FULL"
	if not bool(stepped.get("success", false)):
		execution = "COMPACT_STEP_REFUSED" if compact else "FULL_STEP_REFUSED"
	if compact and not bool(stepped.get("success", false)):
		decision = _refusal("T16_COMPACT_STEP_REFUSED")
	var result := {
		"schema":SCHEMA,
		"status":String(decision.status),
		"reason":String(decision.reason),
		"execution":execution,
		"artifact":decision.probe.candidate.duplicate(true) if compact and decision.status == "BAKE_READY" else {},
		"physical":stepped.get("details", {}).duplicate(true) if bool(stepped.get("success", false)) else {},
		"execution_error":String(stepped.get("error_code", "")),
		"source_hash_before":source_before, "source_hash_after":binary_hash(source),
		"state_hash_before":state_before, "state_hash_after":binary_hash(full_state),
		"compact_calls":1 if compact else 0, "full_calls":0 if compact else 1,
	}
	if source_before != binary_hash(source) or state_before != binary_hash(full_state):
		return U.failure("T16_CALLER_INPUT_MUTATED")
	return U.success(result)
