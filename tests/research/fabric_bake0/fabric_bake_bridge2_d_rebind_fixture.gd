extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Ordering = preload("res://scripts/research/fabric_bake0/mixed_representation_invalidation_ordering_v1.gd")
const Ownership = preload("res://scripts/research/fabric_bake0/mixed_representation_ownership_contract_v1.gd")
const TopologyRuntime = preload("res://scripts/research/fabric_bake0/structural_topology_rebake_runtime_v1.gd")
const FullCompiler = preload("res://scripts/research/fabric_bake0/dynamic_full_model_compiler_v1.gd")
const ROMCompiler = preload("res://scripts/research/fabric_bake0/dynamic_rom_compiler_v1.gd")
const Certification = preload("res://scripts/research/fabric_bake0/dynamic_rom_runtime_certification_v1.gd")
const DynamicBridge = preload("res://scripts/research/fabric_bake0/dynamic_rom_physical_bake_bridge_v1.gd")
const HybridRuntime = preload("res://scripts/research/fabric_bake0/hybrid_bake_executable_runtime_v1.gd")
const DynamicFixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_4_a_fixture.gd")
const Complex0 = preload("res://tests/research/fabric_bake0/fabric_bake_complex0_fixture.gd")
const OwnershipFixture = preload("res://tests/research/fabric_bake0/fabric_bake_bridge2_a_fixture.gd")

static func build() -> Dictionary:
	var old_subject := OwnershipFixture.build()
	if not bool(old_subject.get("success", false)):
		return old_subject
	var canonical: Dictionary = old_subject["canonical"]
	var structural := Complex0.compile_structural(canonical)
	if not bool(structural.get("success", false)):
		return structural
	var guard_result := Complex0.evaluate_guard(canonical, structural)
	if not bool(guard_result.get("success", false)):
		return guard_result
	var broken := Complex0.make_break(canonical, structural)
	if not bool(broken.get("success", false)):
		return broken
	var compiled_transaction := Complex0.compile_transaction(broken)
	if not bool(compiled_transaction.get("success", false)):
		return compiled_transaction
	var transaction: Dictionary = compiled_transaction["transaction"]
	var topology_runtime := TopologyRuntime.execute(
		transaction, structural["local"]["plan"], structural["aggregate"]["descriptor"],
		structural["aggregate"]["reconstruction_mapping"], structural["guard"]["guard_field"],
		Complex0.reduced_state(), Complex0.guard_context(canonical, structural),
		broken["current_frontier"], broken["current_authority"], broken["dependencies"], []
	)
	if not bool(topology_runtime.get("success", false)):
		return topology_runtime
	var fresh_ownership_result := _fresh_ownership(old_subject["contract"], broken)
	if not bool(fresh_ownership_result.get("success", false)):
		return fresh_ownership_result
	var fresh_ownership: Dictionary = fresh_ownership_result["details"]["contract"]
	var rebound := _fresh_dynamic_hybrid(broken, fresh_ownership)
	if not bool(rebound.get("success", false)):
		return rebound

	var fresh_structural_hashes: Array = []
	for component in transaction["rebaked_components"]:
		fresh_structural_hashes.append(String(component["physical_bake_artifact"]["checksum"]))
	fresh_structural_hashes.sort()
	var recoveries := [
		{
			"representation_id": OwnershipFixture.FULL,
			"representation_kind": "FULL",
			"recovery_action": "RECOMPILE_FULL_ON_CURRENT_FRONTIER",
			"fresh_identity_hashes": [String(rebound["full_model"]["model_hash"])],
			"fresh_execution_state": "FRESH_EXECUTABLE",
		},
		{
			"representation_id": OwnershipFixture.STRUCTURAL,
			"representation_kind": "STRUCTURAL_BAKE",
			"recovery_action": "LOCAL_FULL_SPLIT_REBAKE",
			"fresh_identity_hashes": fresh_structural_hashes,
			"fresh_execution_state": "SPLIT_FRESH_EXECUTABLE",
		},
		{
			"representation_id": OwnershipFixture.CONTACT,
			"representation_kind": "CONTACT_BAKE",
			"recovery_action": "DISCARD_AND_REDERIVE_AFTER_COMPONENT_ATTACHMENT",
			"fresh_identity_hashes": [],
			"fresh_execution_state": "DEFERRED_REDERIVE",
		},
		{
			"representation_id": OwnershipFixture.DYNAMIC,
			"representation_kind": "DYNAMIC_ROM",
			"recovery_action": "RECOMPILE_ROM_ON_CURRENT_FRONTIER",
			"fresh_identity_hashes": [String(rebound["dynamic_bundle"]["physical_artifact"]["checksum"])],
			"fresh_execution_state": "ACTIVE",
		},
		{
			"representation_id": OwnershipFixture.HYBRID,
			"representation_kind": "HYBRID_BAKE",
			"recovery_action": "LAZY_COMPILE_MODE_ON_CURRENT_FRONTIER",
			"fresh_identity_hashes": [String(rebound["hybrid_package"]["package_hash"])],
			"fresh_execution_state": "ACTIVE",
		},
	]
	var phase_proofs := [
		U.canonical_hash({
			"phase": Ordering.RECOVERY_PHASES[0],
			"fresh_ownership": fresh_ownership["contract_hash"],
			"fresh_structural": fresh_structural_hashes,
			"fresh_full": rebound["full_model"]["model_hash"],
			"fresh_dynamic": rebound["dynamic_bundle"]["physical_artifact"]["checksum"],
			"fresh_hybrid": rebound["hybrid_package"]["package_hash"],
		}),
		U.canonical_hash({
			"phase": Ordering.RECOVERY_PHASES[1],
			"structural_executable_count": topology_runtime["diagnostics"]["executable_physical_bake_artifact_count"],
			"dynamic_status": rebound["dynamic_step"]["details"].get("physical_artifact_id", ""),
			"hybrid_status": rebound["hybrid_step"]["details"].get("status", ""),
		}),
	]
	var trace := Ordering.create_recovery(
		String(broken["event"]["event_id"]), String(broken["current_frontier"]["frontier_hash"]),
		String(old_subject["contract"]["contract_hash"]), String(fresh_ownership["contract_hash"]),
		phase_proofs, recoveries
	)
	if trace.is_empty():
		return U.failure("BRIDGE2_D_RECOVERY_TRACE_CREATE_FAILED")
	return {
		"success": true,
		"old_subject": old_subject,
		"structural": structural,
		"guard_result": guard_result,
		"broken": broken,
		"transaction": transaction,
		"topology_runtime": topology_runtime,
		"fresh_ownership": fresh_ownership,
		"rebound": rebound,
		"trace": trace,
	}

