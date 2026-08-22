extends RefCounted

## ECO.EVO4/E4.B0.5 — Rich Presentation Spike (presentation layer only).
## Consumes accepted PH1 GrowthGraph skeletons and renders them with
## presentation-only enrichment: tropic trunk bend, presentation twigs,
## phyllotactic leaf whorls, leaf archetypes, species color DNA, dormancy-
## derived flowers, deterministic scatter, atmosphere and cohorts.
## Every stochastic choice is keyed by (individual_seed | graph_hash | label).
## Touches no PH5 core module and no chain hash; fully revertible.

const Skeleton = preload("res://scripts/research/ecology/plant_growth_graph_skeleton_v1.gd")
const RenderDescription = preload("res://scripts/research/ecology/plant_render_description_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo4_bridge_presentation.v1"
const VERSION := "0.5.0"
const GOLDEN_ANGLE_DEG := 137.508
const BRANCH_SIDES := 6

# ---- deterministic hash units -------------------------------------------------

static func _unit(seed_text: String) -> float:
	var digest: String = seed_text.sha256_text()
	return float(digest.substr(0, 12).hex_to_int()) / 281474976710656.0

static func _hash01(a: int, b: int, key: String) -> float:
	return _unit("%d|%d|%s" % [a, b, key])

# ---- palette ------------------------------------------------------------------

static func _species_palette(traits_checksum: String, water_preference: float, shade_tolerance: float) -> Dictionary:
	var foliage_hue := 95.0 + 25.0 * _unit(traits_checksum + "|fol_hue") + 18.0 * clampf(water_preference, 0.0, 1.0)
	var foliage_val := 0.28 + 0.10 * (1.0 - clampf(shade_tolerance, 0.0, 1.0))
	var flower_options: Array[float] = [340.0, 45.0, 300.0, 20.0]
	var flower_hue: float = flower_options[int(_unit(traits_checksum + "|flw_hue") * 4.0) % 4]
	return {
		"foliage_base": Color.from_hsv(foliage_hue / 360.0, 0.62, foliage_val),
		"foliage_jitter": 0.08,
		"branch_base": Color.from_hsv((22.0 + 8.0 * _unit(traits_checksum + "|brn_hue")) / 360.0, 0.42, 0.30 + 0.06 * _unit(traits_checksum + "|brn_val")),
		"flower": Color.from_hsv(flower_hue / 360.0, 0.62, 0.92),
		"flower_core": Color.from_hsv(52.0 / 360.0, 0.75, 0.95),
		"palette_id": traits_checksum.substr(0, 8),
	}

# ---- bend field ---------------------------------------------------------------

static func _bend_params(seed_value: int) -> Dictionary:
	var dir_angle := TAU * _hash01(seed_value, 4, "bendir")
	return {
		"vec": Vector3(cos(dir_angle), 0.0, sin(dir_angle)),
		"mag": 0.22 + 0.45 * _hash01(seed_value, 5, "bendmag"),
		"wobble_amp": 0.05 + 0.09 * _hash01(seed_value, 6, "wobamp"),
		"wobble_freq": 2.2 + 2.2 * _hash01(seed_value, 7, "wobfrq"),
		"phase": TAU * _hash01(seed_value, 8, "wobph"),
	}

static func _bend_point(p: Vector3, height: float, bend: Dictionary) -> Vector3:
	if height <= 0.001:
		return p
	var t: float = clampf(p.y / height, 0.0, 1.0)
	var lateral: Vector3 = Vector3(-bend["vec"].z, 0.0, bend["vec"].x)
	var offset: Vector3 = bend["vec"] * (pow(t, 1.7) * float(bend["mag"]))
	offset += lateral * (sin(p.y * float(bend["wobble_freq"]) + float(bend["phase"])) * float(bend["wobble_amp"]) * t)
	return p + offset

# ---- branch mesh (with vertex colors + presentation twigs) --------------------

static func _perp(axis: Vector3) -> Vector3:
	var candidate := axis.cross(Vector3.UP)
	if candidate.length() < 0.001:
		candidate = axis.cross(Vector3.RIGHT)
	return candidate.normalized()

static func _append_tube(st: SurfaceTool, start: Vector3, end: Vector3, r0: float, r1: float, c0: Color, c1: Color) -> void:
	var axis := (end - start)
	if axis.length() < 0.0005:
		return
	axis = axis.normalized()
	var u := _perp(axis)
	var v := axis.cross(u).normalized()
	for half in range(2):
		var origin: Vector3 = start if half == 0 else end
		var radius: float = r0 if half == 0 else r1
		var col: Color = c0 if half == 0 else c1
		for side in range(BRANCH_SIDES + 1):
			var angle: float = TAU * float(side) / float(BRANCH_SIDES)
			var radial := u * cos(angle) + v * sin(angle)
			st.set_color(col)
			st.set_normal(radial)
			st.add_vertex(origin + radial * radius)

static func _tube_indices(st: SurfaceTool, base: int) -> void:
	for side in range(BRANCH_SIDES):
		var a: int = base + side
		var b: int = base + side + 1
		var c: int = base + BRANCH_SIDES + 1 + side
		var d: int = base + BRANCH_SIDES + 2 + side
		st.add_index(a); st.add_index(c); st.add_index(b)
		st.add_index(b); st.add_index(c); st.add_index(d)

# ---- leaf / flower archetypes --------------------------------------------------

static func _leaf_mesh(archetype: String) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var up := Vector3.UP
	if archetype == "lanceolate":
		var pts := [
			Vector3(0.0, 0.0, 0.0), Vector3(0.11, 0.02, 0.30), Vector3(0.0, 0.03, 1.0),
			Vector3(-0.11, 0.02, 0.30),
		]
		for i in range(4):
			var a: Vector3 = pts[i] as Vector3
			var b: Vector3 = pts[(i + 1) % 4] as Vector3
			st.set_normal(up); st.set_color(Color(1, 1, 1))
			st.add_vertex(a * 0.16); st.set_normal(up); st.set_color(Color(1, 1, 1))
			st.add_vertex(b * 0.16); st.set_normal(up); st.set_color(Color(1, 1, 1))
			st.add_vertex(Vector3(0, 0.05, 0))
	elif archetype == "rounded":
		var w := 0.14
		st.set_normal(up); st.set_color(Color(1, 1, 1)); st.add_vertex(Vector3(-w, 0, 0))
		st.set_normal(up); st.set_color(Color(1, 1, 1)); st.add_vertex(Vector3(w, 0, 0))
		st.set_normal(up); st.set_color(Color(1, 1, 1)); st.add_vertex(Vector3(w * 0.4, 0.02, 0.17))
		st.set_normal(up); st.set_color(Color(1, 1, 1)); st.add_vertex(Vector3(w * 0.4, 0.02, 0.17))
		st.set_normal(up); st.set_color(Color(1, 1, 1)); st.add_vertex(Vector3(-w * 0.4, 0.02, 0.17))
		st.set_normal(up); st.set_color(Color(1, 1, 1)); st.add_vertex(Vector3(0, 0.04, 0.19))
	else: # needle cluster fan
		for blade in range(3):
			var azim: float = deg_to_rad(-40.0 + 40.0 * float(blade))
			var tip := Vector3(sin(azim) * 0.05, 0.06 + 0.05 * float(blade == 1), cos(azim) * 0.16)
			var left := Vector3(sin(azim - 1.35) * 0.008, 0.0, cos(azim - 1.35) * 0.008)
			var right := Vector3(sin(azim + 1.35) * 0.008, 0.0, cos(azim + 1.35) * 0.008)
			st.set_normal(up); st.set_color(Color(1, 1, 1)); st.add_vertex(left)
			st.set_normal(up); st.set_color(Color(1, 1, 1)); st.add_vertex(right)
			st.set_normal(up); st.set_color(Color(1, 1, 1)); st.add_vertex(tip)
	return st.commit(ArrayMesh.new())

static func _flower_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for petal in range(5):
		var ang := TAU * float(petal) / 5.0
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var mid := dir * 0.012 + Vector3.UP * 0.006
		st.set_normal(Vector3.UP); st.set_color(Color(1, 1, 1)); st.add_vertex(mid - dir.rotated(Vector3.UP, 0.5) * 0.014)
		st.set_normal(Vector3.UP); st.set_color(Color(1, 1, 1)); st.add_vertex(mid + dir.rotated(Vector3.UP, 0.5) * 0.014)
		st.set_normal(Vector3.UP); st.set_color(Color(1, 1, 1)); st.add_vertex(mid + dir * 0.02 + Vector3.UP * 0.004)
	st.set_normal(Vector3.UP); st.set_color(Color(1, 1, 1)); st.add_vertex(Vector3(-0.006, 0.008, 0))
	st.set_normal(Vector3.UP); st.set_color(Color(1, 1, 1)); st.add_vertex(Vector3(0.006, 0.008, 0))
	st.set_normal(Vector3.UP); st.set_color(Color(1, 1, 1)); st.add_vertex(Vector3(0, 0.012, 0.004))
	return st.commit(ArrayMesh.new())

# ---- basis helpers -------------------------------------------------------------

static func _basis_from_z(z_axis: Vector3) -> Basis:
	var z := z_axis.normalized()
	var y := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := y.cross(z).normalized()
	y = z.cross(x).normalized()
	return Basis(x, y, z)

# ---- subject builder ------------------------------------------------------------

static func build_rich_subject(
	traits: Dictionary, individual_seed: int, water_preference: float,
	shade_tolerance: float, dormancy_fraction: float, foliage_density: float = 1.0
) -> Dictionary:
	var graph := Skeleton.build(traits, individual_seed)
	if graph.is_empty():
		return {}
	var desc := RenderDescription.build(graph)
	if desc.is_empty():
		return {}
	var graph_hash := String(graph["graph_hash"])
	var bend := _bend_params(individual_seed)
	var height: float = maxf(0.5, float(desc["bounds"]["height_m"]))
	var palette := _species_palette(String(traits["checksum"]), water_preference, shade_tolerance)
	var archetype_options: Array[String] = ["lanceolate", "rounded", "needle"]
	var archetype: String = archetype_options[int(_unit(String(traits["checksum"]) + "|arch") * 3.0) % 3]

	# collect branches from accepted render description (radii reuse) + twigs
	var branches: Array = []
	for br in Array(desc["branches"]):
		branches.append(br)
	# presentation twigs on graph terminals (derived geometry only)
	var graph_parents := {}
	for seg in Array(graph["segments"]):
		graph_parents[String((seg as Dictionary)["parent_segment_id"])] = true
	var terminals: Array = []
	for br in Array(desc["branches"]):
		var segment: Dictionary = br
		if not graph_parents.has(String(segment["segment_id"])):
			terminals.append(segment)
	var twig_count := 0
	for term in terminals:
		var tseg: Dictionary = term
		var tip_start := _bend_point(_vec3(Array(tseg["start"])), height, bend)
		var tip_dir := (_vec3(Array(tseg["end"])) - _vec3(Array(tseg["start"]))).normalized()
		for k in range(2):
			var jitter_key := "twig/%s/%d" % [String(tseg["segment_id"]), k]
			var perp := _perp(tip_dir).rotated(tip_dir, TAU * _hash01(individual_seed, 9, jitter_key))
			var twig_dir := (tip_dir + perp * 0.9 + Vector3.UP * 0.4).normalized()
			var twig_len: float = clampf(float(tseg["length_m"]) * (0.30 + 0.15 * _hash01(individual_seed, 10, jitter_key)), 0.06, 0.55)
			var twig_start := _vec3(Array(tseg["end"]))
			var twig_end := twig_start + twig_dir * twig_len
			branches.append({
				"segment_id": "tw_%s_%d" % [String(tseg["segment_id"]), k],
				"parent_segment_id": String(tseg["segment_id"]),
				"main_axis": false, "axis_order": 3,
				"start": [twig_start.x, twig_start.y, twig_start.z],
				"end": [twig_end.x, twig_end.y, twig_end.z],
				"radius_start_m": 0.0045, "radius_end_m": 0.002,
				"length_m": twig_len,
			})
			twig_count += 1

	# terminals of the ENRICHED branch set (graph terminals + twig tips)
	var enriched_parents := {}
	for br in branches:
		enriched_parents[String((br as Dictionary)["parent_segment_id"])] = true
	terminals = []
	for br in branches:
		var segment: Dictionary = br
		if not enriched_parents.has(String(segment["segment_id"])):
			terminals.append(segment)

	# branch mesh with bend + vertical color gradient
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var index_cursor := 0
	for br in branches:
		var segment: Dictionary = br
		var a := _bend_point(_vec3(Array(segment["start"])), height, bend)
		var b := _bend_point(_vec3(Array(segment["end"])), height, bend)
		var ta: float = clampf(a.y / height, 0.0, 1.0)
		var tb: float = clampf(b.y / height, 0.0, 1.0)
		var c0: Color = (palette["branch_base"] as Color).lightened(0.30 * ta)
		var c1: Color = (palette["branch_base"] as Color).lightened(0.30 * tb)
		_append_tube(st, a, b, float(segment["radius_start_m"]), float(segment["radius_end_m"]), c0, c1)
		_tube_indices(st, index_cursor)
		index_cursor += (BRANCH_SIDES + 1) * 2
	var branch_mesh: ArrayMesh = st.commit(ArrayMesh.new())

	# leaf sites: whorls on terminals (richer on real terminals, small on twigs)
	# + along-lateral leaves; golden-angle azimuths
	var size_scale: float = clampf(height / 4.0, 0.7, 1.5)
	var leaf_transforms: Array[Transform3D] = []
	var leaf_colors: Array[Color] = []
	var flower_transforms: Array[Transform3D] = []
	var flower_density: float = clampf(0.55 - float(dormancy_fraction), 0.05, 0.6)
	for term in terminals:
		var tseg: Dictionary = term
		var tip := _bend_point(_vec3(Array(tseg["end"])), height, bend)
		var stem_dir := (_vec3(Array(tseg["end"])) - _vec3(Array(tseg["start"]))).normalized()
		var is_twig := int(tseg.get("axis_order", 0)) >= 3
		var base_whorl := (3 if is_twig else 6) + int(3.0 * _hash01(individual_seed, 12, "whorl/" + String(tseg["segment_id"])))
		var whorl_n := clampi(int(round(float(base_whorl) * foliage_density)), 2, 14)
		for i in range(whorl_n):
			var azim_deg: float = GOLDEN_ANGLE_DEG * float(i) + 360.0 * _hash01(individual_seed, 13, "az/" + String(tseg["segment_id"]) + "/" + str(i))
			var radial := Vector3(cos(deg_to_rad(azim_deg)), 0.0, sin(deg_to_rad(azim_deg)))
			var leaf_dir := (radial + stem_dir * 0.35 + Vector3.UP * 0.55).normalized()
			var pos := tip + radial * 0.02 + Vector3.UP * 0.01
			_add_leaf_site(leaf_transforms, leaf_colors, individual_seed, i, leaf_dir, pos, size_scale, archetype, palette, graph_hash, false)
			if _hash01(individual_seed, 14, "flw/%s/%d" % [String(tseg["segment_id"]), i]) < flower_density:
				flower_transforms.append(_leaf_basis(leaf_dir, pos + Vector3.UP * 0.035).scaled(Vector3.ONE * size_scale))
	# sparse along-lateral leaves
	for br in Array(desc["branches"]):
		var segment: Dictionary = br
		if bool(segment["main_axis"]):
			continue
		var sdir := (_vec3(Array(segment["end"])) - _vec3(Array(segment["start"]))).normalized()
		var radial2 := _perp(sdir).rotated(sdir, TAU * _hash01(individual_seed, 15, "latleaf/" + String(segment["segment_id"])))
		var ldir := (radial2 + Vector3.UP * 0.5).normalized()
		var along_count := 1 + int(clampf(foliage_density, 1.0, 3.0))
		for li in range(along_count):
			var t_along: float = 0.35 + 0.28 * float(li)
			var pos_along := _bend_point((_vec3(Array(segment["start"])) + (_vec3(Array(segment["end"])) - _vec3(Array(segment["start"]))) * t_along), height, bend)
			var ldir_i := (radial2.rotated(sdir, 0.9 * float(li)) + Vector3.UP * 0.5).normalized()
			_add_leaf_site(leaf_transforms, leaf_colors, individual_seed, li, ldir_i, pos_along, size_scale * 0.85, archetype, palette, graph_hash, true)

	var stats := {
		"schema": SCHEMA, "version": VERSION, "derived_representation": true,
		"source_graph_hash": graph_hash,
		"individual_seed": individual_seed,
		"archetype": archetype, "palette_id": palette["palette_id"],
		"twig_count": twig_count,
		"leaf_count": leaf_transforms.size(),
		"flower_count": flower_transforms.size(),
		"height_m": height,
	}
	stats["presentation_hash"] = _presentation_hash(stats)
	return {
		"stats": stats, "branch_mesh": branch_mesh,
		"leaf_mesh": _leaf_mesh(archetype),
		"flower_mesh": _flower_mesh(),
		"leaf_transforms": leaf_transforms, "leaf_colors": leaf_colors,
		"flower_transforms": flower_transforms,
		"flower_color": palette["flower"], "flower_core_color": palette["flower_core"],
	}

static func _add_leaf_site(
	transforms: Array[Transform3D], colors: Array[Color], seed_value: int, index: int,
	leaf_dir: Vector3, pos: Vector3, size_scale: float, archetype: String, palette: Dictionary,
	graph_hash: String, along_lateral: bool
) -> void:
	var key := "leaf/%d/%s/%s" % [index, graph_hash.substr(0, 8), str(along_lateral)]
	var roll: float = TAU * _hash01(seed_value, 16, key + "/roll")
	var len_scale: float = (0.85 + 0.4 * _hash01(seed_value, 17, key + "/len")) * size_scale
	var basis := _basis_from_z(leaf_dir).rotated(leaf_dir, roll)
	transforms.append(Transform3D(basis, pos).scaled(Vector3(len_scale, len_scale, len_scale)))
	var jitter: float = 1.0 - palette["foliage_jitter"] + 2.0 * palette["foliage_jitter"] * _hash01(seed_value, 18, key + "/col")
	colors.append((palette["foliage_base"] as Color).darkened(1.0 - jitter))

static func _leaf_basis(dir: Vector3, pos: Vector3) -> Transform3D:
	return Transform3D(_basis_from_z(dir), pos)

static func _presentation_hash(stats: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA, VERSION, String(stats["source_graph_hash"]), str(int(stats["individual_seed"])),
		String(stats["archetype"]), String(stats["palette_id"]),
		str(int(stats["twig_count"])), str(int(stats["leaf_count"])), str(int(stats["flower_count"])),
	])
	return "|".join(tokens).sha256_text()

static func _vec3(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
