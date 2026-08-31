class_name FabricBakeContactWrenchCompilerV1
extends RefCounted

const SCHEMA := "planet_simulator.fabric_bake_contact_wrench_model.v1"
const KIND := "B0_3_CONTACT_WRENCH_BAKE"
const COMPILER_VERSION := "FABRIC-BAKE/B0.3-CONTACT-WRENCH-R1"
const FABRIC0_18_CLOSURE := "b9f4a11cb7c31e47884d12eaad2985811e0b6563"
const FABRIC0_18_EXACT_PHYSICS := "e079565b4b9cd0dae530ff5042f057ce8fa0d0cc"
const BRIDGE1_CLOSURE := "82a44ac8f6e362456cb2f8c150145e73afb17157"
const EPS := 1.0e-12
const FRAME_TOLERANCE := 1.0e-9
const COPLANAR_TOLERANCE := 1.0e-9
const DEFAULT_MIN_REDUCTION_RATIO := 2.0

static func compile(request: Dictionary) -> Dictionary:
	var checked := _validate_request(request)
	if not bool(checked.get("ok", false)):
		return checked
	var origin := _vec3(request["origin"])
	var normal := _vec3(request["normal"])
	var t1 := _vec3(request["t1"])
	var t2 := _vec3(request["t2"])
	var normalized_points := _normalized_points(Array(request["points"]), origin, normal, t1, t2)
	if not bool(normalized_points.get("ok", false)):
		return normalized_points
	var unique_points: Array = normalized_points["points"]
	if unique_points.size() < 3:
		return _no_safe("DEGENERATE_SUPPORT_POLYGON", {"unique_point_count": unique_points.size()})
	var hull := _convex_hull(unique_points)
	if hull.size() < 3:
		return _no_safe("DEGENERATE_SUPPORT_POLYGON", {"hull_point_count": hull.size()})
	var full_count := Array(request["points"]).size()
	var generator_count := hull.size()
	var ratio := float(full_count) / float(generator_count)
	var minimum_ratio := float(request.get("minimum_reduction_ratio", DEFAULT_MIN_REDUCTION_RATIO))
	if ratio + EPS < minimum_ratio:
		return _no_safe("INSUFFICIENT_CONTACT_REDUCTION", {
			"full_member_count": full_count,
			"generator_count": generator_count,
			"reduction_ratio": ratio,
			"minimum_reduction_ratio": minimum_ratio,
		})
	var generator_payload: Array = []
	for point_any in hull:
		var point: Dictionary = point_any
		generator_payload.append({
			"member_id": String(point["id"]),
			"r": _arr3(Vector3(point["r"])),
			"uv": [float(point["x"]), float(point["y"])],
		})
	var model := {
		"schema": SCHEMA,
		"kind": KIND,
		"model_id": String(request["model_id"]),
		"patch_id": String(request["patch_id"]),
		"source_frontier_hash": String(request["source_frontier_hash"]),
		"physical_graph_hash": String(request["physical_graph_hash"]),
		"parent_artifact_checksum": String(request["parent_artifact_checksum"]),
		"authority_checksum": String(request["authority_checksum"]),
		"compiler_version": COMPILER_VERSION,
		"fabric0_18_closure": FABRIC0_18_CLOSURE,
		"fabric0_18_exact_physics": FABRIC0_18_EXACT_PHYSICS,
		"bridge1_closure": BRIDGE1_CLOSURE,
		"accepted_domain": "COPLANAR_UNIFORM_PERSISTENT_WRENCH_PATCH_SHARED_NORMAL_BUDGET",
		"origin": _arr3(origin),
		"normal": _arr3(normal),
		"t1": _arr3(t1),
		"t2": _arr3(t2),
		"plane_offset": float(normalized_points["plane_offset"]),
		"normal_support_limit": float(request["normal_support_limit"]),
		"mu_tangent": float(request["mu_tangent"]),
		"mu_rolling": float(request["mu_rolling"]),
		"mu_torsion": float(request["mu_torsion"]),
		"effective_radius": float(request["effective_radius"]),
		"full_member_count": full_count,
		"unique_member_position_count": unique_points.size(),
		"generator_count": generator_count,
		"reduction_ratio": ratio,
		"generators": generator_payload,
		"internal_lambda_persisted": false,
		"warm_start_persisted": false,
		"contact_age_persisted": false,
		"mode_history_persisted": false,
		"reconstruction_policy": "DISCARD_AND_REDERIVE_CONTACT_STATE",
	}
	model["model_hash"] = _hash(_hash_payload(model))
	return {
		"ok": true,
		"status": "BAKE_READY",
		"model": model,
		"diagnostics": {
			"full_member_count": full_count,
			"generator_count": generator_count,
			"reduction_ratio": ratio,
			"exact_support_function_preservation": true,
		},
	}

