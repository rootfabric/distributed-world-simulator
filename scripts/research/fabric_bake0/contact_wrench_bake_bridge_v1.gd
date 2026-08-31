class_name FabricBakeContactWrenchBridgeV1
extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Compiler = preload("res://scripts/research/fabric_bake0/contact_wrench_bake_compiler_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/contact_wrench_bake_runtime_v1.gd")
const FoundationCompiler = preload("res://scripts/research/fabric_bake0/fabric_bake_foundation_compiler_v1.gd")
const BoundaryContract = preload("res://scripts/research/fabric_bake0/physical_boundary_contract_v1.gd")
const DependencySet = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")
const ValidatedDomain = preload("res://scripts/research/fabric_bake0/validated_domain_v1.gd")
const ErrorEnvelope = preload("res://scripts/research/fabric_bake0/error_envelope_v1.gd")
const ConservationEnvelope = preload("res://scripts/research/fabric_bake0/conservation_envelope_v1.gd")
const ReconstructionDescriptor = preload("res://scripts/research/fabric_bake0/reconstruction_descriptor_v1.gd")
const StateMapping = preload("res://scripts/research/fabric_bake0/bake_state_mapping_v1.gd")
const BakeExecutionGate = preload("res://scripts/research/fabric_bake0/bake_execution_gate_v1.gd")

const KIND := "B0_3_BRIDGE1_CONTACT_WRENCH_BUNDLE"
const STATUS_READY := "B0_3_BAKE_READY"
const BRIDGE1_KIND := "BRIDGE1_PHYSICAL_SOURCE_LIFECYCLE_BUNDLE"
const READY_STATUSES := ["BRIDGE1_BAKE_READY", "BRIDGE1_REBUILT_BAKE_READY"]
const NUMERIC_TOLERANCE := 2.0e-10

