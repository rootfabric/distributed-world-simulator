extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const SourceView = preload("res://scripts/research/fabric_bake0/physical_source_view_v1.gd")
const PhysicalGraph = preload("res://scripts/research/fabric_bake0/physical_source_fabric_graph_v1.gd")
const AggregateCompiler = preload("res://scripts/research/fabric_bake0/structural_aggregate_compiler_v1.gd")
const GuardCompiler = preload("res://scripts/research/fabric_bake0/structural_refinement_guard_compiler_v1.gd")
const FoundationCompiler = preload("res://scripts/research/fabric_bake0/fabric_bake_foundation_compiler_v1.gd")
const BoundaryContract = preload("res://scripts/research/fabric_bake0/physical_boundary_contract_v1.gd")
const DependencySet = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")
const ValidatedDomain = preload("res://scripts/research/fabric_bake0/validated_domain_v1.gd")
const ErrorEnvelope = preload("res://scripts/research/fabric_bake0/error_envelope_v1.gd")
const ConservationEnvelope = preload("res://scripts/research/fabric_bake0/conservation_envelope_v1.gd")
const ReconstructionDescriptor = preload("res://scripts/research/fabric_bake0/reconstruction_descriptor_v1.gd")
const StateMapping = preload("res://scripts/research/fabric_bake0/bake_state_mapping_v1.gd")
const Reconstruction = preload("res://scripts/research/fabric_bake0/structural_reconstruction_mapping_v1.gd")
const BakeExecutionGate = preload("res://scripts/research/fabric_bake0/bake_execution_gate_v1.gd")
const RuntimeErrorEstimator = preload("res://scripts/research/fabric_bake0/runtime_error_estimator_v1.gd")
const Bridge0 = preload("res://scripts/research/fabric_bake0/fabric_bake_bridge0_v1.gd")
const BakeInvalidation = preload("res://scripts/research/fabric_bake0/bake_invalidation_v1.gd")
const RepresentationInvalidation = preload("res://scripts/simulation/representation/contracts/representation_invalidation.gd")

const KIND := "BRIDGE1_PHYSICAL_SOURCE_LIFECYCLE_BUNDLE"
const STATUS_READY := "BRIDGE1_BAKE_READY"
const STATUS_REBUILT := "BRIDGE1_REBUILT_BAKE_READY"
const STATUS_FULL := "FULL_RECONSTRUCTED"
const B0_2_FINAL_EXECUTABLE := "91a2f79bf6738efefa342589c44e4a0f0a6960d6"
const CONTINUITY_TOLERANCE := 1.0e-8
const CONSERVATION_TOLERANCE := 1.0e-8
const DEFAULT_MINIMUM_PARTS := 100
const ROOT_PART_ID := "part/b0-2-0000"

