class_name QuaterniusPlayableNetworkEquipmentLab
extends "res://scripts/characters/lab/quaternius_item_graph_equipment_lab.gd"

const NetworkGameplayControllerType = preload("res://scripts/characters/equipment/network_character_equipment_gameplay_controller.gd")
const NetworkBridgeType = preload("res://scripts/runtime/networked_gameplay/ch9/ch9_3_network_item_command_bridge.gd")
const PersistentServerType = preload("res://scripts/runtime/networked_gameplay/ch9/ch9_5_persistent_dedicated_server_runtime.gd")
const GraphicalClientType = preload("res://scripts/runtime/networked_gameplay/ch9/ch9_3_graphical_client_runtime.gd")
const NetworkEquipmentCatalog = preload("res://scripts/characters/equipment/network_character_equipment_catalog.gd")
const NetworkEquipmentSourceType = preload("res://scripts/characters/equipment/item_graph_equipment_source.gd")
const NetworkEquipmentOperationsType = preload("res://scripts/characters/equipment/character_equipment_operation_service.gd")
const NetworkEquipmentInventoryUIType = preload("res://scripts/items/presentation/character_equipment_inventory_ui.gd")

const LOGICAL_PLAYER_ID := "a"
const DEFAULT_PORT := 39965
const READY_TIMEOUT_MS := 15000
const CLI_RESET_STATE := "--ch9-6-reset-state"
const CLI_PORT_PREFIX := "--ch9-6-port="
const PERSISTENCE_USER_PATH := "user://ch9-6-playable-network-equipment-lab"

var network_server
var network_client
var network_bridge
var network_ready: bool = false
var network_setup_in_progress: bool = false
var network_port: int = DEFAULT_PORT
var network_persistence_root: String = ""
var last_network_projection_result: Dictionary = {}


# QuaterniusItemGraphEquipmentLab calls this virtual method from its accepted
# _ready() path after CH8 presentation has been constructed. CH9.6 deliberately
# defers Item Graph setup because an actual ENet client must finish handshake and
# JOIN before its authoritative canonical Item Graph can seed the replica UI.
func _setup_item_graph_inventory_composition() -> void:
	ch9_setup_result = {
		"success": false,
		"code": "CH9_6_NETWORK_BOOTSTRAP_PENDING",
	}
	call_deferred("_begin_network_bootstrap")


