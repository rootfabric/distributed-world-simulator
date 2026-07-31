extends SceneTree

const STRATEGY_PATH := "res://config/network/single-server-multiplayer-roadmap.v1.json"
const ROADMAP_PATH := "res://config/network/network-roadmap.v1.json"
const A2_PATH := "res://config/network/networked-gameplay-architecture.v1.json"

var failures: Array[String] = []
var assertions := 0

func _init() -> void:
	var strategy := _load_json(STRATEGY_PATH)
	var roadmap := _load_json(ROADMAP_PATH)
	var a2 := _load_json(A2_PATH)
	_test_identity(strategy)
	_test_sequence_and_milestones(strategy)
	_test_contracts_and_transport_policy(strategy)
	_test_a2_alignment(strategy, a2)
	_test_network_roadmap_alignment(strategy, roadmap)
	_test_documentation_and_runners()
	_finish()

func _test_identity(strategy: Dictionary) -> void:
	_assert(String(strategy.get("schema", "")) == "planet_simulator.single_server_multiplayer_roadmap.v1", "Strategy schema mismatch")
	_assert(int(strategy.get("document_revision", 0)) == 9, "Strategy revision mismatch")
	_assert(String(strategy.get("checkpoint", "")) == "v16.9.5-roadmap-single-server-multiplayer-first", "Strategy checkpoint mismatch")
	_assert(String(strategy.get("build_id", "")) == "post-a2-single-server-multiplayer-first", "Strategy build ID mismatch")
	_assert(String(strategy.get("status", "")) == "accepted", "Roadmap checkpoint must be accepted")
	_assert(String(strategy.get("decision", "")) == "FULL_SINGLE_SERVER_MULTIPLAYER_FIRST", "Strategic decision mismatch")
	_assert(String(strategy.get("base_checkpoint", "")) == "v16.9.4-architecture-a2-networked-gameplay", "A2 base mismatch")
	_assert(String(strategy.get("historical_track_note", "")).contains("historical M0"), "M0/M1 track distinction missing")

func _test_sequence_and_milestones(strategy: Dictionary) -> void:
	var sequence: Array = strategy.get("priority_sequence", [])
	_assert(sequence == ["M1", "M2", "M3", "M4", "M5", "M6", "A3", "B1", "B2", "N3", "N4", "N5", "N6"], "Priority sequence changed")
	var by_id: Dictionary = {}
	for value in strategy.get("milestones", []):
		if value is Dictionary:
			by_id[String(value.get("id", ""))] = value
	for stage in sequence:
		_assert(by_id.has(stage), "Milestone missing: %s" % stage)
	_assert(String(by_id.get("M1", {}).get("status", "")) == "accepted", "M1 must be accepted")
	_assert(String(by_id.get("M2", {}).get("status", "")) == "accepted", "M2 must be accepted")
	_assert(String(by_id.get("M3", {}).get("status", "")) == "accepted", "M3 must be accepted")
	_assert(String(by_id.get("M4", {}).get("status", "")) == "accepted", "M4 must be accepted")
	_assert(String(by_id.get("M5", {}).get("status", "")) == "accepted", "M5 must be accepted")
	_assert(by_id.get("M1", {}).get("closes", []) == ["A2-D01", "A2-D02"], "M1 debt closure mismatch")
	_assert(by_id.get("M2", {}).get("depends_on", []) == ["M1"], "M2 dependency mismatch")
	_assert(by_id.get("M3", {}).get("depends_on", []) == ["M2"], "M3 dependency mismatch")
	_assert("M0" in by_id.get("M4", {}).get("depends_on", []), "M4 must use accepted M0 transactions")
	_assert("N2" in by_id.get("M5", {}).get("depends_on", []), "M5 must use N2 process harness")
	_assert(by_id.get("M6", {}).get("closes", []) == ["A2-D04"], "M6 debt closure mismatch")
	_assert(String(by_id.get("M6", {}).get("status", "")) == "accepted", "M6 accepted roadmap status mismatch")
	_assert(String(by_id.get("A3", {}).get("status", "")) == "accepted", "A3 accepted roadmap status mismatch")
	_assert(by_id.get("A3", {}).get("depends_on", []) == ["M6"], "A3 dependency mismatch")
	_assert(String(by_id.get("M4", {}).get("status", "")) == "accepted", "M4 roadmap status mismatch")
	_assert(String(by_id.get("M5", {}).get("status", "")) == "accepted", "M5 accepted roadmap status mismatch")
	_assert(String(by_id.get("B1", {}).get("status", "")) == "ready_after_A3_acceptance", "B1 must be unlocked only after A3 acceptance")
	_assert("A3" in by_id.get("B1", {}).get("depends_on", []), "B1 must depend on A3")
	_assert("B2" in by_id.get("N3", {}).get("depends_on", []), "N3 must wait for B2")