static func compile(parent_bundle: Dictionary, contact_request: Dictionary, options: Dictionary = {}) -> Dictionary:
	var checked := _validate_parent_bundle(parent_bundle)
	if not bool(checked.get("ok", false)):
		return checked
	if String(contact_request.get("artifact_id", "")).is_empty():
		return {"ok": false, "code": "B0_3_PHYSICAL_ARTIFACT_ID_REQUIRED"}
	var model_request := contact_request.duplicate(true)
	model_request.erase("artifact_id")
	model_request["source_frontier_hash"] = String(parent_bundle["source_view"]["frontier"]["frontier_hash"])
	model_request["physical_graph_hash"] = String(parent_bundle["physical_graph"]["graph_hash"])
	model_request["parent_artifact_checksum"] = String(parent_bundle["artifact"]["checksum"])
	model_request["authority_checksum"] = String(parent_bundle["source_view"]["authority_envelope"]["checksum"])
	var model_result := Compiler.compile(model_request)
	if not bool(model_result.get("ok", false)):
		return model_result
	var model: Dictionary = model_result["model"]
	var dependencies := _dependencies(parent_bundle)
	if dependencies.is_empty():
		return {"ok": false, "code": "B0_3_DEPENDENCY_SET_BUILD_FAILED"}
	var boundary := _boundary_contract()
	if boundary.is_empty():
		return {"ok": false, "code": "B0_3_BOUNDARY_CONTRACT_BUILD_FAILED"}
	var frontier_hash := String(parent_bundle["source_view"]["frontier"]["frontier_hash"])
	var graph_hash := String(parent_bundle["physical_graph"]["graph_hash"])
	var validated := ValidatedDomain.create(frontier_hash, graph_hash, [], ["CONTACT_WRENCH"], float(options.get("time_horizon_s", 1.0)))
	if validated.is_empty():
		return {"ok": false, "code": "B0_3_VALIDATED_DOMAIN_BUILD_FAILED"}
	var error_envelope := ErrorEnvelope.create(
		NUMERIC_TOLERANCE, 0.0, 0.0, 0.0,
		NUMERIC_TOLERANCE, 0.0, 0.0, 0.0,
		0.0, NUMERIC_TOLERANCE, 1.0e-9, float(options.get("time_horizon_s", 1.0)), true
	)
	if error_envelope.is_empty():
		return {"ok": false, "code": "B0_3_ERROR_ENVELOPE_BUILD_FAILED"}
	var conservation := ConservationEnvelope.create(NUMERIC_TOLERANCE, 0.0, NUMERIC_TOLERANCE, NUMERIC_TOLERANCE, 0.0)
	if conservation.is_empty():
		return {"ok": false, "code": "B0_3_CONSERVATION_ENVELOPE_BUILD_FAILED"}
	var source_keys: Array = []
	for source_any in parent_bundle["source_view"]["frontier"]["sources"]:
		var source: Dictionary = source_any
		source_keys.append(Utils.source_key(String(source["source_domain"]), String(source["source_id"])))
	source_keys.sort()
	var reconstruction := ReconstructionDescriptor.create(
		String(options.get("reconstruction_descriptor_id", "reconstruction/b0-3-contact-wrench")),
		frontier_hash,
		String(model["model_hash"]),
		"CANONICAL_ONLY",
		[{"region_id": "region/b0-3-contact-patch", "source_keys": source_keys}],
		"STRICT",
		Utils.canonical_hash({"policy": "discard-and-rederive-contact-state", "physical_core": Compiler.FABRIC0_18_EXACT_PHYSICS}),
		"FABRIC_BAKE_B0_3_CONTACT_WRENCH_R1"
	)
	if reconstruction.is_empty():
		return {"ok": false, "code": "B0_3_RECONSTRUCTION_DESCRIPTOR_BUILD_FAILED"}
	var reduced_state_schema_hash := Utils.canonical_hash({"schema": "planet_simulator.fabric_bake_b0_3_stateless_wrench_envelope.v1", "persistent_state": false})
	var state_mapping := StateMapping.create(
		String(options.get("state_mapping_id", "state-mapping/b0-3-contact-wrench")),
		Utils.canonical_hash({"schema": "fabric0.18.persistent_contact_wrench_state", "solver_assist_is_transient": true}),
		reduced_state_schema_hash,
		String(model["model_hash"]),
		String(reconstruction["checksum"])
	)
	if state_mapping.is_empty():
		return {"ok": false, "code": "B0_3_STATE_MAPPING_BUILD_FAILED"}
	var bake_policy_hash := Utils.canonical_hash({
		"compiler_version": Compiler.COMPILER_VERSION,
		"accepted_domain": model["accepted_domain"],
		"model_hash": model["model_hash"],
		"transient_contact_state": "DISCARD_AND_REDERIVE",
	})
	var artifact_result := FoundationCompiler.compile({
		"artifact_id": String(contact_request["artifact_id"]),
		"reduction_class": "EXACT",
		"canonical_source_frontier": parent_bundle["source_view"]["frontier"],
		"authority_envelope": parent_bundle["source_view"]["authority_envelope"],
		"dependency_set": dependencies,
		"fabric_graph_hash": graph_hash,
		"fabric_compiler_version": String(parent_bundle["artifact"]["source_binding"]["fabric_compiler_version"]),
		"boundary_contract": boundary,
		"bake_policy_hash": bake_policy_hash,
		"reduced_model_descriptor_hash": String(model["model_hash"]),
		"reduced_state_schema_hash": reduced_state_schema_hash,
		"validated_domain": validated,
		"error_envelope": error_envelope,
		"conservation_envelope": conservation,
		"refinement_guards": [],
		"reconstruction_descriptor": reconstruction,
		"state_mapping": state_mapping,
		"build_generation": int(options.get("build_generation", 1)),
		"error_certified": true,
		"refinement_guard_certified": true,
		"complexity_reduction_certified": true,
	})
	if String(artifact_result.get("status", "")) != "BAKE_READY":
		return {"ok": false, "code": "B0_3_FOUNDATION_COMPILE_NOT_READY", "detail": artifact_result}
	return {
		"ok": true,
		"status": STATUS_READY,
		"kind": KIND,
		"artifact": artifact_result["artifact"],
		"wrench_model": model,
		"dependency_set": dependencies,
		"parent_artifact_id": String(parent_bundle["artifact"]["artifact_id"]),
		"parent_artifact_checksum": String(parent_bundle["artifact"]["checksum"]),
		"contact_state_policy": "TRANSIENT_SOLVER_ASSIST_DISCARD_AND_REDERIVE",
	}

