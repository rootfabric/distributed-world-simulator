extends RefCounted

## ECO.EVO7 VIS2 read-only adapter.
## Consumes the accepted Workbench ecology snapshot and translates already-materialized
## LS3.4 competition evidence into immutable renderer descriptors. It owns no biology.

const SCHEMA := "distributed_world_simulator.ecology.evo7_vis2_phenotype_render_adapter.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-VIS2.1"
const FOUNDER_EVIDENCE := "FOUNDER_RECORD_ONLY"
const PHENOTYPE_EVIDENCE := "LS3.4_COMPETITION_PHENOTYPE"

const RESULT_FIELDS: Array[String] = [
    "schema", "version", "revision", "generation", "source_ecology_state_hash",
    "descriptor_count", "phenotype_evidence_count", "founder_marker_count",
    "descriptors", "adapter_hash",
]
const DESCRIPTOR_FIELDS: Array[String] = [
    "record_id", "cell_index", "bundle_checksum", "lineage_id", "evidence_level",
    "phenotype_hash", "realized_height_m", "leaf_area_index_proxy",
    "realized_root_depth_m", "realized_root_spread_m", "root_shoot_ratio",
    "water_satisfaction", "effective_light", "realized_resource_balance",
    "descriptor_hash",
]

func build(ecology_snapshot: Dictionary) -> Dictionary:
    if ecology_snapshot.is_empty():
        return {}
    var generation := int(ecology_snapshot.get("generation", -1))
    var source_hash := String(ecology_snapshot.get("state_hash", ""))
    var records_value = ecology_snapshot.get("records")
    if generation < 0 or source_hash.length() != 64 or not records_value is Array:
        return {}
    var records: Array = records_value
    if int(ecology_snapshot.get("record_count", -1)) != records.size():
        return {}

    var evaluations_by_record := {}
    if generation > 0:
        var field_value = ecology_snapshot.get("competition_field")
        if not field_value is Dictionary:
            return {}
        var field: Dictionary = field_value
        var evaluations_value = field.get("evaluations")
        if not evaluations_value is Array:
            return {}
        for value in Array(evaluations_value):
            if not value is Dictionary:
                return {}
            var evaluation: Dictionary = value
            var record_id := String(evaluation.get("record_id", ""))
            if record_id.is_empty() or evaluations_by_record.has(record_id):
                return {}
            evaluations_by_record[record_id] = evaluation

    var descriptors: Array[Dictionary] = []
    var phenotype_count := 0
    var founder_count := 0
    for value in records:
        if not value is Dictionary:
            return {}
        var record: Dictionary = value
        var descriptor := _descriptor_for_record(record, generation, evaluations_by_record)
        if descriptor.is_empty():
            return {}
        if String(descriptor["evidence_level"]) == PHENOTYPE_EVIDENCE:
            phenotype_count += 1
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
        "source_ecology_state_hash": source_hash,
        "descriptor_count": descriptors.size(),
        "phenotype_evidence_count": phenotype_count,
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
    if int(result.get("generation", -1)) < 0 or String(result.get("source_ecology_state_hash", "")).length() != 64:
        return false
    var descriptors_value = result.get("descriptors")
    if not descriptors_value is Array:
        return false
    var descriptors: Array = descriptors_value
    if int(result.get("descriptor_count", -1)) != descriptors.size():
        return false
    var phenotype_count := 0
    var founder_count := 0
    var previous_id := ""
    for value in descriptors:
        if not value is Dictionary:
            return false
        var descriptor: Dictionary = value
        if not _validate_descriptor(descriptor, int(result["generation"])):
            return false
        var record_id := String(descriptor["record_id"])
        if not previous_id.is_empty() and record_id <= previous_id:
            return false
        previous_id = record_id
        if String(descriptor["evidence_level"]) == PHENOTYPE_EVIDENCE:
            phenotype_count += 1
        else:
            founder_count += 1
    if phenotype_count != int(result.get("phenotype_evidence_count", -1)) or founder_count != int(result.get("founder_marker_count", -1)):
        return false
    if int(result["generation"]) == 0 and phenotype_count != 0:
        return false
    if int(result["generation"]) > 0 and founder_count != 0:
        return false
    return String(result.get("adapter_hash", "")) == _adapter_hash(result)

