extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Fixture = preload("res://scripts/research/fabric_bake0/complex2_modular_machine_fixture_v1.gd")
const ParentB = preload("res://scripts/research/fabric_bake0/complex2b_modular_machine_extension_v1.gd")
const Compliance = preload("res://scripts/research/fabric_bake0/complex2_compliant_response_v1.gd")
const Coupled = preload("res://scripts/research/fabric_bake0/complex2_coupled_motion_v1.gd")
const Adapter = preload("res://scripts/research/fabric_bake0/bridge2_region_adapter_v1.gd")
const Registry = preload("res://scripts/research/fabric_bake0/bridge2_mixed_registry_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/bridge2_mixed_runtime_v1.gd")

const SCHEMA := "planet_simulator.fabric_complex2c_modular_machine_extension.v1"
const EVENT_TO_FULL := "event/complex2c-dynamic-to-full-mid-motion"
const EVENT_TO_DYNAMIC := "event/complex2c-full-to-dynamic-mid-motion"
const DT := 0.01

static func build() -> Dictionary:
	var parent := ParentB.build()
	if not bool(parent.get("success", false)):
		return _failure("COMPLEX2C_PARENT_B_FAILED", parent)
	var machine: Dictionary = parent["parent_machine"]
	var assembly := Coupled.compile_from_machine(machine)
	if not bool(assembly.get("success", false)):
		return _failure("COMPLEX2C_COUPLED_COMPILE_FAILED", assembly)
	var registry: Dictionary = parent["registry"]
	var old_dynamic := Registry.region_by_id(registry, Fixture.REGION_DYNAMIC)
	if old_dynamic.is_empty():
		return _failure("COMPLEX2C_DYNAMIC_REGION_MISSING")
	var parent_dynamic_backend_hash := String(old_dynamic["adapter"]["backend_contract_hash"])
	var extended_dynamic_backend_hash := Utils.canonical_hash({
		"parent_dynamic_backend_hash": parent_dynamic_backend_hash,
		"coupled_backend_family_hash": String(assembly["backend_family_hash"]),
		"coupled_assembly_hash": String(assembly["assembly_hash"]),
		"composition": "COMPLEX2C_NESTED_DYNAMIC_BACKEND_R1",
	})
	var replacement := Adapter.create(
		Fixture.REGION_DYNAMIC,
		"DYNAMIC_ROM",
		String(old_dynamic["state_id"]),
		old_dynamic["adapter"]["source_slice"],
		extended_dynamic_backend_hash,
		float(old_dynamic["adapter"]["storage"]),
		float(old_dynamic["adapter"]["damping"]),
		2
	)
	if replacement.is_empty():
		return _failure("COMPLEX2C_DYNAMIC_ADAPTER_REBUILD_FAILED")
	var regions: Array = []
	for region in registry["regions"]:
		if String(region["region_id"]) == Fixture.REGION_DYNAMIC:
			regions.append({
				"region_id": Fixture.REGION_DYNAMIC,
				"representation_kind": "DYNAMIC_ROM",
				"state_id": String(old_dynamic["state_id"]),
				"adapter": replacement,
			})
		else:
			regions.append(Dictionary(region).duplicate(true))
	var extended_registry := Registry.create(
		registry["master_frontier"], registry["master_authority"], regions, registry["interfaces"]
	)
	if extended_registry.is_empty():
		return _failure("COMPLEX2C_EXTENDED_REGISTRY_FAILED")
	var value := {
		"success": true,
		"schema": SCHEMA,
		"parent_b": parent,
		"parent_machine": machine,
		"coupled_assembly": assembly,
		"registry": extended_registry,
		"parent_registry_hash": String(registry["registry_hash"]),
		"extended_registry_hash": String(extended_registry["registry_hash"]),
		"parent_dynamic_backend_hash": parent_dynamic_backend_hash,
		"extended_dynamic_backend_hash": extended_dynamic_backend_hash,
		"extension_hash": "",
	}
	value["extension_hash"] = Utils.canonical_hash({
		"schema": SCHEMA,
		"parent_b_extension_hash": String(parent["extension_hash"]),
		"coupled_assembly_hash": String(assembly["assembly_hash"]),
		"extended_registry_hash": String(extended_registry["registry_hash"]),
		"extended_dynamic_backend_hash": extended_dynamic_backend_hash,
	})
	return value

