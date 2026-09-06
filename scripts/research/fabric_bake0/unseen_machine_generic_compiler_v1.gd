extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const AuthorityEnvelope = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const BoundaryContract = preload("res://scripts/research/fabric_bake0/physical_boundary_contract_v1.gd")
const DependencySet = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")
const ValidatedDomain = preload("res://scripts/research/fabric_bake0/validated_domain_v1.gd")
const ErrorEnvelope = preload("res://scripts/research/fabric_bake0/error_envelope_v1.gd")
const ConservationEnvelope = preload("res://scripts/research/fabric_bake0/conservation_envelope_v1.gd")
const ExactCompiler = preload("res://scripts/research/fabric_bake0/exact_boundary_bake_compiler_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/unseen_machine_generic_graph_v1.gd")

const PIVOT_TOLERANCE := 1.0e-12
const SYMMETRY_TOLERANCE := 5.0e-11
const PASSIVITY_TOLERANCE := 5.0e-11
const FLOW_ERROR_LIMIT := 2.0e-8
const POWER_ERROR_LIMIT := 2.0e-8
const AUTHORITY_OWNER := "server/b0-7-unseen"

static func build_context(spec: Dictionary, source_context: Dictionary = {}) -> Dictionary:
	var checked := Graph.validate(spec)
	if not bool(checked.get("success", false)):
		return Utils.failure("B0_7_GENERIC_SPEC_INVALID", {"cause": checked.get("error_code", "")})
	var system := Graph.to_linear_system(spec)
	if system.is_empty():
		return Utils.failure("B0_7_LINEAR_SYSTEM_BUILD_FAILED")
	var slug := _slug(String(spec["machine_id"]))
	var sources := research_source_context(spec) if source_context.is_empty() else validate_source_context(spec, source_context)
	if not sources.success:
		return sources
	var frame: Dictionary = sources.details
	var frontier: Dictionary = frame.frontier
	var authority: Dictionary = frame.authority
	var construction: Dictionary = {}
	var matter: Dictionary = {}
	for source in frontier.sources:
		if source.source_domain == "CONSTRUCTION": construction = source
		if source.source_domain == "MATTER": matter = source
	var boundary := _boundary_contract(spec)
	if boundary.is_empty():
		return Utils.failure("B0_7_BOUNDARY_BUILD_FAILED")
	var dependencies := DependencySet.create([
		{"dependency_id": "dependency/b0-7-generic-graph", "dependency_hash": Utils.canonical_hash({"contract": Graph.SCHEMA})},
		{"dependency_id": "dependency/b0-7-exact-schur", "dependency_hash": Utils.canonical_hash({"reducer": ExactCompiler.REDUCER_VERSION})},
	])
	if dependencies.is_empty():
		return Utils.failure("B0_7_DEPENDENCY_BUILD_FAILED")
	var fabric_graph_hash := Utils.canonical_hash({
		"generic_graph_hash": spec["graph_hash"],
		"linear_system_hash": system["system_hash"],
		"compiler": "B0_7_GENERIC_GRAPH_TO_LINEAR_R1",
	})
	var validated := ValidatedDomain.create(String(frontier["frontier_hash"]), fabric_graph_hash, [], ["STEADY"], 0.0)
	var errors := ErrorEnvelope.create(
		FLOW_ERROR_LIMIT, FLOW_ERROR_LIMIT, POWER_ERROR_LIMIT, FLOW_ERROR_LIMIT,
		POWER_ERROR_LIMIT, FLOW_ERROR_LIMIT, 0.0, 0.0,
		0.0, 0.0, 0.0, 1.0, true
	)
	var conservation := ConservationEnvelope.create(POWER_ERROR_LIMIT, 0.0, 0.0, 0.0, 0.0)
	if validated.is_empty() or errors.is_empty() or conservation.is_empty():
		return Utils.failure("B0_7_SAFETY_CONTRACT_BUILD_FAILED")
	var request := {
		"artifact_id": "bake/b0-7-%s-r%03d" % [slug, int(spec["revision"])],
		"canonical_source_frontier": frontier,
		"authority_envelope": authority,
		"dependency_set": dependencies,
		"fabric_graph_hash": fabric_graph_hash,
		"fabric_compiler_version": "FABRIC-B0.7/GENERIC-GRAPH-R1" if source_context.is_empty() else "FABRIC1/CANONICAL-BINDING-R1",
		"boundary_contract": boundary,
		"bake_policy_hash": Utils.canonical_hash({"policy": "B0_7_UNSEEN_EXACT_BOUNDARY_R1"}),
		"validated_domain": validated,
		"error_envelope": errors,
		"conservation_envelope": conservation,
		"build_generation": int(spec["revision"]),
		"linear_system": system,
		"pivot_relative_tolerance": PIVOT_TOLERANCE,
		"symmetry_tolerance": SYMMETRY_TOLERANCE,
		"passivity_tolerance": PASSIVITY_TOLERANCE,
		"require_symmetric": true,
		"require_passive_laplacian": true,
	}
	return Utils.success({
		"spec": spec.duplicate(true),
		"construction": construction,
		"matter": matter,
		"frontier": frontier,
		"authority": authority,
		"boundary": boundary,
		"dependencies": dependencies,
		"linear_system": system,
		"fabric_graph_hash": fabric_graph_hash,
		"request": request,
		"source_context": frame,
		"external_source": not source_context.is_empty(),
	})

