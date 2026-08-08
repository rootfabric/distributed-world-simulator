class_name CharacterEquipmentDomain
extends RefCounted

const RESULT_OK := "OK"
const RESULT_INVALID_LAYOUT := "INVALID_LAYOUT"
const RESULT_INVALID_PROFILE := "INVALID_PROFILE"
const RESULT_INVALID_ITEM_ID := "INVALID_ITEM_ID"
const RESULT_INCOMPATIBLE_CHARACTER_TAG := "INCOMPATIBLE_CHARACTER_TAG"
const RESULT_FORBIDDEN_CHARACTER_TAG := "FORBIDDEN_CHARACTER_TAG"
const RESULT_MISSING_CAPABILITY := "MISSING_CAPABILITY"
const RESULT_UNSUPPORTED_ANCHOR := "UNSUPPORTED_ANCHOR"
const RESULT_UNSUPPORTED_CHANNEL := "UNSUPPORTED_CHANNEL"
const RESULT_EQUIPMENT_CHANNEL_OCCUPIED := "EQUIPMENT_CHANNEL_OCCUPIED"
const RESULT_ITEM_ALREADY_EQUIPPED := "ITEM_ALREADY_EQUIPPED"
const RESULT_ITEM_NOT_EQUIPPED := "ITEM_NOT_EQUIPPED"


class Layout:
	extends RefCounted

	var layout_id := ""
	var _character_tags: Dictionary = {}
	var _capabilities: Dictionary = {}
	var _channels: Dictionary = {}
	var _anchors: Dictionary = {}
	var _body_regions: Dictionary = {}

	func _init(
		p_layout_id: String,
		character_tags: Array = [],
		capabilities: Array = [],
		channels: Array = [],
		anchors: Array = [],
		body_regions: Array = []
	) -> void:
		layout_id = p_layout_id.strip_edges()
		_character_tags = CharacterEquipmentDomain._make_semantic_set(character_tags)
		_capabilities = CharacterEquipmentDomain._make_semantic_set(capabilities)
		_channels = CharacterEquipmentDomain._make_semantic_set(channels)
		_anchors = CharacterEquipmentDomain._make_semantic_set(anchors)
		_body_regions = CharacterEquipmentDomain._make_semantic_set(body_regions)

	func is_valid() -> bool:
		return CharacterEquipmentDomain.is_valid_semantic_id(layout_id)

	func has_character_tag(value: String) -> bool:
		return _character_tags.has(value)

	func has_capability(value: String) -> bool:
		return _capabilities.has(value)

	func supports_channel(value: String) -> bool:
		return _channels.has(value)

	func supports_anchor(value: String) -> bool:
		return _anchors.has(value)

	func supports_body_region(value: String) -> bool:
		return _body_regions.has(value)

	func character_tags() -> Array[String]:
		return CharacterEquipmentDomain._sorted_keys(_character_tags)

	func capabilities() -> Array[String]:
		return CharacterEquipmentDomain._sorted_keys(_capabilities)

	func channels() -> Array[String]:
		return CharacterEquipmentDomain._sorted_keys(_channels)

	func anchors() -> Array[String]:
		return CharacterEquipmentDomain._sorted_keys(_anchors)

	func body_regions() -> Array[String]:
		return CharacterEquipmentDomain._sorted_keys(_body_regions)


class Profile:
	extends RefCounted

	var profile_id := ""
	var presentation_id := ""
	var preferred_anchor := ""
	var _required_character_tags: Dictionary = {}
	var _forbidden_character_tags: Dictionary = {}
	var _required_capabilities: Dictionary = {}
	var _occupied_channels: Dictionary = {}

	func _init(
		p_profile_id: String,
		p_presentation_id: String,
		p_preferred_anchor: String,
		occupied_channels: Array,
		required_character_tags: Array = [],
		forbidden_character_tags: Array = [],
		required_capabilities: Array = []
	) -> void:
		profile_id = p_profile_id.strip_edges()
		presentation_id = p_presentation_id.strip_edges()
		preferred_anchor = p_preferred_anchor.strip_edges()
		_required_character_tags = CharacterEquipmentDomain._make_semantic_set(required_character_tags)
		_forbidden_character_tags = CharacterEquipmentDomain._make_semantic_set(forbidden_character_tags)
		_required_capabilities = CharacterEquipmentDomain._make_semantic_set(required_capabilities)
		_occupied_channels = CharacterEquipmentDomain._make_semantic_set(occupied_channels)

	func is_valid() -> bool:
		if not CharacterEquipmentDomain.is_valid_semantic_id(profile_id):
			return false
		if not CharacterEquipmentDomain.is_valid_semantic_id(presentation_id):
			return false
		if not CharacterEquipmentDomain.is_valid_semantic_id(preferred_anchor):
			return false
		return not _occupied_channels.is_empty()

	func required_character_tags() -> Array[String]:
		return CharacterEquipmentDomain._sorted_keys(_required_character_tags)

	func forbidden_character_tags() -> Array[String]:
		return CharacterEquipmentDomain._sorted_keys(_forbidden_character_tags)

	func required_capabilities() -> Array[String]:
		return CharacterEquipmentDomain._sorted_keys(_required_capabilities)

	func occupied_channels() -> Array[String]:
		return CharacterEquipmentDomain._sorted_keys(_occupied_channels)


