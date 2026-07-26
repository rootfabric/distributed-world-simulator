extends SceneTree

const CommandRegistryScript = preload("res://scripts/core/command_registry.gd")

var failures: Array[String] = []


func _init() -> void:
	var registry = CommandRegistryScript.new()
	_assert(registry.register_command({
		"id": "echo",
		"description": "test",
		"usage": "echo <text>",
		"aliases": ["say"],
	}, Callable(self, "_echo"), "test"), "Command registration failed.")

	var parsed: Dictionary = registry.parse_command_line(
		"echo \"hello world\" 'second value' escaped\\ value"
	)
	var tokens = parsed.get("tokens", [])
	_assert(bool(parsed.get("success", false)), "Parser rejected valid command line.")
	_assert(tokens.size() == 4, "Parser returned wrong token count.")
	if tokens.size() == 4:
		_assert(String(tokens[1]) == "hello world", "Double-quoted token was parsed incorrectly.")
		_assert(String(tokens[2]) == "second value", "Single-quoted token was parsed incorrectly.")
		_assert(String(tokens[3]) == "escaped value", "Escaped space was parsed incorrectly.")

	var result: Dictionary = registry.execute_line("say one two")
	_assert(bool(result.get("success", false)), "Alias execution failed.")
	_assert(String(result.get("output", "")) == "one|two", "Callback arguments were corrupted.")
	var empty_argument_result: Dictionary = registry.execute_line('say "" tail')
	_assert(
		String(empty_argument_result.get("output", "")) == "|tail",
		"Empty quoted argument was lost by the parser."
	)
	_assert(registry.get_owner_command_count("test") == 1, "Owner command count is incorrect.")
	registry.clear_registration_errors()
	_assert(not registry.register_command({
		"id": "echo",
	}, Callable(self, "_echo"), "duplicate"), "Duplicate command registration unexpectedly succeeded.")
	_assert(not registry.get_registration_errors().is_empty(), "Duplicate registration was not diagnosed.")
	registry.clear_registration_errors()
	_assert(not registry.register_command({
		"id": "bad_aliases",
		"aliases": ["same", "same"],
	}, Callable(self, "_echo"), "duplicate_alias"), "Duplicate alias unexpectedly succeeded.")
	_assert(
		String(registry.get_registration_errors()[0].get("reason", "")) == "DUPLICATE_ALIAS",
		"Duplicate alias did not return the expected diagnosis."
	)
	_assert(registry.unregister_owner("test") == 1, "Owner cleanup did not remove command.")
	_assert(not registry.has_command("echo"), "Command survived owner cleanup.")

	_finish()


func _echo(arguments: Array[String]) -> Dictionary:
	return {
		"success": true,
		"output": "|".join(PackedStringArray(arguments)),
	}


func _finish() -> void:
	if failures.is_empty():
		print("Command registry tests: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Command registry tests: FAIL (%d)" % failures.size())
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
