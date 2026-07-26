extends StaticBody3D

const INTERACTABLE_GROUP: StringName = &"world_interactable"

var repository
var entity_id: String = ""
var beacon_active: bool = true
var focused: bool = false
var outline_material: StandardMaterial3D


func _ready() -> void:
	add_to_group(INTERACTABLE_GROUP)


func setup_interactable(
	repository_reference,
	entity_id_value: String,
	active_value: bool = true
) -> void:
	repository = repository_reference
	entity_id = entity_id_value
	add_to_group(INTERACTABLE_GROUP)
	_ensure_outline_material()
	set_beacon_active(active_value)


func get_interaction_descriptor(_actor = null) -> Dictionary:
	var short_id: String = entity_id.get_file()
	return {
		"schema": "lunar.interaction_descriptor.v1",
		"entity_id": entity_id,
		"entity_type": "survey_beacon",
		"title": "Survey Beacon",
		"details": "Сигнал: %s\nID: %s" % [
			"активен" if beacon_active else "выключен",
			short_id,
		],
		"prompt": "E — %s сигнал" % (
			"выключить" if beacon_active else "включить"
		),
	}


func interact(_actor = null, _context: Dictionary = {}) -> Dictionary:
	if repository == null or not repository.has_method("toggle_survey_beacon_signal"):
		return {
			"success": false,
			"message": "Хранилище маяка недоступно",
		}
	var result: Dictionary = repository.toggle_survey_beacon_signal(entity_id)
	if bool(result.get("success", false)):
		set_beacon_active(bool(result.get("active", beacon_active)))
	return result


func set_interaction_focus(focused_value: bool) -> void:
	if focused == focused_value:
		return
	focused = focused_value
	_ensure_outline_material()
	_apply_outline_recursive(self, outline_material if focused else null)


func set_beacon_active(active_value: bool) -> void:
	beacon_active = active_value
	var signal_mesh := get_node_or_null("Signal") as MeshInstance3D
	if signal_mesh != null:
		var material := signal_mesh.material_override as StandardMaterial3D
		if material != null:
			material.albedo_color = (
				Color(0.94, 0.24, 0.06)
				if beacon_active
				else Color(0.20, 0.22, 0.24)
			)
			material.emission_enabled = beacon_active
			material.emission = Color(0.62, 0.04, 0.01)
			material.emission_energy_multiplier = 1.8 if beacon_active else 0.0
	var label := get_node_or_null("BeaconLabel") as Label3D
	if label != null:
		label.text = "SURVEY" if beacon_active else "STANDBY"
		label.modulate = (
			Color(1.0, 0.42, 0.18)
			if beacon_active
			else Color(0.55, 0.58, 0.62)
		)


func _ensure_outline_material() -> void:
	if outline_material != null:
		return
	outline_material = StandardMaterial3D.new()
	outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline_material.albedo_color = Color(1.0, 0.64, 0.15, 0.82)
	outline_material.emission_enabled = true
	outline_material.emission = Color(1.0, 0.30, 0.04)
	outline_material.emission_energy_multiplier = 1.25
	outline_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outline_material.cull_mode = BaseMaterial3D.CULL_FRONT
	outline_material.grow = true
	outline_material.grow_amount = 0.025
	outline_material.no_depth_test = true


func _apply_outline_recursive(node: Node, material: Material) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_overlay = material
		_apply_outline_recursive(child, material)
