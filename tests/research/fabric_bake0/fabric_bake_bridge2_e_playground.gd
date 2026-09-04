extends SceneTree

const Replay = preload("res://scripts/research/fabric_bake0/mixed_representation_replay_certificate_v1.gd")

func _initialize() -> void:
	var ia := _load("BRIDGE2_E_INVALIDATION_A")
	var ra := _load("BRIDGE2_E_RECOVERY_A")
	var result := Replay.compose(ia, ra)
	if not bool(result.get("success", false)):
		printerr("BRIDGE-2-E playground failed: %s" % str(result))
		quit(1)
		return
	var c: Dictionary = result["details"]["certificate"]
	print("BRIDGE-2-E DETERMINISTIC MIXED REPLAY PLAYGROUND")
	print("event=%s sequence=%d" % [c["event_id"], c["event_sequence"]])
	print("frontier=%s -> %s" % [c["previous_source_frontier_hash"], c["current_source_frontier_hash"]])
	print("route=%s" % c["route_hash"])
	print("commit=%s" % c["commit_hash"])
	print("stale_set=%s" % c["stale_set_hash"])
	print("split=%s" % c["split_identity_hash"])
	print("fresh_execution=%s" % c["fresh_execution_identity_hash"])
	print("final_mixed_state=%s" % c["final_mixed_state_hash"])
	print("certificate=%s" % c["certificate_hash"])
	print("FABRIC-BAKE BRIDGE-2-E Playground: PASS")
	quit(0)

func _load(env_name: String) -> Dictionary:
	var path := OS.get_environment(env_name)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
