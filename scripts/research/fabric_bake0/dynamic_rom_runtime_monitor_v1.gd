extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const RuntimeCertificate = preload("res://scripts/research/fabric_bake0/rom_runtime_certificate_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_dynamic_rom_runtime_monitor.v1"
const ROM_ACTIVE := "ROM_ACTIVE"
const ROM_INVALID := "ROM_INVALID"
const FIELDS: Array[String] = [
	"schema", "state", "source_binding_checksum", "rom_descriptor_hash",
	"invalidation_reason", "invalidated_at_step", "checksum",
]

static func create(source_binding_checksum: String, rom_descriptor_hash: String) -> Dictionary:
	if not Utils.is_lower_hex_64(source_binding_checksum) or not Utils.is_lower_hex_64(rom_descriptor_hash):
		return {}
	var value: Dictionary = {
		"schema": SCHEMA,
		"state": ROM_ACTIVE,
		"source_binding_checksum": source_binding_checksum,
		"rom_descriptor_hash": rom_descriptor_hash,
		"invalidation_reason": "NONE",
		"invalidated_at_step": -1,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_DYNAMIC_ROM_RUNTIME_MONITOR_SCHEMA")
	if not [ROM_ACTIVE, ROM_INVALID].has(String(value.get("state", ""))):
		return Utils.failure("INVALID_DYNAMIC_ROM_RUNTIME_MONITOR_STATE")
	for field in ["source_binding_checksum", "rom_descriptor_hash"]:
		if not Utils.is_lower_hex_64(value.get(field)):
			return Utils.failure("INVALID_DYNAMIC_ROM_RUNTIME_MONITOR_HASH", {"field": field})
	if typeof(value.get("invalidation_reason")) != TYPE_STRING:
		return Utils.failure("INVALID_DYNAMIC_ROM_INVALIDATION_REASON")
	var reason := String(value["invalidation_reason"])
	if reason != "NONE" and not Utils.is_upper_kind(reason):
		return Utils.failure("INVALID_DYNAMIC_ROM_INVALIDATION_REASON")
	if not Utils.is_json_integer(value.get("invalidated_at_step")):
		return Utils.failure("INVALID_DYNAMIC_ROM_INVALIDATION_STEP")
	if String(value["state"]) == ROM_ACTIVE:
		if reason != "NONE" or int(value["invalidated_at_step"]) != -1:
			return Utils.failure("ACTIVE_DYNAMIC_ROM_CANNOT_HAVE_INVALIDATION")
	else:
		if reason == "NONE" or int(value["invalidated_at_step"]) < 0:
			return Utils.failure("INVALID_DYNAMIC_ROM_MISSING_INVALIDATION")
	return Utils.validate_checksum(value)

static func observe(
	monitor: Dictionary,
	runtime_certificate,
	current_source_binding_checksum: String,
	step_index: int
) -> Dictionary:
	var checked := validate(monitor)
	if not bool(checked.get("success", false)):
		return checked
	if not Utils.is_json_integer(step_index) or step_index < 0:
		return Utils.failure("INVALID_DYNAMIC_ROM_RUNTIME_MONITOR_STEP")
	if String(monitor["state"]) == ROM_INVALID:
		return Utils.success({
			"monitor": monitor.duplicate(true),
			"transition": "ROM_INVALID->ROM_INVALID",
			"execution_allowed": false,
		})

	if not Utils.is_lower_hex_64(current_source_binding_checksum):
		return _invalidated(monitor, "SOURCE_BINDING_INVALID", step_index)
	if current_source_binding_checksum != String(monitor["source_binding_checksum"]):
		return _invalidated(monitor, "SOURCE_REVISION_MISMATCH", step_index)
	if typeof(runtime_certificate) != TYPE_DICTIONARY or runtime_certificate.is_empty():
		return _invalidated(monitor, "CERTIFICATE_UNAVAILABLE", step_index)
	checked = RuntimeCertificate.validate(runtime_certificate)
	if not bool(checked.get("success", false)):
		return _invalidated(monitor, "CERTIFICATE_UNAVAILABLE", step_index)
	if String(runtime_certificate["source_binding_checksum"]) != String(monitor["source_binding_checksum"]):
		return _invalidated(monitor, "CERTIFICATE_SOURCE_MISMATCH", step_index)
	if String(runtime_certificate["rom_descriptor_hash"]) != String(monitor["rom_descriptor_hash"]):
		return _invalidated(monitor, "CERTIFICATE_ROM_MISMATCH", step_index)
	if not bool(runtime_certificate["valid"]):
		return _invalidated(monitor, String(runtime_certificate["reason"]), step_index)

	return Utils.success({
		"monitor": monitor.duplicate(true),
		"transition": "ROM_ACTIVE->ROM_ACTIVE",
		"execution_allowed": true,
	})

static func can_execute(monitor: Dictionary) -> Dictionary:
	var checked := validate(monitor)
	if not bool(checked.get("success", false)):
		return checked
	if String(monitor["state"]) != ROM_ACTIVE:
		return Utils.failure("DYNAMIC_ROM_EXECUTION_FORBIDDEN", {
			"reason": monitor["invalidation_reason"],
			"invalidated_at_step": monitor["invalidated_at_step"],
		})
	return Utils.success({
		"state": ROM_ACTIVE,
		"execution_allowed": true,
	})

static func _invalidated(monitor: Dictionary, reason: String, step_index: int) -> Dictionary:
	var next := monitor.duplicate(true)
	next["state"] = ROM_INVALID
	next["invalidation_reason"] = reason
	next["invalidated_at_step"] = step_index
	next["checksum"] = Utils.compute_checksum(next)
	var checked := validate(next)
	if not bool(checked.get("success", false)):
		return checked
	return Utils.success({
		"monitor": next,
		"transition": "ROM_ACTIVE->ROM_INVALID",
		"execution_allowed": false,
	})
