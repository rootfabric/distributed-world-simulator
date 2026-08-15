extends RefCounted

const VIS15_Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const VIS15_Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const VIS15_Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const VIS15_EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const VIS15_Development = preload("res://scripts/research/ecology/plant_environment_coupled_development_v1.gd")
const VIS15_RenderDescription = preload("res://scripts/research/ecology/plant_render_description_v1.gd")
const VIS15_Materializer3D = preload("res://scripts/research/ecology/plant_3d_materializer_v1.gd")
const VIS15_RendererProfile = preload("res://scripts/research/ecology/plant_renderer_profile_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.vis1_5_environment_phenotype_bridge.v1"
const VERSION := "1.0.0"
const MODE := "SHARED_LAB_BASELINE_LOCAL_ENVIRONMENT"


static func create_baseline_genome() -> Dictionary:
	return VIS15_Genome.create_default()


static func create_baseline_traits() -> Dictionary:
	return VIS15_Traits.create_default()


static func realize(
	genome: Dictionary,
	inherited_traits: Dictionary,
	environment_sample: Dictionary,
	profile: Dictionary,
	source_snapshot_hash: String,
	patch_id: String,
	population_id: String,
	instance_index: int
) -> Dictionary:
	if source_snapshot_hash.length() != 64 or patch_id.is_empty() or population_id.is_empty() or instance_index < 0:
		return {}
	if not bool(VIS15_Genome.validate(genome).get("success", false)):
		return {}
	if not bool(VIS15_Traits.validate(inherited_traits).get("success", false)):
		return {}
	if not bool(VIS15_EnvironmentSample.validate(environment_sample).get("success", false)):
		return {}
	if not bool(VIS15_RendererProfile.validate(profile).get("success", false)):
		return {}

	var parent_lineage := "lab-lineage/vis1-5/%s/%s" % [patch_id, population_id]
	var reproduction_event := "snapshot/%s" % source_snapshot_hash
	var envelope := VIS15_Contract.create_seed_envelope(
		genome,
		inherited_traits,
		parent_lineage,
		reproduction_event,
		instance_index
	)
	if envelope.is_empty():
		return {}

	var phenotype := VIS15_Development.realize(envelope, inherited_traits, environment_sample)
	if phenotype.is_empty():
		return {}
	var growth_graph: Dictionary = phenotype.get("growth_graph", {})
	var description := VIS15_RenderDescription.build(growth_graph)
	if description.is_empty():
		return {}
	var materialization := VIS15_Materializer3D.build(description, profile)
	if materialization.is_empty():
		return {}

	var realized_traits: Dictionary = phenotype.get("realized_development_traits", {})
	var response: Dictionary = phenotype.get("response", {})
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"derived_presentation": true,
		"mode": MODE,
		"source_snapshot_hash": source_snapshot_hash,
		"patch_id": patch_id,
		"population_id": population_id,
		"instance_index": instance_index,
		"genome_id": String(genome.get("genome_id", "")),
		"genome_checksum": String(genome.get("checksum", "")),
		"inherited_traits_checksum": String(inherited_traits.get("checksum", "")),
		"environment_checksum": String(environment_sample.get("checksum", "")),
		"phenotype_hash": String(phenotype.get("phenotype_hash", "")),
		"growth_graph_hash": String(growth_graph.get("graph_hash", "")),
		"render_description_hash": String(description.get("render_description_hash", "")),
		"geometry_hash": String(materialization.get("geometry_hash", "")),
		"response": response.duplicate(true),
		"realized_traits": realized_traits.duplicate(true),
		"render_description": description,
		"materialization": materialization,
	}
	result["bridge_hash"] = compute_hash(result)
	return result


static func compute_hash(result: Dictionary) -> String:
	return "|".join(PackedStringArray([
		SCHEMA,
		VERSION,
		MODE,
		String(result.get("source_snapshot_hash", "")),
		String(result.get("patch_id", "")),
		String(result.get("population_id", "")),
		str(int(result.get("instance_index", -1))),
		String(result.get("genome_checksum", "")),
		String(result.get("inherited_traits_checksum", "")),
		String(result.get("environment_checksum", "")),
		String(result.get("phenotype_hash", "")),
		String(result.get("growth_graph_hash", "")),
		String(result.get("render_description_hash", "")),
		String(result.get("geometry_hash", "")),
	])).sha256_text()
