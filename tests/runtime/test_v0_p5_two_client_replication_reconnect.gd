extends SceneTree

const GameplayP5 = preload(
	"res://scripts/runtime/networked_gameplay/p5/networked_gameplay_service_p5.gd"
)
const CanonicalItemGraphDelta = preload(
	"res://scripts/runtime/networked_gameplay/contracts/canonical_item_graph_delta.gd"
)
const ItemProjection = preload(
	"res://scripts/runtime/networked_gameplay/m5/m4_item_graph_ui_projection.gd"
)

const PLAYER_A := "a"
const PLAYER_B := "b"
const SESSION_A1 := "transport-session/p5/a/1"
const SESSION_B1 := "transport-session/p5/b/1"
const SESSION_A2 := "transport-session/p5/a/2"
const SLOT := "tool/main"
const TOOL_DEFINITION := "item/tool/mining"

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_two_client_replication_and_reconnect()
	_finish()


func _test_two_client_replication_and_reconnect() -> void:
	var service = GameplayP5.new()
	_assert_success(service.setup("authority/p5/replication", 1, 0, {
		"profile": "MULTIPLAYER_CORE",
		"topology_adapter": "ENET",
		"region_id": "region/p5/replication",
		"playable_sandbox": true,
	}), "P5 gameplay configures")
	var join_a: Dictionary = service.join(PLAYER_A, SESSION_A1, "operation/p5/repl/join-a")
	var join_b: Dictionary = service.join(PLAYER_B, SESSION_B1, "operation/p5/repl/join-b")
	_assert_success(join_a, "player A joins")
	_assert_success(join_b, "player B joins")
	if not bool(join_a.get("success", false)) or not bool(join_b.get("success", false)):
		return
	var epoch_a := int(service.get_player(PLAYER_A).get("ownership_epoch", 0))
	_assert(epoch_a == 1, "player A starts on ownership epoch 1")

	var graph = service.get_canonical_item_graph_port()
	_assert(graph != null, "P5 exposes the single canonical Item Graph port")
	if graph == null:
		return
	var tool_output: Dictionary = graph.apply_server_output(
		"operation/p5/repl/tool-output-a",
		PLAYER_A,
		TOOL_DEFINITION,
		1,
		"source/p5/replication-test"
	)
	_assert_success(tool_output, "server provisions one canonical mining tool")
	var tool_id := String(tool_output.get("details", {}).get("output_item_id", ""))
	_assert(not tool_id.is_empty(), "provisioned tool has stable canonical item id")

	var before: Dictionary = service.create_canonical_item_graph_snapshot()
	var client_a = ItemProjection.new()
	var client_b = ItemProjection.new()
	_assert_success(client_a.accept_snapshot(before), "client A accepts pre-equip canonical snapshot")
	_assert_success(client_b.accept_snapshot(before), "client B accepts pre-equip canonical snapshot")
	_assert(_equipped_item(client_a.get_snapshot(), PLAYER_A, SLOT).is_empty(), "client A initially sees no equipped tool")
	_assert(_equipped_item(client_b.get_snapshot(), PLAYER_A, SLOT).is_empty(), "client B initially sees no equipped tool")

	var equip: Dictionary = service.handle_canonical_item_command(
		PLAYER_A,
		SESSION_A1,
		epoch_a,
		"operation/p5/repl/equip-a",
		"item.equip",
		{"item_id": tool_id, "slot_id": SLOT}
	)
	_assert_success(equip, "server-authoritative equip succeeds")
	var after: Dictionary = service.create_canonical_item_graph_snapshot()
	_assert(int(after.get("revision", -1)) == int(before.get("revision", -2)) + 1, "equip advances canonical Item Graph once")

	var delta_result: Dictionary = CanonicalItemGraphDelta.create(before, after)
	_assert_success(delta_result, "canonical Item Graph delta serializes equipment relation")
	if not bool(delta_result.get("success", false)):
		return
	var delta: Dictionary = Dictionary(delta_result.get("details", {}).get("delta", {}))
	var replica_a_result: Dictionary = CanonicalItemGraphDelta.apply(client_a.get_snapshot(), delta)
	var replica_b_result: Dictionary = CanonicalItemGraphDelta.apply(client_b.get_snapshot(), delta)
	_assert_success(replica_a_result, "client A applies equipment delta")
	_assert_success(replica_b_result, "client B applies equipment delta")
	if not bool(replica_a_result.get("success", false)) or not bool(replica_b_result.get("success", false)):
		return
	_assert_success(client_a.accept_snapshot(Dictionary(replica_a_result.get("details", {}).get("snapshot", {}))), "client A commits equipment replica")
	_assert_success(client_b.accept_snapshot(Dictionary(replica_b_result.get("details", {}).get("snapshot", {}))), "client B commits equipment replica")
	var replica_a: Dictionary = client_a.get_snapshot()
	var replica_b: Dictionary = client_b.get_snapshot()
	_assert(String(replica_a.get("checksum", "")) == String(after.get("checksum", "")), "client A checksum converges to authority")
	_assert(String(replica_b.get("checksum", "")) == String(after.get("checksum", "")), "client B checksum converges to authority")
	_assert(replica_a == replica_b, "two independent client replicas converge exactly")
	_assert(String(_equipped_item(replica_a, PLAYER_A, SLOT).get("item_id", "")) == tool_id, "client A sees exact equipped item identity")
	_assert(String(_equipped_item(replica_b, PLAYER_A, SLOT).get("item_id", "")) == tool_id, "remote client B sees exact equipped item identity")
	_assert(_count_item_id(replica_a, tool_id) == 1, "client A contains one canonical tool identity")
	_assert(_count_item_id(replica_b, tool_id) == 1, "client B contains one canonical tool identity")
	_assert(_inventory_reference_count(replica_a, PLAYER_A, tool_id) == 1, "equipped tool remains exactly once in owner inventory")

	var durable: Dictionary = service.export_durable_state()
	var replay: Dictionary = service.export_replay_state()
	_assert_success(service.validate_durable_state(durable), "P5 aggregate durable state validates with equipment relation")
	_assert_success(service.validate_replay_state(replay), "P5 aggregate replay state validates")

	var restored = GameplayP5.new()
	_assert_success(restored.restore_durable_state(durable), "fresh P5 aggregate restores durable equipment state")
	_assert_success(restored.restore_replay_state(replay), "fresh P5 aggregate restores replay ledgers")
	var restored_snapshot: Dictionary = restored.create_canonical_item_graph_snapshot()
	_assert(String(restored_snapshot.get("checksum", "")) == String(after.get("checksum", "")), "restored Item Graph checksum matches pre-disconnect authority")
	_assert(String(_equipped_item(restored_snapshot, PLAYER_A, SLOT).get("item_id", "")) == tool_id, "restored aggregate preserves exact equipped item")
	_assert(_count_item_id(restored_snapshot, tool_id) == 1, "restored aggregate contains no duplicate tool identity")
	_assert(_inventory_reference_count(restored_snapshot, PLAYER_A, tool_id) == 1, "restored aggregate keeps one inventory reference")

	var reconnect_projection = ItemProjection.new()
	_assert_success(reconnect_projection.accept_snapshot(restored_snapshot), "fresh reconnect client accepts canonical restored snapshot")
	_assert(String(_equipped_item(reconnect_projection.get_snapshot(), PLAYER_A, SLOT).get("item_id", "")) == tool_id, "reconnect client reconstructs exact equipment relation")

	var rejoin_a: Dictionary = restored.join(PLAYER_A, SESSION_A2, "operation/p5/repl/rejoin-a")
	_assert_success(rejoin_a, "player A rejoins recovered aggregate with new transport session")
	if not bool(rejoin_a.get("success", false)):
		return
	var epoch_a2 := int(restored.get_player(PLAYER_A).get("ownership_epoch", 0))
	_assert(epoch_a2 > epoch_a, "reconnect advances ownership epoch")
	_assert(String(restored.get_player(PLAYER_A).get("player_entity_id", "")) == String(service.get_player(PLAYER_A).get("player_entity_id", "")), "reconnect preserves canonical player entity")
	_assert(String(_equipped_item(restored.create_canonical_item_graph_snapshot(), PLAYER_A, SLOT).get("item_id", "")) == tool_id, "rejoin does not mutate equipped relation")

	var before_unequip: Dictionary = restored.create_canonical_item_graph_snapshot()
	var unequip: Dictionary = restored.handle_canonical_item_command(
		PLAYER_A,
		SESSION_A2,
		epoch_a2,
		"operation/p5/repl/unequip-a",
		"item.unequip",
		{"item_id": tool_id, "slot_id": SLOT}
	)
	_assert_success(unequip, "reconnected owner can unequip exact canonical tool")
	var after_unequip: Dictionary = restored.create_canonical_item_graph_snapshot()
	var unequip_delta_result: Dictionary = CanonicalItemGraphDelta.create(before_unequip, after_unequip)
	_assert_success(unequip_delta_result, "unequip serializes through the same canonical delta codec")
	if bool(unequip_delta_result.get("success", false)):
		var reconnect_delta: Dictionary = Dictionary(unequip_delta_result.get("details", {}).get("delta", {}))
		var reconnect_replica_result: Dictionary = CanonicalItemGraphDelta.apply(reconnect_projection.get_snapshot(), reconnect_delta)
		_assert_success(reconnect_replica_result, "reconnect client applies unequip delta")
		if bool(reconnect_replica_result.get("success", false)):
			_assert_success(reconnect_projection.accept_snapshot(Dictionary(reconnect_replica_result.get("details", {}).get("snapshot", {}))), "reconnect client commits unequip replica")
			_assert(_equipped_item(reconnect_projection.get_snapshot(), PLAYER_A, SLOT).is_empty(), "reconnect client sees equipment relation removed")
	_assert(_count_item_id(after_unequip, tool_id) == 1, "unequip keeps one canonical tool identity")
	_assert(_inventory_reference_count(after_unequip, PLAYER_A, tool_id) == 1, "unequip keeps one canonical inventory reference")


