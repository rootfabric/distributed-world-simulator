extends SceneTree

const FixtureScript = preload("res://tests/matter/network/mw6_test_fixture.gd")
const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const PersistenceCodecScript = preload("res://scripts/simulation/matter/persistence/matter_persistence_codec.gd")
const ResultScript = preload("res://scripts/simulation/matter/contracts/matter_mutation_result.gd")
const DeltaScript = preload("res://scripts/simulation/matter/network/matter_replication_delta.gd")
const FrameScript = preload("res://scripts/simulation/matter/network/matter_replication_frame.gd")
const StateSnapshotScript = preload("res://scripts/simulation/matter/network/matter_replication_snapshot.gd")

class PresenterSpy:
	extends RefCounted
	var calls: Array = []

	func invalidate_brick_addresses(address_ids: Array) -> Dictionary:
		calls.append(address_ids.duplicate())
		return {"success": true}


var assertions: int = 0
var failures: Array[String] = []
var manifest: Dictionary = {}
var _root_path: String = ""
var _suite_started_usec: int = 0


func _init() -> void:
	_suite_started_usec = Time.get_ticks_usec()
	_root_path = ProjectSettings.globalize_path(
		"user://mw6-network-%d" % Time.get_ticks_usec()
	)
	DirAccess.make_dir_recursive_absolute(_root_path)
	print("MW6 matter network authority: START")
	_load_manifest()
	_run_stage("manifest", Callable(self, "_test_manifest"))
	_run_stage("durable-bootstrap", Callable(self, "_test_durable_bootstrap"))
	_run_stage("authority-broadcast-replay", Callable(self, "_test_authority_broadcast_and_replay"))
	_run_stage("reconnect-delta-replay", Callable(self, "_test_reconnect_delta_replay"))
	_run_stage("snapshot-fallback-gap", Callable(self, "_test_snapshot_fallback_and_gap"))
	_finish()


func _run_stage(label: String, test_case: Callable) -> void:
	var started_usec: int = Time.get_ticks_usec()
	print("MW6 stage %s: START" % label)
	test_case.call()
	print("MW6 stage %s: DONE (%.3f s)" % [
		label,
		float(Time.get_ticks_usec() - started_usec) / 1000000.0,
	])


func _load_manifest() -> void:
	var path: String = "res://config/matter/mw6-matter-network-replication.v1.json"
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		manifest = parsed


func _test_manifest() -> void:
	_assert(not manifest.is_empty(), "MW6 manifest is missing")
	if manifest.is_empty():
		return
	_assert(String(manifest.get("schema", "")) == "planet_simulator.mw6_matter_network_manifest.v1", "MW6 manifest schema changed")
	_assert(String(manifest.get("checkpoint", "")) == "v17.6.0-simulation-mw6-matter-network-replication", "MW6 checkpoint changed")
	_assert(String(manifest.get("base_checkpoint", "")) == "v17.5.0-simulation-mw5-matter-persistence", "MW6 base changed")
	_assert(String(manifest.get("base_delivery", "")) == "fix7", "MW6 base delivery changed")
	_assert(String(manifest.get("recommended_branch", "")) == "feature/mw6-matter-network-replication", "MW6 branch changed")
	_assert(bool(manifest.get("authoritative_commands", false)), "MW6 authority flag missing")
	_assert(bool(manifest.get("persistent_bricks_only", false)), "MW6 persistent brick policy missing")
	_assert(bool(manifest.get("exact_binary64_wire_payload", false)), "MW6 exact transport flag missing")
	_assert(bool(manifest.get("reconnect_delta_replay", false)), "MW6 reconnect replay flag missing")
	_assert(bool(manifest.get("snapshot_fallback", false)), "MW6 snapshot fallback flag missing")
	_assert(bool(manifest.get("durable_journal_bootstrap", false)), "MW6 durable bootstrap flag missing")
	_assert(not bool(manifest.get("production_moon_changed", true)), "MW6 unexpectedly changes production Moon")


