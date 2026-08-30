extends RefCounted

## ECO.EVO7 VIS4.1 — read-only morphology descriptor V2.
##
## Consumes only the canonical ecology snapshot plus the separately sealed
## morphology-evidence sidecar. It never calls development, phenotype,
## competition, mutation, persistence or network implementations.

const MorphologyEvidence = preload("res://scripts/research/ecology/plant_morphology_evidence_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_vis4_morphology_render_adapter.v2"
const VERSION := "2.0.0"
const REVISION := "ECO.EVO7-VIS4.1.R1"
const FOUNDER_EVIDENCE := "FOUNDER_RECORD_ONLY"
const MORPHOLOGY_EVIDENCE := "LS3.4_SOURCE_BOUND_MORPHOLOGY"

const RESULT_FIELDS: Array[String] = [
	"schema", "version", "revision", "generation", "source_ecology_state_hash",
	"source_competition_hash", "source_morphology_evidence_hash",
	"descriptor_count", "morphology_evidence_count", "founder_marker_count",
	"descriptors", "adapter_hash",
]
const DESCRIPTOR_FIELDS: Array[String] = [
	"record_id", "cell_index", "bundle_checksum", "lineage_id", "individual_seed",
	"evidence_level", "phenotype_hash", "plasticity_phenotype_hash", "growth_graph_hash",
	"source_evidence_record_hash", "source_evaluation_hash",
	"potential_morphology", "realized_topology", "functional_morphology",
	"competition_context", "descriptor_hash",
]
const COMPETITION_FIELDS: Array[String] = [
	"water_satisfaction", "effective_light", "realized_resource_balance",
]

func build(ecology_snapshot: Dictionary, morphology_snapshot: Dictionary = {}) -> Dictionary:
	if ecology_snapshot.is_empty():
		return {}
	var generation := int(ecology_snapshot.get("generation", -1))
	var source_state_hash := String(ecology_snapshot.get("state_hash", ""))
	var records_value = ecology_snapshot.get("records")
	if generation < 0 or source_state_hash.length() != 64 or not records_value is Array:
		return {}
	var records: Array = records_value
	if int(ecology_snapshot.get("record_count", -1)) != records.size():
		return {}

	var evidence_by_id := {}
	var evaluations_by_id := {}
	var source_competition_hash := ""
	var source_morphology_hash := ""
	if generation == 0:
		if not morphology_snapshot.is_empty():
			return {}
	else:
		if not MorphologyEvidence.validate_snapshot(morphology_snapshot):
			return {}
		if int(morphology_snapshot.get("generation", -1)) != generation:
			return {}
		if String(morphology_snapshot.get("source_precompetition_population_hash", "")) != String(ecology_snapshot.get("precompetition_population_hash", "")):
			return {}
		if String(morphology_snapshot.get("source_competition_hash", "")) != String(ecology_snapshot.get("competition_hash", "")):
			return {}
		if String(morphology_snapshot.get("source_postcompetition_population_hash", "")) != String(ecology_snapshot.get("postcompetition_population_hash", "")):
			return {}
		if int(morphology_snapshot.get("record_count", -1)) != records.size():
			return {}
		source_competition_hash = String(ecology_snapshot.get("competition_hash", ""))
		source_morphology_hash = String(morphology_snapshot.get("evidence_hash", ""))
		for value in Array(morphology_snapshot.get("records", [])):
			if not value is Dictionary:
				return {}
			var evidence: Dictionary = value
			var record_id := String(evidence.get("record_id", ""))
			if record_id.is_empty() or evidence_by_id.has(record_id):
				return {}
			evidence_by_id[record_id] = evidence
		var field_value = ecology_snapshot.get("competition_field")
		if not field_value is Dictionary:
			return {}
		for value in Array(Dictionary(field_value).get("evaluations", [])):
			if not value is Dictionary:
				return {}
			var evaluation: Dictionary = value
			var record_id := String(evaluation.get("record_id", ""))
			if record_id.is_empty() or evaluations_by_id.has(record_id):
				return {}
			evaluations_by_id[record_id] = evaluation

	var descriptors: Array[Dictionary] = []
	var evidence_count := 0
	var founder_count := 0
	for value in records:
		if not value is Dictionary:
			return {}
		var record: Dictionary = value
		var descriptor := (
			_founder_descriptor(record)
			if generation == 0
			else _evidence_descriptor(record, evidence_by_id, evaluations_by_id)
		)
		if descriptor.is_empty():
			return {}
		if String(descriptor["evidence_level"]) == MORPHOLOGY_EVIDENCE:
			evidence_count += 1
		else:
			founder_count += 1
		descriptors.append(descriptor)
	descriptors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["record_id"]) < String(b["record_id"])
	)

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"generation": generation,
		"source_ecology_state_hash": source_state_hash,
		"source_competition_hash": source_competition_hash,
		"source_morphology_evidence_hash": source_morphology_hash,
		"descriptor_count": descriptors.size(),
		"morphology_evidence_count": evidence_count,
		"founder_marker_count": founder_count,
		"descriptors": descriptors,
	}
	result["adapter_hash"] = _adapter_hash(result)
	return result if validate_result(result) else {}

