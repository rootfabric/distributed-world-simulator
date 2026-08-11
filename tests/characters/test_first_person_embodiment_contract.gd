extends SceneTree

const EmbodimentType = preload("res://scripts/characters/presentation/first_person_embodiment.gd")
const AdapterType = preload("res://scripts/characters/presentation/equipment_aware_first_person_adapter.gd")
const ProfileType = preload("res://scripts/characters/presentation/controllable_presentation_profile.gd")
const GrabBridgeType = preload("res://scripts/characters/interaction/first_person_grab_authority_bridge.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var fixture := Node3D.new()
	fixture.name = "FPEContractFixture"
	root.add_child(fixture)

	var player := CharacterBody3D.new()
	player.name = "Player"
	fixture.add_child(player)

	var world_presentation := Node3D.new()
	world_presentation.name = "WorldPresentation"
	player.add_child(world_presentation)
	var world_mesh := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.4, 1.6, 0.3)
	world_mesh.mesh = body_mesh
	world_presentation.add_child(world_mesh)

	var first_camera := Camera3D.new()
	first_camera.name = "FirstCamera"
	player.add_child(first_camera)
	var third_camera := Camera3D.new()
	third_camera.name = "ThirdCamera"
	player.add_child(third_camera)

	var profile := ProfileType.new()
	profile.profile_id = &"fpe_contract"
	profile.entity_kind = &"humanoid"
	profile.first_person_policy = ProfileType.FirstPersonPolicy.HIDE_WORLD_MODEL
	profile.first_person_shadow_policy = ProfileType.FirstPersonShadowPolicy.NONE
	profile.allow_shadow_from_hidden_world_model = false

	var adapter := AdapterType.new()
	adapter.name = "EquipmentAwareFirstPersonAdapter"
	player.add_child(adapter)
	var initial_bind: Dictionary = adapter.bind_avatar(world_presentation, profile)
	_assert(bool(initial_bind.get("success", false)), "Initial accepted view adapter binding failed")
	var initial_cameras: Dictionary = adapter.bind_cameras(first_camera, third_camera)
	_assert(bool(initial_cameras.get("success", false)), "Initial camera binding failed")

	var grab_bridge := GrabBridgeType.new()
	var bridge_setup: Dictionary = grab_bridge.setup(Callable(), true)
	_assert(bool(bridge_setup.get("success", false)), "Grab bridge setup failed")

	var embodiment := EmbodimentType.new()
	embodiment.name = "FirstPersonEmbodiment"
	player.add_child(embodiment)
	var setup_result: Dictionary = embodiment.setup(
		player,
		world_presentation,
		adapter,
		profile,
		first_camera,
		third_camera,
		grab_bridge,
		null
	)
	_assert(bool(setup_result.get("success", false)), "Embodiment setup failed: %s" % JSON.stringify(setup_result))
	adapter.set_first_person_enabled(true)
	await process_frame

	var report: Dictionary = embodiment.create_report()
	_assert(String(report.get("view_policy", "")) == "VIEWMODEL", "FPE must reuse VIEWMODEL policy")
	_assert(bool(report.get("viewmodel_root_present", false)), "Viewmodel root missing")
	_assert(bool(report.get("left_hand_present", false)), "Left hand missing")
	_assert(bool(report.get("right_hand_present", false)), "Right hand missing")
	_assert(bool(report.get("world_hidden_from_first_person", false)), "World body must be hidden from first-person camera")
	_assert(bool(report.get("world_visible_to_third_person", false)), "World body must remain visible to third-person camera")
	_assert(not bool(report.get("moves_gameplay_body", true)), "Embodiment must not move gameplay body")
	_assert(not bool(report.get("owns_network_state", true)), "Embodiment must not own network state")
	_assert(not bool(report.get("owns_item_state", true)), "Embodiment must not own Item Graph state")

	var canonical_target := RigidBody3D.new()
	canonical_target.name = "CanonicalTarget"
	canonical_target.set_meta("item_id", "item/canonical/001")
	fixture.add_child(canonical_target)
	var canonical_result: Dictionary = grab_bridge.request_grab(
		"right",
		canonical_target,
		Vector3.ZERO,
		Vector3.UP
	)
	_assert(not bool(canonical_result.get("success", false)), "Canonical grab must fail closed without server contract")
	_assert(String(canonical_result.get("error_code", "")) == "FPE_CANONICAL_GRAB_AUTHORITY_UNAVAILABLE", "Canonical grab returned wrong fail-closed code")

	var sandbox_target := RigidBody3D.new()
	sandbox_target.name = "SandboxTarget"
	sandbox_target.set_meta("fpe_local_sandbox_grabbable", true)
	fixture.add_child(sandbox_target)
	var sandbox_result: Dictionary = grab_bridge.request_grab(
		"left",
		sandbox_target,
		Vector3.ZERO,
		Vector3.UP
	)
	_assert(bool(sandbox_result.get("success", false)), "Local sandbox grab classification failed")
	_assert(bool(Dictionary(sandbox_result.get("details", {})).get("local_sandbox", false)), "Sandbox grab was not explicitly classified as local-only")

	var hand_item_result: Dictionary = embodiment.set_authoritative_hand_item(
		"right",
		"replica/item/001",
		"Network Replica Item",
		Color(0.4, 0.7, 0.9, 1.0)
	)
	_assert(bool(hand_item_result.get("success", false)), "Authoritative hand presentation proxy failed")
	report = embodiment.create_report()
	_assert(String(report.get("right_authoritative_item_id", "")) == "replica/item/001", "Authoritative hand proxy did not retain replica item id")

	var no_clothing: Dictionary = embodiment.set_upper_clothing_enabled(false)
	_assert(bool(no_clothing.get("success", false)), "Disabling first-person clothing failed")
	report = embodiment.create_report()
	_assert(not bool(report.get("upper_clothing_enabled", true)), "Upper clothing viewmodel did not disable")

	var bridge_report: Dictionary = grab_bridge.create_report()
	_assert(not bool(bridge_report.get("canonical_grab_authority_ready", true)), "Test bridge unexpectedly claims canonical authority")
	_assert(bool(bridge_report.get("local_sandbox_enabled", false)), "Test bridge lost local sandbox mode")

	fixture.queue_free()
	await process_frame
	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FirstPersonEmbodiment contract: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FirstPersonEmbodiment contract: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
