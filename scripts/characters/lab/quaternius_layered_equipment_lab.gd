class_name QuaterniusLayeredEquipmentLab
extends "res://scripts/characters/lab/quaternius_equipment_lab.gd"

const LayerDomain = preload("res://scripts/characters/equipment/character_equipment_domain.gd")
const SelectiveFactory = preload("res://scripts/characters/equipment/selective_garment_scene_factory.gd")
const PresentationCatalog = preload("res://scripts/characters/equipment/wearable_presentation_catalog.gd")
const CoverageCatalogType = preload("res://scripts/characters/equipment/wearable_body_coverage_catalog.gd")
const SuppressionCoordinatorType = preload("res://scripts/characters/equipment/layered_body_suppression_coordinator.gd")
const TopologyCatalogType = preload("res://scripts/characters/equipment/wearable_body_topology_catalog.gd")
const TopologyCoordinatorType = preload("res://scripts/characters/equipment/layered_body_topology_occlusion_coordinator.gd")
const LayeredRigAdapterType = preload("res://scripts/characters/equipment/quaternius_layered_body_suppression_adapter.gd")

const MALE_PEASANT_PATH := "res://assets/external/quaternius/modular_outfits_fantasy/Modular Character Outfits - Fantasy[Standard]/Exports/glTF (Godot-Unreal)/Outfits/Male_Peasant.gltf"
const UPPER_ITEM_ID := "lab.item.layer.upper.001"
const LOWER_ITEM_ID := "lab.item.layer.lower.001"
const FEET_ITEM_ID := "lab.item.layer.feet.001"
const UPPER_PROFILE_ID := "equipment.layer.upper.peasant"
const LOWER_PROFILE_ID := "equipment.layer.lower.peasant"
const FEET_PROFILE_ID := "equipment.layer.feet.peasant"

const REGION_TORSO_CORE := "body.region.torso.core"
const LOWER_TOPOLOGY_THRESHOLD_M := 0.045
const FEET_TOPOLOGY_THRESHOLD_M := 0.035
const TOPOLOGY_BOUNDARY_PAD_M := 0.006

var layered_rig_adapter
var body_coverage_catalog
var body_suppression_coordinator
var body_topology_catalog
var body_topology_coordinator
var layered_setup_result: Dictionary = {}


func _ready() -> void:
	super._ready()
	_setup_layered_equipment()
	_refresh_status()


func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_U:
			_toggle_layer(UPPER_ITEM_ID, UPPER_PROFILE_ID)
		elif event.keycode == KEY_L:
			_toggle_layer(LOWER_ITEM_ID, LOWER_PROFILE_ID)
		elif event.keycode == KEY_K:
			_toggle_layer(FEET_ITEM_ID, FEET_PROFILE_ID)


