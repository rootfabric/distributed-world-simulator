extends SceneTree

const RuntimeRoleScript = preload("res://scripts/runtime/runtime_role.gd")
const RuntimeScript = preload("res://scripts/runtime/listen_host/listen_host_runtime.gd")
const ReplicaStoreScript = preload("res://scripts/runtime/listen_host/client_replica_store.gd")
const ClientGatewayScript = preload("res://scripts/runtime/listen_host/client_command_gateway.gd")
const AuthorityAdapterScript = preload("res://scripts/runtime/listen_host/listen_host_authority_gateway_adapter.gd")
const SnapshotScript = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	_test_runtime_role()
	_test_runner_contracts()
	_test_invalid_components()
	_test_vertical_scenario()
	_finish()


func _test_runtime_role() -> void:
	_assert(RuntimeRoleScript.is_supported(RuntimeRoleScript.LISTEN_HOST), "listen-host role is not supported")
	_assert(RuntimeRoleScript.presentation_enabled(RuntimeRoleScript.LISTEN_HOST), "listen-host must enable presentation")
	_assert(RuntimeRoleScript.accepts_local_input(RuntimeRoleScript.LISTEN_HOST), "listen-host must accept local input")
	_assert(RuntimeRoleScript.is_authoritative(RuntimeRoleScript.LISTEN_HOST), "listen-host must embed authority")
	var descriptor: Dictionary = RuntimeRoleScript.describe(RuntimeRoleScript.LISTEN_HOST)
	_assert(bool(descriptor.get("client_replica_enabled", false)), "listen-host must enable client replica")
	_assert(bool(descriptor.get("embedded_authority", false)), "listen-host descriptor lost embedded authority")
	_assert(not bool(descriptor.get("direct_client_domain_access_allowed", true)), "listen-host allowed direct client domain access")
	var offline: Dictionary = RuntimeRoleScript.describe(RuntimeRoleScript.OFFLINE)
	_assert(bool(offline.get("direct_client_domain_access_allowed", false)), "offline diagnostics role unexpectedly lost direct access")


func _test_runner_contracts() -> void:
	var runner_text: String = FileAccess.get_file_as_string(
		"res://RUN_H0_LISTEN_HOST_TESTS.ps1"
	)
	_assert(not runner_text.is_empty(), "H0 PowerShell runner is missing")
	_assert(runner_text.contains("function Write-JsonFileAtomically"), "H0 runner does not publish summary atomically")
	_assert(runner_text.contains("$Stream.Flush($true)"), "H0 runner does not force summary flush")
	_assert(runner_text.contains("[IO.File]::Replace"), "H0 runner cannot atomically replace existing summary")
	_assert(runner_text.contains("[IO.File]::Move"), "H0 runner cannot atomically publish first summary")
	_assert(runner_text.contains("PSNativeCommandUseErrorActionPreference"), "H0 runner is not stderr-safe on PowerShell")
	_assert(not runner_text.contains("Set-Content -Path $ReportPath"), "H0 runner writes final summary directly")


func _test_invalid_components() -> void:
	var replica = ReplicaStoreScript.new()
	var before_setup: Dictionary = replica.get_snapshot("entity/missing")
	_assert(not bool(before_setup.get("success", true)), "Unconfigured replica store returned a snapshot")
	_assert(String(before_setup.get("error_code", "")) == "REPLICA_STORE_NOT_CONFIGURED", "Unexpected unconfigured replica error")
	_assert(bool(replica.setup().get("success", false)), "Replica store setup failed")
	_assert(replica.get_snapshot_count() == 0, "New replica store is not empty")
	var invalid_snapshot: Dictionary = replica.accept_snapshot({"schema": "invalid"})
	_assert(not bool(invalid_snapshot.get("success", true)), "Invalid snapshot was accepted")
	_assert(replica.get_snapshot_count() == 0, "Invalid snapshot mutated replica store")
	var invalid_delta: Dictionary = replica.accept_delta({"schema": "invalid"})
	_assert(not bool(invalid_delta.get("success", true)), "Invalid delta was accepted")
	var replica_report: Dictionary = replica.get_report()
	_assert(int(replica_report.get("direct_authority_references", -1)) == 0, "Replica store reports authority reference")
	_assert(int(replica_report.get("direct_domain_references", -1)) == 0, "Replica store reports domain reference")

	var gateway = ClientGatewayScript.new()
	_assert(not bool(gateway.setup(null, replica, "session/test").get("success", true)), "Client gateway accepted null transport")
	_assert(not bool(gateway.setup(RefCounted.new(), replica, "session/test").get("success", true)), "Client gateway accepted transport without send")
	var adapter = AuthorityAdapterScript.new()
	_assert(not bool(adapter.setup(null).get("success", true)), "Authority adapter accepted null authority")
	_assert(not bool(adapter.setup(RefCounted.new()).get("success", true)), "Authority adapter accepted incomplete authority")


