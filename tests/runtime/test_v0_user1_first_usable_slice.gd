extends SceneTree

const ProductShell = preload("res://scripts/ui/product_shell.gd")
const Journey = preload("res://scripts/ui/user1_journey_overlay.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_host_identity_preferences()
	_test_host_join_arguments_stay_bounded()
	_test_dual_stack_port_preflight()
	_test_journey_progression()
	_test_journey_ui()
	for failure in failures:
		push_error(failure)
	print("USER1 FIRST USABLE SLICE: %d assertions, %d failures" % [
		assertions,
		failures.size(),
	])
	quit(0 if failures.is_empty() else 1)


func _test_host_identity_preferences() -> void:
	var prefs := ProductShell.normalize_preferences({
		"default_player_name": "join-player",
		"last_host_player_name": "host-player",
		"default_port": 24580,
		"last_server_address": "127.0.0.1",
		"last_hosted_world": "earth",
		"last_persistence_slot": "warehouse-a",
		"has_host_history": true,
		"last_mode": "join",
	})
	_check(
		String(prefs.get("default_player_name", "")) == "join-player",
		"Join/default identity remains independent"
	)
	_check(
		String(prefs.get("last_host_player_name", "")) == "host-player",
		"Continue retains the last Host identity"
	)
	_check(
		String(prefs.get("last_persistence_slot", "")) == "warehouse-a",
		"Continue retains hosted persistence slot"
	)


func _test_host_join_arguments_stay_bounded() -> void:
	var host := ProductShell.build_host_user_args("earth", 24580, "warehouse-a")
	var client := ProductShell.build_join_user_args("127.0.0.1", 24580, "host-player")
	_check(host.has("--role=dedicated-server"), "USER1 host remains dedicated-server")
	_check(host.has("--network-mvp"), "USER1 host remains network-mvp")
	_check(host.has("--product-seam"), "USER1 Host enables the product seam bridge")
	_check(host.has("--instance-id=warehouse-a"), "USER1 host keeps LIVE.3 instance slot")
	_check(not _contains_prefix(host, "--persistence-root="), "USER1 host invents no persistence root")
	_check(client.has("--role=game-client"), "USER1 player remains game-client")
	_check(client.has("--player-identity=host-player"), "USER1 Continue can relaunch the same host player")
	_check(not _contains_prefix(client, "--persistence-root="), "USER1 client owns no persistence root")


func _test_dual_stack_port_preflight() -> void:
	if not OS.has_feature("windows"):
		_check(true, "dual-stack preflight is Windows-specific")
		return
	var port := 31000 + (OS.get_process_id() % 1000)
	var holder := PacketPeerUDP.new()
	var bind_error := holder.bind(port, "::")
	if bind_error != OK:
		_check(true, "Windows host has no IPv6 wildcard bind for falsifier")
		holder.close()
		return
	var shell = ProductShell.new()
	_check(
		not shell._udp_port_available(port),
		"Product Shell rejects a port already owned through IPv6 wildcard"
	)
	shell.free()
	holder.close()


func _test_journey_progression() -> void:
	var overlay = Journey.new()
	get_root().add_child(overlay)
	var player := "user1-test-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var initial := _state(player)
	overlay._player_id = player
	overlay._save_path = overlay._save_path_for_player(player)
	overlay._load_or_initialize(initial)
	overlay._accept_state(initial)
	_check(_done(overlay, "connected"), "journey marks connected")
	_check(not _done(overlay, "second_player"), "journey waits for second player")

	var state := initial.duplicate(true)
	state["remote_player_count"] = 1
	state["position"] = {"x": 1.5, "y": 0.0, "z": 0.0}
	overlay._accept_state(state)
	_check(_done(overlay, "second_player"), "journey observes second client")
	_check(_done(overlay, "move"), "journey observes canonical movement")

	state["region_id"] = "region/user1/a"
	state["seam_roundtrips"] = 1
	state["nearest_resource_distance_m"] = 4.0
	state["mining_tool_equipped"] = true
	overlay._accept_state(state)
	_check(_done(overlay, "seam"), "journey requires a real A→B→A seam roundtrip")
	_check(_done(overlay, "resource_near"), "journey observes nearby resource")
	_check(_done(overlay, "tool_equipped"), "journey observes equipped mining tool")

	state["resource_generation"] = 2
	state["inventory_ore_quantity"] = 1
	overlay._accept_state(state)
	_check(_done(overlay, "mined"), "journey observes canonical ResourceMining advance")
	_check(_done(overlay, "material_received"), "journey observes canonical ore output")

	state["world_item_count"] = 3
	overlay._accept_state(state)
	_check(not _done(overlay, "pickup_drop"), "pickup alone does not satisfy pickup/drop step")
	state["world_item_count"] = 4
	overlay._accept_state(state)
	_check(_done(overlay, "pickup_drop"), "journey observes pickup then world drop")

	state["open_container_id"] = "container/shared/crate/1"
	overlay._accept_state(state)
	_check(_done(overlay, "container_open"), "journey observes shared container open")
	state["shared_container_item_count"] = 1
	overlay._accept_state(state)
	_check(_done(overlay, "container_share"), "journey observes item transferred into shared container")

	state["construction_generation"] = 1
	overlay._accept_state(state)
	_check(_done(overlay, "construction"), "journey observes Construction generation advance")
	_check(
		String(overlay.get_report().get("next_step_id", "")) == "client_reconnect",
		"journey next gate is real client restart after gameplay slice"
	)

	var path := String(overlay.get_report().get("save_path", ""))
	overlay.free()
	if not path.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_journey_ui() -> void:
	var overlay = Journey.new()
	get_root().add_child(overlay)
	var setup := overlay.setup(Callable(self, "_empty_state"))
	_check(bool(setup.get("success", false)), "USER1 journey UI accepts read-only provider")
	_check(overlay.find_child("USER1JourneyRoot", true, false) != null, "USER1 journey root exists")
	_check(overlay.find_child("USER1JourneyPanel", true, false) != null, "USER1 journey panel exists")
	_check(Journey.STEP_DEFINITIONS.size() == 14, "USER1 journey exposes the full bounded route")
	overlay.free()


func _state(player: String) -> Dictionary:
	return {
		"schema": Journey.STATE_SCHEMA,
		"connection_state": "CONNECTED",
		"player_id": player,
		"ownership_epoch": 1,
		"position": {"x": 0.0, "y": 0.0, "z": 0.0},
		"region_id": "region/user1/a",
		"seam_active_authority_id": "authority/test/a",
		"seam_authority_epoch": 1,
		"seam_crossings": 0,
		"seam_roundtrips": 0,
		"remote_player_count": 0,
		"nearest_resource_distance_m": 12.0,
		"resource_generation": 1,
		"mining_tool_equipped": false,
		"inventory_ore_quantity": 0,
		"item_graph_revision": 1,
		"world_item_count": 4,
		"open_container_id": "",
		"shared_container_item_count": 0,
		"construction_generation": 0,
		"construct_count": 0,
		"inventory_visible": false,
		"build_mode": false,
	}


func _empty_state() -> Dictionary:
	return {}


func _done(overlay, step_id: String) -> bool:
	return bool(Dictionary(overlay.get_report().get("completed", {})).get(step_id, false))


func _contains_prefix(values: PackedStringArray, prefix: String) -> bool:
	for value in values:
		if String(value).begins_with(prefix):
			return true
	return false


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
