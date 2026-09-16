extends "res://scripts/runtime/networked_gameplay/mvp/v0_mvp4_shared_dig_authority.gd"

# Composition only. The inherited MW4 commit and P7 delivery are the only
# writers. Receipts are reconstructed by pure reads of the existing owners;
# this class owns neither an inventory nor a replay/delivery ledger.
const Policy5 = preload("res://scripts/runtime/networked_gameplay/p7/p7_matter_material_delivery_policy.gd")
const MAX_GRAPH_ITEMS5 := 256
const MAX_MATERIAL_ITEMS5 := 32
const MAX_MATERIAL_BYTES5 := 32768

func material_snapshot(actor: String, session: String) -> Dictionary:
	var identity: Dictionary = _identity(actor, session)
	if not bool(identity.get("success", false)): return identity
	return _material_projection5()

func _material_projection5() -> Dictionary:
	if not _configured or _output == null:
		return fail("MVP5_MATERIAL_OWNER_UNAVAILABLE")
	var snapshot: Dictionary = _output.create_snapshot()
	var source_items: Array = snapshot.get("items", [])
	if source_items.size() > MAX_GRAPH_ITEMS5:
		return fail("MVP5_MATERIAL_VIEW_BUDGET")
	var items: Array = []
	var totals := {"a": 0, "b": 0}
	for raw in source_items:
		var item: Dictionary = raw
		var location: Dictionary = item.get("location", {})
		var player_id := String(location.get("player_id", ""))
		if item.get("definition_id") != Policy5.OUTPUT_DEFINITION_ID or location.get("kind") != "INVENTORY" or player_id not in ["a", "b"]:
			continue
		items.append({"item_id": item["item_id"], "definition_id": item["definition_id"], "quantity": int(item["quantity"]), "player_id": player_id, "slot_index": int(location.get("slot_index", -1))})
		totals[player_id] += int(item["quantity"])
	if items.size() > MAX_MATERIAL_ITEMS5:
		return fail("MVP5_MATERIAL_VIEW_BUDGET")
	# create_snapshot() supplies deterministically sorted item values. The
	# material digest excludes unrelated tools and advancing gameplay clocks.
	var value := {"schema": "distributed_world_simulator.mvp5_material_projection.v1", "authority_id": OWNER, "authority_epoch": EPOCH, "item_owner": "CANONICAL_ITEM_GRAPH", "canonical_state_owned": false, "scope": "SHARED_A_B_INVENTORIES_SINGLE_REGION", "items": items, "totals": totals, "material_digest": Utils.payload_hash({"items": items, "totals": totals}), "item_graph_revision": int(snapshot.get("revision", -1)), "item_graph_tick": int(snapshot.get("tick", -1)), "item_graph_checksum": String(snapshot.get("checksum", "")), "matter_stream_sequence": _matter.stream_sequence(), "matter_store_hash": _bubble.snapshot_store().content_hash()}
	if JSON.stringify(value).to_utf8_buffer().size() > MAX_MATERIAL_BYTES5:
		return fail("MVP5_MATERIAL_VIEW_BUDGET")
	return ok(value)

func execute_prepared(actor: String, session: String, plan: Dictionary) -> Dictionary:
	# Authorize reads too. The inherited execute path rechecks identity, SM1,
	# attestation, request binding and P7 authority before mutation or replay.
	var identity: Dictionary = _identity(actor, session)
	if not bool(identity.get("success", false)): return identity
	var before: Dictionary = _output.create_snapshot()
	var executed: Dictionary = super.execute_prepared(actor, session, plan)
	if not bool(executed.get("success", false)): return executed
	var details: Dictionary = Dictionary(executed["details"]).duplicate(true)
	var native: Dictionary = Codec.rehydrate_result(Codec.decode_persistence_json(String(details["matter_result_transport"])))
	var ids: Array = native.get("created_aggregate_ids", [])
	if ids.size() != 1: return fail("MVP5_CANONICAL_BATCH_CARDINALITY")
	var batch: Dictionary = _bubble.excavation_service().material_receiver().get_batch(String(ids[0]))
	var planned: Dictionary = Policy5.plan(batch)
	if not bool(planned.get("success", false)): return planned
	var receipt: Dictionary = Dictionary(planned["details"]).duplicate(true)
	if receipt.get("source_operation_id") != native.get("operation_id"):
		return fail("MVP5_CANONICAL_BATCH_BINDING")
	var after: Dictionary = _output.create_snapshot()
	var quantity := int(receipt["output_quantity"])
	receipt["logical_player_id"] = actor
	receipt["output_item_id"] = ""
	receipt["output_created_this_call"] = int(after["revision"]) != int(before["revision"])
	receipt["item_graph_replay"] = quantity > 0 and not bool(receipt["output_created_this_call"])
	receipt["matter_replay"] = bool(details.get("replay", false))
	receipt["current_item_graph_revision"] = int(after["revision"])
	receipt["current_item_graph_tick"] = int(after["tick"])
	if quantity > 0:
		var payload := {"definition_id": receipt["output_definition_id"], "quantity": quantity, "source_id": receipt["source_id"]}
		var lookup: Dictionary = _gameplay.get_canonical_item_graph_port().lookup_replay(actor, EPOCH, String(receipt["output_operation_id"]), "server.output", payload)
		var output: Dictionary = lookup.get("result", {})
		if lookup.get("found") != true or output.get("success") != true:
			return fail("MVP5_CANONICAL_OUTPUT_RECEIPT_MISSING")
		var output_details: Dictionary = output.get("details", {})
		if int(output_details.get("quantity", -1)) != quantity or output_details.get("source_id") != receipt["source_id"]:
			return fail("MVP5_CANONICAL_OUTPUT_RECEIPT_CONFLICT")
		receipt["output_item_id"] = String(output_details.get("output_item_id", ""))
		if String(receipt["output_item_id"]).is_empty(): return fail("MVP5_CANONICAL_OUTPUT_ITEM_MISSING")
		# These describe the ORIGINAL issuance, not the item's current location
		# or remaining quantity after a later legitimate inventory operation.
		receipt["issued_item_graph_revision"] = int(output.get("revision", -1))
		receipt["issued_item_graph_tick"] = int(output.get("tick", -1))
	receipt["receipt_source"] = "MW4_BATCH_AND_CANONICAL_ITEM_GRAPH_REPLAY_LOOKUP"
	receipt["receipt_store_owned"] = false
	details["material_output"] = receipt
	return ok(details)

func report() -> Dictionary:
	var value: Dictionary = super.report()
	value["material_projection"] = _material_projection5() if _configured else fail("MVP5_NOT_CONFIGURED")
	value["material_delivery_owner"] = "P7_CANONICAL_ITEM_GRAPH_OUTPUT_PORT"
	value["exactly_once_owner"] = "CANONICAL_ITEM_GRAPH_REPLAY_LEDGER"
	value["mvp5_receipt_store_owned"] = false
	return value
