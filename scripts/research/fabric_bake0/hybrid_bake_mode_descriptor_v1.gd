extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const ModeSignature = preload("res://scripts/research/fabric_bake0/hybrid_mode_signature_v1.gd")
const ValidatedDomain = preload("res://scripts/research/fabric_bake0/validated_domain_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_hybrid_mode_descriptor.v1"
const ROM_FIELDS: Array[String] = [
	"interface_kind", "artifact_checksum", "reduced_state_schema_hash",
	"state_mapping_checksum", "reconstruction_descriptor_checksum",
]
const FIELDS: Array[String] = [
	"schema", "descriptor_id", "mode_signature", "validated_domain",
	"dynamic_rom_binding", "build_generation", "cache_key",
	"execution_qualification", "checksum",
]
const INTERFACE_KINDS: Array[String] = [
	"UNRESOLVED_B0_4_INTERFACE",
	"PHYSICAL_BAKE_ARTIFACT",
]
const QUALIFICATIONS: Array[String] = ["PREFLIGHT_ONLY", "B0_4_INTERFACE_BOUND"]

static func unresolved_rom_binding() -> Dictionary:
	return {
		"interface_kind": "UNRESOLVED_B0_4_INTERFACE",
		"artifact_checksum": "",
		"reduced_state_schema_hash": "",
		"state_mapping_checksum": "",
		"reconstruction_descriptor_checksum": "",
	}

static func resolved_rom_binding(
	artifact_checksum: String,
	reduced_state_schema_hash: String,
	state_mapping_checksum: String,
	reconstruction_descriptor_checksum: String
) -> Dictionary:
	return {
		"interface_kind": "PHYSICAL_BAKE_ARTIFACT",
		"artifact_checksum": artifact_checksum,
		"reduced_state_schema_hash": reduced_state_schema_hash,
		"state_mapping_checksum": state_mapping_checksum,
		"reconstruction_descriptor_checksum": reconstruction_descriptor_checksum,
	}

static func create(
	descriptor_id: String,
	mode_signature: Dictionary,
	validated_domain: Dictionary,
	dynamic_rom_binding: Dictionary,
	build_generation: int
) -> Dictionary:
	var qualification := "PREFLIGHT_ONLY"
	if String(dynamic_rom_binding.get("interface_kind", "")) == "PHYSICAL_BAKE_ARTIFACT":
		qualification = "B0_4_INTERFACE_BOUND"
	var value: Dictionary = {
		"schema": SCHEMA,
		"descriptor_id": descriptor_id,
		"mode_signature": mode_signature.duplicate(true),
		"validated_domain": validated_domain.duplicate(true),
		"dynamic_rom_binding": dynamic_rom_binding.duplicate(true),
		"build_generation": build_generation,
		"cache_key": "",
		"execution_qualification": qualification,
		"checksum": "",
	}
	value["cache_key"] = compute_cache_key(value)
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_HYBRID_MODE_DESCRIPTOR_SCHEMA")
	if not Utils.is_canonical_id(value.get("descriptor_id"), 2):
		return Utils.failure("INVALID_HYBRID_MODE_DESCRIPTOR_ID")
	if typeof(value.get("mode_signature")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_HYBRID_MODE_DESCRIPTOR_SIGNATURE")
	checked = ModeSignature.validate(value["mode_signature"])
	if not bool(checked.get("success", false)):
		return checked
	if typeof(value.get("validated_domain")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_HYBRID_MODE_VALIDATED_DOMAIN")
	checked = ValidatedDomain.validate(value["validated_domain"])
	if not bool(checked.get("success", false)):
		return checked
	if String(value["validated_domain"]["exact_frontier_hash"]) != String(value["mode_signature"]["source_frontier_hash"]):
		return Utils.failure("HYBRID_MODE_DOMAIN_FRONTIER_MISMATCH")
	if String(value["validated_domain"]["exact_fabric_graph_hash"]) != String(value["mode_signature"]["physical_topology_hash"]):
		return Utils.failure("HYBRID_MODE_DOMAIN_TOPOLOGY_MISMATCH")
	if typeof(value.get("dynamic_rom_binding")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_HYBRID_MODE_ROM_BINDING")
	checked = Utils.validate_exact_fields(value["dynamic_rom_binding"], ROM_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	var binding: Dictionary = value["dynamic_rom_binding"]
	var kind := String(binding.get("interface_kind", ""))
	if not INTERFACE_KINDS.has(kind):
		return Utils.failure("INVALID_HYBRID_MODE_ROM_INTERFACE_KIND")
	if kind == "UNRESOLVED_B0_4_INTERFACE":
		for field in ["artifact_checksum", "reduced_state_schema_hash", "state_mapping_checksum", "reconstruction_descriptor_checksum"]:
			if String(binding.get(field, "")) != "":
				return Utils.failure("UNRESOLVED_B0_4_INTERFACE_MUST_NOT_CLAIM_RUNTIME_HASH", {"field": field})
		if String(value.get("execution_qualification", "")) != "PREFLIGHT_ONLY":
			return Utils.failure("UNRESOLVED_B0_4_INTERFACE_EXECUTION_FORBIDDEN")
	else:
		for field in ["artifact_checksum", "reduced_state_schema_hash", "state_mapping_checksum", "reconstruction_descriptor_checksum"]:
			if not Utils.is_lower_hex_64(binding.get(field)):
				return Utils.failure("INVALID_B0_4_INTERFACE_HASH", {"field": field})
		if String(value.get("execution_qualification", "")) != "B0_4_INTERFACE_BOUND":
			return Utils.failure("BOUND_B0_4_INTERFACE_QUALIFICATION_MISMATCH")
	if not QUALIFICATIONS.has(String(value.get("execution_qualification", ""))):
		return Utils.failure("INVALID_HYBRID_MODE_EXECUTION_QUALIFICATION")
	if not Utils.is_json_integer(value.get("build_generation")) or int(value["build_generation"]) < 1:
		return Utils.failure("INVALID_HYBRID_MODE_BUILD_GENERATION")
	if not Utils.is_lower_hex_64(value.get("cache_key")):
		return Utils.failure("INVALID_HYBRID_MODE_CACHE_KEY")
	if String(value["cache_key"]) != compute_cache_key(value):
		return Utils.failure("HYBRID_MODE_CACHE_KEY_MISMATCH")
	return Utils.validate_checksum(value)

static func compute_cache_key(value: Dictionary) -> String:
	return Utils.canonical_hash({
		"mode_hash": value.get("mode_signature", {}).get("mode_hash", ""),
		"source_frontier_hash": value.get("mode_signature", {}).get("source_frontier_hash", ""),
		"physical_topology_hash": value.get("mode_signature", {}).get("physical_topology_hash", ""),
		"dependency_fingerprint": ModeSignature.dependency_fingerprint(value.get("mode_signature", {})),
		"boundary_contract_hash": value.get("mode_signature", {}).get("boundary_contract_hash", ""),
		"dynamic_rom_binding": value.get("dynamic_rom_binding", {}),
	})
