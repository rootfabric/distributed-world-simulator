extends RefCounted

const OFFLINE: String = "offline"
const CLIENT: String = "client"
const SIMULATION_SERVER: String = "simulation-server"
const BOT_CLIENT: String = "bot-client"
const SUPPORTED: Array[String] = [
	OFFLINE,
	CLIENT,
	SIMULATION_SERVER,
	BOT_CLIENT,
]


static func normalize(value: String) -> String:
	return value.strip_edges().to_lower()


static func is_supported(value: String) -> bool:
	return SUPPORTED.has(normalize(value))


static func presentation_enabled(value: String) -> bool:
	var role: String = normalize(value)
	return role == OFFLINE or role == CLIENT


static func accepts_local_input(value: String) -> bool:
	return presentation_enabled(value)


static func is_authoritative(value: String) -> bool:
	var role: String = normalize(value)
	return role == OFFLINE or role == SIMULATION_SERVER


static func describe(value: String) -> Dictionary:
	var role: String = normalize(value)
	return {
		"role": role,
		"supported": is_supported(role),
		"presentation_enabled": presentation_enabled(role),
		"local_input_enabled": accepts_local_input(role),
		"authoritative": is_authoritative(role),
	}