static func compile(view_request: Dictionary, options: Dictionary = {}) -> Dictionary:
	var view := SourceView.create(view_request)
	if not bool(view.get("success", false)):
		return view
	var graph := PhysicalGraph.compile(view)
	if not bool(graph.get("success", false)):
		return graph
	var construction: Dictionary = graph["construction_payload"]
	var minimum_parts := int(options.get("minimum_part_count", DEFAULT_MINIMUM_PARTS))
	if minimum_parts < 2:
		return Utils.failure("BRIDGE1_INVALID_MINIMUM_PART_COUNT")
	var aggregate_request := {
		"descriptor_id": String(options.get("descriptor_id", "aggregate/bridge1-structural")),
		"mapping_id": String(options.get("mapping_id", "mapping/bridge1-structural")),
		"source_frontier_hash": String(view["frontier"]["frontier_hash"]),
		"construct_id": String(construction["construct_id"]),
		"parts": Array(construction["parts"]).duplicate(true),
		"bonds": Array(construction["bonds"]).duplicate(true),
		"boundary_anchors": Array(construction["boundary_anchors"]).duplicate(true),
		"reconstruction_version": "FABRIC_BAKE_BRIDGE1_R1",
		"minimum_part_count": minimum_parts,
	}
	var aggregate := AggregateCompiler.compile(aggregate_request)
	if not bool(aggregate.get("success", false)):
		if String(aggregate.get("error_code", "")) == "INSUFFICIENT_STRUCTURAL_COMPLEXITY_REDUCTION":
			return {"success": true, "status": STATUS_FULL, "reason": "INSUFFICIENT_COMPLEXITY_REDUCTION", "source_view": view, "physical_graph": graph}
		return aggregate

	var capacities := _capacity_specs(construction["bonds"], construction["parts"], aggregate["descriptor"])
	var capacity_hash := Utils.canonical_hash({
		"schema": "planet_simulator.fabric_bake_structural_capacity_set.v1",
		"source_frontier_hash": view["frontier"]["frontier_hash"],
		"bond_capacity_specs": capacities,
	})
	var root_part_id := String(options.get("root_part_id", ROOT_PART_ID))
	if not _has_part(construction["parts"], root_part_id):
		root_part_id = String(Utils.sorted_dicts(construction["parts"], "part_id")[0]["part_id"])
	var guard_request := {
		"field_id": String(options.get("guard_field_id", "guard-field/bridge1")),
		"source_frontier_hash": String(view["frontier"]["frontier_hash"]),
		"structural_descriptor": aggregate["descriptor"],
		"reconstruction_mapping": aggregate["reconstruction_mapping"],
		"parts": Array(construction["parts"]).duplicate(true),
		"bonds": Array(construction["bonds"]).duplicate(true),
		"root_part_id": root_part_id,
		"bond_capacity_specs": capacities,
		"capacity_certificate_hash": capacity_hash,
		"trigger_ratio": 0.80,
		"required_refinement_level": 2,
		"residual_force_tolerance": 1.0e-8,
		"residual_moment_tolerance": 1.0e-8,
		"evaluator_version": "FABRIC_BAKE_BRIDGE1_GUARD_R1",
	}
	var guarded := GuardCompiler.compile(guard_request)
	if not bool(guarded.get("success", false)):
		return guarded
	var guard_field: Dictionary = guarded["guard_field"]

	var boundary := _boundary_contract(aggregate["descriptor"])
	if boundary.is_empty():
		return Utils.failure("BRIDGE1_BOUNDARY_CONTRACT_FAILED")
	var dependencies := _dependencies()
	var validated := ValidatedDomain.create(String(view["frontier"]["frontier_hash"]), String(graph["graph_hash"]), [], ["RIGID"], 1.0)
	var error_envelope := ErrorEnvelope.create(
		CONTINUITY_TOLERANCE, 0.0, CONTINUITY_TOLERANCE, 0.0,
		CONTINUITY_TOLERANCE, 0.0, CONTINUITY_TOLERANCE, 0.0,
		0.0, CONSERVATION_TOLERANCE, 0.0, 1.0, true
	)
	var conservation := ConservationEnvelope.create(0.0, 0.0, CONSERVATION_TOLERANCE, CONSERVATION_TOLERANCE, 0.0)
	var source_keys: Array = view["frontier"]["sources"].map(func(source): return Utils.source_key(String(source["source_domain"]), String(source["source_id"])))
	source_keys.sort()
	var reconstruction_descriptor := ReconstructionDescriptor.create(
		String(options.get("reconstruction_descriptor_id", "reconstruction/bridge1")),
		String(view["frontier"]["frontier_hash"]),
		String(aggregate["reconstruction_mapping"]["checksum"]),
		"CANONICAL_PLUS_REDUCED",
		[{"region_id": "region/bridge1-all", "source_keys": source_keys}],
		"STRICT",
		Utils.canonical_hash({"event_frontier": "bridge1-source-lifecycle-r1"}),
		"FABRIC_BAKE_BRIDGE1_R1"
	)
	if reconstruction_descriptor.is_empty():
		return Utils.failure("BRIDGE1_RECONSTRUCTION_DESCRIPTOR_FAILED")
	var state_mapping := StateMapping.create(
		String(options.get("state_mapping_id", "state-mapping/bridge1")),
		String(aggregate["descriptor"]["full_state_schema_hash"]),
		String(aggregate["descriptor"]["reduced_state_schema_hash"]),
		String(aggregate["reconstruction_mapping"]["checksum"]),
		String(reconstruction_descriptor["checksum"])
	)
	if state_mapping.is_empty():
		return Utils.failure("BRIDGE1_STATE_MAPPING_FAILED")
	var build_generation := int(options.get("build_generation", 1))
	if build_generation < 1:
		return Utils.failure("BRIDGE1_INVALID_BUILD_GENERATION")
	var artifact_result := FoundationCompiler.compile({
		"artifact_id": String(options.get("artifact_id", "bake/bridge1-structural")),
		"reduction_class": "APPROXIMATE",
		"canonical_source_frontier": view["frontier"],
		"authority_envelope": view["authority_envelope"],
		"dependency_set": dependencies,
		"fabric_graph_hash": graph["graph_hash"],
		"fabric_compiler_version": PhysicalGraph.COMPILER_VERSION,
		"boundary_contract": boundary,
		"bake_policy_hash": Utils.canonical_hash({"policy": "bridge1-structural-r1", "minimum_part_count": minimum_parts}),
		"reduced_model_descriptor_hash": String(aggregate["descriptor"]["checksum"]),
		"reduced_state_schema_hash": String(aggregate["descriptor"]["reduced_state_schema_hash"]),
		"validated_domain": validated,
		"error_envelope": error_envelope,
		"conservation_envelope": conservation,
		"refinement_guards": guard_field["region_guards"],
		"reconstruction_descriptor": reconstruction_descriptor,
		"state_mapping": state_mapping,
		"build_generation": build_generation,
		"error_certified": true,
		"refinement_guard_certified": true,
		"complexity_reduction_certified": true,
	})
	if String(artifact_result.get("status", "")) != "BAKE_READY":
		return Utils.failure("BRIDGE1_FOUNDATION_COMPILE_NOT_READY", {"result": artifact_result})
	return {
		"success": true,
		"status": STATUS_READY,
		"kind": KIND,
		"source_view": view,
		"physical_graph": graph,
		"aggregate": aggregate,
		"guard_field": guard_field,
		"dependency_set": dependencies,
		"artifact": artifact_result["artifact"],
		"build_generation": build_generation,
		"topology_hash": graph["topology_hash"],
		"contact_state_policy": "TRANSIENT_REDERIVE_AFTER_REBUILD",
	}

