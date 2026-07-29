extends SceneTree

const ListenHostRuntime = preload("res://scripts/runtime/listen_host/listen_host_runtime.gd")
const PlayableAuthority = preload("res://scripts/runtime/listen_host/playable_listen_host_authority.gd")
const PlayableStateCodec = preload("res://scripts/runtime/listen_host/playable_state_codec.gd")
const ItemGameplayController = preload("res://scripts/items/presentation/item_gameplay_controller.gd")
const EntitySnapshot = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")

var failures: Array[String] = []
var assertions: int = 0
var authority_host: Node
var runtime
var client_session
var replica
var persistence_root: String


func _init() -> void:
	authority_host = Node.new()
	authority_host.name = "H1IntegrationAuthorityHost"
	root.add_child(authority_host)
	persistence_root = "user://h1-playable-integration-%d" % OS.get_process_id()
	_remove_tree(ProjectSettings.globalize_path(persistence_root))
	_test_persistent_playable_vertical()
	_cleanup()
	_finish()


func _test_persistent_playable_vertical() -> void:
	var first: Dictionary = _start_runtime("session/h1/integration/first")
	_assert(bool(first.get("success", false)), "First playable runtime failed: %s" % first)
	if not bool(first.get("success", false)):
		return
	var initial_item_snapshot: Dictionary = runtime.get_playable_snapshot(PlayableAuthority.ITEM_GRAPH_ENTITY_ID)
	_assert(bool(EntitySnapshot.validate(initial_item_snapshot).get("success", false)), "Initial item replica is invalid")
	_assert(_setup_replica(initial_item_snapshot), "Initial item replica controller failed")

	var grant: Dictionary = replica.grant_debug_item("lunar_rock", 12)
	_assert(bool(grant.get("success", false)), "Grant through listen-host failed: %s" % grant)
	_assert(_total_quantity(replica, "lunar_rock") == 12, "Replica quantity after grant is wrong")
	var rocks: Array[String] = _item_ids(replica, "lunar_rock")
	_assert(not rocks.is_empty(), "Granted rock stack missing")
	var move: Dictionary = replica.move_item_quantity_to_container(
		rocks[0], 5, replica.player_hotbar_id, 2, ""
	)
	_assert(bool(move.get("success", false)), "Split/move to hotbar failed: %s" % move)
	_assert(_hotbar_quantity(replica, 2) == 5, "Hotbar split quantity mismatch")
	var select: Dictionary = replica.select_hotbar(2)
	_assert(bool(select.get("success", false)), "Hotbar selection failed")
	_assert(replica.selected_hotbar_index == 2, "Replica selected index mismatch")
	var save: Dictionary = replica.save_graph()
	_assert(bool(save.get("success", false)), "Authority save command failed: %s" % save)

	var report_before: Dictionary = runtime.get_playable_report()
	var authority_item_checksum: String = String(report_before.get("authority", {}).get("item_checksum", ""))
	var client_item_checksum: String = String(report_before.get("item_replica", {}).get("checksum", ""))
	_assert(not authority_item_checksum.is_empty(), "Authority item checksum missing")
	_assert(authority_item_checksum == client_item_checksum, "Authority/client item checksums differ")
	_assert(int(report_before.get("item_bridge", {}).get("commands_sent", 0)) >= 4, "Item commands did not cross bridge")
	_assert(int(report_before.get("item_bridge", {}).get("deltas_applied", 0)) >= 3, "Item deltas were not applied")

	var first_player: Dictionary = PlayableStateCodec.create_player_state(
		Vector3(0.5, 1737401.0, 0.0), Basis(Vector3.UP, 0.1), Vector3(1.0, 0.0, 0.0),
		Vector3(0.5, 0.0, 0.0), "lunar_humanoid", "third_person", true, 1,
		"body/moon/fixed", "main", "moon", "h1-integration", 0.1
	)
	var movement: Dictionary = client_session.submit_player_state(
		first_player, 0.1, "operation/h1/integration/player/1"
	)
	_assert(bool(movement.get("success", false)), "Player movement command failed: %s" % movement)
	var player_snapshot: Dictionary = runtime.get_playable_snapshot(PlayableAuthority.PLAYER_ENTITY_ID)
	_assert(int(player_snapshot.get("state_revision", -1)) == 1, "Player replica revision mismatch")
	_assert(bool(player_snapshot.get("domain_components", {}).get("player_state", {}).get("flashlight_enabled", false)), "Flashlight state was not replicated")

	var retained_bridge = client_session.get_item_bridge()
	var retained_session = client_session
	var detach: Dictionary = runtime.detach_playable_world()
	_assert(bool(detach.get("success", false)), "First playable detach failed: %s" % detach)
	var after_disconnect: Dictionary = retained_bridge.submit_item_command(
		"item.save", {}, "operation/h1/integration/disconnected"
	)
	_assert(String(after_disconnect.get("error_code", "")) == "PLAYABLE_BRIDGE_NOT_CONFIGURED", "Disconnected bridge still accepted commands")
	var client_after_disconnect: Dictionary = retained_session.submit_player_state(
		first_player, 0.1, "operation/h1/integration/disconnected-client"
	)
	_assert(String(client_after_disconnect.get("error_code", "")) == "PLAYABLE_CLIENT_SESSION_NOT_CONFIGURED", "Detached client session accepted player command")
	var player_after_disconnect: Dictionary = runtime.submit_player_state(
		first_player, 0.1, "operation/h1/integration/disconnected-player"
	)
	_assert(String(player_after_disconnect.get("error_code", "")) == "PLAYABLE_WORLD_NOT_ATTACHED", "Detached runtime accepted player command")
	_free_replica()

	var second: Dictionary = _attach_playable("session/h1/integration/second")
	_assert(bool(second.get("success", false)), "Restarted playable authority failed: %s" % second)
	if not bool(second.get("success", false)):
		return
	var restored_snapshot: Dictionary = runtime.get_playable_snapshot(PlayableAuthority.ITEM_GRAPH_ENTITY_ID)
	_assert(_setup_replica(restored_snapshot), "Restored replica controller failed")
	_assert(_total_quantity(replica, "lunar_rock") == 12, "Restart lost granted item quantity")
	_assert(_hotbar_quantity(replica, 2) == 5, "Restart lost split hotbar stack")
	_assert(replica.selected_hotbar_index == 2, "Restart lost selected hotbar index")
	_assert(String(replica.runtime_mode) == ItemGameplayController.RUNTIME_MODE_REPLICA, "Restored client escaped replica mode")
	var restored_report: Dictionary = runtime.get_playable_report()
	_assert(int(restored_report.get("authority", {}).get("presentation_objects", -1)) == 0, "Restarted authority created presentation")
	_assert(bool(restored_report.get("authority", {}).get("item_graph_valid", false)), "Restored authoritative graph is invalid")
	_assert(int(restored_report.get("client_runtime", {}).get("replica_store", {}).get("snapshot_count", 0)) == 2, "Client did not receive both initial replicas")
	_assert(String(restored_report.get("authority", {}).get("item_checksum", "")) == String(restored_report.get("item_replica", {}).get("checksum", "")), "Restored authority/client checksums differ")


