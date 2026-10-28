extends RefCounted

# NET-SMOOTH1 #815: version selection is bound to the already-validated
# NX0 compatibility handshake and its specific transport session.
# Frame/HELLO/ACK original schemas and their checksum validators stay intact;
# the offer/selection live in the original checksummed outer message payload.
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

const OFFER_SCHEMA: String = "planet_simulator.compact_codec_offer.v1"
const CHOICE_SCHEMA: String = "planet_simulator.compact_codec_choice.v1"
const LEGACY: String = "legacy-v1"
const F64: String = "f64-v2"
const MODES: Array[String] = ["off", "prefer_v2", "require_v2"]
const OFFER_FIELDS: Array[String] = ["schema", "handshake_id", "formats", "checksum"]
const CHOICE_FIELDS: Array[String] = ["schema", "handshake_id", "selected", "offer_checksum", "checksum"]


static func validate_mode(mode: String) -> Dictionary:
	if not MODES.has(mode):
		return _failure("COMPACT_CODEC_INVALID_MODE")
	return _success({"mode": mode})


static func create_offer(mode: String, handshake_id: String) -> Dictionary:
	if not bool(validate_mode(mode).get("success", false)) or mode == "off":
		return {}
	if not _valid_handshake(handshake_id):
		return {}
	var formats: Array = [F64]
	if mode == "prefer_v2":
		formats.append(LEGACY)
	var offer: Dictionary = {
		"schema": OFFER_SCHEMA,
		"handshake_id": handshake_id,
		"formats": formats,
		"checksum": "",
	}
	offer["checksum"] = _hash_without_checksum(offer)
	return offer


static func validate_offer(offer: Dictionary, handshake_id: String) -> Dictionary:
	if not bool(Utils.validate_exact_fields(offer, OFFER_FIELDS).get("success", false)):
		return _failure("COMPACT_CODEC_OFFER_FIELDS")
	if offer.get("schema") != OFFER_SCHEMA or not _valid_handshake(handshake_id):
		return _failure("COMPACT_CODEC_OFFER_SCHEMA")
	if String(offer.get("handshake_id", "")) != handshake_id:
		return _failure("COMPACT_CODEC_OFFER_HANDSHAKE_MISMATCH")
	if not offer.get("formats") is Array:
		return _failure("COMPACT_CODEC_OFFER_FORMATS")
	var formats: Array = offer["formats"]
	if formats.is_empty() or formats.size() > 2:
		return _failure("COMPACT_CODEC_OFFER_FORMATS")
	var unique: Dictionary = {}
	for format_value in formats:
		if typeof(format_value) != TYPE_STRING or String(format_value) not in [LEGACY, F64]:
			return _failure("COMPACT_CODEC_OFFER_FORMATS")
		if unique.has(format_value):
			return _failure("COMPACT_CODEC_OFFER_DUPLICATE")
		unique[format_value] = true
	if typeof(offer.get("checksum")) != TYPE_STRING or String(offer["checksum"]) != _hash_without_checksum(offer):
		return _failure("COMPACT_CODEC_OFFER_CHECKSUM_MISMATCH")
	return _success({"formats": formats.duplicate(), "offer_checksum": String(offer["checksum"])})


static func choose(server_mode: String, offer: Dictionary, handshake_id: String) -> Dictionary:
	var mode_check: Dictionary = validate_mode(server_mode)
	if not bool(mode_check.get("success", false)):
		return mode_check
	if not _valid_handshake(handshake_id):
		return _failure("COMPACT_CODEC_INVALID_HANDSHAKE")
	var formats: Array = [LEGACY]
	if not offer.is_empty():
		var valid: Dictionary = validate_offer(offer, handshake_id)
		if not bool(valid.get("success", false)):
			return valid
		formats = Array(valid["details"]["formats"])
	if server_mode == "require_v2" and not formats.has(F64):
		return _failure("COMPACT_CODEC_V2_REQUIRED")
	var selected: String = F64 if server_mode != "off" and formats.has(F64) else LEGACY
	if not formats.has(selected):
		return _failure("COMPACT_CODEC_NO_COMMON_FORMAT")
	return _success({
		"selected": selected,
		"offer_present": not offer.is_empty(),
		"offer_checksum": String(offer.get("checksum", "")),
	})


