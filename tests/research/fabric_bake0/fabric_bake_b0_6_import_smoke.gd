extends SceneTree

const SCENES: Array[String] = [
	"eco_evo4_b3_plasticity_preview_lab", "eco_evo4_b6_region_lab",
	"eco_evo5_b2_agents_plot_lab", "eco_evo5_probe2_tree_lab",
	"eco_evo5_t51_creature_lab", "eco_evo5_terrain_fly_lab",
]

func _initialize() -> void:
	var checked := 0
	for name in SCENES:
		var scene = load("res://scenes/labs/ecology/" + name + ".tscn")
		if not scene is PackedScene:
			push_error("B0.6 prerequisite scene did not parse: " + name)
			quit(1)
			return
		var node: Node = scene.instantiate()
		if node == null:
			push_error("B0.6 prerequisite scene did not instantiate: " + name)
			quit(1)
			return
		node.free()
		checked += 1
	print("FABRIC B0.6 Import Prerequisites: PASS (%d assertions)" % checked)
	quit(0)
