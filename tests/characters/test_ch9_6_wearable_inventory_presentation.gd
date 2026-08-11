extends SceneTree

const AdapterType = preload("res://scripts/runtime/networked_gameplay/ch9/ch9_3_item_graph_replica_adapter.gd")
const EquipmentCatalog = preload("res://scripts/characters/equipment/network_character_equipment_catalog.gd")
const Factory = preload("res://scripts/items/services/item_domain_factory.gd")

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var adapter = AdapterType.new()
	var setup: Dictionary = adapter.setup("a")
	_assert(bool(setup.get("success", false)), "CH9.6 equipment replica adapter setup failed")

	var domain: Dictionary = Factory.create()
	adapter._register_definitions(domain)

	for slot_index in range(EquipmentCatalog.EQUIPMENT_SLOT_COUNT):
		var canonical_definition := EquipmentCatalog.canonical_definition_for_slot(slot_index)
		var replica_definition := EquipmentCatalog.replica_definition_id(canonical_definition)
		_assert(not replica_definition.is_empty(), "CH9.6 wearable replica definition missing for slot %d" % slot_index)
		var definition = domain.items.get_definition(replica_definition)
		_assert(definition != null, "CH9.6 wearable definition not registered: %s" % replica_definition)
		if definition == null:
			continue
		_assert(not String(definition.display_name).strip_edges().is_empty(), "CH9.6 wearable display name missing: %s" % replica_definition)
		var metadata: Dictionary = definition.metadata
		_assert(metadata.has("icon_color"), "CH9.6 wearable icon_color missing: %s" % replica_definition)
		var color_value = metadata.get("icon_color", [])
		_assert(color_value is Array and color_value.size() >= 3, "CH9.6 wearable icon_color invalid: %s" % replica_definition)
		if color_value is Array and color_value.size() >= 3:
			var brightness := float(color_value[0]) + float(color_value[1]) + float(color_value[2])
			_assert(brightness >= 0.60, "CH9.6 wearable icon_color too dark to distinguish in inventory: %s" % replica_definition)

	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH9.6 wearable inventory presentation: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH9.6 wearable inventory presentation: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
