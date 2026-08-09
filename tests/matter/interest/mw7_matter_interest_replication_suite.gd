extends SceneTree

const FixtureScript = preload("res://tests/matter/interest/mw7_test_fixture.gd")
const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const RegionScript = preload("res://scripts/simulation/matter/interest/matter_interest_region.gd")
const SubscriptionScript = preload("res://scripts/simulation/matter/interest/matter_interest_subscription.gd")
const DeltaScript = preload("res://scripts/simulation/matter/interest/matter_interest_delta.gd")
const FrameScript = preload("res://scripts/simulation/matter/interest/matter_interest_frame.gd")
const PersistenceCodecScript = preload("res://scripts/simulation/matter/persistence/matter_persistence_codec.gd")

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
		"user://mw7-interest-%d" % Time.get_ticks_usec()
	)
	DirAccess.make_dir_recursive_absolute(_root_path)
	print("MW7 matter interest replication: START")
	_load_manifest()
	_run_stage("manifest-region-contract", Callable(self, "_test_manifest_and_region_contract"))
	_run_stage("filtered-stream-interest-move", Callable(self, "_test_filtered_stream_and_interest_move"))
	_run_stage("reconnect-replay-snapshot", Callable(self, "_test_reconnect_replay_and_snapshot_fallback"))
	_finish()


func _run_stage(label: String, test_case: Callable) -> void:
	var started_usec: int = Time.get_ticks_usec()
	print("MW7 stage %s: START" % label)
	test_case.call()
	print("MW7 stage %s: DONE (%.3f s)" % [
		label,
		float(Time.get_ticks_usec() - started_usec) / 1000000.0,
	])


func _load_manifest() -> void:
	var path: String = "res://config/matter/mw7-matter-interest-replication.v1.json"
	if not FileAccess.file_exists(path):
		return
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		manifest = parsed


