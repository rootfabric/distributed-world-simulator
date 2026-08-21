extends RefCounted

const Dispersal = preload("res://scripts/research/ecology/plant_spatial_dispersal_v1.gd")
const SCHEMA := "distributed_world_simulator.ecology.p3_4_environmental_gradient.v1"
const VERSION := "1.0.0"
const PARENT_P3_3_CANDIDATE_AGGREGATE := "37342327500b79f71ff2f5adbab51b659015311039ae5105eb00bb1705ac6c41"
const CHANNELS := ["temperature_c", "moisture", "light", "nutrients"]
const NORM := ["moisture", "light", "nutrients"]
const COORD_FIELDS := ["id", "x", "y", "altitude"]
const COEFF_FIELDS := ["base", "x_slope", "y_slope", "altitude_slope", "min", "max"]
const RESULT_FIELDS := ["schema", "version", "parent_p3_3_candidate_aggregate", "spatial_result", "spatial_result_hash", "field_config", "coordinates", "patch_order", "patches", "edge_gradients", "summary", "result_hash"]

static func apply(spatial: Dictionary, coordinates: Array, config: Dictionary) -> Dictionary:
	if not bool(Dispersal.validate_result(spatial).get("success", false)):
		return {}
	var cfg := _norm_config(config)
	if cfg.is_empty(): return {}
	var order := PackedStringArray(spatial.get("patch_order", PackedStringArray()))
	var coords := _norm_coords(coordinates, order)
	if coords.size() != order.size(): return {}
	var patches: Array[Dictionary] = []
	var by_id := {}
	for c in coords:
		var p := _sample_patch(c, cfg)
		if p.is_empty(): return {}
		patches.append(p); by_id[String(p["id"])] = p
	var edges: Array[Dictionary] = []
	for raw in Array(spatial.get("edges", [])):
		if typeof(raw) != TYPE_DICTIONARY: return {}
		var e: Dictionary = raw
		var a: Dictionary = by_id.get(String(e.get("from", "")), {})
		var b: Dictionary = by_id.get(String(e.get("to", "")), {})
		if a.is_empty() or b.is_empty(): return {}
		var dx := float(b["x"]) - float(a["x"])
		var dy := float(b["y"]) - float(a["y"])
		var d := sqrt(dx * dx + dy * dy)
		if not is_finite(d): return {}
		var g := {
			"from": String(e["from"]), "to": String(e["to"]),
			"spatial_edge_record_hash": String(e.get("record_hash", "")),
			"distance_xy": d,
			"altitude_delta": float(b["altitude"]) - float(a["altitude"]),
			"temperature_delta_c": float(b["temperature_c"]) - float(a["temperature_c"]),
			"moisture_delta": float(b["moisture"]) - float(a["moisture"]),
			"light_delta": float(b["light"]) - float(a["light"]),
			"nutrients_delta": float(b["nutrients"]) - float(a["nutrients"]),
		}
		g["record_hash"] = _edge_hash(g); edges.append(g)
	var result := {
		"schema": SCHEMA, "version": VERSION,
		"parent_p3_3_candidate_aggregate": PARENT_P3_3_CANDIDATE_AGGREGATE,
		"spatial_result": spatial.duplicate(true), "spatial_result_hash": String(spatial.get("result_hash", "")),
		"field_config": cfg, "coordinates": coords, "patch_order": order,
		"patches": patches, "edge_gradients": edges, "summary": _summary(patches),
	}
	result["result_hash"] = compute_result_hash(result)
	return result

static func sample_values(coordinate: Dictionary, config: Dictionary) -> Dictionary:
	var cfg := _norm_config(config); var c := _norm_coord(coordinate)
	if cfg.is_empty() or c.is_empty(): return {}
	var p := _sample_patch(c, cfg)
	if p.is_empty(): return {}
	return {"temperature_c": p["temperature_c"], "moisture": p["moisture"], "light": p["light"], "nutrients": p["nutrients"], "resource_availability": p["resource_availability"].duplicate(true)}