func _test_contracts_and_transport_policy(strategy: Dictionary) -> void:
	for contract in ["PlayerJoinCommand", "PlayerLeaveCommand", "PlayerInputCommand", "PlayerOwnershipSnapshot", "PlayerStateSnapshot", "PlayerStateDelta", "ItemCommand", "ItemGraphSnapshot", "ItemGraphDelta", "CommandResult"]:
		_assert(contract in strategy.get("shared_contracts", []), "Shared contract missing: %s" % contract)
	for requirement in ["versioned", "json_safe", "exact_field", "checksum_bound", "scene_tree_independent", "node_independent", "authority_implementation_independent", "authority_epoch_fenced", "ownership_epoch_fenced", "revision_fenced"]:
		_assert(requirement in strategy.get("contract_requirements", []), "Contract requirement missing: %s" % requirement)
	var transport: Dictionary = strategy.get("transport_policy", {})
	_assert(String(transport.get("graphical_client_realtime", "")) == "ENet", "Graphical realtime transport must remain ENet")
	_assert(String(transport.get("server_to_server_after_A3", "")).contains("NATS Core"), "NATS server-to-server role missing")
	_assert(String(transport.get("forbidden", "")).contains("must not replace ENet"), "NATS gameplay shortcut is not forbidden")
	_assert(strategy.get("production_blocks_before_A3", []).size() == 6, "Production block list changed")
	_assert(String(strategy.get("multi_server_entry_criterion", "")).contains("two reproducible graphical clients"), "Multi-server entry criterion missing")

func _test_a2_alignment(strategy: Dictionary, a2: Dictionary) -> void:
	_assert(String(a2.get("status", "")) == "accepted", "A2 must be accepted")
	_assert(int(a2.get("document_revision", 0)) == 8, "A2 manifest revision mismatch")
	_assert(String(a2.get("post_a2_strategy_checkpoint", "")) == String(strategy.get("checkpoint", "")), "A2 strategy checkpoint link mismatch")
	_assert(String(a2.get("post_a2_strategy_manifest", "")) == "config/network/single-server-multiplayer-roadmap.v1.json", "A2 strategy manifest link missing")
	var mapping: Dictionary = strategy.get("a2_debt_closure", {})
	_assert(String(mapping.get("A2-D01", "")) == "M1", "A2-D01 mapping mismatch")
	_assert(String(mapping.get("A2-D02", "")) == "M1", "A2-D02 mapping mismatch")
	_assert(String(mapping.get("A2-D03", "")) == "M3+M4+M5", "A2-D03 mapping mismatch")
	_assert(String(mapping.get("A2-D04", "")) == "M6", "A2-D04 mapping mismatch")
	_assert(String(a2.get("b1_constraints", {}).get("priority", "")) == "deferred_until_A3_acceptance", "A2 B1 priority mismatch")
	_assert(not bool(a2.get("implementation_assessment", {}).get("multi_authority_work_allowed", true)), "A2 must still block multi-authority work")

func _test_network_roadmap_alignment(strategy: Dictionary, roadmap: Dictionary) -> void:
	_assert(int(roadmap.get("document_revision", 0)) == 28, "Network roadmap revision mismatch")
	_assert(String(roadmap.get("project_checkpoint", "")) == "v16.10.6-architecture-a3-single-server-multiplayer", "Network roadmap checkpoint mismatch")
	_assert(String(roadmap.get("strategy_decision", "")) == "FULL_SINGLE_SERVER_MULTIPLAYER_FIRST", "Network roadmap strategy mismatch")
	_assert(roadmap.get("approved_sequence_after_a2", []) == strategy.get("priority_sequence", []), "Network roadmap sequence mismatch")
	_assert(String(roadmap.get("current_gate", "")).begins_with("M7"), "Network roadmap current gate must be M7 validation")
	var by_id: Dictionary = {}
	for value in roadmap.get("phases", []):
		if value is Dictionary:
			by_id[String(value.get("id", ""))] = value
	_assert(String(by_id.get("A2", {}).get("status", "")) == "accepted", "A2 roadmap status mismatch")
	_assert(String(by_id.get("M1", {}).get("status", "")) == "accepted", "M1 roadmap status mismatch")
	_assert(String(by_id.get("M2", {}).get("status", "")) == "accepted", "M2 accepted roadmap status mismatch")
	_assert(String(by_id.get("M3", {}).get("status", "")) == "accepted", "M3 roadmap status mismatch")
	_assert(String(by_id.get("M4", {}).get("status", "")) == "accepted", "M4 roadmap status mismatch")
	_assert(String(by_id.get("M5", {}).get("status", "")) == "accepted", "M5 accepted roadmap status mismatch")
	_assert(String(by_id.get("M6", {}).get("status", "")) == "accepted", "M6 network roadmap status mismatch")
	_assert(String(by_id.get("A3", {}).get("status", "")) == "accepted", "A3 network roadmap status mismatch")
	_assert(String(by_id.get("B1", {}).get("status", "")) == "ready_after_A3_acceptance", "B1 roadmap status mismatch")
	_assert(String(by_id.get("N3", {}).get("status", "")) == "blocked_until_A3_B2", "N3 roadmap status mismatch")

