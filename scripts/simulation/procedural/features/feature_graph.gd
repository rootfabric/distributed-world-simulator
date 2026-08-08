extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const WorldFeatureScript = preload("res://scripts/simulation/procedural/contracts/world_feature.gd")
const FeatureBoundsScript = preload("res://scripts/simulation/procedural/contracts/feature_bounds.gd")
const FeatureQueryScript = preload("res://scripts/simulation/procedural/contracts/feature_query.gd")
const FeatureRelationScript = preload("res://scripts/simulation/procedural/contracts/feature_relation.gd")
const FeatureIdScript = preload("res://scripts/simulation/procedural/contracts/feature_id.gd")

const MANIFEST_SCHEMA: String = "planet_simulator.feature_graph_manifest.v1"

var _body_id: String = ""
var _frame_id: String = ""
var _features: Dictionary = {}
var _sorted_ids: Array[String] = []
var _sealed: bool = false
var _manifest_hash: String = ""


func configure(body_id: String, frame_id: String) -> Dictionary:
	if not _body_id.is_empty() or not _features.is_empty():
		return GeoUtilsScript.failure("FEATURE_GRAPH_ALREADY_CONFIGURED")
	if not GeoUtilsScript.is_canonical_id(body_id, 2):
		return GeoUtilsScript.failure("INVALID_FEATURE_GRAPH_BODY_ID")
	if not GeoUtilsScript.is_canonical_id(frame_id, 2):
		return GeoUtilsScript.failure("INVALID_FEATURE_GRAPH_FRAME_ID")
	_body_id = body_id
	_frame_id = frame_id
	return GeoUtilsScript.success({"body_id": _body_id, "frame_id": _frame_id})


