extends SceneTree

const Replay = preload("res://scripts/research/fabric_bake0/mixed_representation_replay_certificate_v1.gd")
const InvalidationFixture = preload("res://tests/research/fabric_bake0/fabric_bake_bridge2_d_fixture.gd")
const RecoveryFixture = preload("res://tests/research/fabric_bake0/fabric_bake_bridge2_d_rebind_fixture.gd")

func _initialize() -> void:
	var phase := OS.get_environment("BRIDGE2_E_PHASE").strip_edges().to_upper()
	var result: Dictionary
	match phase:
		"INVALIDATION": result = Replay.capture_invalidation(InvalidationFixture.build())
		"RECOVERY": result = Replay.capture_recovery(RecoveryFixture.build())
		_:
			printerr("FABRIC-BAKE BRIDGE-2-E CAPTURE FAILURE: unsupported phase=%s" % phase)
			quit(2)
			return
	if not bool(result.get("success", false)):
		printerr("FABRIC-BAKE BRIDGE-2-E CAPTURE FAILURE: %s" % str(result))
		quit(1)
		return
	var capsule: Dictionary = result["details"]["capsule"]
	print("BRIDGE2_E_CAPSULE_JSON=%s" % JSON.stringify(capsule))
	print("BRIDGE2_E_CAPSULE_HASH=%s" % capsule["capsule_hash"])
	print("FABRIC-BAKE BRIDGE-2-E %s Capture: PASS" % phase.capitalize())
	quit(0)
