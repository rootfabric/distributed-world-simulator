extends RefCounted

const SCHEMA := "planet_simulator.m5_process_environment.v1"
const BASE_MCP_PORT := 9181


static func create(
	profile_root: String,
	process_role: String,
	ordinal: int,
	mcp_mode: String = "disabled"
) -> Dictionary:
	var root := profile_root.strip_edges()
	var role := process_role.strip_edges().to_lower()
	var mode := mcp_mode.strip_edges().to_lower()
	if root.is_empty() or role.is_empty() or ordinal < 0:
		return _failure("INVALID_M5_PROCESS_ENVIRONMENT")
	if mode not in ["disabled", "unique"]:
		return _failure("INVALID_MCP_MODE")
	var process_root := root.path_join("%02d-%s" % [ordinal, role])
	var data_root := process_root.path_join("data")
	var config_root := process_root.path_join("config")
	var cache_root := process_root.path_join("cache")
	var environment := {
		"HOME": process_root,
		"APPDATA": data_root,
		"LOCALAPPDATA": data_root,
		"XDG_DATA_HOME": data_root,
		"XDG_CONFIG_HOME": config_root,
		"XDG_CACHE_HOME": cache_root,
	}
	var runtime_port := 0
	if mode == "disabled":
		environment["BREAKPOINT_RUNTIME_DISABLED"] = "1"
	else:
		runtime_port = BASE_MCP_PORT + ordinal
		environment["BREAKPOINT_RUNTIME_PORT"] = str(runtime_port)
		environment["BREAKPOINT_RUNTIME_DISABLED"] = "0"
	return {
		"success": true,
		"error_code": "",
		"schema": SCHEMA,
		"process_role": role,
		"ordinal": ordinal,
		"profile_root": process_root,
		"runtime_mcp_mode": mode,
		"runtime_mcp_port": runtime_port,
		"environment": environment,
	}


static func validate_unique(configurations: Array) -> Dictionary:
	var roots: Dictionary = {}
	var ports: Dictionary = {}
	for value in configurations:
		if not value is Dictionary or not bool(value.get("success", false)):
			return _failure("INVALID_M5_PROCESS_CONFIGURATION")
		var root := String(value.get("profile_root", ""))
		if roots.has(root):
			return _failure("M5_PROFILE_ROOT_COLLISION", {"profile_root": root})
		roots[root] = true
		var port := int(value.get("runtime_mcp_port", 0))
		if port > 0:
			if ports.has(port):
				return _failure("M5_MCP_PORT_COLLISION", {"port": port})
			ports[port] = true
	return {"success": true, "error_code": "", "profile_count": roots.size(), "mcp_port_count": ports.size()}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
