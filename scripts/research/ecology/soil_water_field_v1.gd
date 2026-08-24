extends RefCounted

## ECO.EVO7 FFF4 - deterministic bounded soil-water field.
## Texture is a versioned research selector, not geology authority. Plant records are
## canonically sorted; uptake is proportionally apportioned and can never exceed
## either water available after evaporation or each individual request. Canopy shade
## suppresses only evaporation.
const EffectV2 = preload("res://scripts/research/ecology/plant_environment_effect_v2.gd")
const SCHEMA := "distributed_world_simulator.ecology.soil_water_field.v1"
const VERSION := "1.0.0"
const MAX_PPM := 1000000
const TEXTURES := {
	"sand": {"retention": 0.72, "evaporation": 1.18},
	"loam": {"retention": 1.00, "evaporation": 1.00},
	"clay": {"retention": 1.14, "evaporation": 0.84},
}

static func compute(base_moisture_ppm: int, texture: String, sunlight: float, plant_records: Array, generation := 0) -> Dictionary:
	if not TEXTURES.has(texture) or generation < 0 or base_moisture_ppm < 0 or base_moisture_ppm > MAX_PPM:
		return {}
	if not is_finite(sunlight) or sunlight < 0.0 or sunlight > 1.0 or plant_records.is_empty():
		return {}
	var records := plant_records.duplicate(true)
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("identity", "")) < String(b.get("identity", "")))
	var seen := {}
	for record in records:
		if not _valid_record(record):
			return {}
		var identity := String(record["identity"])
		if seen.has(identity):
			return {}
		seen[identity] = true

	var cfg: Dictionary = TEXTURES[texture]
	var available_before := clampi(int(floor(float(base_moisture_ppm) * float(cfg["retention"]))), 0, MAX_PPM)
	var base_evaporation := clampi(int(floor(70000.0 * sunlight * float(cfg["evaporation"]))), 0, available_before)
	var suppression_requests: Array[int] = []
	for record in records:
		var raw := int(floor(float(int(record["shade_output_ppm"])) * 0.18 + float(record["leaf_area_index_proxy"]) * 9000.0))
		suppression_requests.append(maxi(raw, 0))
	var suppression_cap := int(floor(float(base_evaporation) * 0.80))
	var suppression_alloc := _apportion(suppression_requests, suppression_cap)
	var total_suppression := 0
	for value in suppression_alloc:
		total_suppression += value
	var evaporation_loss := maxi(base_evaporation - total_suppression, 0)
	var water_for_plants := maxi(available_before - evaporation_loss, 0)

	var uptake_requests: Array[int] = []
	for record in records:
		var depth_norm := clampf(float(record["realized_root_depth_m"]) / 4.0, 0.0, 1.0)
		var spread_norm := clampf(float(record["realized_root_spread_m"]) / 5.0, 0.0, 1.0)
		var allocation := clampf(float(record["root_shoot_ratio"]), 0.0, 1.0)
		var access := clampf(0.20 + 0.40 * depth_norm + 0.20 * spread_norm + 0.20 * allocation, 0.05, 1.0)
		uptake_requests.append(maxi(int(floor(float(int(record["transpiration_demand_ppm"])) * access)), 0))
	var uptake_alloc := _apportion(uptake_requests, water_for_plants)
	var total_uptake := 0
	for value in uptake_alloc:
		total_uptake += value
	var water_after := maxi(water_for_plants - total_uptake, 0)

	var plant_water := {}
	var effects: Array = []
	for index in records.size():
		var record: Dictionary = records[index]
		var demand := maxi(int(record["transpiration_demand_ppm"]), 1)
		var uptake := uptake_alloc[index]
		if uptake > uptake_requests[index] or suppression_alloc[index] > suppression_requests[index]:
			return {}
		var satisfaction := clampf(float(uptake) / float(demand), 0.0, 1.0)
		var depth_norm := clampf(float(record["realized_root_depth_m"]) / 4.0, 0.0, 1.0)
		var effective_moisture := clampf(float(base_moisture_ppm) / float(MAX_PPM) * (0.30 + 0.70 * satisfaction) + 0.12 * depth_norm, 0.0, 1.0)
		var identity := String(record["identity"])
		plant_water[identity] = {
			"water_uptake_ppm": uptake,
			"water_satisfaction": snappedf(satisfaction, 1e-9),
			"effective_soil_moisture": snappedf(effective_moisture, 1e-9),
		}
		var effect := EffectV2.create(identity, String(record.get("cell_identity", "cell-0")), generation,
			int(record["shade_output_ppm"]), uptake, suppression_alloc[index], String(record["source_phenotype_hash"]))
		if effect.is_empty() or not bool(EffectV2.validate(effect).get("success", false)):
			return {}
		effects.append(effect)

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"generation": generation,
		"texture": texture,
		"base_moisture_ppm": base_moisture_ppm,
		"available_before_ppm": available_before,
		"base_evaporation_ppm": base_evaporation,
		"evaporation_suppression_ppm": total_suppression,
		"evaporation_loss_ppm": evaporation_loss,
		"total_uptake_ppm": total_uptake,
		"water_after_ppm": water_after,
		"plant_water": plant_water,
		"effects": effects,
		"effects_hash": EffectV2.combined_hash(effects),
	}
	if total_uptake > water_for_plants or water_after < 0:
		return {}
	result["field_hash"] = _field_hash(result)
	return result

