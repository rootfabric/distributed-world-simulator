extends SceneTree

const MANIFEST_PATH := "res://config/network/graphical-multiplayer-acceptance.v1.json"
const PREPARATION_PATH := "res://config/network/m5-graphical-acceptance-preparation.v1.json"
const ROADMAP_PATH := "res://config/network/network-roadmap.v1.json"
const SINGLE_SERVER_PATH := "res://config/network/single-server-multiplayer-roadmap.v1.json"
const A2_PATH := "res://config/network/networked-gameplay-architecture.v1.json"
const M6_MANIFEST_PATH := "config/network/dedicated-persistence-recovery.v1.json"

var failures: Array[String] = []
var assertions := 0

func _init() -> void:
	var manifest := _load_json(MANIFEST_PATH)
	var preparation := _load_json(PREPARATION_PATH)
	var roadmap := _load_json(ROADMAP_PATH)
	var single_server := _load_json(SINGLE_SERVER_PATH)
	var a2 := _load_json(A2_PATH)
	_test_identity(manifest)
	_test_topology_and_path(manifest)
	_test_acceptance(manifest)
	_test_roadmaps(manifest, preparation, roadmap, single_server, a2)
	_test_source_and_runners(manifest)
	_finish()

func _test_identity(manifest: Dictionary) -> void:
	_assert(String(manifest.get("schema", "")) == "planet_simulator.graphical_multiplayer_acceptance.v1", "M5 schema mismatch")
	_assert(int(manifest.get("document_revision", 0)) == 2, "M5 document revision mismatch")
	_assert(String(manifest.get("checkpoint", "")) == "v16.10.4-testing-m5-graphical-multiplayer-acceptance", "M5 checkpoint mismatch")
	_assert(String(manifest.get("build_id", "")) == "m5-ui-driven-graphical-multiplayer-acceptance", "M5 build ID mismatch")
	_assert(String(manifest.get("base_checkpoint", "")) == "v16.10.3-pre-m5-graphical-acceptance-preparation", "M5 preparation base mismatch")
	_assert(String(manifest.get("runtime_base_checkpoint", "")) == "v16.10.3-domain-m4-canonical-shared-gameplay", "M5 runtime base mismatch")
	_assert(String(manifest.get("status", "")) == "accepted", "M5 accepted status mismatch")
	_assert(String(manifest.get("decision", "")) == "UI_DRIVEN_GRAPHICAL_MULTIPLAYER_ACCEPTANCE", "M5 decision mismatch")
	_assert(manifest.get("closes", []) == ["A2-D03"], "M5 debt closure mismatch")
	_assert(String(manifest.get("next_stage", "")) == "M6", "M5 next stage mismatch")

func _test_topology_and_path(manifest: Dictionary) -> void:
	var topology: Dictionary = manifest.get("topology", {})
	_assert(String(topology.get("server", "")).contains("headless dedicated"), "M5 dedicated topology missing")
	_assert(Array(topology.get("clients", [])).size() == 3, "M5 graphical process phases mismatch")
	_assert(String(topology.get("transport", "")).contains("ENet"), "M5 transport mismatch")
	_assert(not bool(topology.get("headless_clients_allowed", true)), "M5 must reject headless-only clients")
	var path: Array = manifest.get("canonical_path", [])
	for step in ["inventory_widget", "M5InventoryUiBridge", "M4ItemCommandAdapter", "ITEM_COMMAND", "dedicated NetworkedGameplayService", "canonical Item Graph mutation", "M4ItemGraphUiProjection"]:
		_assert(step in path, "M5 canonical path missing: %s" % step)
	var invariants: Dictionary = manifest.get("ui_invariants", {})
	_assert(int(invariants.get("authority_references", -1)) == 0, "M5 UI authority reference invariant")
	_assert(int(invariants.get("domain_references", -1)) == 0, "M5 UI domain reference invariant")
	_assert(not bool(invariants.get("canonical_mutation_from_ui", true)), "M5 UI local mutation must be forbidden")
	_assert(bool(invariants.get("server_confirmation_required", false)), "M5 server confirmation invariant")
	_assert(String(invariants.get("cursor_drag_pending_state", "")).contains("transient"), "M5 transient UI state invariant")

func _test_acceptance(manifest: Dictionary) -> void:
	var operations: Array = manifest.get("accepted_operations", [])
	for operation in ["movement via InputMap", "hotbar assignment", "container open close", "mount", "detach", "drop", "repick", "contention", "disconnect", "reconnect"]:
		_assert(operation in operations, "M5 operation missing: %s" % operation)
	var acceptance: Array = manifest.get("acceptance", [])
	_assert(acceptance.size() >= 9, "M5 acceptance list incomplete")
	_assert(_contains_fragment(acceptance, "exactly one UI client wins"), "M5 contention acceptance missing")
	_assert(_contains_fragment(acceptance, "ownership epoch 2"), "M5 reconnect acceptance missing")
	_assert(_contains_fragment(acceptance, "identical player and Item Graph checksums"), "M5 convergence acceptance missing")
	_assert(_contains_fragment(acceptance, "ObjectDB"), "M5 clean shutdown acceptance missing")

