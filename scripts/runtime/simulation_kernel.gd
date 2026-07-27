extends RefCounted

const SCHEMA: String = "planet_simulator.simulation_kernel.v1"

var simulation_clock
var command_gateway
var test_registry
var lifecycle_coordinator
var world_entity_store
var services: Dictionary = {}
var initialized: bool = false


func setup(context: Dictionary) -> Dictionary:
	simulation_clock = context.get("simulation_clock")
	command_gateway = context.get("command_gateway")
	test_registry = context.get("test_registry")
	lifecycle_coordinator = context.get("lifecycle_coordinator")
	world_entity_store = context.get("world_entity_store")
	services = Dictionary(context.get("services", {})).duplicate()
	var validation: Dictionary = validate_boundary()
	initialized = bool(validation.get("success", false))
	return validation


func set_world_entity_store(store) -> Dictionary:
	if _is_presentation_object(store):
		return _failure("PRESENTATION_OBJECT_REJECTED", {"service_id": "world_entity_store"})
	world_entity_store = store
	return {"success": true}


func register_service(service_id: String, service) -> Dictionary:
	if service_id.is_empty():
		return _failure("EMPTY_SERVICE_ID")
	if _is_presentation_object(service):
		return _failure("PRESENTATION_OBJECT_REJECTED", {"service_id": service_id})
	services[service_id] = service
	return {"success": true, "service_id": service_id}


func validate_boundary() -> Dictionary:
	var core_services: Dictionary = {
		"simulation_clock": simulation_clock,
		"command_gateway": command_gateway,
		"test_registry": test_registry,
		"lifecycle_coordinator": lifecycle_coordinator,
		"world_entity_store": world_entity_store,
	}
	for service_id in core_services.keys():
		if _is_presentation_object(core_services[service_id]):
			return _failure("PRESENTATION_OBJECT_REJECTED", {"service_id": service_id})
	for service_id in services.keys():
		if _is_presentation_object(services[service_id]):
			return _failure("PRESENTATION_OBJECT_REJECTED", {"service_id": service_id})
	return {"success": true}


func create_snapshot() -> Dictionary:
	return {
		"schema": SCHEMA,
		"initialized": initialized,
		"service_ids": services.keys(),
		"has_simulation_clock": simulation_clock != null,
		"has_command_gateway": command_gateway != null,
		"has_test_registry": test_registry != null,
		"has_lifecycle": lifecycle_coordinator != null,
		"has_world_entity_store": world_entity_store != null,
		"presentation_free": bool(validate_boundary().get("success", false)),
	}


func _is_presentation_object(value, depth: int = 0) -> bool:
	if depth > 32:
		return true
	if (
		value is Control
		or value is CanvasLayer
		or value is Camera3D
		or value is AudioStreamPlayer
		or value is InputEvent
		or value is Viewport
	):
		return true
	if value is Dictionary:
		for child in value.values():
			if _is_presentation_object(child, depth + 1):
				return true
	if value is Array:
		for child in value:
			if _is_presentation_object(child, depth + 1):
				return true
	return false


func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
