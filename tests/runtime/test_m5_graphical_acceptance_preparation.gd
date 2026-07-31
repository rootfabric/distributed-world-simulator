extends SceneTree

const Service = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
const M4Projection = preload("res://scripts/runtime/networked_gameplay/m5/m4_item_graph_ui_projection.gd")
const Adapter = preload("res://scripts/runtime/networked_gameplay/m5/m4_item_command_adapter.gd")
const TransientState = preload("res://scripts/runtime/networked_gameplay/m5/m4_inventory_transient_state.gd")
const UiBridge = preload("res://scripts/runtime/networked_gameplay/m5/m5_inventory_ui_bridge.gd")
const ProcessEnvironment = preload("res://scripts/runtime/networked_gameplay/m5/m5_process_environment.gd")
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

class FakeRuntime:
	extends Node
	signal item_graph_updated(snapshot: Dictionary)
	var snapshot: Dictionary = {}
	var calls: Array[Dictionary] = []
	func get_item_graph_snapshot() -> Dictionary:
		return snapshot.duplicate(true)
	func execute_item_command_blocking(command_type: String, payload: Dictionary, operation_id: String = "") -> Dictionary:
		calls.append({"command_type": command_type, "payload": payload.duplicate(true), "operation_id": operation_id})
		return {"success": true, "error_code": "", "details": {"operation_id": operation_id}}
	func publish(snapshot_value: Dictionary) -> void:
		snapshot = snapshot_value.duplicate(true)
		item_graph_updated.emit(snapshot.duplicate(true))

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	var service = Service.new()
	_assert(bool(service.setup("authority/pre-m5", 1, 0, {
		"profile": Service.PROFILE_MULTIPLAYER_CORE,
		"topology_adapter": "ENET",
		"region_id": "region/pre-m5",
	}).get("success", false)), "service setup")
	_assert(bool(service.join("a", "transport-session/pre-m5/a/1", "operation/pre-m5/join/a").get("success", false)), "player A join")
	_assert(bool(service.join("b", "transport-session/pre-m5/b/1", "operation/pre-m5/join/b").get("success", false)), "player B join")

	var initial: Dictionary = service.create_canonical_item_graph_snapshot()
	var initial_hash := Utils.payload_hash(initial)
	var projection = M4Projection.new()
	_assert(bool(projection.accept_snapshot(initial).get("success", false)), "projection accepts canonical M4 snapshot")
	_assert(Utils.payload_hash(initial) == initial_hash, "projection does not mutate source snapshot")
	var initial_view: Dictionary = projection.build_screen("a")
	_assert(bool(initial_view.get("success", false)), "projection builds screen model")
	_assert(String(initial_view.get("schema", "")) == M4Projection.VIEW_SCHEMA, "projection view schema")
	_assert(int(initial_view.get("canonical_revision", -1)) == 0, "initial projection revision")
	_assert(int(initial_view.get("player", {}).get("slot_count", 0)) == M4Projection.PLAYER_CAPACITY, "player inventory capacity")
	_assert(int(initial_view.get("hotbar", {}).get("slot_count", 0)) == M4Projection.HOTBAR_CAPACITY, "hotbar capacity")
	_assert(Array(initial_view.get("world_items", [])).size() == 3, "world items projected")
	_assert(Dictionary(initial_view.get("external", {})).is_empty(), "external container hidden until authority opens it")
	_assert(int(projection.get_report().get("authority_references", -1)) == 0, "projection has no authority references")
	_assert(int(projection.get_report().get("domain_references", -1)) == 0, "projection has no domain references")

	_assert(bool(service.handle_canonical_item_command(
		"a", "transport-session/pre-m5/a/1", 1,
		"operation/pre-m5/pickup", "item.pickup", {"item_id": "item/shared/beacon/1"}
	).get("success", false)), "authority pickup")
	var picked: Dictionary = service.create_canonical_item_graph_snapshot()
	_assert(bool(projection.accept_snapshot(picked).get("success", false)), "projection accepts newer revision")
	var picked_view: Dictionary = projection.build_screen("a")
	_assert(_container_has(picked_view.get("player", {}), "item/shared/beacon/1"), "winner inventory projected")
	_assert(not _world_has(picked_view, "item/shared/beacon/1"), "picked item removed from world projection")
	_assert(bool(projection.accept_snapshot(picked).get("success", false)), "exact snapshot replay accepted")
	_assert(int(projection.get_report().get("replay_count", 0)) == 1, "snapshot replay counted")
	var mutated := picked.duplicate(true)
	mutated["tick"] = int(mutated.get("tick", 0)) + 1
	var body := mutated.duplicate(true)
	body.erase("checksum")
	mutated["checksum"] = Utils.payload_hash(body)
	_assert(String(projection.accept_snapshot(mutated).get("error_code", "")) == "ITEM_GRAPH_SAME_REVISION_MUTATION", "same-revision mutation rejected")
	_assert(String(projection.accept_snapshot(initial).get("error_code", "")) == "ITEM_GRAPH_REVISION_ROLLBACK", "revision rollback rejected")

	_assert(bool(service.handle_canonical_item_command(
		"a", "transport-session/pre-m5/a/1", 1,
		"operation/pre-m5/open", "container.open", {"container_id": "container/shared/crate/1"}
	).get("success", false)), "authority opens external container")
	var opened := service.create_canonical_item_graph_snapshot()
	_assert(bool(projection.accept_snapshot(opened).get("success", false)), "open-container snapshot accepted")
	var open_view: Dictionary = projection.build_screen("a", "container/shared/crate/1")
	_assert(String(open_view.get("external_container_id", "")) == "container/shared/crate/1", "authoritative external container projected")
	_assert(int(open_view.get("external", {}).get("slot_count", 0)) == 8, "external capacity projected")
	_assert(Dictionary(projection.build_screen("b", "container/shared/crate/1").get("external", {})).is_empty(), "container remains hidden for player without open session")

	var transient = TransientState.new()
	_assert(bool(transient.accept_snapshot(opened).get("success", false)), "transient state accepts canonical revision")
	_assert(bool(transient.begin_cursor_carry("item/shared/beacon/1", 1, "inventory/a", 0, int(opened.get("revision", -1))).get("success", false)), "transient cursor begins")
	var transient_view: Dictionary = projection.build_screen("a", "container/shared/crate/1", "", transient.create_overlay())
	_assert(bool(_cell_for(transient_view.get("player", {}), "item/shared/beacon/1").get("ui_transient_hidden", false)), "cursor overlay hides only presentation cell")
	_assert(String(projection.get_snapshot().get("checksum", "")) == String(opened.get("checksum", "")), "cursor overlay does not mutate canonical checksum")
	_assert(int(transient.get_report().get("canonical_mutation_count", -1)) == 0, "transient state records zero canonical mutations")
	_assert(bool(transient.cancel_cursor().get("success", false)), "cursor cancellation")

	var fake := FakeRuntime.new()
	fake.snapshot = opened.duplicate(true)
	root.add_child(fake)
	var adapter = Adapter.new()
	_assert(bool(adapter.setup(fake, "a").get("success", false)), "command adapter setup")
	var transfer_preview := adapter.preview_action("transfer", {
		"item_id": "item/shared/beacon/1",
		"target_container_id": "container/shared/crate/1",
		"target_slot_index": 6,
	})
	_assert(bool(transfer_preview.get("success", false)), "UI transfer maps to M4 command")
	_assert(String(transfer_preview.get("details", {}).get("command_type", "")) == "item.transfer", "transfer command type exact")
	var transfer_payload: Dictionary = transfer_preview.get("details", {}).get("payload", {})
	_assert(transfer_payload == {
		"item_id": "item/shared/beacon/1",
		"quantity": -1,
		"target_container_id": "container/shared/crate/1",
		"target_slot_index": 6,
	}, "UI transfer emits exact versioned M4 payload")
	var mount_preview := adapter.preview_action("mount", {
		"item_id": "item/shared/beacon/1",
		"assembly_id": "assembly/demo",
		"socket_id": "mount/shared/socket/1",
	})
	_assert(Dictionary(mount_preview.get("details", {}).get("payload", {})) == {"item_id": "item/shared/beacon/1", "mount_id": "mount/shared/socket/1"}, "socket alias maps to canonical mount_id")
	var reverse_preview := adapter.preview_action("transfer", {
		"item_id": "item/shared/beacon/1",
		"target_container_id": "inventory/a",
	})
	_assert(bool(reverse_preview.get("success", false)), "reverse transfer to player inventory is supported")
	_assert(String(reverse_preview.get("details", {}).get("command_type", "")) == "item.transfer", "reverse transfer uses canonical item.transfer")
	var submitted := adapter.submit_action_blocking("select_hotbar", {"slot_index": 2}, "operation/pre-m5/ui/hotbar")
	_assert(bool(submitted.get("success", false)), "adapter dispatches through runtime")
	_assert(fake.calls.size() == 1, "one runtime command dispatched")
	_assert(String(fake.calls[0].get("command_type", "")) == "inventory.select_hotbar", "runtime receives canonical hotbar command")
	_assert(Dictionary(fake.calls[0].get("payload", {})) == {"selected_hotbar_index": 2}, "runtime receives exact hotbar payload")
	_assert(int(adapter.get_report().get("authority_references", -1)) == 0, "adapter has no authority references")

	var bridge = UiBridge.new()
	root.add_child(bridge)
	_assert(bool(bridge.setup(fake, "a").get("success", false)), "UI bridge setup")
	var bridge_view := bridge.build_view()
	_assert(bool(bridge_view.get("success", false)), "UI bridge exposes replica view")
	_assert(String(bridge_view.get("canonical_checksum", "")) == String(opened.get("checksum", "")), "UI bridge checksum matches replica")
	_assert(bool(bridge.begin_cursor_carry("item/shared/beacon/1", 1, "inventory/a", 0).get("success", false)), "UI bridge starts transient carry")
	_assert(int(bridge.get_report().get("transient", {}).get("canonical_mutation_count", -1)) == 0, "bridge transient state remains non-canonical")
	bridge.cancel_cursor()
	fake.publish(opened)
	_assert(int(bridge.get_report().get("view_updates", 0)) >= 2, "UI bridge reacts to replica signal")
	bridge.stop()
	bridge.queue_free()
	fake.queue_free()

	var process_configs := [
		ProcessEnvironment.create("/tmp/m5-profile", "server", 0, "disabled"),
		ProcessEnvironment.create("/tmp/m5-profile", "client-a", 1, "unique"),
		ProcessEnvironment.create("/tmp/m5-profile", "client-b", 2, "unique"),
	]
	_assert(bool(ProcessEnvironment.validate_unique(process_configs).get("success", false)), "process profiles and MCP ports are unique")
	_assert(String(process_configs[0].environment.get("BREAKPOINT_RUNTIME_DISABLED", "")) == "1", "non-managed server disables MCP runtime bridge")
	_assert(int(process_configs[1].get("runtime_mcp_port", 0)) != int(process_configs[2].get("runtime_mcp_port", 0)), "graphical clients use distinct MCP ports")
	_assert(String(process_configs[1].get("profile_root", "")) != String(process_configs[2].get("profile_root", "")), "graphical clients use isolated user profiles")

	var runtime_bridge_text := FileAccess.get_file_as_string("res://addons/breakpoint_mcp/runtime_bridge.gd")
	_assert(runtime_bridge_text.contains("BREAKPOINT_RUNTIME_DISABLED"), "runtime bridge supports explicit disable flag")
	var playground_text := FileAccess.get_file_as_string("res://scripts/world/testing/playground_runtime.gd")
	_assert(playground_text.contains("M5NetworkedInventoryShell"), "networked playground composes M5 inventory shell")
	_assert(playground_text.contains("m5_networked_inventory_shell.toggle_inventory"), "Tab path reaches networked inventory shell")

	var roadmap := _read_json("res://config/network/network-roadmap.v1.json")
	var phases := _by_id(Array(roadmap.get("phases", [])))
	_assert(String(roadmap.get("project_checkpoint", "")) == "v16.10.5-persistence-m6-dedicated-recovery", "roadmap current checkpoint is M6 over accepted M5")
	_assert(String(phases.get("M4", {}).get("status", "")) == "accepted", "M4 roadmap status accepted")
	_assert(String(phases.get("M5", {}).get("status", "")) == "accepted", "M5 accepted before M6 candidate")
	var m4_manifest := _read_json("res://config/network/canonical-shared-gameplay.v1.json")
	_assert(String(m4_manifest.get("status", "")) == "accepted", "M4 implementation manifest accepted")
	var prep_manifest := _read_json("res://config/network/m5-graphical-acceptance-preparation.v1.json")
	_assert(String(prep_manifest.get("status", "")) == "completed", "pre-M5 preparation manifest completed")
	_assert(String(prep_manifest.get("completed_by_checkpoint", "")) == "v16.10.4-testing-m5-graphical-multiplayer-acceptance", "pre-M5 preparation completion checkpoint")

	service.shutdown()
	_finish()


func _container_has(container: Dictionary, item_id: String) -> bool:
	return not _cell_for(container, item_id).is_empty()


func _cell_for(container: Dictionary, item_id: String) -> Dictionary:
	for cell_value in container.get("cells", []):
		if cell_value is Dictionary and String(cell_value.get("item_id", "")) == item_id:
			return Dictionary(cell_value)
	return {}


func _world_has(view: Dictionary, item_id: String) -> bool:
	for item_value in view.get("world_items", []):
		if item_value is Dictionary and String(item_value.get("item_id", "")) == item_id:
			return true
	return false


func _read_json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return Dictionary(parsed) if parsed is Dictionary else {}


func _by_id(values: Array) -> Dictionary:
	var out: Dictionary = {}
	for value in values:
		if value is Dictionary:
			out[String(value.get("id", ""))] = value
	return out


func _assert(ok: bool, message: String) -> void:
	assertions += 1
	if ok:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)


func _finish() -> void:
	print("M5 graphical acceptance preparation: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
