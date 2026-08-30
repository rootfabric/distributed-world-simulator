extends RefCounted

## ECO.EVO7 VIS4.3 — exact GrowthGraph reconstruction evidence.
##
## Packages already-computed PH2 realized development traits and source graph
## identity into a separate derived/presentation-only sidecar. It does not
## realize development, rebuild a graph, evaluate fitness, or mutate ecology.

const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.plant_growth_graph_reconstruction_evidence.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-VIS4.3.R1"
const DERIVED_REPRESENTATION := true
const PRESENTATION_ONLY := true

const RECORD_FIELDS: Array[String] = [
	"record_id", "cell_index", "bundle_checksum", "lineage_id",
	"hereditary_individual_seed", "development_individual_seed",
	"realized_development_traits", "source_realized_traits_hash",
	"source_growth_graph_hash", "reconstruction_evidence_hash",
]

const SNAPSHOT_FIELDS: Array[String] = [
	"schema", "version", "revision", "derived_representation", "presentation_only",
	"generation", "source_precompetition_population_hash", "source_competition_hash",
	"source_postcompetition_population_hash", "record_count", "records", "evidence_hash",
]

static func build_record(record: Dictionary, ph2: Dictionary) -> Dictionary:
	if record.is_empty() or ph2.is_empty():
		return {}
	var bundle_value = record.get("hereditary_bundle")
	var realized_value = ph2.get("realized_development_traits")
	var graph_value = ph2.get("growth_graph")
	if not bundle_value is Dictionary or not realized_value is Dictionary or not graph_value is Dictionary:
		return {}
	var bundle: Dictionary = bundle_value
	var realized: Dictionary = realized_value
	var graph: Dictionary = graph_value
	var lineage_value = bundle.get("lineage", bundle.get("lineage_record"))
	if not lineage_value is Dictionary:
		return {}
	var lineage: Dictionary = lineage_value

	var record_id := String(record.get("record_id", ""))
	var cell_index := int(record.get("cell_index", -1))
	var bundle_checksum := String(record.get("bundle_checksum", ""))
	var lineage_id := String(lineage.get("lineage_id", ""))
	var hereditary_seed := int(bundle.get("individual_seed", -1))
	var development_seed := int(ph2.get("individual_seed", -1))
	if record_id.is_empty() or cell_index < 0 or cell_index >= 1024:
		return {}
	if bundle_checksum.length() != 64 or bundle_checksum != String(bundle.get("bundle_checksum", "")):
		return {}
	if lineage_id.is_empty() or hereditary_seed < 0 or development_seed < 0:
		return {}
	if not bool(Traits.validate(realized).get("success", false)):
		return {}

	var realized_hash := String(realized.get("checksum", ""))
	var graph_hash := String(graph.get("graph_hash", ""))
	if realized_hash.length() != 64 or graph_hash.length() != 64:
		return {}
	if int(graph.get("individual_seed", -1)) != development_seed:
		return {}
	if String(graph.get("development_traits_checksum", "")) != realized_hash:
		return {}
	if String(graph.get("traits_id", "")) != String(realized.get("traits_id", "")):
		return {}

	var evidence := {
		"record_id": record_id,
		"cell_index": cell_index,
		"bundle_checksum": bundle_checksum,
		"lineage_id": lineage_id,
		"hereditary_individual_seed": hereditary_seed,
		"development_individual_seed": development_seed,
		"realized_development_traits": realized.duplicate(true),
		"source_realized_traits_hash": realized_hash,
		"source_growth_graph_hash": graph_hash,
	}
	evidence["reconstruction_evidence_hash"] = record_hash(evidence)
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
		if String(hash_value).length() != 64:
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
	var realized_value = evidence.get("realized_development_traits")
	if not realized_value is Dictionary:
		return false
	var realized: Dictionary = realized_value
	if not bool(Traits.validate(realized).get("success", false)):
		return false
	if String(evidence.get("source_realized_traits_hash", "")) != String(realized.get("checksum", "")):
		return false
	if String(evidence.get("source_realized_traits_hash", "")).length() != 64 or String(evidence.get("source_growth_graph_hash", "")).length() != 64:
		return false
	return String(evidence.get("reconstruction_evidence_hash", "")) == record_hash(evidence)

static func validate_snapshot(snapshot: Dictionary) -> bool:
	if not _exact_keys(snapshot, SNAPSHOT_FIELDS):
		return false
	if String(snapshot.get("schema", "")) != SCHEMA + ".snapshot" or String(snapshot.get("version", "")) != VERSION or String(snapshot.get("revision", "")) != REVISION:
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
	var realized: Dictionary = evidence.get("realized_development_traits", {})
	return "|".join(PackedStringArray([
		SCHEMA, VERSION, REVISION, "record",
		String(evidence.get("record_id", "")),
		str(int(evidence.get("cell_index", -1))),
		String(evidence.get("bundle_checksum", "")),
		String(evidence.get("lineage_id", "")),
		str(int(evidence.get("hereditary_individual_seed", -1))),
		str(int(evidence.get("development_individual_seed", -1))),
		_traits_token(realized),
		String(evidence.get("source_realized_traits_hash", "")),
		String(evidence.get("source_growth_graph_hash", "")),
	])).sha256_text()

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
			tokens.append(String(Dictionary(value).get("reconstruction_evidence_hash", "")))
	return "|".join(tokens).sha256_text()

static func _traits_token(traits: Dictionary) -> String:
	return "|".join(PackedStringArray([
		String(traits.get("schema", "")),
		String(traits.get("version", "")),
		String(traits.get("traits_id", "")),
		_f(float(traits.get("max_height_m", 0.0))),
		_f(float(traits.get("internode_length_m", 0.0))),
		_f(float(traits.get("apical_dominance", 0.0))),
		_f(float(traits.get("branch_probability", 0.0))),
		_f(float(traits.get("branch_angle_deg", 0.0))),
		_f(float(traits.get("branch_length_ratio", 0.0))),
		str(int(traits.get("branching_depth", 0))),
		_f(float(traits.get("crown_spread_m", 0.0))),
		String(traits.get("checksum", "")),
	]))

static func _exact_keys(value: Dictionary, expected: Array[String]) -> bool:
	if value.keys().size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true

static func _f(value: float) -> String:
	return "%.9f" % value
