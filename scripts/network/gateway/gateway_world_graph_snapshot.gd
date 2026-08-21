extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const BusUtilsScript = preload("res://scripts/network/bus/message_bus_contract_utils.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")
const WorldDescriptorScript = preload("res://scripts/network/gateway/world_descriptor.gd")
const WorldRelationScript = preload("res://scripts/network/gateway/world_relation.gd")

const SCHEMA := "planet_simulator.gateway_world_graph_snapshot.v1"
const PROTOCOL_VERSION := 1
const SOURCE_OWNER := "WORLD_DIRECTORY"
const PROVENANCE_FIELDS: Array[String] = ["revision", "content_hash"]
const REQUIRED_FIELDS: Array[String] = [
	"schema",
	"protocol_version",
	"graph_snapshot_id",
	"source_owner",
	"directory_revision",
	"graph_revision",
	"worlds",
	"relations",
	"read_only",
	"reconstructible",
	"canonical",
]
const OPTIONAL_FIELDS: Array[String] = ["absent_world_provenance", "absent_relation_provenance"]


static func create(
		graph_snapshot_id: String,
		directory_revision: int,
		graph_revision: int,
		worlds: Array,
		relations: Array,
		read_only: bool = true,
		reconstructible: bool = true,
		canonical: bool = false,
		absent_world_provenance: Dictionary = {},
		absent_relation_provenance: Dictionary = {},
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"graph_snapshot_id": graph_snapshot_id,
		"source_owner": SOURCE_OWNER,
		"directory_revision": directory_revision,
		"graph_revision": graph_revision,
		"worlds": worlds.duplicate(true),
		"relations": relations.duplicate(true),
		"absent_world_provenance": absent_world_provenance.duplicate(true),
		"absent_relation_provenance": absent_relation_provenance.duplicate(true),
		"read_only": read_only,
		"reconstructible": reconstructible,
		"canonical": canonical,
	}


static func reconstruct_from_directory(
		graph_snapshot_id: String,
		directory_revision: int,
		graph_revision: int,
		worlds: Array,
		relations: Array,
		previous_snapshot: Dictionary = {},
) -> Dictionary:
	var absent_world_provenance: Dictionary = {}
	var absent_relation_provenance: Dictionary = {}
	if not previous_snapshot.is_empty():
		absent_world_provenance = Dictionary(previous_snapshot.get("absent_world_provenance", {})).duplicate(true)
		absent_relation_provenance = Dictionary(previous_snapshot.get("absent_relation_provenance", {})).duplicate(true)
		var next_worlds: Dictionary = _index_by_id(worlds, "world_id")
		for raw_world in Array(previous_snapshot.get("worlds", [])):
			var world: Dictionary = Dictionary(raw_world)
			var world_id: String = String(world.get("world_id"))
			if not next_worlds.has(world_id):
				absent_world_provenance[world_id] = _provenance_entry(world, "world_revision")
		for raw_world in worlds:
			absent_world_provenance.erase(String(Dictionary(raw_world).get("world_id")))

		var next_relations: Dictionary = _index_by_id(relations, "relation_id")
		for raw_relation in Array(previous_snapshot.get("relations", [])):
			var relation: Dictionary = Dictionary(raw_relation)
			var relation_id: String = String(relation.get("relation_id"))
			if not next_relations.has(relation_id):
				absent_relation_provenance[relation_id] = _provenance_entry(relation, "relation_revision")
		for raw_relation in relations:
			absent_relation_provenance.erase(String(Dictionary(raw_relation).get("relation_id")))
	return create(
		graph_snapshot_id,
		directory_revision,
		graph_revision,
		worlds,
		relations,
		true,
		true,
		false,
		absent_world_provenance,
		absent_relation_provenance,
	)


