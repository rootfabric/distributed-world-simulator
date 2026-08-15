extends SceneTree

const SCENE_PATH := "res://scenes/labs/ecology/eco_vis1_2_spatial_projection.tscn"
const EXPECTED_PATCHES := ["A", "B", "C"]
var _assertions := 0
var _failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect(packed != null, "VIS1.2 scene loads")
	if packed == null:
		_finish(); return
	var lab := packed.instantiate() as Node3D
	_expect(lab != null, "VIS1.2 scene instantiates")
	if lab == null:
		_finish(); return
	get_root().add_child(lab)
	await process_frame
	await process_frame

	var snapshot_value: Variant = lab.call("get_spatial_snapshot")
	_expect(typeof(snapshot_value) == TYPE_DICTIONARY, "spatial snapshot is exposed")
	var snapshot: Dictionary = snapshot_value if typeof(snapshot_value) == TYPE_DICTIONARY else {}
	_expect(int(snapshot.get("step_index", -1)) == 5, "VIS1.2 projects the configured ecology frame")
	_expect(PackedStringArray(snapshot.get("patch_order", PackedStringArray())) == PackedStringArray(EXPECTED_PATCHES), "canonical patch order is preserved")
	_expect(String(snapshot.get("snapshot_hash", "")).length() == 64, "source snapshot hash is present")
	_expect(float(snapshot.get("total_final_biomass_kg", 0.0)) > 0.0, "source ecology carries biomass")

	var projection := lab.get_node_or_null("SpatialEcologyProjection") as Node3D
	_expect(projection != null, "derived spatial projection root exists")
	if projection != null:
		_expect(projection.get_node_or_null("DispersalLinks") is MeshInstance3D, "dispersal links are materialized")
		for patch_id in EXPECTED_PATCHES:
			var patch_root := projection.get_node_or_null("Patch_%s" % patch_id) as Node3D
			_expect(patch_root != null, "patch %s is materialized" % patch_id)
			if patch_root != null:
				_expect(patch_root.get_node_or_null("PatchDisc") is MeshInstance3D, "patch %s disc exists" % patch_id)
				_expect(patch_root.get_node_or_null("PatchLabel") is Label3D, "patch %s label exists" % patch_id)

	var bounds := lab.call("get_polygon_bounds") as Rect2
	for patch_id in EXPECTED_PATCHES:
		var p: Vector3 = lab.call("get_patch_world_position", String(patch_id))
		_expect(bounds.has_point(Vector2(p.x, p.z)), "patch %s lies inside polygon" % patch_id)
		_expect(absf(p.y - float(lab.call("sample_terrain_height", p.x, p.z))) < 0.000001, "patch %s follows terrain" % patch_id)

	var hash_a := String(lab.call("get_projection_hash"))
	_expect(hash_a.length() == 64, "projection has deterministic hash")
	var snapshot_before := lab.call("get_spatial_snapshot") as Dictionary
	lab.call("rebuild_spatial_projection")
	await process_frame
	await process_frame
	var hash_b := String(lab.call("get_projection_hash"))
	var snapshot_after := lab.call("get_spatial_snapshot") as Dictionary
	_expect(hash_a == hash_b, "rebuild preserves projection hash")
	_expect(snapshot_before == snapshot_after, "derived projection does not mutate ecology snapshot")

	_expect(lab.get_node_or_null("EnvironmentReferences/WaterGradientAxis") is MeshInstance3D, "VIS1.1 environment reference survives")
	var status := lab.get_node_or_null("HUD/Margin/Panel/VBox/Status") as Label
	_expect(status != null and status.text.contains("snapshot=VALID"), "HUD reports valid ecology snapshot")
	_expect(status != null and status.text.contains("Patches:"), "HUD exposes patch biomass diagnostics")

	lab.queue_free()
	await process_frame
	_finish()

func _expect(condition: bool, message: String) -> void:
	_assertions += 1
	if condition: return
	_failures += 1
	push_error("ECO.VIS1.2 assertion failed: %s" % message)

func _finish() -> void:
	if _failures == 0:
		print("ECO.VIS1.2 headless scene smoke: PASS (%d assertions)" % _assertions)
		quit(0)
		return
	print("ECO.VIS1.2 headless scene smoke: FAIL (%d assertions, %d failures)" % [_assertions, _failures])
	quit(1)
