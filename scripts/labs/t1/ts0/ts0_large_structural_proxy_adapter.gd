extends RefCounted

const FixtureBuilder = preload("res://scripts/labs/t1/ts0/ts0_large_structural_fixture_builder.gd")
const RuntimeRequest = preload("res://scripts/construction/runtime_projection/construction_runtime_projection_request.gd")
const CompileRequest = preload("res://scripts/construction/proxies/construction_proxy_compile_request.gd")
const Interest = preload("res://scripts/construction/proxies/construction_proxy_interest_request.gd")

const MODE_NEAR := "NEAR"
const MODE_MID := "MID"
const MODE_FAR := "FAR"
const MODES: Array[String] = [MODE_NEAR, MODE_MID, MODE_FAR]
const AUTHORITY_EPOCH := 1
const COMPILER_NODE_ID := "server/ts0/proxy-compiler"
const DEFAULT_OBSERVER_ID := "observer/ts0/graphical-lab"
const DEFAULT_CLIENT_ID := "client/ts0/graphical-lab"

static func create_compile_request(profile_id: String) -> Dictionary:
	var built: Dictionary = FixtureBuilder.build_profile(profile_id)
	if not bool(built.get("success", false)):
		return built
	var loaded: Dictionary = FixtureBuilder.load_config()
	if not bool(loaded.get("success", false)):
		return loaded
	var config: Dictionary = loaded["config"]
	var grid: Dictionary = config.get("structural_grid", {})
	var policy: Dictionary = config.get("graphical_policy", {})
	if policy.is_empty():
		return _failure("TS0_GRAPHICAL_POLICY_MISSING")
	var snapshot: Dictionary = built["snapshot"]
	var runtime: Dictionary = RuntimeRequest.create(
		snapshot,
		[],
		{},
		{},
		[0.0, 0.0, 0.0],
		[0.0, 0.0, 0.0, 1.0],
		1,
		1
	)
	var runtime_checked: Dictionary = RuntimeRequest.validate(runtime)
	if not bool(runtime_checked.get("success", false)):
		return _failure("TS0_RUNTIME_REQUEST_INVALID", runtime_checked)
	var request: Dictionary = CompileRequest.create(
		runtime,
		AUTHORITY_EPOCH,
		CompileRequest.READ_ONLY,
		COMPILER_NODE_ID,
		float(grid.get("section_size_m", 8.0)),
		float(policy.get("local_distance_m", 80.0)),
		float(policy.get("section_distance_m", 250.0)),
		float(policy.get("shell_distance_m", 1000.0)),
		[],
		[]
	)
	var checked: Dictionary = CompileRequest.validate(request)
	if not bool(checked.get("success", false)):
		return _failure("TS0_COMPILE_REQUEST_INVALID", checked)
	return _success({
		"profile_id": profile_id,
		"request": request,
		"snapshot": snapshot,
		"canonical_part_count": int(built["canonical_part_count"]),
		"canonical_revision": int(built["canonical_revision"]),
		"canonical_checksum": String(built["canonical_checksum"]),
	})

static func create_interest(manifest: Dictionary, mode: String, observer_id: String = DEFAULT_OBSERVER_ID) -> Dictionary:
	if not MODES.has(mode):
		return _failure("TS0_INVALID_GRAPHICAL_MODE")
	var loaded: Dictionary = FixtureBuilder.load_config()
	if not bool(loaded.get("success", false)):
		return loaded
	var config: Dictionary = loaded["config"]
	var policy: Dictionary = config.get("graphical_policy", {})
	if policy.is_empty():
		return _failure("TS0_GRAPHICAL_POLICY_MISSING")
	var distance_m := _distance_for_mode(manifest, mode)
	var focus_local_m := manifest_center(manifest)
	var interest: Dictionary = Interest.create(
		observer_id,
		String(manifest.get("construct_id", "")),
		int(manifest.get("authority_epoch", AUTHORITY_EPOCH)),
		distance_m,
		focus_local_m,
		"",
		[],
		int(policy.get("bandwidth_budget_bytes", 8388608)),
		int(policy.get("max_section_artifacts", 12)),
		int(policy.get("max_interactive_parts", 0))
	)
	var checked: Dictionary = Interest.validate(interest)
	if not bool(checked.get("success", false)):
		return _failure("TS0_INTEREST_REQUEST_INVALID", checked)
	return _success({
		"mode": mode,
		"expected_detail_mode": expected_detail_mode(mode),
		"interest": interest,
		"focus_local_m": focus_local_m,
		"distance_m": distance_m,
	})

static func expected_detail_mode(mode: String) -> String:
	match mode:
		MODE_NEAR:
			return "LOCAL_EXTERIOR"
		MODE_MID:
			return "SECTION_HLOD"
		MODE_FAR:
			return "DISTANT_SHELL"
	return ""

static func manifest_center(manifest: Dictionary) -> Array:
	var min_v: Array = manifest.get("bounds_min_m", [0.0, 0.0, 0.0])
	var max_v: Array = manifest.get("bounds_max_m", [0.0, 0.0, 0.0])
	if min_v.size() != 3 or max_v.size() != 3:
		return [0.0, 0.0, 0.0]
	return [
		(float(min_v[0]) + float(max_v[0])) * 0.5,
		(float(min_v[1]) + float(max_v[1])) * 0.5,
		(float(min_v[2]) + float(max_v[2])) * 0.5,
	]

static func manifest_span(manifest: Dictionary) -> float:
	var min_v: Array = manifest.get("bounds_min_m", [0.0, 0.0, 0.0])
	var max_v: Array = manifest.get("bounds_max_m", [1.0, 1.0, 1.0])
	if min_v.size() != 3 or max_v.size() != 3:
		return 1.0
	return maxf(
		maxf(float(max_v[0]) - float(min_v[0]), float(max_v[1]) - float(min_v[1])),
		float(max_v[2]) - float(min_v[2])
	)

static func client_id_from_config() -> String:
	var loaded: Dictionary = FixtureBuilder.load_config()
	if not bool(loaded.get("success", false)):
		return DEFAULT_CLIENT_ID
	return String(Dictionary(loaded["config"].get("graphical_policy", {})).get("client_id", DEFAULT_CLIENT_ID))

static func _distance_for_mode(manifest: Dictionary, mode: String) -> float:
	var local_distance := float(manifest.get("local_distance_m", 80.0))
	var section_distance := float(manifest.get("section_distance_m", 250.0))
	var shell_distance := float(manifest.get("shell_distance_m", 1000.0))
	match mode:
		MODE_NEAR:
			return maxf(0.0, local_distance * 0.5)
		MODE_MID:
			return section_distance + (shell_distance - section_distance) * 0.25
		MODE_FAR:
			return shell_distance + maxf(100.0, shell_distance * 0.25)
	return shell_distance

static func _success(extra: Dictionary = {}) -> Dictionary:
	var value := {"success": true, "error_code": "", "message": ""}
	for key in extra:
		value[key] = extra[key]
	return value

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": code,
		"message": code,
		"details": details.duplicate(true),
	}