static func _validate_snapshot_fields(value: Dictionary) -> Dictionary:
	for field in REQUIRED_FIELDS:
		if not value.has(field):
			return NetworkUtilsScript.validation_failure("MISSING_FIELD", "Required field is missing: %s" % field)
	for raw_key in value.keys():
		if typeof(raw_key) != TYPE_STRING:
			return NetworkUtilsScript.validation_failure("INVALID_FIELD_NAME", "WorldGraph field names must be String")
		var key: String = String(raw_key)
		if not REQUIRED_FIELDS.has(key) and not OPTIONAL_FIELDS.has(key):
			return NetworkUtilsScript.validation_failure("UNEXPECTED_FIELD", "Unexpected WorldGraph field: %s" % key)
	return NetworkUtilsScript.validation_success()


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = _validate_snapshot_fields(value)
	if not bool(exact.get("success", false)):
		return exact
	for check in [
		GatewayUtilsScript.validate_schema(value, SCHEMA),
		GatewayUtilsScript.require_id(value, "graph_snapshot_id", "world-graph"),
		GatewayUtilsScript.require_positive_integer(value, "directory_revision"),
		GatewayUtilsScript.require_positive_integer(value, "graph_revision"),
	]:
		if not bool(check.get("success", false)):
			return check
	if value.get("source_owner") != SOURCE_OWNER:
		return NetworkUtilsScript.validation_failure(
			"WORLD_GRAPH_SOURCE_OWNER_INVALID",
			"Gateway WorldGraph cache input must be derived from WORLD_DIRECTORY",
		)
	if typeof(value.get("read_only")) != TYPE_BOOL or not bool(value.get("read_only")):
		return NetworkUtilsScript.validation_failure(
			"WORLD_GRAPH_NOT_READ_ONLY",
			"Gateway WorldGraph cache input must be read_only=true",
		)
	if typeof(value.get("reconstructible")) != TYPE_BOOL or not bool(value.get("reconstructible")):
		return NetworkUtilsScript.validation_failure(
			"WORLD_GRAPH_NOT_RECONSTRUCTIBLE",
			"Gateway WorldGraph cache input must be reconstructible=true",
		)
	if typeof(value.get("canonical")) != TYPE_BOOL or bool(value.get("canonical")):
		return NetworkUtilsScript.validation_failure(
			"WORLD_GRAPH_CANONICAL_FORBIDDEN",
			"Gateway WorldGraph cache input must be canonical=false",
		)
	if typeof(value.get("worlds")) != TYPE_ARRAY or typeof(value.get("relations")) != TYPE_ARRAY:
		return NetworkUtilsScript.validation_failure(
			"INVALID_GRAPH_COLLECTION",
			"worlds and relations must be Arrays",
		)
	if typeof(value.get("absent_world_provenance", {})) != TYPE_DICTIONARY \
			or typeof(value.get("absent_relation_provenance", {})) != TYPE_DICTIONARY:
		return NetworkUtilsScript.validation_failure(
			"INVALID_GRAPH_PROVENANCE",
			"absent provenance ledgers must be Dictionaries",
		)

	var world_ids: Dictionary = {}
	for raw_world in Array(value.get("worlds")):
		if typeof(raw_world) != TYPE_DICTIONARY:
			return NetworkUtilsScript.validation_failure(
				"INVALID_WORLD_DESCRIPTOR",
				"worlds contains non-Dictionary",
			)
		var world: Dictionary = Dictionary(raw_world)
		var world_check: Dictionary = WorldDescriptorScript.validate(world)
		if not bool(world_check.get("success", false)):
			return world_check
		var world_id: String = String(world.get("world_id"))
		if world_ids.has(world_id):
			return NetworkUtilsScript.validation_failure(
				"DUPLICATE_WORLD_ID",
				"Duplicate world_id in graph snapshot",
			)
		world_ids[world_id] = true

	var relation_ids: Dictionary = {}
	for raw_relation in Array(value.get("relations")):
		if typeof(raw_relation) != TYPE_DICTIONARY:
			return NetworkUtilsScript.validation_failure(
				"INVALID_WORLD_RELATION",
				"relations contains non-Dictionary",
			)
		var relation: Dictionary = Dictionary(raw_relation)
		var relation_check: Dictionary = WorldRelationScript.validate(relation)
		if not bool(relation_check.get("success", false)):
			return relation_check
		var relation_id: String = String(relation.get("relation_id"))
		if relation_ids.has(relation_id):
			return NetworkUtilsScript.validation_failure("DUPLICATE_RELATION_ID", "Duplicate relation_id in graph snapshot")
		relation_ids[relation_id] = true
		if not world_ids.has(String(relation.get("world_a"))) or not world_ids.has(String(relation.get("world_b"))):
			return NetworkUtilsScript.validation_failure(
				"UNKNOWN_RELATION_WORLD",
				"Relation references world outside snapshot partition",
			)

	var world_provenance_check: Dictionary = _validate_absent_provenance_map(
		Dictionary(value.get("absent_world_provenance", {})),
		"world",
		world_ids,
		"WORLD",
	)
	if not bool(world_provenance_check.get("success", false)):
		return world_provenance_check
	var relation_provenance_check: Dictionary = _validate_absent_provenance_map(
		Dictionary(value.get("absent_relation_provenance", {})),
		"world-relation",
		relation_ids,
		"RELATION",
	)
	if not bool(relation_provenance_check.get("success", false)):
		return relation_provenance_check
	return NetworkUtilsScript.validation_success()


