extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const ModeSignature = preload("res://scripts/research/fabric_bake0/hybrid_mode_signature_v1.gd")
const ModeDescriptor = preload("res://scripts/research/fabric_bake0/hybrid_bake_mode_descriptor_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_lazy_mode_cache_entry.v1"
const FIELDS: Array[String] = [
	"schema", "cache_key", "mode_hash", "source_frontier_hash",
	"physical_topology_hash", "dependency_fingerprint",
	"b0_4_interface_fingerprint", "build_generation",
	"validity_state", "invalidation_reason", "derived_only",
	"execution_qualification", "checksum",
]
const VALIDITY_STATES: Array[String] = ["VALID", "STALE", "UNRESOLVED"]
const INVALIDATION_REASONS: Array[String] = [
	"NONE",
	"SOURCE_FRONTIER_CHANGED",
	"TOPOLOGY_CHANGED",
	"DEPENDENCY_CHANGED",
	"B0_4_INTERFACE_CHANGED",
	"B0_4_INTERFACE_UNRESOLVED",
]

static func create(mode_descriptor: Dictionary) -> Dictionary:
	var checked: Dictionary = ModeDescriptor.validate(mode_descriptor)
	if not bool(checked.get("success", false)):
		return {}
	var signature: Dictionary = mode_descriptor["mode_signature"]
	var unresolved := String(mode_descriptor["dynamic_rom_binding"]["interface_kind"]) == "UNRESOLVED_B0_4_INTERFACE"
	var value: Dictionary = {
		"schema": SCHEMA,
		"cache_key": String(mode_descriptor["cache_key"]),
		"mode_hash": String(signature["mode_hash"]),
		"source_frontier_hash": String(signature["source_frontier_hash"]),
		"physical_topology_hash": String(signature["physical_topology_hash"]),
		"dependency_fingerprint": ModeSignature.dependency_fingerprint(signature),
		"b0_4_interface_fingerprint": Utils.canonical_hash(mode_descriptor["dynamic_rom_binding"]),
		"build_generation": int(mode_descriptor["build_generation"]),
		"validity_state": "UNRESOLVED" if unresolved else "VALID",
		"invalidation_reason": "B0_4_INTERFACE_UNRESOLVED" if unresolved else "NONE",
		"derived_only": true,
		"execution_qualification": "PREFLIGHT_ONLY",
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_LAZY_MODE_CACHE_SCHEMA")
	for field in [
		"cache_key", "mode_hash", "source_frontier_hash", "physical_topology_hash",
		"dependency_fingerprint", "b0_4_interface_fingerprint",
	]:
		if not Utils.is_lower_hex_64(value.get(field)):
			return Utils.failure("INVALID_LAZY_MODE_CACHE_HASH", {"field": field})
	if not Utils.is_json_integer(value.get("build_generation")) or int(value["build_generation"]) < 1:
		return Utils.failure("INVALID_LAZY_MODE_CACHE_GENERATION")
	if not VALIDITY_STATES.has(String(value.get("validity_state", ""))):
		return Utils.failure("INVALID_LAZY_MODE_CACHE_STATE")
	if not INVALIDATION_REASONS.has(String(value.get("invalidation_reason", ""))):
		return Utils.failure("INVALID_LAZY_MODE_CACHE_REASON")
	if String(value["validity_state"]) == "VALID" and String(value["invalidation_reason"]) != "NONE":
		return Utils.failure("VALID_LAZY_MODE_CACHE_HAS_INVALIDATION")
	if String(value["validity_state"]) == "STALE" and String(value["invalidation_reason"]) == "NONE":
		return Utils.failure("STALE_LAZY_MODE_CACHE_REQUIRES_REASON")
	if typeof(value.get("derived_only")) != TYPE_BOOL or not bool(value["derived_only"]):
		return Utils.failure("LAZY_MODE_CACHE_MUST_BE_DERIVED_ONLY")
	if String(value.get("execution_qualification", "")) != "PREFLIGHT_ONLY":
		return Utils.failure("B0_5_P0_CACHE_EXECUTION_FORBIDDEN")
	return Utils.validate_checksum(value)

static func validate_against(value: Dictionary, mode_signature: Dictionary, mode_descriptor: Dictionary) -> Dictionary:
	var checked: Dictionary = validate(value)
	if not bool(checked.get("success", false)):
		return checked
	checked = ModeSignature.validate(mode_signature)
	if not bool(checked.get("success", false)):
		return checked
	checked = ModeDescriptor.validate(mode_descriptor)
	if not bool(checked.get("success", false)):
		return checked
	if String(value["cache_key"]) != String(mode_descriptor["cache_key"]):
		return Utils.failure("LAZY_MODE_CACHE_KEY_MISMATCH")
	if String(value["mode_hash"]) != String(mode_signature["mode_hash"]):
		return Utils.failure("LAZY_MODE_CACHE_MODE_MISMATCH")
	if String(value["source_frontier_hash"]) != String(mode_signature["source_frontier_hash"]):
		return Utils.failure("LAZY_MODE_CACHE_SOURCE_FRONTIER_MISMATCH")
	if String(value["physical_topology_hash"]) != String(mode_signature["physical_topology_hash"]):
		return Utils.failure("LAZY_MODE_CACHE_TOPOLOGY_MISMATCH")
	if String(value["dependency_fingerprint"]) != ModeSignature.dependency_fingerprint(mode_signature):
		return Utils.failure("LAZY_MODE_CACHE_DEPENDENCY_MISMATCH")
	if String(value["b0_4_interface_fingerprint"]) != Utils.canonical_hash(mode_descriptor["dynamic_rom_binding"]):
		return Utils.failure("LAZY_MODE_CACHE_B0_4_INTERFACE_MISMATCH")
	return Utils.success()

static func invalidate(value: Dictionary, reason: String) -> Dictionary:
	var checked: Dictionary = validate(value)
	if not bool(checked.get("success", false)):
		return {}
	if not INVALIDATION_REASONS.has(reason) or reason in ["NONE", "B0_4_INTERFACE_UNRESOLVED"]:
		return {}
	var stale := value.duplicate(true)
	stale["validity_state"] = "STALE"
	stale["invalidation_reason"] = reason
	stale["checksum"] = Utils.compute_checksum(stale)
	return stale if bool(validate(stale).get("success", false)) else {}

static func detect_invalidation(value: Dictionary, current_signature: Dictionary, current_descriptor: Dictionary) -> String:
	if String(value.get("source_frontier_hash", "")) != String(current_signature.get("source_frontier_hash", "")):
		return "SOURCE_FRONTIER_CHANGED"
	if String(value.get("physical_topology_hash", "")) != String(current_signature.get("physical_topology_hash", "")):
		return "TOPOLOGY_CHANGED"
	if String(value.get("dependency_fingerprint", "")) != ModeSignature.dependency_fingerprint(current_signature):
		return "DEPENDENCY_CHANGED"
	if String(value.get("b0_4_interface_fingerprint", "")) != Utils.canonical_hash(current_descriptor.get("dynamic_rom_binding", {})):
		return "B0_4_INTERFACE_CHANGED"
	return "NONE"