func _test_roadmaps(manifest: Dictionary, preparation: Dictionary, roadmap: Dictionary, single_server: Dictionary, a2: Dictionary) -> void:
	_assert(String(preparation.get("status", "")) == "completed", "Pre-M5 preparation must be completed")
	_assert(String(preparation.get("completed_by_checkpoint", "")) == String(manifest.get("checkpoint", "")), "Pre-M5 completion link mismatch")
	_assert(int(roadmap.get("document_revision", 0)) == 27, "Network roadmap revision mismatch")
	_assert(String(roadmap.get("project_checkpoint", "")) == "v16.10.6-architecture-a3-single-server-multiplayer", "Network roadmap A3 checkpoint mismatch")
	_assert(String(roadmap.get("current_gate", "")).begins_with("A3"), "Network roadmap next gate must be A3")
	_assert(String(roadmap.get("current_implementation_manifest", "")) == "config/network/single-server-multiplayer-architecture.v1.json", "Network roadmap A3 manifest mismatch")
	_assert(int(single_server.get("document_revision", 0)) == 8, "Single-server roadmap revision mismatch")
	_assert(String(single_server.get("current_stage", "")) == "A3", "Single-server current A3 stage mismatch")
	_assert(String(single_server.get("current_checkpoint", "")) == "v16.10.6-architecture-a3-single-server-multiplayer", "Single-server A3 checkpoint mismatch")
	for source in [roadmap, single_server]:
		var phases: Array = source.get("phases", source.get("milestones", []))
		var by_id: Dictionary = {}
		for value in phases:
			if value is Dictionary:
				by_id[String(value.get("id", ""))] = value
		_assert(String(by_id.get("M5", {}).get("status", "")) == "accepted", "M5 roadmap accepted status mismatch")
		_assert(String(by_id.get("M6", {}).get("status", "")) == "accepted", "M6 roadmap accepted status mismatch")
		_assert(String(by_id.get("A3", {}).get("status", "")) == "candidate", "A3 roadmap candidate status mismatch")
	_assert(int(a2.get("document_revision", 0)) == 8, "A2 revision mismatch for A3 candidate")
	_assert(bool(a2.get("implementation_assessment", {}).get("ui_driven_graphical_acceptance_proven", false)), "A2 M5 acceptance evidence missing")
	var d03: Dictionary = {}
	for value in a2.get("known_debt", []):
		if value is Dictionary and String(value.get("id", "")) == "A2-D03":
			d03 = value
	_assert(String(d03.get("status", "")) == "closed", "A2-D03 must be closed by M5")
	_assert(String(d03.get("closed_by", "")) == "M5", "A2-D03 closure stage mismatch")

func _test_source_and_runners(manifest: Dictionary) -> void:
	var evidence: Dictionary = manifest.get("evidence", {})
	for key in ["contracts", "preparation_contracts", "graphical_process", "focused_runner_windows", "focused_runner_linux"]:
		var path := String(evidence.get(key, ""))
		_assert(not path.is_empty(), "M5 evidence path missing: %s" % key)
		_assert(FileAccess.file_exists("res://%s" % path), "M5 evidence file missing: %s" % path)
	var app := _read("res://scripts/app/simulator_app.gd")
	var m3_client := _read("res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd")
	_assert(m3_client.contains("Support.transport_bound_operation_id(_logical_player_id, \"join\", _transport_session_id)"), "M5 reconnect JOIN is not bound to transport session identity")
	_assert(not m3_client.contains("operation/m3/%s/join/%d"), "M5 reconnect JOIN still depends on process-local ticks")
	_assert(app.contains("v16.10.6-architecture-a3-single-server-multiplayer"), "Simulator A3 checkpoint is stale")
	_assert(app.contains("a3-single-server-multiplayer-architecture-freeze"), "Simulator A3 build ID is stale")
	for runner_path in ["res://RUN_NETWORK_CONTRACT_TESTS.ps1", "res://RUN_WORLD_REGRESSION_TESTS.ps1"]:
		var runner := _read(runner_path)
		_assert(runner.contains("res://tests/runtime/test_m5_graphical_acceptance_contracts.gd"), "Full runner missing M5 contracts")
		_assert(runner.contains("res://tests/runtime/test_m5_graphical_multiplayer_acceptance.gd"), "Full runner missing M5 process acceptance")
		_assert(runner.contains("v16.10.6-architecture-a3-single-server-multiplayer") and runner.contains("v16.10.5-persistence-m6-dedicated-recovery"), "Full runner must identify A3 checkpoint over accepted M6 base")

func _contains_fragment(values: Array, fragment: String) -> bool:
	for value in values:
		if String(value).contains(fragment):
			return true
	return false

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
		print("M5 graphical acceptance contracts: %d assertions, 0 failures" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("M5 graphical acceptance contracts: %d assertions, %d failures" % [assertions, failures.size()])
	quit(1)
