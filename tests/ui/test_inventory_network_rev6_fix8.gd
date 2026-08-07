extends SceneTree

const EnhancerFix8 = preload("res://scripts/ui/inventory/inventory_network_rev6_enhancer_fix8.gd")
const RuntimeFix8 = preload("res://scripts/world/testing/playground_view_relative_runtime_fix8.gd")
const PlaygroundScene = preload("res://scenes/testing/playground.tscn")

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_global_hit_contract()
	_test_fix8_report_contract()
	_test_playground_composition_uses_fix8()
	if failures.is_empty():
		print("Inventory network rev6 fix8: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Inventory network rev6 fix8: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)


func _test_global_hit_contract() -> void:
	var enhancer = EnhancerFix8.new()
	var screen := Control.new()
	screen.size = Vector2(800.0, 600.0)
	get_root().add_child(screen)
	var player_button: Button = enhancer._create_sort_button("PlayerProbe", "Sort", "")
	var external_button: Button = enhancer._create_sort_button("ExternalProbe", "Sort", "")
	screen.add_child(player_button)
	screen.add_child(external_button)
	player_button.global_position = Vector2(100.0, 100.0)
	external_button.global_position = Vector2(300.0, 100.0)
	player_button.visible = true
	external_button.visible = true
	enhancer.screen = screen
	enhancer.player_sort_button = player_button
	enhancer.external_sort_button = external_button

	_assert(enhancer._sort_target_at_point(Vector2(110.0, 110.0)) == 0, "global fallback recognizes player sort button")
	_assert(enhancer._sort_target_at_point(Vector2(310.0, 110.0)) == 1, "global fallback recognizes external sort button")
	_assert(enhancer._sort_target_at_point(Vector2(10.0, 10.0)) == -1, "global fallback ignores unrelated inventory clicks")
	player_button.visible = false
	_assert(enhancer._sort_target_at_point(Vector2(110.0, 110.0)) == -1, "hidden sort button cannot activate fallback")

	screen.free()
	enhancer.free()


func _test_fix8_report_contract() -> void:
	var enhancer = EnhancerFix8.new()
	var report: Dictionary = enhancer.get_report()
	_assert(String(report.get("schema", "")) == "planet_simulator.inventory_network_rev6_enhancer.fix8.v1", "fix8 enhancer report schema is active")
	_assert(String(report.get("sort_activation_mode", "")) == "BUTTON_PRESS_SCREEN_FALLBACK_GLOBAL_INPUT", "fix8 reports three-layer activation policy")
	_assert(bool(report.get("sort_global_input_fallback", false)), "fix8 reports global input fallback enabled")
	enhancer.free()


func _test_playground_composition_uses_fix8() -> void:
	var instance = PlaygroundScene.instantiate()
	_assert(instance != null, "playground scene instantiates")
	if instance != null:
		_assert(instance.get_script() == RuntimeFix8, "playground scene selects fix8 sort activation composition")
		instance.free()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