static func validate_model(model: Dictionary) -> Dictionary:
	var artifact := model
	for key in [
		"schema", "kind", "model_id", "patch_id", "source_frontier_hash", "physical_graph_hash",
		"parent_artifact_checksum", "authority_checksum", "compiler_version", "fabric0_18_closure",
		"fabric0_18_exact_physics", "bridge1_closure", "accepted_domain", "origin", "normal", "t1", "t2",
		"plane_offset", "normal_support_limit", "mu_tangent", "mu_rolling", "mu_torsion", "effective_radius",
		"full_member_count", "unique_member_position_count", "generator_count", "reduction_ratio", "generators",
		"internal_lambda_persisted", "warm_start_persisted", "contact_age_persisted", "mode_history_persisted",
		"reconstruction_policy", "model_hash"
	]:
		if not artifact.has(key):
			return {"ok": false, "code": "B0_3_MODEL_FIELD_MISSING", "field": key}
	if String(artifact["schema"]) != SCHEMA or String(artifact["kind"]) != KIND:
		return {"ok": false, "code": "B0_3_MODEL_SCHEMA_MISMATCH"}
	if String(artifact["model_id"]).is_empty() or String(artifact["patch_id"]).is_empty():
		return {"ok": false, "code": "B0_3_MODEL_ID_EMPTY"}
	if String(artifact["compiler_version"]) != COMPILER_VERSION:
		return {"ok": false, "code": "B0_3_COMPILER_VERSION_MISMATCH"}
	if String(artifact["fabric0_18_closure"]) != FABRIC0_18_CLOSURE or String(artifact["fabric0_18_exact_physics"]) != FABRIC0_18_EXACT_PHYSICS:
		return {"ok": false, "code": "B0_3_PHYSICAL_CORE_PREDECESSOR_MISMATCH"}
	if String(artifact["bridge1_closure"]) != BRIDGE1_CLOSURE:
		return {"ok": false, "code": "B0_3_BRIDGE1_PREDECESSOR_MISMATCH"}
	if String(artifact["accepted_domain"]) != "COPLANAR_UNIFORM_PERSISTENT_WRENCH_PATCH_SHARED_NORMAL_BUDGET":
		return {"ok": false, "code": "B0_3_ACCEPTED_DOMAIN_MISMATCH"}
	for key in ["source_frontier_hash", "physical_graph_hash", "parent_artifact_checksum", "authority_checksum"]:
		if not _is_hex64(String(artifact[key])):
			return {"ok": false, "code": "B0_3_BAD_PROVENANCE_HASH", "field": key}
	var origin := _to_vec3(artifact["origin"])
	var normal := _to_vec3(artifact["normal"])
	var t1 := _to_vec3(artifact["t1"])
	var t2 := _to_vec3(artifact["t2"])
	if not bool(origin.get("ok", false)) or not bool(normal.get("ok", false)) or not bool(t1.get("ok", false)) or not bool(t2.get("ok", false)):
		return {"ok": false, "code": "B0_3_BAD_MODEL_FRAME_VECTOR"}
	var frame := _validate_frame(normal["value"], t1["value"], t2["value"])
	if not bool(frame.get("ok", false)):
		return frame
	if not _finite_number(artifact["plane_offset"]):
		return {"ok": false, "code": "B0_3_BAD_PLANE_OFFSET"}
	if not _finite_number(artifact["normal_support_limit"]) or float(artifact["normal_support_limit"]) <= 0.0:
		return {"ok": false, "code": "B0_3_BAD_NORMAL_SUPPORT_LIMIT"}
	for key in ["mu_tangent", "mu_rolling", "mu_torsion", "effective_radius"]:
		if not _finite_number(artifact[key]) or float(artifact[key]) < 0.0:
			return {"ok": false, "code": "B0_3_BAD_WRENCH_PARAMETER", "field": key}
	for key in ["full_member_count", "unique_member_position_count", "generator_count"]:
		if not (artifact[key] is int) or int(artifact[key]) < 1:
			return {"ok": false, "code": "B0_3_BAD_MODEL_COUNT", "field": key}
	if int(artifact["generator_count"]) < 3 or int(artifact["generator_count"]) > int(artifact["unique_member_position_count"]) or int(artifact["unique_member_position_count"]) > int(artifact["full_member_count"]):
		return {"ok": false, "code": "B0_3_INCONSISTENT_MODEL_COUNTS"}
	if not _finite_number(artifact["reduction_ratio"]) or absf(float(artifact["reduction_ratio"]) - float(artifact["full_member_count"]) / float(artifact["generator_count"])) > 1.0e-12:
		return {"ok": false, "code": "B0_3_REDUCTION_RATIO_MISMATCH"}
	if not (artifact["generators"] is Array) or Array(artifact["generators"]).size() != int(artifact["generator_count"]):
		return {"ok": false, "code": "B0_3_GENERATOR_COUNT_MISMATCH"}
	var generator_ids := {}
	for generator_any in Array(artifact["generators"]):
		if not (generator_any is Dictionary):
			return {"ok": false, "code": "B0_3_BAD_GENERATOR"}
		var generator: Dictionary = generator_any
		if not generator.has("member_id") or not generator.has("r") or not generator.has("uv"):
			return {"ok": false, "code": "B0_3_INCOMPLETE_GENERATOR"}
		var member_id := String(generator["member_id"])
		if member_id.is_empty() or generator_ids.has(member_id):
			return {"ok": false, "code": "B0_3_INVALID_GENERATOR_ID", "member_id": member_id}
		generator_ids[member_id] = true
		var r := _to_vec3(generator["r"])
		if not bool(r.get("ok", false)):
			return {"ok": false, "code": "B0_3_BAD_GENERATOR_POSITION", "member_id": member_id}
		if not (generator["uv"] is Array) or Array(generator["uv"]).size() != 2 or not _finite_number(generator["uv"][0]) or not _finite_number(generator["uv"][1]):
			return {"ok": false, "code": "B0_3_BAD_GENERATOR_UV", "member_id": member_id}
		var rv: Vector3 = r["value"]
		if absf(normal["value"].dot(rv) - float(artifact["plane_offset"])) > COPLANAR_TOLERANCE:
			return {"ok": false, "code": "B0_3_GENERATOR_OUTSIDE_PLANE", "member_id": member_id}
		if absf(t1["value"].dot(rv) - float(generator["uv"][0])) > 1.0e-10 or absf(t2["value"].dot(rv) - float(generator["uv"][1])) > 1.0e-10:
			return {"ok": false, "code": "B0_3_GENERATOR_UV_MISMATCH", "member_id": member_id}
	for key in ["internal_lambda_persisted", "warm_start_persisted", "contact_age_persisted", "mode_history_persisted"]:
		if not (artifact[key] is bool) or bool(artifact[key]):
			return {"ok": false, "code": "B0_3_TRANSIENT_CONTACT_STATE_PERSISTED", "field": key}
	if String(artifact["reconstruction_policy"]) != "DISCARD_AND_REDERIVE_CONTACT_STATE":
		return {"ok": false, "code": "B0_3_RECONSTRUCTION_POLICY_MISMATCH"}
	if not _is_hex64(String(artifact["model_hash"])):
		return {"ok": false, "code": "B0_3_BAD_MODEL_HASH"}
	var expected := _hash(_hash_payload(artifact))
	if String(artifact["model_hash"]) != expected:
		return {"ok": false, "code": "B0_3_MODEL_HASH_MISMATCH", "expected": expected, "actual": artifact["model_hash"]}
	return {"ok": true}

