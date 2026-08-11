extends RefCounted

const DevelopmentTraits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")

const SEED_ENVELOPE_SCHEMA := "distributed_world_simulator.ecology.seed_genome_envelope.v1"
const DEVELOPMENT_STATE_SCHEMA := "distributed_world_simulator.ecology.plant_development_state.v1"
const GROWTH_GRAPH_SCHEMA := "distributed_world_simulator.ecology.plant_growth_graph.v1"
const VERSION := "1.0.0"

static func derive_individual_seed(parent_lineage: String, reproduction_event: String, seed_index: int, genome_revision: String) -> int:
	if parent_lineage.is_empty() or reproduction_event.is_empty() or seed_index < 0 or genome_revision.is_empty():
		return -1
	var digest := "%s|%s|%d|%s" % [parent_lineage, reproduction_event, seed_index, genome_revision]
	return digest.sha256_text().substr(0, 15).hex_to_int()

static func create_seed_envelope(
	genome: Dictionary,
	development_traits: Dictionary,
	parent_lineage: String,
	reproduction_event: String,
	seed_index: int,
	stored_energy: float = 1.0
) -> Dictionary:
	if not bool(PlantGenome.validate(genome).get("success", false)):
		return {}
	if not bool(DevelopmentTraits.validate(development_traits).get("success", false)):
		return {}
	if stored_energy < 0.0 or not is_finite(stored_energy):
		return {}
	var individual_seed := derive_individual_seed(parent_lineage, reproduction_event, seed_index, String(genome.get("version", "")))
	if individual_seed < 0:
		return {}
	var result := {
		"schema": SEED_ENVELOPE_SCHEMA,
		"version": VERSION,
		"genome_checksum": String(genome["checksum"]),
		"development_traits_checksum": String(development_traits["checksum"]),
		"lineage_parent": parent_lineage,
		"reproduction_event": reproduction_event,
		"seed_index": seed_index,
		"stored_energy": stored_energy,
		"dormancy": false,
		"age_years": 0.0,
		"individual_seed": individual_seed,
	}
	result["checksum"] = _seed_envelope_checksum(result)
	return result

static func create_initial_development_state(seed_envelope: Dictionary) -> Dictionary:
	if seed_envelope.is_empty() or String(seed_envelope.get("schema", "")) != SEED_ENVELOPE_SCHEMA:
		return {}
	return {
		"schema": DEVELOPMENT_STATE_SCHEMA,
		"version": VERSION,
		"individual_seed": int(seed_envelope.get("individual_seed", -1)),
		"age_years": 0.0,
		"biomass_kg": 0.0,
		"reserve_energy": float(seed_envelope.get("stored_energy", 0.0)),
		"accumulated_stress": 0.0,
		"dormancy": bool(seed_envelope.get("dormancy", false)),
		"root_allocation": 0.5,
		"shoot_allocation": 0.5,
		"damage_revision": 0,
	}

static func create_empty_growth_graph(individual_seed: int, development_traits_checksum: String) -> Dictionary:
	if individual_seed < 0 or development_traits_checksum.length() != 64:
		return {}
	return {
		"schema": GROWTH_GRAPH_SCHEMA,
		"version": VERSION,
		"individual_seed": individual_seed,
		"development_traits_checksum": development_traits_checksum,
		"derived_representation": true,
		"segments": [],
		"graph_hash": "",
	}

static func _seed_envelope_checksum(envelope: Dictionary) -> String:
	return "|".join(PackedStringArray([
		SEED_ENVELOPE_SCHEMA,
		VERSION,
		String(envelope.get("genome_checksum", "")),
		String(envelope.get("development_traits_checksum", "")),
		String(envelope.get("lineage_parent", "")),
		String(envelope.get("reproduction_event", "")),
		str(int(envelope.get("seed_index", -1))),
		"%.9f" % float(envelope.get("stored_energy", 0.0)),
		str(int(envelope.get("individual_seed", -1))),
	])).sha256_text()
