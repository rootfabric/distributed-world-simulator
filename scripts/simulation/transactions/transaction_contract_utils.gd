extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")


static func is_identifier(value: String, prefix: String = "") -> bool:
	if value.is_empty() or value != value.strip_edges() or value.length() > 256:
		return false
	if not prefix.is_empty() and not value.begins_with(prefix):
		return false
	for character in value:
		if not String(character) in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._:/":
			return false
	return true


static func is_upper_kind(value: String) -> bool:
	if value.is_empty() or value != value.to_upper():
		return false
	for character in value:
		if not String(character) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_":
			return false
	return true


static func is_versioned_schema(value: String) -> bool:
	return is_identifier(value) and value.contains(".") and value.get_slice(".", value.get_slice_count(".") - 1).begins_with("v")


static func is_lower_hex_64(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for character in value:
		if not String(character) in "0123456789abcdef":
			return false
	return true


static func canonical_copy(value) -> Dictionary:
	var round_trip: Dictionary = UtilsScript.json_round_trip(value)
	if not bool(round_trip.get("success", false)):
		return {"success": false, "value": {}, "error_code": "NON_CANONICAL_TRANSACTION_VALUE"}
	return {"success": true, "value": round_trip.get("value"), "error_code": ""}


static func success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "message": "", "details": details.duplicate(true)}


static func failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