func _test_durable_bootstrap() -> void:
	var setup: Dictionary = FixtureScript.create_authority(
		_root_path.path_join("durable-bootstrap"), 8, true
	)
	_assert_ok(setup, "MW6 durable authority setup failed")
	if not bool(setup.get("success", false)):
		return
	_assert(String(setup.get("preseed_result", {}).get("status", "")) == "COMMITTED", "MW6 durable preseed did not commit")
	_assert(setup["authority"].stream_sequence() == 1, "MW6 authority ignored restored journal sequence")
	_assert(setup["authority"].replay_log_size() == 0, "MW6 durable bootstrap invented replay history")
	var replica = FixtureScript.create_replica(setup, "client/mw6/durable-bootstrap")
	_assert(replica != null, "MW6 durable bootstrap replica setup failed")
	if replica == null:
		return
	var connected: Dictionary = FixtureScript.connect_replica(
		setup,
		replica,
		"peer/mw6/durable-bootstrap/1",
		"session/mw6/durable-bootstrap/1",
		"actor/mw6/durable-bootstrap"
	)
	_assert_ok(connected, "MW6 durable bootstrap connect failed")
	_assert(String(connected.get("details", {}).get("mode", "")) == "FULL_SNAPSHOT", "MW6 durable bootstrap did not choose full snapshot")
	_dispatch_and_poll(setup, replica, "peer/mw6/durable-bootstrap/1")
	_assert(replica.stream_sequence() == 1, "MW6 durable bootstrap sequence not restored")
	_assert(replica.state_hash() == setup["authority"].current_state_hash(), "MW6 durable bootstrap state hash differs")
	_assert(replica.snapshot_store().content_hash() == setup["context"]["service"].snapshot_store().content_hash(), "MW6 durable bootstrap store differs")
	_assert(replica.mutation_journal().content_hash() == setup["context"]["service"].mutation_journal().content_hash(), "MW6 durable bootstrap journal differs")