class Entry:
	extends RefCounted

	var item_id := ""
	var profile_id := ""
	var presentation_id := ""
	var anchor_id := ""
	var _occupied_channels: Dictionary = {}

	func _init(
		p_item_id: String,
		p_profile_id: String,
		p_presentation_id: String,
		p_anchor_id: String,
		occupied_channels: Array
	) -> void:
		item_id = p_item_id.strip_edges()
		profile_id = p_profile_id.strip_edges()
		presentation_id = p_presentation_id.strip_edges()
		anchor_id = p_anchor_id.strip_edges()
		_occupied_channels = CharacterEquipmentDomain._make_semantic_set(occupied_channels)

	func occupied_channels() -> Array[String]:
		return CharacterEquipmentDomain._sorted_keys(_occupied_channels)

	func canonical_line() -> String:
		return "%s|%s|%s|%s|%s" % [
			item_id,
			profile_id,
			presentation_id,
			anchor_id,
			",".join(occupied_channels()),
		]


class Snapshot:
	extends RefCounted

	var owner_entity_id := ""
	var layout_id := ""
	var revision := 0
	var _entries: Array = []

	func _init(p_owner_entity_id: String, p_layout_id: String, p_revision: int, entries: Array) -> void:
		owner_entity_id = p_owner_entity_id.strip_edges()
		layout_id = p_layout_id.strip_edges()
		revision = maxi(0, p_revision)
		_entries = entries.duplicate()

	func entries() -> Array:
		return _entries.duplicate()

	func find_item(item_id: String):
		for raw_entry in _entries:
			if raw_entry is CharacterEquipmentDomain.Entry and raw_entry.item_id == item_id:
				return raw_entry
		return null

	func state_fingerprint() -> String:
		var lines: Array[String] = []
		for raw_entry in _entries:
			if raw_entry is CharacterEquipmentDomain.Entry:
				lines.append(raw_entry.canonical_line())
		lines.sort()
		return "%s|%s|%s" % [owner_entity_id, layout_id, "||".join(lines)]

	func fingerprint() -> String:
		return "%d|%s" % [revision, state_fingerprint()]


class Source:
	extends RefCounted

	func get_snapshot() -> CharacterEquipmentDomain.Snapshot:
		push_error("CharacterEquipmentDomain.Source.get_snapshot() must be implemented")
		return CharacterEquipmentDomain.Snapshot.new("", "", 0, [])


static func is_valid_semantic_id(value: String) -> bool:
	var candidate := value.strip_edges()
	if candidate.is_empty() or candidate != value:
		return false
	for index in range(candidate.length()):
		var code := candidate.unicode_at(index)
		var is_lower_alpha := code >= 97 and code <= 122
		var is_digit := code >= 48 and code <= 57
		var is_separator := code in [45, 46, 95]
		if not is_lower_alpha and not is_digit and not is_separator:
			return false
	return true


static func validate_equip(layout: Layout, profile: Profile, current_entries: Array, item_id: String) -> Dictionary:
	if layout == null or not layout.is_valid():
		return _result(false, RESULT_INVALID_LAYOUT)
	if profile == null or not profile.is_valid():
		return _result(false, RESULT_INVALID_PROFILE)
	if item_id.strip_edges().is_empty():
		return _result(false, RESULT_INVALID_ITEM_ID)

	for raw_entry in current_entries:
		if raw_entry is Entry and raw_entry.item_id == item_id:
			return _result(false, RESULT_ITEM_ALREADY_EQUIPPED, {"item_id": item_id})

	for required_tag in profile.required_character_tags():
		if not layout.has_character_tag(required_tag):
			return _result(false, RESULT_INCOMPATIBLE_CHARACTER_TAG, {"tag": required_tag})

	for forbidden_tag in profile.forbidden_character_tags():
		if layout.has_character_tag(forbidden_tag):
			return _result(false, RESULT_FORBIDDEN_CHARACTER_TAG, {"tag": forbidden_tag})

	for capability in profile.required_capabilities():
		if not layout.has_capability(capability):
			return _result(false, RESULT_MISSING_CAPABILITY, {"capability": capability})

	if not layout.supports_anchor(profile.preferred_anchor):
		return _result(false, RESULT_UNSUPPORTED_ANCHOR, {"anchor": profile.preferred_anchor})

	var occupied_by: Dictionary = {}
	for raw_entry in current_entries:
		if not raw_entry is Entry:
			continue
		for channel in raw_entry.occupied_channels():
			occupied_by[channel] = raw_entry.item_id

	for channel in profile.occupied_channels():
		if not layout.supports_channel(channel):
			return _result(false, RESULT_UNSUPPORTED_CHANNEL, {"channel": channel})
		if occupied_by.has(channel):
			return _result(false, RESULT_EQUIPMENT_CHANNEL_OCCUPIED, {
				"channel": channel,
				"occupied_by_item_id": String(occupied_by[channel]),
			})

	return _result(true, RESULT_OK)


static func create_entry(item_id: String, profile: Profile) -> Entry:
	if profile == null:
		return null
	return Entry.new(
		item_id,
		profile.profile_id,
		profile.presentation_id,
		profile.preferred_anchor,
		profile.occupied_channels()
	)


static func _make_semantic_set(values: Array) -> Dictionary:
	var result: Dictionary = {}
	for raw_value in values:
		var value := String(raw_value).strip_edges()
		if is_valid_semantic_id(value):
			result[value] = true
	return result


static func _sorted_keys(values: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key in values.keys():
		result.append(String(key))
	result.sort()
	return result


static func _result(success: bool, code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": success,
		"code": code,
		"details": details.duplicate(true),
	}
