extends RefCounted
## Authored genotype programs, not renderer presets and not evidence of natural selection.
const P = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const G = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const NAMES := ["Axial recursive", "Basal multi-axis", "Spreading/reanchoring", "Radial colony", "Supported climbing", "Planar collectors"]

static func make(index: int = 0) -> Dictionary:
	if index < 0 or index >= NAMES.size():
		return {}
	var rules: Array = []
	var leaf := P.rule("leaf", [P.action("differentiate", "collector", [0, 40, 0], 1, 4000), P.action("retire")], "", "light", 100, 1000)
	var root := P.rule("root", [P.action("differentiate", "absorber", [0, -100, 0], 2, 0, 100), P.action("retire")], "", "water", 0, 800)
	match index:
		0:
			# Recursive branching occurs at child axes, not just along one trunk.
			rules = [P.rule("start", [P.action("branch", "support", [0, 0, 0], 0, 0, 0, "root")], "axis"), P.rule("axis", [P.action("extend", "support", [0, 130, 0], 4), P.action("branch", "support", [0, 0, 0], 0, 0, 0, "side"), P.action("branch", "support", [0, 0, 0], 0, 0, 0, "leaf")], "axis"), P.rule("side", [P.action("extend", "support", [90, 70, 30], 3), P.action("branch", "support", [0, 0, 0], 0, 0, 0, "side"), P.action("branch", "support", [0, 0, 0], 0, 0, 0, "leaf")]), leaf, root]
		1:
			rules = [P.rule("start", [P.action("branch", "support", [0, 0, 0], 0, 0, 0, "left"), P.action("branch", "support", [0, 0, 0], 0, 0, 0, "right"), P.action("branch", "support", [0, 0, 0], 0, 0, 0, "middle"), P.action("retire")])]
			for name in ["left", "middle", "right"]:
				var x: int = {"left": -50, "middle": 0, "right": 50}[name]
				rules.append(P.rule(name, [P.action("extend", "support", [x, 140, 0], 4), P.action("branch", "support", [0, 0, 0], 0, 0, 0, "leaf")], name))
			rules.append(leaf)
		2:
			rules = [P.rule("start", [P.action("extend", "transport", [150, 0, 0], 2), P.action("attach", "attachment", [0, 0, 0], 1, 0, 20, "ground"), P.action("branch", "support", [0, 0, 0], 0, 0, 0, "leaf"), P.action("branch", "support", [0, 0, 0], 0, 0, 0, "root")], "start"), leaf, root]
		3:
			var actions: Array = []
			for i in 4:
				actions.append(P.action("branch", "support", [0, 0, 0], 0, 0, 0, "ray%d" % i))
				var delta: Array = [[120, 0, 0], [-120, 0, 0], [0, 0, 120], [0, 0, -120]][i]
				rules.append(P.rule("ray%d" % i, [P.action("extend", "transport", delta, 2), P.action("attach", "attachment", [0, 0, 0], 1, 0, 25, "ground"), P.action("branch", "support", [0, 0, 0], 0, 0, 0, "leaf")], "ray%d" % i))
			actions.append(P.action("retire"))
			rules.append(P.rule("start", actions))
			rules.append(leaf)
		4:
			rules = [P.rule("start", [P.action("attach", "attachment", [0, 0, 0], 1, 0, 20, "host"), P.action("extend", "transport", [0, 160, 0], 2), P.action("branch", "support", [0, 0, 0], 0, 0, 0, "leaf")], "start"), leaf]
		5:
			var flat := P.rule("flat", [P.action("differentiate", "collector", [0, 0, 0], 1, 12000), P.action("retire")])
			rules = [P.rule("start", [P.action("branch", "support", [0, 0, 0], 0, 0, 0, "left"), P.action("branch", "support", [0, 0, 0], 0, 0, 0, "right"), P.action("retire")]), P.rule("left", [P.action("extend", "support", [-100, 70, 0], 2), P.action("branch", "support", [0, 0, 0], 0, 0, 0, "flat")], "left"), P.rule("right", [P.action("extend", "support", [100, 70, 0], 2), P.action("branch", "support", [0, 0, 0], 0, 0, 0, "flat")], "right"), flat]
	return G.create({"schema": P.SCHEMA, "entry": "start", "max_age": 10, "max_depth": 3, "rules": rules}, NAMES[index])
