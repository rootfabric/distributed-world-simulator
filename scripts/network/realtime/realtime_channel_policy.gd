extends RefCounted

const SCHEMA: String = "planet_simulator.realtime_channel_policy.v1"
const ENET_CHANNEL_COUNT: int = 6
const UNRELIABLE_TRANSPORT_MAPPING: String = "ENET_UNRELIABLE_ORDERED_APPLICATION_SEQUENCED_V1"
const REALTIME_COALESCING_POLICY: String = "LATEST_PENDING_TRANSACTIONAL_REPLACEMENT_PER_STREAM_V1"

const CONTROL: String = "CONTROL"
const INPUT: String = "INPUT"
const SNAPSHOT: String = "SNAPSHOT"
const ITEM: String = "ITEM"
const RESYNC: String = "RESYNC"
const TELEMETRY: String = "TELEMETRY"

# Legacy aliases stay valid for pre-NX2 transport contracts and non-production tests.
const LEGACY_COMMAND: String = "COMMAND"
const LEGACY_STATE: String = "STATE"
const LEGACY_EVENT: String = "EVENT"
const LEGACY_JOB: String = "JOB"
const LEGACY_BULK: String = "BULK"

const CANONICAL_CHANNELS: Array[String] = [CONTROL, INPUT, SNAPSHOT, ITEM, RESYNC, TELEMETRY]
const LEGACY_CHANNELS: Array[String] = [LEGACY_COMMAND, LEGACY_STATE, LEGACY_EVENT, LEGACY_JOB, LEGACY_BULK]
const ALL_CHANNELS: Array[String] = [
	CONTROL, INPUT, SNAPSHOT, ITEM, RESYNC, TELEMETRY,
	LEGACY_COMMAND, LEGACY_STATE, LEGACY_EVENT, LEGACY_JOB, LEGACY_BULK,
]

const MAPPING: Dictionary = {
	CONTROL: {"index": 0, "default_delivery": "RELIABLE_ORDERED", "priority": 0, "coalesce_latest": false},
	INPUT: {"index": 1, "default_delivery": "UNRELIABLE_SEQUENCED", "priority": 3, "coalesce_latest": true},
	SNAPSHOT: {"index": 2, "default_delivery": "UNRELIABLE_SEQUENCED", "priority": 4, "coalesce_latest": true},
	ITEM: {"index": 3, "default_delivery": "RELIABLE_ORDERED", "priority": 1, "coalesce_latest": false},
	RESYNC: {"index": 4, "default_delivery": "RELIABLE_ORDERED", "priority": 2, "coalesce_latest": false},
	TELEMETRY: {"index": 5, "default_delivery": "UNRELIABLE_SEQUENCED", "priority": 5, "coalesce_latest": true},
	LEGACY_COMMAND: {"index": 3, "default_delivery": "RELIABLE_ORDERED", "priority": 1, "coalesce_latest": false},
	LEGACY_STATE: {"index": 2, "default_delivery": "RELIABLE_ORDERED", "priority": 4, "coalesce_latest": false},
	LEGACY_EVENT: {"index": 2, "default_delivery": "RELIABLE_ORDERED", "priority": 4, "coalesce_latest": false},
	LEGACY_JOB: {"index": 4, "default_delivery": "RELIABLE_ORDERED", "priority": 2, "coalesce_latest": false},
	LEGACY_BULK: {"index": 4, "default_delivery": "RELIABLE_ORDERED", "priority": 2, "coalesce_latest": false},
}


static func is_supported(channel: String) -> bool:
	return MAPPING.has(channel)


static func channel_index(channel: String) -> int:
	return int(Dictionary(MAPPING.get(channel, {})).get("index", -1))


static func default_delivery(channel: String) -> String:
	return String(Dictionary(MAPPING.get(channel, {})).get("default_delivery", ""))


static func priority(channel: String) -> int:
	return int(Dictionary(MAPPING.get(channel, {})).get("priority", 999))


static func coalesces_latest(channel: String, delivery_mode: String) -> bool:
	return (
		delivery_mode == "UNRELIABLE_SEQUENCED"
		and bool(Dictionary(MAPPING.get(channel, {})).get("coalesce_latest", false))
	)


static func validate_delivery(channel: String, delivery_mode: String) -> Dictionary:
	if not is_supported(channel):
		return _failure("INVALID_CHANNEL")
	if channel in CANONICAL_CHANNELS and delivery_mode != default_delivery(channel):
		return _failure("CHANNEL_DELIVERY_MISMATCH", {
			"channel": channel,
			"expected": default_delivery(channel),
			"actual": delivery_mode,
		})
	return _success()


static func sequence_stream(frame: Dictionary) -> String:
	var delivery_mode: String = String(frame.get("delivery_mode", ""))
	var delivery_class: String = (
		"UNRELIABLE_SEQUENCED"
		if delivery_mode == "UNRELIABLE_SEQUENCED" else "RELIABLE"
	)
	return "%s|ENET_CHANNEL_%d" % [
		delivery_class,
		channel_index(String(frame.get("channel", ""))),
	]


static func outbound_stream_key(frame: Dictionary) -> String:
	return "%02d|%s|%s" % [
		priority(String(frame.get("channel", ""))),
		String(frame.get("channel", "")),
		String(frame.get("delivery_mode", "")),
	]


static func canonical_policy() -> Dictionary:
	var mapping: Dictionary = {}
	for channel in CANONICAL_CHANNELS:
		mapping[channel] = Dictionary(MAPPING[channel]).duplicate(true)
	var aliases: Dictionary = {}
	for channel in LEGACY_CHANNELS:
		aliases[channel] = Dictionary(MAPPING[channel]).duplicate(true)
	return {
		"schema": SCHEMA,
		"enet_channel_count": ENET_CHANNEL_COUNT,
		"canonical_channels": CANONICAL_CHANNELS.duplicate(),
		"legacy_aliases": aliases,
		"mapping": mapping,
	}


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