static func _validate_request(request: Dictionary) -> Dictionary:
	for key in [
		"model_id", "patch_id", "source_frontier_hash", "physical_graph_hash", "parent_artifact_checksum",
		"authority_checksum", "origin", "normal", "t1", "t2", "points", "normal_support_limit",
		"mu_tangent", "mu_rolling", "mu_torsion", "effective_radius"
	]:
		if not request.has(key):
			return {"ok": false, "code": "B0_3_REQUEST_FIELD_MISSING", "field": key}
	if String(request["model_id"]).is_empty() or String(request["patch_id"]).is_empty():
		return {"ok": false, "code": "B0_3_ID_EMPTY"}
	for key in ["source_frontier_hash", "physical_graph_hash", "parent_artifact_checksum", "authority_checksum"]:
		if not _is_hex64(String(request[key])):
			return {"ok": false, "code": "B0_3_BAD_PROVENANCE_HASH", "field": key}
	var origin := _to_vec3(request["origin"])
	var normal := _to_vec3(request["normal"])
	var t1 := _to_vec3(request["t1"])
	var t2 := _to_vec3(request["t2"])
	if not bool(origin.get("ok", false)) or not bool(normal.get("ok", false)) or not bool(t1.get("ok", false)) or not bool(t2.get("ok", false)):
		return {"ok": false, "code": "B0_3_BAD_FRAME_VECTOR"}
	var frame := _validate_frame(normal["value"], t1["value"], t2["value"])
	if not bool(frame.get("ok", false)):
		return frame
	if not (request["points"] is Array) or Array(request["points"]).size() < 4:
		return {"ok": false, "code": "B0_3_TOO_FEW_MANIFOLD_POINTS"}
	if not _finite_number(request["normal_support_limit"]) or float(request["normal_support_limit"]) <= 0.0:
		return {"ok": false, "code": "B0_3_BAD_NORMAL_SUPPORT_LIMIT"}
	for key in ["mu_tangent", "mu_rolling", "mu_torsion", "effective_radius"]:
		if not _finite_number(request[key]) or float(request[key]) < 0.0:
			return {"ok": false, "code": "B0_3_BAD_WRENCH_PARAMETER", "field": key}
	var minimum_ratio := float(request.get("minimum_reduction_ratio", DEFAULT_MIN_REDUCTION_RATIO))
	if not is_finite(minimum_ratio) or minimum_ratio < 1.0:
		return {"ok": false, "code": "B0_3_BAD_MINIMUM_REDUCTION_RATIO"}
	return {"ok": true}

