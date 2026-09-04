extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Ordering = preload("res://scripts/research/fabric_bake0/mixed_representation_invalidation_ordering_v1.gd")
const Router = preload("res://scripts/research/fabric_bake0/mixed_representation_event_router_v1.gd")
const Bridge0 = preload("res://scripts/research/fabric_bake0/fabric_bake_bridge0_v1.gd")
const Lifecycle = preload("res://scripts/research/fabric_bake0/physical_source_lifecycle_v1.gd")
const ContactBridge = preload("res://scripts/research/fabric_bake0/contact_wrench_bake_bridge_v1.gd")
const LocalRuntime = preload("res://scripts/research/fabric_bake0/structural_local_unbake_runtime_v1.gd")
const TopologyRuntime = preload("res://scripts/research/fabric_bake0/structural_topology_rebake_runtime_v1.gd")
const DynamicBridge = preload("res://scripts/research/fabric_bake0/dynamic_rom_physical_bake_bridge_v1.gd")
const HybridRuntime = preload("res://scripts/research/fabric_bake0/hybrid_bake_executable_runtime_v1.gd")
const DynamicFixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_4_a_fixture.gd")
const Complex0 = preload("res://tests/research/fabric_bake0/fabric_bake_complex0_fixture.gd")
const B2BFixture = preload("res://tests/research/fabric_bake0/fabric_bake_bridge2_b_fixture.gd")
const B2CFixture = preload("res://tests/research/fabric_bake0/fabric_bake_bridge2_c_fixture.gd")

