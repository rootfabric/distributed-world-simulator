extends SceneTree

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const RepresentationInvalidation = preload("res://scripts/simulation/representation/contracts/representation_invalidation.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const AuthorityEnvelope = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const BoundaryContract = preload("res://scripts/research/fabric_bake0/physical_boundary_contract_v1.gd")
const DependencySet = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")
const ValidatedDomain = preload("res://scripts/research/fabric_bake0/validated_domain_v1.gd")
const ErrorEnvelope = preload("res://scripts/research/fabric_bake0/error_envelope_v1.gd")
const RuntimeErrorEstimator = preload("res://scripts/research/fabric_bake0/runtime_error_estimator_v1.gd")
const ConservationEnvelope = preload("res://scripts/research/fabric_bake0/conservation_envelope_v1.gd")
const RefinementGuard = preload("res://scripts/research/fabric_bake0/refinement_guard_v1.gd")
const ReconstructionDescriptor = preload("res://scripts/research/fabric_bake0/reconstruction_descriptor_v1.gd")
const StateMapping = preload("res://scripts/research/fabric_bake0/bake_state_mapping_v1.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/physical_bake_artifact_v1.gd")
const CompileResult = preload("res://scripts/research/fabric_bake0/bake_compile_result_v1.gd")
const Compiler = preload("res://scripts/research/fabric_bake0/fabric_bake_foundation_compiler_v1.gd")
const ExecutionGate = preload("res://scripts/research/fabric_bake0/bake_execution_gate_v1.gd")
const Bridge0 = preload("res://scripts/research/fabric_bake0/fabric_bake_bridge0_v1.gd")

func h(value) -> String:
	return Utils.canonical_hash(value)

func error_code(value: Dictionary) -> String:
	return String(value.get("error_code", ""))

func build_fixture() -> Dictionary:
	var dependency_hash := h({"dependency": "canonical-base"})
	var construction := SourceRevision.create(
		"CONSTRUCTION", "construct/alpha", 3, 12, h({"construct": 12}), dependency_hash
	)
	var matter := SourceRevision.create(
		"MATTER", "matter/region-a", 3, 8, h({"matter": 8}), dependency_hash
	)
	var frontier := Frontier.create([matter, construction])
	var construction_key := Utils.source_key("CONSTRUCTION", "construct/alpha")
	var matter_key := Utils.source_key("MATTER", "matter/region-a")
	var authority := AuthorityEnvelope.create(
		"server/alpha",
		[
			{"source_domain": "MATTER", "source_id": "matter/region-a", "authority_epoch": 3, "owner_id": "server/alpha"},
			{"source_domain": "CONSTRUCTION", "source_id": "construct/alpha", "authority_epoch": 3, "owner_id": "server/alpha"},
		],
		[construction_key, matter_key]
	)
	var boundary := BoundaryContract.create([
		{
			"port_id": "port/mechanical-a",
			"physical_domain": "MECHANICAL_TRANSLATIONAL",
			"effort_quantity": "quantity/force",
			"flow_quantity": "quantity/velocity",
			"effort_dimension": [1, 1, -2, 0, 0, 0, 0],
			"flow_dimension": [0, 1, -1, 0, 0, 0, 0],
			"frame": "frame/world",
			"orientation": "INTO_SUBSYSTEM",
			"conservation_group": "group/mechanical",
			"event_observables": ["CONTACT_EVENT", "FAILURE_EVENT"],
		},
	])
	var dependencies := DependencySet.create([
		{"dependency_id": "dependency/fabric-kernel", "dependency_hash": h({"fabric": "0.15"})},
		{"dependency_id": "dependency/material-table", "dependency_hash": h({"material": "v4"})},
	])
	var fabric_graph_hash := h({"graph": "fixture-a"})
	var bake_policy_hash := h({"policy": "b0.0-default"})
	var validated := ValidatedDomain.create(
		String(frontier["frontier_hash"]),
		fabric_graph_hash,
		[
			{
				"quantity_id": "quantity/torque",
				"dimension": [1, 2, -2, 0, 0, 0, 0],
				"minimum": -300.0,
				"maximum": 300.0,
			},
		],
		["STEADY"],
		5.0
	)
	var error_envelope := ErrorEnvelope.create(
		0.01, 0.001, 0.01, 0.001, 0.02, 0.002, 0.001, 0.001,
		0.001, 0.001, 0.0005, 5.0, true
	)
	var conservation := ConservationEnvelope.create(0.001, 0.0, 0.001, 0.001, 0.0)
	var guard := RefinementGuard.create(
		"guard/region-a",
		["quantity/force", "quantity/torque"],
		100.0, 80.0, "region/alpha", 2, 5.0
	)
	var reconstruction := ReconstructionDescriptor.create(
		"reconstruction/aggregate-a",
		String(frontier["frontier_hash"]),
		h({"mapping": "aggregate-a"}),
		"CANONICAL_PLUS_REDUCED",
		[
			{"region_id": "region/alpha", "source_keys": [construction_key, matter_key]},
		],
		"STRICT",
		h({"events": "frontier-a"}),
		"b0.0-r1"
	)
	var reduced_state_schema_hash := h({"state": "reduced-a"})
	var mapping := StateMapping.create(
		"mapping/aggregate-a",
		h({"state": "full-a"}),
		reduced_state_schema_hash,
		h({"projection": "full-to-reduced"}),
		String(reconstruction["checksum"])
	)
	var request := {
		"artifact_id": "bake/aggregate-a",
		"reduction_class": "APPROXIMATE",
		"canonical_source_frontier": frontier,
		"authority_envelope": authority,
		"dependency_set": dependencies,
		"fabric_graph_hash": fabric_graph_hash,
		"fabric_compiler_version": "FABRIC0.15/a8ff0d7",
		"boundary_contract": boundary,
		"bake_policy_hash": bake_policy_hash,
		"reduced_model_descriptor_hash": h({"model": "aggregate-a"}),
		"reduced_state_schema_hash": reduced_state_schema_hash,
		"validated_domain": validated,
		"error_envelope": error_envelope,
		"conservation_envelope": conservation,
		"refinement_guards": [guard],
		"reconstruction_descriptor": reconstruction,
		"state_mapping": mapping,
		"build_generation": 1,
		"error_certified": true,
		"refinement_guard_certified": true,
		"complexity_reduction_certified": true,
	}
	return {
		"construction": construction,
		"matter": matter,
		"frontier": frontier,
		"authority": authority,
		"boundary": boundary,
		"dependencies": dependencies,
		"guard": guard,
		"error_envelope": error_envelope,
		"request": request,
	}

func live_context(artifact: Dictionary, fixture: Dictionary) -> Dictionary:
	return {
		"artifact_state": "READY",
		"canonical_source_frontier": fixture["frontier"].duplicate(true),
		"authority_envelope": fixture["authority"].duplicate(true),
		"dependency_set": fixture["dependencies"].duplicate(true),
		"fabric_graph_hash": artifact["source_binding"]["fabric_graph_hash"],
		"fabric_compiler_version": artifact["source_binding"]["fabric_compiler_version"],
		"boundary_contract_hash": artifact["source_binding"]["boundary_contract_hash"],
		"bake_policy_hash": artifact["source_binding"]["bake_policy_hash"],
		"runtime_domain": {
			"source_frontier_hash": artifact["source_binding"]["frontier_hash"],
			"fabric_graph_hash": artifact["source_binding"]["fabric_graph_hash"],
			"elapsed_s": 1.0,
			"mode": "STEADY",
			"quantities": {"quantity/torque": 120.0},
		},
		"runtime_error_estimator": RuntimeErrorEstimator.create(
			"estimator/aggregate-a",
			0.005, 0.005, 0.01, 0.0005, 0.0005, 0.0005,
			0.7, 15.0, 2.0
		),
		"guard_values": {"guard/region-a": 50.0},
		"invalidations": [],
	}

func _init() -> void:
	var checks := 0
	var fixture := build_fixture()
	assert(not fixture["construction"].is_empty() and not fixture["matter"].is_empty()); checks += 1

	# CanonicalSourceFrontier is multi-source, deterministic, and cannot admit FABRIC.
	assert(fixture["frontier"]["sources"].size() == 2); checks += 1
	var reversed_frontier := Frontier.create([fixture["construction"], fixture["matter"]])
	assert(String(reversed_frontier["frontier_hash"]) == String(fixture["frontier"]["frontier_hash"])); checks += 1
	assert(SourceRevision.create("FABRIC", "fabric/graph-a", 1, 1, h({"x": 1}), h({"d": 1})).is_empty()); checks += 1

	# Happy path: valid B0.0 compilation yields an executable derived physical artifact.
	var compiled := Compiler.compile(fixture["request"])
	assert(String(compiled.get("status", "")) == CompileResult.BAKE_READY); checks += 1
	assert(bool(CompileResult.validate(compiled).get("success", false))); checks += 1
	var artifact: Dictionary = compiled["artifact"]
	assert(bool(Artifact.validate(artifact).get("success", false))); checks += 1
	assert(String(artifact["source_binding"]["frontier_hash"]) == String(fixture["frontier"]["frontier_hash"])); checks += 1
	assert(String(artifact["source_binding"]["boundary_contract_hash"]) == String(fixture["boundary"]["contract_hash"])); checks += 1
	var live := live_context(artifact, fixture)
	var gate := ExecutionGate.can_execute(artifact, live)
	assert(bool(gate.get("success", false))); checks += 1

	# NO_SAFE_BAKE is a successful compiler outcome for unsafe physical candidates.
	var cross_authority_request: Dictionary = fixture["request"].duplicate(true)
	cross_authority_request["authority_envelope"] = AuthorityEnvelope.create(
		"server/alpha",
		[
			{"source_domain": "CONSTRUCTION", "source_id": "construct/alpha", "authority_epoch": 3, "owner_id": "server/alpha"},
			{"source_domain": "MATTER", "source_id": "matter/region-a", "authority_epoch": 3, "owner_id": "server/beta"},
		],
		[
			Utils.source_key("CONSTRUCTION", "construct/alpha"),
			Utils.source_key("MATTER", "matter/region-a"),
		]
	)
	var cross_result := Compiler.compile(cross_authority_request)
	assert(String(cross_result.get("status", "")) == CompileResult.NO_SAFE_BAKE); checks += 1
	assert(String(cross_result.get("reason", "")) == "AUTHORITY_ENVELOPE_CROSSED"); checks += 1
	var uncert_guard_request: Dictionary = fixture["request"].duplicate(true)
	uncert_guard_request["refinement_guard_certified"] = false
	var uncert_guard_result := Compiler.compile(uncert_guard_request)
	assert(String(uncert_guard_result.get("status", "")) == CompileResult.NO_SAFE_BAKE); checks += 1
	assert(String(uncert_guard_result.get("reason", "")) == "UNCERTIFIABLE_REFINEMENT_GUARD"); checks += 1

	# Missing reconstruction is never a valid physical artifact.
	var missing_reconstruction := artifact.duplicate(true)
	missing_reconstruction["reconstruction_descriptor"] = {}
	missing_reconstruction["checksum"] = Utils.compute_checksum(missing_reconstruction)
	assert(not bool(Artifact.validate(missing_reconstruction).get("success", false))); checks += 1

	# Runtime provenance and validity are fail-closed.
	var wrong_revision_live: Dictionary = live.duplicate(true)
	var changed_construction := SourceRevision.create(
		"CONSTRUCTION", "construct/alpha", 3, 13,
		h({"construct": 13}), String(fixture["construction"]["dependency_hash"])
	)
	wrong_revision_live["canonical_source_frontier"] = Frontier.create([changed_construction, fixture["matter"]])
	var wrong_revision_gate := ExecutionGate.can_execute(artifact, wrong_revision_live)
	assert(not bool(wrong_revision_gate.get("success", false)) and error_code(wrong_revision_gate) == "BAKE_SOURCE_FRONTIER_MISMATCH"); checks += 1

	var wrong_dependency_live: Dictionary = live.duplicate(true)
	wrong_dependency_live["dependency_set"] = DependencySet.create([
		{"dependency_id": "dependency/fabric-kernel", "dependency_hash": h({"fabric": "tampered"})},
		{"dependency_id": "dependency/material-table", "dependency_hash": h({"material": "v4"})},
	])
	var wrong_dependency_gate := ExecutionGate.can_execute(artifact, wrong_dependency_live)
	assert(not bool(wrong_dependency_gate.get("success", false)) and error_code(wrong_dependency_gate) == "BAKE_DEPENDENCY_MISMATCH"); checks += 1

	var wrong_graph_live: Dictionary = live.duplicate(true)
	wrong_graph_live["fabric_graph_hash"] = h({"graph": "wrong"})
	assert(error_code(ExecutionGate.can_execute(artifact, wrong_graph_live)) == "BAKE_FABRIC_GRAPH_MISMATCH"); checks += 1

	var wrong_compiler_live: Dictionary = live.duplicate(true)
	wrong_compiler_live["fabric_compiler_version"] = "FABRIC0.99/invalid"
	assert(error_code(ExecutionGate.can_execute(artifact, wrong_compiler_live)) == "BAKE_FABRIC_COMPILER_MISMATCH"); checks += 1

	var wrong_boundary_live: Dictionary = live.duplicate(true)
	wrong_boundary_live["boundary_contract_hash"] = h({"boundary": "wrong"})
	assert(error_code(ExecutionGate.can_execute(artifact, wrong_boundary_live)) == "BAKE_BOUNDARY_CONTRACT_MISMATCH"); checks += 1

	var stale_live: Dictionary = live.duplicate(true)
	stale_live["artifact_state"] = "STALE"
	assert(error_code(ExecutionGate.can_execute(artifact, stale_live)) == "STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN"); checks += 1

	var validity_exit_live: Dictionary = live.duplicate(true)
	validity_exit_live["runtime_domain"] = live["runtime_domain"].duplicate(true)
	validity_exit_live["runtime_domain"]["quantities"] = {"quantity/torque": 450.0}
	assert(error_code(ExecutionGate.can_execute(artifact, validity_exit_live)) == "BAKE_VALIDITY_EXIT_QUANTITY"); checks += 1

	var guard_live: Dictionary = live.duplicate(true)
	guard_live["guard_values"] = {"guard/region-a": 76.0}
	assert(error_code(ExecutionGate.can_execute(artifact, guard_live)) == "BAKE_REFINEMENT_REQUIRED"); checks += 1

	var estimator_live: Dictionary = live.duplicate(true)
	estimator_live["runtime_error_estimator"] = RuntimeErrorEstimator.create(
		"estimator/aggregate-a", 0.02, 0.005, 0.01, 0.0005, 0.0005, 0.0005, 0.7, 15.0, 2.0
	)
	assert(error_code(ExecutionGate.can_execute(artifact, estimator_live)) == "BAKE_RUNTIME_ERROR_BOUND_EXCEEDED"); checks += 1

	# Existing representation revision/invalidation semantics drive BAKE-BRIDGE-0.
	var rollback_source := SourceRevision.create(
		"CONSTRUCTION", "construct/alpha", 2, 13,
		h({"construct": "rollback"}), String(fixture["construction"]["dependency_hash"])
	)
	var rollback_invalidation := RepresentationInvalidation.create(
		"invalidation/rollback",
		fixture["construction"],
		rollback_source,
		[0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
		"MUTATION",
		["scope/construct-alpha"],
		20
	)
	assert(rollback_invalidation.is_empty()); checks += 1

	var source_invalidation := RepresentationInvalidation.create(
		"invalidation/construct-alpha-r13",
		fixture["construction"],
		changed_construction,
		[0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
		"MUTATION",
		["scope/construct-alpha"],
		21
	)
	assert(not source_invalidation.is_empty()); checks += 1
	var current_frontier := Frontier.create([changed_construction, fixture["matter"]])
	var bake_invalidation := Bridge0.invalidate_from_source_mutation(
		artifact, source_invalidation, current_frontier, 21
	)
	assert(not bake_invalidation.is_empty()); checks += 1
	assert(String(bake_invalidation["reason"]) == "SOURCE_REVISION"); checks += 1
	assert(String(bake_invalidation["state_after"]) == "STALE"); checks += 1

	var bridge_live: Dictionary = live.duplicate(true)
	bridge_live["invalidations"] = [bake_invalidation]
	var bridge_gate := ExecutionGate.can_execute(artifact, bridge_live)
	assert(error_code(bridge_gate) == "STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN"); checks += 1

	# Mutation of unrelated bytes cannot preserve executable identity by accident.
	assert(String(current_frontier["frontier_hash"]) != String(fixture["frontier"]["frontier_hash"])); checks += 1
	assert(String(bake_invalidation["previous_source_frontier_hash"]) == String(fixture["frontier"]["frontier_hash"])); checks += 1
	assert(String(bake_invalidation["current_source_frontier_hash"]) == String(current_frontier["frontier_hash"])); checks += 1

	print("FABRIC-BAKE B0.0 Acceptance: PASS (%d assertions) artifact=%s frontier=%s invalidation=%s" % [
		checks,
		String(artifact["checksum"]),
		String(fixture["frontier"]["frontier_hash"]),
		String(bake_invalidation["checksum"]),
	])
	quit(0)
