extends SceneTree
const Profile = preload("res://scripts/runtime/playtest_launch_profile.gd")
const Shell = preload("res://scripts/ui/product_shell.gd")
var count := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	count += 1
	if not ok: failures.append(label)
func _init() -> void:
	var root := "/tmp/dws-test-profiles"
	var head := "0123456789012345678901234567890123456789"
	var server := Profile.prepare(Shell.build_host_user_args("earth", 24680, "safe-test"),root,head)
	var client := Profile.prepare(Shell.build_join_user_args("127.0.0.1",24680,"b"),root,head)
	check(server.get("success",false), "server config valid")
	check(client.get("success",false), "client config valid")
	check(server["profile_root"] != client["profile_root"], "profiles isolated")
	check(server["user_args"].has("--server-address=0.0.0.0"), "host accepts LAN")
	check(client["user_args"].has("--server-address=127.0.0.1"), "client address preserved")
	for value in [server,client]:
		check(value["engine_args"].has("60"), "safe 60fps")
		check(not value["engine_args"].has("120"), "120fps not enabled")
		check(value["user_args"].has("--network-git-commit="+head), "exact build identity")
		check(not value["user_args"].has("--network-playground"), "no playground")
	check(server["environment"]["DWS_NET_R3C_ASYNC_ADMISSION"] == "1", "server async admission")
	check(server["environment"]["DWS_NET_R31P23R22_ATTESTED_COMPACT"] == "1", "server compact attestation")
	check(client["environment"]["DWS_NET_R3C_ASYNC_ADMISSION"] == "0", "client never server canary")
	check(client["environment"]["DWS_NET_R3C3_STAGED_EARTH"] == "1", "staged client earth")
	check(client["environment"]["DWS_NET_R3C2_AVATAR_PREWARM"] == "1", "prewarm avatar")
	check(server["environment"]["DWS_NET_R3C3_STAGED_EARTH"] == "0", "headless never client generation")
	check(not Profile.prepare(PackedStringArray(["--role=listen-host","--world=earth"]),root,head).get("success",true), "reject developer path")
	check(not Profile.prepare(PackedStringArray(["--role=game-client","--world=playground","--network-playground"]),root,head).get("success",true), "reject old playground")
	check(not Profile.prepare(Shell.build_join_user_args("127.0.0.1",24680,"b"),root,"").get("success",true), "missing source identity rejected")
	var old := OS.get_environment("DWS_PLAYTEST_ENV_TEST")
	var had := OS.has_environment("DWS_PLAYTEST_ENV_TEST")
	var saved := Profile.apply_environment({"DWS_PLAYTEST_ENV_TEST":"temporary"})
	check(OS.get_environment("DWS_PLAYTEST_ENV_TEST") == "temporary", "child env applied")
	Profile.restore_environment(saved)
	check(OS.has_environment("DWS_PLAYTEST_ENV_TEST") == had and OS.get_environment("DWS_PLAYTEST_ENV_TEST") == old, "parent env restored")
	if failures.is_empty():
		print("PLAYTEST LAUNCH PROFILE: PASS (%d assertions, 0 failures)" % count)
		quit(0)
	else:
		for f in failures: printerr(f)
		print("PLAYTEST LAUNCH PROFILE: FAIL")
		quit(1)