static func validate_result(result: Dictionary) -> Dictionary:
	if not _exact(result, RESULT_FIELDS): return _fail("FIELDS")
	if String(result.get("schema", "")) != SCHEMA or String(result.get("version", "")) != VERSION: return _fail("SCHEMA")
	if String(result.get("parent_p3_3_candidate_aggregate", "")) != PARENT_P3_3_CANDIDATE_AGGREGATE: return _fail("PARENT")
	if typeof(result.get("spatial_result")) != TYPE_DICTIONARY or typeof(result.get("field_config")) != TYPE_DICTIONARY or typeof(result.get("coordinates")) != TYPE_ARRAY: return _fail("SOURCE_SHAPE")
	if typeof(result.get("patch_order")) != TYPE_PACKED_STRING_ARRAY or typeof(result.get("patches")) != TYPE_ARRAY or typeof(result.get("edge_gradients")) != TYPE_ARRAY or typeof(result.get("summary")) != TYPE_DICTIONARY: return _fail("DERIVED_SHAPE")
	var spatial: Dictionary = result["spatial_result"]
	if not bool(Dispersal.validate_result(spatial).get("success", false)): return _fail("SPATIAL")
	if String(result.get("spatial_result_hash", "")) != String(spatial.get("result_hash", "")): return _fail("SPATIAL_HASH")
	if not _derived_records_valid(result, PackedStringArray(result["patch_order"]), Array(spatial.get("edges", []))): return _fail("DERIVED_RECORD")
	var expected := apply(spatial, Array(result["coordinates"]), Dictionary(result["field_config"]))
	if expected.is_empty(): return _fail("RECONSTRUCT")
	var current_hash := compute_result_hash(result)
	if current_hash.is_empty() or String(result.get("result_hash", "")) != current_hash: return _fail("HASH")
	if String(result.get("result_hash", "")) != String(expected.get("result_hash", "")): return _fail("DERIVED")
	return {"success": true, "error": ""}

static func _derived_records_valid(result: Dictionary, order: PackedStringArray, spatial_edges: Array) -> bool:
	var patches: Array = result["patches"]; var edges: Array = result["edge_gradients"]
	if patches.size() != order.size() or edges.size() != spatial_edges.size(): return false
	for i in range(patches.size()):
		if typeof(patches[i]) != TYPE_DICTIONARY: return false
		var p: Dictionary = patches[i]
		if not _exact(p, ["id","x","y","altitude","temperature_c","moisture","light","nutrients","resource_availability","record_hash"]): return false
		if String(p["id"]) != String(order[i]) or typeof(p["resource_availability"]) != TYPE_DICTIONARY: return false
		if not _exact(Dictionary(p["resource_availability"]), ["light","water","nutrients"]): return false
		if String(p["record_hash"]) != _patch_hash(p): return false
	for i in range(edges.size()):
		if typeof(edges[i]) != TYPE_DICTIONARY or typeof(spatial_edges[i]) != TYPE_DICTIONARY: return false
		var e: Dictionary = edges[i]; var se: Dictionary = spatial_edges[i]
		if not _exact(e, ["from","to","spatial_edge_record_hash","distance_xy","altitude_delta","temperature_delta_c","moisture_delta","light_delta","nutrients_delta","record_hash"]): return false
		if String(e["from"]) != String(se.get("from","")) or String(e["to"]) != String(se.get("to","")) or String(e["spatial_edge_record_hash"]) != String(se.get("record_hash","")): return false
		if String(e["record_hash"]) != _edge_hash(e): return false
	return true

