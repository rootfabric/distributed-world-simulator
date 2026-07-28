extends SceneTree

const EntityPortScript = preload("res://scripts/runtime/ports/entity_registry_kernel_port.gd")
const RepositoryPortScript = preload("res://scripts/runtime/ports/world_repository_kernel_port.gd")
const KernelScript = preload("res://scripts/runtime/simulation_kernel.gd")

var failures: Array[String] = []
var assertions: int = 0


class ForgedEntityRegistryPort:
	extends RefCounted

	func create_descriptor() -> Dictionary:
		return {
			"schema": "planet_simulator.entity_registry_kernel_port.v1",
			"configured": true,
			"read_only": true,
			"entity_count": 1,
			"authority_owner_id": "sim-a",
			"authority_epoch": 4,
		}

	func validate_contract_state() -> Dictionary:
		return {"success": true}


class ForgedWorldRepositoryPort:
	extends RefCounted

	func create_descriptor() -> Dictionary:
		return {
			"schema": "planet_simulator.world_repository_kernel_port.v1",
			"configured": true,
			"world_id": "moon",
			"instance_id": "persistent",
			"supports_flush_request": true,
		}

	func validate_contract_state() -> Dictionary:
		return {"success": true}


func _init() -> void:
	var entity_record: Dictionary = {
		"schema": "planet_simulator.entity.v2",
		"entity_id": "entity/a",
		"entity_type": "probe",
		"spatial_ref": {},
		"partition_address": {},
		"zone_id": "",
		"chunk_id": "",
		"world_position": [0.0, 0.0, 0.0],
		"components": {},
		"authority_owner_id": "sim-a",
		"authority_epoch": 4,
		"state_revision": 3,
		"revision": 3,
		"last_simulation_tick": 10,
		"created_at_utc": "2026-07-27T00:00:00Z",
		"updated_at_utc": "2026-07-27T00:00:00Z",
	}
	var registry_snapshot: Dictionary = {
		"schema": "planet_simulator.entity_registry.v2",
		"authority_owner_id": "sim-a",
		"authority_epoch": 4,
		"entity_count": 1,
		"migration_count": 0,
		"chunk_transition_count": 0,
		"zone_transition_count": 0,
		"stale_write_rejection_count": 0,
		"entities": [entity_record],
	}
	var entity_port = EntityPortScript.new()
	_assert_ok(entity_port.setup(registry_snapshot), "Entity port setup failed")
	_assert(entity_port.get_entity_count() == 1, "Entity count incorrect")
	_assert(entity_port.has_entity("entity/a"), "Known entity missing")
	_assert(not entity_port.has_entity("entity/missing"), "Missing entity reported")
	_assert_ok(entity_port.get_entity_snapshot("entity/a"), "Entity snapshot read failed")
	_assert_code(entity_port.get_entity_snapshot("entity/missing"), "ENTITY_NOT_FOUND", "Missing entity returned success")
	_assert(bool(entity_port.create_descriptor()["read_only"]), "Entity port is not read-only")
	_assert(String(entity_port.create_descriptor()["authority_owner_id"]) == "sim-a", "Entity port authority owner lost")
	_assert_ok(EntityPortScript.validate_descriptor(entity_port.create_descriptor()), "Entity port descriptor rejected")
	var entity_descriptor_extra: Dictionary = entity_port.create_descriptor()
	entity_descriptor_extra["callback"] = "forbidden"
	_assert_code(EntityPortScript.validate_descriptor(entity_descriptor_extra), "UNEXPECTED_FIELD", "Entity descriptor extra field accepted")
	var entity_descriptor_writable: Dictionary = entity_port.create_descriptor()
	entity_descriptor_writable["read_only"] = false
	_assert_code(EntityPortScript.validate_descriptor(entity_descriptor_writable), "INVALID_PORT_DESCRIPTOR", "Writable entity descriptor accepted")
	var entity_descriptor_bad_configured: Dictionary = entity_port.create_descriptor()
	entity_descriptor_bad_configured["configured"] = "true"
	_assert_code(EntityPortScript.validate_descriptor(entity_descriptor_bad_configured), "INVALID_PORT_DESCRIPTOR", "String configured flag accepted")

	var bad_count: Dictionary = registry_snapshot.duplicate(true)
	bad_count["entity_count"] = 2
	_assert_code(entity_port.refresh(bad_count), "REGISTRY_COUNT_MISMATCH", "Count mismatch accepted")
	_assert(entity_port.get_entity_count() == 1, "Failed refresh mutated live port")
	var extra_registry_field: Dictionary = registry_snapshot.duplicate(true)
	extra_registry_field["callback"] = "forbidden"
	_assert_code(entity_port.refresh(extra_registry_field), "UNEXPECTED_FIELD", "Registry extra field accepted")
	var extra_entity_field: Dictionary = registry_snapshot.duplicate(true)
	extra_entity_field["entities"] = [entity_record.duplicate(true)]
	extra_entity_field["entities"][0]["unexpected"] = true
	_assert_code(entity_port.refresh(extra_entity_field), "INVALID_ENTITY_SNAPSHOT", "Entity extra field accepted")
	var duplicate_ids: Dictionary = registry_snapshot.duplicate(true)
	duplicate_ids["entity_count"] = 2
	duplicate_ids["entities"] = [entity_record, entity_record]
	_assert_code(entity_port.refresh(duplicate_ids), "DUPLICATE_ENTITY_ID", "Duplicate entity IDs accepted")
	var runtime_value: Dictionary = registry_snapshot.duplicate(true)
	var runtime_entity_node := Node.new()
	runtime_value["entities"] = [runtime_entity_node]
	_assert_code(entity_port.refresh(runtime_value), "INVALID_ENTITY_SNAPSHOT", "Runtime entity object accepted")
	runtime_entity_node.free()
	_assert(entity_port.get_entity_count() == 1, "Runtime-object refresh mutated live port")

	var repository_snapshot: Dictionary = {
		"schema": "lunar.persistence_runtime.v1",
		"initialized": true,
		"world_id": "moon",
		"universe_id": "main",
		"instance_id": "persistent",
		"partition_space_id": "moon",
		"partition_scheme": "cube_sphere",
		"partition_scheme_revision": 1,
		"partition_grid": {},
		"world_root": "user://worlds/moon",
		"manifest_path": "user://worlds/moon/world.json",
		"journal_path": "user://worlds/moon/journal.jsonl",
		"landmark_index_path": "user://worlds/moon/landmarks.json",
		"landmark_count": 0,
		"landmark_marker_node_count": 0,
		"landmark_markers_enabled": true,
		"landmark_marker_max_distance_m": 1000.0,
		"landmark_index_rebuilt": false,
		"loaded_chunk_count": 2,
		"runtime_node_count": 2,
		"persistent_entity_count": 1,
		"dirty_chunks": [],
		"chunk_load_count": 2,
		"chunk_unload_count": 0,
		"last_save_summary": "ready",
		"last_player_world_position": [0.0, 0.0, 0.0],
	}
	var repository_port = RepositoryPortScript.new()
	_assert_ok(repository_port.setup(repository_snapshot), "Repository port setup failed")
	_assert_ok(repository_port.create_repository_snapshot(), "Repository snapshot failed")
	_assert_ok(RepositoryPortScript.validate_descriptor(repository_port.create_descriptor()), "Repository port descriptor rejected")
	var repository_descriptor_extra: Dictionary = repository_port.create_descriptor()
	repository_descriptor_extra["callback"] = "forbidden"
	_assert_code(RepositoryPortScript.validate_descriptor(repository_descriptor_extra), "UNEXPECTED_FIELD", "Repository descriptor extra field accepted")
	var repository_descriptor_no_flush: Dictionary = repository_port.create_descriptor()
	repository_descriptor_no_flush["supports_flush_request"] = false
	_assert_code(RepositoryPortScript.validate_descriptor(repository_descriptor_no_flush), "INVALID_PORT_DESCRIPTOR", "Configured repository without flush support accepted")
	var flush_request: Dictionary = repository_port.create_flush_request("operation/flush/1", 100)
	_assert_ok(flush_request, "Flush request creation failed")
	_assert(String(flush_request["request"]["world_id"]) == "moon", "Flush request lost world ID")
	_assert_ok(repository_port.validate_flush_request(flush_request["request"]), "Valid flush request rejected")
	var bad_flush: Dictionary = flush_request["request"].duplicate(true)
	bad_flush["requested_at_tick"] = "100"
	_assert_code(repository_port.validate_flush_request(bad_flush), "INVALID_FLUSH_REQUEST_TICK", "String flush tick accepted")
	var extra_flush: Dictionary = flush_request["request"].duplicate(true)
	extra_flush["callback"] = "forbidden"
	_assert_code(repository_port.validate_flush_request(extra_flush), "UNEXPECTED_FIELD", "Extra flush field accepted")
	var extra_repository: Dictionary = repository_snapshot.duplicate(true)
	extra_repository["callback"] = "forbidden"
	_assert_code(repository_port.refresh(extra_repository), "UNEXPECTED_FIELD", "Repository extra field accepted")
	var duplicate_dirty: Dictionary = repository_snapshot.duplicate(true)
	duplicate_dirty["dirty_chunks"] = ["chunk/a", "chunk/a"]
	_assert_code(repository_port.refresh(duplicate_dirty), "DUPLICATE_DIRTY_CHUNK", "Duplicate dirty chunks accepted")
	var bad_repository: Dictionary = repository_snapshot.duplicate(true)
	bad_repository["schema"] = "unknown.repository"
	_assert_code(repository_port.refresh(bad_repository), "UNSUPPORTED_REPOSITORY_SCHEMA", "Unknown repository schema accepted")
	_assert(String(repository_port.create_descriptor()["world_id"]) == "moon", "Failed repository refresh mutated port")
	var unsafe_repository: Dictionary = repository_snapshot.duplicate(true)
	var repository_debug_node := Node.new()
	unsafe_repository["partition_grid"] = {"debug_node": repository_debug_node}
	_assert_code(repository_port.refresh(unsafe_repository), "NON_CANONICAL_REPOSITORY_SNAPSHOT", "Runtime object in repository snapshot accepted")
	repository_debug_node.free()

	var kernel = KernelScript.new()
	_assert_ok(kernel.setup({}), "Kernel setup failed")
	_assert_ok(kernel.set_entity_registry_port(entity_port), "Kernel rejected entity port")
	_assert_ok(kernel.set_world_repository_port(repository_port), "Kernel rejected repository port")
	_assert_code(kernel.set_entity_registry_port(RefCounted.new()), "INVALID_KERNEL_PORT", "Kernel accepted arbitrary entity port")
	_assert_code(kernel.set_world_repository_port(entity_port), "KERNEL_PORT_SCHEMA_MISMATCH", "Kernel accepted wrong repository port schema")
	_assert_code(kernel.set_entity_registry_port(ForgedEntityRegistryPort.new()), "INVALID_KERNEL_PORT_TYPE", "Kernel accepted forged entity port")
	_assert_code(kernel.set_world_repository_port(ForgedWorldRepositoryPort.new()), "INVALID_KERNEL_PORT_TYPE", "Kernel accepted forged repository port")
	var unconfigured_repository_port = RepositoryPortScript.new()
	_assert_code(kernel.set_world_repository_port(unconfigured_repository_port), "KERNEL_PORT_NOT_CONFIGURED", "Kernel accepted unconfigured repository port")
	var tampered_entity_port = EntityPortScript.new()
	_assert_ok(tampered_entity_port.setup(registry_snapshot), "Tampered entity port setup failed")
	tampered_entity_port.registry_snapshot["entity_count"] = 2
	_assert_code(kernel.set_entity_registry_port(tampered_entity_port), "INVALID_KERNEL_PORT_STATE", "Kernel accepted corrupted entity port state")
	_assert(kernel.entity_registry_port == entity_port, "Rejected entity port replaced live kernel port")
	var tampered_repository_port = RepositoryPortScript.new()
	_assert_ok(tampered_repository_port.setup(repository_snapshot), "Tampered repository port setup failed")
	tampered_repository_port.repository_snapshot["partition_scheme_revision"] = 0
	_assert_code(kernel.set_world_repository_port(tampered_repository_port), "INVALID_KERNEL_PORT_STATE", "Kernel accepted corrupted repository port state")
	_assert(kernel.world_repository_port == repository_port, "Rejected repository port replaced live kernel port")
	var kernel_snapshot: Dictionary = kernel.create_snapshot()
	_assert(bool(kernel_snapshot["has_entity_registry_port"]), "Kernel missed entity port")
	_assert(bool(kernel_snapshot["has_world_repository_port"]), "Kernel missed repository port")
	_assert(bool(kernel_snapshot["presentation_free"]), "Pure ports broke presentation-free boundary")
	var presentation_port = EntityPortScript.new()
	presentation_port.set_meta("hidden_camera", Camera2D.new())
	_assert_code(kernel.set_entity_registry_port(presentation_port), "PRESENTATION_OBJECT_REJECTED", "Kernel accepted presentation-bearing port")
	var hidden_camera: Camera2D = presentation_port.get_meta("hidden_camera")
	presentation_port.remove_meta("hidden_camera")
	hidden_camera.free()

	_finish()


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert_code(result: Dictionary, code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == code, "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("Foundation kernel ports: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Foundation kernel ports: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
