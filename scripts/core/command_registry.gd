extends RefCounted

signal command_registered(command_id: String)
signal command_executed(command_id: String, result: Dictionary)

var _commands: Dictionary = {}
var _aliases: Dictionary = {}
var _registration_errors: Array[Dictionary] = []


func register_command(
	definition: Dictionary,
	callback: Callable,
	owner_id: String = "core"
) -> bool:
	var command_id: String = _normalize_id(String(definition.get("id", "")))
	if command_id.is_empty():
		_record_registration_error(owner_id, command_id, "EMPTY_COMMAND_ID")
		return false
	if not callback.is_valid():
		_record_registration_error(owner_id, command_id, "INVALID_CALLBACK")
		return false
	if _commands.has(command_id) or _aliases.has(command_id):
		_record_registration_error(owner_id, command_id, "COMMAND_ID_COLLISION")
		return false

	var aliases: Array[String] = []
	var raw_aliases = definition.get("aliases", [])
	if raw_aliases is Array:
		for alias_value in raw_aliases:
			var alias_id: String = _normalize_id(String(alias_value))
			if alias_id.is_empty() or alias_id == command_id:
				continue
			if aliases.has(alias_id):
				_record_registration_error(
					owner_id, command_id, "DUPLICATE_ALIAS", alias_id
				)
				return false
			if _commands.has(alias_id) or _aliases.has(alias_id):
				_record_registration_error(
					owner_id, command_id, "ALIAS_COLLISION", alias_id
				)
				return false
			aliases.append(alias_id)

	var record: Dictionary = {
		"id": command_id,
		"description": String(definition.get("description", "")),
		"usage": String(definition.get("usage", command_id)),
		"category": String(definition.get("category", "general")),
		"aliases": aliases,
		"callback": callback,
		"owner_id": owner_id,
	}
	_commands[command_id] = record
	for alias_id in aliases:
		_aliases[alias_id] = command_id
	command_registered.emit(command_id)
	return true


func unregister_owner(owner_id: String) -> int:
	var removed_ids: Array[String] = []
	for command_id_value in _commands.keys():
		var command_id: String = String(command_id_value)
		var record: Dictionary = _commands[command_id]
		if String(record.get("owner_id", "")) == owner_id:
			removed_ids.append(command_id)
	for command_id in removed_ids:
		var record: Dictionary = _commands[command_id]
		for alias_value in record.get("aliases", []):
			_aliases.erase(String(alias_value))
		_commands.erase(command_id)
	return removed_ids.size()


func clear_registration_errors() -> void:
	_registration_errors.clear()


func get_registration_errors() -> Array[Dictionary]:
	return _registration_errors.duplicate(true)


func get_owner_command_count(owner_id: String) -> int:
	var count: int = 0
	for command_id_value in _commands.keys():
		var record: Dictionary = _commands[String(command_id_value)]
		if String(record.get("owner_id", "")) == owner_id:
			count += 1
	return count


func has_command(command_id: String) -> bool:
	var normalized: String = _normalize_id(command_id)
	return _commands.has(normalized) or _aliases.has(normalized)


func execute_line(command_line: String) -> Dictionary:
	var parsed: Dictionary = parse_command_line(command_line)
	if not bool(parsed.get("success", false)):
		return parsed
	var tokens: Array[String] = parsed.get("tokens", [])
	if tokens.is_empty():
		return _failure("EMPTY_COMMAND", "Команда не указана")
	var requested_id: String = _normalize_id(tokens[0])
	var command_id: String = String(_aliases.get(requested_id, requested_id))
	if not _commands.has(command_id):
		return _failure(
			"UNKNOWN_COMMAND",
			"Неизвестная команда: %s. Используйте help." % requested_id,
			{"requested_id": requested_id}
		)
	var record: Dictionary = _commands[command_id]
	var callback: Callable = record["callback"]
	if not callback.is_valid():
		return _failure(
			"INVALID_CALLBACK",
			"Обработчик команды больше недоступен: %s" % command_id
		)
	var arguments: Array[String] = []
	for index in range(1, tokens.size()):
		arguments.append(tokens[index])
	var raw_result = callback.call(arguments)
	var result: Dictionary = _normalize_result(raw_result, command_id)
	result["command_id"] = command_id
	result["requested_id"] = requested_id
	command_executed.emit(command_id, result)
	return result


