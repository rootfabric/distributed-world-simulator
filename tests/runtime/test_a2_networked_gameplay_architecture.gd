extends SceneTree

const MANIFEST_PATH := "res://config/network/networked-gameplay-architecture.v1.json"
const ROADMAP_PATH := "res://config/network/network-roadmap.v1.json"

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	var manifest := _load_json(MANIFEST_PATH)
	var roadmap := _load_json(ROADMAP_PATH)
	_test_manifest_identity(manifest)
	_test_pipeline_and_topologies(manifest)
	_test_identity_ownership_and_replay(manifest)
	_test_assessment_debt_and_gates(manifest)
	_test_roadmap_alignment(roadmap)
	_test_source_evidence(manifest)
	_test_documentation_evidence()
	_test_regression_runner_coverage()
	_finish()


func _test_manifest_identity(manifest: Dictionary) -> void:
	_assert(not manifest.is_empty(), "A2 freeze manifest is missing or invalid")
	_assert(String(manifest.get("schema", "")) == "planet_simulator.networked_gameplay_architecture.v1", "A2 schema mismatch")
	_assert(int(manifest.get("document_revision", 0)) == 3, "A2 document revision mismatch")
	_assert(String(manifest.get("checkpoint", "")) == "v16.9.4-architecture-a2-networked-gameplay", "A2 checkpoint mismatch")
	_assert(String(manifest.get("build_id", "")) == "a2-networked-gameplay-audit-freeze", "A2 build ID mismatch")
	_assert(String(manifest.get("status", "")) == "accepted", "A2 status must be accepted after independent verification")
	_assert(String(manifest.get("decision", "")) == "FROZEN_WITH_GATES", "A2 decision mismatch")
	var evidence: Dictionary = manifest.get("runtime_evidence_base", {})
	for stage in ["H1", "H2", "H3"]:
		_assert(String(evidence.get(stage, {}).get("status", "")) == "accepted", "%s is not accepted in A2 evidence" % stage)
	_assert(String(evidence.get("H1", {}).get("checkpoint", "")) == "v16.9.1-runtime-h1-playable-listen-host", "H1 evidence checkpoint mismatch")
	_assert(String(evidence.get("H2", {}).get("checkpoint", "")) == "v16.9.2-runtime-h2-host-client-ownership", "H2 evidence checkpoint mismatch")
	_assert(String(evidence.get("H3", {}).get("checkpoint", "")) == "v16.9.3-runtime-h3-dedicated-multiplayer", "H3 evidence checkpoint mismatch")


func _test_pipeline_and_topologies(manifest: Dictionary) -> void:
	var pipeline: Array = manifest.get("canonical_pipeline", [])
	_assert(pipeline == [
		"input_or_ui_intent", "client_command_gateway", "versioned_command_dto",
		"authority_command_handler", "authoritative_mutation", "targeted_command_result",
		"snapshot_or_delta", "client_replica_store", "presentation",
	], "Canonical gameplay pipeline changed")
	var topologies: Array = manifest.get("topology_matrix", [])
	_assert(topologies.size() == 3, "A2 must freeze three proven topologies")
	var by_id: Dictionary = {}
	for topology_value in topologies:
		if topology_value is Dictionary:
			by_id[String(topology_value.get("id", ""))] = topology_value
	_assert(by_id.has("listen_host"), "listen_host topology missing")
	_assert(by_id.has("dedicated_single"), "dedicated_single topology missing")
	_assert(by_id.has("dedicated_multi"), "dedicated_multi topology missing")
	_assert(String(by_id.get("listen_host", {}).get("client_kind", "")) == "graphical", "H1 graphical evidence lost")
	_assert(String(by_id.get("dedicated_single", {}).get("transport", "")) == "enet_multi_peer_v2", "H2 transport mismatch")
	_assert(String(by_id.get("dedicated_multi", {}).get("client_kind", "")) == "two_headless_protocol_clients", "H3 evidence must not claim unproven graphical clients")
	_assert("movement_replication" in by_id.get("dedicated_multi", {}).get("proven_scope", []), "H3 movement evidence missing")
	_assert("shared_item_contention" in by_id.get("dedicated_multi", {}).get("proven_scope", []), "H3 contention evidence missing")