static func _apportion(requests: Array[int], limit: int) -> Array[int]:
	var result: Array[int] = []
	result.resize(requests.size())
	result.fill(0)
	var total := 0
	for request in requests:
		total += maxi(request, 0)
	if total <= 0 or limit <= 0:
		return result
	if total <= limit:
		for index in requests.size():
			result[index] = maxi(requests[index], 0)
		return result
	var assigned := 0
	var positive_indices: Array[int] = []
	for index in requests.size():
		var request := maxi(requests[index], 0)
		if request > 0:
			positive_indices.append(index)
		var share := mini(request, int(floor(float(limit) * float(request) / float(total))))
		result[index] = share
		assigned += share
	var remainder := maxi(limit - assigned, 0)
	while remainder > 0:
		var progressed := false
		for index in positive_indices:
			var request := maxi(requests[index], 0)
			if result[index] >= request:
				continue
			result[index] += 1
			remainder -= 1
			progressed = true
			if remainder == 0:
				break
		if not progressed:
			break
	return result

static func _valid_record(record: Dictionary) -> bool:
	for key in ["identity", "realized_root_depth_m", "realized_root_spread_m", "root_shoot_ratio", "leaf_area_index_proxy", "transpiration_demand_ppm", "shade_output_ppm", "source_phenotype_hash"]:
		if not record.has(key):
			return false
	if String(record["identity"]).is_empty() or String(record["source_phenotype_hash"]).length() != 64:
		return false
	for key in ["realized_root_depth_m", "realized_root_spread_m", "root_shoot_ratio", "leaf_area_index_proxy"]:
		if typeof(record[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(record[key])) or float(record[key]) < 0.0:
			return false
	for key in ["transpiration_demand_ppm", "shade_output_ppm"]:
		if typeof(record[key]) != TYPE_INT or int(record[key]) < 0:
			return false
	return true

static func _field_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA, VERSION, String(result.get("texture", "")), str(int(result.get("generation", -1))),
		str(int(result.get("base_moisture_ppm", -1))), str(int(result.get("available_before_ppm", -1))),
		str(int(result.get("base_evaporation_ppm", -1))), str(int(result.get("evaporation_suppression_ppm", -1))),
		str(int(result.get("evaporation_loss_ppm", -1))), str(int(result.get("total_uptake_ppm", -1))),
		str(int(result.get("water_after_ppm", -1))), String(result.get("effects_hash", "")),
	])
	var identities := PackedStringArray()
	for identity in result.get("plant_water", {}).keys():
		identities.append(String(identity))
	identities.sort()
	for identity in identities:
		var item: Dictionary = result["plant_water"][identity]
		tokens.append("%s:%d:%.9f:%.9f" % [identity, int(item["water_uptake_ppm"]), float(item["water_satisfaction"]), float(item["effective_soil_moisture"])])
	return "|".join(tokens).sha256_text()