func _test_documentation_and_runners() -> void:
	var docs := [
		"res://docs/plans/SINGLE_SERVER_MULTIPLAYER_ROADMAP_RU.md",
		"res://docs/checkpoints/2026-07-30_POST_A2_SINGLE_SERVER_MULTIPLAYER_ROADMAP_RU.md",
		"res://docs/architecture/adr/ADR-012-single-server-multiplayer-first.md",
		"res://docs/architecture/M6_DEDICATED_PERSISTENCE_RECOVERY_RU.md",
		"res://docs/checkpoints/2026-07-31_V16_10_5_PERSISTENCE_M6_DEDICATED_RECOVERY_RU.md",
	]
	for path in docs:
		_assert(FileAccess.file_exists(path), "Post-A2 roadmap document missing: %s" % path)
	var plan := _read(docs[0])
	_assert(plan.contains("FULL SINGLE-SERVER MULTIPLAYER FIRST"), "Strategy title missing")
	_assert(plan.contains("M1 → M2 → M3 → M4 → M5 → M6 → A3"), "Plan sequence missing")
	_assert(plan.contains("NATS не используется для обычного graphical realtime traffic"), "NATS/ENet boundary missing")
	for runner_path in ["res://RUN_NETWORK_CONTRACT_TESTS.ps1", "res://RUN_WORLD_REGRESSION_TESTS.ps1"]:
		var runner := _read(runner_path)
		_assert(runner.contains("res://tests/runtime/test_post_a2_single_server_multiplayer_roadmap.gd"), "Full runner missing roadmap contract test")
		_assert(runner.contains("res://tests/runtime/test_m1_networked_gameplay_contracts.gd"), "Full runner missing M1 wire contract test")
		_assert(runner.contains("res://tests/runtime/test_m1_unified_networked_gameplay_service.gd"), "Full runner missing M1 service test")
		_assert(runner.contains("res://tests/runtime/test_m2_graphical_client_contracts.gd"), "Full runner missing M2 graphical contract test")
		_assert(runner.contains("res://tests/runtime/test_m2_dedicated_graphical_processes.gd"), "Full runner missing M2 graphical process test")
		_assert(runner.contains("res://tests/runtime/test_m3_graphical_multiplayer_contracts.gd"), "Full runner missing M3 graphical contract test")
		_assert(runner.contains("res://tests/runtime/test_m3_graphical_multiplayer_processes.gd"), "Full runner missing M3 graphical process test")
		_assert(runner.contains("res://tests/runtime/test_m4_canonical_shared_gameplay_contracts.gd"), "Full runner missing M4 contract test")
		_assert(runner.contains("res://tests/runtime/test_m4_graphical_shared_gameplay_processes.gd"), "Full runner missing M4 process test")
		_assert(runner.contains("res://tests/runtime/test_m5_graphical_acceptance_preparation.gd"), "Full runner missing pre-M5 preparation test")
		_assert(runner.contains("res://tests/runtime/test_m5_graphical_acceptance_contracts.gd"), "Full runner missing M5 acceptance contracts")
		_assert(runner.contains("res://tests/runtime/test_m5_graphical_multiplayer_acceptance.gd"), "Full runner missing M5 process acceptance")
		_assert(runner.contains("res://tests/runtime/test_m6_dedicated_recovery_contracts.gd"), "Full runner missing M6 recovery contracts")
		_assert(runner.contains("res://tests/runtime/test_m6_dedicated_recovery_processes.gd"), "Full runner missing M6 recovery process test")
		_assert(runner.contains("res://tests/runtime/test_a3_single_server_multiplayer_architecture.gd"), "Full runner missing A3 architecture test")
		_assert(runner.contains("v16.10.6-architecture-a3-single-server-multiplayer"), "Full runner checkpoint is stale")

	for focused_runner_path in ["res://RUN_M6_DEDICATED_RECOVERY_TESTS.ps1", "res://RUN_M6_DEDICATED_RECOVERY_TESTS.sh"]:
		var focused_runner := _read(focused_runner_path)
		_assert(not focused_runner.is_empty(), "M6 focused runner missing: %s" % focused_runner_path)
		_assert(focused_runner.contains("res://tests/runtime/test_m6_dedicated_recovery_contracts.gd"), "M6 focused runner missing contract test")
		_assert(focused_runner.contains("res://tests/runtime/test_m6_dedicated_recovery_processes.gd"), "M6 focused runner missing process test")
	_assert(FileAccess.file_exists("res://config/network/dedicated-persistence-recovery.v1.json"), "M6 implementation manifest missing")

func _load_json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(_read(path))
	return parsed if parsed is Dictionary else {}

func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""

func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("Post-A2 single-server multiplayer roadmap: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Post-A2 single-server multiplayer roadmap: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
