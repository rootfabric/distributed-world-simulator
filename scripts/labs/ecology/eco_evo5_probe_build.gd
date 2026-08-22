extends SceneTree

## ECO.EVO5 probe: per-genome build diagnostics for build_rich_subject.

const Presentation = preload("res://scripts/research/ecology/evo4_bridge_presentation_v1.gd")

func _init() -> void:
	var man = JSON.parse_string(FileAccess.get_file_as_string("res://validation/ecology/evo4_b6_region_manifest.v1.json"))
	var idx := 0
	for gid in ((man as Dictionary)["species_traits"] as Dictionary).keys():
		var sp: Dictionary = (man["species_traits"] as Dictionary)[gid]
		var t: Dictionary = (sp["development_traits"] as Dictionary).duplicate(true)
		t["branching_depth"] = int(t["branching_depth"])
		var built := Presentation.build_rich_subject(t, 123456 + idx * 7919,
			float(sp["water_preference"]), float(sp["shade_tolerance"]),
			float(sp["dormancy_fraction"]), 1.6)
		if built.is_empty():
			print(gid, " EMPTY")
			idx += 1
			continue
		var bm = built.get("branch_mesh")
		var ba := (bm as Mesh).get_aabb() if bm != null else AABB()
		var min_y := 999.0
		var max_y := -999.0
		var lt = built.get("leaf_transforms")
		if lt != null:
			for xf in lt:
				min_y = minf(min_y, (xf as Transform3D).origin.y)
				max_y = maxf(max_y, (xf as Transform3D).origin.y)
		print("%s branch_aabb=(%.2f %.2f %.2f)-(%.2f %.2f %.2f) leaves_y=[%.2f..%.2f] n_leaves=%d" % [
			gid.substr(0, 10), ba.position.x, ba.position.y, ba.position.z,
			ba.size.x, ba.size.y, ba.size.z, min_y, max_y,
			(lt as Array).size() if lt != null else 0])
		idx += 1
	quit(0)
