extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_rom_runtime_certificate.v1"
const COMPONENTS: Array[String] = ["STATE", "PORT", "ENERGY", "CONSTRAINT"]
const THRESHOLD_FIELDS: Array[String] = ["state", "port", "energy", "constraint"]
const FIELDS: Array[String] = [
	"schema", "valid", "residual_norm", "relative_residual",
	"state_error", "port_error", "energy_error", "constraint_error",
	"worst_component", "threshold", "component_thresholds", "reason",
	"source_binding_checksum", "rom_descriptor_hash", "elapsed_s", "checksum",
]

static func create(
	source_binding_checksum: String,
	rom_descriptor_hash: String,
	residual_norm: float,
	state_error: float,
	port_error: float,
	energy_error: float,
	constraint_error: float,
	component_thresholds: Dictionary,
	elapsed_s: float
) -> Dictionary:
	if not Utils.is_lower_hex_64(source_binding_checksum):
		return {}
	if not Utils.is_lower_hex_64(rom_descriptor_hash):
		return {}
	for raw in [residual_norm, state_error, port_error, energy_error, constraint_error, elapsed_s]:
		if not Utils.is_non_negative_number(raw):
			return {}
	var checked := _validate_thresholds(component_thresholds)
	if not bool(checked.get("success", false)):
		return {}

	var errors := {
		"STATE": state_error,
		"PORT": port_error,
		"ENERGY": energy_error,
		"CONSTRAINT": constraint_error,
	}
	var aggregate := _aggregate(errors, component_thresholds)
	var relative_residual := float(aggregate["relative_residual"])
	var worst_component := String(aggregate["worst_component"])
	var valid := relative_residual <= 1.0
	var reason := "CERTIFIED" if valid else "%s_RESIDUAL_EXCEEDED" % worst_component
	var value: Dictionary = {
		"schema": SCHEMA,
		"valid": valid,
		"residual_norm": residual_norm,
		"relative_residual": relative_residual,
		"state_error": state_error,
		"port_error": port_error,
		"energy_error": energy_error,
		"constraint_error": constraint_error,
		"worst_component": worst_component,
		"threshold": 1.0,
		"component_thresholds": component_thresholds.duplicate(true),
		"reason": reason,
		"source_binding_checksum": source_binding_checksum,
		"rom_descriptor_hash": rom_descriptor_hash,
		"elapsed_s": elapsed_s,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_ROM_RUNTIME_CERTIFICATE_SCHEMA")
	if typeof(value.get("valid")) != TYPE_BOOL:
		return Utils.failure("INVALID_ROM_RUNTIME_CERTIFICATE_VALID_FLAG")
	for field in [
		"residual_norm", "relative_residual", "state_error", "port_error",
		"energy_error", "constraint_error", "threshold", "elapsed_s",
	]:
		if not Utils.is_non_negative_number(value.get(field)):
			return Utils.failure("INVALID_ROM_RUNTIME_CERTIFICATE_NUMBER", {"field": field})
	if absf(float(value["threshold"]) - 1.0) > 1.0e-15:
		return Utils.failure("ROM_RUNTIME_CERTIFICATE_THRESHOLD_NOT_NORMALIZED")
	for field in ["source_binding_checksum", "rom_descriptor_hash"]:
		if not Utils.is_lower_hex_64(value.get(field)):
			return Utils.failure("INVALID_ROM_RUNTIME_CERTIFICATE_HASH", {"field": field})
	if typeof(value.get("component_thresholds")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_ROM_RUNTIME_COMPONENT_THRESHOLDS")
	checked = _validate_thresholds(value["component_thresholds"])
	if not bool(checked.get("success", false)):
		return checked
	if not COMPONENTS.has(String(value.get("worst_component", ""))):
		return Utils.failure("INVALID_ROM_RUNTIME_WORST_COMPONENT")

	var errors := {
		"STATE": float(value["state_error"]),
		"PORT": float(value["port_error"]),
		"ENERGY": float(value["energy_error"]),
		"CONSTRAINT": float(value["constraint_error"]),
	}
	var aggregate := _aggregate(errors, value["component_thresholds"])
	var expected_relative := float(aggregate["relative_residual"])
	var expected_worst := String(aggregate["worst_component"])
	if not _near(float(value["relative_residual"]), expected_relative):
		return Utils.failure("ROM_RUNTIME_RELATIVE_RESIDUAL_MISMATCH")
	if String(value["worst_component"]) != expected_worst:
		return Utils.failure("ROM_RUNTIME_WORST_COMPONENT_MISMATCH")
	var expected_valid := expected_relative <= float(value["threshold"])
	if bool(value["valid"]) != expected_valid:
		return Utils.failure("ROM_RUNTIME_CERTIFICATE_VALIDITY_MISMATCH")
	var expected_reason := "CERTIFIED" if expected_valid else "%s_RESIDUAL_EXCEEDED" % expected_worst
	if String(value.get("reason", "")) != expected_reason:
		return Utils.failure("ROM_RUNTIME_CERTIFICATE_REASON_MISMATCH")
	return Utils.validate_checksum(value)

static func _validate_thresholds(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, THRESHOLD_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	for field in THRESHOLD_FIELDS:
		if not Utils.is_positive_number(value.get(field)):
			return Utils.failure("INVALID_ROM_RUNTIME_COMPONENT_THRESHOLD", {"field": field})
	return Utils.success()

static func _aggregate(errors: Dictionary, thresholds: Dictionary) -> Dictionary:
	var worst_component := COMPONENTS[0]
	var relative_residual := -1.0
	for component in COMPONENTS:
		var threshold_key := component.to_lower()
		var ratio := float(errors[component]) / float(thresholds[threshold_key])
		if ratio > relative_residual:
			relative_residual = ratio
			worst_component = component
	return {
		"relative_residual": maxf(0.0, relative_residual),
		"worst_component": worst_component,
	}

static func _near(a: float, b: float) -> bool:
	return absf(a - b) <= 1.0e-14 * maxf(1.0, maxf(absf(a), absf(b)))
