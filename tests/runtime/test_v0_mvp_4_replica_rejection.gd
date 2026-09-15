extends "res://tests/runtime/test_v0_mvp_4_shared_canonical_dig.gd"

# Runs the same real owners/replicas and additionally attacks each actual MW6
# delta before applying its untouched transport bytes. No fabricated PASS DTOs.
func drain(actor: String) -> bool:
	for _iteration in range(16):
		var polled: Dictionary = bridge.poll_replica(actor, sessions[actor])
		if not success(polled, "rejection probe poll " + actor): return false
		for envelope in polled["details"]["messages"]:
			var wire: Dictionary = JSON.parse_string(JSON.stringify(envelope))
			var before: Dictionary = replicas[actor].contract_report()
			var foreign := wire.duplicate(true)
			foreign["target_peer_id"] = "peer/mvp4/" + ("b" if actor == "a" else "a")
			check(replicas[actor].consume(foreign).get("error_code") == "MVP4_REPLICA_FOREIGN_PEER", "other peer frame rejected")
			var gap := wire.duplicate(true)
			gap["sequence"] = int(gap["sequence"]) + 1
			check(replicas[actor].consume(gap).get("error_code") == "MVP4_REPLICA_TRANSPORT_SEQUENCE_GAP", "skipped transport frame rejected")
			var tampered := wire.duplicate(true)
			tampered["payload"]["checksum"] = "0".repeat(64)
			check(not bool(replicas[actor].consume(tampered).get("success", false)), "corrupted MW6 checksum rejected")
			var after_rejected: Dictionary = replicas[actor].contract_report()
			check(after_rejected["store_hash"] == before["store_hash"] and after_rejected["geometry_hash"] == before["geometry_hash"] and after_rejected["rebuild_count"] == before["rebuild_count"], "rejected frames cannot change store or visible geometry")
			if not success(replicas[actor].consume(wire), "legitimate original MW6 frame accepted after rejections"):
				return false
			var committed: Dictionary = replicas[actor].contract_report()
			check(not bool(replicas[actor].consume(wire).get("success", false)), "duplicate transport sequence rejected")
			var after_duplicate: Dictionary = replicas[actor].contract_report()
			check(after_duplicate["geometry_hash"] == committed["geometry_hash"] and after_duplicate["store_hash"] == committed["store_hash"] and after_duplicate["rebuild_count"] == committed["rebuild_count"], "duplicate frame causes no second rebuild or mutation")
		if int(polled["details"]["remaining"]) == 0:
			return success(bridge.acknowledge_replica(actor, sessions[actor], replicas[actor].create_ack()), "rejection probe canonical ack " + actor)
	return check(false, "bounded rejection probe drain")
