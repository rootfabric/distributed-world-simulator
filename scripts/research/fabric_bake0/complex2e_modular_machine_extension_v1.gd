extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Fixture = preload("res://scripts/research/fabric_bake0/complex2_modular_machine_fixture_v1.gd")
const ParentD = preload("res://scripts/research/fabric_bake0/complex2d_modular_machine_extension_v1.gd")
const Structural = preload("res://scripts/research/fabric_bake0/complex2_independent_structural_failure_v1.gd")
const Coupled = preload("res://scripts/research/fabric_bake0/complex2_coupled_motion_v1.gd")
const Lifecycle = preload("res://scripts/research/fabric_bake0/complex2_settle_rebake_reimpact_v1.gd")
const Adapter = preload("res://scripts/research/fabric_bake0/bridge2_region_adapter_v1.gd")
const Registry = preload("res://scripts/research/fabric_bake0/bridge2_mixed_registry_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/bridge2_mixed_runtime_v1.gd")

const SCHEMA := "planet_simulator.fabric_complex2e_modular_machine_extension.v1"
const REBAKE_GENERATION := 6
const DT := 0.01

static func build() -> Dictionary:
	var parent := ParentD.build()
	if not bool(parent.get("success", false)):
		return _failure("COMPLEX2E_PARENT_D_FAILED", parent)
	return {
		"success": true,
		"schema": SCHEMA,
		"parent_d": parent,
		"parent_machine": parent["parent_machine"],
		"registry": parent["registry"],
		"extension_hash": Utils.canonical_hash({
			"schema": SCHEMA,
			"parent_d_extension_hash": String(parent["extension_hash"]),
			"lifecycle_backend": Lifecycle.BACKEND_CONTRACT_ID,
		}),
	}