static func execute(bundle: Dictionary, reduced_state: Dictionary, elapsed_s: float = 0.0, invalidations: Array = []) -> Dictionary:
	if not _is_bundle(bundle):
		return Utils.failure("BRIDGE1_INVALID_BUNDLE")
	var gate := _gate(bundle, elapsed_s, invalidations)
	if not bool(gate.get("success", false)):
		return gate
	var momentum := AggregateCompiler.reduced_momentum(bundle["aggregate"]["descriptor"], reduced_state)
	if not bool(momentum.get("success", false)):
		return momentum
	var anchors: Array = []
	for anchor in bundle["aggregate"]["descriptor"]["boundary_anchors"]:
		var evaluated := AggregateCompiler.evaluate_anchor(bundle["aggregate"]["descriptor"], reduced_state, String(anchor["anchor_id"]))
		if not bool(evaluated.get("success", false)):
			return evaluated
		anchors.append({"anchor_id": String(anchor["anchor_id"]), "state": evaluated["details"]})
	return {
		"success": true,
		"status": "BRIDGE1_EXECUTED",
		"artifact_id": bundle["artifact"]["artifact_id"],
		"artifact_hash": bundle["artifact"]["checksum"],
		"source_frontier_hash": bundle["source_view"]["frontier"]["frontier_hash"],
		"graph_hash": bundle["physical_graph"]["graph_hash"],
		"gate": gate["details"],
		"reduced_state": reduced_state.duplicate(true),
		"momentum": momentum["details"],
		"anchors": anchors,
	}

