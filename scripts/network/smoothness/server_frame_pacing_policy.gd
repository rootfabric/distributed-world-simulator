extends RefCounted

# NET-SMOOTH1 R31 P1 server-only pacing candidate.
# Alter only Godot HEADLESS engine-frame cap, never authority fixed 60Hz tick
# or 20Hz COMPACT snapshot schedule. Strict opt-in, original default untouched.
const ALLOWED_CAPS: Array[int] = [60, 90, 120]


static func validate(options: Dictionary) -> Dictionary:
	var requested = options.get("server_frame_cap", 0)
	if typeof(requested) != TYPE_INT:
		return _failure("R31_SERVER_FRAME_CAP_INVALID_TYPE")
	var cap: int = int(requested)
	if cap == 0:
		return _success({"enabled": false, "cap": 0})
	if not ALLOWED_CAPS.has(cap):
		return _failure("R31_SERVER_FRAME_CAP_UNSUPPORTED")
	if String(options.get("role", "")) != "dedicated-server":
		return _failure("R31_SERVER_FRAME_CAP_DEDICATED_ONLY")
	if not bool(options.get("network_mvp", false)):
		return _failure("R31_SERVER_FRAME_CAP_REQUIRES_MVP")
	if not bool(options.get("product_seam", false)):
		return _failure("R31_SERVER_FRAME_CAP_REQUIRES_PRODUCT_SEAM")
	if String(options.get("world", "")) != "earth":
		return _failure("R31_SERVER_FRAME_CAP_EARTH_ONLY")
	return _success({"enabled": true, "cap": cap})


static func apply(options: Dictionary) -> Dictionary:
	var check: Dictionary = validate(options)
	if not bool(check.get("success", false)):
		return check
	if not bool(check.get("details", {}).get("enabled", false)):
		# No Engine writes on original/default path.
		return _success({
			"enabled": false,
			"before": Engine.max_fps,
			"effective": Engine.max_fps,
		})
	var cap: int = int(check["details"]["cap"])
	var before: int = Engine.max_fps
	Engine.max_fps = cap
	if Engine.max_fps != cap:
		Engine.max_fps = before
		return _failure("R31_SERVER_FRAME_CAP_ENGINE_REJECTED")
	return _success({
		"enabled": true,
		"before": before,
		"effective": Engine.max_fps,
		"simulation_rate_hz_unchanged": 60,
		"snapshot_rate_hz_unchanged": 20,
	})


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "details": {}}
