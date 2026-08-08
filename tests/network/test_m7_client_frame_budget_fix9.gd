extends SceneTree

const ClientRuntime = preload("res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd")
const InventoryFix9 = preload("res://scripts/ui/inventory/inventory_network_rev6_enhancer_fix9.gd")
const RuntimeFix9 = preload("res://scripts/world/testing/playground_view_relative_runtime_fix9.gd")
const PlaygroundScene = preload("res://scenes/testing/playground.tscn")

class FakeProfile:
	extends RefCounted
	var profile_id: String = "seven_days_like"

class FakeScreen:
	extends Control
	var player_panel: Control
	var external_panel: Control
	var active_interaction_profile = FakeProfile.new()
	var external_container_id: String = ""

class FakeRuntime:
	extends Node
	var interaction_label: Label

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_client_phase_budget_report()
	_test_fix9_source_contracts()
	_test_inventory_layout_write_suppression()
	_test_playground_composition_uses_fix9()
	_finish()


func _test_client_phase_budget_report() -> void:
	var runtime = ClientRuntime.new()
	_assert(runtime != null, "FIX9 graphical client runtime instantiates")
	if runtime == null:
		return
	var report: Dictionary = runtime.get_report()
	var budget: Dictionary = Dictionary(report.get("client_frame_budget", {}))
	_assert(
		String(budget.get("policy", "")) == "PHASE_ACCOUNTING_NO_GAMEPLAY_SEMANTICS_V1",
		"FIX9 client frame budget policy missing"
	)
	_assert(float(budget.get("phase_budget_ms", 0.0)) >= 16.0, "FIX9 frame phase budget is not observable")
	_assert(float(budget.get("unattributed_max_ms", -1.0)) >= 0.0, "FIX9 unattributed process time missing")
	var phases: Dictionary = Dictionary(budget.get("phases", {}))
	for phase_name in [
		"message_dispatch",
		"snapshot_message",
		"item_message",
		"prediction_reconcile",
		"input_flush",
		"telemetry_update",
		"local_prediction",
		"process_unattributed",
	]:
		_assert(phases.has(phase_name), "FIX9 client phase missing: %s" % phase_name)
	runtime.free()


func _test_fix9_source_contracts() -> void:
	var client_source: String = FileAccess.get_file_as_string(
		"res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd"
	)
	_assert(client_source.contains("func _handle_message(payload: Dictionary) -> void"), "FIX9 message dispatch timing wrapper missing")
	_assert(client_source.contains("func _reconcile_prediction_from_snapshot(snapshot: Dictionary) -> void"), "FIX9 reconciliation timing wrapper missing")
	_assert(client_source.contains("func _flush_pending_input_batch(force_send: bool) -> bool"), "FIX9 input flush timing wrapper missing")
	_assert(client_source.contains("func advance_local_prediction(intent: Dictionary, frame_delta_seconds: float) -> Dictionary"), "FIX9 local prediction timing wrapper missing")
	_assert(client_source.contains("process_unattributed"), "FIX9 cannot attribute residual client process time")

	var world_source: String = FileAccess.get_file_as_string(
		"res://scripts/world/testing/playground_view_relative_runtime_fix9.gd"
	)
	for token in [
		"prediction_sync",
		"prediction_callback",
		"presentation_flush",
		"replica_presentation",
		"item_projection",
		"world_physics_unattributed",
	]:
		_assert(world_source.contains(token), "FIX9 world presentation phase missing: %s" % token)


func _test_inventory_layout_write_suppression() -> void:
	var runtime := FakeRuntime.new()
	var screen := FakeScreen.new()
	var player_panel := Control.new()
	var external_panel := Control.new()
	var hint := Label.new()
	player_panel.position = Vector2(40.0, 50.0)
	player_panel.size = Vector2(500.0, 300.0)
	external_panel.position = Vector2(600.0, 50.0)
	external_panel.size = Vector2(500.0, 300.0)
	screen.player_panel = player_panel
	screen.external_panel = external_panel
	runtime.interaction_label = hint
	get_root().add_child(runtime)
	runtime.add_child(screen)
	screen.add_child(player_panel)
	screen.add_child(external_panel)
	runtime.add_child(hint)

	var enhancer = InventoryFix9.new()
	runtime.add_child(enhancer)
	enhancer.screen = screen
	enhancer.player_sort_button = enhancer._create_sort_button("PlayerSortProbe", "Sort", "")
	enhancer.external_sort_button = enhancer._create_sort_button("ExternalSortProbe", "Sort", "")
	screen.add_child(enhancer.player_sort_button)
	screen.add_child(enhancer.external_sort_button)

	enhancer._layout_sort_buttons()
	enhancer._layout_interaction_hint()
	var first: Dictionary = enhancer.get_report()
	var first_sort_updates: int = int(first.get("sort_layout_updates", 0))
	var first_hint_updates: int = int(first.get("interaction_hint_layout_updates", 0))
	_assert(first_sort_updates >= 1, "FIX9 initial sort geometry is applied")
	_assert(first_hint_updates >= 1, "FIX9 initial hint geometry is applied")

	enhancer._layout_sort_buttons()
	enhancer._layout_interaction_hint()
	enhancer._update_sort_button_visibility(false, false)
	enhancer._update_sort_button_visibility(false, false)
	var second: Dictionary = enhancer.get_report()
	_assert(int(second.get("sort_layout_updates", 0)) == first_sort_updates, "FIX9 unchanged sort geometry no longer rewrites Controls")
	_assert(int(second.get("interaction_hint_layout_updates", 0)) == first_hint_updates, "FIX9 unchanged hint geometry no longer rewrites Controls")
	_assert(int(second.get("sort_layout_skips", 0)) >= 1, "FIX9 sort layout skip is observable")
	_assert(int(second.get("interaction_hint_layout_skips", 0)) >= 1, "FIX9 hint layout skip is observable")
	_assert(int(second.get("visibility_skips", 0)) >= 2, "FIX9 unchanged visibility writes are suppressed")
	_assert(String(second.get("layout_policy", "")) == "WRITE_CONTROL_GEOMETRY_ONLY_WHEN_CHANGED_V1", "FIX9 inventory layout policy missing")
	runtime.free()


func _test_playground_composition_uses_fix9() -> void:
	var instance = PlaygroundScene.instantiate()
	_assert(instance != null, "FIX9 playground scene instantiates")
	if instance != null:
		_assert(instance.get_script() == RuntimeFix9, "playground scene does not select FIX9 frame-budget composition")
		instance.free()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	for failure in failures:
		push_error(failure)
	print("M7 client frame budget FIX9: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
