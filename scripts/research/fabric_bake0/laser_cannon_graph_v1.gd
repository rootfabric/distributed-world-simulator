extends RefCounted
## Hierarchical T10 assembly graph: three compiled subcapsules + two optical elements.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MatterCatalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const OpticsProfile = preload("res://scripts/research/fabric_bake0/laser_cannon_optics_profile_v1.gd")
const Capsule = preload("res://scripts/research/fabric_bake0/behavior_capsule_contract_v2.gd")

const SCHEMA := "planet_simulator.fabric_laser_cannon_graph.v1"
const FIELDS: Array[String] = [
	"schema","graph_id","material_catalog","optics_profile",
	"power_stage_capsule","laser_emitter_capsule","cooling_capsule",
	"input_focal_length_m","output_focal_length_m","clear_aperture_diameter_m",
	"optics_temperature_k","graph_hash","checksum",
]

static func create(data: Dictionary) -> Dictionary:
	var value := {
		"schema":SCHEMA,
		"graph_id":String(data.graph_id),
		"material_catalog":data.material_catalog.duplicate(true),
		"optics_profile":data.optics_profile.duplicate(true),
		"power_stage_capsule":data.power_stage_capsule.duplicate(true),
		"laser_emitter_capsule":data.laser_emitter_capsule.duplicate(true),
		"cooling_capsule":data.cooling_capsule.duplicate(true),
		"input_focal_length_m":float(data.input_focal_length_m),
		"output_focal_length_m":float(data.output_focal_length_m),
		"clear_aperture_diameter_m":float(data.clear_aperture_diameter_m),
		"optics_temperature_k":float(data.optics_temperature_k),
		"graph_hash":"",
		"checksum":"",
	}
	value.graph_hash = U.canonical_hash(_identity(value))
	value.checksum = U.compute_checksum(value)
	return value if validate(value).success else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := U.validate_exact_fields(value,FIELDS)
	if not checked.success:
		return checked
	if value.get("schema") != SCHEMA or not U.is_canonical_id(value.get("graph_id"),2):
		return U.failure("INVALID_LASER_CANNON_GRAPH")
	if typeof(value.get("material_catalog")) != TYPE_DICTIONARY or not bool(MatterCatalog.validate(value.material_catalog).get("success",false)):
		return U.failure("INVALID_LASER_CANNON_MATERIAL_CATALOG")
	checked = OpticsProfile.validate(value.optics_profile)
	if not checked.success:
		return checked
	var material := MatterCatalog.material_by_id(value.material_catalog,String(value.optics_profile.optical_material_id))
	if material.is_empty():
		return U.failure("LASER_CANNON_OPTICS_MATERIAL_MISSING")
	checked = OpticsProfile.validate_against_material(value.optics_profile,material)
	if not checked.success:
		return checked
	for field in ["power_stage_capsule","laser_emitter_capsule","cooling_capsule"]:
		if typeof(value.get(field)) != TYPE_DICTIONARY:
			return U.failure("LASER_CANNON_SUBCAPSULE_MISSING",{"field":field})
		checked = Capsule.validate(value[field])
		if not checked.success:
			return checked
	if String(value.power_stage_capsule.capsule_kind) != "POWER_STAGE":
		return U.failure("LASER_CANNON_POWER_STAGE_KIND_MISMATCH")
	if String(value.laser_emitter_capsule.capsule_kind) != "LASER_EMITTER":
		return U.failure("LASER_CANNON_EMITTER_KIND_MISMATCH")
	if String(value.cooling_capsule.capsule_kind) != "COOLING_LOOP":
		return U.failure("LASER_CANNON_COOLING_KIND_MISMATCH")
	for field in ["input_focal_length_m","output_focal_length_m","clear_aperture_diameter_m","optics_temperature_k"]:
		if not U.is_positive_number(value.get(field)):
			return U.failure("INVALID_LASER_CANNON_GEOMETRY",{"field":field})
	if float(value.output_focal_length_m) < float(value.input_focal_length_m):
		return U.failure("LASER_CANNON_OPTICAL_EXPANDER_RATIO_INVALID")
	if float(value.optics_temperature_k) < float(value.optics_profile.min_temperature_k) or float(value.optics_temperature_k) > float(value.optics_profile.max_temperature_k):
		return U.failure("LASER_CANNON_OPTICS_TEMPERATURE_OUT_OF_DOMAIN")
	if not U.is_lower_hex_64(value.get("graph_hash")) or String(value.graph_hash) != U.canonical_hash(_identity(value)):
		return U.failure("LASER_CANNON_GRAPH_HASH_MISMATCH")
	return U.validate_checksum(value)

static func _identity(value: Dictionary) -> Dictionary:
	return {
		"graph_id":value.graph_id,
		"material_catalog":value.material_catalog,
		"optics_profile":value.optics_profile,
		"power_stage_capsule":value.power_stage_capsule,
		"laser_emitter_capsule":value.laser_emitter_capsule,
		"cooling_capsule":value.cooling_capsule,
		"input_focal_length_m":value.input_focal_length_m,
		"output_focal_length_m":value.output_focal_length_m,
		"clear_aperture_diameter_m":value.clear_aperture_diameter_m,
		"optics_temperature_k":value.optics_temperature_k,
	}