func _test_manifest_and_region_contract() -> void:
	_assert(not manifest.is_empty(), "MW7 manifest is missing")
	if manifest.is_empty():
		return
	_assert(String(manifest.get("schema", "")) == "planet_simulator.mw7_matter_interest_manifest.v1", "MW7 manifest schema changed")
	_assert(String(manifest.get("checkpoint", "")) == "v17.7.0-simulation-mw7-matter-interest-replication", "MW7 checkpoint changed")
	_assert(String(manifest.get("base_checkpoint", "")) == "v17.6.0-simulation-mw6-matter-network-replication", "MW7 base changed")
	_assert(String(manifest.get("base_delivery", "")) == "fix2", "MW7 base delivery changed")
	_assert(bool(manifest.get("regional_interest", false)), "MW7 regional interest flag missing")
	_assert(bool(manifest.get("persistent_bricks_only", false)), "MW7 persistent-only flag missing")
	_assert(bool(manifest.get("interest_enter_leave", false)), "MW7 enter/leave flag missing")
	_assert(bool(manifest.get("regional_delta_replay", false)), "MW7 regional replay flag missing")
	_assert(bool(manifest.get("regional_snapshot_fallback", false)), "MW7 regional snapshot flag missing")
	_assert(not bool(manifest.get("full_body_sparse_store_sent", true)), "MW7 still declares full-body store replication")
	_assert(not bool(manifest.get("production_moon_changed", true)), "MW7 unexpectedly changes production Moon")

	var setup: Dictionary = FixtureScript.create_authority(
		_root_path.path_join("region-contract"), 4
	)
	_assert_ok(setup, "MW7 region contract setup failed")
	if not bool(setup.get("success", false)):
		return
	var fixtures: Array[Dictionary] = FixtureScript.surface_fixtures(setup, Vector3.RIGHT, 2)
	_assert(fixtures.size() >= 1, "MW7 region fixture missing")
	if fixtures.is_empty():
		return
	var center_cell: Dictionary = fixtures[0]["address"]["cell_address"]
	var subscription: Dictionary = SubscriptionScript.create(
		"subscription/mw7/region-contract",
		"client/mw7/region-contract",
		FixtureScript.AUTHORITY_EPOCH,
		1,
		FixtureScript.CELL_LEVEL,
		center_cell,
		1
	)
	_assert_ok(RegionScript.validate_subscription(setup["context"]["grid_profile"], subscription), "MW7 subscription validation failed")
	var center_indices: Array = RegionScript.indices_for_cell(center_cell)
	_assert(center_indices.size() == 3, "MW7 center indices missing")
	if center_indices.size() != 3:
		return
	var rebuilt: Dictionary = RegionScript.cell_for_indices(
		setup["context"]["grid_profile"],
		FixtureScript.CELL_LEVEL,
		int(center_indices[0]), int(center_indices[1]), int(center_indices[2])
	)
	_assert(String(rebuilt.get("cell_id", "")) == String(center_cell["cell_id"]), "MW7 cell index roundtrip changed address")
	var addresses: Array[Dictionary] = RegionScript.cell_addresses(
		setup["context"]["grid_profile"], subscription
	)
	_assert(not addresses.is_empty() and addresses.size() <= 27, "MW7 radius-one region size invalid")
	_assert(RegionScript.contains_cell_address(setup["context"]["grid_profile"], subscription, center_cell), "MW7 region excludes center")
	var stale: Dictionary = subscription.duplicate(true)
	stale["radius_cells"] = 9
	stale["checksum"] = ""
	stale["checksum"] = MatterUtilsScript.compute_checksum(stale)
	_assert(not bool(SubscriptionScript.validate(stale).get("success", false)), "MW7 oversized interest radius accepted")
	var fence_client = FixtureScript.create_replica(setup, "client/mw7/revision-fence")
	_assert(fence_client != null, "MW7 revision-fence client failed")
	if fence_client != null:
		_assert_ok(fence_client.set_interest("subscription/mw7/revision-fence", 1, center_cell, 1), "MW7 initial revision fence failed")
		var same_revision_conflict: Dictionary = fence_client.set_interest(
			"subscription/mw7/revision-fence", 1, center_cell, 0
		)
		_assert(String(same_revision_conflict.get("error_code", "")) == "SAME_REVISION_MATTER_INTEREST_CONFLICT", "MW7 same-revision interest conflict accepted")
		_assert_ok(fence_client.set_interest("subscription/mw7/revision-fence", 2, center_cell, 0), "MW7 newer interest revision rejected")
		var stale_revision: Dictionary = fence_client.set_interest(
			"subscription/mw7/revision-fence", 1, center_cell, 0
		)
		_assert(String(stale_revision.get("error_code", "")) == "STALE_MATTER_INTEREST_REVISION", "MW7 stale interest revision accepted")


