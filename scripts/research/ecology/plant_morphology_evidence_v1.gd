extends RefCounted

## ECO.EVO7 VIS4.1 — source-bound morphology evidence contract.
##
## This module packages morphology facts that LS3.4 already computes in its
## accepted phenotype pass. It is not a biology implementation: no environment
## sampling, plasticity, fitness, competition, mutation, persistence or network
## authority lives here.

const SCHEMA := "distributed_world_simulator.ecology.plant_morphology_evidence.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-VIS4.1.R2"
const DERIVED_REPRESENTATION := true
const PRESENTATION_ONLY := true

const RECORD_FIELDS: Array[String] = [
	"record_id", "cell_index", "bundle_checksum", "lineage_id",
	"hereditary_individual_seed", "development_individual_seed",
	"source_phenotype_hash", "source_plasticity_phenotype_hash", "source_growth_graph_hash",
	"source_inherited_traits_hash", "source_realized_traits_hash", "source_extension_traits_hash",
	"potential_morphology", "realized_topology", "functional_morphology", "evidence_hash",
]
const SNAPSHOT_FIELDS: Array[String] = [
	"schema", "version", "revision", "derived_representation", "presentation_only",
	"generation", "source_precompetition_population_hash", "source_competition_hash",
	"source_postcompetition_population_hash", "record_count", "records", "evidence_hash",
]
const POTENTIAL_FIELDS: Array[String] = [
	"max_height_m", "internode_length_m", "apical_dominance", "branch_probability",
	"branch_angle_deg", "branch_length_ratio", "branching_depth", "crown_spread_m",
	"foliage_density", "leaf_economics_proxy", "structural_investment",
	"root_depth_m", "root_spread_m", "root_shoot_ratio",
]
const REALIZED_TOPOLOGY_FIELDS: Array[String] = [
	"max_height_m", "internode_length_m", "apical_dominance", "branch_probability",
	"branch_angle_deg", "branch_length_ratio", "branching_depth", "crown_spread_m",
]
const FUNCTIONAL_FIELDS: Array[String] = [
	"realized_height_m", "realized_crown_radius_m", "realized_crown_density",
	"leaf_area_index_proxy", "leaf_size_proxy", "leaf_conservative_strategy",
	"structural_investment", "realized_root_depth_m", "realized_root_spread_m",
	"root_shoot_ratio",
]