static func build() -> Dictionary:
	var mixed := B2BFixture.build()
	if not bool(mixed.get("success", false)):
		return mixed
	var canonical: Dictionary = mixed["canonical"]
	var structural := Complex0.compile_structural(canonical)
	if not bool(structural.get("success", false)):
		return structural
	var guard_result := Complex0.evaluate_guard(canonical, structural)
	if not bool(guard_result.get("success", false)):
		return guard_result
	var local_transition := LocalRuntime.execute(
		structural["local"]["plan"], structural["aggregate"]["descriptor"],
		structural["aggregate"]["reconstruction_mapping"], structural["guard"]["guard_field"],
		Complex0.reduced_state(), Complex0.guard_context(canonical, structural)
	)
	if not bool(local_transition.get("success", false)):
		return local_transition

	# Canonical break is committed only after the local FULL transition has succeeded.
	var broken := Complex0.make_break(canonical, structural)
	if not bool(broken.get("success", false)):
		return broken
	var c_subject := {
		"success": true, "mixed": mixed, "structural": structural, "broken": broken,
		"entries": _entry_map(mixed["subject"]),
	}
	var route_result := B2CFixture.canonical_route(c_subject)
	if not bool(route_result.get("success", false)):
		return route_result
	var route: Dictionary = route_result["details"]["route"]
	var receipt_result := B2CFixture.canonical_receipt(c_subject, route)
	if not bool(receipt_result.get("success", false)):
		return receipt_result
	var receipt: Dictionary = receipt_result["details"]["receipt"]
	var commit_result := Router.commit_route(route, receipt, mixed["subject"], mixed["ownership"], [])
	if not bool(commit_result.get("success", false)):
		return commit_result
	var commit: Dictionary = commit_result["details"]["commit"]

	var tick := int(broken["event"]["event_tick"])
	var structural_invalidation := Bridge0.invalidate_from_source_mutation(
		mixed["structural_bundle"]["artifact"], broken["source_invalidation"], broken["current_frontier"], tick
	)
	var contact_invalidation := Bridge0.invalidate_from_source_mutation(
		mixed["contact_bundle"]["artifact"], broken["source_invalidation"], broken["current_frontier"], tick
	)
	var dynamic_invalidation := Bridge0.invalidate_from_source_mutation(
		mixed["dynamic_bundle"]["physical_artifact"], broken["source_invalidation"], broken["current_frontier"], tick
	)
	for invalidation in [structural_invalidation, contact_invalidation, dynamic_invalidation]:
		if invalidation.has("success") and not bool(invalidation.get("success", false)):
			return invalidation

	var old_hybrid_key := String(mixed["hybrid_package"]["mode_descriptor"]["cache_key"])
	var old_registry := {old_hybrid_key: mixed["hybrid_package"].duplicate(true)}
	var hybrid_invalidated := HybridRuntime.invalidate_cached_mode(old_registry, old_hybrid_key, "SOURCE_FRONTIER_CHANGED")
	if not bool(hybrid_invalidated.get("success", false)):
		return hybrid_invalidated
	var stale_registry: Dictionary = hybrid_invalidated["details"]["registry"]

	var structural_stale := Lifecycle.execute(mixed["structural_bundle"], Complex0.reduced_state(), 0.0, [structural_invalidation])
	var contact_stale := ContactBridge.support(
		mixed["structural_bundle"], mixed["contact_bundle"],
		[0.0, 0.0, 1.0, 0.0, 0.0, 0.0], 0.0, [contact_invalidation]
	)
	var zero_flows := DynamicFixture.zero_flows(mixed["full_model"]["boundary_contract"])
	var dynamic_stale := DynamicBridge.governed_step(
		mixed["dynamic_bundle"], mixed["dynamic_session"], mixed["full_model"],
		mixed["rom"]["descriptor"], mixed["rom"]["artifact_binding"], mixed["certification"],
		zero_flows, 0.01, String(mixed["full_model"]["source_binding"]["checksum"]),
		[dynamic_invalidation], false
	)
	var hybrid_stale := HybridRuntime.flow_step(
		mixed["hybrid_session"], mixed["hybrid_package"], zero_flows, 0.01,
		[dynamic_invalidation], false
	)
	var stale_mode_resolution := HybridRuntime.resolve_mode(_old_hybrid_blueprint(mixed), stale_registry)

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

	var phase_proofs := [
		U.canonical_hash({"phase": Ordering.INVALIDATION_PHASES[0], "guard": guard_result}),
		U.canonical_hash({"phase": Ordering.INVALIDATION_PHASES[1], "local_transition": local_transition}),
		U.canonical_hash({"phase": Ordering.INVALIDATION_PHASES[2], "commit_hash": commit["commit_hash"]}),
		U.canonical_hash({"phase": Ordering.INVALIDATION_PHASES[3], "source_invalidation": broken["source_invalidation"]}),
		U.canonical_hash({"phase": Ordering.INVALIDATION_PHASES[4], "invalidations": [structural_invalidation, contact_invalidation, dynamic_invalidation], "hybrid_cache_checksum": hybrid_invalidated["details"]["package"]["checksum"]}),
		U.canonical_hash({"phase": Ordering.INVALIDATION_PHASES[5], "rejections": [_compact(structural_stale), _compact(contact_stale), _compact(dynamic_stale), _compact(hybrid_stale), _compact(stale_mode_resolution)]}),
		U.canonical_hash({"phase": Ordering.INVALIDATION_PHASES[6], "transaction_checksum": transaction["checksum"], "transaction_event_commit": topology_runtime["event_commit"]}),
	]
	var trace := Ordering.create_invalidation(
		String(commit["event_id"]), String(commit["previous_source_frontier_hash"]),
		String(commit["current_source_frontier_hash"]), String(route["route_hash"]),
		String(commit["commit_hash"]), String(mixed["subject"]["subject_hash"]),
		String(mixed["ownership"]["contract_hash"]), phase_proofs
	)
	if trace.is_empty():
		return U.failure("BRIDGE2_D_INVALIDATION_TRACE_CREATE_FAILED")
	return {
		"success": true,
		"mixed": mixed,
		"structural": structural,
		"guard_result": guard_result,
		"local_transition": local_transition,
		"broken": broken,
		"route": route,
		"receipt": receipt,
		"commit": commit,
		"structural_invalidation": structural_invalidation,
		"contact_invalidation": contact_invalidation,
		"dynamic_invalidation": dynamic_invalidation,
		"hybrid_invalidated": hybrid_invalidated,
		"stale_registry": stale_registry,
		"structural_stale": structural_stale,
		"contact_stale": contact_stale,
		"dynamic_stale": dynamic_stale,
		"hybrid_stale": hybrid_stale,
		"stale_mode_resolution": stale_mode_resolution,
		"transaction": transaction,
		"topology_runtime": topology_runtime,
		"trace": trace,
	}

static func _old_hybrid_blueprint(mixed: Dictionary) -> Dictionary:
	return {
		"mode_id": "mode/bridge2-b/hybrid-a",
		"mode_descriptor_id": "hybrid-mode/bridge2-b/executable-a",
		"active_relation_ids": ["relation/bridge2-b/hybrid-a"],
		"complementarity_active_ids": ["active-set/bridge2-b/hybrid-a"],
		"dependency_versions": [
			{"dependency_id": "dependency/bridge2-a/ownership", "version_hash": String(mixed["ownership"]["contract_hash"])},
			{"dependency_id": "dependency/bridge2-b/dynamic-artifact", "version_hash": String(mixed["dynamic_bundle"]["physical_artifact"]["checksum"])},
		],
		"physical_bundle": mixed["dynamic_bundle"],
		"full_model": mixed["full_model"],
		"rom_descriptor": mixed["rom"]["descriptor"],
		"reduction_binding": mixed["rom"]["artifact_binding"],
		"certification": mixed["certification"],
	}

static func _entry_map(subject: Dictionary) -> Dictionary:
	var output := {}
	for entry in subject["entries"]:
		output[String(entry["representation_id"])] = entry
	return output

static func _compact(result: Dictionary) -> Dictionary:
	return {
		"success": bool(result.get("success", result.get("ok", false))),
		"error_code": String(result.get("error_code", result.get("code", ""))),
		"status": String(result.get("status", "")),
		"reason": String(result.get("reason", "")),
	}