func _test_filtered_stream_and_interest_move() -> void:
	var setup: Dictionary = FixtureScript.create_authority(
		_root_path.path_join("filtered-stream"), 8
	)
	_assert_ok(setup, "MW7 filtered stream setup failed")
	if not bool(setup.get("success", false)):
		return
	var positive_fixtures: Array[Dictionary] = FixtureScript.surface_fixtures(setup, Vector3.RIGHT, 2)
	var negative_fixtures: Array[Dictionary] = FixtureScript.surface_fixtures(setup, Vector3.LEFT, 2)
	_assert(positive_fixtures.size() >= 1 and negative_fixtures.size() >= 1, "MW7 distant fixtures missing")
	if positive_fixtures.is_empty() or negative_fixtures.is_empty():
		return
	var positive: Dictionary = positive_fixtures[0]
	var negative: Dictionary = negative_fixtures[0]

	var positive_client = FixtureScript.create_replica(setup, "client/mw7/positive")
	var negative_client = FixtureScript.create_replica(setup, "client/mw7/negative")
	_assert(positive_client != null and negative_client != null, "MW7 driver replicas failed")
	if positive_client == null or negative_client == null:
		return
	_assert_ok(positive_client.set_interest("subscription/mw7/positive", 1, positive["address"]["cell_address"], 0), "MW7 positive interest setup failed")
	_assert_ok(negative_client.set_interest("subscription/mw7/negative", 1, negative["address"]["cell_address"], 0), "MW7 negative interest setup failed")
	var positive_connect: Dictionary = FixtureScript.connect_replica(
		setup, positive_client, "peer/mw7/positive/1", "session/mw7/positive/1", "actor/mw7/positive"
	)
	var negative_connect: Dictionary = FixtureScript.connect_replica(
		setup, negative_client, "peer/mw7/negative/1", "session/mw7/negative/1", "actor/mw7/negative"
	)
	_assert_ok(positive_connect, "MW7 positive connect failed")
	_assert_ok(negative_connect, "MW7 negative connect failed")
	_assert(String(positive_connect.get("details", {}).get("mode", "")) == "CURRENT", "MW7 empty positive region did not start current")
	_assert(String(negative_connect.get("details", {}).get("mode", "")) == "CURRENT", "MW7 empty negative region did not start current")

	var positive_result: Dictionary = _send_mutation(
		setup, positive_client, positive, "operation/mw7/positive", "actor/mw7/positive", "message/mw7/positive"
	)
	_assert_ok(positive_result, "MW7 positive command failed")
	_assert(setup["interest_server"].outbound_count("peer/mw7/positive/1") == 1, "MW7 relevant positive delta not queued")
	_assert(setup["interest_server"].outbound_count("peer/mw7/negative/1") == 0, "MW7 irrelevant positive delta leaked to negative region")
	_assert(setup["authority"].outbound_count("peer/mw7/positive/1") == 0, "MW7 interest peer received a full MW6 frame")
	_dispatch_and_poll(setup, positive_client, "peer/mw7/positive/1")
	_assert(positive_client.snapshot_store().size() == 1, "MW7 positive region did not receive one persistent brick")
	_assert(negative_client.snapshot_store().size() == 0, "MW7 negative region mutated by irrelevant delta")

	var negative_result: Dictionary = _send_mutation(
		setup, negative_client, negative, "operation/mw7/negative", "actor/mw7/negative", "message/mw7/negative"
	)
	_assert_ok(negative_result, "MW7 negative command failed")
	_assert(setup["authority"].replication_observer_errors().is_empty(), "MW7 interest observer reported projection errors")
	_assert(setup["interest_server"].outbound_count("peer/mw7/positive/1") == 0, "MW7 irrelevant negative delta leaked to positive region")
	_assert(setup["interest_server"].outbound_count("peer/mw7/negative/1") == 1, "MW7 relevant negative delta not queued")
	_dispatch_and_poll(setup, negative_client, "peer/mw7/negative/1")
	_assert(setup["context"]["service"].snapshot_store().size() >= 2, "MW7 authority fixture did not create two persistent regions")

	var presenter = PresenterSpy.new()
	var observer = FixtureScript.create_replica(setup, "client/mw7/observer", presenter)
	_assert(observer != null, "MW7 observer replica failed")
	if observer == null:
		return
	_assert_ok(observer.set_interest("subscription/mw7/observer", 1, positive["address"]["cell_address"], 0), "MW7 observer positive interest failed")
	var observer_connect: Dictionary = FixtureScript.connect_replica(
		setup, observer, "peer/mw7/observer/1", "session/mw7/observer/1", "actor/mw7/observer"
	)
	_assert_ok(observer_connect, "MW7 observer connect failed")
	_assert(String(observer_connect.get("details", {}).get("mode", "")) == "REGION_SNAPSHOT", "MW7 late observer did not receive regional snapshot")
	_dispatch_and_poll(setup, observer, "peer/mw7/observer/1")
	_assert(observer.snapshot_store().size() == 1, "MW7 regional snapshot did not filter full sparse store")
	_assert(observer.snapshot_store().has_address_id(String(positive["address"]["address_id"])), "MW7 positive regional snapshot missing target brick")
	_assert(not observer.snapshot_store().has_address_id(String(negative["address"]["address_id"])), "MW7 positive regional snapshot leaked negative brick")
	for address_id in observer.snapshot_store().address_ids():
		_assert(observer.snapshot_store().revision_for_address_id(String(address_id)) >= 1, "MW7 regional snapshot contained revision-zero brick")
	_assert(observer.source_global_stream_sequence() == setup["authority"].stream_sequence(), "MW7 regional snapshot global cursor changed")
	var ack: Dictionary = observer.create_ack()
	_assert_ok(setup["interest_server"].acknowledge("peer/mw7/observer/1", ack), "MW7 regional ack failed")
	var forged_ack: Dictionary = ack.duplicate(true)
	forged_ack["projection_hash"] = "0000000000000000000000000000000000000000000000000000000000000000"
	forged_ack["checksum"] = ""
	forged_ack["checksum"] = MatterUtilsScript.compute_checksum(forged_ack)
	var forged_result: Dictionary = setup["interest_server"].acknowledge("peer/mw7/observer/1", forged_ack)
	_assert(not bool(forged_result.get("success", false)), "MW7 forged projection ack accepted")

	_assert_ok(observer.set_interest("subscription/mw7/observer", 2, negative["address"]["cell_address"], 0), "MW7 observer move failed")
	_assert(observer.snapshot_store().has_address_id(String(positive["address"]["address_id"])), "MW7 pending interest update evicted active view before snapshot")
	_assert(int(observer.pending_subscription().get("interest_revision", 0)) == 2, "MW7 pending interest revision not retained")
	var active_snapshot: Dictionary = setup["interest_server"].create_region_snapshot("client/mw7/observer")
	_assert(not active_snapshot.is_empty(), "MW7 active snapshot fixture missing during pending interest")
	if active_snapshot.is_empty():
		return
	var active_subscription: Dictionary = observer.subscription()
	var active_frame: Dictionary = FrameScript.create({
		"frame_id": "frame/mw7/observer/inflight-active",
		"frame_kind": "REGION_SNAPSHOT",
		"body_id": setup["context"]["body"]["body_id"],
		"authority_owner_id": FixtureScript.AUTHORITY_OWNER_ID,
		"authority_epoch": FixtureScript.AUTHORITY_EPOCH,
		"session_id": "session/mw7/observer/1",
		"subscription_id": active_subscription["subscription_id"],
		"interest_revision": active_subscription["interest_revision"],
		"region_sequence": active_snapshot["region_sequence"],
		"source_global_stream_sequence": active_snapshot["source_global_stream_sequence"],
		"payload_schema": active_snapshot["schema"],
		"payload_transport": PersistenceCodecScript.encode_persistence_json(active_snapshot),
	})
	_assert_ok(observer.apply_frame(active_frame), "MW7 in-flight active snapshot failed while interest was pending")
	_assert(int(observer.pending_subscription().get("interest_revision", 0)) == 2, "MW7 in-flight active snapshot cleared pending interest")
	var update_result: Dictionary = setup["interest_server"].update_interest(
		"peer/mw7/observer/1", observer.create_sync_request()
	)
	_assert_ok(update_result, "MW7 server interest update failed")
	_assert(String(update_result.get("details", {}).get("mode", "")) == "REGION_SNAPSHOT", "MW7 interest move did not queue replacement snapshot")
	_dispatch_and_poll(setup, observer, "peer/mw7/observer/1")
	_assert(observer.snapshot_store().size() == 1, "MW7 moved region snapshot size changed")
	_assert(observer.snapshot_store().has_address_id(String(negative["address"]["address_id"])), "MW7 moved region missing entered brick")
	_assert(not observer.snapshot_store().has_address_id(String(positive["address"]["address_id"])), "MW7 moved region retained evicted brick")
	_assert(presenter.calls.size() >= 2, "MW7 presenter did not observe enter/leave invalidations")