static func compute_result_hash(result: Dictionary) -> String:
	if typeof(result.get("field_config")) != TYPE_DICTIONARY or typeof(result.get("coordinates")) != TYPE_ARRAY or typeof(result.get("patches")) != TYPE_ARRAY or typeof(result.get("edge_gradients")) != TYPE_ARRAY or typeof(result.get("summary")) != TYPE_DICTIONARY: return ""
	var t := PackedStringArray([SCHEMA, VERSION, PARENT_P3_3_CANDIDATE_AGGREGATE, String(result.get("spatial_result_hash", ""))])
	var cfg: Dictionary = result["field_config"]; var origin: Dictionary = cfg.get("origin", {})
	for f in ["x", "y", "altitude"]: t.append("o|%s=%.12f" % [f, float(origin.get(f, 0.0))])
	for ch in CHANNELS:
		var c: Dictionary = cfg.get(ch, {})
		for f in COEFF_FIELDS: t.append("c|%s|%s=%.12f" % [ch, f, float(c.get(f, 0.0))])
	for raw in Array(result["coordinates"]):
		if typeof(raw) != TYPE_DICTIONARY: return ""
		var c: Dictionary = raw; t.append("p|%s|%.12f|%.12f|%.12f" % [String(c.get("id", "")), float(c.get("x", 0.0)), float(c.get("y", 0.0)), float(c.get("altitude", 0.0))])
	for raw in Array(result["patches"]):
		if typeof(raw) != TYPE_DICTIONARY: return ""
		t.append("ph|%s|%s" % [String(raw.get("id", "")), String(raw.get("record_hash", ""))])
	for raw in Array(result["edge_gradients"]):
		if typeof(raw) != TYPE_DICTIONARY: return ""
		t.append("eh|%s|%s|%s" % [String(raw.get("from", "")), String(raw.get("to", "")), String(raw.get("record_hash", ""))])
	var s: Dictionary = result["summary"]
	for f in ["patch_count", "temperature_min_c", "temperature_max_c", "moisture_min", "moisture_max", "light_min", "light_max", "nutrients_min", "nutrients_max"]: t.append("s|%s=%s" % [f, str(s.get(f, 0))])
	return "\n".join(t).sha256_text()

static func _sample_patch(c: Dictionary, cfg: Dictionary) -> Dictionary:
	var o: Dictionary = cfg["origin"]
	var dx := float(c["x"]) - float(o["x"]); var dy := float(c["y"]) - float(o["y"]); var da := float(c["altitude"]) - float(o["altitude"])
	if not is_finite(dx) or not is_finite(dy) or not is_finite(da): return {}
	var v := {}
	for ch in CHANNELS:
		var k: Dictionary = cfg[ch]
		var raw := float(k["base"]) + float(k["x_slope"]) * dx + float(k["y_slope"]) * dy + float(k["altitude_slope"]) * da
		if not is_finite(raw): return {}
		v[ch] = clampf(raw, float(k["min"]), float(k["max"]))
	var resources := {"light": float(v["light"]), "water": float(v["moisture"]), "nutrients": float(v["nutrients"])}
	var p := {"id": String(c["id"]), "x": float(c["x"]), "y": float(c["y"]), "altitude": float(c["altitude"]), "temperature_c": float(v["temperature_c"]), "moisture": float(v["moisture"]), "light": float(v["light"]), "nutrients": float(v["nutrients"]), "resource_availability": resources}
	p["record_hash"] = _patch_hash(p); return p

static func _norm_config(cfg: Dictionary) -> Dictionary:
	if not _exact(cfg, ["origin", "temperature_c", "moisture", "light", "nutrients"]) or typeof(cfg.get("origin")) != TYPE_DICTIONARY: return {}
	var o := _num_map(Dictionary(cfg["origin"]), ["x", "y", "altitude"])
	if o.is_empty(): return {}
	var out := {"origin": o}
	for ch in CHANNELS:
		if typeof(cfg.get(ch)) != TYPE_DICTIONARY: return {}
		var k := _num_map(Dictionary(cfg[ch]), COEFF_FIELDS)
		if k.is_empty() or float(k["min"]) > float(k["max"]): return {}
		if ch in NORM and (float(k["min"]) < 0.0 or float(k["max"]) > 1.0): return {}
		out[ch] = k
	return out

