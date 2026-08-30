extends RefCounted

const DescriptorV2 = preload("res://scripts/labs/ecology/eco_evo7_vis4_morphology_render_adapter.gd")

## ECO.EVO7 VIS4.2 — pure diagnostic morphology mapper.
##
## Input is ONLY the sealed Descriptor V2 result produced by VIS4.1.
## This file owns no biology, mutation, competition, persistence or network authority.
## It preserves source morphology values and derives only presentation hashes.

const SCHEMA := "distributed_world_simulator.ecology.evo7_vis4_2_diagnostic_morphology.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-VIS4.2.R1"

const SOURCE_SCHEMA := "distributed_world_simulator.ecology.evo7_vis4_morphology_render_adapter.v2"
const SOURCE_VERSION := "2.0.0"
const SOURCE_REVISION := "ECO.EVO7-VIS4.1.R2"
const SOURCE_EVIDENCE := "LS3.4_SOURCE_BOUND_MORPHOLOGY"

const RESULT_FIELDS: Array[String] = [
	"schema", "version", "revision", "generation",
	"source_adapter_hash", "source_ecology_state_hash", "source_morphology_evidence_hash",
	"descriptor_count", "descriptors", "render_hash",
]

const DESCRIPTOR_FIELDS: Array[String] = [
	"record_id", "cell_index", "lineage_id",
	"source_descriptor_hash", "source_evidence_record_hash", "source_growth_graph_hash",
	"hereditary_individual_seed", "development_individual_seed",
	"realized_height_m", "realized_crown_radius_m", "realized_crown_density",
	"structural_investment", "leaf_conservative_strategy",
	"apical_dominance", "branch_probability", "branch_angle_deg",
	"branch_length_ratio", "branching_depth", "crown_spread_m", "foliage_density",
	"silhouette_hash", "render_descriptor_hash",
]

func build(source: Dictionary) -> Dictionary:
	if not _validate_source_envelope(source):
		return {}
	var generation := int(source.get("generation", -1))
	if generation < 1:
		# VIS4.2 is intentionally a realized-morphology diagnostic. Generation zero
		# remains founder/potential-only and is rendered by prior VIS surfaces.
		return {}

	var descriptors_value = source.get("descriptors")
	if not descriptors_value is Array:
		return {}
	var descriptors: Array[Dictionary] = []
	for value in Array(descriptors_value):
		if not value is Dictionary:
			return {}
		var mapped := _map_descriptor(value)
		if mapped.is_empty():
			return {}
		descriptors.append(mapped)
	descriptors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["record_id"]) < String(b["record_id"])
	)

	if descriptors.size() != int(source.get("descriptor_count", -1)):
		return {}
	if descriptors.size() != int(source.get("morphology_evidence_count", -2)):
		return {}
	if int(source.get("founder_marker_count", -1)) != 0:
		return {}

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"generation": generation,
		"source_adapter_hash": String(source.get("adapter_hash", "")),
		"source_ecology_state_hash": String(source.get("source_ecology_state_hash", "")),
		"source_morphology_evidence_hash": String(source.get("source_morphology_evidence_hash", "")),
		"descriptor_count": descriptors.size(),
		"descriptors": descriptors,
	}
	result["render_hash"] = _render_hash(result)
	return result if validate_result(result) else {}

func validate_result(result: Dictionary) -> bool:
	if not _exact_keys(result, RESULT_FIELDS):
		return false
	if String(result.get("schema", "")) != SCHEMA or String(result.get("version", "")) != VERSION or String(result.get("revision", "")) != REVISION:
		return false
	if int(result.get("generation", -1)) < 1:
		return false
	for key in ["source_adapter_hash", "source_ecology_state_hash", "source_morphology_evidence_hash"]:
		if String(result.get(key, "")).length() != 64:
			return false
	var descriptors_value = result.get("descriptors")
	if not descriptors_value is Array:
		return false
	var descriptors: Array = descriptors_value
	if int(result.get("descriptor_count", -1)) != descriptors.size():
		return false
	var previous_id := ""
	for value in descriptors:
		if not value is Dictionary or not _validate_descriptor(value):
			return false
		var record_id := String(Dictionary(value).get("record_id", ""))
		if not previous_id.is_empty() and record_id <= previous_id:
			return false
		previous_id = record_id
	return String(result.get("render_hash", "")) == _render_hash(result)

