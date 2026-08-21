extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")
const WorldDescriptorScript = preload("res://scripts/network/gateway/world_descriptor.gd")
const WorldRelationScript = preload("res://scripts/network/gateway/world_relation.gd")

const SCHEMA := "planet_simulator.gateway_world_graph_snapshot.v1"
const PROTOCOL_VERSION := 1
const SOURCE_OWNER := "WORLD_DIRECTORY"
const FIELDS: Array[String] = [
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


static func create(
		graph_snapshot_id: String,
		directory_revision: int,
		graph_revision: int,
		worlds: Array,
		relations: Array,
		read_only: bool = true,
		reconstructible: bool = true,
		canonical: bool = false,
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
) -> Dictionary:
	return create(
		graph_snapshot_id,
		directory_revision,
		graph_revision,
		worlds,
		relations,
		true,
		true,
		false,
	)


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
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
		if not world_ids.has(String(relation.get("world_a"))) or not world_ids.has(String(relation.get("world_b"))):
			return NetworkUtilsScript.validation_failure(
				"UNKNOWN_RELATION_WORLD",
				"Relation references world outside snapshot partition",
			)
	return NetworkUtilsScript.validation_success()


static func validate_newer(candidate: Dictionary, current: Dictionary) -> Dictionary:
	var candidate_check: Dictionary = validate(candidate)
	if not bool(candidate_check.get("success", false)):
		return candidate_check
	var current_check: Dictionary = validate(current)
	if not bool(current_check.get("success", false)):
		return current_check
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
	return NetworkUtilsScript.validation_success()


static func _validate_nested_revision_provenance(candidate: Dictionary, current: Dictionary) -> Dictionary:
	var current_worlds: Dictionary = {}
	for raw_world in Array(current.get("worlds")):
		var world: Dictionary = Dictionary(raw_world)
		current_worlds[String(world.get("world_id"))] = world
	for raw_world in Array(candidate.get("worlds")):
		var world: Dictionary = Dictionary(raw_world)
		var world_id: String = String(world.get("world_id"))
		if not current_worlds.has(world_id):
			continue
		var previous: Dictionary = Dictionary(current_worlds[world_id])
		var candidate_revision: int = int(world.get("world_revision"))
		var current_revision: int = int(previous.get("world_revision"))
		if candidate_revision < current_revision:
			return NetworkUtilsScript.validation_failure(
				"STALE_NESTED_WORLD_REVISION",
				"world_revision cannot rewind inside a newer graph snapshot",
			)
		if candidate_revision == current_revision \
				and NetworkUtilsScript.canonical_json(world) != NetworkUtilsScript.canonical_json(previous):
			return NetworkUtilsScript.validation_failure(
				"WORLD_REVISION_REUSED_WITH_DIFFERENT_CONTENT",
				"A world revision cannot be reused for different descriptor content",
			)

	var current_relations: Dictionary = {}
	for raw_relation in Array(current.get("relations")):
		var relation: Dictionary = Dictionary(raw_relation)
		current_relations[String(relation.get("relation_id"))] = relation
	for raw_relation in Array(candidate.get("relations")):
		var relation: Dictionary = Dictionary(raw_relation)
		var relation_id: String = String(relation.get("relation_id"))
		if not current_relations.has(relation_id):
			continue
		var previous: Dictionary = Dictionary(current_relations[relation_id])
		var candidate_revision: int = int(relation.get("relation_revision"))
		var current_revision: int = int(previous.get("relation_revision"))
		if candidate_revision < current_revision:
			return NetworkUtilsScript.validation_failure(
				"STALE_NESTED_RELATION_REVISION",
				"relation_revision cannot rewind inside a newer graph snapshot",
			)
		if candidate_revision == current_revision \
				and NetworkUtilsScript.canonical_json(relation) != NetworkUtilsScript.canonical_json(previous):
			return NetworkUtilsScript.validation_failure(
				"RELATION_REVISION_REUSED_WITH_DIFFERENT_CONTENT",
				"A relation revision cannot be reused for different relation content",
			)
	return NetworkUtilsScript.validation_success()