static func _validate_frame(normal: Vector3, t1: Vector3, t2: Vector3) -> Dictionary:
	if not _finite_vec3(normal) or not _finite_vec3(t1) or not _finite_vec3(t2):
		return {"ok": false, "code": "B0_3_NONFINITE_CONTACT_FRAME"}
	if absf(normal.length() - 1.0) > FRAME_TOLERANCE or absf(t1.length() - 1.0) > FRAME_TOLERANCE or absf(t2.length() - 1.0) > FRAME_TOLERANCE:
		return {"ok": false, "code": "B0_3_NONUNIT_CONTACT_FRAME"}
	if absf(normal.dot(t1)) > FRAME_TOLERANCE or absf(normal.dot(t2)) > FRAME_TOLERANCE or absf(t1.dot(t2)) > FRAME_TOLERANCE:
		return {"ok": false, "code": "B0_3_NONORTHOGONAL_CONTACT_FRAME"}
	if normal.cross(t1).dot(t2) < 1.0 - 1.0e-8:
		return {"ok": false, "code": "B0_3_LEFT_HANDED_CONTACT_FRAME"}
	return {"ok": true}

static func _normalized_points(points: Array, origin: Vector3, normal: Vector3, t1: Vector3, t2: Vector3) -> Dictionary:
	var seen_ids := {}
	var plane_offset := INF
	var projected: Array = []
	for point_any in points:
		if not (point_any is Dictionary):
			return {"ok": false, "code": "B0_3_BAD_MANIFOLD_POINT"}
		var point: Dictionary = point_any
		var id := String(point.get("id", ""))
		if id.is_empty():
			return {"ok": false, "code": "B0_3_MANIFOLD_POINT_ID_EMPTY"}
		if seen_ids.has(id):
			return {"ok": false, "code": "B0_3_DUPLICATE_MANIFOLD_POINT_ID", "id": id}
		seen_ids[id] = true
		var parsed := _to_vec3(point.get("position", null))
		if not bool(parsed.get("ok", false)):
			return {"ok": false, "code": "B0_3_BAD_MANIFOLD_POINT_POSITION", "id": id}
		var position: Vector3 = parsed["value"]
		var r := position - origin
		var offset := normal.dot(r)
		if not is_finite(plane_offset):
			plane_offset = offset
		elif absf(offset - plane_offset) > COPLANAR_TOLERANCE:
			return _no_safe("NON_COPLANAR_CONTACT_PATCH", {"id": id, "plane_error": absf(offset - plane_offset)})
		projected.append({"id": id, "r": r, "x": t1.dot(r), "y": t2.dot(r)})
	projected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if absf(float(a["x"]) - float(b["x"])) > EPS:
			return float(a["x"]) < float(b["x"])
		if absf(float(a["y"]) - float(b["y"])) > EPS:
			return float(a["y"]) < float(b["y"])
		return String(a["id"]) < String(b["id"])
	)
	var unique: Array = []
	for point_any in projected:
		var point: Dictionary = point_any
		if unique.is_empty():
			unique.append(point)
			continue
		var previous: Dictionary = unique[-1]
		if absf(float(point["x"]) - float(previous["x"])) <= EPS and absf(float(point["y"]) - float(previous["y"])) <= EPS:
			continue
		unique.append(point)
	return {"ok": true, "points": unique, "plane_offset": plane_offset}

