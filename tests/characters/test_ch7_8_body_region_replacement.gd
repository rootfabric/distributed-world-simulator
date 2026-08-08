extends SceneTree

const Domain = preload("res://scripts/characters/equipment/character_equipment_domain.gd")
const RigAdapter = preload("res://scripts/characters/equipment/character_rig_adapter.gd")
const Catalog = preload("res://scripts/characters/equipment/wearable_presentation_catalog.gd")
const Presenter = preload("res://scripts/characters/equipment/character_equipment_presenter.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var visual_root := Node3D.new()
	visual_root.name = "VisualRoot"
	root.add_child(visual_root)

	var source_skeleton := Skeleton3D.new()
	source_skeleton.name = "SourceSkeleton"
	visual_root.add_child(source_skeleton)
	_add_test_bones(source_skeleton)

	var base_region := Node3D.new()
	base_region.name = "BaseBody"
	visual_root.add_child(base_region)
	var base_visible := _add_base_mesh(base_region, source_skeleton, "BaseVisible", true)
	var base_pre_hidden := _add_base_mesh(base_region, source_skeleton, "BasePreHidden", false)

	var adapter = RigAdapter.new()
	var adapter_result: Dictionary = adapter.setup(
		"test.skinned",
		{"body.root": NodePath("SourceSkeleton")},
		{
			"body.region.torso": NodePath("BaseBody"),
			"body.region.arms": NodePath("BaseBody"),
			"body.region.legs": NodePath("BaseBody"),
		}
	)
	_assert(bool(adapter_result.get("success", false)), "Synthetic body-region rig setup failed")
	_assert(adapter.supports_body_region("body.region.torso"), "Synthetic torso region missing")
	_assert(adapter.resolve_body_region_visuals(visual_root, "body.region.torso").size() == 2, "Body region did not expand to its geometry")

	var garment_scene := _packed_skinned_scene("Garment", 2)
	var head_scene := _packed_skinned_scene("HeadReplacement", 1)
	_assert(garment_scene != null, "Synthetic garment scene could not be packed")
	_assert(head_scene != null, "Synthetic head replacement scene could not be packed")

	var catalog = Catalog.new()
	var registration: Dictionary = catalog.register_scene(
		"wearable.outfit.synthetic",
		"test.skinned",
		Catalog.STRATEGY_SKINNED_GARMENT,
		garment_scene,
		["body.region.torso", "body.region.arms", "body.region.legs"],
		Transform3D.IDENTITY,
		head_scene,
		Transform3D.IDENTITY
	)
	_assert(bool(registration.get("success", false)), "Synthetic body replacement catalog registration failed")

	var presenter = Presenter.new()
	presenter.name = "EquipmentPresenter"
	visual_root.add_child(presenter)
	_assert(bool(presenter.setup(visual_root, adapter, catalog).get("success", false)), "Synthetic body replacement presenter setup failed")

	var entry := Domain.Entry.new(
		"item.outfit.synthetic.001",
		"equipment.outfit.synthetic",
		"wearable.outfit.synthetic",
		"body.root",
		["body.torso.outer", "body.arms.outer", "body.legs.outer"]
	)
	var equipped := Domain.Snapshot.new("entity.synthetic.001", "test.layout", 1, [entry])
	var equip_result: Dictionary = presenter.apply_snapshot(equipped)
	_assert(bool(equip_result.get("success", false)), "Synthetic skinned body replacement equip failed")
	_assert(not base_visible.visible, "Visible base body geometry was not hidden")
	_assert(not base_pre_hidden.visible, "Pre-hidden base geometry changed while hidden")
	var outfit_visual: Node3D = presenter.get_visual("item.outfit.synthetic.001")
	_assert(outfit_visual != null, "Synthetic outfit visual missing")
	_assert(outfit_visual != null and outfit_visual.get_node_or_null("BodyReplacement") != null, "Synthetic body replacement bridge missing")
	var equipped_report: Dictionary = presenter.create_report()
	_assert(int(equipped_report.get("hidden_body_visual_count", 0)) == 2, "Duplicate semantic regions inflated hidden body visual count")
	_assert(int(equipped_report.get("body_replacement_item_count", 0)) == 1, "Body replacement item was not reported")
	_assert((equipped_report.get("body_replacement_item_ids", []) as Array).has("item.outfit.synthetic.001"), "Body replacement item ID missing from report")

	var repeated: Dictionary = presenter.apply_snapshot(equipped)
	_assert(bool(repeated.get("success", false)), "Repeated body replacement snapshot failed")
	_assert(not bool((repeated.get("details", {}) as Dictionary).get("changed", true)), "Repeated body replacement snapshot was not idempotent")
	_assert(int(presenter.create_report().get("hidden_body_visual_count", 0)) == 2, "Idempotent reapply changed body hide refcounts")

	var unequipped := Domain.Snapshot.new("entity.synthetic.001", "test.layout", 2, [])
	var remove_result: Dictionary = presenter.apply_snapshot(unequipped)
	_assert(bool(remove_result.get("success", false)), "Synthetic body replacement unequip failed")
	_assert(base_visible.visible, "Base body visibility was not restored after unequip")
	_assert(not base_pre_hidden.visible, "Originally hidden base geometry was incorrectly made visible")
	_assert(int(presenter.create_report().get("hidden_body_visual_count", -1)) == 0, "Body hide state leaked after unequip")
	_assert(int(presenter.create_report().get("body_replacement_item_count", -1)) == 0, "Body replacement node leaked after unequip")

	for cycle in range(10):
		var on_snapshot := Domain.Snapshot.new("entity.synthetic.001", "test.layout", 10 + cycle * 2, [entry])
		var off_snapshot := Domain.Snapshot.new("entity.synthetic.001", "test.layout", 11 + cycle * 2, [])
		_assert(bool(presenter.apply_snapshot(on_snapshot).get("success", false)), "Body replacement lifecycle equip failed at cycle %d" % cycle)
		_assert(not base_visible.visible, "Body replacement lifecycle did not hide base at cycle %d" % cycle)
		_assert(bool(presenter.apply_snapshot(off_snapshot).get("success", false)), "Body replacement lifecycle unequip failed at cycle %d" % cycle)
		_assert(base_visible.visible, "Body replacement lifecycle did not restore base at cycle %d" % cycle)
	await process_frame
	_assert(int(presenter.create_report().get("hidden_body_visual_count", -1)) == 0, "Lifecycle left body hide refs")
	_assert(presenter.get_visual("item.outfit.synthetic.001") == null, "Lifecycle left outfit visual registered")

	visual_root.queue_free()
	_finish()


func _add_test_bones(skeleton: Skeleton3D) -> void:
	skeleton.add_bone("root")
	skeleton.add_bone("spine")
	skeleton.set_bone_parent(1, 0)
	skeleton.add_bone("head")
	skeleton.set_bone_parent(2, 1)


func _add_base_mesh(
	parent: Node3D,
	skeleton: Skeleton3D,
	mesh_name: String,
	initial_visible: bool
) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = mesh_name
	mesh.mesh = BoxMesh.new()
	parent.add_child(mesh)
	mesh.skeleton = mesh.get_path_to(skeleton)
	mesh.visible = initial_visible
	return mesh


func _packed_skinned_scene(scene_name: String, mesh_count: int) -> PackedScene:
	var scene_root := Node3D.new()
	scene_root.name = scene_name
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	scene_root.add_child(skeleton)
	skeleton.owner = scene_root
	_add_test_bones(skeleton)
	for index in range(mesh_count):
		var mesh := MeshInstance3D.new()
		mesh.name = "Mesh%d" % index
		mesh.mesh = BoxMesh.new()
		skeleton.add_child(mesh)
		mesh.owner = scene_root
		mesh.skin = Skin.new()
		mesh.skeleton = mesh.get_path_to(skeleton)
	var packed := PackedScene.new()
	var error := packed.pack(scene_root)
	scene_root.free()
	return packed if error == OK else null


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH7.8 body region replacement: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH7.8 body region replacement: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
