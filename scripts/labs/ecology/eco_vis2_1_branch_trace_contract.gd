extends RefCounted

const STAGE := "ECO.VIS2.1"
const FIELD_HASH_DOMAIN := "ECO.VIS2.1/POPULATION_FIELD"
const REQUIRED_FIELDS: Array[String] = [
	"generation",
	"branch_id",
	"experiment_id",
	"visual_count",
	"birth_count",
	"death_count",
	"survivor_count",
	"mean_fitness",
	"unique_genomes",
	"alpha_count",
	"beta_count",
	"represented_biomass_kg",
	"field_hash",
	"environment_revision",
]


static func create_point(
	generation: int,
	branch_id: String,
	experiment_id: String,
	visual_count: int,
	birth_count: int,
	death_count: int,
	survivor_count: int,
	mean_fitness: float,
	unique_genomes: int,
	alpha_count: int,
	beta_count: int,
	represented_biomass_kg: float,
	field_hash: String,
	environment_revision: String
) -> Dictionary:
	var point := {
		"generation": generation,
		"branch_id": branch_id,
		"experiment_id": experiment_id,
		"visual_count": visual_count,
		"birth_count": birth_count,
		"death_count": death_count,
		"survivor_count": survivor_count,
		"mean_fitness": mean_fitness,
		"unique_genomes": unique_genomes,
		"alpha_count": alpha_count,
		"beta_count": beta_count,
		"represented_biomass_kg": represented_biomass_kg,
		"field_hash": field_hash,
		"environment_revision": environment_revision,
	}
	return point if bool(validate(point).get("success", false)) else {}


static func validate(point: Dictionary) -> Dictionary:
	for field_name in REQUIRED_FIELDS:
		if not point.has(field_name):
			return _failure("missing_field", field_name)
	if typeof(point["generation"]) != TYPE_INT or int(point["generation"]) < 0:
		return _failure("invalid_generation", "generation")
	for field_name in ["branch_id", "experiment_id", "environment_revision"]:
		if typeof(point[field_name]) != TYPE_STRING or String(point[field_name]).strip_edges().is_empty():
			return _failure("invalid_string", String(field_name))
	for field_name in [
		"visual_count", "birth_count", "death_count", "survivor_count",
		"unique_genomes", "alpha_count", "beta_count",
	]:
		if typeof(point[field_name]) != TYPE_INT or int(point[field_name]) < 0:
			return _failure("invalid_count", String(field_name))
	var visual_count := int(point["visual_count"])
	if int(point["survivor_count"]) > visual_count:
		return _failure("survivors_exceed_visual_count", "survivor_count")
	if int(point["alpha_count"]) + int(point["beta_count"]) > visual_count:
		return _failure("composition_exceeds_visual_count", "alpha_count/beta_count")
	if typeof(point["mean_fitness"]) not in [TYPE_FLOAT, TYPE_INT]:
		return _failure("invalid_number", "mean_fitness")
	var mean_fitness := float(point["mean_fitness"])
	if not is_finite(mean_fitness) or mean_fitness < 0.0 or mean_fitness > 1.0:
		return _failure("invalid_fitness", "mean_fitness")
	if typeof(point["represented_biomass_kg"]) not in [TYPE_FLOAT, TYPE_INT]:
		return _failure("invalid_number", "represented_biomass_kg")
	var represented_biomass := float(point["represented_biomass_kg"])
	if not is_finite(represented_biomass) or represented_biomass < 0.0:
		return _failure("invalid_biomass", "represented_biomass_kg")
	if typeof(point["field_hash"]) != TYPE_STRING or not _is_sha256(String(point["field_hash"])):
		return _failure("invalid_field_hash", "field_hash")
	return {"success": true}


static func validate_trace(points: Array) -> Dictionary:
	var previous_generation := -1
	for index in range(points.size()):
		if typeof(points[index]) != TYPE_DICTIONARY:
			return _failure("invalid_trace_point", "trace[%d]" % index)
		var point: Dictionary = points[index]
		var validation := validate(point)
		if not bool(validation.get("success", false)):
			validation["trace_index"] = index
			return validation
		var generation := int(point["generation"])
		if generation <= previous_generation:
			return _failure("non_increasing_generation", "trace[%d].generation" % index)
		previous_generation = generation
	return {"success": true, "point_count": points.size()}


static func compute_field_hash(generation: int, generation_map: Dictionary) -> String:
	var tokens := PackedStringArray([FIELD_HASH_DOMAIN, "generation=%d" % generation])
	var keys := generation_map.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	for key_variant in keys:
		var state_variant: Variant = generation_map[key_variant]
		if typeof(state_variant) != TYPE_DICTIONARY:
			continue
		var state: Dictionary = state_variant
		var center: Vector2 = state.get("patch_center", Vector2.ZERO)
		tokens.append("state=%s|patch=%s|population=%s|base=%d|source=%.9f|center=%.9f,%.9f" % [
			String(key_variant),
			String(state.get("patch_id", "")),
			String(state.get("population_id", "")),
			int(state.get("base_count", 0)),
			float(state.get("source_biomass_kg", 0.0)),
			center.x,
			center.y,
		])
		var records: Array = Array(state.get("records", [])).duplicate(false)
		records.sort_custom(func(a: Variant, b: Variant) -> bool:
			if typeof(a) != TYPE_DICTIONARY:
				return true
			if typeof(b) != TYPE_DICTIONARY:
				return false
			return String(Dictionary(a).get("stable_id", "")) < String(Dictionary(b).get("stable_id", ""))
		)
		for record_variant in records:
			if typeof(record_variant) != TYPE_DICTIONARY:
				continue
			var record: Dictionary = record_variant
			var genome: Dictionary = record.get("genome", {})
			var lineage: Dictionary = record.get("lineage", {})
			tokens.append("record=%s|parent=%s|population=%s|x=%.9f|z=%.9f|birth=%d|age=%d|mass=%.12f|fitness=%.12f|genome=%s|lineage=%s|event=%s" % [
				String(record.get("stable_id", "")),
				String(record.get("parent_stable_id", "")),
				String(record.get("population_id", state.get("population_id", ""))),
				float(record.get("world_x", 0.0)),
				float(record.get("world_z", 0.0)),
				int(record.get("birth_generation", 0)),
				int(record.get("age_generations", 0)),
				float(record.get("represented_biomass_kg", 0.0)),
				float(record.get("current_fitness", 0.0)),
				String(genome.get("checksum", "")),
				String(lineage.get("lineage_id", "")),
				String(lineage.get("event_hash", lineage.get("checksum", ""))),
			])
	return "\n".join(tokens).sha256_text()


static func _failure(code: String, field_name: String) -> Dictionary:
	return {"success": false, "error": code, "field": field_name}


static func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102):
			return false
	return true
