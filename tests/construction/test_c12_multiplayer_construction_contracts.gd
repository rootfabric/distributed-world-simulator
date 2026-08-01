extends SceneTree

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const GrantScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_permission_grant.gd")
const PermissionStoreScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_permission_store.gd")
const CommandScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_command.gd")
const SessionStoreScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_session_store.gd")
const BundleScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_state_bundle.gd")
const EventScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_event.gd")
const ReplicaScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_replica.gd")
const Fixture = preload("res://tests/construction/fixtures/c12_multiplayer_construction_fixture.gd")
const C11Fixture = preload("res://tests/construction/fixtures/c11_local_geometry_editing_fixture.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_test_permission_contract_and_store()
	_test_command_session_event_and_replica()
	_finish()

func _test_permission_contract_and_store() -> void:
	var grant := GrantScript.create("permission/c12/contracts", Fixture.CLIENT_A, "construct/geometry-edit/contracts", [GrantScript.ACTION_EDIT, GrantScript.ACTION_READ], 3, 5, {"role": "engineer"})
	_assert_ok(GrantScript.validate(grant), "Valid permission rejected")
	_assert(GrantScript.authorizes(grant, Fixture.CLIENT_A, "construct/geometry-edit/contracts", GrantScript.ACTION_EDIT, 3), "Permission did not authorize exact target")
	_assert(not GrantScript.authorizes(grant, Fixture.CLIENT_B, "construct/geometry-edit/contracts", GrantScript.ACTION_EDIT, 3), "Permission authorized wrong subject")
	_assert(not GrantScript.authorizes(grant, Fixture.CLIENT_A, "construct/geometry-edit/contracts", GrantScript.ACTION_DAMAGE, 3), "Permission authorized wrong action")
	_assert(not GrantScript.authorizes(grant, Fixture.CLIENT_A, "construct/geometry-edit/contracts", GrantScript.ACTION_EDIT, 6), "Expired permission remained active")
	var unexpected := grant.duplicate(true); unexpected["unknown"] = true
	_assert_error(GrantScript.validate(unexpected), "UNEXPECTED_FIELD", "Permission accepted unknown field")
	var duplicate := GrantScript.create("permission/c12/duplicate", Fixture.CLIENT_A, "*", [GrantScript.ACTION_EDIT, GrantScript.ACTION_EDIT], 1)
	_assert_error(GrantScript.validate(duplicate), "DUPLICATE_CONSTRUCTION_MULTIPLAYER_PERMISSION_ACTION", "Permission accepted duplicate action")
	var noncanonical := grant.duplicate(true); noncanonical["allowed_actions"] = [GrantScript.ACTION_READ, GrantScript.ACTION_EDIT]; noncanonical["checksum"] = GrantScript.compute_checksum(noncanonical)
	_assert_error(GrantScript.validate(noncanonical), "NON_CANONICAL_CONSTRUCTION_MULTIPLAYER_PERMISSION_ACTIONS", "Permission accepted noncanonical actions")
	var store = PermissionStoreScript.new(); _assert_ok(store.setup(3), "Permission store setup failed")
	_assert_ok(store.publish(grant), "Permission publish failed")
	_assert(store.get_generation() == 1, "Permission publish generation mismatch")
	var replay := store.publish(grant); _assert_ok(replay, "Permission replay failed"); _assert(bool(replay["replay"]), "Permission replay not marked"); _assert(store.get_generation() == 1, "Permission replay changed generation")
	_assert_ok(store.authorize(Fixture.CLIENT_A, "construct/geometry-edit/contracts", GrantScript.ACTION_EDIT, 3), "Store denied valid permission")
	_assert_error(store.authorize(Fixture.CLIENT_A, "construct/geometry-edit/contracts", GrantScript.ACTION_DAMAGE, 3), "CONSTRUCTION_MULTIPLAYER_PERMISSION_DENIED", "Store authorized missing action")
	_assert_error(store.authorize(Fixture.CLIENT_A, "construct/geometry-edit/contracts", GrantScript.ACTION_EDIT, 2), "CONSTRUCTION_MULTIPLAYER_PERMISSION_EPOCH_MISMATCH", "Store accepted stale epoch")
	_assert_ok(store.revoke(String(grant["grant_id"]), String(grant["checksum"])), "Permission revoke failed")
	_assert_error(store.authorize(Fixture.CLIENT_A, "construct/geometry-edit/contracts", GrantScript.ACTION_EDIT, 3), "CONSTRUCTION_MULTIPLAYER_PERMISSION_DENIED", "Revoked permission remained active")
	_assert_ok(store.set_epoch(4), "Permission epoch advance failed")
	_assert_error(store.set_epoch(3), "CONSTRUCTION_MULTIPLAYER_PERMISSION_EPOCH_ROLLBACK", "Permission epoch rolled back")
	var state := store.export_state(); _assert_ok(PermissionStoreScript.validate_state(state), "Permission state rejected")
	var restored = PermissionStoreScript.new(); _assert_ok(restored.load_state(state), "Permission state restore failed")
	_assert(UtilsScript.canonical_json(restored.export_state()) == UtilsScript.canonical_json(state), "Permission state roundtrip changed")
	var tampered := state.duplicate(true); tampered["epoch"] = 9
	_assert_error(restored.load_state(tampered), "CONSTRUCTION_MULTIPLAYER_PERMISSION_STORE_CHECKSUM_MISMATCH", "Permission state accepted tamper")

func _test_command_session_event_and_replica() -> void:
	var graph := C11Fixture.graph("contracts")
	var session_store = SessionStoreScript.new()
	var connected := session_store.connect_session(Fixture.CLIENT_A, Fixture.SESSION_A, 1, -1); _assert_ok(connected, "Session connect failed")
	var session: Dictionary = connected["session"]
	_assert_ok(SessionStoreScript.validate_session(session), "Session contract rejected")
	_assert(int(session["session_epoch"]) == 1 and int(session["next_sequence"]) == 0, "Fresh session counters mismatch")
	_assert_ok(session_store.consume_sequence(Fixture.SESSION_A, 1, 0), "Session sequence consume failed")
	_assert_error(session_store.consume_sequence(Fixture.SESSION_A, 1, 0), "CONSTRUCTION_MULTIPLAYER_COMMAND_SEQUENCE_MISMATCH", "Session accepted duplicate sequence")
	_assert_ok(session_store.acknowledge(Fixture.SESSION_A, 1, 0), "Session acknowledge failed")
	_assert_error(session_store.acknowledge(Fixture.SESSION_A, 1, -1), "CONSTRUCTION_MULTIPLAYER_EVENT_ACK_ROLLBACK", "Session ack rolled back")
	_assert_ok(session_store.disconnect_session(Fixture.SESSION_A, 1), "Session disconnect failed")
	_assert_error(session_store.require_active(Fixture.SESSION_A, 1), "CONSTRUCTION_MULTIPLAYER_SESSION_DISCONNECTED", "Disconnected session remained active")
	var reconnected := session_store.connect_session(Fixture.CLIENT_A, Fixture.SESSION_A, 2, 0); _assert_ok(reconnected, "Session reconnect failed")
	_assert(bool(reconnected["reconnect"]) and int(reconnected["session"]["session_epoch"]) == 2, "Reconnect epoch mismatch")
	_assert_error(session_store.require_active(Fixture.SESSION_A, 1), "CONSTRUCTION_MULTIPLAYER_SESSION_EPOCH_MISMATCH", "Old session epoch remained active")
	var command := Fixture.edit_command(reconnected["session"], 1, "contracts", graph, 0, 5.0)
	_assert_ok(CommandScript.validate(command), "Valid multiplayer command rejected")
	var bad_checksum := command.duplicate(true); bad_checksum["payload"]["failure_mode"] = "BEFORE_COMMIT"
	_assert_error(CommandScript.validate(bad_checksum), "CONSTRUCTION_MULTIPLAYER_COMMAND_CHECKSUM_MISMATCH", "Command accepted checksum tamper")
	var unexpected := command.duplicate(true); unexpected["extra"] = true
	_assert_error(CommandScript.validate(unexpected), "UNEXPECTED_FIELD", "Command accepted unknown field")
	var bundle := BundleScript.create(0, [graph["root"], graph["projection"]], [graph["snapshot"]])
	_assert_ok(BundleScript.validate(bundle), "State bundle rejected")
	_assert(String(bundle["items"][0]["item_instance_id"]) < String(bundle["items"][1]["item_instance_id"]), "State bundle items not sorted")
	var event := EventScript.create(0, command, bundle); _assert_ok(EventScript.validate(event), "Multiplayer event rejected")
	var replica = ReplicaScript.new(); _assert_ok(replica.initialize(bundle, -1), "Replica initialization failed")
	_assert_ok(replica.apply_event(event), "Replica event apply failed")
	_assert(replica.get_last_event_index() == 0 and replica.get_checksum() == String(bundle["checksum"]), "Replica state mismatch")
	var event_replay := replica.apply_event(event); _assert_ok(event_replay, "Replica event replay failed"); _assert(bool(event_replay["replay"]), "Replica replay not marked")
	var gap := EventScript.create(2, command, bundle)
	_assert_error(replica.apply_event(gap), "CONSTRUCTION_MULTIPLAYER_REPLICA_EVENT_GAP", "Replica accepted event gap")
	var tampered_event := event.duplicate(true); tampered_event["state_bundle"]["server_generation"] = 9
	_assert_error(EventScript.validate(tampered_event), "CONSTRUCTION_MULTIPLAYER_STATE_BUNDLE_CHECKSUM_MISMATCH", "Event accepted nested bundle tamper")
	var session_state := session_store.export_state(); _assert_ok(SessionStoreScript.validate_state(session_state), "Session state rejected")
	var restored_sessions = SessionStoreScript.new(); _assert_ok(restored_sessions.load_state(session_state), "Session state restore failed")
	_assert(UtilsScript.canonical_json(restored_sessions.export_state()) == UtilsScript.canonical_json(session_state), "Session state roundtrip changed")

func _assert_ok(result: Dictionary, message: String) -> void: _assert(bool(result.get("success", false)), "%s: %s" % [message, result])
func _assert_error(result: Dictionary, expected: String, message: String) -> void: _assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == expected, "%s: %s" % [message, result])
func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)
func _finish() -> void:
	if failures.is_empty(): print("C12 multiplayer construction contracts: PASS (%d assertions)" % assertions); quit(0); return
	for failure in failures: push_error(failure)
	print("C12 multiplayer construction contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions]); quit(1)