func _test_authority_broadcast_and_replay() -> void:
	var setup: Dictionary = FixtureScript.create_authority(
		_root_path.path_join("authority-broadcast"), 16
	)
	_assert_ok(setup, "MW6 authority setup failed")
	if not bool(setup.get("success", false)):
		return
	var presenter_a := PresenterSpy.new()
	var presenter_b := PresenterSpy.new()
	var client_a = FixtureScript.create_replica(setup, "client/mw6/a", presenter_a)
	var client_b = FixtureScript.create_replica(setup, "client/mw6/b", presenter_b)
	_assert(client_a != null and client_b != null, "MW6 replica setup failed")
	if client_a == null or client_b == null:
		return
	_assert_ok(FixtureScript.connect_replica(setup, client_a, "peer/mw6/a/1", "session/mw6/a/1", "actor/mw6/a"), "MW6 client A connect failed")
	_assert_ok(FixtureScript.connect_replica(setup, client_b, "peer/mw6/b/1", "session/mw6/b/1", "actor/mw6/b"), "MW6 client B connect failed")
	_assert(setup["authority"].outbound_count("peer/mw6/a/1") == 0, "MW6 synchronized baseline queued unnecessary snapshot")
	_assert(client_a.state_hash() == setup["authority"].current_state_hash(), "MW6 baseline state hash differs")
	var fixture_value: Dictionary = FixtureScript.fixture(setup)
	_assert(not fixture_value.is_empty(), "MW6 excavation fixture missing")
	if fixture_value.is_empty():
		return

	var forged_request: Dictionary = FixtureScript.request(
		setup, fixture_value, "operation/mw6/forged-actor", "actor/mw6/attacker"
	)
	var forged_command: Dictionary = client_a.create_mutation_command(
		forged_request, "message/mw6/forged-actor"
	)
	var forged_wire: Dictionary = setup["command_transport"].send(forged_command)
	_assert(bool(forged_wire.get("success", false)), "MW6 forged command transport failed")
	var forged_result: Dictionary = forged_wire.get("result", {})
	_assert(String(forged_result.get("status", "")) == "REJECTED", "MW6 forged actor command was not rejected")
	_assert(String(forged_result.get("error_code", "")) == "MATTER_COMMAND_ACTOR_NOT_OWNED", "MW6 forged actor error changed")
	_assert(setup["authority"].stream_sequence() == 0, "MW6 forged actor advanced stream")

	var stale_request: Dictionary = FixtureScript.request(
		setup, fixture_value, "operation/mw6/stale-epoch", "actor/mw6/a"
	)
	var stale_command: Dictionary = client_a.create_mutation_command(
		stale_request, "message/mw6/stale-epoch"
	)
	stale_command["authority_epoch"] = 2
	var stale_wire: Dictionary = setup["command_transport"].send(stale_command)
	_assert(bool(stale_wire.get("success", false)), "MW6 stale epoch transport failed")
	_assert(String(stale_wire.get("result", {}).get("error_code", "")) == "STALE_AUTHORITY_EPOCH", "MW6 stale epoch was not rejected")
	_assert(setup["authority"].stream_sequence() == 0, "MW6 stale epoch advanced stream")

	var rejected_request: Dictionary = FixtureScript.request(
		setup, fixture_value, "operation/mw6/insufficient-energy", "actor/mw6/a", 0.0
	)
	var rejected_command: Dictionary = client_a.create_mutation_command(
		rejected_request, "message/mw6/insufficient-energy"
	)
	var rejected_wire: Dictionary = setup["command_transport"].send(rejected_command)
	_assert(bool(rejected_wire.get("success", false)), "MW6 rejected domain command transport failed")
	var rejected_accept: Dictionary = client_a.accept_command_result(rejected_wire.get("result", {}))
	_assert_ok(rejected_accept, "MW6 rejected domain result decode failed")
	var rejected_domain: Dictionary = rejected_accept.get("details", {}).get("result", {})
	_assert(String(rejected_domain.get("status", "")) == "REJECTED", "MW6 insufficient energy result status changed")
	_assert(String(rejected_domain.get("error_code", "")) == "MATTER_MUTATION_INSUFFICIENT_ENERGY", "MW6 insufficient energy error changed")
	_assert(setup["authority"].stream_sequence() == 1, "MW6 rejected journal outcome did not advance stream")
	_dispatch_and_poll(setup, client_a, "peer/mw6/a/1")
	_dispatch_and_poll(setup, client_b, "peer/mw6/b/1")
	_assert(client_a.snapshot_store().size() == 0, "MW6 rejected outcome replicated brick state")
	_assert(client_a.mutation_journal().size() == 1, "MW6 rejected outcome was not journal-replicated")
	_assert(client_a.state_hash() == setup["authority"].current_state_hash(), "MW6 rejected outcome state hash differs")

	var committed_request: Dictionary = FixtureScript.request(
		setup, fixture_value, "operation/mw6/committed", "actor/mw6/a"
	)
	var committed_command: Dictionary = client_a.create_mutation_command(
		committed_request, "message/mw6/committed/1"
	)
	var committed_wire: Dictionary = setup["command_transport"].send(committed_command)
	_assert(bool(committed_wire.get("success", false)), "MW6 committed command transport failed")
	var committed_accept: Dictionary = client_a.accept_command_result(committed_wire.get("result", {}))
	_assert_ok(committed_accept, "MW6 committed command result decode failed")
	var committed_domain: Dictionary = committed_accept.get("details", {}).get("result", {})
	_assert(String(committed_domain.get("status", "")) == "COMMITTED", "MW6 mutation did not commit")
	_assert(setup["authority"].stream_sequence() == 2, "MW6 committed mutation stream sequence changed")
	_dispatch_and_poll(setup, client_a, "peer/mw6/a/1")
	_dispatch_and_poll(setup, client_b, "peer/mw6/b/1")
	_assert(client_a.snapshot_store().content_hash() == setup["context"]["service"].snapshot_store().content_hash(), "MW6 client A brick state differs")
	_assert(client_b.snapshot_store().content_hash() == setup["context"]["service"].snapshot_store().content_hash(), "MW6 client B brick state differs")
	_assert(client_a.mutation_journal().content_hash() == setup["context"]["service"].mutation_journal().content_hash(), "MW6 client journal differs")
	_assert(client_a.state_hash() == setup["authority"].current_state_hash(), "MW6 committed state hash differs")
	_assert(presenter_a.calls.size() == 1, "MW6 presenter A was not selectively invalidated")
	_assert(presenter_b.calls.size() == 1, "MW6 presenter B was not selectively invalidated")
	if not presenter_a.calls.is_empty():
		_assert(Array(presenter_a.calls[0]).size() == committed_domain["changed_bricks"].size(), "MW6 invalidation set size changed")
	var ack: Dictionary = client_a.create_ack()
	_assert_ok(setup["authority"].acknowledge("peer/mw6/a/1", ack), "MW6 replication ack failed")
	var forged_ack: Dictionary = ack.duplicate(true)
	forged_ack["state_hash"] = "0000000000000000000000000000000000000000000000000000000000000000"
	forged_ack["checksum"] = MatterUtilsScript.compute_checksum(forged_ack)
	var forged_ack_result: Dictionary = setup["authority"].acknowledge("peer/mw6/a/1", forged_ack)
	_assert(not bool(forged_ack_result.get("success", false)), "MW6 forged ack hash was accepted")
	_assert(String(forged_ack_result.get("error_code", "")) == "MATTER_REPLICATION_ACK_STATE_MISMATCH", "MW6 forged ack error changed")

	var stream_before_replay: int = setup["authority"].stream_sequence()
	var replay_command: Dictionary = client_a.create_mutation_command(
		committed_request, "message/mw6/committed/2"
	)
	var replay_wire: Dictionary = setup["command_transport"].send(replay_command)
	_assert(bool(replay_wire.get("success", false)), "MW6 exact command replay transport failed")
	_assert(String(replay_wire.get("result", {}).get("status", "")) == "SUCCEEDED", "MW6 exact command replay failed")
	_assert(setup["authority"].stream_sequence() == stream_before_replay, "MW6 exact replay advanced stream")
	_assert(setup["authority"].outbound_count("peer/mw6/a/1") == 0, "MW6 exact replay queued duplicate delta")

	var conflicting_request: Dictionary = committed_request.duplicate(true)
	conflicting_request["energy_budget_j"] = float(conflicting_request["energy_budget_j"]) - 1.0
	conflicting_request["checksum"] = MatterUtilsScript.compute_checksum(conflicting_request)
	var conflicting_command: Dictionary = client_a.create_mutation_command(
		conflicting_request, "message/mw6/committed/conflict"
	)
	var conflicting_wire: Dictionary = setup["command_transport"].send(conflicting_command)
	_assert(bool(conflicting_wire.get("success", false)), "MW6 conflict command transport failed")
	_assert(String(conflicting_wire.get("result", {}).get("error_code", "")) == "OPERATION_ID_CONFLICT", "MW6 operation conflict was not rejected")
	_assert(setup["authority"].stream_sequence() == stream_before_replay, "MW6 operation conflict changed stream")