func add_feature(feature: Dictionary) -> Dictionary:
	if _body_id.is_empty():
		return GeoUtilsScript.failure("FEATURE_GRAPH_NOT_CONFIGURED")
	if _sealed:
		return GeoUtilsScript.failure("FEATURE_GRAPH_ALREADY_SEALED")
	var validation: Dictionary = WorldFeatureScript.validate(feature)
	if not bool(validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_FEATURE_GRAPH_FEATURE", {"cause": validation.get("error_code", "")})
	if String(feature["body_id"]) != _body_id:
		return GeoUtilsScript.failure("FEATURE_GRAPH_BODY_MISMATCH")
	if String(feature["frame_id"]) != _frame_id:
		return GeoUtilsScript.failure("FEATURE_GRAPH_FRAME_MISMATCH")
	var feature_id: String = String(feature["feature_id"])
	if _features.has(feature_id):
		return GeoUtilsScript.failure("DUPLICATE_FEATURE_ID", {"feature_id": feature_id})
	_features[feature_id] = feature.duplicate(true)
	return GeoUtilsScript.success({"feature_id": feature_id})


func seal() -> Dictionary:
	if _body_id.is_empty():
		return GeoUtilsScript.failure("FEATURE_GRAPH_NOT_CONFIGURED")
	if _sealed:
		return GeoUtilsScript.success({"manifest_hash": _manifest_hash, "feature_count": _sorted_ids.size()})
	_sorted_ids.clear()
	for raw_id in _features.keys():
		_sorted_ids.append(String(raw_id))
	_sorted_ids.sort()
	for feature_id in _sorted_ids:
		var feature: Dictionary = _features[feature_id]
		var parent_id: String = String(feature["parent_feature_id"])
		if not parent_id.is_empty() and not _features.has(parent_id):
			return GeoUtilsScript.failure("MISSING_PARENT_FEATURE", {"feature_id": feature_id, "parent_feature_id": parent_id})
		for relation_value in feature["relations"]:
			var target_id: String = String(relation_value["target_feature_id"])
			if not _features.has(target_id):
				return GeoUtilsScript.failure("MISSING_FEATURE_RELATION_TARGET", {"feature_id": feature_id, "target_feature_id": target_id})
	var cycle: Dictionary = _validate_parent_cycles()
	if not bool(cycle.get("success", false)):
		return cycle
	var manifest_features: Array = []
	for feature_id in _sorted_ids:
		manifest_features.append(Dictionary(_features[feature_id]).duplicate(true))
	_manifest_hash = GeoUtilsScript.payload_hash({
		"schema": MANIFEST_SCHEMA,
		"body_id": _body_id,
		"frame_id": _frame_id,
		"features": manifest_features,
	})
	_sealed = true
	return GeoUtilsScript.success({
		"manifest_hash": _manifest_hash,
		"feature_count": _sorted_ids.size(),
		"feature_ids": _sorted_ids.duplicate(),
	})


func query(query_value: Dictionary) -> Dictionary:
	if not _sealed:
		return GeoUtilsScript.failure("FEATURE_GRAPH_NOT_SEALED")
	var validation: Dictionary = FeatureQueryScript.validate(query_value)
	if not bool(validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_FEATURE_GRAPH_QUERY", {"cause": validation.get("error_code", "")})
	if String(query_value["body_id"]) != _body_id:
		return GeoUtilsScript.failure("FEATURE_QUERY_BODY_MISMATCH")
	if String(query_value["frame_id"]) != _frame_id:
		return GeoUtilsScript.failure("FEATURE_QUERY_FRAME_MISMATCH")
	var type_filter: Array = query_value["feature_types"]
	var matches: Array = []
	var ids: Array[String] = []
	for feature_id in _sorted_ids:
		var feature: Dictionary = _features[feature_id]
		if not type_filter.is_empty() and not type_filter.has(String(feature["feature_type"])):
			continue
		if not FeatureBoundsScript.intersects_sphere(feature["bounds"], query_value["center_m"], float(query_value["radius_m"])):
			continue
		matches.append(feature.duplicate(true))
		ids.append(feature_id)
	return GeoUtilsScript.success({
		"features": matches,
		"feature_ids": ids,
		"manifest_hash": _manifest_hash,
	})


func get_feature(feature_id: String) -> Dictionary:
	if not bool(FeatureIdScript.validate(feature_id).get("success", false)):
		return GeoUtilsScript.failure("INVALID_FEATURE_LOOKUP_ID")
	if not _features.has(feature_id):
		return GeoUtilsScript.failure("FEATURE_NOT_FOUND", {"feature_id": feature_id})
	return GeoUtilsScript.success({"feature": Dictionary(_features[feature_id]).duplicate(true)})


func related_features(feature_id: String, relation_type: String = "") -> Dictionary:
	if not _sealed:
		return GeoUtilsScript.failure("FEATURE_GRAPH_NOT_SEALED")
	var lookup: Dictionary = get_feature(feature_id)
	if not bool(lookup.get("success", false)):
		return lookup
	if not relation_type.is_empty() and (not GeoUtilsScript.is_canonical_id(relation_type, 2) or not relation_type.begins_with(FeatureRelationScript.TYPE_PREFIX)):
		return GeoUtilsScript.failure("INVALID_FEATURE_RELATION_FILTER")
	var relations: Array = []
	for relation_value in lookup["details"]["feature"]["relations"]:
		if not relation_type.is_empty() and String(relation_value["relation_type"]) != relation_type:
			continue
		var target_id: String = String(relation_value["target_feature_id"])
		relations.append({
			"relation": Dictionary(relation_value).duplicate(true),
			"feature": Dictionary(_features[target_id]).duplicate(true),
		})
	return GeoUtilsScript.success({"relations": relations})


func children_of(feature_id: String) -> Dictionary:
	if not _sealed:
		return GeoUtilsScript.failure("FEATURE_GRAPH_NOT_SEALED")
	if not bool(FeatureIdScript.validate(feature_id).get("success", false)):
		return GeoUtilsScript.failure("INVALID_FEATURE_LOOKUP_ID")
	var children: Array = []
	var child_ids: Array[String] = []
	for candidate_id in _sorted_ids:
		var candidate: Dictionary = _features[candidate_id]
		if String(candidate["parent_feature_id"]) == feature_id:
			children.append(candidate.duplicate(true))
			child_ids.append(candidate_id)
	return GeoUtilsScript.success({"features": children, "feature_ids": child_ids})


func feature_ids() -> Array[String]:
	if _sealed:
		return _sorted_ids.duplicate()
	var ids: Array[String] = []
	for raw_id in _features.keys():
		ids.append(String(raw_id))
	ids.sort()
	return ids


func manifest_hash() -> String:
	return _manifest_hash


func is_sealed() -> bool:
	return _sealed


func size() -> int:
	return _features.size()


func _validate_parent_cycles() -> Dictionary:
	var done: Dictionary = {}
	for feature_id in _sorted_ids:
		if done.has(feature_id):
			continue
		var chain_index: Dictionary = {}
		var current: String = feature_id
		while not current.is_empty():
			if done.has(current):
				break
			if chain_index.has(current):
				return GeoUtilsScript.failure("FEATURE_PARENT_CYCLE", {"feature_id": current})
			chain_index[current] = true
			current = String(Dictionary(_features[current]).get("parent_feature_id", ""))
		for visited in chain_index.keys():
			done[String(visited)] = true
	return GeoUtilsScript.success()