static func can_execute(parent_bundle: Dictionary, b0_3_bundle: Dictionary, elapsed_s: float = 0.0, invalidations: Array = []) -> Dictionary:
	var checked := _validate_parent_bundle(parent_bundle)
	if not bool(checked.get("ok", false)):
		return checked
	checked = _validate_b0_3_bundle(b0_3_bundle)
	if not bool(checked.get("ok", false)):
		return checked
	var model: Dictionary = b0_3_bundle["wrench_model"]
	if String(model["source_frontier_hash"]) != String(parent_bundle["source_view"]["frontier"]["frontier_hash"]):
		return {"ok": false, "code": "B0_3_SOURCE_FRONTIER_MISMATCH"}
	if String(model["physical_graph_hash"]) != String(parent_bundle["physical_graph"]["graph_hash"]):
		return {"ok": false, "code": "B0_3_PHYSICAL_GRAPH_MISMATCH"}
	if String(model["parent_artifact_checksum"]) != String(parent_bundle["artifact"]["checksum"]):
		return {"ok": false, "code": "B0_3_PARENT_ARTIFACT_MISMATCH"}
	if String(model["authority_checksum"]) != String(parent_bundle["source_view"]["authority_envelope"]["checksum"]):
		return {"ok": false, "code": "B0_3_AUTHORITY_MISMATCH"}
	var parent_gate := BakeExecutionGate.can_execute(parent_bundle["artifact"], _parent_live(parent_bundle, elapsed_s, invalidations))
	if not bool(parent_gate.get("success", false)):
		return {"ok": false, "code": "B0_3_PARENT_EXECUTION_FORBIDDEN", "parent_gate": parent_gate}
	var own_gate := BakeExecutionGate.can_execute(b0_3_bundle["artifact"], _own_live(parent_bundle, b0_3_bundle, elapsed_s, invalidations))
	if not bool(own_gate.get("success", false)):
		return {"ok": false, "code": "B0_3_EXECUTION_FORBIDDEN", "b0_3_gate": own_gate}
	return {"ok": true, "parent_gate": parent_gate, "b0_3_gate": own_gate}

static func support(parent_bundle: Dictionary, b0_3_bundle: Dictionary, direction: Array, elapsed_s: float = 0.0, invalidations: Array = []) -> Dictionary:
	var gate := can_execute(parent_bundle, b0_3_bundle, elapsed_s, invalidations)
	if not bool(gate.get("ok", false)):
		return gate
	var result := Runtime.support(b0_3_bundle["wrench_model"], direction)
	if not bool(result.get("ok", false)):
		return result
	var out := result.duplicate(true)
	out["parent_gate"] = gate["parent_gate"]
	out["b0_3_gate"] = gate["b0_3_gate"]
	out["artifact_id"] = String(b0_3_bundle["artifact"]["artifact_id"])
	return out

static func maximum_dissipation_wrench(parent_bundle: Dictionary, b0_3_bundle: Dictionary, twist: Array, elapsed_s: float = 0.0, invalidations: Array = []) -> Dictionary:
	var gate := can_execute(parent_bundle, b0_3_bundle, elapsed_s, invalidations)
	if not bool(gate.get("ok", false)):
		return gate
	var result := Runtime.maximum_dissipation_wrench(b0_3_bundle["wrench_model"], twist)
	if not bool(result.get("ok", false)):
		return result
	var out := result.duplicate(true)
	out["parent_gate"] = gate["parent_gate"]
	out["b0_3_gate"] = gate["b0_3_gate"]
	return out