func _test_reconnect_delta_replay() -> void:
	var setup: Dictionary = FixtureScript.create_authority(
		_root_path.path_join("reconnect-replay"), 8
	)
	_assert_ok(setup, "MW6 reconnect authority setup failed")
	if not bool(setup.get("success", false)):
		return
	var reconnecting = FixtureScript.create_replica(setup, "client/mw6/reconnect")
	var driver = FixtureScript.create_replica(setup, "client/mw6/driver")
	_assert(reconnecting != null and driver != null, "MW6 reconnect replica setup failed")
	if reconnecting == null or driver == null:
		return
	_assert_ok(FixtureScript.connect_replica(setup, reconnecting, "peer/mw6/reconnect/1", "session/mw6/reconnect/1", "actor/mw6/reconnect"), "MW6 reconnect client initial connect failed")
	_assert_ok(FixtureScript.connect_replica(setup, driver, "peer/mw6/driver/1", "session/mw6/driver/1", "actor/mw6/driver"), "MW6 driver connect failed")
	var baseline_hash: String = reconnecting.state_hash()
	_assert_ok(setup["authority"].disconnect_peer("peer/mw6/reconnect/1"), "MW6 disconnect failed")
	var fixture_value: Dictionary = FixtureScript.fixture(setup)
	var request: Dictionary = FixtureScript.request(
		setup, fixture_value, "operation/mw6/reconnect-commit", "actor/mw6/driver"
	)
	var command: Dictionary = driver.create_mutation_command(request, "message/mw6/reconnect-commit")
	var wire: Dictionary = setup["command_transport"].send(command)
	_assert(bool(wire.get("success", false)), "MW6 reconnect driver command transport failed")
	_assert_ok(driver.accept_command_result(wire.get("result", {})), "MW6 reconnect driver result failed")
	_dispatch_and_poll(setup, driver, "peer/mw6/driver/1")
	_assert(setup["authority"].stream_sequence() == 1, "MW6 reconnect stream sequence changed")
	_assert(reconnecting.stream_sequence() == 0 and reconnecting.state_hash() == baseline_hash, "MW6 disconnected client changed")
	_assert_ok(reconnecting.activate_session("peer/mw6/reconnect/2", "session/mw6/reconnect/2"), "MW6 reconnect session rotation failed")
	var reconnect_result: Dictionary = setup["authority"].connect_peer(
		"peer/mw6/reconnect/2",
		"client/mw6/reconnect",
		"session/mw6/reconnect/2",
		"actor/mw6/reconnect",
		reconnecting.create_sync_request()
	)
	_assert_ok(reconnect_result, "MW6 reconnect synchronization failed")
	_assert(String(reconnect_result.get("details", {}).get("mode", "")) == "DELTA_REPLAY", "MW6 reconnect did not choose delta replay")
	_assert(setup["authority"].outbound_count("peer/mw6/reconnect/2") == 1, "MW6 reconnect replay count changed")
	_dispatch_and_poll(setup, reconnecting, "peer/mw6/reconnect/2")
	_assert(reconnecting.stream_sequence() == 1, "MW6 reconnect sequence not restored")
	_assert(reconnecting.state_hash() == setup["authority"].current_state_hash(), "MW6 reconnect state hash differs")
	_assert(reconnecting.snapshot_store().content_hash() == setup["context"]["service"].snapshot_store().content_hash(), "MW6 reconnect brick state differs")


