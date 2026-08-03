extends Node

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const CompilerScript = preload("res://scripts/construction/runtime_projection/construction_runtime_projection_compiler.gd")
const DescriptorScript = preload("res://scripts/construction/runtime_projection/construction_runtime_construct_descriptor.gd")
const StoreScript = preload("res://scripts/construction/runtime_projection/construction_runtime_projection_store.gd")
const ConstructNodeScript = preload("res://scripts/construction/runtime_projection/construction_runtime_construct_node.gd")

var _root: Node3D
var _store = StoreScript.new()
var _nodes: Dictionary = {}
var _presentation_generation := 0

func _init() -> void:
	_root = Node3D.new(); _root.name = "ConstructionRuntimeProjectionRoot"; add_child(_root)

func upsert(request: Dictionary) -> Dictionary:
	var compiled := CompilerScript.compile(request); if not bool(compiled.get("success", false)): return compiled
	var descriptor: Dictionary = compiled["descriptor"]
	var preflight := _preflight(descriptor); if not bool(preflight.get("success", false)): return preflight
	var published := _store.publish(descriptor); if not bool(published.get("success", false)): return published
	var construct_id := String(descriptor["construct_id"])
	if bool(published.get("replay", false)) and _nodes.has(construct_id): return _success({"replay": true, "descriptor": descriptor, "generation": _store.get_generation(), "presentation_generation": _presentation_generation})
	var created := not _nodes.has(construct_id)
	var node = _nodes.get(construct_id, null)
	if node == null or not is_instance_valid(node):
		node = ConstructNodeScript.new(); _root.add_child(node); _nodes[construct_id] = node
	var applied: Dictionary = node.apply_descriptor(descriptor); if not bool(applied.get("success", false)): return applied
	_presentation_generation += 1
	return _success({"replay": bool(published.get("replay", false)), "created": created, "descriptor": descriptor, "apply_result": applied, "generation": _store.get_generation(), "presentation_generation": _presentation_generation})

func sync_world(requests: Array) -> Dictionary:
	var descriptors: Array = []; var ids := {}; var item_owners := {}
	for request in requests:
		if typeof(request) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_RUNTIME_WORLD_REQUEST")
		var compiled := CompilerScript.compile(request); if not bool(compiled.get("success", false)): return compiled
		var descriptor: Dictionary = compiled["descriptor"]; var construct_id := String(descriptor["construct_id"])
		if ids.has(construct_id): return _failure("DUPLICATE_CONSTRUCTION_RUNTIME_WORLD_CONSTRUCT")
		var preflight := _preflight(descriptor); if not bool(preflight.get("success", false)): return preflight
		for part in descriptor["part_descriptors"]:
			if String(part["condition"]) == "DESTROYED": continue
			var item_id := String(part["item_instance_id"])
			if item_owners.has(item_id): return _failure("CONSTRUCTION_RUNTIME_WORLD_DUPLICATE_ITEM_ID", {"item_instance_id": item_id, "construct_a": item_owners[item_id], "construct_b": construct_id})
			item_owners[item_id] = construct_id
		ids[construct_id] = true; descriptors.append(descriptor)
	descriptors.sort_custom(func(a, b): return String(a["construct_id"]) < String(b["construct_id"]))
	var removed: Array = []
	for existing_id in _store.get_all().map(func(value): return String(value["construct_id"])):
		if not ids.has(existing_id):
			_remove_node(existing_id); var removed_result := _store.remove(existing_id); if not bool(removed_result.get("success", false)): return removed_result
			removed.append(existing_id)
	var created: Array = []; var updated: Array = []; var replayed: Array = []
	for descriptor in descriptors:
		var construct_id := String(descriptor["construct_id"]); var existed := _nodes.has(construct_id)
		var request_result := _apply_compiled(descriptor)
		if not bool(request_result.get("success", false)): return request_result
		if bool(request_result.get("replay", false)): replayed.append(construct_id)
		elif existed: updated.append(construct_id)
		else: created.append(construct_id)
	return _success({"created_construct_ids": created, "updated_construct_ids": updated, "removed_construct_ids": removed, "replayed_construct_ids": replayed, "world_checksum": get_world_checksum(), "generation": _store.get_generation(), "presentation_generation": _presentation_generation})