static func validate_newer(candidate: Dictionary, current: Dictionary) -> Dictionary:
	var candidate_check: Dictionary = validate(candidate)
	if not bool(candidate_check.get("success", false)):
		return candidate_check
	var current_check: Dictionary = validate(current)
	if not bool(current_check.get("success", false)):
		return current_check
	if String(candidate.get("graph_snapshot_id")) != String(current.get("graph_snapshot_id")):
		return NetworkUtilsScript.validation_failure(
			"GRAPH_SNAPSHOT_ID_MISMATCH",
			"Cannot compare different WorldGraph cache lineages",
		)
	if int(candidate.get("graph_revision")) <= int(current.get("graph_revision")):
		return NetworkUtilsScript.validation_failure(
			"STALE_GRAPH_REVISION",
			"graph_revision must advance",
		)
	if int(candidate.get("directory_revision")) < int(current.get("directory_revision")):
		return NetworkUtilsScript.validation_failure(
			"STALE_DIRECTORY_REVISION",
			"directory_revision cannot rewind",
		)
	var nested_check: Dictionary = _validate_nested_revision_provenance(candidate, current)
	if not bool(nested_check.get("success", false)):
		return nested_check
	var absence_check: Dictionary = _validate_absence_provenance_transition(candidate, current)
	if not bool(absence_check.get("success", false)):
		return absence_check
	return NetworkUtilsScript.validation_success()


static func _validate_nested_revision_provenance(candidate: Dictionary, current: Dictionary) -> Dictionary:
	var current_worlds: Dictionary = _index_by_id(Array(current.get("worlds")), "world_id")
	for raw_world in Array(candidate.get("worlds")):
		var world: Dictionary = Dictionary(raw_world)
		var world_id: String = String(world.get("world_id"))
		if not current_worlds.has(world_id):
			continue
		var previous: Dictionary = Dictionary(current_worlds[world_id])
		var comparison: Dictionary = _compare_revision_content(
			world,
			int(world.get("world_revision")),
			int(previous.get("world_revision")),
			NetworkUtilsScript.payload_hash(previous),
			"STALE_NESTED_WORLD_REVISION",
			"WORLD_REVISION_REUSED_WITH_DIFFERENT_CONTENT",
			"world",
		)
		if not bool(comparison.get("success", false)):
			return comparison

	var current_relations: Dictionary = _index_by_id(Array(current.get("relations")), "relation_id")
	for raw_relation in Array(candidate.get("relations")):
		var relation: Dictionary = Dictionary(raw_relation)
		var relation_id: String = String(relation.get("relation_id"))
		if not current_relations.has(relation_id):
			continue
		var previous: Dictionary = Dictionary(current_relations[relation_id])
		var comparison: Dictionary = _compare_revision_content(
			relation,
			int(relation.get("relation_revision")),
			int(previous.get("relation_revision")),
			NetworkUtilsScript.payload_hash(previous),
			"STALE_NESTED_RELATION_REVISION",
			"RELATION_REVISION_REUSED_WITH_DIFFERENT_CONTENT",
			"relation",
		)
		if not bool(comparison.get("success", false)):
			return comparison
	return NetworkUtilsScript.validation_success()


static func _validate_absence_provenance_transition(candidate: Dictionary, current: Dictionary) -> Dictionary:
	var world_check: Dictionary = _validate_kind_absence_transition(
		Array(candidate.get("worlds")),
		Array(current.get("worlds")),
		Dictionary(candidate.get("absent_world_provenance", {})),
		Dictionary(current.get("absent_world_provenance", {})),
		"world_id",
		"world_revision",
		"WORLD",
	)
	if not bool(world_check.get("success", false)):
		return world_check
	return _validate_kind_absence_transition(
		Array(candidate.get("relations")),
		Array(current.get("relations")),
		Dictionary(candidate.get("absent_relation_provenance", {})),
		Dictionary(current.get("absent_relation_provenance", {})),
		"relation_id",
		"relation_revision",
		"RELATION",
	)