static func _convex_hull(points: Array) -> Array:
	if points.size() <= 1:
		return points.duplicate(true)
	var lower: Array = []
	for point_any in points:
		var point: Dictionary = point_any
		while lower.size() >= 2 and _cross2(lower[-2], lower[-1], point) <= EPS:
			lower.pop_back()
		lower.append(point)
	var upper: Array = []
	for index in range(points.size() - 1, -1, -1):
		var point: Dictionary = points[index]
		while upper.size() >= 2 and _cross2(upper[-2], upper[-1], point) <= EPS:
			upper.pop_back()
		upper.append(point)
	lower.pop_back()
	upper.pop_back()
	var hull := lower + upper
	return hull

static func _cross2(a: Dictionary, b: Dictionary, c: Dictionary) -> float:
	return (float(b["x"]) - float(a["x"])) * (float(c["y"]) - float(a["y"])) - (float(b["y"]) - float(a["y"])) * (float(c["x"]) - float(a["x"]))

static func _hash_payload(model: Dictionary) -> Dictionary:
	var payload := model.duplicate(true)
	payload.erase("model_hash")
	return payload

static func _hash(value) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(value, "", false).to_utf8_buffer())
	return context.finish().hex_encode()

static func _no_safe(reason: String, diagnostics: Dictionary = {}) -> Dictionary:
	return {"ok": false, "status": "NO_SAFE_BAKE", "code": "B0_3_NO_SAFE_BAKE", "reason": reason, "diagnostics": diagnostics}

static func _to_vec3(value) -> Dictionary:
	if value is Vector3:
		return {"ok": _finite_vec3(value), "value": value}
	if value is Array and Array(value).size() == 3:
		for component in Array(value):
			if not _finite_number(component):
				return {"ok": false}
		return {"ok": true, "value": Vector3(float(value[0]), float(value[1]), float(value[2]))}
	return {"ok": false}

static func _vec3(value) -> Vector3:
	if value is Vector3:
		return value
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func _arr3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

static func _finite_number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _finite_vec3(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)

static func _is_hex64(value: String) -> bool:
	if value.length() != 64:
		return false
	for i in range(value.length()):
		var code := value.unicode_at(i)
		var digit := code >= 48 and code <= 57
		var lower := code >= 97 and code <= 102
		if not digit and not lower:
			return false
	return true