func _descriptor_for_record(record: Dictionary, generation: int, evaluations_by_record: Dictionary) -> Dictionary:
    var record_id := String(record.get("record_id", ""))
    var bundle_checksum := String(record.get("bundle_checksum", ""))
    var cell_index := int(record.get("cell_index", -1))
    var lineage_id := _lineage_id(record)
    if record_id.is_empty() or bundle_checksum.length() != 64 or cell_index < 0 or cell_index >= 1024 or lineage_id.is_empty():
        return {}

    var descriptor := {
        "record_id": record_id,
        "cell_index": cell_index,
        "bundle_checksum": bundle_checksum,
        "lineage_id": lineage_id,
        "evidence_level": FOUNDER_EVIDENCE,
        "phenotype_hash": "",
        "realized_height_m": 0.0,
        "leaf_area_index_proxy": 0.0,
        "realized_root_depth_m": 0.0,
        "realized_root_spread_m": 0.0,
        "root_shoot_ratio": 0.0,
        "water_satisfaction": 1.0,
        "effective_light": 1.0,
        "realized_resource_balance": 0.0,
    }
    if generation > 0:
        if not evaluations_by_record.has(record_id):
            return {}
        var evaluation: Dictionary = evaluations_by_record[record_id]
        if int(evaluation.get("cell_index", -1)) != cell_index or String(evaluation.get("bundle_checksum", "")) != bundle_checksum:
            return {}
        if not bool(evaluation.get("survives", false)):
            return {}
        descriptor["evidence_level"] = PHENOTYPE_EVIDENCE
        descriptor["phenotype_hash"] = String(evaluation.get("phenotype_hash", ""))
        descriptor["realized_height_m"] = float(evaluation.get("realized_height_m", NAN))
        descriptor["leaf_area_index_proxy"] = float(evaluation.get("leaf_area_index_proxy", NAN))
        descriptor["realized_root_depth_m"] = float(evaluation.get("realized_root_depth_m", NAN))
        descriptor["realized_root_spread_m"] = float(evaluation.get("realized_root_spread_m", NAN))
        descriptor["root_shoot_ratio"] = float(evaluation.get("root_shoot_ratio", NAN))
        descriptor["water_satisfaction"] = float(evaluation.get("water_satisfaction", NAN))
        descriptor["effective_light"] = float(evaluation.get("effective_light", NAN))
        descriptor["realized_resource_balance"] = float(evaluation.get("realized_resource_balance", NAN))
    descriptor["descriptor_hash"] = _descriptor_hash(descriptor)
    return descriptor if _validate_descriptor(descriptor, generation) else {}

func _validate_descriptor(descriptor: Dictionary, generation: int) -> bool:
    if not _exact_keys(descriptor, DESCRIPTOR_FIELDS):
        return false
    if String(descriptor.get("record_id", "")).is_empty() or String(descriptor.get("bundle_checksum", "")).length() != 64 or String(descriptor.get("lineage_id", "")).is_empty():
        return false
    if int(descriptor.get("cell_index", -1)) < 0 or int(descriptor.get("cell_index", -1)) >= 1024:
        return false
    var evidence := String(descriptor.get("evidence_level", ""))
    if generation == 0:
        if evidence != FOUNDER_EVIDENCE or not String(descriptor.get("phenotype_hash", "")).is_empty():
            return false
    else:
        if evidence != PHENOTYPE_EVIDENCE or String(descriptor.get("phenotype_hash", "")).length() != 64:
            return false
    for metric in ["realized_height_m", "leaf_area_index_proxy", "realized_root_depth_m", "realized_root_spread_m", "root_shoot_ratio", "water_satisfaction", "effective_light", "realized_resource_balance"]:
        if not is_finite(float(descriptor.get(metric, NAN))):
            return false
    if float(descriptor["realized_height_m"]) < 0.0 or float(descriptor["leaf_area_index_proxy"]) < 0.0 or float(descriptor["realized_root_depth_m"]) < 0.0 or float(descriptor["realized_root_spread_m"]) < 0.0:
        return false
    if float(descriptor["root_shoot_ratio"]) < 0.0 or float(descriptor["water_satisfaction"]) < 0.0 or float(descriptor["water_satisfaction"]) > 1.0 or float(descriptor["effective_light"]) < 0.0 or float(descriptor["effective_light"]) > 1.0:
        return false
    return String(descriptor.get("descriptor_hash", "")) == _descriptor_hash(descriptor)

func _lineage_id(record: Dictionary) -> String:
    var bundle_value = record.get("hereditary_bundle")
    if not bundle_value is Dictionary:
        return ""
    var lineage_value = Dictionary(bundle_value).get("lineage", Dictionary(bundle_value).get("lineage_record"))
    if not lineage_value is Dictionary:
        return ""
    return String(Dictionary(lineage_value).get("lineage_id", ""))

func _descriptor_hash(descriptor: Dictionary) -> String:
    return "|".join(PackedStringArray([
        SCHEMA, VERSION, REVISION,
        String(descriptor.get("record_id", "")), str(int(descriptor.get("cell_index", -1))),
        String(descriptor.get("bundle_checksum", "")), String(descriptor.get("lineage_id", "")),
        String(descriptor.get("evidence_level", "")), String(descriptor.get("phenotype_hash", "")),
        _f(float(descriptor.get("realized_height_m", 0.0))), _f(float(descriptor.get("leaf_area_index_proxy", 0.0))),
        _f(float(descriptor.get("realized_root_depth_m", 0.0))), _f(float(descriptor.get("realized_root_spread_m", 0.0))),
        _f(float(descriptor.get("root_shoot_ratio", 0.0))), _f(float(descriptor.get("water_satisfaction", 0.0))),
        _f(float(descriptor.get("effective_light", 0.0))), _f(float(descriptor.get("realized_resource_balance", 0.0))),
    ])).sha256_text()

func _adapter_hash(result: Dictionary) -> String:
    var tokens := PackedStringArray([
        SCHEMA, VERSION, REVISION, str(int(result.get("generation", -1))),
        String(result.get("source_ecology_state_hash", "")), str(int(result.get("descriptor_count", -1))),
        str(int(result.get("phenotype_evidence_count", -1))), str(int(result.get("founder_marker_count", -1))),
    ])
    for value in Array(result.get("descriptors", [])):
        if value is Dictionary:
            tokens.append(String(Dictionary(value).get("descriptor_hash", "")))
    return "|".join(tokens).sha256_text()

func _exact_keys(value: Dictionary, expected: Array[String]) -> bool:
    if value.keys().size() != expected.size():
        return false
    for key in expected:
        if not value.has(key):
            return false
    return true

func _f(value: float) -> String:
    return "%.9f" % value
