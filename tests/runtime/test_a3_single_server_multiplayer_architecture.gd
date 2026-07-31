extends SceneTree

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Service = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
const Auditor = preload("res://scripts/runtime/networked_gameplay/a3/single_server_architecture_auditor.gd")

const MANIFEST_PATH := "res://config/network/single-server-multiplayer-architecture.v1.json"
const ROADMAP_PATH := "res://config/network/network-roadmap.v1.json"
const STRATEGY_PATH := "res://config/network/single-server-multiplayer-roadmap.v1.json"
const A2_PATH := "res://config/network/networked-gameplay-architecture.v1.json"

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	var manifest := _load_json(MANIFEST_PATH)
	_test_manifest_and_auditor(manifest)
	_test_milestone_acceptance(manifest)
	_test_source_freeze(manifest)
	_test_topology_equivalence_and_recovery()
	_test_roadmaps_and_debt()
	_test_documents_and_runners()
	_finish()


func _test_manifest_and_auditor(manifest: Dictionary) -> void:
	_assert(not manifest.is_empty(), "A3 architecture manifest is missing")
	var validation: Dictionary = Auditor.validate_manifest(manifest)
	_assert(bool(validation.get("success", false)), "A3 manifest audit failed: %s" % [validation.get("failures", [])])
	_assert(String(manifest.get("schema", "")) == Auditor.SCHEMA, "A3 manifest schema mismatch")
	_assert(int(manifest.get("document_revision", 0)) == 2, "A3 manifest revision mismatch")
	_assert(String(manifest.get("checkpoint", "")) == Auditor.CHECKPOINT, "A3 checkpoint mismatch")
	_assert(String(manifest.get("build_id", "")) == Auditor.BUILD_ID, "A3 build ID mismatch")
	_assert(String(manifest.get("status", "")) == "accepted", "A3 independent acceptance is not recorded")
	_assert(String(manifest.get("decision", "")) == Auditor.DECISION, "A3 freeze decision mismatch")
	_assert(String(manifest.get("next_checkpoint", "")) == "v16.11.0-data-plane-b1-nats-core", "A3 next checkpoint mismatch")
	_assert(String(manifest.get("b1_handoff", {}).get("scope", "")) == "server_to_server_only", "B1 scope is not server-to-server only")
	_assert(not bool(manifest.get("b1_handoff", {}).get("may_replace_enet", true)), "B1 may replace ENet")
	_assert(not bool(manifest.get("b1_handoff", {}).get("may_create_second_gameplay_path", true)), "B1 may create second gameplay path")
	_assert(not bool(manifest.get("multi_authority_gate", {}).get("production_multi_authority_allowed", true)), "A3 incorrectly opens production multi-authority")


func _test_milestone_acceptance(manifest: Dictionary) -> void:
	var expected := {
		"M1": ["res://config/network/networked-gameplay-core.v1.json", "v16.10.0-runtime-m1-unified-networked-gameplay-core"],
		"M2": ["res://config/network/dedicated-graphical-client.v1.json", "v16.10.1-runtime-m2-dedicated-graphical-client"],
		"M3": ["res://config/network/dedicated-graphical-multiplayer.v1.json", "v16.10.2-runtime-m3-dedicated-graphical-multiplayer"],
		"M4": ["res://config/network/canonical-shared-gameplay.v1.json", "v16.10.3-domain-m4-canonical-shared-gameplay"],
		"M5": ["res://config/network/graphical-multiplayer-acceptance.v1.json", "v16.10.4-testing-m5-graphical-multiplayer-acceptance"],
		"M6": ["res://config/network/dedicated-persistence-recovery.v1.json", "v16.10.5-persistence-m6-dedicated-recovery"],
	}
	var milestone_by_id := _index_by_id(manifest.get("accepted_milestones", []))
	_assert(milestone_by_id.size() == 6, "A3 must freeze exactly M1-M6")
	for milestone_id in expected:
		var pair: Array = expected[milestone_id]
		var milestone_manifest := _load_json(String(pair[0]))
		_assert(not milestone_manifest.is_empty(), "%s manifest missing" % milestone_id)
		_assert(String(milestone_manifest.get("checkpoint", "")) == String(pair[1]), "%s checkpoint mismatch" % milestone_id)
		_assert(String(milestone_manifest.get("status", "")) == "accepted", "%s manifest is not accepted" % milestone_id)
		_assert(String(milestone_by_id.get(milestone_id, {}).get("effective_status", "")) == "accepted", "%s effective status mismatch" % milestone_id)
	_assert(String(_load_json("res://config/network/graphical-multiplayer-acceptance.v1.json").get("delivery", "fix1")) == "fix1", "M5 fix1 acceptance evidence missing")
	var m6 := _load_json("res://config/network/dedicated-persistence-recovery.v1.json")
	_assert(String(m6.get("delivery", "")) == "fix1", "M6 fix1 delivery evidence missing")
	_assert(String(m6.get("acceptance_sha256", "")) == "7AF3317A3E2B9F24D452DECEC6A18D1AE0747A903F6C03A69DFFE0CC82B966BF", "M6 local acceptance hash mismatch")
	_assert(String(m6.get("verification_status", {}).get("independent_local_acceptance", "")) == "passed", "M6 independent acceptance not recorded")