static func compile(spec: Dictionary, source_context: Dictionary = {}) -> Dictionary:
	var context := build_context(spec, source_context)
	if not bool(context.get("success", false)):
		return context
	var result := ExactCompiler.compile(context["details"]["request"])
	var status := String(result.get("status", ""))
	return {
		"success": status in ["BAKE_READY", "NO_SAFE_BAKE"],
		"error_code": String(result.get("error_code", "")),
		"status": status,
		"reason": String(result.get("reason", "")),
		"context": context["details"],
		"compile_result": result,
	}

static func live_context(context: Dictionary, invalidations: Array = []) -> Dictionary:
	# Request came from current source inputs; artifacts/capsules cannot self-attest authority.
	if typeof(context.get("request")) != TYPE_DICTIONARY:
		return {}
	return ExactCompiler.live_context_from_request(context["request"], invalidations)

static func validate_source_context(spec: Dictionary, source_context: Dictionary) -> Dictionary:
	if not Utils.validate_exact_fields(source_context, ["frontier", "authority", "graph_hash"]).success:
		return Utils.failure("FABRIC1_SOURCE_CONTEXT_INVALID")
	if typeof(source_context.get("frontier")) != TYPE_DICTIONARY or typeof(source_context.get("authority")) != TYPE_DICTIONARY:
		return Utils.failure("FABRIC1_SOURCE_CONTEXT_INVALID")
	if typeof(source_context.get("graph_hash")) != TYPE_STRING or source_context["graph_hash"] != spec.get("graph_hash"):
		return Utils.failure("FABRIC1_SOURCE_GRAPH_MISMATCH")
	var checked := Frontier.validate(source_context.frontier)
	if not checked.success: return checked
	checked = AuthorityEnvelope.validate_b0_safety(source_context.authority)
	if not checked.success: return checked
	var source_epochs := {}
	for source in source_context.frontier.sources:
		source_epochs[Utils.source_key(source.source_domain, source.source_id)] = int(source.authority_epoch)
	var authority_epochs := {}
	for source in source_context.authority.source_authority_frontier:
		authority_epochs[Utils.source_key(source.source_domain, source.source_id)] = int(source.authority_epoch)
	if source_epochs != authority_epochs:
		return Utils.failure("FABRIC1_AUTHORITY_FRONTIER_MISMATCH")
	return Utils.success(source_context)

static func research_source_context(spec: Dictionary) -> Dictionary:
	# Legacy standalone B0.7 numerical experiments only. BRIDGE4 supplies real sources.
	var checked := Graph.validate(spec)
	if not checked.success: return checked
	var slug := _slug(String(spec["machine_id"]))
	var dependency_hash := Utils.canonical_hash({
		"b0_7_generic_graph": "v1",
		"exact_reducer": ExactCompiler.REDUCER_VERSION,
	})
	var construction := SourceRevision.create(
		"CONSTRUCTION", "construct/b0-7-%s" % slug, 1, int(spec["revision"]),
		String(spec["graph_hash"]), dependency_hash
	)
	var matter := SourceRevision.create(
		"MATTER", "matter/b0-7-%s" % slug, 1, 1,
		Utils.canonical_hash({"generic_power_medium": "v1", "machine": spec["machine_id"]}),
		dependency_hash
	)
	if construction.is_empty() or matter.is_empty():
		return Utils.failure("B0_7_SOURCE_REVISION_BUILD_FAILED")
	var frontier := Frontier.create([construction, matter])
	if frontier.is_empty():
		return Utils.failure("B0_7_FRONTIER_BUILD_FAILED")
	var construction_key := Utils.source_key("CONSTRUCTION", String(construction["source_id"]))
	var matter_key := Utils.source_key("MATTER", String(matter["source_id"]))
	var authority := AuthorityEnvelope.create(
		AUTHORITY_OWNER,
		[
			{"source_domain": "CONSTRUCTION", "source_id": construction["source_id"], "authority_epoch": 1, "owner_id": AUTHORITY_OWNER},
			{"source_domain": "MATTER", "source_id": matter["source_id"], "authority_epoch": 1, "owner_id": AUTHORITY_OWNER},
		],
		[construction_key, matter_key]
	)
	if authority.is_empty():
		return Utils.failure("B0_7_AUTHORITY_BUILD_FAILED")
	return Utils.success({"frontier": frontier, "authority": authority, "graph_hash": spec["graph_hash"]})

static func _boundary_contract(spec: Dictionary) -> Dictionary:
	var ports: Array = []
	for port_id in spec["boundary_node_ids"]:
		ports.append({
			"port_id": port_id,
			"physical_domain": "GENERIC_POWER",
			"effort_quantity": "quantity/generic-effort",
			"flow_quantity": "quantity/generic-flow",
			"effort_dimension": [1, 2, -3, 0, 0, 0, 0],
			"flow_dimension": [0, 0, 0, 0, 0, 0, 0],
			"frame": "frame/b0-7-generic",
			"orientation": "INTO_SUBSYSTEM",
			"conservation_group": "group/b0-7-generic-power",
			"event_observables": ["SOURCE_INVALIDATION", "TOPOLOGY_CHANGE"],
		})
	return BoundaryContract.create(ports)

static func _slug(machine_id: String) -> String:
	return machine_id.replace("/", "-").replace("_", "-").to_lower()