func _test_vertical_scenario() -> void:
	var runtime = RuntimeScript.new()
	var setup_result: Dictionary = runtime.setup({
		"authority_owner_id": "sim-n1",
		"authority_epoch": 5,
		"server_tick": 500,
		"session_id": "session/h0/listen-host/test",
	})
	_assert(bool(setup_result.get("success", false)), "Listen-host setup failed: %s" % setup_result)
	_assert(String(setup_result.get("details", {}).get("state", "")) == "READY", "Listen-host did not become READY")
	_assert(not bool(runtime.setup().get("success", true)), "Listen-host allowed repeated setup")

	var initial_client: Dictionary = runtime.get_client_snapshot()
	var initial_authority: Dictionary = runtime.get_authority_snapshot_for_diagnostics()
	_assert(bool(SnapshotScript.validate(initial_client).get("success", false)), "Initial client replica is invalid")
	_assert(bool(SnapshotScript.validate(initial_authority).get("success", false)), "Initial authority snapshot is invalid")
	_assert(String(initial_client.get("checksum", "")) == String(initial_authority.get("checksum", "")), "Initial client/server checksum differs")
	initial_client["domain_components"]["test_alias"] = {"value": 1}
	initial_authority["domain_components"]["test_alias"] = {"value": 2}
	_assert(not runtime.get_client_snapshot().get("domain_components", {}).has("test_alias"), "Client snapshot accessor leaked mutable reference")
	_assert(not runtime.get_authority_snapshot_for_diagnostics().get("domain_components", {}).has("test_alias"), "Authority snapshot accessor leaked mutable reference")

	var scenario: Dictionary = runtime.run_vertical_scenario()
	_assert(bool(scenario.get("success", false)), "Listen-host vertical scenario failed: %s" % scenario)
	var report: Dictionary = runtime.get_report()
	_assert(bool(report.get("passed", false)), "Listen-host report is not passed")
	_assert(String(report.get("state", "")) == "COMPLETE", "Listen-host did not complete")
	_assert(String(report.get("failure_code", "x")).is_empty(), "Listen-host retained failure code")
	_assert(String(report.get("transport_kind", "")) == "LOOPBACK", "Listen-host transport is not loopback")
	_assert(not bool(report.get("direct_client_domain_access", true)), "Listen-host reports direct domain access")
	_assert(bool(report.get("alias_isolation_verified", false)), "Client/server alias isolation was not verified")
	_assert(bool(report.get("initial_snapshot_delivered", false)), "Initial snapshot was not delivered")
	_assert(bool(report.get("primary_delta_delivered", false)), "Primary delta was not delivered")
	_assert(bool(report.get("replay_delta_fenced", false)), "Duplicate delta was not fenced")
	_assert(bool(report.get("stale_revision_rejected", false)), "Stale command was not rejected")
	_assert(int(report.get("boundary_round_trips", -1)) == 6, "Unexpected boundary round-trip count")
	_assert(String(report.get("client_snapshot_checksum", "")) == String(report.get("authority_snapshot_checksum", "")), "Final client/server checksum differs")
	_assert(String(report.get("initial_snapshot_checksum", "")) != String(report.get("client_snapshot_checksum", "")), "Scenario did not mutate snapshot")
	_assert(int(report.get("client_revision", -1)) == 13, "Client revision is not 13")
	_assert(int(report.get("authority_revision", -1)) == 13, "Authority revision is not 13")
	_assert(int(report.get("server_tick", -1)) == 501, "Server tick is not 501")
	_assert(int(report.get("authority_mutation_count", -1)) == 1, "Authority mutation count is not one")
	_assert(int(report.get("authority_handler_invocation_count", -1)) == 2, "Authority handler invocation count is not two")
	_assert(int(report.get("operation_ledger_count", -1)) == 1, "Operation ledger count is not one")
	var replica_report: Dictionary = report.get("replica_store", {})
	_assert(int(replica_report.get("snapshot_count", -1)) == 1, "Replica store snapshot count is not one")
	_assert(int(replica_report.get("snapshot_deliveries", -1)) == 1, "Initial snapshot delivery count is not one")
	_assert(int(replica_report.get("delta_deliveries", -1)) == 2, "Delta delivery count is not two")
	_assert(int(replica_report.get("delta_replays", -1)) == 1, "Delta replay count is not one")
	_assert(int(replica_report.get("mutation_count", -1)) == 1, "Replica mutation count is not one")
	_assert(int(replica_report.get("direct_authority_references", -1)) == 0, "Replica store gained authority reference")
	_assert(int(replica_report.get("direct_domain_references", -1)) == 0, "Replica store gained domain reference")
	var gateway_report: Dictionary = report.get("client_gateway", {})
	_assert(int(gateway_report.get("commands_sent", -1)) == 3, "Client command count is not three")
	_assert(int(gateway_report.get("results_received", -1)) == 3, "Client result count is not three")
	_assert(int(gateway_report.get("direct_authority_references", -1)) == 0, "Client gateway gained authority reference")
	_assert(int(gateway_report.get("direct_domain_references", -1)) == 0, "Client gateway gained domain reference")

	var final_client: Dictionary = runtime.get_client_snapshot()
	var final_authority: Dictionary = runtime.get_authority_snapshot_for_diagnostics()
	var inventory: Dictionary = final_client.get("domain_components", {}).get("inventory", {})
	_assert(Array(inventory.get("source_item_ids", [])).is_empty(), "Client source still contains item")
	_assert(Array(inventory.get("destination_item_ids", [])).size() == 1, "Client destination item count is not one")
	_assert(int(inventory.get("item_revision", -1)) == 1, "Client item revision is not one")
	_assert(int(inventory.get("committed_operation_count", -1)) == 1, "Client committed operation count is not one")


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("H0 listen-host contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("H0 listen-host contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
