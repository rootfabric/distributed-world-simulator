extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Fixture = preload("res://scripts/research/fabric_bake0/complex2_modular_machine_fixture_v1.gd")
const Compliance = preload("res://scripts/research/fabric_bake0/complex2_compliant_response_v1.gd")
const Adapter = preload("res://scripts/research/fabric_bake0/bridge2_region_adapter_v1.gd")
const Registry = preload("res://scripts/research/fabric_bake0/bridge2_mixed_registry_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/bridge2_mixed_runtime_v1.gd")

const SCHEMA := "planet_simulator.fabric_complex2b_modular_machine_extension.v1"
const DT := 0.01

static func build() -> Dictionary:
	var machine := Fixture.build()
	if not bool(machine.get("success", false)):
		return _failure("COMPLEX2B_PARENT_MACHINE_FAILED", machine)
	var section := Compliance.compile_from_machine(machine)
	if not bool(section.get("success", false)):
		return _failure("COMPLEX2B_COMPLIANCE_COMPILE_FAILED", section)

	var registry: Dictionary = machine["registry"]
	var old_hybrid := Registry.region_by_id(registry, Fixture.REGION_HYBRID)
	if old_hybrid.is_empty():
		return _failure("COMPLEX2B_PARENT_HYBRID_REGION_MISSING")
	var parent_backend_hash := String(old_hybrid["adapter"]["backend_contract_hash"])
	var extended_backend_hash := Utils.canonical_hash({
		"parent_backend_hash": parent_backend_hash,
		"compliant_backend_family_hash": String(section["backend_family_hash"]),
		"composition": "COMPLEX2B_NESTED_HYBRID_BACKEND_R1",
	})
	var replacement := Adapter.create(
		Fixture.REGION_HYBRID,
		"HYBRID_BAKE",
		String(old_hybrid["state_id"]),
		old_hybrid["adapter"]["source_slice"],
		extended_backend_hash,
		float(old_hybrid["adapter"]["storage"]),
		float(old_hybrid["adapter"]["damping"]),
		2
	)
	if replacement.is_empty():
		return _failure("COMPLEX2B_HYBRID_ADAPTER_REBUILD_FAILED")

	var regions: Array = []
	for region in registry["regions"]:
		if String(region["region_id"]) == Fixture.REGION_HYBRID:
			regions.append({
				"region_id": Fixture.REGION_HYBRID,
				"representation_kind": "HYBRID_BAKE",
				"state_id": String(old_hybrid["state_id"]),
				"adapter": replacement,
			})
		else:
			regions.append(Dictionary(region).duplicate(true))
	var extended_registry := Registry.create(
		registry["master_frontier"],
		registry["master_authority"],
		regions,
		registry["interfaces"]
	)
	if extended_registry.is_empty():
		return _failure("COMPLEX2B_EXTENDED_REGISTRY_FAILED")

	var value := {
		"success": true,
		"schema": SCHEMA,
		"parent_machine": machine,
		"compliant_section": section,
		"registry": extended_registry,
		"parent_registry_hash": String(registry["registry_hash"]),
		"extended_registry_hash": String(extended_registry["registry_hash"]),
		"parent_backend_hash": parent_backend_hash,
		"extended_backend_hash": extended_backend_hash,
		"extension_hash": "",
	}
	value["extension_hash"] = Utils.canonical_hash({
		"schema": SCHEMA,
		"parent_machine_hash": String(machine["machine_hash"]),
		"section_hash": String(section["section_hash"]),
		"parent_registry_hash": value["parent_registry_hash"],
		"extended_registry_hash": value["extended_registry_hash"],
		"extended_backend_hash": value["extended_backend_hash"],
	})
	return value

static func run_experiment() -> Dictionary:
	var built := build()
	if not bool(built.get("success", false)):
		return built
	var machine: Dictionary = built["parent_machine"]
	var registry: Dictionary = built["registry"]
	var compliance := Compliance.run_envelope(machine)
	if not bool(compliance.get("success", false)):
		return _failure("COMPLEX2B_COMPLIANT_ENVELOPE_FAILED", compliance)

	var started := Runtime.start(registry, machine["initial_state"])
	if not bool(started.get("success", false)):
		return _failure("COMPLEX2B_EXTENDED_SESSION_START_FAILED", started)
	var session: Dictionary = started["details"]["session"]
	var mixed := Runtime.step(session, registry, {Fixture.REGION_HYBRID: 0.05}, DT)
	var full := Runtime.full_reference_step(registry, machine["initial_state"], {Fixture.REGION_HYBRID: 0.05}, DT)
	if not bool(mixed.get("success", false)):
		return _failure("COMPLEX2B_EXTENDED_MIXED_STEP_FAILED", mixed)
	if not bool(full.get("success", false)):
		return _failure("COMPLEX2B_EXTENDED_FULL_STEP_FAILED", full)
	var mixed_values: Dictionary = mixed["details"]["session"]["state_values"]
	var full_values: Dictionary = full["details"]["state_values"]
	var extended_step_delta := _state_error(mixed_values, full_values)

	var parent_result := Fixture.run_experiment()
	if not bool(parent_result.get("success", false)):
		return _failure("COMPLEX2B_PARENT_REGRESSION_FAILED", parent_result)
	var result := {
		"success": true,
		"schema": SCHEMA,
		"extension_hash": String(built["extension_hash"]),
		"section_hash": String(built["compliant_section"]["section_hash"]),
		"parent_registry_hash": String(built["parent_registry_hash"]),
		"extended_registry_hash": String(built["extended_registry_hash"]),
		"parent_backend_hash": String(built["parent_backend_hash"]),
		"extended_backend_hash": String(built["extended_backend_hash"]),
		"extended_step_full_delta": extended_step_delta,
		"compliance": compliance,
		"parent_experiment_hash": String(parent_result["experiment_hash"]),
		"parent_mixed_full_max_state_delta": float(parent_result["mixed_full_max_state_delta"]),
		"parent_representation_swap_handoff_error": float(parent_result["representation_swap_handoff_error"]),
	}
	result["experiment_hash"] = Utils.canonical_hash({
		"extension_hash": result["extension_hash"],
		"extended_registry_hash": result["extended_registry_hash"],
		"compliance_experiment_hash": result["compliance"]["experiment_hash"],
		"parent_experiment_hash": result["parent_experiment_hash"],
	})
	return result

static func _state_error(a: Dictionary, b: Dictionary) -> float:
	var error := 0.0
	for key in a.keys():
		error = maxf(error, absf(float(a[key]) - float(b[key])))
	return error

static func _failure(error_code: String, details = null) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"details": details,
	}