static func build_record(record: Dictionary, ph2: Dictionary, functional_phenotype: Dictionary) -> Dictionary:
	var bundle_value = record.get("hereditary_bundle")
	if not bundle_value is Dictionary:
		return {}
	var bundle: Dictionary = bundle_value
	var dev_value = bundle.get("dev_traits")
	var ext_value = bundle.get("ext_traits")
	var genome_value = bundle.get("genome")
	var lineage_value = bundle.get("lineage", bundle.get("lineage_record"))
	if not dev_value is Dictionary or not ext_value is Dictionary or not genome_value is Dictionary or not lineage_value is Dictionary:
		return {}
	var dev: Dictionary = dev_value
	var ext: Dictionary = ext_value
	var genome: Dictionary = genome_value
	var lineage: Dictionary = lineage_value
	var realized_value = ph2.get("realized_development_traits")
	var graph_value = ph2.get("growth_graph")
	if not realized_value is Dictionary or not graph_value is Dictionary:
		return {}
	var realized: Dictionary = realized_value
	var graph: Dictionary = graph_value

	var record_id := String(record.get("record_id", ""))
	var cell_index := int(record.get("cell_index", -1))
	var bundle_checksum := String(record.get("bundle_checksum", ""))
	var lineage_id := String(lineage.get("lineage_id", ""))
	var hereditary_individual_seed := int(bundle.get("individual_seed", -1))
	var development_individual_seed := int(ph2.get("individual_seed", -1))
	if record_id.is_empty() or cell_index < 0 or cell_index >= 1024:
		return {}
	if bundle_checksum.length() != 64 or bundle_checksum != String(bundle.get("bundle_checksum", "")):
		return {}
	if lineage_id.is_empty() or hereditary_individual_seed < 0 or development_individual_seed < 0:
		return {}

	var phenotype_hash := String(functional_phenotype.get("phenotype_hash", ""))
	var plasticity_hash := String(ph2.get("phenotype_hash", ""))
	var growth_graph_hash := String(graph.get("graph_hash", ""))
	var inherited_hash := String(ph2.get("inherited_traits_checksum", ""))
	var realized_hash := String(realized.get("checksum", ""))
	var extension_hash := String(ext.get("checksum", ""))
	for hash_value in [phenotype_hash, plasticity_hash, growth_graph_hash, inherited_hash, realized_hash, extension_hash]:
		if String(hash_value).length() != 64:
			return {}
	if development_individual_seed != int(functional_phenotype.get("individual_seed", -1)):
		return {}
	if development_individual_seed != int(graph.get("individual_seed", -1)):
		return {}
	if inherited_hash != String(dev.get("checksum", "")):
		return {}
	if String(functional_phenotype.get("growth_graph_hash", "")) != growth_graph_hash:
		return {}
	if String(functional_phenotype.get("plasticity_phenotype_hash", "")) != plasticity_hash:
		return {}
	if String(functional_phenotype.get("inherited_traits_hash", "")) != inherited_hash:
		return {}

	var potential := {
		"max_height_m": float(dev.get("max_height_m", NAN)),
		"internode_length_m": float(dev.get("internode_length_m", NAN)),
		"apical_dominance": float(dev.get("apical_dominance", NAN)),
		"branch_probability": float(dev.get("branch_probability", NAN)),
		"branch_angle_deg": float(dev.get("branch_angle_deg", NAN)),
		"branch_length_ratio": float(dev.get("branch_length_ratio", NAN)),
		"branching_depth": int(dev.get("branching_depth", -1)),
		"crown_spread_m": float(dev.get("crown_spread_m", NAN)),
		"foliage_density": float(ext.get("foliage_density", NAN)),
		"leaf_economics_proxy": float(ext.get("leaf_economics_proxy", NAN)),
		"structural_investment": float(ext.get("structural_investment", NAN)),
		"root_depth_m": float(genome.get("root_depth_m", NAN)),
		"root_spread_m": float(ext.get("root_spread_m", NAN)),
		"root_shoot_ratio": float(ext.get("root_shoot_ratio", NAN)),
	}
	var topology := {
		"max_height_m": float(realized.get("max_height_m", NAN)),
		"internode_length_m": float(realized.get("internode_length_m", NAN)),
		"apical_dominance": float(realized.get("apical_dominance", NAN)),
		"branch_probability": float(realized.get("branch_probability", NAN)),
		"branch_angle_deg": float(realized.get("branch_angle_deg", NAN)),
		"branch_length_ratio": float(realized.get("branch_length_ratio", NAN)),
		"branching_depth": int(realized.get("branching_depth", -1)),
		"crown_spread_m": float(realized.get("crown_spread_m", NAN)),
	}
	var functional := {
		"realized_height_m": float(functional_phenotype.get("realized_height_m", NAN)),
		"realized_crown_radius_m": float(functional_phenotype.get("realized_crown_radius_m", NAN)),
		"realized_crown_density": float(functional_phenotype.get("realized_crown_density", NAN)),
		"leaf_area_index_proxy": float(functional_phenotype.get("leaf_area_index_proxy", NAN)),
		"leaf_size_proxy": float(functional_phenotype.get("leaf_size_proxy", NAN)),
		"leaf_conservative_strategy": float(functional_phenotype.get("leaf_conservative_strategy", NAN)),
		"structural_investment": float(functional_phenotype.get("structural_investment", NAN)),
		"realized_root_depth_m": float(functional_phenotype.get("realized_root_depth_m", NAN)),
		"realized_root_spread_m": float(functional_phenotype.get("realized_root_spread_m", NAN)),
		"root_shoot_ratio": float(functional_phenotype.get("root_shoot_ratio", NAN)),
	}

	var evidence := {
		"record_id": record_id,
		"cell_index": cell_index,
		"bundle_checksum": bundle_checksum,
		"lineage_id": lineage_id,
		"hereditary_individual_seed": hereditary_individual_seed,
		"development_individual_seed": development_individual_seed,
		"source_phenotype_hash": phenotype_hash,
		"source_plasticity_phenotype_hash": plasticity_hash,
		"source_growth_graph_hash": growth_graph_hash,
		"source_inherited_traits_hash": inherited_hash,
		"source_realized_traits_hash": realized_hash,
		"source_extension_traits_hash": extension_hash,
		"potential_morphology": potential,
		"realized_topology": topology,
		"functional_morphology": functional,
	}
	evidence["evidence_hash"] = record_hash(evidence)
	return evidence if validate_record(evidence) else {}

