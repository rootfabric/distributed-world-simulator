extends SceneTree

# Strict product launch: only dedicated network-MVP Earth seam can change
# Godot Engine.max_fps; the original default and both clients remain inert.
const Options = preload("res://scripts/runtime/launch_options.gd")
const Pacing = preload("res://scripts/network/smoothness/server_frame_pacing_policy.gd")

var checks: int = 0
var errors: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		errors.append(message)


func good(value: Dictionary) -> bool:
	return bool(value.get("success", false))


func parsed(extra: Array[String]) -> Dictionary:
	var all_args := PackedStringArray([
		"--role=dedicated-server",
		"--network-mvp",
		"--product-seam",
		"--world=earth",
	])
	for value in extra:
		all_args.append(value)
	return Options.parse(all_args)


func _run() -> void:
	var original_cap: int = Engine.max_fps
	var defaults: Dictionary = Options.parse(PackedStringArray())
	check(good(defaults), "all original launch defaults parse")
	check(int(defaults["options"].get("server_frame_cap", -1)) == 0,
		"original frame-cap option is DISABLED, no implicit 120")
	var default_applied: Dictionary = Pacing.apply(defaults.get("options", {}))
	check(good(default_applied) and not bool(default_applied["details"]["enabled"]),
		"original listen-host frame cap path untouched")
	check(Engine.max_fps == original_cap, "no writes to Engine on legacy path")

	for cap in [60, 90, 120]:
		var selected: Dictionary = parsed(["--server-frame-cap=%d" % cap])
		check(good(selected), "valid Earth dedicated cap %d parsed" % cap)
		if not good(selected):
			continue
		check(int(selected["options"]["server_frame_cap"]) == cap,
			"cap %d parsed without truncation" % cap)
		var applied: Dictionary = Pacing.apply(selected["options"])
		check(good(applied), "cap %d applied" % cap)
		check(Engine.max_fps == cap, "native Engine.max_fps set to %d" % cap)
		check(bool(applied.get("details", {}).get("enabled", false)),
			"cap opt-in is reflected in actual receipt")
		check(int(applied.get("details", {}).get("simulation_rate_hz_unchanged", -1)) == 60,
			"60Hz authoritative fixed tick explicitly immutable")
		check(int(applied.get("details", {}).get("snapshot_rate_hz_unchanged", -1)) == 20,
			"20Hz COMPACT source schedule explicitly immutable")

	Engine.max_fps = original_cap
	for bad in ["--server-frame-cap=59", "--server-frame-cap=121",
		"--server-frame-cap=144", "--server-frame-cap=0x78",
		"--server-frame-cap=-1", "--server-frame-cap=nope"]:
		var rejected: Dictionary = parsed([bad])
		check(not good(rejected), "bad server cap rejected: %s" % bad)
	check(not good(Options.parse(PackedStringArray([
		"--role=game-client","--network-mvp","--world=earth",
		"--server-frame-cap=120"]))), "client cannot claim dedicated frame cap")
	check(not good(Options.parse(PackedStringArray([
		"--role=listen-host","--server-frame-cap=120"]))),
		"listen host cannot claim dedicated frame cap")
	check(not good(Options.parse(PackedStringArray([
		"--role=simulation-server","--server-frame-cap=120"]))),
		"simulation server cannot claim product cap")
	check(not good(Options.parse(PackedStringArray([
		"--role=dedicated-server","--product-seam","--world=earth",
		"--server-frame-cap=120"]))), "server without network MVP denied")
	check(not good(Options.parse(PackedStringArray([
		"--role=dedicated-server","--network-mvp","--world=earth",
		"--server-frame-cap=120"]))), "server without PRODUCT_SEAM denied")
	check(not good(Options.parse(PackedStringArray([
		"--role=dedicated-server","--network-mvp","--product-seam",
		"--world=moon","--server-frame-cap=120"]))),
		"server cap cannot be activated in a different world")

	var invalid_policy: Dictionary = Pacing.apply({
		"server_frame_cap": 120, "role":"game-client",
		"world":"earth", "network_mvp":true, "product_seam":true})
	check(not good(invalid_policy)
		and String(invalid_policy.get("error_code","")) == "R31_SERVER_FRAME_CAP_DEDICATED_ONLY",
		"direct policy bypass fails closed on unauthorized role")
	check(Engine.max_fps == original_cap,
		"rejected options never change actual native engine FPS")
	check(checks >= 30, "complete negative and positive native matrix executed")

	Engine.max_fps = original_cap
	for msg in errors:
		push_error("NET_SMOOTH_R31_SERVER_PACING_FAIL:" + msg)
	print("NET_SMOOTH_R31_SERVER_PACING %s assertions=%d failures=%d" % [
		"PASS" if errors.is_empty() else "FAIL", checks, errors.size()])
	quit(0 if errors.is_empty() else 1)
