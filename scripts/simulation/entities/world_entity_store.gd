extends RefCounted

const AggregateScript = preload("res://scripts/simulation/entities/world_entity_aggregate.gd")
const Relations = preload("res://scripts/items/domain/item_relations.gd")
const EntityLifecycle = preload("res://scripts/simulation/lifecycle/entity_lifecycle.gd")

const SCHEMA: String = "planet_simulator.world_entity_store.v1"
const MAX_SAFE_JSON_INTEGER: int = 9007199254740991
const FIELDS: Array[String] = [
	"schema",
	"authority_owner_id",
	"authority_epoch",
	"entity_count",
	"entities",
]

var entities: Dictionary = {}
var item_to_entity: Dictionary = {}
var authority_owner_id: String = "local-process"
var authority_epoch: int = 1


func setup(context: Dictionary = {}) -> void:
	authority_owner_id = String(context.get("authority_owner_id", "local-process"))
	authority_epoch = maxi(1, int(context.get("authority_epoch", 1)))


func deterministic_entity_id(item_instance_id: String) -> String:
	if item_instance_id.begins_with("item/"):
		return "entity/item/%s" % item_instance_id.substr(5)
	return "entity/item/%s" % item_instance_id.replace("/", "_")


func create_for_item(
	item_instance_id: String,
	spatial_ref: Dictionary,
	context: Dictionary = {}
):
	if item_instance_id.is_empty() or item_to_entity.has(item_instance_id):
		return null
	var entity_id: String = String(context.get("entity_id", deterministic_entity_id(item_instance_id)))
	if entity_id.is_empty() or entities.has(entity_id):
		return null
	var aggregate = AggregateScript.new()
	var aggregate_context: Dictionary = context.duplicate(true)
	aggregate_context["authority_owner_id"] = String(context.get("authority_owner_id", authority_owner_id))
	aggregate_context["authority_epoch"] = int(context.get("authority_epoch", authority_epoch))
	if not aggregate.setup(entity_id, item_instance_id, spatial_ref, aggregate_context):
		return null
	entities[entity_id] = aggregate
	item_to_entity[item_instance_id] = entity_id
	return aggregate


func register(aggregate) -> Dictionary:
	if aggregate == null:
		return _failure("AGGREGATE_REQUIRED")
	var validation: Dictionary = aggregate.validate()
	if not bool(validation.get("success", false)):
		return validation
	if entities.has(aggregate.entity_id):
		return _failure("DUPLICATE_ENTITY_ID")
	if item_to_entity.has(aggregate.item_instance_id):
		return _failure("DUPLICATE_ITEM_BINDING")
	entities[aggregate.entity_id] = aggregate
	item_to_entity[aggregate.item_instance_id] = aggregate.entity_id
	return {"success": true, "entity_id": aggregate.entity_id}


func get_entity(entity_id: String):
	return entities.get(entity_id)


func get_for_item(item_instance_id: String):
	return entities.get(String(item_to_entity.get(item_instance_id, "")))


func has_entity(entity_id: String) -> bool:
	return entities.has(entity_id)


func remove_entity(entity_id: String) -> bool:
	var aggregate = entities.get(entity_id)
	if aggregate == null:
		return false
	item_to_entity.erase(aggregate.item_instance_id)
	entities.erase(entity_id)
	return true


func remove_for_item(item_instance_id: String) -> bool:
	var entity_id: String = String(item_to_entity.get(item_instance_id, ""))
	return remove_entity(entity_id) if not entity_id.is_empty() else false


func all_entities() -> Array:
	return entities.values()


func size() -> int:
	return entities.size()


func replace_from(other) -> void:
	entities = other.entities.duplicate()
	item_to_entity = other.item_to_entity.duplicate()
	authority_owner_id = other.authority_owner_id
	authority_epoch = other.authority_epoch


func migrate_legacy_item_relations(item_registry) -> Dictionary:
	# Migration is staged against an isolated store. Neither the live store nor
	# any ItemInstance relation is changed until every WORLD binding validates.
	var staged = get_script().new()
	staged.authority_owner_id = authority_owner_id
	staged.authority_epoch = authority_epoch
	staged.entities = entities.duplicate()
	staged.item_to_entity = item_to_entity.duplicate()
	var relation_updates: Array[Dictionary] = []
	var migrated: int = 0
	var created: int = 0
	for item in item_registry.all_items():
		if Relations.kind_of(item.relation) != Relations.WORLD:
			continue
		var relation_entity_id: String = Relations.world_entity_id(item.relation)
		if not relation_entity_id.is_empty():
			var existing = staged.get_entity(relation_entity_id)
			if existing == null:
				return _failure("WORLD_ENTITY_NOT_FOUND", {
					"item_id": item.instance_id,
					"entity_id": relation_entity_id,
				})
			if existing.item_instance_id != item.instance_id:
				return _failure("WORLD_ENTITY_ITEM_MISMATCH", {
					"item_id": item.instance_id,
					"entity_id": relation_entity_id,
				})
			continue
		var spatial_ref: Dictionary = Relations.spatial_ref_from_relation(item.relation)
		var aggregate = staged.create_for_item(item.instance_id, spatial_ref, {
			"state_revision": int(item.revision),
			"domain_components": {
				"definition_id": item.definition_id,
				"quantity": int(item.quantity),
			},
			"lifecycle_state": EntityLifecycle.ACTIVE,
		})
		if aggregate == null:
			return _failure("WORLD_ENTITY_CREATE_FAILED", {"item_id": item.instance_id})
		relation_updates.append({
			"item": item,
			"relation": Relations.world_entity(aggregate.entity_id),
		})
		created += 1
		migrated += 1

	# Commit is intentionally last and contains no fallible operations.
	entities = staged.entities
	item_to_entity = staged.item_to_entity
	for update in relation_updates:
		update["item"].set_relation(Dictionary(update["relation"]))
	return {
		"success": true,
		"migrated_relation_count": migrated,
		"created_entity_count": created,
	}