func _validate_source_envelope(source: Dictionary) -> bool:
	if source.is_empty():
		return false
	if String(source.get("schema", "")) != SOURCE_SCHEMA or String(source.get("version", "")) != SOURCE_VERSION or String(source.get("revision", "")) != SOURCE_REVISION:
		return false
	if not DescriptorV2.new().validate_result(source):
		return false
	if int(source.get("generation", -1)) < 0:
		return false
	for key in ["source_ecology_state_hash", "adapter_hash"]:
		if String(source.get(key, "")).length() != 64:
			return false
	if int(source.get("generation", 0)) > 0 and String(source.get("source_morphology_evidence_hash", "")).length() != 64:
		return false
	var descriptors_value = source.get("descriptors")
	if not descriptors_value is Array:
		return false
	return int(source.get("descriptor_count", -1)) == Array(descriptors_value).size()

func _map_descriptor(source: Dictionary) -> Dictionary:
	if String(source.get("evidence_level", "")) != SOURCE_EVIDENCE:
		return {}
	for key in [
		"descriptor_hash", "source_evidence_record_hash", "growth_graph_hash",
	]:
		if String(source.get(key, "")).length() != 64:
			return {}
	var topology_value = source.get("realized_topology")
	var functional_value = source.get("functional_morphology")
	var potential_value = source.get("potential_morphology")
	if not topology_value is Dictionary or not functional_value is Dictionary or not potential_value is Dictionary:
		return {}
	var topology: Dictionary = topology_value
	var functional: Dictionary = functional_value
	var potential: Dictionary = potential_value

	var descriptor := {
		"record_id": String(source.get("record_id", "")),
		"cell_index": int(source.get("cell_index", -1)),
		"lineage_id": String(source.get("lineage_id", "")),
		"source_descriptor_hash": String(source.get("descriptor_hash", "")),
		"source_evidence_record_hash": String(source.get("source_evidence_record_hash", "")),
		"source_growth_graph_hash": String(source.get("growth_graph_hash", "")),
		"hereditary_individual_seed": int(source.get("hereditary_individual_seed", -1)),
		"development_individual_seed": int(source.get("development_individual_seed", -1)),
		"realized_height_m": float(functional.get("realized_height_m", NAN)),
		"realized_crown_radius_m": float(functional.get("realized_crown_radius_m", NAN)),
		"realized_crown_density": float(functional.get("realized_crown_density", NAN)),
		"structural_investment": float(functional.get("structural_investment", NAN)),
		"leaf_conservative_strategy": float(functional.get("leaf_conservative_strategy", NAN)),
		"apical_dominance": float(topology.get("apical_dominance", NAN)),
		"branch_probability": float(topology.get("branch_probability", NAN)),
		"branch_angle_deg": float(topology.get("branch_angle_deg", NAN)),
		"branch_length_ratio": float(topology.get("branch_length_ratio", NAN)),
		"branching_depth": int(topology.get("branching_depth", -1)),
		"crown_spread_m": float(topology.get("crown_spread_m", NAN)),
		"foliage_density": float(potential.get("foliage_density", NAN)),
	}
	descriptor["silhouette_hash"] = _silhouette_hash(descriptor)
	descriptor["render_descriptor_hash"] = _descriptor_hash(descriptor)
	return descriptor if _validate_descriptor(descriptor) else {}

