extends SceneTree

const Service = preload("res://scripts/runtime/networked_gameplay/ch9/ch9_3_networked_gameplay_service.gd")
const EquipmentCatalog = preload("res://scripts/characters/equipment/network_character_equipment_catalog.gd")
const EquipmentProjection = preload("res://scripts/characters/equipment/network_character_equipment_projection.gd")
const ItemDelta = preload("res://scripts/runtime/networked_gameplay/contracts/canonical_item_graph_delta.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var service = Service.new()
	var setup: Dictionary = service.setup("simulation/ch9-3/test", 1, 0, {
		"profile": "MULTIPLAYER_CORE",
		"topology_adapter": "LOOPBACK",
		"region_id": "region/ch9-3/test",
		"playable_sandbox": true,
	})
	_assert(bool(setup.get("success", false)), "CH9.3 service setup failed: %s" % JSON.stringify(setup))
	if not bool(setup.get("success", false)):
		_finish()
		return

	var join_a: Dictionary = service.join("a", "transport-session/ch9-3/a", "operation/ch9-3/join/a")
	var join_b: Dictionary = service.join("b", "transport-session/ch9-3/b", "operation/ch9-3/join/b")
	_assert(bool(join_a.get("success", false)), "CH9.3 player A join failed")
	_assert(bool(join_b.get("success", false)), "CH9.3 player B join failed")
	var player_a: Dictionary = Dictionary(join_a.get("details", {}).get("player", {}))
	var player_b: Dictionary = Dictionary(join_b.get("details", {}).get("player", {}))
	var epoch_a := int(player_a.get("ownership_epoch", 0))
	var epoch_b := int(player_b.get("ownership_epoch", 0))
	_assert(epoch_a >= 1 and epoch_b >= 1, "CH9.3 ownership epochs missing")

	var initial_items: Dictionary = service.create_canonical_item_graph_snapshot()
	_assert(String(initial_items.get("schema", "")) == "planet_simulator.canonical_multiplayer_item_graph_snapshot.v1", "CH9.3 canonical Item Graph schema drift")
	_assert(not _find_container(initial_items, EquipmentCatalog.equipment_container_id("a")).is_empty(), "CH9.3 A equipment container missing after join")
	_assert(not _find_container(initial_items, EquipmentCatalog.equipment_container_id("b")).is_empty(), "CH9.3 B equipment container missing after join")
	var lower_id := "item/player/a/wearable/lower"
	var lower_before := _find_item(initial_items, lower_id)
	_assert(String(lower_before.get("definition_id", "")) == EquipmentCatalog.DEFINITION_LOWER, "CH9.3 A lower wearable missing from canonical inventory")
	_assert(String(lower_before.get("location", {}).get("kind", "")) == "INVENTORY", "CH9.3 A lower wearable must start in inventory")

	var gameplay_before := service.create_snapshot()
	_assert(not JSON.stringify(gameplay_before).contains(lower_id), "CH9.3 movement/gameplay snapshot leaked equipment Item ID before equip")
	_assert(not JSON.stringify(gameplay_before).contains(EquipmentCatalog.equipment_container_id("a")), "CH9.3 movement/gameplay snapshot leaked equipment container")

	var equip: Dictionary = service.handle_canonical_item_command(
		"a",
		"transport-session/ch9-3/a",
		epoch_a,
		"operation/ch9-3/equip/a/lower",
		"equipment.equip",
		{"item_id": lower_id, "slot_index": EquipmentCatalog.SLOT_LOWER}
	)
	_assert(bool(equip.get("success", false)), "CH9.3 server equip failed: %s" % JSON.stringify(equip))
	var equipped_items := service.create_canonical_item_graph_snapshot()
	var lower_after := _find_item(equipped_items, lower_id)
	var lower_location: Dictionary = Dictionary(lower_after.get("location", {}))
	_assert(String(lower_location.get("kind", "")) == "CONTAINER", "CH9.3 equipped item relation is not canonical CONTAINER")
	_assert(String(lower_location.get("container_id", "")) == EquipmentCatalog.equipment_container_id("a"), "CH9.3 equipped item container mismatch")
	_assert(int(lower_location.get("slot_index", -1)) == EquipmentCatalog.SLOT_LOWER, "CH9.3 equipped item slot mismatch")
	var a_equipment := _find_container(equipped_items, EquipmentCatalog.equipment_container_id("a"))
	_assert(String(a_equipment.get("container_kind", "")) == EquipmentCatalog.EQUIPMENT_CONTAINER_KIND, "CH9.3 equipment container kind missing")
	_assert(String(a_equipment.get("owner_player_id", "")) == "a", "CH9.3 equipment owner mismatch")
	_assert(String(Dictionary(a_equipment.get("equipment_slots", {})).get(str(EquipmentCatalog.SLOT_LOWER), "")) == lower_id, "CH9.3 slot map did not reference equipped lower")
	_assert(Array(a_equipment.get("slots", [])).size() == 1 and String(Array(a_equipment.get("slots", []))[0]) == lower_id, "CH9.3 canonical equipment reference list invalid")

	var gameplay_after := service.create_snapshot()
	_assert(not JSON.stringify(gameplay_after).contains(lower_id), "CH9.3 gameplay snapshot leaked equipped Item ID")
	_assert(not JSON.stringify(gameplay_after).contains("equipment_slots"), "CH9.3 gameplay snapshot leaked equipment state")

	var permission_denied: Dictionary = service.handle_canonical_item_command(
		"b",
		"transport-session/ch9-3/b",
		epoch_b,
		"operation/ch9-3/equip/b/foreign",
		"equipment.equip",
		{"item_id": lower_id, "slot_index": EquipmentCatalog.SLOT_LOWER}
	)
	_assert(not bool(permission_denied.get("success", false)), "CH9.3 player B equipped player A item")
	_assert(String(permission_denied.get("error_code", "")) == "EQUIPMENT_ITEM_NOT_OWNED", "CH9.3 foreign equipment rejection code drift")
	_assert(_find_item(service.create_canonical_item_graph_snapshot(), lower_id) == lower_after, "CH9.3 rejected foreign command changed canonical item")

	var delta_result: Dictionary = ItemDelta.create(initial_items, equipped_items)
	_assert(bool(delta_result.get("success", false)), "CH9.3 Item Graph equipment delta build failed")
	var applied: Dictionary = ItemDelta.apply(initial_items, Dictionary(delta_result.get("details", {}).get("delta", {})))
	_assert(bool(applied.get("success", false)), "CH9.3 Item Graph equipment delta apply failed")
	var replica_after: Dictionary = Dictionary(applied.get("details", {}).get("snapshot", {}))
	_assert(String(replica_after.get("checksum", "")) == String(equipped_items.get("checksum", "")), "CH9.3 replicated equipment checksum diverged")
	_assert(_find_item(replica_after, lower_id) == lower_after, "CH9.3 remote Item Graph delta lost equipment relation")

	var projection = EquipmentProjection.new()
	var projected: Dictionary = projection.project(replica_after, "a")
	_assert(bool(projected.get("success", false)), "CH9.3 remote equipment projection failed: %s" % JSON.stringify(projected))
	var character_snapshot = projected.get("details", {}).get("snapshot")
	_assert(character_snapshot is CharacterEquipmentDomain.Snapshot, "CH9.3 projection did not produce CharacterEquipmentDomain.Snapshot")
	if character_snapshot is CharacterEquipmentDomain.Snapshot:
		var entry = character_snapshot.find_item(lower_id)
		_assert(entry != null, "CH9.3 remote character snapshot missing A lower item")
		if entry != null:
			_assert(String(entry.profile_id) == EquipmentCatalog.PROFILE_LOWER, "CH9.3 remote lower profile mismatch")
			_assert(String(entry.presentation_id) == EquipmentCatalog.PRESENTATION_LOWER, "CH9.3 remote lower presentation mismatch")

	var replay: Dictionary = service.handle_canonical_item_command(
		"a",
		"transport-session/ch9-3/a",
		epoch_a,
		"operation/ch9-3/equip/a/lower",
		"equipment.equip",
		{"item_id": lower_id, "slot_index": EquipmentCatalog.SLOT_LOWER}
	)
	_assert(bool(replay.get("success", false)) and bool(replay.get("replay", false)), "CH9.3 equip replay was not idempotent")
	_assert(String(service.create_canonical_item_graph_snapshot().get("checksum", "")) == String(equipped_items.get("checksum", "")), "CH9.3 replay changed Item Graph checksum")

	var unequip: Dictionary = service.handle_canonical_item_command(
		"a",
		"transport-session/ch9-3/a",
		epoch_a,
		"operation/ch9-3/unequip/a/lower",
		"equipment.unequip",
		{"item_id": lower_id}
	)
	_assert(bool(unequip.get("success", false)), "CH9.3 server unequip failed")
	var final_items := service.create_canonical_item_graph_snapshot()
	var lower_final := _find_item(final_items, lower_id)
	_assert(String(lower_final.get("location", {}).get("kind", "")) == "INVENTORY", "CH9.3 unequip did not return item to inventory")
	_assert(String(lower_final.get("location", {}).get("player_id", "")) == "a", "CH9.3 unequip returned item to wrong player")
	_assert(Dictionary(_find_container(final_items, EquipmentCatalog.equipment_container_id("a")).get("equipment_slots", {})).is_empty(), "CH9.3 equipment slot remained occupied after unequip")

	var durable := service.export_durable_state()
	_assert(not durable.is_empty(), "CH9.3 durable state export failed with equipment containers")
	_assert(bool(service.validate_durable_state(durable).get("success", false)), "CH9.3 durable state rejected equipment relation")

	service.shutdown()
	_finish()


func _find_item(snapshot: Dictionary, item_id: String) -> Dictionary:
	for value in snapshot.get("items", []):
		if value is Dictionary and String(value.get("item_id", "")) == item_id:
			return Dictionary(value).duplicate(true)
	return {}


func _find_container(snapshot: Dictionary, container_id: String) -> Dictionary:
	for value in snapshot.get("containers", []):
		if value is Dictionary and String(value.get("container_id", "")) == container_id:
			return Dictionary(value).duplicate(true)
	return {}


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH9.3 multiplayer equipment authority: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH9.3 multiplayer equipment authority: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