static func observe_persistent_contact_state(parent_bundle: Dictionary, b0_3_bundle: Dictionary, contact_state: Dictionary, elapsed_s: float = 0.0, invalidations: Array = []) -> Dictionary:
	var gate := can_execute(parent_bundle, b0_3_bundle, elapsed_s, invalidations)
	if not bool(gate.get("ok", false)):
		return gate
	if not bool(contact_state.get("ok", false)) or String(contact_state.get("kind", "")) != "PERSISTENT_WRENCH_CONTACT_STATE":
		return {"ok": false, "code": "B0_3_BAD_TRANSIENT_CONTACT_STATE"}
	return {
		"ok": true,
		"kind": "B0_3_TRANSIENT_CONTACT_OBSERVATION",
		"canonical_mutation": false,
		"source_revision_changed": false,
		"artifact_invalidation": false,
		"accepted_impulse_persisted": false,
		"warm_start_persisted": false,
		"contact_age_persisted": false,
		"mode_history_persisted": false,
		"state_retention": "TRANSIENT_SOLVER_ASSIST_ONLY",
		"rebuild_policy": "DISCARD_AND_REDERIVE_CONTACT_STATE",
		"pair_id": String(contact_state.get("pair_id", "")),
		"manifold_identity": String(contact_state.get("manifold_identity", "")),
	}

static func _dependencies(parent_bundle: Dictionary) -> Dictionary:
	var deps: Array = []
	for dependency_any in parent_bundle["dependency_set"]["dependencies"]:
		deps.append(Dictionary(dependency_any).duplicate(true))
	deps.append({
		"dependency_id": "dependency/fabric-core-0-18",
		"dependency_hash": Utils.canonical_hash({"closure": Compiler.FABRIC0_18_CLOSURE, "exact_physics": Compiler.FABRIC0_18_EXACT_PHYSICS}),
	})
	deps.append({
		"dependency_id": "dependency/fabric-bake-bridge1",
		"dependency_hash": Utils.canonical_hash({"closure": Compiler.BRIDGE1_CLOSURE, "parent_artifact_checksum": parent_bundle["artifact"]["checksum"]}),
	})
	return DependencySet.create(deps)

static func _boundary_contract() -> Dictionary:
	return BoundaryContract.create([
		{
			"port_id": "port/b0-3-contact-force",
			"physical_domain": "MECHANICAL",
			"effort_quantity": "quantity/force",
			"flow_quantity": "quantity/linear-velocity",
			"effort_dimension": [1, 1, -2, 0, 0, 0, 0],
			"flow_dimension": [0, 1, -1, 0, 0, 0, 0],
			"frame": "frame/b0-3-contact",
			"orientation": "INTO_SUBSYSTEM",
			"conservation_group": "group/b0-3-contact-wrench",
			"event_observables": ["STICK_TO_SLIDE", "SUPPORT_TO_SEPARATION", "WRENCH_CAPACITY_EXIT"],
		},
		{
			"port_id": "port/b0-3-contact-torque",
			"physical_domain": "MECHANICAL",
			"effort_quantity": "quantity/torque",
			"flow_quantity": "quantity/angular-velocity",
			"effort_dimension": [1, 2, -2, 0, 0, 0, 0],
			"flow_dimension": [0, 0, -1, 0, 0, 0, 0],
			"frame": "frame/b0-3-contact",
			"orientation": "INTO_SUBSYSTEM",
			"conservation_group": "group/b0-3-contact-wrench",
			"event_observables": ["STICK_TO_ROLL", "STICK_TO_SPIN", "SUPPORT_TO_SEPARATION", "WRENCH_CAPACITY_EXIT"],
		},
	])

static func _validate_parent_bundle(bundle: Dictionary) -> Dictionary:
	if String(bundle.get("kind", "")) != BRIDGE1_KIND:
		return {"ok": false, "code": "B0_3_BAD_BRIDGE1_BUNDLE"}
	if not READY_STATUSES.has(String(bundle.get("status", ""))):
		return {"ok": false, "code": "B0_3_BRIDGE1_BUNDLE_NOT_READY"}
	for key in ["source_view", "physical_graph", "artifact", "dependency_set"]:
		if not bundle.has(key) or not (bundle[key] is Dictionary):
			return {"ok": false, "code": "B0_3_INCOMPLETE_BRIDGE1_BUNDLE", "field": key}
	for path in [
		["source_view", "frontier"], ["source_view", "authority_envelope"],
		["artifact", "source_binding"], ["artifact", "boundary_contract"],
	]:
		if not (Dictionary(bundle[path[0]]).get(path[1], null) is Dictionary):
			return {"ok": false, "code": "B0_3_INCOMPLETE_BRIDGE1_BUNDLE", "field": "%s.%s" % [path[0], path[1]]}
	return {"ok": true}