func _begin_network_bootstrap() -> void:
	if network_setup_in_progress or network_ready:
		return
	network_setup_in_progress = true
	network_port = _resolve_port()
	network_persistence_root = ProjectSettings.globalize_path(PERSISTENCE_USER_PATH)
	if CLI_RESET_STATE in OS.get_cmdline_user_args():
		_remove_persistence_tree(network_persistence_root)

	network_server = PersistentServerType.new()
	network_server.name = "CH9_6PersistentEquipmentServer"
	add_child(network_server)
	var server_setup: Dictionary = network_server.setup({
		"host": "127.0.0.1",
		"port": network_port,
		"authority_owner_id": "simulation/ch9-6/playable-lab",
		"authority_epoch": 1,
		"persistence_root": network_persistence_root,
		"playable_sandbox": true,
		"automated_acceptance": false,
	})
	if not bool(server_setup.get("success", false)):
		_fail_network_setup("CH9_6_SERVER_SETUP_FAILED", server_setup)
		return

	network_client = GraphicalClientType.new()
	network_client.name = "CH9_6LocalEquipmentClient"
	add_child(network_client)
	var client_setup: Dictionary = network_client.setup({
		"host": "127.0.0.1",
		"port": network_port,
		"logical_player_id": LOGICAL_PLAYER_ID,
		"playable_sandbox": true,
		"automated_acceptance": false,
		"connect_timeout_ms": READY_TIMEOUT_MS,
		"command_timeout_ms": READY_TIMEOUT_MS,
	})
	if not bool(client_setup.get("success", false)):
		_fail_network_setup("CH9_6_CLIENT_SETUP_FAILED", client_setup)
		return

	var ready: bool = await _wait_for_client_ready(READY_TIMEOUT_MS)
	if not ready:
		_fail_network_setup("CH9_6_CLIENT_READY_TIMEOUT", network_client.get_report())
		return

	network_bridge = NetworkBridgeType.new()
	var bridge_setup: Dictionary = network_bridge.setup(
		network_client,
		LOGICAL_PLAYER_ID,
		Callable(self, "_selected_item_id_for_bridge")
	)
	if not bool(bridge_setup.get("success", false)):
		_fail_network_setup("CH9_6_BRIDGE_SETUP_FAILED", bridge_setup)
		return

	var canonical_snapshot: Dictionary = network_client.get_item_graph_snapshot()
	var converted: Dictionary = network_bridge.convert_snapshot(canonical_snapshot)
	if not bool(converted.get("success", false)):
		_fail_network_setup("CH9_6_INITIAL_REPLICA_CONVERSION_FAILED", converted)
		return
	var initial_graph: Dictionary = Dictionary(converted.get("details", {}).get("graph_snapshot", {})).duplicate(true)
	if initial_graph.is_empty():
		_fail_network_setup("CH9_6_INITIAL_REPLICA_GRAPH_EMPTY", converted)
		return

	character_gameplay_controller = NetworkGameplayControllerType.new()
	character_gameplay_controller.name = "CH9_6NetworkCharacterEquipmentGameplayController"
	add_child(character_gameplay_controller)
	var runtime_setup: Dictionary = character_gameplay_controller.setup_runtime(
		player,
		self,
		self,
		null,
		"scenario/local",
		"",
		"ch9-6-network-character-equipment-lab",
		"ch9-6-network-character-equipment-lab",
		false,
		{
			"mode": "replica",
			"network_command_bridge": network_bridge,
			"initial_graph_snapshot": initial_graph,
			"persistence_enabled": false,
			"presentation_enabled": false,
			"include_demo_world": false,
		}
	)
	if not bool(runtime_setup.get("success", false)):
		_fail_network_setup("CH9_6_REPLICA_CONTROLLER_SETUP_FAILED", runtime_setup)
		return

	var equipment_container_id: String = NetworkEquipmentCatalog.equipment_container_id(LOGICAL_PLAYER_ID)
	item_graph_equipment_source = NetworkEquipmentSourceType.new()
	var source_setup: Dictionary = item_graph_equipment_source.setup(
		NetworkEquipmentCatalog.owner_entity_id(LOGICAL_PLAYER_ID),
		equipment_container_id,
		NetworkEquipmentCatalog.layout(),
		character_gameplay_controller.domain.items,
		character_gameplay_controller.domain.containers,
		NetworkEquipmentCatalog.slot_profile_ids(),
		NetworkEquipmentCatalog.profiles()
	)
	if not bool(source_setup.get("success", false)):
		_fail_network_setup("CH9_6_EQUIPMENT_SOURCE_SETUP_FAILED", source_setup)
		return

	equipment_operation_service = NetworkEquipmentOperationsType.new()
	var operations_setup: Dictionary = equipment_operation_service.setup(
		NetworkEquipmentCatalog.owner_entity_id(LOGICAL_PLAYER_ID),
		equipment_container_id,
		item_graph_equipment_source,
		character_gameplay_controller.domain.items,
		character_gameplay_controller.domain.containers,
		character_gameplay_controller.domain.transfer
	)
	if not bool(operations_setup.get("success", false)):
		_fail_network_setup("CH9_6_EQUIPMENT_OPERATIONS_SETUP_FAILED", operations_setup)
		return

	equipment_source = item_graph_equipment_source
	var equipment_binding: Dictionary = character_gameplay_controller.configure_character_equipment(
		equipment_container_id,
		item_graph_equipment_source,
		equipment_operation_service,
		equipment_presenter,
		body_suppression_coordinator,
		body_topology_coordinator
	)
	if not bool(equipment_binding.get("success", false)):
		_fail_network_setup("CH9_6_EQUIPMENT_PRESENTATION_BINDING_FAILED", equipment_binding)
		return

	_populate_replica_wearable_ids()
	character_inventory_ui = NetworkEquipmentInventoryUIType.new()
	character_inventory_ui.name = "CH9_6NetworkCharacterEquipmentInventoryUI"
	character_gameplay_controller.add_child(character_inventory_ui)
	character_gameplay_controller.inventory_ui = character_inventory_ui
	character_inventory_ui.setup(character_gameplay_controller, "component", "planet_default")
	character_gameplay_controller.set_inventory_visible(true)

	if not network_bridge.projected_item_graph_updated.is_connected(_on_projected_item_graph_updated):
		network_bridge.projected_item_graph_updated.connect(_on_projected_item_graph_updated)

	network_ready = true
	network_setup_in_progress = false
	ch9_setup_result = {
		"success": true,
		"code": "OK",
		"logical_player_id": LOGICAL_PLAYER_ID,
		"equipment_container_id": equipment_container_id,
		"port": network_port,
		"persistence_root": network_persistence_root,
		"recovered": bool(server_setup.get("details", {}).get("recovered", false)),
		"network_mutation_enabled": true,
		"wearable_item_ids_by_slot": equipment_item_ids_by_slot.duplicate(true),
	}
	_refresh_status()


func _on_projected_item_graph_updated(projected_canonical_snapshot: Dictionary) -> void:
	if character_gameplay_controller == null or network_bridge == null:
		return
	var converted: Dictionary = network_bridge.convert_snapshot(projected_canonical_snapshot)
	if not bool(converted.get("success", false)):
		last_network_projection_result = converted.duplicate(true)
		return
	var details: Dictionary = Dictionary(converted.get("details", {}))
	var replica_graph: Dictionary = Dictionary(details.get("graph_snapshot", {})).duplicate(true)
	var applied: Dictionary = character_gameplay_controller.apply_network_graph_snapshot(
		replica_graph,
		int(details.get("canonical_revision", -1)),
		String(details.get("canonical_checksum", ""))
	)
	if not bool(applied.get("success", false)):
		last_network_projection_result = applied.duplicate(true)
		return
	var presentation: Dictionary = character_gameplay_controller.synchronize_character_equipment_presentation()
	last_network_projection_result = presentation.duplicate(true)
	_populate_replica_wearable_ids()
	_refresh_status()