static func seal_snapshot(
	records: Array,
	generation: int,
	precompetition_population_hash: String,
	competition_hash: String,
	postcompetition_population_hash: String,
	expected_record_count: int = -1
) -> Dictionary:
	if generation < 1:
		return {}
	for hash_value in [precompetition_population_hash, competition_hash, postcompetition_population_hash]:
		if hash_value.length() != 64:
			return {}
	if expected_record_count < -1:
		return {}
	if expected_record_count >= 0 and records.size() != expected_record_count:
		return {}
	var ordered: Array[Dictionary] = []
	for value in records:
		if not value is Dictionary or not validate_record(value):
			return {}
		ordered.append(Dictionary(value).duplicate(true))
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["record_id"]) < String(b["record_id"])
	)
	var snapshot := {
		"schema": SCHEMA + ".snapshot",
		"version": VERSION,
		"revision": REVISION,
		"derived_representation": DERIVED_REPRESENTATION,
		"presentation_only": PRESENTATION_ONLY,
		"generation": generation,
		"source_precompetition_population_hash": precompetition_population_hash,
		"source_competition_hash": competition_hash,
		"source_postcompetition_population_hash": postcompetition_population_hash,
		"record_count": ordered.size(),
		"records": ordered,
	}
	snapshot["evidence_hash"] = snapshot_hash(snapshot)
	return snapshot if validate_snapshot(snapshot) else {}

static func validate_record(evidence: Dictionary) -> bool:
	if not _exact_keys(evidence, RECORD_FIELDS):
		return false
	if String(evidence.get("record_id", "")).is_empty() or int(evidence.get("cell_index", -1)) < 0 or int(evidence.get("cell_index", -1)) >= 1024:
		return false
	if String(evidence.get("bundle_checksum", "")).length() != 64 or String(evidence.get("lineage_id", "")).is_empty():
		return false
	if int(evidence.get("hereditary_individual_seed", -1)) < 0 or int(evidence.get("development_individual_seed", -1)) < 0:
		return false
	for key in [
		"source_phenotype_hash", "source_plasticity_phenotype_hash", "source_growth_graph_hash",
		"source_inherited_traits_hash", "source_realized_traits_hash", "source_extension_traits_hash",
	]:
		if String(evidence.get(key, "")).length() != 64:
			return false
	var potential_value = evidence.get("potential_morphology")
	var topology_value = evidence.get("realized_topology")
	var functional_value = evidence.get("functional_morphology")
	if not potential_value is Dictionary or not topology_value is Dictionary or not functional_value is Dictionary:
		return false
	if not _validate_numeric_map(potential_value, POTENTIAL_FIELDS, ["branching_depth"]):
		return false
	if not _validate_numeric_map(topology_value, REALIZED_TOPOLOGY_FIELDS, ["branching_depth"]):
		return false
	if not _validate_numeric_map(functional_value, FUNCTIONAL_FIELDS, []):
		return false
	if int(Dictionary(potential_value).get("branching_depth", -1)) < 1 or int(Dictionary(topology_value).get("branching_depth", -1)) < 1:
		return false
	if float(Dictionary(functional_value).get("realized_height_m", -1.0)) < 0.0:
		return false
	if float(Dictionary(functional_value).get("realized_crown_radius_m", -1.0)) < 0.0:
		return false
	if float(Dictionary(functional_value).get("realized_crown_density", -1.0)) < 0.0 or float(Dictionary(functional_value).get("realized_crown_density", 2.0)) > 1.0:
		return false
	if float(Dictionary(functional_value).get("root_shoot_ratio", -1.0)) < 0.0 or float(Dictionary(functional_value).get("root_shoot_ratio", 2.0)) > 1.0:
		return false
	return String(evidence.get("evidence_hash", "")) == record_hash(evidence)