func _test_reconnect_replay_and_snapshot_fallback() -> void:
	var setup: Dictionary = FixtureScript.create_authority(
		_root_path.path_join("reconnect"), 1
	)
	_assert_ok(setup, "MW7 reconnect setup failed")
	if not bool(setup.get("success", false)):
		return
	var fixtures: Array[Dictionary] = FixtureScript.nearby_fixtures(setup, Vector3.RIGHT, 2, 4)
	_assert(fixtures.size() >= 4, "MW7 reconnect requires four nearby fixtures")
	if fixtures.size() < 4:
		return
	var client = FixtureScript.create_replica(setup, "client/mw7/reconnect")
	_assert(client != null, "MW7 reconnect client failed")
	if client == null:
		return
	_assert_ok(client.set_interest("subscription/mw7/reconnect", 1, fixtures[0]["address"]["cell_address"], 2), "MW7 reconnect interest failed")
	_assert_ok(FixtureScript.connect_replica(setup, client, "peer/mw7/reconnect/1", "session/mw7/reconnect/1", "actor/mw7/reconnect"), "MW7 reconnect initial connect failed")
	_assert_ok(_send_mutation(setup, client, fixtures[0], "operation/mw7/reconnect/one", "actor/mw7/reconnect", "message/mw7/reconnect/one"), "MW7 reconnect first mutation failed")
	_dispatch_and_poll(setup, client, "peer/mw7/reconnect/1")
	_assert(client.region_sequence() == 1, "MW7 reconnect first regional sequence changed")

	setup["interest_server"].disconnect_peer("peer/mw7/reconnect/1")
	setup["authority"].disconnect_peer("peer/mw7/reconnect/1")
	var driver = FixtureScript.create_replica(setup, "client/mw7/reconnect-driver")
	_assert(driver != null, "MW7 reconnect driver failed")
	if driver == null:
		return
	_assert_ok(driver.set_interest("subscription/mw7/reconnect-driver", 1, fixtures[0]["address"]["cell_address"], 2), "MW7 reconnect driver interest failed")
	_assert_ok(FixtureScript.connect_replica(setup, driver, "peer/mw7/reconnect-driver/1", "session/mw7/reconnect-driver/1", "actor/mw7/reconnect-driver"), "MW7 reconnect driver connect failed")
	_dispatch_if_queued(setup, driver, "peer/mw7/reconnect-driver/1")
	_assert_ok(_send_mutation(setup, driver, fixtures[1], "operation/mw7/reconnect/two", "actor/mw7/reconnect-driver", "message/mw7/reconnect/two"), "MW7 reconnect second mutation failed")

	var replay_connect: Dictionary = FixtureScript.reconnect_replica(
		setup, client, "peer/mw7/reconnect/1", "peer/mw7/reconnect/2", "session/mw7/reconnect/2", "actor/mw7/reconnect"
	)
	_assert_ok(replay_connect, "MW7 replay reconnect failed")
	_assert(String(replay_connect.get("details", {}).get("mode", "")) == "DELTA_REPLAY", "MW7 reconnect did not choose regional delta replay")
	_dispatch_and_poll(setup, client, "peer/mw7/reconnect/2")
	_assert(client.region_sequence() == 2, "MW7 replay reconnect sequence changed")
	_assert(client.projection_hash() == String(setup["interest_server"].subscription_state("client/mw7/reconnect")["projection_hash"]), "MW7 replay projection hash differs")

	setup["interest_server"].disconnect_peer("peer/mw7/reconnect/2")
	setup["authority"].disconnect_peer("peer/mw7/reconnect/2")
	_assert_ok(_send_mutation(setup, driver, fixtures[2], "operation/mw7/reconnect/three", "actor/mw7/reconnect-driver", "message/mw7/reconnect/three"), "MW7 reconnect third mutation failed")
	var fourth_fixture: Dictionary = fixtures[3]
	_assert_ok(_send_mutation(setup, driver, fourth_fixture, "operation/mw7/reconnect/four", "actor/mw7/reconnect-driver", "message/mw7/reconnect/four"), "MW7 reconnect fourth mutation failed")
	var fallback_connect: Dictionary = FixtureScript.reconnect_replica(
		setup, client, "peer/mw7/reconnect/2", "peer/mw7/reconnect/3", "session/mw7/reconnect/3", "actor/mw7/reconnect"
	)
	_assert_ok(fallback_connect, "MW7 fallback reconnect failed")
	_assert(String(fallback_connect.get("details", {}).get("mode", "")) == "REGION_SNAPSHOT", "MW7 replay eviction did not choose regional snapshot")
	_dispatch_and_poll(setup, client, "peer/mw7/reconnect/3")
	var state: Dictionary = setup["interest_server"].subscription_state("client/mw7/reconnect")
	_assert(client.projection_hash() == String(state["projection_hash"]), "MW7 fallback projection hash differs")

	var replay_log: Array = state["replay_log"]
	_assert(not replay_log.is_empty(), "MW7 replay log missing for gap test")
	if replay_log.is_empty():
		return
	var latest_delta: Dictionary = replay_log[replay_log.size() - 1]
	var gap_client = FixtureScript.create_replica(setup, "client/mw7/gap")
	_assert(gap_client != null, "MW7 gap client failed")
	if gap_client == null:
		return
	_assert_ok(gap_client.set_interest("subscription/mw7/reconnect", 1, fixtures[0]["address"]["cell_address"], 2), "MW7 gap interest failed")
	_assert_ok(gap_client.activate_session("peer/mw7/gap/1", "session/mw7/gap/1"), "MW7 gap session failed")
	var gap_frame: Dictionary = FrameScript.create({
		"frame_id": "frame/mw7/gap/1",
		"frame_kind": "REGION_DELTA",
		"body_id": setup["context"]["body"]["body_id"],
		"authority_owner_id": FixtureScript.AUTHORITY_OWNER_ID,
		"authority_epoch": FixtureScript.AUTHORITY_EPOCH,
		"session_id": "session/mw7/gap/1",
		"subscription_id": latest_delta["subscription_id"],
		"interest_revision": latest_delta["interest_revision"],
		"region_sequence": latest_delta["region_sequence"],
		"source_global_stream_sequence": latest_delta["source_global_stream_sequence"],
		"payload_schema": DeltaScript.SCHEMA,
		"payload_transport": PersistenceCodecScript.encode_persistence_json(latest_delta),
	})
	_assert(bool(FrameScript.validate(gap_frame).get("success", false)), "MW7 gap fixture frame invalid")
	var gap_result: Dictionary = gap_client.apply_frame(gap_frame)
	_assert(not bool(gap_result.get("success", false)), "MW7 regional sequence gap accepted")
	_assert(String(gap_result.get("error_code", "")) == "MATTER_INTEREST_SEQUENCE_GAP", "MW7 regional sequence gap error changed")
	_assert(gap_client.requires_resync(), "MW7 regional gap did not request resync")
	_assert(gap_client.snapshot_store().size() == 0, "MW7 regional gap partially mutated store")
	_assert(setup["authority"].replication_observer_errors().is_empty(), "MW7 reconnect observer reported projection errors")