static func _validate_kind_absence_transition(
		candidate_items: Array,
		current_items: Array,
		candidate_absent: Dictionary,
		current_absent: Dictionary,
		id_field: String,
		revision_field: String,
		label: String,
) -> Dictionary:
	var candidate_map: Dictionary = _index_by_id(candidate_items, id_field)
	var current_map: Dictionary = _index_by_id(current_items, id_field)
	var expected_absent: Dictionary = {}

	for item_id in current_map.keys():
		if candidate_map.has(item_id):
			continue
		var current_item: Dictionary = Dictionary(current_map[item_id])
		var expected_entry: Dictionary = _provenance_entry(current_item, revision_field)
		expected_absent[item_id] = expected_entry
		if not candidate_absent.has(item_id) \
				or NetworkUtilsScript.canonical_json(candidate_absent[item_id]) != NetworkUtilsScript.canonical_json(expected_entry):
			return NetworkUtilsScript.validation_failure(
				"%s_ABSENCE_PROVENANCE_MISSING" % label,
				"Removed %s identity must retain exact last-seen revision/content provenance" % label.to_lower(),
			)

	for item_id in current_absent.keys():
		var floor_entry: Dictionary = Dictionary(current_absent[item_id])
		if candidate_map.has(item_id):
			var candidate_item: Dictionary = Dictionary(candidate_map[item_id])
			var stale_code: String = "STALE_REINTRODUCED_%s_REVISION" % label
			var changed_code: String = "%s_REVISION_REINTRODUCED_WITH_DIFFERENT_CONTENT" % label
			var comparison: Dictionary = _compare_revision_content(
				candidate_item,
				int(candidate_item.get(revision_field)),
				int(floor_entry.get("revision")),
				String(floor_entry.get("content_hash")),
				stale_code,
				changed_code,
				label.to_lower(),
			)
			if not bool(comparison.get("success", false)):
				return comparison
			continue
		expected_absent[item_id] = floor_entry
		if not candidate_absent.has(item_id) \
				or NetworkUtilsScript.canonical_json(candidate_absent[item_id]) != NetworkUtilsScript.canonical_json(floor_entry):
			return NetworkUtilsScript.validation_failure(
				"%s_ABSENCE_PROVENANCE_REWRITTEN" % label,
				"Absent %s provenance cannot advance or change without observed content" % label.to_lower(),
			)

	for item_id in candidate_absent.keys():
		if not expected_absent.has(item_id):
			return NetworkUtilsScript.validation_failure(
				"UNEXPECTED_ABSENT_%s_PROVENANCE" % label,
				"Candidate introduced ungrounded absent %s provenance" % label.to_lower(),
			)
	return NetworkUtilsScript.validation_success()


static func _validate_absent_provenance_map(
		provenance: Dictionary,
		id_prefix: String,
		present_ids: Dictionary,
		label: String,
) -> Dictionary:
	for raw_id in provenance.keys():
		if typeof(raw_id) != TYPE_STRING or not BusUtilsScript.is_canonical_id(raw_id, id_prefix):
			return NetworkUtilsScript.validation_failure("INVALID_%s_PROVENANCE_ID" % label, "Invalid provenance identity")
		var item_id: String = String(raw_id)
		if present_ids.has(item_id):
			return NetworkUtilsScript.validation_failure(
				"PRESENT_%s_HAS_ABSENT_PROVENANCE" % label,
				"Present identity cannot also be recorded as absent",
			)
		if typeof(provenance[raw_id]) != TYPE_DICTIONARY:
			return NetworkUtilsScript.validation_failure("INVALID_%s_PROVENANCE" % label, "Provenance entry must be a Dictionary")
		var entry: Dictionary = Dictionary(provenance[raw_id])
		var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(entry, PROVENANCE_FIELDS)
		if not bool(exact.get("success", false)):
			return NetworkUtilsScript.validation_failure("INVALID_%s_PROVENANCE" % label, "Provenance entry fields are invalid")
		if not NetworkUtilsScript.is_json_integer(entry.get("revision")) or int(entry.get("revision")) < 1:
			return NetworkUtilsScript.validation_failure("INVALID_%s_PROVENANCE" % label, "Provenance revision must be positive")
		if not _is_sha256(String(entry.get("content_hash", ""))):
			return NetworkUtilsScript.validation_failure("INVALID_%s_PROVENANCE" % label, "Provenance content_hash must be SHA-256")
	return NetworkUtilsScript.validation_success()


static func _compare_revision_content(
		candidate_item: Dictionary,
		candidate_revision: int,
		floor_revision: int,
		floor_hash: String,
		stale_code: String,
		changed_code: String,
		label: String,
) -> Dictionary:
	if candidate_revision < floor_revision:
		return NetworkUtilsScript.validation_failure(stale_code, "%s revision cannot rewind" % label)
	if candidate_revision == floor_revision and NetworkUtilsScript.payload_hash(candidate_item) != floor_hash:
		return NetworkUtilsScript.validation_failure(changed_code, "%s revision cannot be reused for different content" % label)
	return NetworkUtilsScript.validation_success()


static func _provenance_entry(item: Dictionary, revision_field: String) -> Dictionary:
	return {
		"revision": int(item.get(revision_field, 0)),
		"content_hash": NetworkUtilsScript.payload_hash(item),
	}


static func _index_by_id(items: Array, id_field: String) -> Dictionary:
	var output: Dictionary = {}
	for raw_item in items:
		if typeof(raw_item) == TYPE_DICTIONARY:
			var item: Dictionary = Dictionary(raw_item)
			output[String(item.get(id_field, ""))] = item
	return output


static func _is_sha256(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for character in value:
		if not ((character >= "0" and character <= "9") or (character >= "a" and character <= "f")):
			return false
	return true
