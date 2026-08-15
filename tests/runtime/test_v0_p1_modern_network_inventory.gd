extends SceneTree

const ModernNetworkedInventoryShell = preload(
	"res://scripts/ui/inventory/networked/m5_modern_networked_inventory_shell.gd"
)

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_run()


func _run() -> void:
	var shell = ModernNetworkedInventoryShell.new()
	shell.name = "ModernNetworkedInventoryTest"
	get_root().add_child(shell)

	var profile_result: Dictionary = shell._load_interaction_profile()
	_assert(
		bool(profile_result.get("success", false)),
		"modern network shell resolves the existing interaction profile catalog"
	)
	shell._build_ui()

	var screen = shell.inventory_window
	_assert(screen != null, "modern network shell instantiates InventoryScreen")
	_assert(
		String(screen.scene_file_path) == "res://scenes/ui/inventory/inventory_screen.tscn",
		"network shell reuses the existing modern InventoryScreen scene"
	)
	var header = screen.get_node("Margin/Main/Header")
	_assert(
		String(header.text).contains("ПРОФИЛИ УПРАВЛЕНИЯ ПРЕДМЕТАМИ"),
		"modern inventory header replaces the legacy V0 shell title"
	)
	_assert(
		not String(header.text).contains("ИНВЕНТАРЬ · V0"),
		"legacy V0 inventory title is not shipped by the modern composition"
	)
	for node_name in [
		"SearchEdit",
		"FilterOption",
		"SortOption",
		"InteractionProfileOption",
		"ResetProjectionButton",
		"Inspector",
	]:
		_assert(
			screen.get_node_or_null(NodePath("%" + String(node_name))) != null,
			"modern inventory control exists: %s" % node_name
		)
	var profile_option: OptionButton = screen.get_node("%InteractionProfileOption")
	_assert(
		profile_option.item_count >= 3,
		"network shell exposes the existing inventory interaction profiles"
	)
	_assert(
		shell.active_profile != null
		and String(shell.active_profile.profile_id) == "seven_days_like",
		"network MVP keeps the 7 Days interaction profile as its default"
	)
	_assert(
		shell.hotbar_panel != null
		and String(shell.hotbar_panel.name) == "M5NetworkedHotbar",
		"persistent network hotbar remains outside the inventory window"
	)
	_assert(
		not screen.get_node("%HotbarPanel").visible,
		"duplicate embedded hotbar is hidden"
	)
	_assert(
		not shell.world_panel.is_visible_in_tree()
		and not shell.mounts_panel.is_visible_in_tree(),
		"legacy world and mount compatibility surfaces are not product-visible"
	)
	_assert(
		shell.has_method("_on_interaction_requested")
		and shell.has_method("_submit"),
		"modern presentation inherits the existing M5 canonical command path"
	)
	var report: Dictionary = shell.get_report()
	_assert(
		String(report.get("ui_variant", "")) == "MODERN_INVENTORY_SCREEN",
		"report identifies the modern inventory composition"
	)
	_assert(
		String(report.get("canonical_mutation_boundary", ""))
		== "M5_INVENTORY_UI_BRIDGE",
		"report preserves M5InventoryUiBridge as the mutation boundary"
	)
	_assert(
		int(report.get("authority_references", -1)) == 0
		and int(report.get("domain_references", -1)) == 0,
		"modern presentation introduces no inventory authority/domain owner"
	)

	shell.free()
	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)


func _finish() -> void:
	print(
		"V0-P1 modern network inventory: %d assertions, %d failures"
		% [assertions, failures.size()]
	)
	quit(0 if failures.is_empty() else 1)