static func source_frontier_mismatch(bundle: Dictionary, current_view_request: Dictionary) -> Dictionary:
	if not _is_bundle(bundle):
		return Utils.failure("BRIDGE1_INVALID_BUNDLE")
	var current_view := SourceView.create(current_view_request)
	if not bool(current_view.get("success", false)):
		return current_view
	var current_graph := PhysicalGraph.compile(current_view)
	if not bool(current_graph.get("success", false)):
		return current_graph
	var live := _live(bundle, 0.0, [])
	live["canonical_source_frontier"] = current_view["frontier"]
	live["authority_envelope"] = current_view["authority_envelope"]
	live["fabric_graph_hash"] = current_graph["graph_hash"]
	live["runtime_domain"]["source_frontier_hash"] = current_view["frontier"]["frontier_hash"]
	live["runtime_domain"]["fabric_graph_hash"] = current_graph["graph_hash"]
	return BakeExecutionGate.can_execute(bundle["artifact"], live)

static func derived_dependency_mismatch(bundle: Dictionary, changed_compiler_version: String) -> Dictionary:
	if not _is_bundle(bundle):
		return Utils.failure("BRIDGE1_INVALID_BUNDLE")
	var live := _live(bundle, 0.0, [])
	live["fabric_compiler_version"] = changed_compiler_version
	return BakeExecutionGate.can_execute(bundle["artifact"], live)

static func observe_transient_contact_event(bundle: Dictionary, event: Dictionary) -> Dictionary:
	if not _is_bundle(bundle):
		return Utils.failure("BRIDGE1_INVALID_BUNDLE")
	if typeof(event) != TYPE_DICTIONARY or not ["STICK_TO_SLIDE", "STICK_TO_ROLL", "STICK_TO_SPIN", "SUPPORT_TO_SEPARATION"].has(String(event.get("event_type", ""))):
		return Utils.failure("BRIDGE1_INVALID_TRANSIENT_CONTACT_EVENT")
	return Utils.success({
		"source_frontier_hash": bundle["source_view"]["frontier"]["frontier_hash"],
		"artifact_id": bundle["artifact"]["artifact_id"],
		"bake_invalidation_emitted": false,
		"canonical_revision_emitted": false,
		"contact_state_owner": "PHYSICAL_CORE",
	})