func validate_result(result: Dictionary) -> bool:
	if not _exact_keys(result, RESULT_FIELDS):
		return false
	if String(result.get("schema", "")) != SCHEMA or String(result.get("version", "")) != VERSION or String(result.get("revision", "")) != REVISION:
		return false
	var generation := int(result.get("generation", -1))
	if generation < 0 or String(result.get("source_ecology_state_hash", "")).length() != 64:
		return false
	if generation == 0:
		if not String(result.get("source_competition_hash", "")).is_empty() or not String(result.get("source_morphology_evidence_hash", "")).is_empty():
			return false
	else:
		if String(result.get("source_competition_hash", "")).length() != 64 or String(result.get("source_morphology_evidence_hash", "")).length() != 64:
			return false
	var descriptors_value = result.get("descriptors")
	if not descriptors_value is Array:
		return false
	var descriptors: Array = descriptors_value
	if int(result.get("descriptor_count", -1)) != descriptors.size():
		return false
	var evidence_count := 0
	var founder_count := 0
	var previous_id := ""
	for value in descriptors:
		if not value is Dictionary:
			return false
		var descriptor: Dictionary = value
		if not _validate_descriptor(descriptor, generation):
			return false
		var record_id := String(descriptor["record_id"])
		if not previous_id.is_empty() and record_id <= previous_id:
			return false
		previous_id = record_id
		if String(descriptor["evidence_level"]) == MORPHOLOGY_EVIDENCE:
			evidence_count += 1
		else:
			founder_count += 1
	if evidence_count != int(result.get("morphology_evidence_count", -1)) or founder_count != int(result.get("founder_marker_count", -1)):
		return false
	if generation == 0 and evidence_count != 0:
		return false
	if generation > 0 and founder_count != 0:
		return false
	return String(result.get("adapter_hash", "")) == _adapter_hash(result)

func _founder_descriptor(record: Dictionary) -> Dictionary:
	var identity := _record_identity(record)
	if identity.is_empty():
		return {}
	var potential := _potential_from_record(record)
	if potential.is_empty():
		return {}
	var descriptor := {
		"record_id": String(record["record_id"]),
		"cell_index": int(record["cell_index"]),
		"bundle_checksum": String(record["bundle_checksum"]),
		"lineage_id": String(identity["lineage_id"]),
		"individual_seed": int(identity["individual_seed"]),
		"evidence_level": FOUNDER_EVIDENCE,
		"phenotype_hash": "",
		"plasticity_phenotype_hash": "",
		"growth_graph_hash": "",
		"source_evidence_record_hash": "",
		"source_evaluation_hash": "",
		"potential_morphology": potential,
		"realized_topology": {},
		"functional_morphology": {},
		"competition_context": {},
	}
	descriptor["descriptor_hash"] = _descriptor_hash(descriptor)
	return descriptor if _validate_descriptor(descriptor, 0) else {}