static func _norm_coords(coords: Array, order: PackedStringArray) -> Array[Dictionary]:
	if coords.size() != order.size(): return []
	var by := {}
	for raw in coords:
		if typeof(raw) != TYPE_DICTIONARY: return []
		var c := _norm_coord(Dictionary(raw)); if c.is_empty() or by.has(String(c["id"])): return []
		by[String(c["id"])] = c
	var out: Array[Dictionary] = []
	for id in order:
		if not by.has(id): return []
		out.append(by[id])
	return out

static func _norm_coord(c: Dictionary) -> Dictionary:
	if not _exact(c, COORD_FIELDS): return {}
	var id := String(c.get("id", "")).strip_edges(); if id.is_empty(): return {}
	var out := {"id": id}
	for f in ["x", "y", "altitude"]:
		var x = c.get(f); if typeof(x) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(x)): return {}
		out[f] = float(x)
	return out

static func _num_map(d: Dictionary, fields: Array) -> Dictionary:
	if not _exact(d, fields): return {}
	var out := {}
	for f in fields:
		var x = d.get(f); if typeof(x) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(x)): return {}
		out[f] = float(x)
	return out

static func _summary(p: Array[Dictionary]) -> Dictionary:
	if p.is_empty(): return {"patch_count": 0, "temperature_min_c": 0.0, "temperature_max_c": 0.0, "moisture_min": 0.0, "moisture_max": 0.0, "light_min": 0.0, "light_max": 0.0, "nutrients_min": 0.0, "nutrients_max": 0.0}
	var s := {"patch_count": p.size(), "temperature_min_c": float(p[0]["temperature_c"]), "temperature_max_c": float(p[0]["temperature_c"]), "moisture_min": float(p[0]["moisture"]), "moisture_max": float(p[0]["moisture"]), "light_min": float(p[0]["light"]), "light_max": float(p[0]["light"]), "nutrients_min": float(p[0]["nutrients"]), "nutrients_max": float(p[0]["nutrients"])}
	for x in p:
		for ch in ["temperature", "moisture", "light", "nutrients"]:
			var src: String = "temperature_c" if ch == "temperature" else String(ch); var lo: String = String(ch) + "_min_c" if ch == "temperature" else String(ch) + "_min"; var hi: String = String(ch) + "_max_c" if ch == "temperature" else String(ch) + "_max"
			s[lo] = minf(float(s[lo]), float(x[src])); s[hi] = maxf(float(s[hi]), float(x[src]))
	return s

static func _patch_hash(p: Dictionary) -> String:
	var r: Dictionary = p["resource_availability"]
	return ("%s|%.12f|%.12f|%.12f|%.12f|%.12f|%.12f|%.12f|%.12f|%.12f|%.12f" % [String(p["id"]), float(p["x"]), float(p["y"]), float(p["altitude"]), float(p["temperature_c"]), float(p["moisture"]), float(p["light"]), float(p["nutrients"]), float(r["light"]), float(r["water"]), float(r["nutrients"])]).sha256_text()

static func _edge_hash(e: Dictionary) -> String:
	return ("%s|%s|%s|%.12f|%.12f|%.12f|%.12f|%.12f|%.12f" % [String(e["from"]), String(e["to"]), String(e["spatial_edge_record_hash"]), float(e["distance_xy"]), float(e["altitude_delta"]), float(e["temperature_delta_c"]), float(e["moisture_delta"]), float(e["light_delta"]), float(e["nutrients_delta"])]).sha256_text()

static func _exact(d: Dictionary, fields: Array) -> bool:
	if d.size() != fields.size(): return false
	for f in fields:
		if not d.has(f): return false
	return true

static func _fail(e: String) -> Dictionary:
	return {"success": false, "error": "ECO_P3_4_" + e}