func _test_source_freeze(manifest: Dictionary) -> void:
	var sources: Dictionary = {}
	var paths: Array[String] = [
		Auditor.PRODUCTION_SERVICE_PATH,
		"scripts/runtime/listen_host/playable_listen_host_authority.gd",
		"scripts/runtime/host_client/multiplayer_gameplay_authority.gd",
		"scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd",
		"scripts/runtime/networked_gameplay/m6/m6_dedicated_gameplay_authority_adapter.gd",
		"scripts/runtime/listen_host/client_runtime.gd",
		"scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd",
		"scripts/runtime/networked_gameplay/transports/graphical_game_client_runtime.gd",
	]
	for contract_value in manifest.get("wire_contract_family", []):
		if contract_value is Dictionary:
			paths.append(String(contract_value.get("path", "")))
	for path in paths:
		sources[path] = _read("res://%s" % path)
	var audit: Dictionary = Auditor.audit_sources(sources)
	_assert(bool(audit.get("success", false)), "A3 source audit failed: %s" % [audit.get("failures", [])])
	_assert(int(audit.get("details", {}).get("contracts", 0)) == 11, "A3 source audit contract count mismatch")
	_assert(int(audit.get("details", {}).get("authority_adapters", 0)) == 4, "A3 source audit adapter count mismatch")
	_assert(int(audit.get("details", {}).get("graphical_clients", 0)) == 3, "A3 source audit client count mismatch")
	var service_source := String(sources.get(Auditor.PRODUCTION_SERVICE_PATH, ""))
	_assert(service_source.contains("PROFILE_CANONICAL_PLAYABLE"), "Canonical playable profile missing")
	_assert(service_source.contains("PROFILE_MULTIPLAYER_CORE"), "Multiplayer core profile missing")
	_assert(service_source.contains("export_durable_state"), "M6 durable export missing from common service")
	_assert(service_source.contains("restore_durable_state"), "M6 durable restore missing from common service")
	_assert(not service_source.contains("NATS") and not service_source.contains("JetStream"), "Broker concern leaked into gameplay service")


func _test_topology_equivalence_and_recovery() -> void:
	var loopback = _new_service("LOOPBACK")
	var enet = _new_service("ENET")
	if loopback == null or enet == null:
		return
	_run_common_scenario(loopback)
	_run_common_scenario(enet)
	var loopback_snapshot: Dictionary = loopback.create_snapshot()
	var enet_snapshot: Dictionary = enet.create_snapshot()
	_assert(String(loopback_snapshot.get("checksum", "")) == String(enet_snapshot.get("checksum", "")), "Topology changed player checksum")
	_assert(Utils.canonical_json(loopback_snapshot) == Utils.canonical_json(enet_snapshot), "Topology changed canonical player state")
	var loopback_items: Dictionary = loopback.create_canonical_item_graph_snapshot()
	var enet_items: Dictionary = enet.create_canonical_item_graph_snapshot()
	_assert(String(loopback_items.get("checksum", "")) == String(enet_items.get("checksum", "")), "Topology changed Item Graph checksum")
	var durable: Dictionary = enet.export_durable_state()
	var replay_state: Dictionary = enet.export_replay_state()
	_assert(bool(enet.validate_durable_state(durable).get("success", false)), "A3 source service durable state invalid")
	_assert(bool(enet.validate_replay_state(replay_state).get("success", false)), "A3 source service replay state invalid")
	var recovered = _new_service("ENET")
	if recovered == null:
		return
	var restored: Dictionary = recovered.restore_durable_state(durable)
	_assert(bool(restored.get("success", false)), "A3 durable restore failed: %s" % [restored])
	var replay_restored: Dictionary = recovered.restore_replay_state(replay_state)
	_assert(bool(replay_restored.get("success", false)), "A3 replay restore failed: %s" % [replay_restored])
	_assert(String(recovered.export_durable_state().get("checksum", "")) == String(durable.get("checksum", "")), "A3 durable checksum did not round-trip")
	_assert(not bool(recovered.get_player("a").get("connected", true)), "Recovered A retained transient connection")
	_assert(not bool(recovered.get_player("b").get("connected", true)), "Recovered B retained transient connection")
	var checksum_before_replay := String(recovered.export_durable_state().get("checksum", ""))
	var replay: Dictionary = recovered.handle_canonical_item_command(
		"a", "transport-session/a3/a/1", 1,
		"operation/a3/a/hotbar/1", "inventory.assign_hotbar",
		{"item_id": "item/shared/ore/1", "slot_index": 1}
	)
	_assert(bool(replay.get("success", false)), "Committed item operation replay failed: %s" % [replay])
	_assert(bool(replay.get("details", {}).get("replay", false)), "Committed item replay marker missing")
	_assert(String(recovered.export_durable_state().get("checksum", "")) == checksum_before_replay, "Exact replay changed durable state")
	var rejoin_a: Dictionary = recovered.join("a", "transport-session/a3/a/3", "operation/a3/a/join/3")
	_assert(bool(rejoin_a.get("success", false)), "Recovered A rejoin failed")
	_assert(int(rejoin_a.get("details", {}).get("player", {}).get("ownership_epoch", 0)) == 3, "Recovered A ownership epoch did not advance")