func remove_construct(construct_id: String, expected_descriptor_checksum: String = "") -> Dictionary:
	var removed := _store.remove(construct_id, expected_descriptor_checksum); if not bool(removed.get("success", false)): return removed
	if not bool(removed.get("replay", false)): _remove_node(construct_id); _presentation_generation += 1
	return removed

func clear_presentation() -> void:
	for construct_id in _nodes.keys().duplicate(): _remove_node(String(construct_id))
	_presentation_generation += 1

func rebuild_presentation() -> Dictionary:
	for descriptor in _store.get_all():
		var construct_id := String(descriptor["construct_id"])
		var node = ConstructNodeScript.new(); _root.add_child(node); _nodes[construct_id] = node
		var applied: Dictionary = node.apply_descriptor(descriptor); if not bool(applied.get("success", false)): return applied
	_presentation_generation += 1
	return _success({"construct_count": _nodes.size(), "world_checksum": get_world_checksum()})

func export_state() -> Dictionary: return _store.export_state()
func load_state(state: Dictionary, rebuild: bool = true) -> Dictionary:
	var loaded := _store.load_state(state); if not bool(loaded.get("success", false)): return loaded
	clear_presentation()
	return rebuild_presentation() if rebuild else _success()
func get_construct_node(construct_id: String): return _nodes.get(construct_id, null)
func get_descriptor(construct_id: String) -> Dictionary: return _store.get_descriptor(construct_id)
func get_generation() -> int: return _store.get_generation()
func get_presentation_generation() -> int: return _presentation_generation
func get_construct_count() -> int: return _nodes.size()
func get_world_checksum() -> String: return UtilsScript.payload_hash({"descriptors": _store.get_all()})
func get_runtime_root() -> Node3D: return _root

func _apply_compiled(descriptor: Dictionary) -> Dictionary:
	var published := _store.publish(descriptor); if not bool(published.get("success", false)): return published
	var construct_id := String(descriptor["construct_id"])
	if bool(published.get("replay", false)) and _nodes.has(construct_id): return _success({"replay": true})
	var node = _nodes.get(construct_id, null)
	if node == null or not is_instance_valid(node): node = ConstructNodeScript.new(); _root.add_child(node); _nodes[construct_id] = node
	var applied: Dictionary = node.apply_descriptor(descriptor); if not bool(applied.get("success", false)): return applied
	_presentation_generation += 1
	return _success({"replay": bool(published.get("replay", false)), "apply_result": applied})

func _preflight(descriptor: Dictionary) -> Dictionary:
	var checked := DescriptorScript.validate(descriptor); if not bool(checked.get("success", false)): return checked
	var current := _store.get_descriptor(String(descriptor["construct_id"]))
	if current.is_empty(): return _success()
	if String(current["checksum"]) == String(descriptor["checksum"]): return _success()
	if int(descriptor["construct_revision"]) < int(current["construct_revision"]): return _failure("STALE_CONSTRUCTION_RUNTIME_PROJECTION")
	if int(descriptor["construct_revision"]) == int(current["construct_revision"]) and String(descriptor["construct_checksum"]) != String(current["construct_checksum"]): return _failure("CONSTRUCTION_RUNTIME_SAME_REVISION_MUTATION")
	return _success()

func _remove_node(construct_id: String) -> void:
	if not _nodes.has(construct_id): return
	var node = _nodes[construct_id]
	if is_instance_valid(node): _root.remove_child(node); node.free()
	_nodes.erase(construct_id)

static func _success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": "", "details": details.duplicate(true)}
	for key in details: result[key] = details[key]
	return result
static func _failure(code: String, details: Dictionary = {}) -> Dictionary: return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
