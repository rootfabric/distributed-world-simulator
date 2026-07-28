class_name InventoryInspector
extends PanelContainer

signal close_requested()

@onready var empty_label: Label = %EmptyLabel
@onready var content: VBoxContainer = %Content
@onready var title_label: Label = %TitleLabel
@onready var definition_label: Label = %DefinitionLabel
@onready var quantity_label: Label = %QuantityLabel
@onready var physical_label: Label = %PhysicalLabel
@onready var relation_label: Label = %RelationLabel
@onready var tags_label: Label = %TagsLabel
@onready var components_label: Label = %ComponentsLabel
@onready var revision_label: Label = %RevisionLabel
@onready var close_button: Button = %CloseButton

var current_item_id: String = ""
var current_model: Dictionary = {}


func _ready() -> void:
	close_button.pressed.connect(func() -> void: close_requested.emit())
	clear_item()


func show_item(model: Dictionary) -> void:
	current_model = model.duplicate(true)
	current_item_id = String(model.get("item_id", ""))
	if current_item_id.is_empty():
		clear_item()
		return
	empty_label.visible = false
	content.visible = true
	title_label.text = String(model.get("display_name", "Предмет"))
	definition_label.text = "Тип: %s" % String(model.get("definition_id", "—"))
	quantity_label.text = "Количество: %d / max stack %d" % [
		int(model.get("quantity", 0)),
		int(model.get("max_stack", 1)),
	]
	physical_label.text = "Масса: %.2f кг/шт · %.2f кг всего\nОбъём: %.2f л/шт · %.2f л всего" % [
		float(model.get("unit_mass_kg", 0.0)),
		float(model.get("total_mass_kg", 0.0)),
		float(model.get("unit_volume_l", 0.0)),
		float(model.get("total_volume_l", 0.0)),
	]
	var relation := Dictionary(model.get("relation", {}))
	var relation_kind := String(relation.get("kind", model.get("relation_kind", "—")))
	var relation_target := ""
	match relation_kind:
		"CONTAINER":
			relation_target = String(relation.get("container_id", ""))
			var slot_index := int(relation.get("slot_index", -1))
			if slot_index >= 0:
				relation_target += " · слот %d" % (slot_index + 1)
		"ATTACHMENT":
			relation_target = "%s / %s" % [String(relation.get("parent_item_id", "")), String(relation.get("socket_id", ""))]
		"WORLD":
			relation_target = String(relation.get("frame_id", ""))
	relation_label.text = "Положение: %s%s" % [relation_kind, " · %s" % relation_target if not relation_target.is_empty() else ""]
	var tags := PackedStringArray(model.get("tags", []))
	tags_label.text = "Категории: %s" % (", ".join(tags) if not tags.is_empty() else "—")
	var components := Dictionary(model.get("components", {}))
	var component_names := PackedStringArray()
	for component_name in components.keys():
		component_names.append(String(component_name))
	component_names.sort()
	components_label.text = "Компоненты: %s" % (", ".join(component_names) if not component_names.is_empty() else "—")
	revision_label.text = "Revision: %d%s" % [
		int(model.get("revision", 0)),
		" · UUID: %s" % current_item_id if OS.is_debug_build() else "",
	]


func clear_item() -> void:
	current_item_id = ""
	current_model = {}
	if empty_label != null:
		empty_label.visible = true
	if content != null:
		content.visible = false


func create_debug_snapshot() -> Dictionary:
	return {
		"schema": "planet_simulator.inventory_inspector_debug.v1",
		"visible": visible,
		"item_id": current_item_id,
		"has_content": not current_item_id.is_empty(),
		"model": current_model.duplicate(true),
	}
