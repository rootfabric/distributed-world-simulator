extends RefCounted

const SCHEMA := "distributed_world_simulator.ecology.plant_lineage_record.v1"
const VERSION := "1.0.0"
const FIELD_NAMES: Array[String] = [
	"schema",
	"version",
	"lineage_id",
	"individual_id",
	"parent_individual_id",
	"generation",
	"birth_index",
	"mutation_seed",
	"parent_genome_checksum",
	"genome_checksum",
	"mutation_event_hash",
	"checksum",
]


static func create_ancestor(genome: Dictionary, lineage_seed: int) -> Dictionary:
	var genome_checksum := String(genome.get("checksum", ""))
	if not _is_lower_hex_64(genome_checksum):
		return {}
	var lineage_id := "eco-lineage/%s" % _identity_hash("lineage|%s|%d" % [genome_checksum, lineage_seed]).substr(0, 24)
	var individual_id := "eco-individual/%s" % _identity_hash("ancestor|%s|%d" % [lineage_id, lineage_seed]).substr(0, 24)
	var mutation_event_hash := "ancestor|%s|%d" % [genome_checksum, lineage_seed]
	mutation_event_hash = mutation_event_hash.sha256_text()
	return create(
		lineage_id,
		individual_id,
		"",
		0,
		0,
		lineage_seed,
		"",
		genome_checksum,
		mutation_event_hash
	)


static func create_descendant(
	parent_record: Dictionary,
	genome_checksum: String,
	birth_index: int,
	mutation_seed: int,
	mutation_event_hash: String
) -> Dictionary:
	if not bool(validate(parent_record).get("success", false)):
		return {}
	if not _is_lower_hex_64(genome_checksum) or not _is_lower_hex_64(mutation_event_hash) or birth_index < 0:
		return {}
	var generation := int(parent_record.get("generation", -1)) + 1
	var lineage_id := String(parent_record.get("lineage_id", ""))
	var parent_id := String(parent_record.get("individual_id", ""))
	var individual_key := "%s|%s|%d|%d|%d|%s|%s" % [
		lineage_id,
		parent_id,
		generation,
		birth_index,
		mutation_seed,
		genome_checksum,
		mutation_event_hash,
	]
	var individual_id := "eco-individual/%s" % _identity_hash(individual_key).substr(0, 24)
	return create(
		lineage_id,
		individual_id,
		parent_id,
		generation,
		birth_index,
		mutation_seed,
		String(parent_record.get("genome_checksum", "")),
		genome_checksum,
		mutation_event_hash
	)


static func create(
	lineage_id: String,
	individual_id: String,
	parent_individual_id: String,
	generation: int,
	birth_index: int,
	mutation_seed: int,
	parent_genome_checksum: String,
	genome_checksum: String,
	mutation_event_hash: String
) -> Dictionary:
	var record := {
		"schema": SCHEMA,
		"version": VERSION,
		"lineage_id": lineage_id,
		"individual_id": individual_id,
		"parent_individual_id": parent_individual_id,
		"generation": generation,
		"birth_index": birth_index,
		"mutation_seed": mutation_seed,
		"parent_genome_checksum": parent_genome_checksum,
		"genome_checksum": genome_checksum,
		"mutation_event_hash": mutation_event_hash,
	}
	record["checksum"] = compute_checksum(record)
	return record


static func validate(record: Dictionary) -> Dictionary:
	if record.keys().size() != FIELD_NAMES.size():
		return _failure("ECO_LINEAGE_FIELD_COUNT_MISMATCH")
	for field_name in FIELD_NAMES:
		if not record.has(field_name):
			return _failure("ECO_LINEAGE_MISSING_FIELD", {"field": field_name})
	for field_name in record.keys():
		if not String(field_name) in FIELD_NAMES:
			return _failure("ECO_LINEAGE_UNEXPECTED_FIELD", {"field": String(field_name)})
	if String(record.get("schema", "")) != SCHEMA or String(record.get("version", "")) != VERSION:
		return _failure("ECO_LINEAGE_SCHEMA_OR_VERSION_MISMATCH")
	var lineage_id := String(record.get("lineage_id", ""))
	var individual_id := String(record.get("individual_id", ""))
	if not lineage_id.begins_with("eco-lineage/") or not individual_id.begins_with("eco-individual/"):
		return _failure("ECO_LINEAGE_INVALID_ID")
	if typeof(record.get("generation")) != TYPE_INT or int(record.get("generation")) < 0:
		return _failure("ECO_LINEAGE_INVALID_GENERATION")
	if typeof(record.get("birth_index")) != TYPE_INT or int(record.get("birth_index")) < 0:
		return _failure("ECO_LINEAGE_INVALID_BIRTH_INDEX")
	if typeof(record.get("mutation_seed")) != TYPE_INT:
		return _failure("ECO_LINEAGE_INVALID_MUTATION_SEED")
	var generation := int(record.get("generation"))
	var parent_id := String(record.get("parent_individual_id", ""))
	var parent_genome_checksum := String(record.get("parent_genome_checksum", ""))
	if generation == 0:
		if not parent_id.is_empty() or not parent_genome_checksum.is_empty():
			return _failure("ECO_LINEAGE_ANCESTOR_HAS_PARENT")
	else:
		if not parent_id.begins_with("eco-individual/") or not _is_lower_hex_64(parent_genome_checksum):
			return _failure("ECO_LINEAGE_DESCENDANT_PARENT_INVALID")
	for field_name in ["genome_checksum", "mutation_event_hash", "checksum"]:
		if not _is_lower_hex_64(String(record.get(field_name, ""))):
			return _failure("ECO_LINEAGE_INVALID_HASH", {"field": field_name})
	if String(record.get("checksum", "")) != compute_checksum(record):
		return _failure("ECO_LINEAGE_CHECKSUM_MISMATCH")
	return _success()


static func compute_checksum(record: Dictionary) -> String:
	return "|".join(PackedStringArray([
		SCHEMA,
		VERSION,
		String(record.get("lineage_id", "")),
		String(record.get("individual_id", "")),
		String(record.get("parent_individual_id", "")),
		str(int(record.get("generation", 0))),
		str(int(record.get("birth_index", 0))),
		str(int(record.get("mutation_seed", 0))),
		String(record.get("parent_genome_checksum", "")),
		String(record.get("genome_checksum", "")),
		String(record.get("mutation_event_hash", "")),
	])).sha256_text()


static func _identity_hash(payload: String) -> String:
	return ("%s|%s|%s" % [SCHEMA, VERSION, payload]).sha256_text()


static func _is_lower_hex_64(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for character in value:
		if not String(character) in [
			"0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
			"a", "b", "c", "d", "e", "f",
		]:
			return false
	return true


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
