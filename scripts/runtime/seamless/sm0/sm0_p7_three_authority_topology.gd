extends RefCounted

const AUTHORITY_A := "authority/sm0/a"
const AUTHORITY_B := "authority/sm0/b"
const AUTHORITY_C := "authority/sm0/c"

const ZONE_A := "zone/earth/sm0/west"
const ZONE_B := "zone/earth/sm0/central"
const ZONE_C := "zone/earth/sm0/east"

const AUTHORITIES: Array[String] = [AUTHORITY_A, AUTHORITY_B, AUTHORITY_C]


static func zone_for_authority(authority_id: String) -> String:
	match authority_id:
		AUTHORITY_A: return ZONE_A
		AUTHORITY_B: return ZONE_B
		AUTHORITY_C: return ZONE_C
		_: return ""


static func authority_for_zone(zone_id: String) -> String:
	match zone_id:
		ZONE_A: return AUTHORITY_A
		ZONE_B: return AUTHORITY_B
		ZONE_C: return AUTHORITY_C
		_: return ""


static func neighbors(authority_id: String) -> Array[String]:
	match authority_id:
		AUTHORITY_A: return [AUTHORITY_B]
		AUTHORITY_B: return [AUTHORITY_A, AUTHORITY_C]
		AUTHORITY_C: return [AUTHORITY_B]
		_: return []


static func are_adjacent(a: String, b: String) -> bool:
	return b in neighbors(a)


static func plan_route(source_authority_id: String, destination_authority_id: String) -> Array[String]:
	if source_authority_id not in AUTHORITIES or destination_authority_id not in AUTHORITIES:
		return []
	if source_authority_id == destination_authority_id:
		return [source_authority_id]
	var queue: Array = [[source_authority_id]]
	var visited: Dictionary = {source_authority_id: true}
	while not queue.is_empty():
		var path: Array = queue.pop_front()
		var current := String(path[path.size() - 1])
		for neighbor in neighbors(current):
			if visited.has(neighbor):
				continue
			var next_path: Array = path.duplicate()
			next_path.append(neighbor)
			if neighbor == destination_authority_id:
				var typed: Array[String] = []
				for item in next_path: typed.append(String(item))
				return typed
			visited[neighbor] = true
			queue.append(next_path)
	return []


static func validate_route(route_path: Array, source_authority_id: String, destination_authority_id: String) -> Dictionary:
	if source_authority_id not in AUTHORITIES or destination_authority_id not in AUTHORITIES:
		return _failure("SM0_P7_ROUTE_ENDPOINT_INVALID")
	if route_path.is_empty():
		return _failure("SM0_P7_ROUTE_PATH_REQUIRED")
	if String(route_path[0]) != source_authority_id or String(route_path[route_path.size() - 1]) != destination_authority_id:
		return _failure("SM0_P7_ROUTE_ENDPOINT_MISMATCH")
	var seen: Dictionary = {}
	for index in range(route_path.size()):
		var authority_id := String(route_path[index])
		if authority_id not in AUTHORITIES:
			return _failure("SM0_P7_ROUTE_AUTHORITY_INVALID")
		if seen.has(authority_id):
			return _failure("SM0_P7_ROUTE_LOOP_FORBIDDEN")
		seen[authority_id] = true
		if index > 0 and not are_adjacent(String(route_path[index - 1]), authority_id):
			return _failure("SM0_P7_ROUTE_NON_ADJACENT_HOP")
	var planned := plan_route(source_authority_id, destination_authority_id)
	if route_path.size() != planned.size():
		return _failure("SM0_P7_ROUTE_NOT_CANONICAL")
	for index in range(planned.size()):
		if String(route_path[index]) != planned[index]:
			return _failure("SM0_P7_ROUTE_NOT_CANONICAL")
	return _success()


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
