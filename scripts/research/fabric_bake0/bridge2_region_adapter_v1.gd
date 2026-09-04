extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Entry = preload("res://scripts/research/fabric_bake0/bridge2_entry_contract_v1.gd")
const Slice = preload("res://scripts/research/fabric_bake0/bridge2_source_slice_v1.gd")
const FoundationCompiler = preload("res://scripts/research/fabric_bake0/fabric_bake_foundation_compiler_v1.gd")
const BoundaryContract = preload("res://scripts/research/fabric_bake0/physical_boundary_contract_v1.gd")
const DependencySet = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")
const ValidatedDomain = preload("res://scripts/research/fabric_bake0/validated_domain_v1.gd")
const ErrorEnvelope = preload("res://scripts/research/fabric_bake0/error_envelope_v1.gd")
const ConservationEnvelope = preload("res://scripts/research/fabric_bake0/conservation_envelope_v1.gd")
const ReconstructionDescriptor = preload("res://scripts/research/fabric_bake0/reconstruction_descriptor_v1.gd")
const StateMapping = preload("res://scripts/research/fabric_bake0/bake_state_mapping_v1.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/physical_bake_artifact_v1.gd")

const SCHEMA := "planet_simulator.fabric_bridge2_region_adapter.v1"
const COMPILER_VERSION := "FABRIC/BRIDGE-2/MIXED-GENERIC-MACHINE-R1"
const FIELDS: Array[String] = [
	"schema", "region_id", "representation_kind", "state_id",
	"source_slice", "boundary_contract", "backend_contract_hash",
	"storage", "damping", "artifact", "adapter_hash", "checksum",
]

static func create(
	region_id: String,
	representation_kind: String,
	state_id: String,
	source_slice: Dictionary,
	backend_contract_hash: String,
	storage: float,
	damping: float,
	build_generation: int = 1
) -> Dictionary:
	if not Entry.REPRESENTATIONS.has(representation_kind):
		return {}
	var checked := Slice.validate(source_slice)
	if not bool(checked.get("success", false)):
		return {}
	if not Utils.is_positive_number(storage) or not Utils.is_non_negative_number(damping):
		return {}
	var boundary := _boundary(region_id)
	if boundary.is_empty():
		return {}
	var artifact: Dictionary = {}
	if representation_kind != "FULL":
		artifact = _compile_artifact(
			region_id, representation_kind, state_id, source_slice,
			backend_contract_hash, boundary, build_generation
		)
		if artifact.is_empty():
			return {}
	var value: Dictionary = {
		"schema": SCHEMA,
		"region_id": region_id,
		"representation_kind": representation_kind,
		"state_id": state_id,
		"source_slice": source_slice.duplicate(true),
		"boundary_contract": boundary,
		"backend_contract_hash": backend_contract_hash,
		"storage": storage,
		"damping": damping,
		"artifact": artifact,
		"adapter_hash": "",
		"checksum": "",
	}
	value["adapter_hash"] = Utils.canonical_hash(_identity_payload(value))
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_BRIDGE2_REGION_ADAPTER_SCHEMA")
	if not Utils.is_canonical_id(value.get("region_id"), 2) or not Utils.is_canonical_id(value.get("state_id"), 2):
		return Utils.failure("INVALID_BRIDGE2_REGION_ADAPTER_ID")
	if not Entry.REPRESENTATIONS.has(String(value.get("representation_kind", ""))):
		return Utils.failure("INVALID_BRIDGE2_REGION_REPRESENTATION_KIND")
	checked = Slice.validate(value["source_slice"])
	if not bool(checked.get("success", false)):
		return checked
	checked = BoundaryContract.validate(value["boundary_contract"])
	if not bool(checked.get("success", false)):
		return checked
	if not Utils.is_lower_hex_64(value.get("backend_contract_hash")):
		return Utils.failure("INVALID_BRIDGE2_BACKEND_CONTRACT_HASH")
	if not Utils.is_positive_number(value.get("storage")) or not Utils.is_non_negative_number(value.get("damping")):
		return Utils.failure("INVALID_BRIDGE2_PASSIVE_REGION_PARAMETERS")
	var kind := String(value["representation_kind"])
	if kind == "FULL":
		if typeof(value.get("artifact")) != TYPE_DICTIONARY or not value["artifact"].is_empty():
			return Utils.failure("BRIDGE2_FULL_REGION_MUST_NOT_OWN_BAKE_ARTIFACT")
	else:
		if typeof(value.get("artifact")) != TYPE_DICTIONARY or value["artifact"].is_empty():
			return Utils.failure("BRIDGE2_DERIVED_REGION_REQUIRES_ARTIFACT")
		checked = Artifact.validate(value["artifact"])
		if not bool(checked.get("success", false)):
			return checked
		if String(value["artifact"]["source_binding"]["frontier_hash"]) != String(value["source_slice"]["frontier"]["frontier_hash"]):
			return Utils.failure("BRIDGE2_REGION_ARTIFACT_SLICE_MISMATCH")
		if String(value["artifact"]["boundary_contract"]["contract_hash"]) != String(value["boundary_contract"]["contract_hash"]):
			return Utils.failure("BRIDGE2_REGION_BOUNDARY_ARTIFACT_MISMATCH")
	if not Utils.is_lower_hex_64(value.get("adapter_hash")):
		return Utils.failure("INVALID_BRIDGE2_REGION_ADAPTER_HASH")
	if String(value["adapter_hash"]) != Utils.canonical_hash(_identity_payload(value)):
		return Utils.failure("BRIDGE2_REGION_ADAPTER_HASH_MISMATCH")
	return Utils.validate_checksum(value)