static func create_choice(selected: String, offer: Dictionary, handshake_id: String) -> Dictionary:
	if selected not in [F64, LEGACY] or not _valid_handshake(handshake_id):
		return {}
	var choice: Dictionary = {
		"schema": CHOICE_SCHEMA,
		"handshake_id": handshake_id,
		"selected": selected,
		"offer_checksum": String(offer.get("checksum", "")),
		"checksum": "",
	}
	choice["checksum"] = _hash_without_checksum(choice)
	return choice


static func validate_choice(choice: Dictionary, handshake_id: String) -> Dictionary:
	if not bool(Utils.validate_exact_fields(choice, CHOICE_FIELDS).get("success", false)):
		return _failure("COMPACT_CODEC_CHOICE_FIELDS")
	if choice.get("schema") != CHOICE_SCHEMA or not _valid_handshake(handshake_id):
		return _failure("COMPACT_CODEC_CHOICE_SCHEMA")
	if String(choice.get("handshake_id", "")) != handshake_id:
		return _failure("COMPACT_CODEC_CHOICE_HANDSHAKE_MISMATCH")
	if choice.get("selected") not in [LEGACY, F64]:
		return _failure("COMPACT_CODEC_CHOICE_FORMAT")
	if typeof(choice.get("offer_checksum")) != TYPE_STRING:
		return _failure("COMPACT_CODEC_CHOICE_OFFER_MISMATCH")
	if typeof(choice.get("checksum")) != TYPE_STRING or String(choice["checksum"]) != _hash_without_checksum(choice):
		return _failure("COMPACT_CODEC_CHOICE_CHECKSUM_MISMATCH")
	return _success({"selected": String(choice["selected"])})


static func client_accept(client_mode: String, offer: Dictionary, choice: Dictionary, handshake_id: String) -> Dictionary:
	var checked: Dictionary = validate_mode(client_mode)
	if not bool(checked.get("success", false)):
		return checked
	if not _valid_handshake(handshake_id):
		return _failure("COMPACT_CODEC_INVALID_HANDSHAKE")
	if not offer.is_empty():
		var verified_offer: Dictionary = validate_offer(offer, handshake_id)
		if not bool(verified_offer.get("success", false)):
			return verified_offer
	elif client_mode != "off":
		return _failure("COMPACT_CODEC_LOCAL_OFFER_MISSING")
	var selected: String = LEGACY
	if not choice.is_empty():
		var verified_choice: Dictionary = validate_choice(choice, handshake_id)
		if not bool(verified_choice.get("success", false)):
			return verified_choice
		if String(choice["offer_checksum"]) != String(offer.get("checksum", "")):
			return _failure("COMPACT_CODEC_CHOICE_OFFER_MISMATCH")
		selected = String(verified_choice["details"]["selected"])
	if selected == F64 and (client_mode == "off" or not Array(offer.get("formats", [])).has(F64)):
		return _failure("COMPACT_CODEC_UNOFFERED_V2")
	if selected == LEGACY and client_mode == "require_v2":
		return _failure("COMPACT_CODEC_DOWNGRADE_FORBIDDEN")
	if selected == LEGACY and not offer.is_empty() and not Array(offer["formats"]).has(LEGACY):
		return _failure("COMPACT_CODEC_UNOFFERED_V1")
	return _success({"selected": selected})


static func _valid_handshake(value: String) -> bool:
	if not value.begins_with("handshake/") or value.length() > 192 or value != value.to_lower():
		return false
	for c in value:
		if not ((c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c in ["/", "-", "_", "."]):
			return false
	return not value.contains("//") and not value.ends_with("/")


static func _hash_without_checksum(value: Dictionary) -> String:
	var copy: Dictionary = value.duplicate(true)
	copy.erase("checksum")
	return Utils.payload_hash(copy)


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "details": {}}