func _test_identity_ownership_and_replay(manifest: Dictionary) -> void:
	var identity: Dictionary = manifest.get("identity_model", {})
	for field in ["logical_player_id", "player_entity_id", "transport_session_id", "ownership_epoch", "authority_owner_id", "authority_epoch", "route_generation"]:
		_assert(identity.has(field), "Identity model missing %s" % field)
	_assert(String(identity.get("rule", "")).contains("never replaces"), "Transport/player identity separation is not frozen")
	var boundary: Dictionary = manifest.get("command_ownership_boundary", {})
	for fence in ["logical_player_id", "transport_session_id", "ownership_epoch", "operation_id", "payload_fingerprint"]:
		_assert(fence in boundary.get("required_fences", []), "Command fence missing: %s" % fence)
	_assert(String(boundary.get("permission_rule", "")).contains("owned player state"), "Player permission rule missing")
	_assert(String(boundary.get("replay_rule", "")).contains("without second mutation"), "Replay idempotency missing")
	_assert(String(boundary.get("conflict_rule", "")).contains("rejected"), "Replay conflict rule missing")
	var reconnect: Dictionary = manifest.get("reconnect_and_replay", {})
	for flag in ["logical_identity_persists", "player_entity_identity_persists", "transport_session_rotates", "ownership_epoch_increments", "duplicate_player_forbidden", "stale_transport_session_rejected", "exact_operation_replay_is_idempotent"]:
		_assert(bool(reconnect.get(flag, false)), "Reconnect invariant missing: %s" % flag)
	var mapping: Dictionary = manifest.get("peer_to_player_mapping", {})
	_assert(String(mapping.get("source_of_truth", "")) == "authority-owned ownership registry", "Peer mapping source changed")
	_assert(String(mapping.get("disconnect", "")).contains("must not stop listener"), "Peer-independent listener lifecycle missing")


func _test_assessment_debt_and_gates(manifest: Dictionary) -> void:
	var assessment: Dictionary = manifest.get("implementation_assessment", {})
	_assert(bool(assessment.get("architecture_target_frozen", false)), "Architecture target is not frozen")
	_assert(bool(assessment.get("one_semantic_pipeline_frozen", false)), "Semantic pipeline is not frozen")
	_assert(bool(assessment.get("one_production_service_implementation_across_h1_h2_h3", false)), "M1 implementation convergence is not recorded")
	_assert(bool(assessment.get("shared_wire_validators_independent_from_authority_implementations", false)), "M1 shared validator closure is not recorded")
	_assert(not bool(assessment.get("two_graphical_client_windows_proven", true)), "A2 incorrectly claims two graphical windows")
	_assert(not bool(assessment.get("full_item_graph_contention_over_dedicated_transport_proven", true)), "A2 incorrectly claims full Item Graph contention")
	_assert(bool(assessment.get("b1_allowed", false)), "B1 should be allowed behind frozen B0 constraints")
	_assert(not bool(assessment.get("multi_authority_work_allowed", true)), "Multi-authority work must remain blocked")
	var debt: Array = manifest.get("known_debt", [])
	_assert(debt.size() == 5, "A2 debt register size changed")
	var debt_by_id: Dictionary = {}
	for entry_value in debt:
		if entry_value is Dictionary:
			debt_by_id[String(entry_value.get("id", ""))] = entry_value
	for debt_id in ["A2-D01", "A2-D02", "A2-D03", "A2-D04"]:
		_assert(debt_by_id.has(debt_id), "Required architecture debt entry missing: %s" % debt_id)
	for debt_id in ["A2-D01", "A2-D02"]:
		_assert(String(debt_by_id.get(debt_id, {}).get("status", "")) == "closed", "%s must be closed by M1" % debt_id)
		_assert(String(debt_by_id.get(debt_id, {}).get("closed_by", "")) == "M1", "%s closure checkpoint mismatch" % debt_id)
	for debt_id in ["A2-D03", "A2-D04"]:
		_assert(String(debt_by_id.get(debt_id, {}).get("status", "")) == "open", "%s must remain open" % debt_id)
		_assert(String(debt_by_id.get(debt_id, {}).get("closure_before", "")) == "A3", "%s must close before A3" % debt_id)
	var b1: Dictionary = manifest.get("b1_constraints", {})
	_assert(String(b1.get("next_checkpoint", "")) == "v16.11.0-data-plane-b1-nats-core", "B1 checkpoint mismatch")
	_assert(String(b1.get("branch", "")) == "feature/b1-nats-core-adapter", "B1 branch mismatch")
	for forbidden in ["new gameplay command model", "direct broker calls from domain/runtime gameplay", "NATS subject names in canonical domain state", "using broker delivery as authority ownership"]:
		_assert(forbidden in b1.get("forbidden_scope", []), "B1 forbidden scope missing: %s" % forbidden)
	var gates: Dictionary = manifest.get("multi_authority_gates", {})
	_assert(gates.get("blocked_until", []) == ["M1", "M2", "M3", "M4", "M5", "M6", "A3", "B1", "B2"], "Multi-authority blockers changed")


