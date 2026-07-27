extends SceneTree

const SimulationKernel = preload("res://scripts/runtime/simulation_kernel.gd")
const PresentationHost = preload("res://scripts/runtime/presentation_host.gd")
const SimulationClock = preload("res://scripts/simulation/time/simulation_clock.gd")
const CommandRegistry = preload("res://scripts/core/command_registry.gd")
const RuntimeTestRegistry = preload("res://scripts/core/runtime_test_registry.gd")
const LifecycleCoordinator = preload("res://scripts/runtime/lifecycle_coordinator.gd")
const CanonicalStatePort = preload("res://scripts/persistence/canonical_state_port.gd")
const Factory = preload("res://scripts/items/services/item_domain_factory.gd")

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var clock = SimulationClock.new()
	clock.setup({})
	var commands = CommandRegistry.new()
	var tests = RuntimeTestRegistry.new()
	var lifecycle = LifecycleCoordinator.new()
	lifecycle.setup({"node_id": "kernel-test"})
	var domain := Factory.create()
	var kernel = SimulationKernel.new()
	var setup_result: Dictionary = kernel.setup({
		"simulation_clock": clock,
		"command_gateway": commands,
		"test_registry": tests,
		"lifecycle_coordinator": lifecycle,
		"world_entity_store": domain.world_entities,
		"services": {"item_domain": domain.items},
	})
	_assert_success(setup_result, "Pure simulation services must pass kernel boundary")
	var kernel_snapshot: Dictionary = kernel.create_snapshot()
	_assert(bool(kernel_snapshot.get("initialized", false)), "Kernel must report initialized")
	_assert(bool(kernel_snapshot.get("presentation_free", false)), "Kernel must report presentation-free")
	_assert(bool(kernel_snapshot.get("has_world_entity_store", false)), "Kernel must expose world entity store")
	_assert_success(kernel.register_service("mass", domain.mass), "RefCounted domain service must register")
	var rejected_control := Control.new()
	_assert_error(kernel.register_service("bad-ui", rejected_control), "PRESENTATION_OBJECT_REJECTED", "Control must be rejected at kernel boundary")
	rejected_control.free()
	var rejected_camera := Camera3D.new()
	_assert_error(kernel.register_service("bad-camera", rejected_camera), "PRESENTATION_OBJECT_REJECTED", "Camera must be rejected at kernel boundary")
	rejected_camera.free()
	var rejected_viewport := SubViewport.new()
	var poisoned_kernel = SimulationKernel.new()
	_assert_error(poisoned_kernel.setup({"services": {"viewport": rejected_viewport}}), "PRESENTATION_OBJECT_REJECTED", "Viewport in setup must fail boundary")
	rejected_viewport.free()
	var nested_control := Control.new()
	_assert_error(kernel.register_service("nested-ui", {"layers": [[nested_control]]}), "PRESENTATION_OBJECT_REJECTED", "Nested presentation object must be rejected recursively")
	nested_control.free()

	var host = PresentationHost.new()
	host.name = "PresentationHostTest"
	host.setup(true)
	get_root().add_child(host)
	var panel := Control.new()
	panel.name = "Panel"
	_assert_success(host.attach_presentation(panel), "Enabled host must accept UI")
	_assert(panel.get_parent() == host, "Presentation node must be parented under host")
	_assert(int(host.create_snapshot().get("active_node_count", 0)) == 1, "Host snapshot must count active nodes")
	_assert(host.detach_all() == 1, "Host must detach registered nodes")
	_assert(panel.get_parent() == null, "Detached panel must leave host")
	panel.free()
	host.queue_free()
	var disabled_host = PresentationHost.new()
	disabled_host.setup(false)
	var disabled_panel := Control.new()
	_assert_error(disabled_host.attach_presentation(disabled_panel), "PRESENTATION_DISABLED", "Disabled host must reject UI")
	disabled_panel.free()
	disabled_host.free()

	var port = CanonicalStatePort.new()
	_assert(not (port is Node), "Canonical state port must not be a Node")
	_assert_success(port.validate_payload({"schema": "test", "values": [1, 2.5, true, "ok"]}), "JSON-safe payload must validate")
	var forbidden_node := Node.new()
	_assert_error(port.validate_payload({"node": forbidden_node}), "NON_CANONICAL_STATE_PAYLOAD", "Node must be rejected by persistence port")
	forbidden_node.free()
	var port_snapshot: Dictionary = port.create_port_snapshot("test-port")
	_assert(bool(port_snapshot.get("server_safe", false)), "Port snapshot must declare server-safe")
	_assert(not bool(port_snapshot.get("node_backed", true)), "Port must not be node-backed")
	var json_store = Factory.create_json_state_store("user://planet_simulator/kernel_port_test")
	_assert(not (json_store is Node), "JSON store must remain server-safe RefCounted")
	_assert_success(json_store.validate_payload({"value": 1}), "JSON store must inherit canonical validation")
	_assert_error(json_store.validate_payload({"callable": Callable()}), "NON_CANONICAL_STATE_PAYLOAD", "Callable must be rejected")
	_assert_error(json_store.validate_payload({"unsafe": 9007199254740992}), "NON_CANONICAL_STATE_PAYLOAD", "Unsafe JSON integer must be rejected")
	var persisted_node := Node.new()
	_assert_error(json_store.save_state("kernel-invalid", {"node": persisted_node}), "NON_CANONICAL_STATE_PAYLOAD", "State store must validate payload before file write")
	persisted_node.free()
	_assert(not json_store.has_state("kernel-invalid"), "Rejected state must not create persistence file")

	_finish()


func _assert_success(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert_error(result: Dictionary, code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)), "%s: expected failure, got %s" % [message, result])
	_assert(String(result.get("error_code", "")) == code, "%s: expected %s, got %s" % [message, code, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("Simulation kernel boundary: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Simulation kernel boundary: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