func _test_snapshot_fallback_and_gap() -> void:
	var setup: Dictionary = FixtureScript.create_authority(
		_root_path.path_join("snapshot-fallback"), 0
	)
	_assert_ok(setup, "MW6 snapshot authority setup failed")
	if not bool(setup.get("success", false)):
		return
	var driver = FixtureScript.create_replica(setup, "client/mw6/snapshot-driver")
	_assert(driver != null, "MW6 snapshot driver setup failed")
	if driver == null:
		return
	_assert_ok(FixtureScript.connect_replica(setup, driver, "peer/mw6/snapshot-driver/1", "session/mw6/snapshot-driver/1", "actor/mw6/snapshot-driver"), "MW6 snapshot driver connect failed")
	var fixture_value: Dictionary = FixtureScript.fixture(setup)
	var request: Dictionary = FixtureScript.request(
		setup, fixture_value, "operation/mw6/snapshot-commit", "actor/mw6/snapshot-driver"
	)
	var command: Dictionary = driver.create_mutation_command(request, "message/mw6/snapshot-commit")
	var wire: Dictionary = setup["command_transport"].send(command)
	_assert(bool(wire.get("success", false)), "MW6 snapshot driver command failed")
	_assert_ok(driver.accept_command_result(wire.get("result", {})), "MW6 snapshot driver result failed")
	_dispatch_and_poll(setup, driver, "peer/mw6/snapshot-driver/1")
	_assert(setup["authority"].replay_log_size() == 0, "MW6 zero replay window retained deltas")

	var late = FixtureScript.create_replica(setup, "client/mw6/late")
	_assert(late != null, "MW6 late replica setup failed")
	if late == null:
		return
	var late_connect: Dictionary = FixtureScript.connect_replica(
		setup, late, "peer/mw6/late/1", "session/mw6/late/1", "actor/mw6/late"
	)
	_assert_ok(late_connect, "MW6 late replica connect failed")
	_assert(String(late_connect.get("details", {}).get("mode", "")) == "FULL_SNAPSHOT", "MW6 replay miss did not choose snapshot")
	var adapter = setup["replication_adapter"]
	_assert_ok(setup["authority"].dispatch_peer("peer/mw6/late/1", adapter), "MW6 late snapshot dispatch failed")
	var raw_poll: Dictionary = adapter.poll("peer/mw6/late/1", 8)
	_assert(bool(raw_poll.get("success", false)), "MW6 late raw poll failed")
	var messages: Array = raw_poll.get("details", {}).get("messages", [])
	_assert(messages.size() == 1, "MW6 late snapshot message count changed")
	if messages.size() != 1:
		return
	var snapshot_frame: Dictionary = messages[0]["payload"]
	var snapshot_payload: Dictionary = FrameScript.decode_payload(snapshot_frame)
	_assert(bool(StateSnapshotScript.validate(snapshot_payload).get("success", false)), "MW6 full snapshot contract failed")
	var store_state: Dictionary = PersistenceCodecScript.decode_persistence_json(String(snapshot_payload["store_state_transport"]))
	_assert(store_state.get("snapshots", []).size() > 0, "MW6 full snapshot contains no mutations")
	for raw_snapshot in store_state.get("snapshots", []):
		_assert(int(Dictionary(raw_snapshot).get("state_revision", 0)) >= 1, "MW6 replicated procedural revision-0 brick")
	_assert_ok(late.apply_frame(snapshot_frame), "MW6 late full snapshot apply failed")
	_assert(late.state_hash() == setup["authority"].current_state_hash(), "MW6 late snapshot state hash differs")

	var valid_snapshot: Dictionary = setup["authority"].create_state_snapshot()
	var store_transport: String = String(valid_snapshot["store_state_transport"])
	var journal_transport: String = String(valid_snapshot["journal_state_transport"])
	var operation_record: Dictionary = PersistenceCodecScript.decode_persistence_json(journal_transport)["records"][0]
	var result: Dictionary = operation_record["result"]
	var snapshot_transports: Array = []
	for raw_snapshot in PersistenceCodecScript.decode_persistence_json(store_transport)["snapshots"]:
		snapshot_transports.append(PersistenceCodecScript.encode_persistence_json(Dictionary(raw_snapshot)))
	var base_mismatch_client = FixtureScript.create_replica(setup, "client/mw6/base-mismatch")
	_assert(base_mismatch_client != null, "MW6 base mismatch replica setup failed")
	if base_mismatch_client == null:
		return
	_assert_ok(base_mismatch_client.activate_session("peer/mw6/base-mismatch/1", "session/mw6/base-mismatch/1"), "MW6 base mismatch session setup failed")
	var base_mismatch_delta: Dictionary = DeltaScript.create({
		"body_id": valid_snapshot["body_id"],
		"authority_owner_id": valid_snapshot["authority_owner_id"],
		"authority_epoch": valid_snapshot["authority_epoch"],
		"previous_stream_sequence": 0,
		"stream_sequence": 1,
		"operation_id": operation_record["operation_id"],
		"request_transport": PersistenceCodecScript.encode_persistence_json(Dictionary(operation_record["request"])),
		"result_transport": PersistenceCodecScript.encode_persistence_json(Dictionary(result)),
		"snapshot_transports": snapshot_transports,
		"base_state_hash": "0000000000000000000000000000000000000000000000000000000000000000",
		"target_state_hash": valid_snapshot["state_hash"],
	})
	_assert(bool(DeltaScript.validate(base_mismatch_delta).get("success", false)), "MW6 base mismatch fixture delta invalid")
	var base_mismatch_frame: Dictionary = FrameScript.create({
		"frame_id": "frame/mw6/base-mismatch/1",
		"frame_kind": "MUTATION_DELTA",
		"body_id": valid_snapshot["body_id"],
		"authority_owner_id": valid_snapshot["authority_owner_id"],
		"authority_epoch": valid_snapshot["authority_epoch"],
		"session_id": "session/mw6/base-mismatch/1",
		"stream_sequence": 1,
		"payload_schema": DeltaScript.SCHEMA,
		"payload_transport": PersistenceCodecScript.encode_persistence_json(base_mismatch_delta),
	})
	var base_mismatch_result: Dictionary = base_mismatch_client.apply_frame(base_mismatch_frame)
	_assert(not bool(base_mismatch_result.get("success", false)), "MW6 wrong base hash was accepted")
	_assert(String(base_mismatch_result.get("error_code", "")) == "MATTER_REPLICATION_BASE_STATE_MISMATCH", "MW6 base mismatch error changed")
	_assert(base_mismatch_client.requires_resync(), "MW6 base mismatch did not request resync")
	_assert(base_mismatch_client.snapshot_store().size() == 0 and base_mismatch_client.mutation_journal().size() == 0, "MW6 base mismatch partially mutated replica")

	var gap_client = FixtureScript.create_replica(setup, "client/mw6/gap")
	_assert(gap_client != null, "MW6 gap replica setup failed")
	if gap_client == null:
		return
	_assert_ok(gap_client.activate_session("peer/mw6/gap/1", "session/mw6/gap/1"), "MW6 gap session setup failed")
	var gap_delta: Dictionary = DeltaScript.create({
		"body_id": valid_snapshot["body_id"],
		"authority_owner_id": valid_snapshot["authority_owner_id"],
		"authority_epoch": valid_snapshot["authority_epoch"],
		"previous_stream_sequence": 1,
		"stream_sequence": 2,
		"operation_id": operation_record["operation_id"],
		"request_transport": PersistenceCodecScript.encode_persistence_json(Dictionary(operation_record["request"])),
		"result_transport": PersistenceCodecScript.encode_persistence_json(Dictionary(result)),
		"snapshot_transports": snapshot_transports,
		"base_state_hash": valid_snapshot["state_hash"],
		"target_state_hash": "0000000000000000000000000000000000000000000000000000000000000000",
	})
	_assert(bool(DeltaScript.validate(gap_delta).get("success", false)), "MW6 gap fixture delta invalid")
	var gap_frame: Dictionary = FrameScript.create({
		"frame_id": "frame/mw6/gap/2",
		"frame_kind": "MUTATION_DELTA",
		"body_id": valid_snapshot["body_id"],
		"authority_owner_id": valid_snapshot["authority_owner_id"],
		"authority_epoch": valid_snapshot["authority_epoch"],
		"session_id": "session/mw6/gap/1",
		"stream_sequence": 2,
		"payload_schema": DeltaScript.SCHEMA,
		"payload_transport": PersistenceCodecScript.encode_persistence_json(gap_delta),
	})
	var gap_result: Dictionary = gap_client.apply_frame(gap_frame)
	_assert(not bool(gap_result.get("success", false)), "MW6 sequence gap was accepted")
	_assert(String(gap_result.get("error_code", "")) == "MATTER_REPLICATION_SEQUENCE_GAP", "MW6 sequence gap error changed")
	_assert(gap_client.requires_resync(), "MW6 sequence gap did not request resync")
	_assert(gap_client.snapshot_store().size() == 0 and gap_client.mutation_journal().size() == 0, "MW6 sequence gap partially mutated replica")


func _dispatch_and_poll(setup: Dictionary, replica, peer_id: String) -> void:
	_assert_ok(setup["authority"].dispatch_peer(peer_id, setup["replication_adapter"]), "MW6 replication dispatch failed for %s" % peer_id)
	_assert_ok(replica.poll_replication(setup["replication_adapter"]), "MW6 replication apply failed for %s" % peer_id)


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, String(result.get("error_code", ""))])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _finish() -> void:
	var duration_seconds: float = float(Time.get_ticks_usec() - _suite_started_usec) / 1000000.0
	if failures.is_empty():
		print("MW6 matter network authority: PASS (%d assertions / %.3f s)" % [assertions, duration_seconds])
		quit(0)
		return
	print("MW6 matter network authority: FAIL (%d failures / %d assertions / %.3f s)" % [
		failures.size(), assertions, duration_seconds,
	])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)