func _new_service(topology: String):
	var service = Service.new()
	var setup: Dictionary = service.setup("simulation/a3/freeze", 6, 100, {
		"profile": Service.PROFILE_MULTIPLAYER_CORE,
		"topology_adapter": topology,
		"region_id": "region/a3/single-server",
	})
	_assert(bool(setup.get("success", false)), "%s service setup failed: %s" % [topology, setup])
	return service if bool(setup.get("success", false)) else null


func _run_common_scenario(service) -> void:
	_assert(_ok(service.join("a", "transport-session/a3/a/1", "operation/a3/a/join/1")), "A join")
	_assert(_ok(service.join("b", "transport-session/a3/b/1", "operation/a3/b/join/1")), "B join")
	_assert(_ok(service.move_player("a", "transport-session/a3/a/1", 1, 1, 2.0, 1.0, "operation/a3/a/move/1")), "A move")
	_assert(_ok(service.move_player("b", "transport-session/a3/b/1", 1, 1, -1.0, 2.0, "operation/a3/b/move/1")), "B move")
	_assert(_ok(service.set_player_presentation("a", "transport-session/a3/a/1", 1, 0.75, true, "operation/a3/a/presentation/1")), "A presentation")
	_assert(_ok(service.handle_canonical_item_command("a", "transport-session/a3/a/1", 1, "operation/a3/a/pickup/1", "item.pickup", {"item_id": "item/shared/ore/1"})), "A pickup")
	var contention: Dictionary = service.handle_canonical_item_command("b", "transport-session/a3/b/1", 1, "operation/a3/b/pickup/1", "item.pickup", {"item_id": "item/shared/ore/1"})
	_assert(String(contention.get("error_code", "")) == "ITEM_ALREADY_CLAIMED", "Contention rejection changed")
	_assert(_ok(service.handle_canonical_item_command("a", "transport-session/a3/a/1", 1, "operation/a3/a/hotbar/1", "inventory.assign_hotbar", {"item_id": "item/shared/ore/1", "slot_index": 1})), "A hotbar assignment")
	_assert(_ok(service.leave("a", "transport-session/a3/a/1", "operation/a3/a/leave/1")), "A leave")
	_assert(_ok(service.move_player("b", "transport-session/a3/b/1", 1, 2, 0.0, 1.0, "operation/a3/b/move/2")), "B continues after A leave")
	var rejoin: Dictionary = service.join("a", "transport-session/a3/a/2", "operation/a3/a/join/2")
	_assert(_ok(rejoin), "A reconnect")
	_assert(int(rejoin.get("details", {}).get("player", {}).get("ownership_epoch", 0)) == 2, "A reconnect epoch")