func _setup_layered_equipment() -> void:
	var loaded = load(MALE_PEASANT_PATH)
	if not loaded is PackedScene:
		layered_setup_result = {"success": false, "code": "MALE_PEASANT_SCENE_MISSING", "details": {}}
		push_error("CH8C layered lab Male_Peasant source is unavailable")
		return
	var source_scene := loaded as PackedScene

	layered_rig_adapter = LayeredRigAdapterType.new()
	layered_setup_result = layered_rig_adapter.bind_presenter(avatar)
	if not bool(layered_setup_result.get("success", false)):
		push_error("CH8C layered rig adapter bind failed: %s" % JSON.stringify(layered_setup_result))
		return

	body_coverage_catalog = CoverageCatalogType.new()
	body_suppression_coordinator = SuppressionCoordinatorType.new()
	layered_setup_result = body_suppression_coordinator.setup(avatar, layered_rig_adapter, body_coverage_catalog)
	if not bool(layered_setup_result.get("success", false)):
		push_error("CH8C suppression coordinator setup failed: %s" % JSON.stringify(layered_setup_result))
		return

	body_topology_catalog = TopologyCatalogType.new()
	body_topology_coordinator = TopologyCoordinatorType.new()
	layered_setup_result = body_topology_coordinator.setup(avatar, layered_rig_adapter, body_topology_catalog)
	if not bool(layered_setup_result.get("success", false)):
		push_error("CH8C topology coordinator setup failed: %s" % JSON.stringify(layered_setup_result))
		return

	var definitions := [
		{
			"profile": UPPER_PROFILE_ID,
			"presentation": "wearable.layer.upper.peasant",
			"channels": ["body.torso.outer", "body.arms.outer"],
			"meshes": ["Male_Peasant_Body", "Male_Peasant_Arms"],
			"regions": [REGION_TORSO_CORE],
			"topology_threshold_m": 0.0,
		},
		{
			"profile": LOWER_PROFILE_ID,
			"presentation": "wearable.layer.lower.peasant",
			"channels": ["body.legs.outer"],
			"meshes": ["Male_Peasant_Legs"],
			# Open/torn trousers preserve skin through real holes and below cuffs.
			# Only body triangles geometrically close to actual trouser surfaces are
			# removed from a temporary presentation mesh.
			"regions": [],
			"topology_threshold_m": LOWER_TOPOLOGY_THRESHOLD_M,
		},
		{
			"profile": FEET_PROFILE_ID,
			"presentation": "wearable.layer.feet.peasant",
			"channels": ["body.feet"],
			"meshes": ["Male_Peasant_Feet"],
			# Open footwear uses the same topology-aware rule instead of deleting the
			# complete foot/ankle volume.
			"regions": [],
			"topology_threshold_m": FEET_TOPOLOGY_THRESHOLD_M,
		}
	]

	for definition in definitions:
		var profile := LayerDomain.Profile.new(
			String(definition["profile"]),
			String(definition["presentation"]),
			"body.root",
			definition["channels"],
			[], [], ["equipment.clothing"]
		)
		layered_setup_result = equipment_source.register_profile(profile)
		if not bool(layered_setup_result.get("success", false)):
			push_error("CH8C layered profile registration failed: %s" % JSON.stringify(layered_setup_result))
			return

		var selected: Dictionary = SelectiveFactory.create(source_scene, definition["meshes"])
		if not bool(selected.get("success", false)):
			layered_setup_result = selected
			push_error("CH8C selective scene creation failed: %s" % JSON.stringify(selected))
			return
		var selected_scene = selected.get("details", {}).get("scene")
		if not selected_scene is PackedScene:
			layered_setup_result = {"success": false, "code": "SELECTED_SCENE_NOT_PACKED", "details": {}}
			return
		var presentation_scene := selected_scene as PackedScene

		layered_setup_result = wearable_catalog.register_scene(
			String(definition["presentation"]),
			equipment_rig_adapter.rig_profile_id,
			PresentationCatalog.STRATEGY_SKINNED_GARMENT,
			presentation_scene
		)
		if not bool(layered_setup_result.get("success", false)):
			push_error("CH8C layered presentation registration failed: %s" % JSON.stringify(layered_setup_result))
			return

		layered_setup_result = body_coverage_catalog.register_coverage(
			String(definition["presentation"]),
			layered_rig_adapter.rig_profile_id,
			definition["regions"]
		)
		if not bool(layered_setup_result.get("success", false)):
			push_error("CH8C coverage registration failed: %s" % JSON.stringify(layered_setup_result))
			return

		var topology_threshold_m := float(definition.get("topology_threshold_m", 0.0))
		if topology_threshold_m > 0.0:
			layered_setup_result = body_topology_catalog.register_surface_occlusion(
				String(definition["presentation"]),
				layered_rig_adapter.rig_profile_id,
				presentation_scene,
				topology_threshold_m,
				TOPOLOGY_BOUNDARY_PAD_M
			)
			if not bool(layered_setup_result.get("success", false)):
				push_error("CH8C topology registration failed: %s" % JSON.stringify(layered_setup_result))
				return

	layered_setup_result = body_suppression_coordinator.apply_snapshot(equipment_source.get_snapshot())
	if not bool(layered_setup_result.get("success", false)):
		return
	layered_setup_result = body_topology_coordinator.apply_snapshot(equipment_source.get_snapshot())


func _toggle_layer(item_id: String, profile_id: String) -> Dictionary:
	if body_suppression_coordinator == null or body_topology_coordinator == null:
		return {"success": false, "code": "CH8C_COORDINATOR_NOT_READY", "details": {}}
	var enabled: bool = not bool(equipment_source.has_item(item_id))
	var mutation_result: Dictionary = _set_item_equipped(item_id, profile_id, enabled)
	if not bool(mutation_result.get("success", false)):
		return mutation_result

	var snapshot := equipment_source.get_snapshot()
	var suppression_result: Dictionary = body_suppression_coordinator.apply_snapshot(snapshot)
	if not bool(suppression_result.get("success", false)):
		layered_setup_result = suppression_result
		push_error("CH8C layered suppression apply failed: %s" % JSON.stringify(suppression_result))
		_refresh_status()
		return suppression_result

	var topology_result: Dictionary = body_topology_coordinator.apply_snapshot(snapshot)
	if not bool(topology_result.get("success", false)):
		layered_setup_result = topology_result
		push_error("CH8C topology occlusion apply failed: %s" % JSON.stringify(topology_result))
		_refresh_status()
		return topology_result

	layered_setup_result = topology_result
	_refresh_equipment_view_policy()
	_refresh_status()
	return mutation_result


func _refresh_status() -> void:
	super._refresh_status()
	if status_label == null:
		return
	var upper_state := "ON" if equipment_source != null and equipment_source.has_item(UPPER_ITEM_ID) else "OFF"
	var lower_state := "ON" if equipment_source != null and equipment_source.has_item(LOWER_ITEM_ID) else "OFF"
	var feet_state := "ON" if equipment_source != null and equipment_source.has_item(FEET_ITEM_ID) else "OFF"
	var regions: Array = []
	if body_suppression_coordinator != null:
		regions = body_suppression_coordinator.create_report().get("active_regions", [])
	var topology_removed := 0
	var topology_active: Array = []
	if body_topology_coordinator != null:
		var topology_report: Dictionary = body_topology_coordinator.create_report()
		topology_removed = int(topology_report.get("removed_triangles", 0))
		topology_active = topology_report.get("active_presentations", [])
	var layered_status := (
		"\n\nCH8C — Layered Garments\n"
		+ "U — upper | L — lower | K — feet\n"
		+ "upper: %s | lower: %s | feet: %s\n"
		+ "material suppression: %s\n"
		+ "topology: %s | removed triangles: %d"
	)
	status_label.text += layered_status % [
		upper_state,
		lower_state,
		feet_state,
		", ".join(regions),
		", ".join(topology_active),
		topology_removed,
	]