func validate_item_bindings(item_registry) -> Dictionary:
	var expected: Dictionary = {}
	for item in item_registry.all_items():
		if Relations.kind_of(item.relation) != Relations.WORLD:
			if get_for_item(item.instance_id) != null:
				return _failure("NON_WORLD_ITEM_HAS_WORLD_ENTITY", {"item_id": item.instance_id})
			continue
		var entity_id: String = Relations.world_entity_id(item.relation)
		if entity_id.is_empty():
			return _failure("LEGACY_WORLD_RELATION_NOT_MIGRATED", {"item_id": item.instance_id})
		var aggregate = get_entity(entity_id)
		if aggregate == null:
			return _failure("WORLD_ENTITY_NOT_FOUND", {"item_id": item.instance_id, "entity_id": entity_id})
		if aggregate.item_instance_id != item.instance_id:
			return _failure("WORLD_ENTITY_ITEM_MISMATCH", {"item_id": item.instance_id, "entity_id": entity_id})
		expected[entity_id] = true
	for entity_id_value in entities.keys():
		var entity_id: String = String(entity_id_value)
		var aggregate = entities[entity_id]
		if not expected.has(entity_id):
			return _failure("ORPHAN_WORLD_ENTITY", {"entity_id": entity_id})
		var validation: Dictionary = aggregate.validate()
		if not bool(validation.get("success", false)):
			return _failure("INVALID_WORLD_ENTITY", {"entity_id": entity_id, "cause": validation})
	return {"success": true, "entity_count": entities.size()}


func to_dict() -> Dictionary:
	var rows: Array[Dictionary] = []
	var ids: Array = entities.keys()
	ids.sort()
	for entity_id in ids:
		rows.append(entities[entity_id].to_snapshot())
	return {
		"schema": SCHEMA,
		"authority_owner_id": authority_owner_id,
		"authority_epoch": authority_epoch,
		"entity_count": rows.size(),
		"entities": rows,
	}


func load_dict(value: Dictionary) -> Dictionary:
	var fields_result: Dictionary = _validate_exact_fields(value)
	if not bool(fields_result.get("success", false)):
		return fields_result
	if typeof(value["schema"]) != TYPE_STRING or value["schema"] != SCHEMA:
		return _failure("UNSUPPORTED_WORLD_ENTITY_STORE_SCHEMA")
	if typeof(value["authority_owner_id"]) != TYPE_STRING or String(value["authority_owner_id"]).strip_edges().is_empty():
		return _failure("INVALID_WORLD_ENTITY_STORE_AUTHORITY")
	if not _is_json_integer(value["authority_epoch"]) or int(value["authority_epoch"]) <= 0:
		return _failure("INVALID_WORLD_ENTITY_STORE_AUTHORITY")
	if not _is_json_integer(value["entity_count"]) or int(value["entity_count"]) < 0:
		return _failure("INVALID_WORLD_ENTITY_COUNT")
	var rows = value["entities"]
	if typeof(rows) != TYPE_ARRAY:
		return _failure("INVALID_WORLD_ENTITY_ROWS")
	var staged_entities: Dictionary = {}
	var staged_items: Dictionary = {}
	for row in rows:
		if not row is Dictionary:
			return _failure("INVALID_WORLD_ENTITY_ROW")
		var aggregate = AggregateScript.new()
		var snapshot_validation: Dictionary = aggregate.validate_snapshot_payload(Dictionary(row))
		if not bool(snapshot_validation.get("success", false)):
			return _failure("INVALID_WORLD_ENTITY_SNAPSHOT", {"cause": snapshot_validation})
		if not aggregate.setup_from_snapshot(Dictionary(row)):
			return _failure("INVALID_WORLD_ENTITY_SNAPSHOT")
		if staged_entities.has(aggregate.entity_id):
			return _failure("DUPLICATE_ENTITY_ID")
		if staged_items.has(aggregate.item_instance_id):
			return _failure("DUPLICATE_ITEM_BINDING")
		staged_entities[aggregate.entity_id] = aggregate
		staged_items[aggregate.item_instance_id] = aggregate.entity_id
	if int(value["entity_count"]) != staged_entities.size():
		return _failure("WORLD_ENTITY_COUNT_MISMATCH")
	entities = staged_entities
	item_to_entity = staged_items
	authority_owner_id = String(value["authority_owner_id"])
	authority_epoch = int(value["authority_epoch"])
	return {"success": true, "entity_count": entities.size()}


func _validate_exact_fields(value: Dictionary) -> Dictionary:
	for field in FIELDS:
		if not value.has(field):
			return _failure("MISSING_WORLD_ENTITY_STORE_FIELD", {"field": field})
	for key_value in value.keys():
		if typeof(key_value) != TYPE_STRING or not FIELDS.has(String(key_value)):
			return _failure("UNEXPECTED_WORLD_ENTITY_STORE_FIELD", {"field": str(key_value)})
	return {"success": true}


func _is_json_integer(value) -> bool:
	if typeof(value) == TYPE_INT:
		return abs(int(value)) <= MAX_SAFE_JSON_INTEGER
	return typeof(value) == TYPE_FLOAT and is_finite(float(value)) and absf(float(value)) <= float(MAX_SAFE_JSON_INTEGER) and float(value) == floor(float(value))


func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
