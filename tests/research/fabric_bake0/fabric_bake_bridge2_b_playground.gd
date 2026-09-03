extends SceneTree

const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_bridge2_b_fixture.gd")

func _initialize() -> void:
	var built := Fixture.build()
	if not bool(built.get("success", false)):
		printerr("BRIDGE-2-B playground build failed: %s" % str(built))
		quit(1)
		return
	var subject: Dictionary = built["subject"]
	print("BRIDGE-2-B EXECUTABLE MIXED SUBJECT")
	print("subject_hash=%s" % subject["subject_hash"])
	print("frontier=%s" % subject["canonical_source_frontier_hash"])
	print("authority=%s" % subject["authority_epoch_binding"])
	for entry in subject["entries"]:
		print("representation=%s kind=%s region=%s witness=%s physical=%s execution=%s" % [
			entry["representation_id"], entry["representation_kind"], entry["region_id"],
			entry["witness_kind"], entry["physical_artifact_checksum"], entry["execution_identity_hash"]
		])
	print("FABRIC-BAKE BRIDGE-2-B Playground: PASS")
	quit(0)