static func port_id(region_id: String, side: String) -> String:
	return "port/bridge2-%s-%s" % [region_id.replace("/", "-"), side]

static func _compile_artifact(
	region_id: String,
	representation_kind: String,
	state_id: String,
	source_slice: Dictionary,
	backend_contract_hash: String,
	boundary: Dictionary,
	build_generation: int
) -> Dictionary:
	var frontier: Dictionary = source_slice["frontier"]
	var graph_hash := Utils.canonical_hash({
		"bridge2_region": region_id,
		"representation_kind": representation_kind,
		"state_id": state_id,
		"source_slice_hash": source_slice["slice_hash"],
		"backend_contract_hash": backend_contract_hash,
	})
	var dependencies := DependencySet.create([
		{
			"dependency_id": "dependency/bridge2-backend-%s" % region_id.replace("/", "-"),
			"dependency_hash": backend_contract_hash,
		},
		{
			"dependency_id": "dependency/sync4-entry",
			"dependency_hash": Utils.canonical_hash({"sync4": "51403977606f6f88fa8d31b3505a6c83361a4a3f"}),
		},
	])
	var validated := ValidatedDomain.create(
		String(frontier["frontier_hash"]), graph_hash, [], [representation_kind], 10.0
	)
	var errors := ErrorEnvelope.create(
		1.0e-12, 0.0, 1.0e-12, 0.0,
		1.0e-12, 0.0, 1.0e-12, 0.0,
		1.0e-12, 1.0e-12, 1.0e-12, 10.0, true
	)
	var conservation := ConservationEnvelope.create(1.0e-12, 1.0e-12, 1.0e-12, 1.0e-12, 0.0)
	var mapping_hash := Utils.canonical_hash({
		"method": "BRIDGE2_IDENTITY_SCALAR_HANDOFF_R1",
		"region_id": region_id,
		"state_id": state_id,
		"backend_contract_hash": backend_contract_hash,
	})
	var source_keys: Array = source_slice["source_keys"].duplicate()
	var reconstruction := ReconstructionDescriptor.create(
		"reconstruction/bridge2-%s" % region_id.replace("/", "-"),
		String(frontier["frontier_hash"]),
		mapping_hash,
		"CANONICAL_PLUS_REDUCED",
		[{"region_id": region_id, "source_keys": source_keys}],
		"STRICT",
		Utils.canonical_hash({"event_owner": "FABRIC_PHYSICAL_EVENT", "region_id": region_id}),
		COMPILER_VERSION
	)
	if reconstruction.is_empty():
		return {}
	var full_schema_hash := Utils.canonical_hash({"state_id": state_id, "schema": "bridge2.full.scalar.r1"})
	var reduced_schema_hash := Utils.canonical_hash({"state_id": state_id, "schema": "bridge2.reduced.scalar.r1", "kind": representation_kind})
	var mapping := StateMapping.create(
		"state-mapping/bridge2-%s" % region_id.replace("/", "-"),
		full_schema_hash,
		reduced_schema_hash,
		mapping_hash,
		String(reconstruction["checksum"])
	)
	if mapping.is_empty():
		return {}
	var compiled := FoundationCompiler.compile({
		"artifact_id": "bake/bridge2-%s" % region_id.replace("/", "-"),
		"reduction_class": "EXACT",
		"canonical_source_frontier": frontier,
		"authority_envelope": source_slice["authority_envelope"],
		"dependency_set": dependencies,
		"fabric_graph_hash": graph_hash,
		"fabric_compiler_version": COMPILER_VERSION,
		"boundary_contract": boundary,
		"bake_policy_hash": Utils.canonical_hash({
			"policy": "BRIDGE2_EXACT_REGION_ADAPTER_R1",
			"representation_kind": representation_kind,
			"backend_contract_hash": backend_contract_hash,
		}),
		"reduced_model_descriptor_hash": backend_contract_hash,
		"reduced_state_schema_hash": reduced_schema_hash,
		"validated_domain": validated,
		"error_envelope": errors,
		"conservation_envelope": conservation,
		"refinement_guards": [],
		"reconstruction_descriptor": reconstruction,
		"state_mapping": mapping,
		"build_generation": build_generation,
		"error_certified": true,
		"refinement_guard_certified": true,
		"complexity_reduction_certified": true,
	})
	if String(compiled.get("status", "")) != "BAKE_READY":
		return {}
	return compiled["artifact"]

static func _boundary(region_id: String) -> Dictionary:
	var ports: Array = []
	for side in ["left", "right"]:
		ports.append({
			"port_id": port_id(region_id, side),
			"physical_domain": "GENERIC",
			"effort_quantity": "quantity/bridge2-effort",
			"flow_quantity": "quantity/bridge2-flow",
			"effort_dimension": [0, 0, 0, 0, 0, 0, 0],
			"flow_dimension": [0, 0, -1, 0, 0, 0, 0],
			"frame": "frame/bridge2-%s" % region_id.replace("/", "-"),
			"orientation": "INTO_SUBSYSTEM",
			"conservation_group": "group/bridge2-generic-power",
			"event_observables": ["REPRESENTATION_CHANGE", "SOURCE_INVALIDATION"],
		})
	return BoundaryContract.create(ports)

static func _identity_payload(value: Dictionary) -> Dictionary:
	var payload := value.duplicate(true)
	payload.erase("adapter_hash")
	payload.erase("checksum")
	return payload