static func rebuild_same_topology(
	bundle: Dictionary, reduced_state: Dictionary, source_invalidation: Dictionary,
	current_view_request: Dictionary, options: Dictionary = {}, applied_invalidation_ids: Array = []
) -> Dictionary:
	if not _is_bundle(bundle):
		return Utils.failure("BRIDGE1_INVALID_BUNDLE")
	var checked := RepresentationInvalidation.validate(source_invalidation)
	if not bool(checked.get("success", false)):
		return checked
	if applied_invalidation_ids.has(String(source_invalidation["invalidation_id"])):
		return Utils.failure("BRIDGE1_SOURCE_INVALIDATION_ALREADY_APPLIED")
	var current_view := SourceView.create(current_view_request)
	if not bool(current_view.get("success", false)):
		return current_view
	var current_graph := PhysicalGraph.compile(current_view)
	if not bool(current_graph.get("success", false)):
		return current_graph
	if String(current_graph["topology_hash"]) != String(bundle["topology_hash"]):
		return Utils.failure("BRIDGE1_TOPOLOGY_CHANGE_REQUIRES_B0_2_E", {
			"previous_topology_hash": bundle["topology_hash"],
			"current_topology_hash": current_graph["topology_hash"],
		})
	var bake_invalidation := Bridge0.invalidate_from_source_mutation(
		bundle["artifact"], source_invalidation, current_view["frontier"], int(options.get("created_tick", source_invalidation["created_tick"]))
	)
	if bake_invalidation.has("success") and not bool(bake_invalidation.get("success", false)):
		return bake_invalidation
	checked = BakeInvalidation.validate(bake_invalidation)
	if not bool(checked.get("success", false)):
		return checked
	var stale_gate := _gate(bundle, 0.0, [bake_invalidation])
	if bool(stale_gate.get("success", false)):
		return Utils.failure("BRIDGE1_STALE_ARTIFACT_EXECUTED")
	if String(stale_gate.get("error_code", "")) != "STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN":
		return Utils.failure("BRIDGE1_STALE_REJECTION_WRONG", {"gate": stale_gate})
	var reconstructed := Reconstruction.reconstruct(bundle["aggregate"]["reconstruction_mapping"], reduced_state)
	if not bool(reconstructed.get("success", false)):
		return reconstructed
	var full_states: Dictionary = reconstructed["details"]["full_states"]
	var full_hash := Utils.canonical_hash(full_states)
	if bool(options.get("force_full_fallback", false)):
		return {
			"success": true,
			"status": STATUS_FULL,
			"bake_invalidation": bake_invalidation,
			"stale_rejection_code": stale_gate["error_code"],
			"full_states": full_states,
			"full_state_hash": full_hash,
			"contact_state_policy": "DISCARD_AND_REDERIVE",
			"accepted_previous_contact_impulse": false,
		}
	var rebuild_options := options.duplicate(true)
	rebuild_options.erase("created_tick")
	rebuild_options.erase("force_full_fallback")
	rebuild_options["build_generation"] = int(bundle["build_generation"]) + 1
	var rebuilt := compile(current_view_request, rebuild_options)
	if not bool(rebuilt.get("success", false)):
		return rebuilt
	if String(rebuilt.get("status", "")) != STATUS_READY:
		return Utils.failure("BRIDGE1_REBUILD_DID_NOT_PRODUCE_BAKE")
	var projected := Reconstruction.project(rebuilt["aggregate"]["reconstruction_mapping"], full_states, CONTINUITY_TOLERANCE)
	if not bool(projected.get("success", false)):
		return projected
	var new_reduced_state: Dictionary = projected["details"]["reduced_state"]
	var roundtrip := Reconstruction.reconstruct(rebuilt["aggregate"]["reconstruction_mapping"], new_reduced_state)
	if not bool(roundtrip.get("success", false)):
		return roundtrip
	var handoff_error := _full_state_error(full_states, roundtrip["details"]["full_states"])
	if handoff_error > CONTINUITY_TOLERANCE:
		return Utils.failure("BRIDGE1_REBUILD_STATE_HANDOFF_MISMATCH", {"error": handoff_error})
	var fresh_gate := _gate(rebuilt, 0.0, [])
	if not bool(fresh_gate.get("success", false)):
		return Utils.failure("BRIDGE1_REBUILT_ARTIFACT_NOT_EXECUTABLE", {"gate": fresh_gate})
	return {
		"success": true,
		"status": STATUS_REBUILT,
		"bake_invalidation": bake_invalidation,
		"stale_rejection_code": stale_gate["error_code"],
		"full_state_hash": full_hash,
		"full_states": full_states,
		"rebuilt_bundle": rebuilt,
		"rebuilt_reduced_state": new_reduced_state,
		"handoff_error": handoff_error,
		"fresh_execution_gate": fresh_gate["details"],
		"contact_state_policy": "DISCARD_AND_REDERIVE",
		"accepted_previous_contact_impulse": false,
	}

static func _gate(bundle: Dictionary, elapsed_s: float, invalidations: Array) -> Dictionary:
	return BakeExecutionGate.can_execute(bundle["artifact"], _live(bundle, elapsed_s, invalidations))

static func _live(bundle: Dictionary, elapsed_s: float, invalidations: Array) -> Dictionary:
	var estimator := RuntimeErrorEstimator.create("estimator/bridge1", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, minf(0.5, maxf(0.0, elapsed_s)))
	var guards: Dictionary = {}
	for guard in bundle["artifact"]["refinement_guards"]:
		guards[String(guard["guard_id"])] = 0.0
	return {
		"artifact_state": "READY",
		"canonical_source_frontier": bundle["source_view"]["frontier"],
		"authority_envelope": bundle["source_view"]["authority_envelope"],
		"dependency_set": bundle["dependency_set"],
		"fabric_graph_hash": bundle["physical_graph"]["graph_hash"],
		"fabric_compiler_version": PhysicalGraph.COMPILER_VERSION,
		"boundary_contract_hash": bundle["artifact"]["boundary_contract"]["contract_hash"],
		"bake_policy_hash": bundle["artifact"]["source_binding"]["bake_policy_hash"],
		"runtime_domain": {
			"source_frontier_hash": bundle["source_view"]["frontier"]["frontier_hash"],
			"fabric_graph_hash": bundle["physical_graph"]["graph_hash"],
			"elapsed_s": elapsed_s,
			"mode": "RIGID",
			"quantities": {},
		},
		"runtime_error_estimator": estimator,
		"guard_values": guards,
		"invalidations": invalidations,
	}

