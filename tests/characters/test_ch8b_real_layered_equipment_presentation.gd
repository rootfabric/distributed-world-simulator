extends SceneTree

const LabScene = preload("res://scenes/labs/character/quaternius_equipment_lab.tscn")
const Domain = preload("res://scripts/characters/equipment/character_equipment_domain.gd")
const Factory = preload("res://scripts/characters/equipment/selective_garment_scene_factory.gd")
const Catalog = preload("res://scripts/characters/equipment/wearable_presentation_catalog.gd")
const MALE_PEASANT_PATH := "res://assets/external/quaternius/modular_outfits_fantasy/Modular Character Outfits - Fantasy[Standard]/Exports/glTF (Godot-Unreal)/Outfits/Male_Peasant.gltf"

var failures: Array[String] = []
var assertions := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var lab = LabScene.instantiate()
	root.add_child(lab)
	await process_frame
	await physics_frame
	_assert(lab.equipment_source != null, "CH8B equipment source missing")
	_assert(lab.equipment_presenter != null, "CH8B equipment presenter missing")
	_assert(lab.wearable_catalog != null, "CH8B wearable catalog missing")
	if lab.equipment_source == null or lab.equipment_presenter == null or lab.wearable_catalog == null:
		lab.queue_free()
		_finish()
		return

	var loaded = load(MALE_PEASANT_PATH)
	_assert(loaded is PackedScene, "CH8B Male_Peasant source scene missing")
	if not loaded is PackedScene:
		lab.queue_free()
		_finish()
		return
	var source_scene := loaded as PackedScene

	var definitions := [
		{"item": "lab.item.layer.upper.001", "profile": "equipment.layer.upper.peasant", "presentation": "wearable.layer.upper.peasant", "channels": ["body.torso.outer", "body.arms.outer"], "meshes": ["Male_Peasant_Body", "Male_Peasant_Arms"], "count": 2},
		{"item": "lab.item.layer.lower.001", "profile": "equipment.layer.lower.peasant", "presentation": "wearable.layer.lower.peasant", "channels": ["body.legs.outer"], "meshes": ["Male_Peasant_Legs"], "count": 1},
		{"item": "lab.item.layer.feet.001", "profile": "equipment.layer.feet.peasant", "presentation": "wearable.layer.feet.peasant", "channels": ["body.feet"], "meshes": ["Male_Peasant_Feet"], "count": 1},
	]

	for definition in definitions:
		var profile := Domain.Profile.new(
			String(definition["profile"]),
			String(definition["presentation"]),
			"body.root",
			definition["channels"],
			[], [], ["equipment.clothing"]
		)
		_assert(bool(lab.equipment_source.register_profile(profile).get("success", false)), "CH8B profile registration failed")
		var selected: Dictionary = Factory.create(source_scene, definition["meshes"])
		_assert(bool(selected.get("success", false)), "CH8B selective scene factory failed")
		if not bool(selected.get("success", false)):
			continue
		var selected_scene = selected.get("details", {}).get("scene")
		_assert(selected_scene is PackedScene, "CH8B selected scene was not packed")
		if selected_scene is PackedScene:
			var registration: Dictionary = lab.wearable_catalog.register_scene(
				String(definition["presentation"]),
				lab.equipment_rig_adapter.rig_profile_id,
				Catalog.STRATEGY_SKINNED_GARMENT,
				selected_scene as PackedScene
			)
			_assert(bool(registration.get("success", false)), "CH8B selected presentation registration failed")

	var player_position_before: Vector3 = lab.player.position
	var capsule_height_before := float(lab.player_capsule.height)
	lab.set_first_person_mode(true)
	await process_frame
	var fp_before: Dictionary = lab.first_person_adapter.create_report()
	var world_before := int(fp_before.get("world_visual_count", 0))
	var shadow_before := int(fp_before.get("shadow_proxy_count", 0))

	for definition in definitions:
		var equip_result: Dictionary = lab.call("_set_item_equipped", String(definition["item"]), String(definition["profile"]), true)
		_assert(bool(equip_result.get("success", false)), "CH8B real layered equip failed: %s" % String(definition["item"]))
		await process_frame

	var snapshot = lab.equipment_source.get_snapshot()
	_assert(snapshot.entries().size() == 3, "CH8B expected three canonical layered items")
	_assert(snapshot.revision == 3, "CH8B three explicit equips should advance three revisions")
	var presenter_report: Dictionary = lab.equipment_presenter.create_report()
	_assert(int(presenter_report.get("visual_count", 0)) == 3, "CH8B presenter expected three real skinned visuals")

	for definition in definitions:
		var visual: Node3D = lab.equipment_presenter.get_visual(String(definition["item"]))
		_assert(visual != null, "CH8B real layered visual missing: %s" % String(definition["item"]))
		_assert(visual != null and visual.has_method("create_report"), "CH8B real layered visual is not a pose bridge")
		if visual != null and visual.has_method("create_report"):
			var report: Dictionary = visual.call("create_report")
			_assert(int(report.get("matched_bones", 0)) == 65, "CH8B real layered bridge lost 65/65 match")
			_assert(int(report.get("skinned_mesh_count", 0)) == int(definition["count"]), "CH8B real layered bridge mesh count mismatch")

	var fp_after: Dictionary = lab.first_person_adapter.create_report()
	_assert(int(fp_after.get("world_visual_count", 0)) >= world_before + 4, "CH8B selected meshes were not recaptured into CH6 world visuals")
	_assert(int(fp_after.get("shadow_proxy_count", 0)) >= shadow_before + 4, "CH8B selected meshes were not recaptured into CH6 shadow proxy")
	_assert(bool(fp_after.get("shadow_proxy_active", false)), "CH8B layered parts disabled first-person shadow proxy")
	_assert(lab.player.position.is_equal_approx(player_position_before), "CH8B real layered equipment moved gameplay body")
	_assert(is_equal_approx(float(lab.player_capsule.height), capsule_height_before), "CH8B real layered equipment changed gameplay capsule")

	for definition in definitions:
		var off_result: Dictionary = lab.call("_set_item_equipped", String(definition["item"]), String(definition["profile"]), false)
		_assert(bool(off_result.get("success", false)), "CH8B real layered unequip failed")
		await process_frame
	_assert(lab.equipment_source.get_snapshot().entries().is_empty(), "CH8B layered canonical state did not clear")
	_assert(int(lab.equipment_presenter.create_report().get("visual_count", -1)) == 0, "CH8B layered presentation did not clear")
	_assert(lab.player.position.is_equal_approx(player_position_before), "CH8B lifecycle moved gameplay body")
	_assert(is_equal_approx(float(lab.player_capsule.height), capsule_height_before), "CH8B lifecycle changed gameplay capsule")

	lab.queue_free()
	_finish()

func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("CH8B real layered equipment presentation: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH8B real layered equipment presentation: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
