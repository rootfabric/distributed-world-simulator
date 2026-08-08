extends SceneTree

const Domain = preload("res://scripts/characters/equipment/character_equipment_domain.gd")
const LabSource = preload("res://scripts/characters/equipment/lab_equipment_source.gd")
const RigAdapter = preload("res://scripts/characters/equipment/character_rig_adapter.gd")
const Catalog = preload("res://scripts/characters/equipment/wearable_presentation_catalog.gd")
const Presenter = preload("res://scripts/characters/equipment/character_equipment_presenter.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var character_root := Node3D.new()
	character_root.name = "LayeredCharacter"
	root.add_child(character_root)
	var body_root := Node3D.new()
	body_root.name = "BodyRoot"
	character_root.add_child(body_root)

	var rig = RigAdapter.new()
	var rig_setup: Dictionary = rig.setup("test.layered.rig", {"body.root": NodePath("BodyRoot")})
	_assert(bool(rig_setup.get("success", false)), "Layered presentation rig setup failed")

	var layout := _layout()
	var profiles: Array[Domain.Profile] = [
		_profile("equipment.layer.undersuit", "wearable.layer.undersuit", ["body.torso.inner", "body.arms.inner", "body.legs.inner"]),
		_profile("equipment.layer.jacket", "wearable.layer.jacket", ["body.torso.outer", "body.arms.outer"]),
		_profile("equipment.layer.trousers", "wearable.layer.trousers", ["body.legs.outer"]),
		_profile("equipment.layer.boots", "wearable.layer.boots", ["body.feet"]),
		_profile("equipment.layer.armor", "wearable.layer.armor", ["body.torso.armor"]),
		_profile("equipment.layer.eva", "wearable.layer.eva", ["body.torso.outer", "body.torso.armor", "body.arms.outer", "body.legs.outer", "body.feet"]),
	]
	var source = LabSource.new()
	_assert(bool(source.setup("entity.layered.presentation.001", layout, profiles).get("success", false)), "Layered presentation source setup failed")

	var catalog = Catalog.new()
	for index in range(profiles.size()):
		var profile: Domain.Profile = profiles[index]
		var scene := _visual_scene(profile.presentation_id, float(index) * 0.02)
		_assert(scene != null, "Layered visual scene packing failed: %s" % profile.presentation_id)
		if scene != null:
			var registration: Dictionary = catalog.register_scene(
				profile.presentation_id,
				rig.rig_profile_id,
				Catalog.STRATEGY_RIGID_ATTACHMENT,
				scene
			)
			_assert(bool(registration.get("success", false)), "Layered visual registration failed: %s" % profile.presentation_id)

	var presenter = Presenter.new()
	character_root.add_child(presenter)
	_assert(bool(presenter.setup(character_root, rig, catalog).get("success", false)), "Layered presenter setup failed")

	var item_profile_pairs := [
		["item.undersuit.001", "equipment.layer.undersuit"],
		["item.jacket.001", "equipment.layer.jacket"],
		["item.trousers.001", "equipment.layer.trousers"],
		["item.boots.001", "equipment.layer.boots"],
		["item.armor.001", "equipment.layer.armor"],
	]
	for pair in item_profile_pairs:
		_assert(bool(source.equip(String(pair[0]), String(pair[1])).get("success", false)), "Layered presentation fixture equip failed: %s" % pair[0])

	var layered_apply: Dictionary = presenter.apply_snapshot(source.get_snapshot())
	_assert(bool(layered_apply.get("success", false)), "Layered presentation apply failed")
	var layered_details: Dictionary = layered_apply.get("details", {})
	_assert(int(layered_details.get("created", -1)) == 5, "Initial layered apply did not create five visuals")
	_assert(int(layered_details.get("removed", -1)) == 0, "Initial layered apply unexpectedly removed visuals")
	_assert(int(layered_details.get("visual_count", -1)) == 5, "Initial layered presentation count mismatch")
	var undersuit_visual: Node3D = presenter.get_visual("item.undersuit.001")
	_assert(undersuit_visual != null, "Inner-layer visual missing before replacement")
	for pair in item_profile_pairs:
		_assert(presenter.get_visual(String(pair[0])) != null, "Layered visual missing before replacement: %s" % pair[0])

	var revision_before := source.get_snapshot().revision
	var replacement: Dictionary = source.equip_replacing_conflicts("item.eva.001", "equipment.layer.eva")
	_assert(bool(replacement.get("success", false)), "Layered presentation atomic replacement failed")
	_assert(source.get_snapshot().revision == revision_before + 1, "Atomic replacement advanced more than one canonical revision")
	var replacement_apply: Dictionary = presenter.apply_snapshot(source.get_snapshot())
	_assert(bool(replacement_apply.get("success", false)), "Presenter failed to consume atomic replacement snapshot")
	var replacement_details: Dictionary = replacement_apply.get("details", {})
	_assert(int(replacement_details.get("created", -1)) == 1, "Atomic replacement should create only EVA visual")
	_assert(int(replacement_details.get("removed", -1)) == 4, "Atomic replacement should remove four conflicting visuals")
	_assert(int(replacement_details.get("reused", -1)) == 1, "Atomic replacement should reuse compatible undersuit visual")
	_assert(int(replacement_details.get("visual_count", -1)) == 2, "Atomic replacement final visual count mismatch")
	_assert(presenter.get_visual("item.undersuit.001") == undersuit_visual, "Compatible inner-layer visual was recreated instead of reused")
	_assert(presenter.get_visual("item.eva.001") != null, "EVA visual missing after atomic replacement")
	for removed_item in ["item.jacket.001", "item.trousers.001", "item.boots.001", "item.armor.001"]:
		_assert(presenter.get_visual(removed_item) == null, "Conflicting visual remained registered: %s" % removed_item)

	var idempotent: Dictionary = presenter.apply_snapshot(source.get_snapshot())
	_assert(bool(idempotent.get("success", false)), "Idempotent layered reapply failed")
	var idempotent_details: Dictionary = idempotent.get("details", {})
	_assert(not bool(idempotent_details.get("changed", true)), "Idempotent layered reapply reported change")
	_assert(int(idempotent_details.get("created", -1)) == 0, "Idempotent layered reapply created visuals")
	_assert(int(idempotent_details.get("removed", -1)) == 0, "Idempotent layered reapply removed visuals")

	var report: Dictionary = presenter.create_report()
	_assert(int(report.get("visual_count", -1)) == 2, "Layered presenter report final count mismatch")
	_assert(not bool(report.get("moves_gameplay_body", true)), "Layered presenter claims gameplay authority")
	_assert(not bool(report.get("reads_input", true)), "Layered presenter claims input authority")
	_assert(not bool(report.get("owns_network_state", true)), "Layered presenter claims network authority")

	character_root.queue_free()
	_finish()


func _visual_scene(name_value: String, y_offset: float) -> PackedScene:
	var visual_root := Node3D.new()
	visual_root.name = "LayerVisual"
	visual_root.position.y = y_offset
	var mesh := MeshInstance3D.new()
	mesh.name = name_value.replace(".", "_")
	mesh.mesh = BoxMesh.new()
	visual_root.add_child(mesh)
	mesh.owner = visual_root
	var packed := PackedScene.new()
	if packed.pack(visual_root) != OK:
		visual_root.free()
		return null
	visual_root.free()
	return packed


func _layout() -> Domain.Layout:
	return Domain.Layout.new(
		"humanoid.layered.presentation",
		["character", "humanoid", "biped"],
		["equipment.clothing"],
		[
			"body.torso.inner", "body.torso.outer", "body.torso.armor",
			"body.arms.inner", "body.arms.outer",
			"body.legs.inner", "body.legs.outer", "body.feet",
		],
		["body.root"]
	)


func _profile(profile_id: String, presentation_id: String, channels: Array) -> Domain.Profile:
	return Domain.Profile.new(
		profile_id,
		presentation_id,
		"body.root",
		channels,
		[],
		[],
		["equipment.clothing"]
	)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH8 layered equipment presentation diff: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH8 layered equipment presentation diff: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
