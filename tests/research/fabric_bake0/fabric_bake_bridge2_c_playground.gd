extends SceneTree

const Router = preload("res://scripts/research/fabric_bake0/mixed_representation_event_router_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_bridge2_c_fixture.gd")

func _initialize() -> void:
	var subject := Fixture.build()
	if not bool(subject.get("success", false)):
		printerr("BRIDGE-2-C playground build failed: %s" % str(subject))
		quit(1)
		return
	var route_result := Fixture.canonical_route(subject)
	if not bool(route_result.get("success", false)):
		printerr("BRIDGE-2-C playground route failed: %s" % str(route_result))
		quit(1)
		return
	var route: Dictionary = route_result["details"]["route"]
	var receipt_result := Fixture.canonical_receipt(subject, route)
	if not bool(receipt_result.get("success", false)):
		printerr("BRIDGE-2-C playground receipt failed: %s" % str(receipt_result))
		quit(1)
		return
	var committed := Router.commit_route(route, receipt_result["details"]["receipt"], subject["mixed"]["subject"], subject["mixed"]["ownership"])
	if not bool(committed.get("success", false)):
		printerr("BRIDGE-2-C playground commit failed: %s" % str(committed))
		quit(1)
		return
	var commit: Dictionary = committed["details"]["commit"]
	print("BRIDGE-2-C CROSS-REPRESENTATION EVENT ROUTING")
	print("event=%s" % route["event_id"])
	print("emitter=%s evaluator=%s" % [route["emitter_representation_id"], route["evaluator_representation_id"]])
	print("commit_owner=%s" % route["commit_owner"])
	print("frontier=%s -> %s" % [commit["previous_source_frontier_hash"], commit["current_source_frontier_hash"]])
	for delivery in commit["observer_deliveries"]:
		print("observer=%s delivery=%s read_only=%s" % [delivery["representation_id"], delivery["delivery_kind"], str(not bool(delivery["canonical_write_authorized"]))])
	print("ledger_append=%s" % commit["ledger_append_event_id"])
	print("route_hash=%s" % route["route_hash"])
	print("commit_hash=%s" % commit["commit_hash"])
	print("FABRIC-BAKE BRIDGE-2-C Playground: PASS")
	quit(0)
