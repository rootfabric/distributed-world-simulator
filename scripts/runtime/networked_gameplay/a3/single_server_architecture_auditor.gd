extends RefCounted

const SCHEMA := "planet_simulator.single_server_multiplayer_architecture.v1"
const CHECKPOINT := "v16.10.6-architecture-a3-single-server-multiplayer"
const BUILD_ID := "a3-single-server-multiplayer-architecture-freeze"
const DECISION := "SINGLE_SERVER_MULTIPLAYER_FROZEN"
const PRODUCTION_SERVICE_PATH := "scripts/runtime/networked_gameplay/networked_gameplay_service.gd"

const REQUIRED_MILESTONES := ["M1", "M2", "M3", "M4", "M5", "M6"]
const REQUIRED_CONTRACTS := [
	"PlayerJoinCommand",
	"PlayerLeaveCommand",
	"PlayerInputCommand",
	"PlayerPresentationCommand",
	"PlayerOwnershipSnapshot",
	"PlayerStateSnapshot",
	"PlayerStateDelta",
	"ItemCommand",
	"ItemGraphSnapshot",
	"ItemGraphDelta",
	"CommandResult",
]
const REQUIRED_COMPONENTS := [
	"PlayerRegistry",
	"OwnershipService",
	"MovementService",
	"ItemGraphService",
	"ContainerInteractionService",
	"MountInteractionService",
	"ResultRouter",
	"ReplicationPublisher",
]
const REQUIRED_AUTHORITY_ADAPTERS := [
	"listen_host",
	"host_client_compatibility",
	"dedicated_enet",
	"dedicated_recovery",
]
const FORBIDDEN_B1_SCOPE := [
	"graphical client realtime traffic",
	"new gameplay command model",
	"direct broker calls from gameplay or domain code",
	"NATS subjects in canonical gameplay state",
	"broker delivery as authority ownership",
]


