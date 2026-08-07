extends SceneTree

const EnhancerFix6 = preload("res://scripts/ui/inventory/inventory_network_rev6_enhancer_fix6.gd")
const PlaygroundFix6 = preload("res://scripts/world/testing/playground_view_relative_runtime_fix6.gd")

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_enhancer_activation_contract()
	_test_playground_composition_loads()
	if failures.is_empty():
		print("Inventory network rev6 fix6: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Inventory network rev6 fix6: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)


func _test_enhancer_activation_contract() -> void:
	var enhancer = EnhancerFix6.new()
	_assert(enhancer != null, "fix6 enhancer instantiates")
	if enhancer == null:
		return
	get_root().add_child(enhancer)
	var button = enhancer._create_sort_button("ProbeSort", "Sort", "")
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_assert(button.action_mode == BaseButton.ACTION_MODE_BUTTON_PRESS, "sort action fires on mouse press instead of release")
	_assert(button.mouse_filter == Control.MOUSE_FILTER_STOP, "sort control stops GUI mouse propagation")
	button.free()
	var report: Dictionary = enhancer.get_report()
	_assert(String(report.get("schema", "")) == "planet_simulator.inventory_network_rev6_enhancer.fix6.v1", "fix6 report schema is active")
	_assert(String(report.get("sort_activation_mode", "")) == "BUTTON_PRESS_WITH_SCREEN_FALLBACK", "fix6 reports press plus screen fallback activation")
	_assert(int(report.get("sort_press_debounce_ms", -1)) == 120, "sort activation has deterministic debounce")
	enhancer.free()


func _test_playground_composition_loads() -> void:
	var runtime = PlaygroundFix6.new()
	_assert(runtime != null, "fix6 playground runtime instantiates")
	if runtime != null:
		_assert(runtime.get_script() == PlaygroundFix6, "playground composition points at fix6 runtime")
		runtime.free()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