func _evidence_descriptor(record: Dictionary, evidence_by_id: Dictionary, evaluations_by_id: Dictionary) -> Dictionary:
	var record_id := String(record.get("record_id", ""))
	if record_id.is_empty() or not evidence_by_id.has(record_id) or not evaluations_by_id.has(record_id):
		return {}
	var evidence: Dictionary = evidence_by_id[record_id]
	var evaluation: Dictionary = evaluations_by_id[record_id]
	if not MorphologyEvidence.validate_record(evidence):
		return {}
	if not bool(evaluation.get("survives", false)):
		return {}
	if int(evidence.get("cell_index", -1)) != int(record.get("cell_index", -2)) or int(evaluation.get("cell_index", -1)) != int(record.get("cell_index", -2)):
		return {}
	if String(evidence.get("bundle_checksum", "")) != String(record.get("bundle_checksum", "")) or String(evaluation.get("bundle_checksum", "")) != String(record.get("bundle_checksum", "")):
		return {}
	if String(evidence.get("source_phenotype_hash", "")) != String(evaluation.get("phenotype_hash", "")):
		return {}
	var evaluation_hash := String(evaluation.get("evaluation_hash", ""))
	if evaluation_hash.length() != 64:
		return {}
	var context := {
		"water_satisfaction": float(evaluation.get("water_satisfaction", NAN)),
		"effective_light": float(evaluation.get("effective_light", NAN)),
		"realized_resource_balance": float(evaluation.get("realized_resource_balance", NAN)),
	}
	var descriptor := {
		"record_id": record_id,
		"cell_index": int(record["cell_index"]),
		"bundle_checksum": String(record["bundle_checksum"]),
		"lineage_id": String(evidence["lineage_id"]),
		"individual_seed": int(evidence["individual_seed"]),
		"evidence_level": MORPHOLOGY_EVIDENCE,
		"phenotype_hash": String(evidence["source_phenotype_hash"]),
		"plasticity_phenotype_hash": String(evidence["source_plasticity_phenotype_hash"]),
		"growth_graph_hash": String(evidence["source_growth_graph_hash"]),
		"source_evidence_record_hash": String(evidence["evidence_hash"]),
		"source_evaluation_hash": evaluation_hash,
		"potential_morphology": Dictionary(evidence["potential_morphology"]).duplicate(true),
		"realized_topology": Dictionary(evidence["realized_topology"]).duplicate(true),
		"functional_morphology": Dictionary(evidence["functional_morphology"]).duplicate(true),
		"competition_context": context,
	}
	descriptor["descriptor_hash"] = _descriptor_hash(descriptor)
	return descriptor if _validate_descriptor(descriptor, 1) else {}

func _record_identity(record: Dictionary) -> Dictionary:
	var bundle_value = record.get("hereditary_bundle")
	if not bundle_value is Dictionary:
		return {}
	var bundle: Dictionary = bundle_value
	if String(record.get("bundle_checksum", "")) != String(bundle.get("bundle_checksum", "")):
		return {}
	var lineage_value = bundle.get("lineage", bundle.get("lineage_record"))
	if not lineage_value is Dictionary:
		return {}
	var lineage_id := String(Dictionary(lineage_value).get("lineage_id", ""))
	var individual_seed := int(bundle.get("individual_seed", -1))
	if lineage_id.is_empty() or individual_seed < 0:
		return {}
	return {"lineage_id": lineage_id, "individual_seed": individual_seed}

func _potential_from_record(record: Dictionary) -> Dictionary:
	var bundle_value = record.get("hereditary_bundle")
	if not bundle_value is Dictionary:
		return {}
	var bundle: Dictionary = bundle_value
	var dev_value = bundle.get("dev_traits")
	var ext_value = bundle.get("ext_traits")
	var genome_value = bundle.get("genome")
	if not dev_value is Dictionary or not ext_value is Dictionary or not genome_value is Dictionary:
		return {}
	var dev: Dictionary = dev_value
	var ext: Dictionary = ext_value
	var genome: Dictionary = genome_value
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
	return potential if _validate_map(potential, MorphologyEvidence.POTENTIAL_FIELDS, ["branching_depth"]) else {}

