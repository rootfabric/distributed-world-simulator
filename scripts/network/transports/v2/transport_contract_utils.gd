extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")


static func is_canonical_transport_id(value, prefix: String) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text: String = String(value)
	if text != text.strip_edges() or text != text.to_lower() or not text.begins_with(prefix + "/"):
		return false
	if text.length() < prefix.length() + 2 or text.length() > 192:
		return false
	for character in text:
		if not (character >= "a" and character <= "z") \
			and not (character >= "0" and character <= "9") \
			and character not in ["/", "-", "_", "."]:
			return false
	return not text.contains("//") and not text.ends_with("/")


static func deep_copy_json(value) -> Dictionary:
	var round_trip: Dictionary = NetworkUtilsScript.json_round_trip(value)
	if not bool(round_trip.get("success", false)):
		return failure("NON_CANONICAL_VALUE")
	return success({"value": round_trip.get("value")})


static func success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