static func _validate_b0_3_bundle(bundle: Dictionary) -> Dictionary:
	if String(bundle.get("kind", "")) != KIND or String(bundle.get("status", "")) != STATUS_READY:
		return {"ok": false, "code": "B0_3_BAD_BUNDLE"}
	for key in ["artifact", "wrench_model", "dependency_set"]:
		if not bundle.has(key) or not (bundle[key] is Dictionary):
			return {"ok": false, "code": "B0_3_INCOMPLETE_BUNDLE", "field": key}
	var checked := Compiler.validate_model(bundle["wrench_model"])
	if not bool(checked.get("ok", false)):
		return checked
	return {"ok": true}

static func _parent_live(bundle: Dictionary, elapsed_s: float, invalidations: Array) -> Dictionary:
	var guards: Dictionary = {}
	for guard_any in bundle["artifact"]["refinement_guards"]:
		var guard: Dictionary = guard_any
		guards[String(guard["guard_id"])] = 0.0
	return {
		"artifact_state": "READY",
		"canonical_source_frontier": bundle["source_view"]["frontier"],
		"authority_envelope": bundle["source_view"]["authority_envelope"],
		"dependency_set": bundle["dependency_set"],
		"fabric_graph_hash": bundle["physical_graph"]["graph_hash"],
		"fabric_compiler_version": bundle["artifact"]["source_binding"]["fabric_compiler_version"],
		"boundary_contract_hash": bundle["artifact"]["boundary_contract"]["contract_hash"],
		"bake_policy_hash": bundle["artifact"]["source_binding"]["bake_policy_hash"],
		"runtime_domain": {
			"source_frontier_hash": bundle["source_view"]["frontier"]["frontier_hash"],
			"fabric_graph_hash": bundle["physical_graph"]["graph_hash"],
			"elapsed_s": elapsed_s,
			"mode": "RIGID",
			"quantities": {},
		},
		"runtime_error_estimator": _parent_estimator(elapsed_s),
		"guard_values": guards,
		"invalidations": invalidations,
	}

static func _own_live(parent_bundle: Dictionary, bundle: Dictionary, elapsed_s: float, invalidations: Array) -> Dictionary:
	return {
		"artifact_state": "READY",
		"canonical_source_frontier": parent_bundle["source_view"]["frontier"],
		"authority_envelope": parent_bundle["source_view"]["authority_envelope"],
		"dependency_set": bundle["dependency_set"],
		"fabric_graph_hash": parent_bundle["physical_graph"]["graph_hash"],
		"fabric_compiler_version": bundle["artifact"]["source_binding"]["fabric_compiler_version"],
		"boundary_contract_hash": bundle["artifact"]["boundary_contract"]["contract_hash"],
		"bake_policy_hash": bundle["artifact"]["source_binding"]["bake_policy_hash"],
		"runtime_domain": {
			"source_frontier_hash": parent_bundle["source_view"]["frontier"]["frontier_hash"],
			"fabric_graph_hash": parent_bundle["physical_graph"]["graph_hash"],
			"elapsed_s": elapsed_s,
			"mode": "CONTACT_WRENCH",
			"quantities": {},
		},
		"runtime_error_estimator": {},
		"guard_values": {},
		"invalidations": invalidations,
	}

static func _parent_estimator(elapsed_s: float) -> Dictionary:
	# Parent BRIDGE-1 is APPROXIMATE and therefore requires its established zero-error estimator.
	var RuntimeErrorEstimator = preload("res://scripts/research/fabric_bake0/runtime_error_estimator_v1.gd")
	return RuntimeErrorEstimator.create("estimator/b0-3-parent-bridge1", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, minf(0.5, maxf(0.0, elapsed_s)))