static func _fresh_ownership(old_ownership: Dictionary, broken: Dictionary) -> Dictionary:
	var representations: Array = old_ownership["representations"].duplicate(true)
	for representation in representations:
		representation["source_frontier_hash"] = String(broken["current_frontier"]["frontier_hash"])
		representation["authority_epoch_binding"] = String(broken["current_authority"]["authority_epoch_binding"])
	return Ownership.compile(
		broken["current_frontier"], broken["current_authority"], representations,
		old_ownership["region_bindings"].duplicate(true)
	)

static func _fresh_dynamic_hybrid(broken: Dictionary, fresh_ownership: Dictionary) -> Dictionary:
	var seed := DynamicFixture.build("ZERO")
	var request: Dictionary = seed["request"].duplicate(true)
	request["model_id"] = "dynamic-model/bridge2-d-current-frontier"
	request["canonical_source_frontier"] = broken["current_frontier"].duplicate(true)
	request["authority_envelope"] = broken["current_authority"].duplicate(true)
	var full := FullCompiler.compile(request)
	if not bool(full.get("success", false)):
		return full
	var rom := ROMCompiler.compile(full["model"])
	if not bool(rom.get("success", false)):
		return rom
	var certification := Certification.create(full["model"], rom["descriptor"])
	if certification.is_empty():
		return U.failure("BRIDGE2_D_FRESH_CERTIFICATION_FAILED")
	var dynamic_result := DynamicBridge.compile_bundle(
		full["model"], rom["descriptor"], rom["artifact_binding"], certification,
		"bake/bridge2-d-dynamic-current", "artifact/bridge2-d-dynamic-current", 2
	)
	if not bool(dynamic_result.get("success", false)):
		return dynamic_result
	var dynamic_bundle: Dictionary = dynamic_result["details"]["bundle"]
	var dynamic_started := DynamicBridge.start_execution(
		dynamic_bundle, full["model"], rom["descriptor"], rom["artifact_binding"], certification
	)
	if not bool(dynamic_started.get("success", false)):
		return dynamic_started
	var zero_flows := DynamicFixture.zero_flows(full["model"]["boundary_contract"])
	var dynamic_step := DynamicBridge.governed_step(
		dynamic_bundle, dynamic_started["details"]["session"], full["model"], rom["descriptor"],
		rom["artifact_binding"], certification, zero_flows, 0.01,
		String(full["model"]["source_binding"]["checksum"]), [], false
	)
	if not bool(dynamic_step.get("success", false)):
		return dynamic_step
	var blueprint := _hybrid_blueprint(dynamic_bundle, full["model"], rom, certification, String(fresh_ownership["contract_hash"]))
	var resolved := HybridRuntime.resolve_mode(blueprint, {})
	if not bool(resolved.get("success", false)):
		return resolved
	if String(resolved["details"].get("action", "")) != "LAZY_COMPILED":
		return U.failure("BRIDGE2_D_FRESH_HYBRID_NOT_LAZY_COMPILED", {"resolved": resolved})
	var package: Dictionary = resolved["details"]["package"]
	var started := HybridRuntime.start(package)
	if not bool(started.get("success", false)):
		return started
	var hybrid_step := HybridRuntime.flow_step(started["details"]["session"], package, zero_flows, 0.01, [], false)
	if not bool(hybrid_step.get("success", false)):
		return hybrid_step
	return {
		"success": true,
		"full_model": full["model"],
		"rom": rom,
		"certification": certification,
		"dynamic_bundle": dynamic_bundle,
		"dynamic_session": dynamic_started["details"]["session"],
		"dynamic_step": dynamic_step,
		"hybrid_blueprint": blueprint,
		"hybrid_resolution": resolved,
		"hybrid_package": package,
		"hybrid_session": started["details"]["session"],
		"hybrid_step": hybrid_step,
	}

static func _hybrid_blueprint(dynamic_bundle: Dictionary, full_model: Dictionary, rom: Dictionary, certification: Dictionary, ownership_hash: String) -> Dictionary:
	return {
		"mode_id": "mode/bridge2-b/hybrid-a",
		"mode_descriptor_id": "hybrid-mode/bridge2-b/executable-a",
		"active_relation_ids": ["relation/bridge2-b/hybrid-a"],
		"complementarity_active_ids": ["active-set/bridge2-b/hybrid-a"],
		"dependency_versions": [
			{"dependency_id": "dependency/bridge2-a/ownership", "version_hash": ownership_hash},
			{"dependency_id": "dependency/bridge2-b/dynamic-artifact", "version_hash": String(dynamic_bundle["physical_artifact"]["checksum"])},
		],
		"physical_bundle": dynamic_bundle,
		"full_model": full_model,
		"rom_descriptor": rom["descriptor"],
		"reduction_binding": rom["artifact_binding"],
		"certification": certification,
	}