static func _dependencies() -> Dictionary:
	return DependencySet.create([
		{"dependency_id": "dependency/fabric-core-0-16", "dependency_hash": Utils.canonical_hash({"exact_executable": PhysicalGraph.FABRIC0_16_EXACT_EXECUTABLE})},
		{"dependency_id": "dependency/fabric-bake-b0-2", "dependency_hash": Utils.canonical_hash({"exact_executable": B0_2_FINAL_EXECUTABLE})},
	])

static func _boundary_contract(descriptor: Dictionary) -> Dictionary:
	var ports: Array = []
	for index in range(descriptor["boundary_anchors"].size()):
		var frame_id := "frame/bridge1-%03d" % index
		for kind in ["force", "torque"]:
			var force: bool = kind == "force"
			ports.append({
				"port_id": "port/bridge1-%03d-%s" % [index, kind],
				"physical_domain": "MECHANICAL",
				"effort_quantity": "quantity/force" if force else "quantity/torque",
				"flow_quantity": "quantity/linear-velocity" if force else "quantity/angular-velocity",
				"effort_dimension": [1, 1, -2, 0, 0, 0, 0] if force else [1, 2, -2, 0, 0, 0, 0],
				"flow_dimension": [0, 1, -1, 0, 0, 0, 0] if force else [0, 0, -1, 0, 0, 0, 0],
				"frame": frame_id,
				"orientation": "INTO_SUBSYSTEM",
				"conservation_group": "group/bridge1-structural",
				"event_observables": ["SOURCE_INVALIDATION", "TOPOLOGY_BREAK"],
			})
	return BoundaryContract.create(ports)

static func _capacity_specs(bonds: Array, parts: Array, descriptor: Dictionary) -> Array:
	var part_position: Dictionary = {}
	var com := _vec3(descriptor["center_of_mass"])
	for part in parts:
		part_position[String(part["part_id"])] = _vec3(part["position"]) - com
	var specs: Array = []
	for bond in Utils.sorted_dicts(bonds, "bond_id"):
		var a: Vector3 = part_position[String(bond["part_a"])]
		var b: Vector3 = part_position[String(bond["part_b"])]
		specs.append({
			"bond_id": String(bond["bond_id"]),
			"point_from_com": _arr3((a + b) * 0.5),
			"certified_force_capacity": 1.0e9,
			"certified_moment_capacity": 1.0e9,
			"uncertainty_ratio": 0.01,
		})
	return specs

static func _has_part(parts: Array, part_id: String) -> bool:
	for part in parts:
		if String(part.get("part_id", "")) == part_id:
			return true
	return false

static func _is_bundle(bundle: Dictionary) -> bool:
	return bool(bundle.get("success", false)) and String(bundle.get("kind", "")) == KIND and String(bundle.get("status", "")) == STATUS_READY

static func _full_state_error(a: Dictionary, b: Dictionary) -> float:
	if a.size() != b.size():
		return INF
	var error := 0.0
	for key in a.keys():
		if not b.has(key):
			return INF
		var x: Dictionary = a[key]
		var y: Dictionary = b[key]
		error = maxf(error, _vec3(x["position"]).distance_to(_vec3(y["position"])))
		error = maxf(error, _vec3(x["linear_velocity"]).distance_to(_vec3(y["linear_velocity"])))
		error = maxf(error, _vec3(x["angular_velocity"]).distance_to(_vec3(y["angular_velocity"])))
		var qx := Quaternion(float(x["orientation"][0]), float(x["orientation"][1]), float(x["orientation"][2]), float(x["orientation"][3])).normalized()
		var qy := Quaternion(float(y["orientation"][0]), float(y["orientation"][1]), float(y["orientation"][2]), float(y["orientation"][3])).normalized()
		error = maxf(error, 1.0 - absf(qx.dot(qy)))
	return error

static func _vec3(v: Array) -> Vector3:
	return Vector3(float(v[0]), float(v[1]), float(v[2]))

static func _arr3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]
