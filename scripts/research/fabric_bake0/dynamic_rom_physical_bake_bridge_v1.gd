extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const FullModel = preload("res://scripts/research/fabric_bake0/dynamic_full_model_descriptor_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/dynamic_rom_descriptor_v1.gd")
const ReductionBinding = preload("res://scripts/research/fabric_bake0/dynamic_rom_artifact_binding_v1.gd")
const Certification = preload("res://scripts/research/fabric_bake0/dynamic_rom_runtime_certification_v1.gd")
const ReconstructionDescriptor = preload("res://scripts/research/fabric_bake0/reconstruction_descriptor_v1.gd")
const StateMapping = preload("res://scripts/research/fabric_bake0/bake_state_mapping_v1.gd")
const FoundationCompiler = preload("res://scripts/research/fabric_bake0/fabric_bake_foundation_compiler_v1.gd")
const PhysicalArtifact = preload("res://scripts/research/fabric_bake0/physical_bake_artifact_v1.gd")
const BakeExecutionGate = preload("res://scripts/research/fabric_bake0/bake_execution_gate_v1.gd")
const BakeInvalidation = preload("res://scripts/research/fabric_bake0/bake_invalidation_v1.gd")
const ExecutionArtifact = preload("res://scripts/research/fabric_bake0/dynamic_rom_execution_artifact_v1.gd")
const ExecutionRuntime = preload("res://scripts/research/fabric_bake0/dynamic_rom_execution_runtime_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_dynamic_rom_physical_bundle.v1"
const MAPPING_VERSION := "FABRIC-BAKE/B0.4-D/ROM-STATE-MAPPING-R1"
const RECONSTRUCTION_VERSION := "FABRIC-BAKE/B0.4-D/ROM-RECONSTRUCTION-R1"
const PROJECTION_METHOD := "C_INNER_PRODUCT_GALERKIN_PROJECTION_R1"
const RECONSTRUCTION_METHOD := "GALERKIN_BASIS_RECONSTRUCTION_R1"
const FIELDS: Array[String] = [
	"schema", "physical_artifact", "execution_artifact",
	"reconstruction_descriptor", "state_mapping", "mapping_contract_hash",
	"build_generation", "bundle_hash", "checksum",
]

static func compile_bundle(
	full_model: Dictionary,
	descriptor: Dictionary,
	reduction_binding: Dictionary,
	certification: Dictionary,
	physical_artifact_id: String = "bake/dynamic-rom-b0-4-d-r1",
	execution_artifact_id: String = "artifact/dynamic-rom-b0-4-d-r1",
	build_generation: int = 1
) -> Dictionary:
	var checked := _validate_inputs(full_model, descriptor, reduction_binding, certification)
	if not bool(checked.get("success", false)):
		return checked
	if build_generation < 1:
		return Utils.failure("DYNAMIC_ROM_PHYSICAL_BAKE_INVALID_BUILD_GENERATION")

	var mapping_contract_hash := _mapping_contract_hash(full_model, descriptor)
	var source_keys: Array = Frontier.source_keys(full_model["source_binding"]["canonical_source_frontier"])
	source_keys.sort()
	var reconstruction := ReconstructionDescriptor.create(
		"reconstruction/dynamic-rom-b0-4-d-r1",
		String(full_model["source_binding"]["frontier_hash"]),
		mapping_contract_hash,
		"CANONICAL_PLUS_REDUCED",
		[{"region_id": "region/dynamic/all", "source_keys": source_keys}],
		"BOUNDED",
		Utils.canonical_hash({
			"owner": "FABRIC_PHYSICAL_EVENT",
			"mode_scope": "MODE_LOCAL_DYNAMIC_ROM_R1",
			"source_frontier_hash": full_model["source_binding"]["frontier_hash"],
		}),
		RECONSTRUCTION_VERSION
	)
	if reconstruction.is_empty():
		return Utils.failure("DYNAMIC_ROM_RECONSTRUCTION_DESCRIPTOR_CREATE_FAILED")
	var state_mapping := StateMapping.create(
		"state-mapping/dynamic-rom-b0-4-d-r1",
		String(descriptor["full_state_schema_hash"]),
		String(descriptor["reduced_state_schema_hash"]),
		mapping_contract_hash,
		String(reconstruction["checksum"])
	)
	if state_mapping.is_empty():
		return Utils.failure("DYNAMIC_ROM_STATE_MAPPING_CREATE_FAILED")

	var source_binding: Dictionary = full_model["source_binding"]
	var compiled := FoundationCompiler.compile({
		"artifact_id": physical_artifact_id,
		"reduction_class": "APPROXIMATE",
		"canonical_source_frontier": source_binding["canonical_source_frontier"],
		"authority_envelope": source_binding["authority_envelope"],
		"dependency_set": source_binding["dependency_set"],
		"fabric_graph_hash": String(source_binding["fabric_graph_hash"]),
		"fabric_compiler_version": String(source_binding["fabric_compiler_version"]),
		"boundary_contract": full_model["boundary_contract"],
		"bake_policy_hash": String(source_binding["bake_policy_hash"]),
		"reduced_model_descriptor_hash": String(descriptor["descriptor_hash"]),
		"reduced_state_schema_hash": String(descriptor["reduced_state_schema_hash"]),
		"validated_domain": certification["validated_domain"],
		"error_envelope": certification["error_envelope"],
		"conservation_envelope": certification["conservation_envelope"],
		"refinement_guards": certification["refinement_guards"],
		"reconstruction_descriptor": reconstruction,
		"state_mapping": state_mapping,
		"build_generation": build_generation,
		"error_certified": true,
		"refinement_guard_certified": true,
		"complexity_reduction_certified": true,
	})
	if String(compiled.get("status", "")) != "BAKE_READY":
		return Utils.failure("DYNAMIC_ROM_PHYSICAL_BAKE_FOUNDATION_NOT_READY", {"result": compiled})
	var physical_artifact: Dictionary = compiled["artifact"]
	if String(physical_artifact["source_binding"]["checksum"]) != String(source_binding["checksum"]):
		return Utils.failure("DYNAMIC_ROM_PHYSICAL_BAKE_SOURCE_BINDING_CHANGED")

	var execution_artifact := ExecutionArtifact.create(
		full_model,
		descriptor,
		reduction_binding,
		certification,
		execution_artifact_id,
		build_generation
	)
	if execution_artifact.is_empty():
		return Utils.failure("DYNAMIC_ROM_EXECUTION_ARTIFACT_CREATE_FAILED")

	var value: Dictionary = {
		"schema": SCHEMA,
		"physical_artifact": physical_artifact,
		"execution_artifact": execution_artifact,
		"reconstruction_descriptor": reconstruction,
		"state_mapping": state_mapping,
		"mapping_contract_hash": mapping_contract_hash,
		"build_generation": build_generation,
		"bundle_hash": "",
		"checksum": "",
	}
	value["bundle_hash"] = Utils.canonical_hash(_bundle_payload(value))
	value["checksum"] = Utils.compute_checksum(value)
	checked = validate(value, full_model, descriptor, reduction_binding, certification)
	if not bool(checked.get("success", false)):
		return checked
	return Utils.success({"bundle": value})

static func validate(
	bundle: Dictionary,
	full_model: Dictionary,
	descriptor: Dictionary,
	reduction_binding: Dictionary,
	certification: Dictionary
) -> Dictionary:
	var checked := Utils.validate_exact_fields(bundle, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if bundle.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_DYNAMIC_ROM_PHYSICAL_BUNDLE_SCHEMA")
	checked = _validate_inputs(full_model, descriptor, reduction_binding, certification)
	if not bool(checked.get("success", false)):
		return checked
	if typeof(bundle.get("physical_artifact")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_DYNAMIC_ROM_PHYSICAL_ARTIFACT")
	checked = PhysicalArtifact.validate(bundle["physical_artifact"])
	if not bool(checked.get("success", false)):
		return checked
	if typeof(bundle.get("execution_artifact")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_DYNAMIC_ROM_EXECUTION_ARTIFACT")
	checked = ExecutionArtifact.verify_bindings(
		bundle["execution_artifact"], full_model, descriptor, reduction_binding, certification
	)
	if not bool(checked.get("success", false)):
		return checked
	if typeof(bundle.get("reconstruction_descriptor")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_DYNAMIC_ROM_RECONSTRUCTION_DESCRIPTOR")
	checked = ReconstructionDescriptor.validate(bundle["reconstruction_descriptor"])
	if not bool(checked.get("success", false)):
		return checked
	if typeof(bundle.get("state_mapping")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_DYNAMIC_ROM_STATE_MAPPING")
	checked = StateMapping.validate(bundle["state_mapping"])
	if not bool(checked.get("success", false)):
		return checked
	if not Utils.is_lower_hex_64(bundle.get("mapping_contract_hash")):
		return Utils.failure("INVALID_DYNAMIC_ROM_MAPPING_CONTRACT_HASH")
	if String(bundle["mapping_contract_hash"]) != _mapping_contract_hash(full_model, descriptor):
		return Utils.failure("DYNAMIC_ROM_MAPPING_CONTRACT_HASH_MISMATCH")
	if String(bundle["reconstruction_descriptor"]["mapping_hash"]) != String(bundle["mapping_contract_hash"]):
		return Utils.failure("DYNAMIC_ROM_RECONSTRUCTION_MAPPING_HASH_MISMATCH")
	if String(bundle["state_mapping"]["projection_hash"]) != String(bundle["mapping_contract_hash"]):
		return Utils.failure("DYNAMIC_ROM_STATE_MAPPING_PROJECTION_HASH_MISMATCH")
	if String(bundle["state_mapping"]["reconstruction_descriptor_hash"]) != String(bundle["reconstruction_descriptor"]["checksum"]):
		return Utils.failure("DYNAMIC_ROM_STATE_MAPPING_RECONSTRUCTION_MISMATCH")
	var physical: Dictionary = bundle["physical_artifact"]
	var execution: Dictionary = bundle["execution_artifact"]
	if String(physical["source_binding"]["checksum"]) != String(full_model["source_binding"]["checksum"]):
		return Utils.failure("DYNAMIC_ROM_PHYSICAL_ARTIFACT_SOURCE_MISMATCH")
	if String(physical["reduced_model_descriptor_hash"]) != String(descriptor["descriptor_hash"]):
		return Utils.failure("DYNAMIC_ROM_PHYSICAL_ARTIFACT_DESCRIPTOR_MISMATCH")
	if String(physical["reduced_state_schema_hash"]) != String(descriptor["reduced_state_schema_hash"]):
		return Utils.failure("DYNAMIC_ROM_PHYSICAL_ARTIFACT_STATE_SCHEMA_MISMATCH")
	if String(physical["reconstruction_descriptor"]["checksum"]) != String(bundle["reconstruction_descriptor"]["checksum"]):
		return Utils.failure("DYNAMIC_ROM_PHYSICAL_ARTIFACT_RECONSTRUCTION_MISMATCH")
	if String(physical["state_mapping"]["checksum"]) != String(bundle["state_mapping"]["checksum"]):
		return Utils.failure("DYNAMIC_ROM_PHYSICAL_ARTIFACT_MAPPING_MISMATCH")
	if int(physical["build_generation"]) != int(bundle["build_generation"]):
		return Utils.failure("DYNAMIC_ROM_PHYSICAL_ARTIFACT_GENERATION_MISMATCH")
	if int(execution["build_generation"]) != int(bundle["build_generation"]):
		return Utils.failure("DYNAMIC_ROM_EXECUTION_ARTIFACT_GENERATION_MISMATCH")
	if String(execution["source_binding_checksum"]) != String(physical["source_binding"]["checksum"]):
		return Utils.failure("DYNAMIC_ROM_DUAL_ARTIFACT_SOURCE_MISMATCH")
	if not Utils.is_json_integer(bundle.get("build_generation")) or int(bundle["build_generation"]) < 1:
		return Utils.failure("INVALID_DYNAMIC_ROM_PHYSICAL_BUNDLE_GENERATION")
	if not Utils.is_lower_hex_64(bundle.get("bundle_hash")) or String(bundle["bundle_hash"]) != Utils.canonical_hash(_bundle_payload(bundle)):
		return Utils.failure("DYNAMIC_ROM_PHYSICAL_BUNDLE_HASH_MISMATCH")
	return Utils.validate_checksum(bundle)

static func project_full_values(full_model: Dictionary, descriptor: Dictionary, full_values: Array) -> Dictionary:
	var checked := FullModel.validate(full_model)
	if not bool(checked.get("success", false)):
		return checked
	checked = Descriptor.validate(descriptor)
	if not bool(checked.get("success", false)):
		return checked
	if String(descriptor["full_model_hash"]) != String(full_model["model_hash"]):
		return Utils.failure("DYNAMIC_ROM_STATE_MAPPING_FULL_MODEL_MISMATCH")
	if full_values.size() != int(descriptor["full_state_count"]):
		return Utils.failure("DYNAMIC_ROM_STATE_MAPPING_FULL_LENGTH_MISMATCH")
	var reduced: Array = []
	reduced.resize(int(descriptor["reduced_state_count"]))
	reduced.fill(0.0)
	for full_index in range(full_values.size()):
		if not Utils.is_finite_number(full_values[full_index]):
			return Utils.failure("DYNAMIC_ROM_STATE_MAPPING_NONFINITE_FULL_STATE")
		var weighted := float(full_model["storage_nodes"][full_index]["storage_coefficient"]) * float(full_values[full_index])
		for reduced_index in range(reduced.size()):
			reduced[reduced_index] = float(reduced[reduced_index]) + float(descriptor["basis_matrix"][full_index][reduced_index]) * weighted
	var reconstructed := reconstruct_values(descriptor, reduced)
	if not bool(reconstructed.get("success", false)):
		return reconstructed
	var max_abs_error := 0.0
	var c_error_squared := 0.0
	for index in range(full_values.size()):
		var delta := float(full_values[index]) - float(reconstructed["details"]["full_values"][index])
		max_abs_error = maxf(max_abs_error, absf(delta))
		c_error_squared += float(full_model["storage_nodes"][index]["storage_coefficient"]) * delta * delta
	return Utils.success({
		"reduced_values": reduced,
		"projection_error_max_abs": max_abs_error,
		"projection_error_c_norm": sqrt(maxf(0.0, c_error_squared)),
		"projection_hash": _mapping_contract_hash(full_model, descriptor),
	})

static func reconstruct_values(descriptor: Dictionary, reduced_values: Array) -> Dictionary:
	var checked := Descriptor.validate(descriptor)
	if not bool(checked.get("success", false)):
		return checked
	if reduced_values.size() != int(descriptor["reduced_state_count"]):
		return Utils.failure("DYNAMIC_ROM_RECONSTRUCTION_REDUCED_LENGTH_MISMATCH")
	var full: Array = []
	full.resize(int(descriptor["full_state_count"]))
	for full_index in range(full.size()):
		var value := 0.0
		for reduced_index in range(reduced_values.size()):
			if not Utils.is_finite_number(reduced_values[reduced_index]):
				return Utils.failure("DYNAMIC_ROM_RECONSTRUCTION_NONFINITE_REDUCED_STATE")
			value += float(descriptor["basis_matrix"][full_index][reduced_index]) * float(reduced_values[reduced_index])
		full[full_index] = value
	return Utils.success({"full_values": full})

static func start_execution(
	bundle: Dictionary,
	full_model: Dictionary,
	descriptor: Dictionary,
	reduction_binding: Dictionary,
	certification: Dictionary
) -> Dictionary:
	var checked := validate(bundle, full_model, descriptor, reduction_binding, certification)
	if not bool(checked.get("success", false)):
		return checked
	return ExecutionRuntime.start(
		bundle["execution_artifact"], full_model, descriptor, reduction_binding, certification
	)

static func governed_step(
	bundle: Dictionary,
	session: Dictionary,
	full_model: Dictionary,
	descriptor: Dictionary,
	reduction_binding: Dictionary,
	certification: Dictionary,
	port_flows: Dictionary,
	delta_s: float,
	current_source_binding_checksum: String,
	invalidations: Array = [],
	local_unbake_available: bool = false
) -> Dictionary:
	var checked := validate(bundle, full_model, descriptor, reduction_binding, certification)
	if not bool(checked.get("success", false)):
		return checked
	var low_level := ExecutionRuntime.step(
		session, bundle["execution_artifact"], full_model, descriptor, reduction_binding, certification,
		port_flows, delta_s, current_source_binding_checksum, local_unbake_available
	)
	if not bool(low_level.get("success", false)):
		return low_level
	var next_session: Dictionary = low_level["details"]["session"]
	var estimate := Certification.estimate_after_step(
		certification,
		full_model,
		descriptor,
		float(session["error_c_norm_bound"]),
		session["rom_state"]["values"],
		next_session["rom_state"]["values"],
		port_flows,
		delta_s,
		float(next_session["elapsed_s"])
	)
	if not bool(estimate.get("success", false)):
		return Utils.failure("DYNAMIC_ROM_PHYSICAL_GATE_ESTIMATE_FAILED", {
			"cause": estimate.get("error_code", "ESTIMATE_FAILED"),
			"session": session,
		})
	var gate := can_execute(bundle, full_model, estimate["details"], invalidations)
	if not bool(gate.get("success", false)):
		return Utils.failure("DYNAMIC_ROM_PHYSICAL_BAKE_EXECUTION_FORBIDDEN", {
			"cause": gate.get("error_code", "PHYSICAL_BAKE_GATE_FAILED"),
			"gate": gate,
			"session": session,
		})
	var details: Dictionary = low_level["details"].duplicate(true)
	details["physical_bake_gate"] = gate["details"]
	details["physical_artifact_id"] = String(bundle["physical_artifact"]["artifact_id"])
	return Utils.success(details)

static func can_execute(
	bundle: Dictionary,
	full_model: Dictionary,
	estimate_details: Dictionary,
	invalidations: Array = [],
	artifact_state: String = "READY"
) -> Dictionary:
	if typeof(bundle.get("physical_artifact")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_DYNAMIC_ROM_PHYSICAL_BAKE_BUNDLE")
	if typeof(estimate_details.get("runtime_domain")) != TYPE_DICTIONARY or typeof(estimate_details.get("estimator")) != TYPE_DICTIONARY or typeof(estimate_details.get("guard_values")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_DYNAMIC_ROM_PHYSICAL_BAKE_LIVE_ESTIMATE")
	var source_binding: Dictionary = full_model["source_binding"]
	return BakeExecutionGate.can_execute(bundle["physical_artifact"], {
		"artifact_state": artifact_state,
		"canonical_source_frontier": source_binding["canonical_source_frontier"],
		"authority_envelope": source_binding["authority_envelope"],
		"dependency_set": source_binding["dependency_set"],
		"fabric_graph_hash": String(source_binding["fabric_graph_hash"]),
		"fabric_compiler_version": String(source_binding["fabric_compiler_version"]),
		"boundary_contract_hash": String(source_binding["boundary_contract_hash"]),
		"bake_policy_hash": String(source_binding["bake_policy_hash"]),
		"runtime_domain": estimate_details["runtime_domain"],
		"runtime_error_estimator": estimate_details["estimator"],
		"guard_values": estimate_details["guard_values"],
		"invalidations": invalidations.duplicate(true),
	})

static func create_source_invalidation(bundle: Dictionary, current_frontier_hash: String, created_tick: int) -> Dictionary:
	if typeof(bundle.get("physical_artifact")) != TYPE_DICTIONARY:
		return {}
	var artifact: Dictionary = bundle["physical_artifact"]
	return BakeInvalidation.create(
		"invalidation/dynamic-rom/source-%06d" % created_tick,
		String(artifact["artifact_id"]),
		"SOURCE_REVISION",
		String(artifact["source_binding"]["frontier_hash"]),
		current_frontier_hash,
		created_tick
	)

static func _validate_inputs(
	full_model: Dictionary,
	descriptor: Dictionary,
	reduction_binding: Dictionary,
	certification: Dictionary
) -> Dictionary:
	var checked := FullModel.validate(full_model)
	if not bool(checked.get("success", false)):
		return checked
	checked = Descriptor.validate(descriptor)
	if not bool(checked.get("success", false)):
		return checked
	checked = ReductionBinding.validate(reduction_binding)
	if not bool(checked.get("success", false)):
		return checked
	checked = Certification.validate(certification)
	if not bool(checked.get("success", false)):
		return checked
	if String(descriptor["full_model_hash"]) != String(full_model["model_hash"]):
		return Utils.failure("DYNAMIC_ROM_PHYSICAL_BAKE_FULL_MODEL_MISMATCH")
	if String(descriptor["source_binding_checksum"]) != String(full_model["source_binding"]["checksum"]):
		return Utils.failure("DYNAMIC_ROM_PHYSICAL_BAKE_SOURCE_MISMATCH")
	if String(reduction_binding["reduced_model_descriptor_hash"]) != String(descriptor["descriptor_hash"]):
		return Utils.failure("DYNAMIC_ROM_PHYSICAL_BAKE_REDUCTION_MISMATCH")
	if String(certification["rom_descriptor_hash"]) != String(descriptor["descriptor_hash"]):
		return Utils.failure("DYNAMIC_ROM_PHYSICAL_BAKE_CERTIFICATION_MISMATCH")
	return Utils.success()

static func _mapping_contract_hash(full_model: Dictionary, descriptor: Dictionary) -> String:
	return Utils.canonical_hash({
		"version": MAPPING_VERSION,
		"projection_method": PROJECTION_METHOD,
		"reconstruction_method": RECONSTRUCTION_METHOD,
		"full_model_hash": full_model.get("model_hash", ""),
		"full_state_schema_hash": descriptor.get("full_state_schema_hash", ""),
		"reduced_state_schema_hash": descriptor.get("reduced_state_schema_hash", ""),
		"basis_hash": descriptor.get("basis_hash", ""),
	})

static func _bundle_payload(value: Dictionary) -> Dictionary:
	var payload := value.duplicate(true)
	payload.erase("bundle_hash")
	payload.erase("checksum")
	return payload