func parse_command_line(command_line: String) -> Dictionary:
	var tokens: Array[String] = []
	var current: String = ""
	var quote: String = ""
	var escaping: bool = false
	var token_started: bool = false
	var index: int = 0
	while index < command_line.length():
		var character: String = command_line.substr(index, 1)
		if escaping:
			match character:
				"n":
					current += "\n"
				"t":
					current += "\t"
				_:
					current += character
			escaping = false
			token_started = true
			index += 1
			continue
		if character == "\\":
			escaping = true
			token_started = true
			index += 1
			continue
		if not quote.is_empty():
			if character == quote:
				quote = ""
			else:
				current += character
			token_started = true
			index += 1
			continue
		if character == "\"" or character == "'":
			quote = character
			token_started = true
			index += 1
			continue
		if character == " " or character == "\t":
			if token_started:
				tokens.append(current)
				current = ""
				token_started = false
			index += 1
			continue
		current += character
		token_started = true
		index += 1
	if escaping:
		current += "\\"
		token_started = true
	if not quote.is_empty():
		return _failure(
			"UNCLOSED_QUOTE",
			"Незакрытая кавычка в командной строке"
		)
	if token_started:
		tokens.append(current)
	return {
		"success": true,
		"tokens": tokens,
	}


func list_commands(category_filter: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for command_id_value in _commands.keys():
		var command_id: String = String(command_id_value)
		var record: Dictionary = _commands[command_id]
		if (
			not category_filter.is_empty()
			and String(record.get("category", "")) != category_filter
		):
			continue
		result.append({
			"id": command_id,
			"description": record.get("description", ""),
			"usage": record.get("usage", command_id),
			"category": record.get("category", "general"),
			"aliases": record.get("aliases", []).duplicate(),
			"owner_id": record.get("owner_id", ""),
		})
	result.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var first_category: String = String(first.get("category", ""))
		var second_category: String = String(second.get("category", ""))
		if first_category == second_category:
			return String(first.get("id", "")) < String(second.get("id", ""))
		return first_category < second_category
	)
	return result


func get_command(command_id: String) -> Dictionary:
	var normalized: String = _normalize_id(command_id)
	var resolved: String = String(_aliases.get(normalized, normalized))
	if not _commands.has(resolved):
		return {}
	var record: Dictionary = _commands[resolved]
	return {
		"id": resolved,
		"description": record.get("description", ""),
		"usage": record.get("usage", resolved),
		"category": record.get("category", "general"),
		"aliases": record.get("aliases", []).duplicate(),
		"owner_id": record.get("owner_id", ""),
	}


func find_completions(prefix: String) -> Array[String]:
	var normalized: String = _normalize_id(prefix)
	var result: Array[String] = []
	for command_id_value in _commands.keys():
		var command_id: String = String(command_id_value)
		if normalized.is_empty() or command_id.begins_with(normalized):
			result.append(command_id)
	for alias_value in _aliases.keys():
		var alias_id: String = String(alias_value)
		if normalized.is_empty() or alias_id.begins_with(normalized):
			result.append(alias_id)
	result.sort()
	return result


func get_command_count() -> int:
	return _commands.size()


func _normalize_result(raw_result, command_id: String) -> Dictionary:
	if raw_result is Dictionary:
		var dictionary_result: Dictionary = raw_result.duplicate(true)
		if not dictionary_result.has("success"):
			dictionary_result["success"] = true
		if not dictionary_result.has("output"):
			dictionary_result["output"] = (
				String(dictionary_result.get("message", "OK"))
			)
		return dictionary_result
	if raw_result is bool:
		return {
			"success": raw_result,
			"output": "OK" if raw_result else "Команда завершилась с ошибкой",
		}
	if raw_result == null:
		return {
			"success": true,
			"output": "OK",
		}
	return {
		"success": true,
		"output": String(raw_result),
		"value": raw_result,
		"command_id": command_id,
	}


func _failure(code: String, message: String, data: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": code,
		"output": message,
		"message": message,
		"data": data,
	}


func _record_registration_error(
	owner_id: String,
	command_id: String,
	reason: String,
	conflicting_id: String = ""
) -> void:
	_registration_errors.append({
		"owner_id": owner_id,
		"command_id": command_id,
		"reason": reason,
		"conflicting_id": conflicting_id,
	})


func _normalize_id(value: String) -> String:
	return value.strip_edges().to_lower()
