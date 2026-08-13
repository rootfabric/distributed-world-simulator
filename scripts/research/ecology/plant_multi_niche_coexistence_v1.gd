extends RefCounted

const Disturbance = preload("res://scripts/research/ecology/plant_disturbance_succession_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.p3_7_multi_niche_coexistence.v1"
const VERSION := "1.0.0"
const PARENT_P3_6_CANDIDATE_AGGREGATE := "a7abcc49c2b9e7d473ceefb147996cb2febf6248bafe7004e3d5da01827cc5cc"
const EPSILON := 0.000000000001

const CONFIG_FIELDS := ["stabilization_fraction"]
const NICHE_FIELDS := ["id", "temperature_optimum_c", "temperature_breadth_c", "moisture_optimum", "moisture_breadth", "light_optimum", "light_breadth", "nutrients_optimum", "nutrients_breadth"]
const COMMUNITY_PATCH_FIELDS := ["id", "plant_order", "plants"]
const COMMUNITY_PLANT_FIELDS := ["id", "biomass_kg"]
const RESULT_FIELDS := ["schema", "version", "parent_p3_6_candidate_aggregate", "disturbance_result", "disturbance_result_hash", "config", "niches", "niche_order", "input_community", "patch_order", "patches", "next_community", "summary", "result_hash"]
const PATCH_FIELDS := ["id", "parent_disturbance_patch_hash", "environment_patch_hash", "total_biomass_kg", "distance_to_target_before", "distance_to_target_after", "plant_order", "plants", "record_hash"]
const PLANT_FIELDS := ["id", "current_biomass_kg", "current_share", "niche_suitability", "target_share", "delta_biomass_kg", "next_biomass_kg", "record_hash"]
const SUMMARY_FIELDS := ["patch_count", "lineage_count", "total_biomass_kg", "distance_to_target_before", "distance_to_target_after", "active_lineages_next", "multi_niche_patches", "conservation_error_kg"]

static func community_from_parent(disturbance_result: Dictionary, niches: Array) -> Array[Dictionary]:
	if not bool(Disturbance.validate_result(disturbance_result).get("success", false)):
		return []
	var expected_ids := PackedStringArray(disturbance_result.get("trait_order", PackedStringArray()))
	var normalized_niches := _normalize_niches(niches, expected_ids)
	if normalized_niches.is_empty() and not expected_ids.is_empty():
		return []
	var patch_order := PackedStringArray(disturbance_result.get("patch_order", PackedStringArray()))
	var patch_by_id := _patch_map(Array(disturbance_result.get("patches", [])))
	var out: Array[Dictionary] = []
	for patch_id_value in patch_order:
		var patch_id := String(patch_id_value)
		if not patch_by_id.has(patch_id): return []
		var parent_patch: Dictionary = patch_by_id[patch_id]
		var biomass_by_id := {}
		for plant_value in parent_patch.get("plants", []):
			if typeof(plant_value) != TYPE_DICTIONARY: return []
			var plant: Dictionary = plant_value
			biomass_by_id[String(plant.get("id", ""))] = float(plant.get("final_biomass_kg", -1.0))
		var plants: Array[Dictionary] = []
		for plant_id in expected_ids:
			plants.append({"id":String(plant_id), "biomass_kg":float(biomass_by_id.get(String(plant_id), 0.0))})
		out.append({"id":patch_id, "plant_order":expected_ids.duplicate(), "plants":plants})
	return out

static func step(disturbance_result: Dictionary, community: Array, niches: Array, config: Dictionary) -> Dictionary:
	if not bool(Disturbance.validate_result(disturbance_result).get("success", false)):
		return {}
	var normalized_config := _normalize_config(config)
	if normalized_config.is_empty(): return {}
	var expected_ids := PackedStringArray(disturbance_result.get("trait_order", PackedStringArray()))
	var normalized_niches := _normalize_niches(niches, expected_ids)
	if normalized_niches.is_empty() and not expected_ids.is_empty(): return {}
	var niche_order := PackedStringArray()
	var niche_by_id := {}
	for profile_value in normalized_niches:
		var profile: Dictionary = profile_value
		var plant_id := String(profile["id"])
		niche_order.append(plant_id)
		niche_by_id[plant_id] = profile
	var normalized_community := _normalize_community(community, disturbance_result, niche_order)
	if normalized_community.is_empty() and not disturbance_result.get("patches", []).is_empty(): return {}
	var patch_order := PackedStringArray(disturbance_result.get("patch_order", PackedStringArray()))
	var disturbance_by_id := _patch_map(Array(disturbance_result.get("patches", [])))
	var seasonal_result: Dictionary = disturbance_result.get("seasonal_result", {})
	var environment_by_id := _patch_map(Array(seasonal_result.get("patches", [])))
	var community_by_id := _patch_map(normalized_community)
	if disturbance_by_id.size() != patch_order.size() or environment_by_id.size() != patch_order.size() or community_by_id.size() != patch_order.size(): return {}

	var patch_results: Array[Dictionary] = []
	var next_community: Array[Dictionary] = []
	var regional_next := {}
	for plant_id in niche_order: regional_next[String(plant_id)] = 0.0
	var total_biomass := 0.0
	var total_distance_before := 0.0
	var total_distance_after := 0.0
	var conservation_error := 0.0
	var multi_niche_patches := 0
	for patch_id_value in patch_order:
		var patch_id := String(patch_id_value)
		var patch_result := _step_patch(disturbance_by_id[patch_id], environment_by_id[patch_id], community_by_id[patch_id], niche_order, niche_by_id, normalized_config)
		if patch_result.is_empty(): return {}
		patch_results.append(patch_result)
		var next_plants: Array[Dictionary] = []
		var next_total := 0.0
		var positive_targets := 0
		for plant_value in Array(patch_result["plants"]):
			var plant: Dictionary = plant_value
			var plant_id := String(plant["id"])
			var next_biomass := float(plant["next_biomass_kg"])
			next_plants.append({"id":plant_id, "biomass_kg":next_biomass})
			next_total += next_biomass
			regional_next[plant_id] = float(regional_next[plant_id]) + next_biomass
			if float(plant["target_share"]) > EPSILON: positive_targets += 1
		if positive_targets > 1: multi_niche_patches += 1
		next_community.append({"id":patch_id, "plant_order":niche_order.duplicate(), "plants":next_plants})
		var patch_total := float(patch_result["total_biomass_kg"])
		var error := absf(next_total - patch_total)
		conservation_error += error
		total_biomass += patch_total
		total_distance_before += float(patch_result["distance_to_target_before"])
		total_distance_after += float(patch_result["distance_to_target_after"])
		if not _all_finite([next_total, conservation_error, total_biomass, total_distance_before, total_distance_after]): return {}
		if error > EPSILON: return {}
	var active_lineages := 0
	for plant_id in niche_order:
		if float(regional_next[String(plant_id)]) > EPSILON: active_lineages += 1
	var summary := {"patch_count":patch_results.size(),"lineage_count":niche_order.size(),"total_biomass_kg":total_biomass,"distance_to_target_before":total_distance_before,"distance_to_target_after":total_distance_after,"active_lineages_next":active_lineages,"multi_niche_patches":multi_niche_patches,"conservation_error_kg":conservation_error}
	var result := {"schema":SCHEMA,"version":VERSION,"parent_p3_6_candidate_aggregate":PARENT_P3_6_CANDIDATE_AGGREGATE,"disturbance_result":disturbance_result.duplicate(true),"disturbance_result_hash":String(disturbance_result.get("result_hash", "")),"config":normalized_config,"niches":normalized_niches,"niche_order":niche_order,"input_community":normalized_community,"patch_order":patch_order,"patches":patch_results,"next_community":next_community,"summary":summary}
	result["result_hash"] = compute_result_hash(result)
	return result

static func validate_result(result: Dictionary) -> Dictionary:
	if not _exact(result, RESULT_FIELDS): return _failure("RESULT_FIELDS_MISMATCH")
	if String(result.get("schema", "")) != SCHEMA or String(result.get("version", "")) != VERSION: return _failure("SCHEMA_OR_VERSION_MISMATCH")
	if String(result.get("parent_p3_6_candidate_aggregate", "")) != PARENT_P3_6_CANDIDATE_AGGREGATE: return _failure("PARENT_MISMATCH")
	if typeof(result.get("disturbance_result")) != TYPE_DICTIONARY or not bool(Disturbance.validate_result(Dictionary(result["disturbance_result"])).get("success", false)): return _failure("DISTURBANCE_RESULT_INVALID")
	if String(result.get("disturbance_result_hash", "")) != String(Dictionary(result["disturbance_result"]).get("result_hash", "")): return _failure("DISTURBANCE_HASH_MISMATCH")
	if typeof(result.get("config")) != TYPE_DICTIONARY or typeof(result.get("niches")) != TYPE_ARRAY or typeof(result.get("input_community")) != TYPE_ARRAY: return _failure("INPUT_CONTAINER_TYPE")
	if typeof(result.get("niche_order")) != TYPE_PACKED_STRING_ARRAY or typeof(result.get("patch_order")) != TYPE_PACKED_STRING_ARRAY or typeof(result.get("patches")) != TYPE_ARRAY or typeof(result.get("next_community")) != TYPE_ARRAY or typeof(result.get("summary")) != TYPE_DICTIONARY: return _failure("DERIVED_CONTAINER_TYPE")
	if not _derived_records_valid(result): return _failure("DERIVED_RECORD_INVALID")
	var expected := step(Dictionary(result["disturbance_result"]), Array(result["input_community"]), Array(result["niches"]), Dictionary(result["config"]))
	if expected.is_empty(): return _failure("RECONSTRUCTION_FAILED")
	var current_hash := compute_result_hash(result)
	if current_hash.is_empty() or String(result.get("result_hash", "")) != current_hash: return _failure("RESULT_HASH_MISMATCH")
	if String(result.get("result_hash", "")) != String(expected.get("result_hash", "")): return _failure("DERIVED_STATE_MISMATCH")
	return {"success":true,"error":""}

static func compute_result_hash(result: Dictionary) -> String:
	if typeof(result.get("config")) != TYPE_DICTIONARY or typeof(result.get("niches")) != TYPE_ARRAY or typeof(result.get("input_community")) != TYPE_ARRAY or typeof(result.get("patches")) != TYPE_ARRAY or typeof(result.get("next_community")) != TYPE_ARRAY or typeof(result.get("summary")) != TYPE_DICTIONARY: return ""
	var tokens := PackedStringArray([SCHEMA,VERSION,PARENT_P3_6_CANDIDATE_AGGREGATE,String(result.get("disturbance_result_hash", "")),"stabilization_fraction=%.12f" % float(Dictionary(result["config"]).get("stabilization_fraction",0.0))])
	for profile_value in Array(result["niches"]):
		if typeof(profile_value) != TYPE_DICTIONARY: return ""
		var profile: Dictionary = profile_value
		tokens.append("niche|%s|%s" % [String(profile.get("id", "")), _niche_hash(profile)])
	for patch_value in Array(result["input_community"]): tokens.append("input|" + _community_patch_hash(Dictionary(patch_value)))
	for patch_value in Array(result["patches"]):
		var patch: Dictionary = patch_value
		tokens.append("patch|%s|%s" % [String(patch.get("id", "")),String(patch.get("record_hash", ""))])
	for patch_value in Array(result["next_community"]): tokens.append("next|" + _community_patch_hash(Dictionary(patch_value)))
	var summary: Dictionary = result["summary"]
	for field_name in SUMMARY_FIELDS: tokens.append("summary|%s=%s" % [field_name,str(summary.get(field_name,0))])
	return "\n".join(tokens).sha256_text()

static func _step_patch(parent_patch: Dictionary, environment_patch: Dictionary, community_patch: Dictionary, niche_order: PackedStringArray, niche_by_id: Dictionary, config: Dictionary) -> Dictionary:
	var patch_id := String(parent_patch.get("id", ""))
	if patch_id != String(environment_patch.get("id", "")) or patch_id != String(community_patch.get("id", "")): return {}
	var community_plants: Array = community_patch.get("plants", [])
	if community_plants.size() != niche_order.size(): return {}
	var current_by_id := {}
	var total := 0.0
	for plant_value in community_plants:
		var plant: Dictionary = plant_value
		var plant_id := String(plant.get("id", "")); var biomass := float(plant.get("biomass_kg", -1.0))
		if plant_id.is_empty() or current_by_id.has(plant_id) or not is_finite(biomass) or biomass < 0.0: return {}
		current_by_id[plant_id] = biomass; total += biomass
	if not is_finite(total): return {}
	var suitability := {}; var suitability_total := 0.0
	for plant_id_value in niche_order:
		var plant_id := String(plant_id_value)
		var score := _suitability(environment_patch, niche_by_id[plant_id])
		if not is_finite(score) or score < 0.0 or score > 1.0: return {}
		suitability[plant_id] = score; suitability_total += score
	if not is_finite(suitability_total): return {}
	var fraction := float(config["stabilization_fraction"])
	var plants: Array[Dictionary] = []
	var distance_before := 0.0; var distance_after := 0.0; var next_total := 0.0
	for plant_id_value in niche_order:
		var plant_id := String(plant_id_value)
		var current := float(current_by_id.get(plant_id, 0.0))
		var current_share := current / total if total > EPSILON else 0.0
		var target_share := float(suitability[plant_id]) / suitability_total if suitability_total > EPSILON else current_share
		var next_biomass := current * (1.0 - fraction) + total * target_share * fraction
		var next_share := next_biomass / total if total > EPSILON else 0.0
		var delta := next_biomass - current
		if not _all_finite([current_share,target_share,next_biomass,next_share,delta]): return {}
		var plant := {"id":plant_id,"current_biomass_kg":current,"current_share":current_share,"niche_suitability":float(suitability[plant_id]),"target_share":target_share,"delta_biomass_kg":delta,"next_biomass_kg":next_biomass}
		plant["record_hash"] = _plant_hash(plant); plants.append(plant)
		distance_before += absf(current_share-target_share); distance_after += absf(next_share-target_share); next_total += next_biomass
	if absf(next_total-total) > EPSILON: return {}
	var patch := {"id":patch_id,"parent_disturbance_patch_hash":String(parent_patch.get("record_hash", "")),"environment_patch_hash":String(environment_patch.get("record_hash", "")),"total_biomass_kg":total,"distance_to_target_before":distance_before,"distance_to_target_after":distance_after,"plant_order":niche_order.duplicate(),"plants":plants}
	patch["record_hash"] = _patch_hash(patch)
	return patch

static func _suitability(environment_patch: Dictionary, profile: Dictionary) -> float:
	var t := _axis_match(float(environment_patch.get("temperature_c",0.0)),float(profile["temperature_optimum_c"]),float(profile["temperature_breadth_c"]))
	var m := _axis_match(float(environment_patch.get("moisture",0.0)),float(profile["moisture_optimum"]),float(profile["moisture_breadth"]))
	var l := _axis_match(float(environment_patch.get("light",0.0)),float(profile["light_optimum"]),float(profile["light_breadth"]))
	var n := _axis_match(float(environment_patch.get("nutrients",0.0)),float(profile["nutrients_optimum"]),float(profile["nutrients_breadth"]))
	return (t+m+l+n)/4.0

static func _axis_match(value: float, optimum: float, breadth: float) -> float:
	if not _all_finite([value,optimum,breadth]) or breadth <= 0.0: return -1.0
	return clampf(1.0 - absf(value-optimum)/breadth,0.0,1.0)

static func _normalize_config(config: Dictionary) -> Dictionary:
	if not _exact(config,CONFIG_FIELDS) or not _numeric_fields_finite(config,CONFIG_FIELDS): return {}
	var f := float(config["stabilization_fraction"]); if f < 0.0 or f > 1.0: return {}
	return {"stabilization_fraction":f}

static func _normalize_niches(values: Array, expected_ids: PackedStringArray) -> Array[Dictionary]:
	var by_id := {}
	for value in values:
		if typeof(value) != TYPE_DICTIONARY: return []
		var profile: Dictionary = value
		if not _exact(profile,NICHE_FIELDS) or not _numeric_fields_finite(profile,NICHE_FIELDS.slice(1)): return []
		var plant_id := String(profile.get("id", "")); if plant_id.is_empty() or by_id.has(plant_id): return []
		for field_name in ["temperature_breadth_c","moisture_breadth","light_breadth","nutrients_breadth"]:
			if float(profile[field_name]) <= 0.0: return []
		for field_name in ["moisture_optimum","light_optimum","nutrients_optimum"]:
			var v := float(profile[field_name]); if v < 0.0 or v > 1.0: return []
		by_id[plant_id] = profile
	var actual := PackedStringArray(); for key in by_id.keys(): actual.append(String(key)); actual.sort()
	var expected := expected_ids.duplicate(); expected.sort(); if actual != expected: return []
	var out: Array[Dictionary] = []
	for plant_id in actual:
		var source: Dictionary = by_id[plant_id]; var item := {"id":String(plant_id)}
		for field_name in NICHE_FIELDS.slice(1): item[field_name] = float(source[field_name])
		out.append(item)
	return out

static func _normalize_community(values: Array, disturbance_result: Dictionary, niche_order: PackedStringArray) -> Array[Dictionary]:
	var by_id := _patch_map(values)
	var patch_order := PackedStringArray(disturbance_result.get("patch_order",PackedStringArray()))
	var parent_by_id := _patch_map(Array(disturbance_result.get("patches",[])))
	if by_id.size() != patch_order.size() or parent_by_id.size() != patch_order.size(): return []
	var out: Array[Dictionary] = []
	for patch_id_value in patch_order:
		var patch_id := String(patch_id_value); if not by_id.has(patch_id): return []
		var patch: Dictionary = by_id[patch_id]
		if not _exact(patch,COMMUNITY_PATCH_FIELDS) or typeof(patch.get("plants")) != TYPE_ARRAY: return []
		var plant_by_id := {}; var sum := 0.0
		for plant_value in patch["plants"]:
			if typeof(plant_value) != TYPE_DICTIONARY: return []
			var plant: Dictionary = plant_value
			if not _exact(plant,COMMUNITY_PLANT_FIELDS): return []
			var plant_id := String(plant.get("id", "")); var biomass := float(plant.get("biomass_kg",-1.0))
			if plant_id.is_empty() or plant_by_id.has(plant_id) or not is_finite(biomass) or biomass < 0.0: return []
			plant_by_id[plant_id] = biomass; sum += biomass
		if plant_by_id.size() != niche_order.size() or not is_finite(sum): return []
		var canonical_plants: Array[Dictionary] = []
		for plant_id_value in niche_order:
			var plant_id := String(plant_id_value); if not plant_by_id.has(plant_id): return []
			canonical_plants.append({"id":plant_id,"biomass_kg":float(plant_by_id[plant_id])})
		var parent_total := float(Dictionary(parent_by_id[patch_id]).get("final_biomass_kg",-1.0))
		if not is_finite(parent_total) or absf(sum-parent_total) > EPSILON: return []
		out.append({"id":patch_id,"plant_order":niche_order.duplicate(),"plants":canonical_plants})
	return out

static func _derived_records_valid(result: Dictionary) -> bool:
	var niches: Array = result["niches"]; var niche_order: PackedStringArray = result["niche_order"]
	if niches.size()!=niche_order.size(): return false
	for i in range(niches.size()):
		if typeof(niches[i])!=TYPE_DICTIONARY or not _exact(Dictionary(niches[i]),NICHE_FIELDS) or String(Dictionary(niches[i]).get("id",""))!=String(niche_order[i]): return false
	var patches: Array = result["patches"]; var patch_order: PackedStringArray = result["patch_order"]
	if patches.size()!=patch_order.size(): return false
	for i in range(patches.size()):
		if typeof(patches[i])!=TYPE_DICTIONARY: return false
		var patch: Dictionary=patches[i]
		if not _exact(patch,PATCH_FIELDS) or String(patch.get("id",""))!=String(patch_order[i]) or String(patch.get("record_hash",""))!=_patch_hash(patch): return false
		var plants: Array=patch.get("plants",[]); var order: PackedStringArray=patch.get("plant_order",PackedStringArray())
		if plants.size()!=order.size(): return false
		for j in range(plants.size()):
			if typeof(plants[j])!=TYPE_DICTIONARY: return false
			var plant: Dictionary=plants[j]
			if not _exact(plant,PLANT_FIELDS) or String(plant.get("id",""))!=String(order[j]) or String(plant.get("record_hash",""))!=_plant_hash(plant): return false
	if not _community_records_valid(Array(result["input_community"]),patch_order,niche_order) or not _community_records_valid(Array(result["next_community"]),patch_order,niche_order): return false
	if not _exact(Dictionary(result["summary"]),SUMMARY_FIELDS): return false
	return true

static func _community_records_valid(values: Array, patch_order: PackedStringArray, niche_order: PackedStringArray) -> bool:
	if values.size()!=patch_order.size(): return false
	for i in range(values.size()):
		if typeof(values[i])!=TYPE_DICTIONARY: return false
		var patch: Dictionary=values[i]
		if not _exact(patch,COMMUNITY_PATCH_FIELDS) or String(patch.get("id",""))!=String(patch_order[i]) or PackedStringArray(patch.get("plant_order",PackedStringArray()))!=niche_order: return false
		var plants: Array=patch.get("plants",[]); if plants.size()!=niche_order.size(): return false
		for j in range(plants.size()):
			if typeof(plants[j])!=TYPE_DICTIONARY: return false
			var plant: Dictionary=plants[j]
			if not _exact(plant,COMMUNITY_PLANT_FIELDS) or String(plant.get("id",""))!=String(niche_order[j]): return false
	return true

static func _patch_map(values: Array) -> Dictionary:
	var out := {}
	for value in values:
		if typeof(value) != TYPE_DICTIONARY:
			return {}
		var patch: Dictionary = value
		var patch_id := String(patch.get("id", ""))
		if patch_id.is_empty() or out.has(patch_id):
			return {}
		out[patch_id] = patch
	return out

static func _patch_hash(patch: Dictionary) -> String:
	var tokens:=PackedStringArray()
	for field_name in PATCH_FIELDS:
		if field_name=="plants":
			for plant_value in patch.get("plants",[]):
				var plant: Dictionary=plant_value; tokens.append("plant|%s|%s" % [String(plant.get("id","")),String(plant.get("record_hash",""))])
		elif field_name=="plant_order":
			for plant_id in PackedStringArray(patch.get("plant_order",PackedStringArray())): tokens.append("order|"+String(plant_id))
		elif field_name!="record_hash": tokens.append("%s=%s" % [field_name,str(patch.get(field_name,0))])
	return "\n".join(tokens).sha256_text()

static func _plant_hash(plant: Dictionary) -> String:
	var tokens:=PackedStringArray(); for field_name in PLANT_FIELDS:
		if field_name!="record_hash": tokens.append("%s=%s" % [field_name,str(plant.get(field_name,0))])
	return "\n".join(tokens).sha256_text()

static func _niche_hash(profile: Dictionary) -> String:
	var tokens:=PackedStringArray(); for field_name in NICHE_FIELDS: tokens.append("%s=%s" % [field_name,str(profile.get(field_name,0))])
	return "\n".join(tokens).sha256_text()

static func _community_patch_hash(patch: Dictionary) -> String:
	var tokens:=PackedStringArray(["id="+String(patch.get("id",""))])
	for plant_value in patch.get("plants",[]):
		var plant: Dictionary=plant_value; tokens.append("%s=%.12f" % [String(plant.get("id","")),float(plant.get("biomass_kg",0.0))])
	return "\n".join(tokens).sha256_text()

static func _exact(value: Dictionary, fields: Array) -> bool:
	if value.size()!=fields.size(): return false
	for field_name in fields:
		if not value.has(field_name): return false
	return true
static func _numeric_fields_finite(value: Dictionary, fields: Array) -> bool:
	for field_name in fields:
		if not value.has(field_name) or typeof(value[field_name]) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value[field_name])): return false
	return true
static func _all_finite(values: Array) -> bool:
	for value in values:
		if not is_finite(float(value)): return false
	return true
static func _failure(error: String) -> Dictionary: return {"success":false,"error":error}