static func run_experiment() -> Dictionary:
	var built := build()
	if not bool(built.get("success", false)):
		return built
	var machine: Dictionary = built["parent_machine"]
	var registry: Dictionary = built["registry"]
	var coupled := Coupled.run_envelope(machine)
	if not bool(coupled.get("success", false)):
		return _failure("COMPLEX2C_COUPLED_ENVELOPE_FAILED", coupled)
	var compliance := Compliance.run_envelope(machine)
	if not bool(compliance.get("success", false)):
		return _failure("COMPLEX2C_PARENT_B_COMPLIANCE_FAILED", compliance)

	var started := Runtime.start(registry, machine["initial_state"])
	if not bool(started.get("success", false)):
		return _failure("COMPLEX2C_SESSION_START_FAILED", started)
	var session: Dictionary = started["details"]["session"]
	var reference: Dictionary = machine["initial_state"].duplicate(true)
	var runtime_max_delta := 0.0
	var pre_swap := _run_runtime_pair(session, registry, reference, 4, {Fixture.REGION_DYNAMIC: 0.08})
	if not bool(pre_swap.get("success", false)):
		return pre_swap
	session = pre_swap["session"]
	reference = pre_swap["reference"]
	runtime_max_delta = maxf(runtime_max_delta, float(pre_swap["max_delta"]))

	var dynamic_region := Registry.region_by_id(registry, Fixture.REGION_DYNAMIC)
	var full_region := Registry.region_by_id(registry, Fixture.REGION_FULL)
	var dynamic_to_full := Adapter.create(
		Fixture.REGION_DYNAMIC,
		"FULL",
		String(dynamic_region["state_id"]),
		dynamic_region["adapter"]["source_slice"],
		Utils.canonical_hash({"complex2c": "FULL_CANONICAL_MID_MOTION", "assembly": built["coupled_assembly"]["assembly_hash"]}),
		float(dynamic_region["adapter"]["storage"]),
		float(dynamic_region["adapter"]["damping"]),
		3
	)
	var full_to_dynamic := Adapter.create(
		Fixture.REGION_FULL,
		"DYNAMIC_ROM",
		String(full_region["state_id"]),
		full_region["adapter"]["source_slice"],
		String(built["parent_dynamic_backend_hash"]),
		float(full_region["adapter"]["storage"]),
		float(full_region["adapter"]["damping"]),
		3
	)
	if dynamic_to_full.is_empty() or full_to_dynamic.is_empty():
		return _failure("COMPLEX2C_SWAP_ADAPTER_BUILD_FAILED")
	var swap_to_full := Runtime.consume_representation_swap_event(
		session,
		registry,
		{"event_id": EVENT_TO_FULL, "time": float(session["time_s"]), "transitions": [{"kind": "COUPLED_DYNAMIC_TO_FULL"}]},
		Fixture.REGION_DYNAMIC,
		dynamic_to_full,
		Fixture.REGION_FULL,
		full_to_dynamic
	)
	if not bool(swap_to_full.get("success", false)):
		return _failure("COMPLEX2C_SWAP_TO_FULL_FAILED", swap_to_full)
	session = swap_to_full["details"]["session"]
	registry = swap_to_full["details"]["registry"]
	var during_full := _run_runtime_pair(session, registry, reference, 3, {Fixture.REGION_DYNAMIC: -0.04})
	if not bool(during_full.get("success", false)):
		return during_full
	session = during_full["session"]
	reference = during_full["reference"]
	runtime_max_delta = maxf(runtime_max_delta, float(during_full["max_delta"]))

	var dynamic_now := Registry.region_by_id(registry, Fixture.REGION_DYNAMIC)
	var full_now := Registry.region_by_id(registry, Fixture.REGION_FULL)
	var dynamic_back := Adapter.create(
		Fixture.REGION_DYNAMIC,
		"DYNAMIC_ROM",
		String(dynamic_now["state_id"]),
		dynamic_now["adapter"]["source_slice"],
		String(built["extended_dynamic_backend_hash"]),
		float(dynamic_now["adapter"]["storage"]),
		float(dynamic_now["adapter"]["damping"]),
		4
	)
	var full_back := Adapter.create(
		Fixture.REGION_FULL,
		"FULL",
		String(full_now["state_id"]),
		full_now["adapter"]["source_slice"],
		String(built["parent_b"]["parent_machine"]["registry"]["regions"].filter(func(r): return String(r["region_id"]) == Fixture.REGION_FULL)[0]["adapter"]["backend_contract_hash"]),
		float(full_now["adapter"]["storage"]),
		float(full_now["adapter"]["damping"]),
		4
	)
	if dynamic_back.is_empty() or full_back.is_empty():
		return _failure("COMPLEX2C_SWAP_BACK_ADAPTER_BUILD_FAILED")
	var swap_back := Runtime.consume_representation_swap_event(
		session,
		registry,
		{"event_id": EVENT_TO_DYNAMIC, "time": float(session["time_s"]), "transitions": [{"kind": "COUPLED_FULL_TO_DYNAMIC"}]},
		Fixture.REGION_DYNAMIC,
		dynamic_back,
		Fixture.REGION_FULL,
		full_back
	)
	if not bool(swap_back.get("success", false)):
		return _failure("COMPLEX2C_SWAP_BACK_FAILED", swap_back)
	session = swap_back["details"]["session"]
	registry = swap_back["details"]["registry"]
	var post_swap := _run_runtime_pair(session, registry, reference, 4, {})
	if not bool(post_swap.get("success", false)):
		return post_swap
	session = post_swap["session"]
	reference = post_swap["reference"]
	runtime_max_delta = maxf(runtime_max_delta, float(post_swap["max_delta"]))

	var handoff_error := 0.0
	for event_result in [swap_to_full, swap_back]:
		for handoff in event_result["details"]["handoffs"]:
			handoff_error = maxf(handoff_error, absf(float(handoff["state_error"])))
	var kinds: Array = []
	for region in registry["regions"]:
		kinds.append(String(region["representation_kind"]))
	kinds.sort()
	var parent_hybrid := Registry.region_by_id(built["parent_b"]["registry"], Fixture.REGION_HYBRID)
	var final_hybrid := Registry.region_by_id(registry, Fixture.REGION_HYBRID)
	var result := {
		"success": true,
		"schema": SCHEMA,
		"extension_hash": String(built["extension_hash"]),
		"coupled": coupled,
		"parent_b_compliance_hash": String(compliance["experiment_hash"]),
		"runtime_mixed_full_max_delta": runtime_max_delta,
		"representation_swap_handoff_error": handoff_error,
		"representation_event_ledger_size": session["event_ledger"].size(),
		"final_representation_kinds": kinds,
		"parent_b_hybrid_backend_hash": String(parent_hybrid["adapter"]["backend_contract_hash"]),
		"final_hybrid_backend_hash": String(final_hybrid["adapter"]["backend_contract_hash"]),
		"final_state_hash": Utils.canonical_hash(session["state_values"]),
		"experiment_hash": "",
	}
	result["experiment_hash"] = Utils.canonical_hash({
		"extension_hash": result["extension_hash"],
		"coupled_experiment_hash": result["coupled"]["experiment_hash"],
		"parent_b_compliance_hash": result["parent_b_compliance_hash"],
		"final_state_hash": result["final_state_hash"],
		"representation_event_ledger_size": result["representation_event_ledger_size"],
	})
	return result

static func _run_runtime_pair(session: Dictionary, registry: Dictionary, reference: Dictionary, steps: int, flows: Dictionary) -> Dictionary:
	var live_session := session
	var live_reference := reference.duplicate(true)
	var max_delta := 0.0
	for step_index in range(steps):
		var mixed := Runtime.step(live_session, registry, flows, DT)
		var full := Runtime.full_reference_step(registry, live_reference, flows, DT)
		if not bool(mixed.get("success", false)):
			return _failure("COMPLEX2C_RUNTIME_MIXED_STEP_FAILED", {"step": step_index, "result": mixed})
		if not bool(full.get("success", false)):
			return _failure("COMPLEX2C_RUNTIME_FULL_STEP_FAILED", {"step": step_index, "result": full})
		live_session = mixed["details"]["session"]
		live_reference = full["details"]["state_values"]
		max_delta = maxf(max_delta, _state_error(live_session["state_values"], live_reference))
	return {"success": true, "session": live_session, "reference": live_reference, "max_delta": max_delta}

static func _state_error(a: Dictionary, b: Dictionary) -> float:
	var error := 0.0
	for key in a.keys():
		error = maxf(error, absf(float(a[key]) - float(b[key])))
	return error

static func _failure(error_code: String, details = null) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details}
