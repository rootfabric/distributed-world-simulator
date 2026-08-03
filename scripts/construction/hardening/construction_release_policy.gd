extends RefCounted

const H = preload("res://scripts/construction/hardening/construction_hardening_utils.gd")

const SCHEMA := "planet_simulator.construction_release_descriptor.v1"
const REQUIRED_COMPATIBILITY_CAPABILITIES: Array[String] = ["audit", "exact-replay"]
const FIELDS: Array[String] = [
	"schema", "release_id", "state_version_min", "state_version_max",
	"operation_version_min", "operation_version_max", "capabilities", "read_only", "checksum",
]

static func create(
	release_id: String,
	state_min: int,
	state_max: int,
	operation_min: int,
	operation_max: int,
	capabilities: Array,
	read_only: bool = false
) -> Dictionary:
	var descriptor := {
		"schema": SCHEMA,
		"release_id": release_id,
		"state_version_min": state_min,
		"state_version_max": state_max,
		"operation_version_min": operation_min,
		"operation_version_max": operation_max,
		"capabilities": H.sorted_string_array(capabilities),
		"read_only": read_only,
		"checksum": "",
	}
	descriptor["checksum"] = H.checksum(descriptor)
	return descriptor

static func validate(descriptor: Dictionary) -> Dictionary:
	var exact := H.exact_fields(descriptor, FIELDS)
	if not bool(exact.get("success", false)):
		return H.failure("INVALID_CONSTRUCTION_RELEASE_FIELDS")
	if descriptor.get("schema") != SCHEMA or not H.is_path_id(descriptor.get("release_id"), "release/"):
		return H.failure("INVALID_CONSTRUCTION_RELEASE_DESCRIPTOR")
	if not H.is_positive_integer(descriptor.get("state_version_min")) or not H.is_positive_integer(descriptor.get("state_version_max")):
		return H.failure("INVALID_CONSTRUCTION_RELEASE_STATE_RANGE")
	if int(descriptor["state_version_min"]) > int(descriptor["state_version_max"]):
		return H.failure("INVALID_CONSTRUCTION_RELEASE_STATE_RANGE")
	if not H.is_positive_integer(descriptor.get("operation_version_min")) or not H.is_positive_integer(descriptor.get("operation_version_max")):
		return H.failure("INVALID_CONSTRUCTION_RELEASE_OPERATION_RANGE")
	if int(descriptor["operation_version_min"]) > int(descriptor["operation_version_max"]):
		return H.failure("INVALID_CONSTRUCTION_RELEASE_OPERATION_RANGE")
	if not H.sorted_unique_strings(descriptor.get("capabilities")) or typeof(descriptor.get("read_only")) != TYPE_BOOL:
		return H.failure("INVALID_CONSTRUCTION_RELEASE_CAPABILITIES")
	return H.validate_checksum(descriptor, "CONSTRUCTION_RELEASE_CHECKSUM_MISMATCH")

static func negotiate(current: Dictionary, candidate: Dictionary) -> Dictionary:
	var checked := validate(current)
	if not bool(checked.get("success", false)):
		return checked
	checked = validate(candidate)
	if not bool(checked.get("success", false)):
		return checked
	var state_min := maxi(int(current["state_version_min"]), int(candidate["state_version_min"]))
	var state_max := mini(int(current["state_version_max"]), int(candidate["state_version_max"]))
	var operation_min := maxi(int(current["operation_version_min"]), int(candidate["operation_version_min"]))
	var operation_max := mini(int(current["operation_version_max"]), int(candidate["operation_version_max"]))
	if state_min > state_max or operation_min > operation_max:
		return H.failure("INCOMPATIBLE_CONSTRUCTION_ROLLING_UPGRADE")
	var candidate_capabilities: Array = candidate["capabilities"]
	var shared: Array = []
	for capability in current["capabilities"]:
		if candidate_capabilities.has(capability):
			shared.append(capability)
	for capability in REQUIRED_COMPATIBILITY_CAPABILITIES:
		if not shared.has(capability):
			return H.failure("INCOMPATIBLE_CONSTRUCTION_ROLLING_UPGRADE_CAPABILITIES")
	return H.success({
		"state_version": state_max,
		"operation_version": operation_max,
		"shared_capabilities": shared,
		"candidate_read_only": bool(candidate["read_only"]),
		"migration_required": int(current["state_version_max"]) != int(candidate["state_version_max"]),
	})
