extends RefCounted
## Diagnostics only. Edge Jaccard is a labeled program metric, not body-plan count.
const G = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const P = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const FEATURES := ["module_count", "material_mg", "collector_area_mm2", "absorber_reach_mm", "height_mm", "below_ground_mm", "branching_nodes"]

static func compare(a: Dictionary, b: Dictionary, pa: Dictionary, pb: Dictionary) -> Dictionary:
	if not G.validate(a).is_empty() or not G.validate(b).is_empty(): return {}
	var genes := 0
	for name in G.BOUNDS:
		genes += absi(a.genes[name] - b.genes[name]) * 1000000 / (G.BOUNDS[name][1] - G.BOUNDS[name][0])
	var functional := 0
	for name in FEATURES:
		var x: int = pa.statistics[name]
		var y: int = pb.statistics[name]
		functional += absi(x - y) * 1000000 / maxi(1, maxi(x, y))
	var histogram := 0
	var total := 0
	for role in P.ROLES:
		var x: int = pa.module_roles.get(role, 0)
		var y: int = pb.module_roles.get(role, 0)
		histogram += absi(x - y)
		total += x + y
	var va := {}
	var vb := {}
	_flatten(P.normalized(a.program), "", va)
	_flatten(P.normalized(b.program), "", vb)
	var names := va.keys()
	for key in vb:
		if not va.has(key): names.append(key)
	var changed := 0
	for key in names:
		if not va.has(key) or not vb.has(key) or va[key] != vb[key]: changed += 1
	var ea := _edges(a.program)
	var eb := _edges(b.program)
	var shared := 0
	for edge in ea:
		if eb.has(edge): shared += 1
	var union_size := ea.size() + eb.size() - shared
	return {"program_value_hamming_ppm": changed * 1000000 / maxi(1,names.size()), "gene_l1_ppm": genes / G.BOUNDS.size(), "functional_l1_ppm": functional / FEATURES.size(), "module_histogram_l1_ppm": histogram * 1000000 / maxi(1, total), "program_edge_jaccard_ppm": (union_size - shared) * 1000000 / maxi(1, union_size)}

static func _edges(program: Dictionary) -> Dictionary:
	var edges := {}
	for rule in program.rules:
		if not rule.next.is_empty(): edges[rule.id + "|next|" + rule.next] = true
		for i in rule.actions.size():
			var a: Dictionary = rule.actions[i]
			if a.op == "branch": edges["%s|%d|%s|%s" % [rule.id, i, str(a.enabled), a.target]] = true
	return edges

static func _flatten(value: Variant, path: String, out: Dictionary) -> void:
	if value is Dictionary or value is Array:
		for key in value.keys() if value is Dictionary else range(value.size()):
			_flatten(value[key], path + "/" + str(key), out)
	else:
		out[path] = value