func _validate_descriptor(value: Dictionary) -> bool:
	if not _exact_keys(value, DESCRIPTOR_FIELDS):
		return false
	if String(value.get("record_id", "")).is_empty() or String(value.get("lineage_id", "")).is_empty():
		return false
	if int(value.get("cell_index", -1)) < 0 or int(value.get("cell_index", -1)) >= 1024:
		return false
	if int(value.get("hereditary_individual_seed", -1)) < 0 or int(value.get("development_individual_seed", -1)) < 0:
		return false
	for key in ["source_descriptor_hash", "source_evidence_record_hash", "source_growth_graph_hash", "silhouette_hash", "render_descriptor_hash"]:
		if String(value.get(key, "")).length() != 64:
			return false
	for key in [
		"realized_height_m", "realized_crown_radius_m", "realized_crown_density",
		"structural_investment", "leaf_conservative_strategy", "apical_dominance",
		"branch_probability", "branch_angle_deg", "branch_length_ratio",
		"crown_spread_m", "foliage_density",
	]:
		if not is_finite(float(value.get(key, NAN))):
			return false
	if float(value.get("realized_height_m", -1.0)) < 0.0 or float(value.get("realized_crown_radius_m", -1.0)) < 0.0:
		return false
	for key in ["realized_crown_density", "structural_investment", "leaf_conservative_strategy", "apical_dominance", "branch_probability", "foliage_density"]:
		var v := float(value.get(key, -1.0))
		if v < 0.0 or v > 1.0:
			return false
	if float(value.get("branch_angle_deg", -1.0)) < 0.0 or float(value.get("branch_angle_deg", 181.0)) > 180.0:
		return false
	if float(value.get("branch_length_ratio", -1.0)) < 0.0:
		return false
	if int(value.get("branching_depth", -1)) < 0:
		return false
	if float(value.get("crown_spread_m", -1.0)) < 0.0:
		return false
	if String(value.get("silhouette_hash", "")) != _silhouette_hash(value):
		return false
	return String(value.get("render_descriptor_hash", "")) == _descriptor_hash(value)

func _silhouette_hash(value: Dictionary) -> String:
	return "|".join(PackedStringArray([
		SCHEMA, VERSION, REVISION, "silhouette",
		_f(float(value.get("realized_height_m", 0.0))),
		_f(float(value.get("realized_crown_radius_m", 0.0))),
		_f(float(value.get("realized_crown_density", 0.0))),
		_f(float(value.get("structural_investment", 0.0))),
		_f(float(value.get("leaf_conservative_strategy", 0.0))),
		_f(float(value.get("apical_dominance", 0.0))),
		_f(float(value.get("branch_probability", 0.0))),
		_f(float(value.get("branch_angle_deg", 0.0))),
		_f(float(value.get("branch_length_ratio", 0.0))),
		str(int(value.get("branching_depth", 0))),
		_f(float(value.get("crown_spread_m", 0.0))),
		_f(float(value.get("foliage_density", 0.0))),
	])).sha256_text()

func _descriptor_hash(value: Dictionary) -> String:
	return "|".join(PackedStringArray([
		SCHEMA, VERSION, REVISION, "descriptor",
		String(value.get("record_id", "")), str(int(value.get("cell_index", -1))),
		String(value.get("lineage_id", "")),
		String(value.get("source_descriptor_hash", "")),
		String(value.get("source_evidence_record_hash", "")),
		String(value.get("source_growth_graph_hash", "")),
		str(int(value.get("hereditary_individual_seed", -1))),
		str(int(value.get("development_individual_seed", -1))),
		String(value.get("silhouette_hash", "")),
	])).sha256_text()

func _render_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA, VERSION, REVISION,
		str(int(result.get("generation", -1))),
		String(result.get("source_adapter_hash", "")),
		String(result.get("source_ecology_state_hash", "")),
		String(result.get("source_morphology_evidence_hash", "")),
		str(int(result.get("descriptor_count", -1))),
	])
	for value in Array(result.get("descriptors", [])):
		if value is Dictionary:
			tokens.append(String(Dictionary(value).get("render_descriptor_hash", "")))
	return "|".join(tokens).sha256_text()

func _exact_keys(value: Dictionary, expected: Array[String]) -> bool:
	if value.keys().size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true

func _f(value: float) -> String:
	return "%.9f" % snappedf(value, 1e-9)