func _validate_descriptor(descriptor: Dictionary, generation: int) -> bool:
	if not _exact_keys(descriptor, DESCRIPTOR_FIELDS):
		return false
	if String(descriptor.get("record_id", "")).is_empty() or int(descriptor.get("cell_index", -1)) < 0 or int(descriptor.get("cell_index", -1)) >= 1024:
		return false
	if String(descriptor.get("bundle_checksum", "")).length() != 64 or String(descriptor.get("lineage_id", "")).is_empty() or int(descriptor.get("individual_seed", -1)) < 0:
		return false
	var potential_value = descriptor.get("potential_morphology")
	if not potential_value is Dictionary or not _validate_map(potential_value, MorphologyEvidence.POTENTIAL_FIELDS, ["branching_depth"]):
		return false
	var evidence_level := String(descriptor.get("evidence_level", ""))
	if generation == 0:
		if evidence_level != FOUNDER_EVIDENCE:
			return false
		for key in ["phenotype_hash", "plasticity_phenotype_hash", "growth_graph_hash", "source_evidence_record_hash", "source_evaluation_hash"]:
			if not String(descriptor.get(key, "")).is_empty():
				return false
		for key in ["realized_topology", "functional_morphology", "competition_context"]:
			if not descriptor.get(key, {}) is Dictionary or not Dictionary(descriptor.get(key, {})).is_empty():
				return false
	else:
		if evidence_level != MORPHOLOGY_EVIDENCE:
			return false
		for key in ["phenotype_hash", "plasticity_phenotype_hash", "growth_graph_hash", "source_evidence_record_hash", "source_evaluation_hash"]:
			if String(descriptor.get(key, "")).length() != 64:
				return false
		if not _validate_map(descriptor.get("realized_topology"), MorphologyEvidence.REALIZED_TOPOLOGY_FIELDS, ["branching_depth"]):
			return false
		if not _validate_map(descriptor.get("functional_morphology"), MorphologyEvidence.FUNCTIONAL_FIELDS, []):
			return false
		if not _validate_map(descriptor.get("competition_context"), COMPETITION_FIELDS, []):
			return false
		var context: Dictionary = descriptor["competition_context"]
		if float(context["water_satisfaction"]) < 0.0 or float(context["water_satisfaction"]) > 1.0:
			return false
		if float(context["effective_light"]) < 0.0 or float(context["effective_light"]) > 1.0:
			return false
	return String(descriptor.get("descriptor_hash", "")) == _descriptor_hash(descriptor)

func _validate_map(value, fields: Array[String], integer_fields: Array[String]) -> bool:
	if not value is Dictionary:
		return false
	var data: Dictionary = value
	if not _exact_keys(data, fields):
		return false
	for key in fields:
		if key in integer_fields:
			if typeof(data.get(key)) != TYPE_INT:
				return false
		else:
			var raw = data.get(key)
			if typeof(raw) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(raw)):
				return false
	return true

func _descriptor_hash(descriptor: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA, VERSION, REVISION,
		String(descriptor.get("record_id", "")),
		str(int(descriptor.get("cell_index", -1))),
		String(descriptor.get("bundle_checksum", "")),
		String(descriptor.get("lineage_id", "")),
		str(int(descriptor.get("individual_seed", -1))),
		String(descriptor.get("evidence_level", "")),
		String(descriptor.get("phenotype_hash", "")),
		String(descriptor.get("plasticity_phenotype_hash", "")),
		String(descriptor.get("growth_graph_hash", "")),
		String(descriptor.get("source_evidence_record_hash", "")),
		String(descriptor.get("source_evaluation_hash", "")),
	])
	_append_map(tokens, "P", descriptor.get("potential_morphology", {}), MorphologyEvidence.POTENTIAL_FIELDS, ["branching_depth"])
	_append_map(tokens, "R", descriptor.get("realized_topology", {}), MorphologyEvidence.REALIZED_TOPOLOGY_FIELDS, ["branching_depth"])
	_append_map(tokens, "F", descriptor.get("functional_morphology", {}), MorphologyEvidence.FUNCTIONAL_FIELDS, [])
	_append_map(tokens, "C", descriptor.get("competition_context", {}), COMPETITION_FIELDS, [])
	return "|".join(tokens).sha256_text()

func _adapter_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA, VERSION, REVISION, str(int(result.get("generation", -1))),
		String(result.get("source_ecology_state_hash", "")),
		String(result.get("source_competition_hash", "")),
		String(result.get("source_morphology_evidence_hash", "")),
		str(int(result.get("descriptor_count", -1))),
		str(int(result.get("morphology_evidence_count", -1))),
		str(int(result.get("founder_marker_count", -1))),
	])
	for value in Array(result.get("descriptors", [])):
		if value is Dictionary:
			tokens.append(String(Dictionary(value).get("descriptor_hash", "")))
	return "|".join(tokens).sha256_text()

func _append_map(tokens: PackedStringArray, prefix: String, value, fields: Array[String], integer_fields: Array[String]) -> void:
	if not value is Dictionary:
		tokens.append("%s:<empty>" % prefix)
		return
	var data: Dictionary = value
	if data.is_empty():
		tokens.append("%s:<empty>" % prefix)
		return
	for key in fields:
		var token := str(int(data.get(key, 0))) if key in integer_fields else "%.9f" % float(data.get(key, 0.0))
		tokens.append("%s:%s=%s" % [prefix, key, token])

func _exact_keys(value: Dictionary, expected: Array[String]) -> bool:
	if value.keys().size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true