func _test_roadmap_alignment(roadmap: Dictionary) -> void:
	_assert(String(roadmap.get("project_checkpoint", "")) == "v16.10.0-runtime-m1-unified-networked-gameplay-core", "Roadmap current checkpoint mismatch")
	_assert(String(roadmap.get("runtime_base_checkpoint", "")) == "v16.10.0-runtime-m1-unified-networked-gameplay-core", "Roadmap runtime base mismatch")
	var phases: Dictionary = {}
	for phase_value in roadmap.get("phases", []):
		if phase_value is Dictionary:
			phases[String(phase_value.get("id", ""))] = phase_value
	for stage in ["H1", "H2", "H3"]:
		_assert(String(phases.get(stage, {}).get("status", "")) == "accepted", "%s roadmap status is not accepted" % stage)
	_assert(String(phases.get("A2", {}).get("status", "")) == "accepted", "A2 roadmap status mismatch")
	_assert(String(phases.get("M1", {}).get("status", "")) == "current_candidate", "M1 roadmap status must be current candidate")
	_assert(String(phases.get("B1", {}).get("status", "")) == "deferred_after_A3", "B1 roadmap status must be deferred after A3")
	_assert(String(roadmap.get("architecture_freeze_manifest", "")) == "config/network/networked-gameplay-architecture.v1.json", "Roadmap freeze manifest link missing")


