extends RefCounted

const PREFIX: String = "item/"
const UUID_LENGTH: int = 36

var _crypto: Crypto = Crypto.new()


func generate(_definition_id: String = "") -> String:
	var bytes: PackedByteArray = _crypto.generate_random_bytes(16)
	if bytes.size() != 16:
		push_error("Unable to generate 16 cryptographically secure bytes for item ID")
		return ""

	# RFC 4122 UUID v4: version 4 and variant 10xx.
	bytes[6] = (int(bytes[6]) & 0x0f) | 0x40
	bytes[8] = (int(bytes[8]) & 0x3f) | 0x80

	var hex_value: String = ""
	for byte_value in bytes:
		hex_value += "%02x" % int(byte_value)

	return PREFIX + "%s-%s-%s-%s-%s" % [
		hex_value.substr(0, 8),
		hex_value.substr(8, 4),
		hex_value.substr(12, 4),
		hex_value.substr(16, 4),
		hex_value.substr(20, 12),
	]


static func is_global_id(value: String) -> bool:
	if not value.begins_with(PREFIX):
		return false
	var uuid_value: String = value.substr(PREFIX.length())
	if uuid_value.length() != UUID_LENGTH:
		return false
	var groups: PackedStringArray = uuid_value.split("-", false)
	if groups.size() != 5:
		return false
	var required_lengths: Array[int] = [8, 4, 4, 4, 12]
	for index in range(groups.size()):
		if groups[index].length() != required_lengths[index]:
			return false
		if not _is_lower_hex(groups[index]):
			return false
	if not groups[2].begins_with("4"):
		return false
	var variant_nibble: String = groups[3].substr(0, 1)
	if not ["8", "9", "a", "b"].has(variant_nibble):
		return false
	return true


static func _is_lower_hex(value: String) -> bool:
	for index in range(value.length()):
		var code: int = value.unicode_at(index)
		if not (
			(code >= 48 and code <= 57)
			or (code >= 97 and code <= 102)
		):
			return false
	return true
