extends RefCounted

# Selects only who authors realtime locomotion for the owning player.
# Entity ownership, spawn/despawn, items, economy, persistence and every durable
# gameplay mutation remain server/domain authoritative in both modes.
const SERVER_PREDICTED: String = "SERVER_PREDICTED"
const OWNER_AUTHORITATIVE_VALIDATED: String = "OWNER_AUTHORITATIVE_VALIDATED"
const SUPPORTED: Array[String] = [
	SERVER_PREDICTED,
	OWNER_AUTHORITATIVE_VALIDATED,
]


static func normalize(value: String) -> String:
	var normalized := value.strip_edges().to_upper()
	return SERVER_PREDICTED if normalized.is_empty() else normalized


static func is_supported(value: String) -> bool:
	return normalize(value) in SUPPORTED


static func is_owner_authoritative(value: String) -> bool:
	return normalize(value) == OWNER_AUTHORITATIVE_VALIDATED
