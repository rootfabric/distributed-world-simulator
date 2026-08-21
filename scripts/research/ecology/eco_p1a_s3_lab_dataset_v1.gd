extends RefCounted

const Fixture = preload("res://scripts/research/ecology/synthetic_environment_fixture_v1.gd")
const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const ResourceModel = preload("res://scripts/research/ecology/plant_resource_model_v1.gd")
const PatchSimulator = preload("res://scripts/research/ecology/single_plant_patch_simulator_v1.gd")
const Probes = preload("res://scripts/research/ecology/controlled_trait_probes_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.p1a_s3_lab_dataset.v1"
const VERSION := "1.0.0"
const DEFAULT_GRID_SIZE := 25
const DEFAULT_SEASONS := 24
const VIEW_TEMPERATURE := "temperature_c"
const VIEW_SOIL_MOISTURE := "soil_moisture"
const VIEW_SUNLIGHT := "sunlight"
const VIEW_NUTRIENTS := "nutrients"
const VIEW_FLOOD := "flood_frequency"
const VIEW_BIOMASS := "final_biomass_kg_m2"
const VIEW_NET_BALANCE := "net_resource_balance"
const VIEW_LIMITING_FACTOR := "dominant_limiting_factor"
const VIEW_IDS: Array[String] = [
	VIEW_TEMPERATURE,
	VIEW_SOIL_MOISTURE,
	VIEW_SUNLIGHT,
	VIEW_NUTRIENTS,
	VIEW_FLOOD,
	VIEW_BIOMASS,
	VIEW_NET_BALANCE,
	VIEW_LIMITING_FACTOR,
]
const NUMERIC_VIEW_IDS: Array[String] = [
	VIEW_TEMPERATURE,
	VIEW_SOIL_MOISTURE,
	VIEW_SUNLIGHT,
	VIEW_NUTRIENTS,
	VIEW_FLOOD,
	VIEW_BIOMASS,
	VIEW_NET_BALANCE,
]


static func build(
	probe_id: String = Probes.BASE,
	grid_size: int = DEFAULT_GRID_SIZE,
	seasons: int = DEFAULT_SEASONS,
	seed: int = Fixture.DEFAULT_SEED
) -> Dictionary:
	if grid_size < 3 or seasons <= 0 or not probe_id in Probes.ORDER:
		return {}
	var genome := Probes.genome(probe_id)
	if not bool(PlantGenome.validate(genome).get("success", false)):
		return {}

	var records: Array[Dictionary] = []
	var ranges := {}
	for view_id in NUMERIC_VIEW_IDS:
		ranges[view_id] = {"min": INF, "max": -INF}
	var limiting_counts := {"LIGHT": 0, "WATER": 0, "NUTRIENT": 0, "TEMPERATURE": 0, "FLOOD": 0}
	var viability_counts := {"FAVOURABLE": 0, "MARGINAL": 0, "UNSUSTAINABLE": 0}
	var hash_tokens := PackedStringArray()
	for iz in range(grid_size):
		for ix in range(grid_size):
			var position := Fixture.grid_position(ix, iz, grid_size)
			var record := sample_world(position.x, position.y, probe_id, seasons, seed)
			if record.is_empty():
				return {}
			record["ix"] = ix
			record["iz"] = iz
			records.append(record)
			for view_id in NUMERIC_VIEW_IDS:
				var value := float(record[view_id])
				ranges[view_id]["min"] = minf(float(ranges[view_id]["min"]), value)
				ranges[view_id]["max"] = maxf(float(ranges[view_id]["max"]), value)
			var limiting := String(record[VIEW_LIMITING_FACTOR])
			limiting_counts[limiting] = int(limiting_counts.get(limiting, 0)) + 1
			var viability := String(record["viability_class"])
			viability_counts[viability] = int(viability_counts.get(viability, 0)) + 1
			hash_tokens.append("%d,%d:%s:%s:%s" % [ix, iz, String(record["environment_checksum"]), String(record["balance_checksum"]), String(record["simulation_checksum"])])

	var dataset := {
		"schema": SCHEMA,
		"version": VERSION,
		"probe_id": probe_id,
		"genome_checksum": String(genome["checksum"]),
		"environment_revision": Fixture.ENVIRONMENT_REVISION,
		"seed": seed,
		"grid_size": grid_size,
		"seasons": seasons,
		"records": records,
		"ranges": ranges,
		"limiting_counts": limiting_counts,
		"viability_counts": viability_counts,
		"environment_hash": Fixture.environment_hash(Fixture.LOGICAL_GRID_SIZE, seed),
	}
	dataset["dataset_hash"] = _dataset_hash(dataset, hash_tokens)
	return dataset


static func sample_world(
	world_x_m: float,
	world_z_m: float,
	probe_id: String = Probes.BASE,
	seasons: int = DEFAULT_SEASONS,
	seed: int = Fixture.DEFAULT_SEED
) -> Dictionary:
	var genome := Probes.genome(probe_id)
	if genome.is_empty():
		return {}
	var environment := Fixture.sample_at(world_x_m, world_z_m, seed)
	var initial_balance := ResourceModel.evaluate(environment, genome, PatchSimulator.DEFAULT_INITIAL_BIOMASS_KG_M2)
	var simulation := PatchSimulator.simulate(environment, genome, seasons, PatchSimulator.DEFAULT_INITIAL_BIOMASS_KG_M2)
	if initial_balance.is_empty() or simulation.is_empty():
		return {}
	return {
		"world_x_m": float(environment["world_x_m"]),
		"world_z_m": float(environment["world_z_m"]),
		"temperature_c": float(environment["temperature_c"]),
		"soil_moisture": float(environment["soil_moisture"]),
		"sunlight": float(environment["sunlight"]),
		"nutrients": float(environment["nutrients"]),
		"flood_frequency": float(environment["flood_frequency"]),
		"effective_soil_moisture": float(initial_balance["effective_soil_moisture"]),
		"light_response": float(initial_balance["light_response"]),
		"water_response": float(initial_balance["water_response"]),
		"nutrient_response": float(initial_balance["nutrient_response"]),
		"temperature_response": float(initial_balance["temperature_response"]),
		"light_limitation": float(initial_balance["light_limitation"]),
		"water_limitation": float(initial_balance["water_limitation"]),
		"nutrient_limitation": float(initial_balance["nutrient_limitation"]),
		"temperature_limitation": float(initial_balance["temperature_limitation"]),
		"flood_limitation": float(initial_balance["flood_limitation"]),
		"gross_photosynthetic_income": float(initial_balance["gross_photosynthetic_income"]),
		"maintenance_cost": float(initial_balance["maintenance_cost"]),
		"root_cost": float(initial_balance["root_cost"]),
		"structural_cost": float(initial_balance["structural_cost"]),
		"growth_allocation_cost": float(initial_balance["growth_allocation_cost"]),
		"reproduction_allocation_cost": float(initial_balance["reproduction_allocation_cost"]),
		"water_stress_penalty": float(initial_balance["water_stress_penalty"]),
		"flood_penalty": float(initial_balance["flood_penalty"]),
		"density_cost": float(initial_balance["density_cost"]),
		"net_resource_balance": float(initial_balance["net_resource_balance"]),
		"dominant_limiting_factor": String(initial_balance["dominant_limiting_factor"]),
		"viability_class": String(initial_balance["viability_class"]),
		"final_biomass_kg_m2": float(simulation["final_biomass_kg_m2"]),
		"peak_biomass_kg_m2": float(simulation["peak_biomass_kg_m2"]),
		"productive_seasons": int(simulation["productive_seasons"]),
		"stress_seasons": int(simulation["stress_seasons"]),
		"environment_checksum": String(environment["checksum"]),
		"balance_checksum": String(initial_balance["checksum"]),
		"simulation_checksum": String(simulation["checksum"]),
	}


static func control_point(name: String, probe_id: String = Probes.BASE, seasons: int = DEFAULT_SEASONS) -> Dictionary:
	if not Fixture.CONTROL_POINTS.has(name):
		return {}
	var position: Vector2 = Fixture.CONTROL_POINTS[name]
	return sample_world(position.x, position.y, probe_id, seasons)


static func record(dataset: Dictionary, ix: int, iz: int) -> Dictionary:
	var grid_size := int(dataset.get("grid_size", 0))
	if grid_size <= 0 or ix < 0 or iz < 0 or ix >= grid_size or iz >= grid_size:
		return {}
	var records: Array = dataset.get("records", [])
	var index := iz * grid_size + ix
	if index < 0 or index >= records.size():
		return {}
	return Dictionary(records[index])


static func normalized_value(dataset: Dictionary, record_value: Dictionary, view_id: String) -> float:
	if not view_id in NUMERIC_VIEW_IDS:
		return 0.0
	var range: Dictionary = dataset.get("ranges", {}).get(view_id, {})
	var minimum := float(range.get("min", 0.0))
	var maximum := float(range.get("max", 0.0))
	if maximum - minimum <= 0.000000001:
		return 0.5
	return clampf((float(record_value.get(view_id, minimum)) - minimum) / (maximum - minimum), 0.0, 1.0)


static func _dataset_hash(dataset: Dictionary, record_tokens: PackedStringArray) -> String:
	return "|".join(PackedStringArray([
		SCHEMA,
		VERSION,
		String(dataset.get("probe_id", "")),
		String(dataset.get("genome_checksum", "")),
		String(dataset.get("environment_revision", "")),
		str(int(dataset.get("seed", 0))),
		str(int(dataset.get("grid_size", 0))),
		str(int(dataset.get("seasons", 0))),
		String(dataset.get("environment_hash", "")),
		"\n".join(record_tokens),
	])).sha256_text()