static func validate_manifest(value: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	_expect_equal(failures, String(value.get("schema", "")), SCHEMA, "schema")
	_expect_equal(failures, String(value.get("checkpoint", "")), CHECKPOINT, "checkpoint")
	_expect_equal(failures, String(value.get("build_id", "")), BUILD_ID, "build_id")
	_expect_equal(failures, String(value.get("decision", "")), DECISION, "decision")
	if String(value.get("status", "")) not in ["candidate", "accepted"]:
		failures.append("status must be candidate or accepted")
	_expect_equal(
		failures,
		String(value.get("base_checkpoint", "")),
		"v16.10.5-persistence-m6-dedicated-recovery",
		"base_checkpoint"
	)

	var milestones := _index_by_id(value.get("accepted_milestones", []))
	for milestone_id in REQUIRED_MILESTONES:
		if not milestones.has(milestone_id):
			failures.append("accepted milestone missing: %s" % milestone_id)
			continue
		if String(milestones.get(milestone_id, {}).get("effective_status", "")) != "accepted":
			failures.append("milestone is not effectively accepted: %s" % milestone_id)

	var production_path: Dictionary = value.get("production_gameplay_path", {})
	_expect_equal(
		failures,
		String(production_path.get("service_path", "")),
		PRODUCTION_SERVICE_PATH,
		"production service path"
	)
	_expect_equal(
		failures,
		String(production_path.get("service_count", "")),
		"one",
		"production service count"
	)
	if production_path.get("canonical_pipeline", []) != [
		"input_or_ui_intent",
		"client_command_gateway",
		"versioned_wire_command",
		"NetworkedGameplayService",
		"authoritative_mutation",
		"durable_commit_when_enabled",
		"targeted_result_and_replication",
		"client_replica_store",
		"presentation",
	]:
		failures.append("canonical production pipeline changed")

	var adapters := _index_by_id(production_path.get("authority_adapters", []))
	if adapters.size() != REQUIRED_AUTHORITY_ADAPTERS.size():
		failures.append("authority adapter count changed")
	for adapter_id in REQUIRED_AUTHORITY_ADAPTERS:
		if not adapters.has(adapter_id):
			failures.append("authority adapter missing: %s" % adapter_id)
			continue
		if String(adapters.get(adapter_id, {}).get("gameplay_service", "")) != "NetworkedGameplayService":
			failures.append("adapter bypasses NetworkedGameplayService: %s" % adapter_id)

	var contract_family: Array = value.get("wire_contract_family", [])
	var contract_names: Array[String] = []
	for contract_value in contract_family:
		if contract_value is Dictionary:
			contract_names.append(String(contract_value.get("name", "")))
	contract_names.sort()
	var expected_contracts := REQUIRED_CONTRACTS.duplicate()
	expected_contracts.sort()
	if contract_names != expected_contracts:
		failures.append("wire contract family changed")
	for contract_value in contract_family:
		if not contract_value is Dictionary:
			failures.append("wire contract entry is not a dictionary")
			continue
		var contract: Dictionary = contract_value
		if String(contract.get("path", "")).is_empty():
			failures.append("wire contract path is empty: %s" % String(contract.get("name", "")))
		for property_name in ["versioned", "json_safe", "exact_field", "node_independent"]:
			if not bool(contract.get(property_name, false)):
				failures.append("wire contract property missing %s: %s" % [property_name, String(contract.get("name", ""))])

	var freeze: Dictionary = value.get("frozen_invariants", {})
	for key in [
		"single_authoritative_writer",
		"stable_player_identity",
		"ownership_epoch_fencing",
		"operation_replay_idempotency",
		"canonical_item_identity_conservation",
		"replica_only_graphical_clients",
		"transient_transport_sessions",
		"durable_recovery_before_ack",
	]:
		if not bool(freeze.get(key, false)):
			failures.append("frozen invariant missing: %s" % key)

	var b1: Dictionary = value.get("b1_handoff", {})
	_expect_equal(failures, String(b1.get("checkpoint", "")), "v16.11.0-data-plane-b1-nats-core", "B1 checkpoint")
	_expect_equal(failures, String(b1.get("scope", "")), "server_to_server_only", "B1 scope")
	for forbidden in FORBIDDEN_B1_SCOPE:
		if forbidden not in b1.get("forbidden_scope", []):
			failures.append("B1 forbidden scope missing: %s" % forbidden)
	if bool(b1.get("may_replace_enet", true)):
		failures.append("B1 may not replace ENet")
	if bool(b1.get("may_create_second_gameplay_path", true)):
		failures.append("B1 may not create a second gameplay path")

	var gates: Dictionary = value.get("multi_authority_gate", {})
	if bool(gates.get("production_multi_authority_allowed", true)):
		failures.append("production multi-authority must remain blocked")
	if gates.get("required_before_n3", []) != ["A3", "B1", "B2"]:
		failures.append("N3 prerequisite chain changed")

	return _result(failures, {
		"milestones": milestones.size(),
		"contracts": contract_family.size(),
		"authority_adapters": adapters.size(),
	})


static func audit_sources(sources: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	var service_source := String(sources.get(PRODUCTION_SERVICE_PATH, ""))
	if service_source.is_empty():
		failures.append("production NetworkedGameplayService source missing")
	else:
		for component in REQUIRED_COMPONENTS:
			if not service_source.contains(component):
				failures.append("production service component missing: %s" % component)
		for forbidden in ["NATS", "JetStream", "nats://", "subject_name"]:
			if service_source.contains(forbidden):
				failures.append("broker concern leaked into gameplay service: %s" % forbidden)

	var adapter_rules := {
		"scripts/runtime/listen_host/playable_listen_host_authority.gd": "networked_gameplay_service.gd",
		"scripts/runtime/host_client/multiplayer_gameplay_authority.gd": "networked_gameplay_service.gd",
		"scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd": "networked_gameplay_service.gd",
		"scripts/runtime/networked_gameplay/m6/m6_dedicated_gameplay_authority_adapter.gd": "service_reference",
	}
	for path in adapter_rules:
		var source := String(sources.get(path, ""))
		if source.is_empty():
			failures.append("authority adapter source missing: %s" % path)
			continue
		if not source.contains(String(adapter_rules[path])):
			failures.append("authority adapter does not delegate to common service: %s" % path)
		for forbidden in ["var _players: Dictionary", "var _operation_ledger", "NATS", "JetStream"]:
			if source.contains(forbidden):
				failures.append("topology-specific gameplay fork marker in %s: %s" % [path, forbidden])

	for path in [
		"scripts/runtime/listen_host/client_runtime.gd",
		"scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd",
		"scripts/runtime/networked_gameplay/transports/graphical_game_client_runtime.gd",
	]:
		var source := String(sources.get(path, ""))
		if source.is_empty():
			failures.append("graphical client source missing: %s" % path)
			continue
		for forbidden in [
			"networked_gameplay_service.gd",
			"player_registry.gd",
			"player_ownership_service.gd",
			"authoritative_recovery_repository.gd",
		]:
			if source.contains(forbidden):
				failures.append("client authority reference found in %s: %s" % [path, forbidden])

	var contract_count := 0
	for contract_name in REQUIRED_CONTRACTS:
		var contract_path := _contract_path(contract_name)
		var source := String(sources.get(contract_path, ""))
		if source.is_empty():
			failures.append("wire contract source missing: %s" % contract_path)
			continue
		contract_count += 1
		if not source.contains("extends RefCounted"):
			failures.append("wire contract is not RefCounted: %s" % contract_name)
		for forbidden in ["extends Node", "extends SceneTree", "get_tree()", "SceneTree", "Camera3D", "Control"]:
			if source.contains(forbidden):
				failures.append("wire contract contains presentation/runtime dependency %s: %s" % [contract_name, forbidden])

	return _result(failures, {
		"sources": sources.size(),
		"contracts": contract_count,
		"authority_adapters": adapter_rules.size(),
		"graphical_clients": 3,
	})


static func _contract_path(contract_name: String) -> String:
	var paths := {
		"PlayerJoinCommand": "scripts/runtime/networked_gameplay/contracts/player_join_command.gd",
		"PlayerLeaveCommand": "scripts/runtime/networked_gameplay/contracts/player_leave_command.gd",
		"PlayerInputCommand": "scripts/runtime/networked_gameplay/contracts/player_input_command.gd",
		"PlayerPresentationCommand": "scripts/runtime/networked_gameplay/contracts/player_presentation_command.gd",
		"PlayerOwnershipSnapshot": "scripts/runtime/networked_gameplay/contracts/player_ownership_snapshot.gd",
		"PlayerStateSnapshot": "scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd",
		"PlayerStateDelta": "scripts/runtime/networked_gameplay/contracts/player_state_delta.gd",
		"ItemCommand": "scripts/runtime/networked_gameplay/contracts/item_command.gd",
		"ItemGraphSnapshot": "scripts/runtime/networked_gameplay/contracts/item_graph_snapshot.gd",
		"ItemGraphDelta": "scripts/runtime/networked_gameplay/contracts/item_graph_delta.gd",
		"CommandResult": "scripts/runtime/networked_gameplay/contracts/command_result.gd",
	}
	return String(paths.get(contract_name, ""))


static func _index_by_id(values: Array) -> Dictionary:
	var result: Dictionary = {}
	for value in values:
		if value is Dictionary:
			var identifier := String(value.get("id", ""))
			if not identifier.is_empty():
				result[identifier] = value
	return result


static func _expect_equal(failures: Array[String], actual, expected, field_name: String) -> void:
	if actual != expected:
		failures.append("%s mismatch" % field_name)


static func _result(failures: Array[String], details: Dictionary) -> Dictionary:
	return {
		"success": failures.is_empty(),
		"error_code": "" if failures.is_empty() else "A3_ARCHITECTURE_AUDIT_FAILED",
		"details": details.duplicate(true),
		"failures": failures.duplicate(),
	}