func _start_runtime(session_id: String) -> Dictionary:
	runtime = ListenHostRuntime.new()
	var setup: Dictionary = runtime.setup({
		"authority_host": authority_host,
		"authority_owner_id": "h1-integration-host",
		"authority_epoch": 1,
		"server_tick": 0,
		"session_id": "session/h0/integration-compat",
	})
	if not bool(setup.get("success", false)):
		return setup
	return _attach_playable(session_id)


func _attach_playable(session_id: String) -> Dictionary:
	var attach_result: Dictionary = runtime.attach_playable_world({
		"authority_owner_id": "h1-integration-host",
		"authority_epoch": 1,
		"server_tick": 0,
		"session_id": session_id,
		"universe_id": "main",
		"instance_id": "h1-integration",
		"space_id": "moon",
		"frame_id": "body/moon/fixed",
		"player_state": PlayableStateCodec.create_player_state(
			Vector3(0.0, 1737401.0, 0.0), Basis.IDENTITY, Vector3.ZERO,
			Vector3.ZERO, "lunar_humanoid", "first_person", false, 0,
			"body/moon/fixed", "main", "moon", "h1-integration", 0.0
		),
		"item_persistence_enabled": true,
		"item_persistence_root": persistence_root,
		"item_profile_id": "playground",
		"item_state_key": "h1-persistent-items",
		"include_demo_world": false,
	})
	if bool(attach_result.get("success", false)):
		client_session = runtime.get_playable_client_session()
	return attach_result


func _setup_replica(snapshot: Dictionary) -> bool:
	_free_replica()
	var graph_value = snapshot.get("domain_components", {}).get("item_graph", {})
	if not graph_value is Dictionary or Dictionary(graph_value).is_empty():
		return false
	replica = ItemGameplayController.new()
	root.add_child(replica)
	var result: Dictionary = replica.setup_runtime(
		null, null, null, null,
		"body/moon/fixed", "moon-local", "h1-client-replica", "playground", false,
		{
			"mode": ItemGameplayController.RUNTIME_MODE_REPLICA,
			"initial_graph_snapshot": Dictionary(graph_value),
			"replica_revision": int(snapshot.get("state_revision", -1)),
			"replica_checksum": String(snapshot.get("checksum", "")),
			"network_command_bridge": client_session.get_item_bridge(),
			"persistence_enabled": false,
			"presentation_enabled": false,
		}
	)
	return bool(result.get("success", false))


func _item_ids(controller, definition_id: String) -> Array[String]:
	var ids: Array[String] = []
	for item in controller.domain.items.all_items():
		if String(item.definition_id) == definition_id:
			ids.append(String(item.instance_id))
	ids.sort()
	return ids


func _total_quantity(controller, definition_id: String) -> int:
	var total: int = 0
	for item in controller.domain.items.all_items():
		if String(item.definition_id) == definition_id:
			total += int(item.quantity)
	return total


func _hotbar_quantity(controller, slot_index: int) -> int:
	var hotbar = controller.get_container(controller.player_hotbar_id)
	if hotbar == null:
		return 0
	var item_id: String = String(hotbar.get_item_at_slot(slot_index))
	var item = controller.get_item(item_id)
	return int(item.quantity) if item != null else 0


func _free_replica() -> void:
	if replica != null and is_instance_valid(replica):
		if replica.get_parent() != null:
			replica.get_parent().remove_child(replica)
		replica.free()
	replica = null


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		var child := path.path_join(name)
		if directory.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
		name = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)


func _cleanup() -> void:
	_free_replica()
	if runtime != null:
		runtime.detach_playable_world()
		runtime = null
	client_session = null
	if authority_host != null and is_instance_valid(authority_host):
		authority_host.queue_free()
	_remove_tree(ProjectSettings.globalize_path(persistence_root))


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("H1 playable listen-host integration: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("H1 playable listen-host integration: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