func _populate_replica_wearable_ids() -> void:
	equipment_item_ids_by_slot.clear()
	if network_bridge == null:
		return
	var adapter = network_bridge.get_adapter()
	if adapter == null:
		return
	for spec in NetworkEquipmentCatalog.wearable_specs():
		var slot_index: int = int(spec.get("slot_index", -1))
		var suffix: String = String(spec.get("suffix", ""))
		var canonical_id: String = "item/player/%s/wearable/%s" % [LOGICAL_PLAYER_ID, suffix]
		var replica_id: String = String(adapter.to_replica_item_id(canonical_id))
		if slot_index >= 0 and not replica_id.is_empty():
			equipment_item_ids_by_slot[slot_index] = replica_id


func _selected_item_id_for_bridge() -> String:
	if character_gameplay_controller == null:
		return ""
	return character_gameplay_controller.get_selected_hotbar_item_id()


func get_canonical_wearable_item_id(slot_index: int) -> String:
	if network_bridge == null:
		return ""
	var replica_id: String = get_wearable_item_id(slot_index)
	return String(network_bridge.get_adapter().to_canonical_item_id(replica_id))


func get_network_debug_snapshot() -> Dictionary:
	return {
		"schema": "planet_simulator.ch9_6_playable_network_equipment_lab.v1",
		"network_ready": network_ready,
		"setup": ch9_setup_result.duplicate(true),
		"server": network_server.get_report() if network_server != null else {},
		"client": network_client.get_report() if network_client != null else {},
		"bridge": network_bridge.get_report() if network_bridge != null else {},
		"controller": character_gameplay_controller.create_character_equipment_debug_snapshot() if character_gameplay_controller != null else {},
		"last_projection": last_network_projection_result.duplicate(true),
	}


func _wait_for_client_ready(timeout_ms: int) -> bool:
	var started_ms: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_ms <= timeout_ms:
		if network_client != null and network_client.is_ready():
			return true
		await get_tree().process_frame
	return false


func _resolve_port() -> int:
	for raw_argument in OS.get_cmdline_user_args():
		var argument: String = String(raw_argument)
		if argument.begins_with(CLI_PORT_PREFIX):
			var raw_port: String = argument.substr(CLI_PORT_PREFIX.length()).strip_edges()
			if raw_port.is_valid_int():
				return clampi(raw_port.to_int(), 1024, 65535)
	return DEFAULT_PORT


func _fail_network_setup(code: String, cause: Dictionary) -> void:
	network_setup_in_progress = false
	network_ready = false
	ch9_setup_result = {
		"success": false,
		"code": code,
		"error_code": code,
		"cause": cause.duplicate(true),
	}
	push_error("CH9.6 network equipment lab setup failed: %s" % JSON.stringify(ch9_setup_result))
	_refresh_status()


func _remove_persistence_tree(path: String) -> void:
	if path.is_empty() or not DirAccess.dir_exists_absolute(path):
		return
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var entry_name: String = directory.get_next()
		if entry_name.is_empty():
			break
		if entry_name in [".", ".."]:
			continue
		var child_path: String = path.path_join(entry_name)
		if directory.current_is_dir():
			_remove_persistence_tree(child_path)
		else:
			DirAccess.remove_absolute(child_path)
	directory.list_dir_end()
	DirAccess.remove_absolute(path)


func _refresh_status() -> void:
	super._refresh_status()
	if status_label == null:
		return
	var state: String = "READY" if network_ready else "BOOTSTRAPPING" if network_setup_in_progress else String(ch9_setup_result.get("code", "PENDING"))
	var server_generation: int = 0
	if network_server != null:
		server_generation = int(Dictionary(network_server.get_report().get("persistence", {})).get("checkpoint_generation", 0))
	status_label.text += (
		"\n\nCH9.6 — Playable Network Equipment Lab"
		+ "\nInventory -> network controller -> ITEM/ENet -> server Item Graph -> replica -> Quaternius"
		+ "\nstate: %s | player: %s | port: %d | checkpoint generation: %d"
		+ "\nTab — inventory | drag backpack wearable -> equipment slot | drag back to unequip"
		+ "\nClose and reopen without -ResetState to verify durable recovered equipment presentation"
	) % [state, LOGICAL_PLAYER_ID, network_port, server_generation]


func _exit_tree() -> void:
	if network_bridge != null:
		network_bridge.stop("CH9_6_LAB_SHUTDOWN")
	if network_client != null and network_client.has_method("stop"):
		network_client.stop()
	if network_server != null and network_server.has_method("stop"):
		network_server.stop()
