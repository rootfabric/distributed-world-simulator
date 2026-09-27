extends SceneTree

const World = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp_two_client_shared_world.gd")
const Surface = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp_bootstrap_surface.gd")
const Scene = preload("res://scenes/labs/mvp/v0_mvp_two_client_shared_world.tscn")
var _assertions := 0
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _expect(value: bool, label: String) -> void:
	_assertions += 1
	if not value:
		_failures.append(label)
		push_error("MVP2_ASSERTION: " + label)


func _run() -> void:
	var root_node := Scene.instantiate()
	_expect(root_node is Node3D, "scene is a Node3D")
	_expect(root_node.get_script() == World, "real shared scene uses the reviewed composition root")
	_expect(root_node.get_child_count() == 0, "role-specific runtime is created only after launch validation")
	root_node.free()
	var options := {
		"role": "dedicated-server", "world": "moon",
		"network_build_id": World.BUILD_ID,
		"network_git_commit": "1".repeat(40),
		"network_session_token": "session-id/mvp2-focused",
		"server_port": 24580, "server_address": "127.0.0.1",
		"player_identity": "a",
	}
	_expect(bool(World.validate_options(options).get("success", false)), "explicit server launch")
	options["role"] = "game-client"
	_expect(bool(World.validate_options(options).get("success", false)), "explicit client launch")
	for mutation in [
		{"role": "offline"}, {"world": "earth"},
		{"network_mvp": true}, {"network_playground": true},
		{"network_build_id": "foreign"}, {"network_git_commit": "main"},
		{"network_git_commit": "z".repeat(40)}, {"network_session_token": ""},
		{"server_port": 0}, {"server_port": 65536},
		{"server_address": ""}, {"player_identity": ""},
	]:
		var invalid: Dictionary = options.duplicate(true)
		invalid.merge(mutation, true)
		_expect(not bool(World.validate_options(invalid).get("success", true)), "reject invalid launch: %s" % mutation)
	var first := Surface.new()
	var second := Surface.new()
	_expect(bool(first.configure(false).get("success", false)), "first immutable bootstrap")
	_expect(bool(second.configure(false).get("success", false)), "second immutable bootstrap")
	var a: Dictionary = first.contract_report()
	var b: Dictionary = second.contract_report()
	_expect(String(a.get("bootstrap_hash", "")).length() == 64, "nonempty SHA256 bootstrap identity")
	_expect(a.get("bootstrap_hash") == b.get("bootstrap_hash"), "same descriptor produces same bootstrap")
	_expect(a.get("descriptor") == b.get("descriptor"), "same canonical surface descriptor")
	_expect(not bool(a.get("canonical_state_owned", true)), "not a second canonical Matter owner")
	_expect(not bool(a.get("mutable_matter_store_retained", true)), "no retained mutable Matter store")
	_expect(not bool(a.get("network_mutation_proven", true)), "no false network-dig claim")
	_expect(int(a.get("mesh_count", -1)) == 0, "server bootstrap does not create visual meshes")
	_expect(not bool(first.configure(false).get("success", true)), "duplicate bootstrap rejected")
	first.free()
	second.free()
	if _failures.is_empty():
		print("MVP2 focused: PASS (%d assertions)" % _assertions)
		quit(0)
	else:
		print("MVP2 focused: FAIL (%d/%d)" % [_failures.size(), _assertions])
		quit(1)