func _test_roadmaps_and_debt() -> void:
	var roadmap := _load_json(ROADMAP_PATH)
	var strategy := _load_json(STRATEGY_PATH)
	var a2 := _load_json(A2_PATH)
	_assert(String(roadmap.get("project_checkpoint", "")) == Auditor.CHECKPOINT, "Network roadmap current checkpoint mismatch")
	_assert(String(roadmap.get("current_implementation_stage", "")) == "M7_VALIDATION_OVER_ACCEPTED_A3", "Network roadmap current validation stage mismatch")
	_assert(String(roadmap.get("current_implementation_manifest", "")) == "config/network/single-server-multiplayer-architecture.v1.json", "Network roadmap A3 manifest link missing")
	var phases := _index_by_id(roadmap.get("phases", []))
	for milestone_id in Auditor.REQUIRED_MILESTONES:
		_assert(String(phases.get(milestone_id, {}).get("status", "")) == "accepted", "Network roadmap milestone not accepted: %s" % milestone_id)
	_assert(String(phases.get("A3", {}).get("status", "")) == "accepted", "Network roadmap A3 accepted status mismatch")
	_assert(String(phases.get("B1", {}).get("status", "")) == "ready_after_A3_acceptance", "B1 adapter stage is not unlocked after accepted A3")
	var milestones := _index_by_id(strategy.get("milestones", []))
	for milestone_id in Auditor.REQUIRED_MILESTONES:
		_assert(String(milestones.get(milestone_id, {}).get("status", "")) == "accepted", "Strategy milestone not accepted: %s" % milestone_id)
	_assert(String(milestones.get("A3", {}).get("status", "")) == "accepted", "Strategy A3 accepted status mismatch")
	_assert("PlayerPresentationCommand" in strategy.get("shared_contracts", []), "Frozen shared contract family omits presentation command")
	var debts := _index_by_id(a2.get("known_debt", []))
	for debt_id in ["A2-D01", "A2-D02", "A2-D03", "A2-D04"]:
		_assert(String(debts.get(debt_id, {}).get("status", "")) == "closed", "Architecture debt not closed before A3: %s" % debt_id)
	_assert(String(debts.get("A2-D05", {}).get("status", "")) == "open", "A2-D05 authentication debt must remain explicit")
	var assessment: Dictionary = a2.get("implementation_assessment", {})
	_assert(bool(assessment.get("dedicated_server_restart_recovery_proven", false)), "M6 recovery proof missing from A2 assessment")
	_assert(bool(assessment.get("single_server_multiplayer_architecture_candidate", false)), "A3 candidate link missing from A2 assessment")
	_assert(not bool(assessment.get("multi_authority_work_allowed", true)), "A2 gate incorrectly allows multi-authority")


func _test_documents_and_runners() -> void:
	for path in [
		"res://docs/architecture/A3_SINGLE_SERVER_MULTIPLAYER_ARCHITECTURE_RU.md",
		"res://docs/architecture/audits/2026-07-31_V16_10_6_SINGLE_SERVER_MULTIPLAYER_AUDIT_RU.md",
		"res://docs/checkpoints/2026-07-31_V16_10_6_ARCHITECTURE_A3_SINGLE_SERVER_MULTIPLAYER_RU.md",
		"res://docs/architecture/adr/ADR-016-single-server-multiplayer-architecture-freeze.md",
	]:
		_assert(FileAccess.file_exists(path), "A3 document missing: %s" % path)
	var architecture := _read("res://docs/architecture/A3_SINGLE_SERVER_MULTIPLAYER_ARCHITECTURE_RU.md")
	_assert(architecture.contains("SINGLE_SERVER_MULTIPLAYER_FROZEN"), "A3 decision missing from architecture document")
	_assert(architecture.contains("NetworkedGameplayService"), "Production service missing from architecture document")
	_assert(architecture.contains("server-to-server"), "B1 boundary missing from architecture document")
	for runner_path in [
		"res://RUN_A3_SINGLE_SERVER_MULTIPLAYER_TESTS.ps1",
		"res://RUN_A3_SINGLE_SERVER_MULTIPLAYER_TESTS.sh",
		"res://RUN_NETWORK_CONTRACT_TESTS.ps1",
		"res://RUN_WORLD_REGRESSION_TESTS.ps1",
	]:
		var runner := _read(runner_path)
		_assert(not runner.is_empty(), "A3 runner missing: %s" % runner_path)
		_assert(runner.contains("res://tests/runtime/test_a3_single_server_multiplayer_architecture.gd"), "Runner omits A3 contract: %s" % runner_path)
		_assert(runner.contains(Auditor.CHECKPOINT), "Runner checkpoint is stale: %s" % runner_path)
	_assert(FileAccess.file_exists("res://config/network/single-server-multiplayer-architecture.v1.json"), "A3 implementation manifest missing")


func _index_by_id(values: Array) -> Dictionary:
	var result: Dictionary = {}
	for value in values:
		if value is Dictionary:
			result[String(value.get("id", ""))] = value
	return result


func _load_json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(_read(path))
	return parsed if parsed is Dictionary else {}


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _ok(value: Dictionary) -> bool:
	return bool(value.get("success", false))


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("A3 single-server multiplayer architecture: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("A3 single-server multiplayer architecture: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
