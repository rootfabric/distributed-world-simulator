extends RefCounted

# Movement authority is deliberately narrower than entity/gameplay authority.
# Ownership, spawn/despawn, inventory, items, economy and durable mutations remain
# server-authoritative in both modes. This profile only selects who authors the
# realtime locomotion transform of an owned player.
const SERVER_PREDICTED: String = "SERVER_PREDICTED"
const OWNER_AUTHORITATIVE_VALIDATED: String = "OWNER_AUTHORITATIVE_VALIDATED"
const SUPPORTED: Array[String] = [SERVER_PREDICTED, OWNER_AUTHORITATIVE_VALIDATED]


static func normalize(value: String) -> String:
	var normalized: String = value.strip_edges().to_upper()
	if normalized.is_empty():
		return SERVER_PREDICTED
	return normalized


static func is_supported(value: String) -> bool:
	return normalize(value) in SUPPORTED


static func is_owner_authoritative(value: String) -> bool:
	return normalize(value) == OWNER_AUTHORITATIVE_VALIDATED