func _test_source_evidence(manifest: Dictionary) -> void:
	var h1_authority := _read("res://scripts/runtime/listen_host/playable_listen_host_authority.gd")
	var h1_session := _read("res://scripts/runtime/listen_host/playable_client_session.gd")
	var h1_bridge := _read("res://scripts/runtime/listen_host/playable_item_command_bridge.gd")
	var h2_registry := _read("res://scripts/runtime/host_client/player_ownership_registry.gd")
	var h2_replica := _read("res://scripts/runtime/host_client/player_ownership_replica_store.gd")
	var h3_authority := _read("res://scripts/runtime/host_client/multiplayer_gameplay_authority.gd")
	var h3_replica := _read("res://scripts/runtime/host_client/multiplayer_gameplay_replica_store.gd")
	var service := _read("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
	var h3_client := _read("res://tools/runtime/h3_multiplayer_client.gd")
	var t1_boundary := _read("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
	for content in [h1_authority, h1_session, h1_bridge, h2_registry, h2_replica, h3_authority, h3_replica, service, h3_client, t1_boundary]:
		_assert(not content.is_empty(), "Required implementation evidence file is missing")
	_assert(h1_authority.contains("networked_gameplay_service.gd"), "H1 adapter does not use NetworkedGameplayService")
	_assert(h3_authority.contains("networked_gameplay_service.gd"), "H3 adapter does not use NetworkedGameplayService")
	_assert(h2_registry.contains("player_ownership_service.gd"), "H2 adapter does not use shared PlayerOwnershipService")
	_assert(not h1_authority.contains("_operation_ledger") and not h3_authority.contains("_operation_ledger"), "Compatibility authority retains an independent operation ledger")
	_assert(h2_replica.contains("player_ownership_snapshot.gd"), "H2 replica does not use independent ownership validator")
	_assert(not h2_replica.contains("player_ownership_registry.gd"), "H2 replica still depends on authority implementation")
	_assert(h3_replica.contains("player_state_snapshot.gd") and h3_replica.contains("player_state_delta.gd"), "H3 replica does not use independent state validators")
	_assert(not h3_replica.contains("multiplayer_gameplay_authority.gd"), "H3 replica still depends on authority implementation")
	for component in ["PlayerRegistry", "OwnershipService", "MovementService", "ItemGraphService", "ContainerInteractionService", "MountInteractionService", "ResultRouter", "ReplicationPublisher"]:
		_assert(service.contains(component), "NetworkedGameplayService component missing: %s" % component)
	_assert(h1_session.contains('"direct_authority_references": 0'), "H1 client session authority boundary missing")
	_assert(h1_bridge.contains('"direct_authority_references": 0'), "H1 item bridge authority boundary missing")
	_assert(h3_client.contains("extends SceneTree"), "H3 client process evidence missing")
	_assert(not h3_client.contains("Control") and not h3_client.contains("Camera3D"), "M1 must not claim M3 graphical evidence")
	_assert(t1_boundary.contains("_outbound_queues") and t1_boundary.contains("STALE_TRANSPORT_SESSION"), "T1 peer isolation evidence missing")
	_assert(bool(manifest.get("implementation_assessment", {}).get("one_production_service_implementation_across_h1_h2_h3", false)), "M1 convergence assessment missing")
	_assert(bool(manifest.get("implementation_assessment", {}).get("shared_wire_validators_independent_from_authority_implementations", false)), "M1 validator assessment missing")


func _test_documentation_evidence() -> void:
	var required := [
		"res://docs/architecture/A2_NETWORKED_GAMEPLAY_ARCHITECTURE_RU.md",
		"res://docs/architecture/adr/ADR-011-networked-gameplay-boundary.md",
		"res://docs/architecture/audits/2026-07-30_V16_9_4_NETWORKED_GAMEPLAY_AUDIT_RU.md",
		"res://docs/checkpoints/2026-07-30_V16_9_4_ARCHITECTURE_A2_NETWORKED_GAMEPLAY_RU.md",
	]
	for path in required:
		_assert(FileAccess.file_exists(path), "A2 document missing: %s" % path)
	var architecture := _read(required[0])
	var adr := _read(required[1])
	var audit := _read(required[2])
	_assert(architecture.contains("FROZEN_WITH_GATES"), "A2 architecture decision missing")
	_assert(architecture.contains("A2-D01"), "A2 architecture debt register link missing")
	_assert(adr.contains("NetworkedGameplayService"), "ADR consolidation decision missing")
	_assert(audit.contains("B1 adapter work: ALLOWED WITH GATES"), "A2 audit B1 decision missing")
	_assert(audit.contains("FULL SINGLE-SERVER MULTIPLAYER FIRST"), "Post-A2 priority decision missing")
	_assert(audit.contains("N3–N6 multi-authority work: BLOCKED"), "A2 audit multi-authority block missing")


func _test_regression_runner_coverage() -> void:
	var network_runner := _read("res://RUN_NETWORK_CONTRACT_TESTS.ps1")
	var world_runner := _read("res://RUN_WORLD_REGRESSION_TESTS.ps1")
	for runner in [network_runner, world_runner]:
		_assert(not runner.is_empty(), "Required full regression runner is missing")
		for path in [
			"res://tests/runtime/test_m1_networked_gameplay_contracts.gd",
			"res://tests/runtime/test_m1_unified_networked_gameplay_service.gd",
			"res://tests/runtime/test_h2_player_ownership_contracts.gd",
			"res://tests/runtime/test_h2_host_client_processes.gd",
			"res://tests/runtime/test_h3_multiplayer_gameplay_contracts.gd",
			"res://tests/runtime/test_h3_dedicated_multiplayer_processes.gd",
			"res://tests/runtime/test_a2_networked_gameplay_architecture.gd",
			"res://tests/runtime/test_post_a2_single_server_multiplayer_roadmap.gd",
		]:
			_assert(runner.contains(path), "Regression runner does not cover accepted H2/H3/A2 evidence: %s" % path)
		_assert(runner.contains("v16.10.0-runtime-m1-unified-networked-gameplay-core"), "Regression runner checkpoint is stale")


func _load_json(path: String) -> Dictionary:
	var text := _read(path)
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("A2 networked gameplay architecture audit: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("A2 networked gameplay architecture audit: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