func _send_mutation(
	setup: Dictionary,
	replica,
	fixture_value: Dictionary,
	operation_id: String,
	actor_id: String,
	message_id: String
) -> Dictionary:
	var request: Dictionary = FixtureScript.request(
		setup, fixture_value, operation_id, actor_id
	)
	if request.is_empty():
		return {"success": false, "error_code": "MW7_REQUEST_BUILD_FAILED"}
	var command: Dictionary = replica.create_mutation_command(request, message_id)
	if command.is_empty():
		return {"success": false, "error_code": "MW7_COMMAND_BUILD_FAILED"}
	var wire: Dictionary = setup["command_transport"].send(command)
	if not bool(wire.get("success", false)):
		return {"success": false, "error_code": "MW7_COMMAND_TRANSPORT_FAILED"}
	return replica.accept_command_result(Dictionary(wire.get("result", {})))


func _dispatch_and_poll(setup: Dictionary, replica, peer_id: String) -> void:
	_assert_ok(setup["interest_server"].dispatch_peer(peer_id, setup["replication_adapter"]), "MW7 interest dispatch failed for %s" % peer_id)
	_assert_ok(replica.poll_replication(setup["replication_adapter"]), "MW7 interest apply failed for %s" % peer_id)


func _dispatch_if_queued(setup: Dictionary, replica, peer_id: String) -> void:
	if setup["interest_server"].outbound_count(peer_id) > 0:
		_dispatch_and_poll(setup, replica, peer_id)


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
		print("MW7 matter interest replication: PASS (%d assertions / %.3f s)" % [assertions, duration_seconds])
		quit(0)
		return
	print("MW7 matter interest replication: FAIL (%d failures / %d assertions / %.3f s)" % [
		failures.size(), assertions, duration_seconds,
	])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)