static func validate_snapshot(snapshot: Dictionary) -> bool:
	if not _exact_keys(snapshot, SNAPSHOT_FIELDS):
		return false
	if String(snapshot.get("schema", "")) != SCHEMA + ".snapshot":
		return false
	if String(snapshot.get("version", "")) != VERSION or String(snapshot.get("revision", "")) != REVISION:
		return false
	if not bool(snapshot.get("derived_representation", false)) or not bool(snapshot.get("presentation_only", false)):
		return false
	if int(snapshot.get("generation", -1)) < 1:
		return false
	for key in ["source_precompetition_population_hash", "source_competition_hash", "source_postcompetition_population_hash"]:
		if String(snapshot.get(key, "")).length() != 64:
			return false
	var records_value = snapshot.get("records")
	if not records_value is Array:
		return false
	var records: Array = records_value
	if int(snapshot.get("record_count", -1)) != records.size():
		return false
	var previous_id := ""
	for value in records:
		if not value is Dictionary or not validate_record(value):
			return false
		var record_id := String(Dictionary(value).get("record_id", ""))
		if not previous_id.is_empty() and record_id <= previous_id:
			return false
		previous_id = record_id
	return String(snapshot.get("evidence_hash", "")) == snapshot_hash(snapshot)

static func record_hash(evidence: Dictionary) -> String:
	var potential: Dictionary = evidence.get("potential_morphology", {})
	var topology: Dictionary = evidence.get("realized_topology", {})
	var functional: Dictionary = evidence.get("functional_morphology", {})
	var tokens := PackedStringArray([
		SCHEMA, VERSION, REVISION, "record",
		String(evidence.get("record_id", "")),
		str(int(evidence.get("cell_index", -1))),
		String(evidence.get("bundle_checksum", "")),
		String(evidence.get("lineage_id", "")),
		str(int(evidence.get("hereditary_individual_seed", -1))),
		str(int(evidence.get("development_individual_seed", -1))),
		String(evidence.get("source_phenotype_hash", "")),
		String(evidence.get("source_plasticity_phenotype_hash", "")),
		String(evidence.get("source_growth_graph_hash", "")),
		String(evidence.get("source_inherited_traits_hash", "")),
		String(evidence.get("source_realized_traits_hash", "")),
		String(evidence.get("source_extension_traits_hash", "")),
	])
	for key in POTENTIAL_FIELDS:
		tokens.append("P:%s=%s" % [key, _number_token(potential.get(key), key == "branching_depth")])
	for key in REALIZED_TOPOLOGY_FIELDS:
		tokens.append("R:%s=%s" % [key, _number_token(topology.get(key), key == "branching_depth")])
	for key in FUNCTIONAL_FIELDS:
		tokens.append("F:%s=%s" % [key, _number_token(functional.get(key), false)])
	return "|".join(tokens).sha256_text()

static func snapshot_hash(snapshot: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA, VERSION, REVISION, "snapshot",
		str(int(snapshot.get("generation", -1))),
		String(snapshot.get("source_precompetition_population_hash", "")),
		String(snapshot.get("source_competition_hash", "")),
		String(snapshot.get("source_postcompetition_population_hash", "")),
		str(int(snapshot.get("record_count", -1))),
	])
	for value in Array(snapshot.get("records", [])):
		if value is Dictionary:
			tokens.append(String(Dictionary(value).get("evidence_hash", "")))
	return "|".join(tokens).sha256_text()

static func _validate_numeric_map(value, fields: Array[String], integer_fields: Array[String]) -> bool:
	if not value is Dictionary or not _exact_keys(value, fields):
		return false
	var data: Dictionary = value
	for key in fields:
		if key in integer_fields:
			if typeof(data.get(key)) != TYPE_INT:
				return false
		else:
			var raw = data.get(key)
			if typeof(raw) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(raw)):
				return false
	return true

static func _exact_keys(value: Dictionary, fields: Array[String]) -> bool:
	if value.keys().size() != fields.size():
		return false
	for key in fields:
		if not value.has(key):
			return false
	return true

static func _number_token(value, integer_value: bool) -> String:
	return str(int(value)) if integer_value else "%.9f" % float(value)