func _equipped_item(snapshot: Dictionary, player_id: String, slot_id: String) -> Dictionary:
	for item_value in snapshot.get("items", []):
		if not item_value is Dictionary:
			continue
		var item: Dictionary = item_value
		var equipment_value = item.get("equipment", null)
		if not equipment_value is Dictionary:
			continue
		var equipment: Dictionary = equipment_value
		if String(equipment.get("player_id", "")) == player_id and String(equipment.get("slot_id", "")) == slot_id:
			return item.duplicate(true)
	return {}


func _count_item_id(snapshot: Dictionary, item_id: String) -> int:
	var count := 0
	for item_value in snapshot.get("items", []):
		if item_value is Dictionary and String(item_value.get("item_id", "")) == item_id:
			count += 1
	return count


func _inventory_reference_count(snapshot: Dictionary, player_id: String, item_id: String) -> int:
	var inventory: Dictionary = Dictionary(snapshot.get("inventories", {}).get(player_id, {}))
	var count := 0
	for value in inventory.get("inventory", []):
		if String(value) == item_id:
			count += 1
	return count


func _assert_success(result: Dictionary, label: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [label, String(result.get("error_code", ""))])


func _assert(condition: bool, label: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % label)
		return
	failures.append(label)
	push_error("FAIL: %s" % label)


func _finish() -> void:
	print("V0-P5 two-client replication/reconnect: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
