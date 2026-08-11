extends RefCounted

const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.plant_growth_graph_skeleton.v1"
const VERSION := "1.0.0"
const MAX_MAIN_SEGMENTS := 64
const MAX_TOTAL_SEGMENTS := 512

static func build(development_traits: Dictionary, individual_seed: int) -> Dictionary:
	if not bool(Traits.validate(development_traits).get("success", false)) or individual_seed < 0:
		return {}
	var internode := float(development_traits["internode_length_m"])
	var max_height := float(development_traits["max_height_m"])
	var main_count := clampi(int(ceil(max_height / internode)), 1, MAX_MAIN_SEGMENTS)
	var graph := Contract.create_empty_growth_graph(individual_seed, String(development_traits["checksum"]))
	if graph.is_empty():
		return {}
	graph["schema"] = SCHEMA
	graph["version"] = VERSION
	graph["traits_id"] = String(development_traits["traits_id"])
	var segments: Array = []
	var y := 0.0
	var branch_roots := 0
	for i in range(main_count):
		var remaining := max_height - y
		if remaining <= 0.000000001:
			break
		var length := minf(internode, remaining)
		var start := Vector3(0.0, y, 0.0)
		var end := start + Vector3.UP * length
		segments.append(_segment("m%02d" % i, "" if i == 0 else "m%02d" % (i - 1), 0, start, end, length, true))
		y = end.y
		if segments.size() >= MAX_TOTAL_SEGMENTS:
			break
		if i == 0 or i >= main_count - 1:
			continue
		var apical := float(development_traits["apical_dominance"])
		var probability := float(development_traits["branch_probability"]) * (1.0 - 0.75 * apical)
		if _unit(individual_seed, "branch/%d" % i) >= probability:
			continue
		branch_roots += 1
		_add_lateral_chain(segments, development_traits, individual_seed, i, start, branch_roots)
		if segments.size() >= MAX_TOTAL_SEGMENTS:
			break
	graph["segments"] = segments
	graph["metrics"] = _metrics(segments, branch_roots)
	graph["graph_hash"] = compute_graph_hash(graph)
	return graph

static func _add_lateral_chain(segments: Array, development_traits: Dictionary, individual_seed: int, main_index: int, origin: Vector3, branch_index: int) -> void:
	var depth := int(development_traits["branching_depth"])
	var nominal_angle := deg_to_rad(float(development_traits["branch_angle_deg"]))
	var azimuth := TAU * _unit(individual_seed, "azimuth/%d" % main_index)
	var angle_jitter := lerpf(0.92, 1.08, _unit(individual_seed, "angle/%d" % main_index))
	var angle := clampf(nominal_angle * angle_jitter, 0.0, deg_to_rad(89.0))
	var direction := Vector3(sin(angle) * cos(azimuth), cos(angle), sin(angle) * sin(azimuth)).normalized()
	var current := origin
	var parent_id := "m%02d" % main_index
	var crown_spread := float(development_traits["crown_spread_m"])
	for j in range(depth):
		if segments.size() >= MAX_TOTAL_SEGMENTS:
			return
		var taper := pow(float(development_traits["branch_length_ratio"]), 1.0 + 0.15 * j)
		var jitter := lerpf(0.88, 1.12, _unit(individual_seed, "length/%d/%d" % [main_index, j]))
		var length := float(development_traits["internode_length_m"]) * taper * jitter
		var radial := Vector2(current.x, current.z).length()
		var horizontal_fraction := maxf(0.000001, Vector2(direction.x, direction.z).length())
		var remaining_radial := maxf(0.0, crown_spread - radial)
		length = minf(length, remaining_radial / horizontal_fraction if remaining_radial > 0.0 else 0.0)
		if length <= 0.000001:
			return
		var end := current + direction * length
		var id := "b%02d_%02d" % [branch_index, j]
		segments.append(_segment(id, parent_id, j + 1, current, end, length, false))
		parent_id = id
		current = end

static func _segment(id: String, parent_id: String, axis_order: int, start: Vector3, end: Vector3, length: float, main_axis: bool) -> Dictionary:
	return {"segment_id":id,"parent_segment_id":parent_id,"axis_order":axis_order,"main_axis":main_axis,"start":[start.x,start.y,start.z],"end":[end.x,end.y,end.z],"length_m":length}

static func _metrics(segments: Array, lateral_branch_count: int) -> Dictionary:
	var max_height := 0.0
	var radius := 0.0
	var total_length := 0.0
	var main_count := 0
	var lateral_count := 0
	var angle_sum := 0.0
	for segment in segments:
		var s: Dictionary = segment
		var a := _vec3(Array(s["start"]))
		var b := _vec3(Array(s["end"]))
		max_height = maxf(max_height, maxf(a.y, b.y))
		radius = maxf(radius, maxf(Vector2(a.x, a.z).length(), Vector2(b.x, b.z).length()))
		total_length += float(s["length_m"])
		if bool(s["main_axis"]):
			main_count += 1
		else:
			lateral_count += 1
			var direction := (b - a).normalized()
			angle_sum += rad_to_deg(acos(clampf(direction.dot(Vector3.UP), -1.0, 1.0)))
	return {"segment_count":segments.size(),"main_axis_segment_count":main_count,"lateral_segment_count":lateral_count,"lateral_branch_count":lateral_branch_count,"height_m":max_height,"horizontal_radius_m":radius,"total_length_m":total_length,"mean_lateral_angle_deg":0.0 if lateral_count == 0 else angle_sum / lateral_count}

static func compute_graph_hash(graph: Dictionary) -> String:
	var tokens := PackedStringArray([SCHEMA,VERSION,str(int(graph.get("individual_seed", -1))),String(graph.get("development_traits_checksum", ""))])
	for segment in Array(graph.get("segments", [])):
		var s: Dictionary = segment
		tokens.append("%s|%s|%d|%s|%s|%.9f" % [String(s["segment_id"]),String(s["parent_segment_id"]),int(s["axis_order"]),_vec_token(Array(s["start"])),_vec_token(Array(s["end"])),float(s["length_m"])])
	return "\n".join(tokens).sha256_text()

static func _unit(seed: int, key: String) -> float:
	var digest := (str(seed) + "|" + key).sha256_text()
	var value := digest.substr(0, 12).hex_to_int()
	return float(value) / 281474976710655.0

static func _vec3(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

static func _vec_token(values: Array) -> String:
	return "%.9f,%.9f,%.9f" % [float(values[0]), float(values[1]), float(values[2])]
