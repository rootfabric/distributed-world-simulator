extends SceneTree

const ProductShellScript = preload("res://scripts/ui/product_shell.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_shell_entry_contract()
	_test_preferences_contract()
	_test_host_join_arguments()
	_test_child_process_arguments()
	_test_ui_build()
	for failure in failures:
		push_error(failure)
	print("UX0 PRODUCT SHELL: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _test_shell_entry_contract() -> void:
	_check(ProductShellScript.should_open_shell(PackedStringArray()), "empty user args open Product Shell")
	_check(ProductShellScript.should_open_shell(PackedStringArray(["--product-shell"])), "explicit product-shell opens Product Shell")
	_check(
		not ProductShellScript.should_open_shell(PackedStringArray([
			"--role=game-client",
			"--network-mvp",
		])),
		"game-client runtime args bypass Product Shell"
	)
	_check(
		not ProductShellScript.should_open_shell(PackedStringArray([
			"--role=dedicated-server",
			"--network-mvp",
		])),
		"dedicated-server runtime args bypass Product Shell"
	)


func _test_preferences_contract() -> void:
	var defaults: Dictionary = ProductShellScript.default_preferences()
	_check(String(defaults.get("schema", "")) == ProductShellScript.PREFS_SCHEMA, "preferences schema is explicit")
	_check(not bool(defaults.get("has_host_history", true)), "fresh shell has no fake Continue history")
	var normalized: Dictionary = ProductShellScript.normalize_preferences({
		"default_player_name": "Yuri",
		"default_port": 24581,
		"last_server_address": "10.0.0.7",
		"last_hosted_world": "moon",
		"last_persistence_slot": "My Warehouse / A",
		"has_host_history": true,
		"last_mode": "HOST",
	})
	_check(String(normalized.get("default_player_name", "")) == "Yuri", "display player preference preserved")
	_check(int(normalized.get("default_port", 0)) == 24581, "port preference preserved")
	_check(String(normalized.get("last_server_address", "")) == "10.0.0.7", "server preference preserved")
	_check(String(normalized.get("last_hosted_world", "")) == "earth", "UX0 R1 remains on accepted Earth product world")
	_check(String(normalized.get("last_persistence_slot", "")) == "my-warehouse-a", "persistence slot normalized for instance identity")
	_check(bool(normalized.get("has_host_history", false)), "Continue history preserved")
	_check(String(normalized.get("last_mode", "")) == "host", "last mode normalized")


func _test_host_join_arguments() -> void:
	var host := ProductShellScript.build_host_user_args("earth", 24580, "warehouse-a")
	_check(host.has("--role=dedicated-server"), "Host uses dedicated-server role")
	_check(host.has("--network-mvp"), "Host uses product network MVP")
	_check(host.has("--world=earth"), "Host binds Earth product world")
	_check(host.has("--server-port=24580"), "Host preserves requested port")
	_check(host.has("--instance-id=warehouse-a"), "Host persistence slot maps to instance-id")
	_check(not _contains_prefix(host, "--persistence-root="), "Host does not invent a second persistence path")

	var joined := ProductShellScript.build_join_user_args("192.168.1.20", 24581, "Yuri G")
	_check(joined.has("--role=game-client"), "Join uses game-client role")
	_check(joined.has("--network-mvp"), "Join uses product network MVP")
	_check(joined.has("--server-address=192.168.1.20"), "Join preserves server address")
	_check(joined.has("--server-port=24581"), "Join preserves server port")
	_check(joined.has("--player-identity=yuri-g"), "Join derives bounded logical player identity")
	_check(not _contains_prefix(joined, "--persistence-root="), "client never receives persistence root")
	_check(not _contains_prefix(joined, "--instance-id="), "client does not own hosted persistence slot")


func _test_child_process_arguments() -> void:
	var user := PackedStringArray(["--role=game-client", "--network-mvp"])
	var editor := ProductShellScript.build_child_process_args(user, true, "C:/dws", false)
	_check(editor.size() == 5, "editor child args have path, separator and user args")
	_check(editor[0] == "--path" and editor[1] == "C:/dws", "editor child receives project path")
	_check(editor[2] == "--", "editor child separates engine and user args")
	_check(editor[3] == "--role=game-client" and editor[4] == "--network-mvp", "editor child preserves user args")

	var server := ProductShellScript.build_child_process_args(
		ProductShellScript.build_host_user_args("earth", 24580, "world-01"),
		false,
		"",
		true
	)
	_check(server[0] == "--headless", "dedicated child is headless")
	_check(server[1] == "--", "exported dedicated child uses user-arg separator")
	_check(server.has("--role=dedicated-server"), "exported dedicated child preserves runtime role")


func _test_ui_build() -> void:
	var shell = ProductShellScript.new()
	get_root().add_child(shell)
	shell.setup()
	var report: Dictionary = shell.get_report()
	var view_ids: Array = report.get("view_ids", [])
	for required in ["home", "host", "join", "settings"]:
		_check(view_ids.has(required), "Product Shell view exists: " + required)
	_check(shell.find_child("ProductShellRoot", true, false) != null, "Product Shell root UI constructed")
	shell.queue_free()


func _contains_prefix(values: PackedStringArray, prefix: String) -> bool:
	for value in values:
		if String(value).begins_with(prefix):
			return true
	return false


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
