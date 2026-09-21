extends RefCounted
## Canonical-derived symmetric coolant-loop lane graph.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MatterCatalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const Profile = preload("res://scripts/research/fabric_bake0/cooling_coolant_profile_v1.gd")

const SCHEMA := "planet_simulator.fabric_cooling_loop_graph.v1"
const FIELDS: Array[String] = [
	"schema", "graph_id", "material_catalog", "coolant_profile", "lanes", "graph_hash", "checksum",
]
const LANE_FIELDS: Array[String] = [
	"lane_id", "plate_material_id", "radiator_material_id", "coolant_material_id",
	"plate_volume_m3", "plate_contact_area_m2", "plate_wall_thickness_m",
	"hot_coolant_volume_m3", "cold_coolant_volume_m3",
	"radiator_volume_m3", "radiator_contact_area_m2", "radiator_wall_thickness_m",
	"radiator_ambient_area_m2", "channel_flow_area_m2", "channel_hydraulic_diameter_m",
	"channel_flow_length_m", "quality_ratio", "enabled",
]

static func create(
	graph_id: String,
	material_catalog: Dictionary,
	coolant_profile: Dictionary,
	lanes: Array
) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"graph_id": graph_id,
		"material_catalog": material_catalog.duplicate(true),
		"coolant_profile": coolant_profile.duplicate(true),
		"lanes": U.sorted_dicts(lanes, "lane_id"),
		"graph_hash": "",
		"checksum": "",
	}
	value.graph_hash = U.canonical_hash(_identity(value))
	value.checksum = U.compute_checksum(value)
	return value if validate(value).success else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := U.validate_exact_fields(value, FIELDS)
	if not checked.success:
		return checked
	if value.get("schema") != SCHEMA:
		return U.failure("UNSUPPORTED_COOLING_LOOP_GRAPH_SCHEMA")
	if not U.is_canonical_id(value.get("graph_id"), 2):
		return U.failure("INVALID_COOLING_LOOP_GRAPH_ID")
	if typeof(value.get("material_catalog")) != TYPE_DICTIONARY or not bool(MatterCatalog.validate(value.material_catalog).get("success", false)):
		return U.failure("INVALID_COOLING_LOOP_MATERIAL_CATALOG")
	if typeof(value.get("coolant_profile")) != TYPE_DICTIONARY:
		return U.failure("INVALID_COOLING_LOOP_PROFILE")
	checked = Profile.validate(value.coolant_profile)
	if not checked.success:
		return checked
	var coolant_material := MatterCatalog.material_by_id(value.material_catalog, String(value.coolant_profile.coolant_material_id))
	if coolant_material.is_empty():
		return U.failure("COOLING_LOOP_COOLANT_MATERIAL_MISSING")
	checked = Profile.validate_against_material(value.coolant_profile, coolant_material)
	if not checked.success:
		return checked
	if typeof(value.get("lanes")) != TYPE_ARRAY or value.lanes.is_empty():
		return U.failure("INVALID_COOLING_LOOP_LANES")
	var previous := ""
	for index in range(value.lanes.size()):
		var raw = value.lanes[index]
		if typeof(raw) != TYPE_DICTIONARY:
			return U.failure("INVALID_COOLING_LOOP_LANE", {"index": index})
		var lane: Dictionary = raw
		checked = U.validate_exact_fields(lane, LANE_FIELDS)
		if not checked.success:
			return checked
		if not U.is_canonical_id(lane.get("lane_id"), 2):
			return U.failure("INVALID_COOLING_LOOP_LANE_ID", {"index": index})
		for field in ["plate_material_id", "radiator_material_id", "coolant_material_id"]:
			if MatterCatalog.material_by_id(value.material_catalog, String(lane.get(field, ""))).is_empty():
				return U.failure("COOLING_LOOP_LANE_MATERIAL_MISSING", {"index": index, "field": field})
		if String(lane.coolant_material_id) != String(value.coolant_profile.coolant_material_id):
			return U.failure("COOLING_LOOP_LANE_COOLANT_PROFILE_MISMATCH", {"index": index})
		for field in [
			"plate_volume_m3", "plate_contact_area_m2", "plate_wall_thickness_m",
			"hot_coolant_volume_m3", "cold_coolant_volume_m3",
			"radiator_volume_m3", "radiator_contact_area_m2", "radiator_wall_thickness_m",
			"radiator_ambient_area_m2", "channel_flow_area_m2", "channel_hydraulic_diameter_m",
			"channel_flow_length_m", "quality_ratio"
		]:
			if not U.is_positive_number(lane.get(field)):
				return U.failure("INVALID_COOLING_LOOP_LANE_PROPERTY", {"index": index, "field": field})
		if float(lane.quality_ratio) > 1.0:
			return U.failure("INVALID_COOLING_LOOP_LANE_QUALITY", {"index": index})
		if typeof(lane.get("enabled")) != TYPE_BOOL:
			return U.failure("INVALID_COOLING_LOOP_LANE_ENABLED", {"index": index})
		var current := String(lane.lane_id)
		if index > 0 and current <= previous:
			return U.failure("COOLING_LOOP_LANES_NOT_SORTED_UNIQUE")
		previous = current
	if not U.is_lower_hex_64(value.get("graph_hash")) or String(value.graph_hash) != U.canonical_hash(_identity(value)):
		return U.failure("COOLING_LOOP_GRAPH_HASH_MISMATCH")
	return U.validate_checksum(value)

static func _identity(value: Dictionary) -> Dictionary:
	return {
		"graph_id": value.graph_id,
		"material_catalog": value.material_catalog,
		"coolant_profile": value.coolant_profile,
		"lanes": value.lanes,
	}