static func run_experiment() -> Dictionary:
	var built := build()
	if not bool(built.get("success", false)):
		return built
	var parent_result := ParentD.run_experiment()
	if not bool(parent_result.get("success", false)):
		return _failure("COMPLEX2E_PARENT_D_EXECUTION_FAILED", parent_result)
	var continuation: Dictionary = parent_result["continuation"]
	var machine: Dictionary = continuation["machine"]
	var session: Dictionary = continuation["session"]
	var registry: Dictionary = continuation["registry"]
	var reference: Dictionary = continuation["reference"]
	var structural: Dictionary = parent_result["structural"]

	var lifecycle := Lifecycle.initial_lifecycle()
	var premature_rebake := Lifecycle.mark_rebaked(lifecycle, "premature")
	var premature_reimpact := Lifecycle.commit_reimpact(lifecycle)

	var settled := Lifecycle.settle_after_first_impact(machine)
	if not bool(settled.get("success", false)):
		return _failure("COMPLEX2E_SETTLE_FAILED", settled)
	var marked_settled := Lifecycle.mark_settled(lifecycle, String(settled["settled_state_hash"]))
	if not bool(marked_settled.get("success", false)):
		return _failure("COMPLEX2E_MARK_SETTLED_FAILED", marked_settled)
	lifecycle = marked_settled["lifecycle"]

	var old_dynamic := Registry.region_by_id(registry, Fixture.REGION_DYNAMIC)
	if old_dynamic.is_empty():
		return _failure("COMPLEX2E_DYNAMIC_REGION_MISSING")
	var old_dynamic_backend_hash := String(old_dynamic["adapter"]["backend_contract_hash"])
	var old_source_slice_hash := Utils.canonical_hash(old_dynamic["adapter"]["source_slice"])
	var rebaked_backend_hash := Utils.canonical_hash({
		"parent_dynamic_backend_hash": old_dynamic_backend_hash,
		"settled_state_hash": String(settled["settled_state_hash"]),
		"failed_structural_topology_hash": String(structural["after_topology_hash"]),
		"rebake_generation": REBAKE_GENERATION,
		"kind": "SETTLED_DYNAMIC_ROM_REBAKE_R1",
	})
	var rebake_adapter := Adapter.create(
		Fixture.REGION_DYNAMIC,
		"DYNAMIC_ROM",
		String(old_dynamic["state_id"]),
		old_dynamic["adapter"]["source_slice"],
		rebaked_backend_hash,
		float(old_dynamic["adapter"]["storage"]),
		float(old_dynamic["adapter"]["damping"]),
		REBAKE_GENERATION
	)
	if rebake_adapter.is_empty():
		return _failure("COMPLEX2E_REBAKE_ADAPTER_BUILD_FAILED")
	var rebaked := Runtime.rebuild_region(session, registry, rebake_adapter)
	if not bool(rebaked.get("success", false)):
		return _failure("COMPLEX2E_RUNTIME_REBAKE_FAILED", rebaked)
	session = rebaked["details"]["session"]
	registry = rebaked["details"]["registry"]
	var dynamic_after_rebake := Registry.region_by_id(registry, Fixture.REGION_DYNAMIC)
	var rebake_artifact_hash := String(dynamic_after_rebake["adapter"]["artifact"]["checksum"])
	var marked_rebaked := Lifecycle.mark_rebaked(lifecycle, rebake_artifact_hash)
	if not bool(marked_rebaked.get("success", false)):
		return _failure("COMPLEX2E_MARK_REBAKED_FAILED", marked_rebaked)
	lifecycle = marked_rebaked["lifecycle"]

	var quiet := _run_runtime_pair(session, registry, reference, 3, {})
	if not bool(quiet.get("success", false)):
		return quiet
	session = quiet["session"]
	reference = quiet["reference"]
	var contact_before := float(session["state_values"][Fixture.STATE_CONTACT])

	var committed := Lifecycle.commit_reimpact(lifecycle)
	if not bool(committed.get("success", false)):
		return _failure("COMPLEX2E_COMMIT_REIMPACT_FAILED", committed)
	lifecycle = committed["lifecycle"]
	var duplicate := Lifecycle.commit_reimpact(lifecycle)
	var reimpact := Lifecycle.reimpact_from_settled(settled["assembly"], settled["settled_state"], settled["settled_reference"])
	if not bool(reimpact.get("success", false)):
		return _failure("COMPLEX2E_PHYSICAL_REIMPACT_FAILED", reimpact)

	var runtime_reimpact := _run_runtime_pair(
		session, registry, reference, 4,
		{Fixture.REGION_CONTACT: 0.16, Fixture.REGION_DYNAMIC: 0.04}
	)
	if not bool(runtime_reimpact.get("success", false)):
		return runtime_reimpact
	session = runtime_reimpact["session"]
	reference = runtime_reimpact["reference"]
	var contact_after := float(session["state_values"][Fixture.STATE_CONTACT])

	var final_dynamic := Registry.region_by_id(registry, Fixture.REGION_DYNAMIC)
	var parent_hybrid := Registry.region_by_id(parent_result["continuation"]["registry"], Fixture.REGION_HYBRID)
	var final_hybrid := Registry.region_by_id(registry, Fixture.REGION_HYBRID)
	var source_slice_hash_after := Utils.canonical_hash(final_dynamic["adapter"]["source_slice"])
	var final_structural_assembly := Structural.compile_from_machine(machine)
	if not bool(final_structural_assembly.get("success", false)):
		return _failure("COMPLEX2E_FINAL_STRUCTURAL_COMPILE_FAILED", final_structural_assembly)
	var kinds: Array = []
	for region in registry["regions"]:
		kinds.append(String(region["representation_kind"]))
	kinds.sort()
	var result := {
		"success": true,
		"schema": SCHEMA,
		"extension_hash": String(built["extension_hash"]),
		"parent_d_experiment_hash": String(parent_result["experiment_hash"]),
		"premature_rebake_error": String(premature_rebake.get("error_code", "")),
		"premature_reimpact_error": String(premature_reimpact.get("error_code", "")),
		"settled": settled,
		"rebake_generation": int(final_dynamic["adapter"]["artifact"]["build_generation"]),
		"rebake_state_handoff_error": float(rebaked["details"]["state_handoff_error"]),
		"old_dynamic_backend_hash": old_dynamic_backend_hash,
		"rebaked_dynamic_backend_hash": String(final_dynamic["adapter"]["backend_contract_hash"]),
		"old_source_slice_hash": old_source_slice_hash,
		"rebaked_source_slice_hash": source_slice_hash_after,
		"rebake_artifact_hash": rebake_artifact_hash,
		"registry_hash_before_rebake": String(continuation["registry"]["registry_hash"]),
		"registry_hash_after_rebake": String(registry["registry_hash"]),
		"reimpact": reimpact,
		"reimpact_event_id": Lifecycle.REIMPACT_EVENT_ID,
		"applied_reimpact_ids": Array(lifecycle["applied_reimpact_ids"]).duplicate(),
		"duplicate_reimpact_error": String(duplicate.get("error_code", "")),
		"runtime_quiet_mixed_full_delta": float(quiet["max_delta"]),
		"runtime_reimpact_mixed_full_delta": float(runtime_reimpact["max_delta"]),
		"runtime_contact_state_delta": absf(contact_after - contact_before),
		"parent_b_hybrid_backend_hash": String(parent_hybrid["adapter"]["backend_contract_hash"]),
		"final_hybrid_backend_hash": String(final_hybrid["adapter"]["backend_contract_hash"]),
		"structural_topology_hash_before_rebake": String(structural["after_topology_hash"]),
		"structural_topology_hash_after_reimpact": String(final_structural_assembly["topology_hash"]),
		"functional_subject_hash": Utils.canonical_hash(machine["functional_subject"]),
		"final_representation_kinds": kinds,
		"final_state_hash": Utils.canonical_hash(session["state_values"]),
		"experiment_hash": "",
	}
	result["experiment_hash"] = Utils.canonical_hash({
		"extension_hash": result["extension_hash"],
		"parent_d_experiment_hash": result["parent_d_experiment_hash"],
		"settled_state_hash": settled["settled_state_hash"],
		"rebake_artifact_hash": rebake_artifact_hash,
		"reimpact_hash": reimpact["experiment_hash"],
		"final_state_hash": result["final_state_hash"],
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
			return _failure("COMPLEX2E_RUNTIME_MIXED_STEP_FAILED", {"step": step_index, "result": mixed})
		if not bool(full.get("success", false)):
			return _failure("COMPLEX2E_RUNTIME_FULL_STEP_FAILED", {"step": step_index, "result": full})
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
